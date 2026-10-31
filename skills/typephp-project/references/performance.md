# Performance: telling "compiled" from "actually fast"

TypePHP's claim is that AOT output approaches C++ speed. That is true for code the compiler can
statically type, and false for code that falls back to boxed `php::Var` operations. Both compile,
both link, both run — and one is orders of magnitude slower.

## Before anything else: the default is `-O0`

`tpc --help` says it plainly — `Optimization level (0-3, default: 0)` — and it is easy to miss,
because most tools default to `-O2`. Measured on the same `fib(30)` source:

| Build | Time |
|---|---|
| default (no flag = `-O0`) | **19.1 ms** |
| `-O2` | **5.8 ms** |

**A 3.3× difference from a flag nobody passed.** Every performance conclusion drawn from a default
build is wrong. This also explains why "it compiles fast" feels deceptive: `-O0` is why.

Corollary: `-d` / `--debug` *sets* `-O0` and adds `-g`. Never benchmark, profile, or ship a debug
build.

## The signal: `php::Var` in the generated C++

`tpc --dry --build-dir` writes the generated `.cc`. Grep it.

Measured on two programs that differ only in one line:

```php
// typed.php
$sum = 0;                          // inferred int
$sum = $sum + $i;

// dynamic.php
$sum = std::any(0);                // explicitly erased to a boxed value
$sum = $sum + $i;
```

Generated loop bodies:

```cpp
// typed   — native integer arithmetic
sum = php::toInt(((sum) + (i)));

// dynamic — boxed, heap-allocated PHP values
sum = ((php::Var(sum)) + (php::Var(i)));
```

`php::Var` is the dynamic value wrapper. Every appearance in a hot loop is a boxed allocation and
a dynamic type dispatch. Counting occurrences across the two files: **2 vs 4** for the same
program shape, and the extra two are exactly inside the loop.

### Read the signal carefully — it over-reports

`php::Var` in a loop is a *suspect*, not a verdict. Scalar `int`/`float`/`bool`/`null` are stored
inline in a zval without refcount traffic, so the cost of a boxed int is the type-tag branch and
lost inlining — real, but not an allocation. A boxed **string/array/object** is where
refcounting and heap traffic actually appear.

So rank by what the value holds, and trace it to its source rather than pattern-matching the
variable. The sources that cause it are listed in `type-system.md` (array elements, `global`,
`mixed`/untyped signatures, untyped properties, `std::any()`, `varint_types`).

The stronger, cheaper signal is separate: **a method call whose receiver comes from an array
element, a `global`, or a temporary expression is always dynamic.** The compiler docs state this
directly (`(new Foo())->bar();` and `global $foo; $foo->bar();` cannot become native calls). That
is a structural fact, not a heuristic.

Containers show the difference starkly. `std::vector(Type::Int)` lowers to real C++ iteration:

```cpp
for (auto tmp_var_0 = items_ref.begin(); tmp_var_0 != items_ref.end(); ++tmp_var_0) {
    v = *tmp_var_0;
    total = php::toInt(((total) + (v)));
}
```

No `php::Var`, no boxing — native code.

## Where to look up the actual cost

`tpc --dry` shows the shape; it does not show the speed. Two ways to get numbers:

| Approach | Command | Constraint |
|---|---|---|
| gperftools | `tpc app.php --profile -O2` then `./tpc app.prof` | **Linux only**; must exit normally (crash writes no `.prof`); 100 Hz default |
| perf | `perf record -g -F 99 ./app` | Linux; no rebuild needed, good for CI |

`--profile` requires `-O2` — pairing it with `--debug` (which forces `-O0`) produces meaningless
data. On macOS/Windows there is no built-in profiler; use `microtime(true)` at the PHP level.

## Workflow

```bash
tpc --dry src/hot.php --build-dir /tmp/inspect
grep -c 'php::Var' /tmp/inspect/hot.cc          # count
grep -n  'php::Var' /tmp/inspect/hot.cc         # locate, then look at the enclosing function
```

Three readings:

| `php::Var` density | Meaning |
|---|---|
| 0 in the function of interest | fully static — this is the fast path |
| a few, outside loops (params, returns) | normal, ignore |
| recurring **inside** a loop body | the loop is boxed; this is where the time goes |

Then fix the specific line, not the file. The usual causes, in order of frequency:

1. a variable that was widened with `std::any()` for convenience
2. a value coming from a dynamic context (mixed array element, `json_decode` result) used in a
   numeric loop
3. a PHP `array` used where a typed `std::vector` / `std::orderedMap` would do
4. `use varint_types` — the trap, see below

### The `varint_types` trap

`use varint_types` looks like an "integers are integers" switch. For performance it is the
opposite: the compiler docs state that with this mode **inferred `int` locals map to `php::Var`**,
while `float` and `bool` are unaffected (`docs/zh-cn/VARINT_TYPES.md`). It exists to give
PHP-compatible overflow and division semantics, at the cost of boxing every inferred integer in
that file.

| You want | Use |
|---|---|
| maximum speed | default, no `use varint_types`; integers stay `php::Int` |
| PHP-compatible overflow / division | `use varint_types`, accepting boxed integer paths in that file |

It is file-scoped, part of the preprocessing cache key, resets per file and does not leak into
callees. It also skips generic SSA local narrowing and property narrowing in that file, so the
cost is broader than storage alone. Never add it "to be safe" — in a hot file it silently undoes
the optimisation you were trying to get. For a single value that needs PHP division semantics, use
`std::any($x)` on that one value instead of downgrading the whole file.

## Why this is the compiler's own #1 priority, not a workaround

The project's optimisation notes (`docs/zh-cn/aot-optimization-priority.md`) rank
"type inference → emit concrete C++ types instead of `php::Var`" as the **single largest gain**,
because GCC/Clang cannot optimise `php::add(a, b)` well: the call hides that it is addition, and
`php::Var` forces heap layout, reference counting and blocked register allocation. That is exactly
the signal you read when grepping generated code — you are looking at the compiler's own known
bottleneck.

The same document notes full SSA is not required; per-assignment-point inference suffices. So the
fast path is reachable from ordinary typed PHP, and boxing you find is usually something you
introduced (an erasure, a dynamic source, or `varint_types`) rather than an inherent limit.

## Cost: this check is nearly free

`--dry` costs ~200–500 ms and no C++ compilation. You can afford to run it on every hot path
before building, and compare two variants in a second. That makes "is this fast" a static
question for most cases, which is unusual and worth exploiting.

## What this does NOT tell you

The generated-C++ heuristic is structural, not measured. It says "this code will not be boxed",
not "this code is 8× faster". Three things it cannot answer:

- **constant factors** — allocation strategy, cache behaviour, whether the optimizer did anything
- **whether the boxing matters for your workload** — a boxed loop over 10 items is free
- **total program time** — I/O and startup often dominate short CLI runs

For those you need the real comparison: build both variants, run each with a timer on a
representative input, and compare. The project's own benchmark methodology
(`benchmark/` in the compiler repo) is the reference for how to do it fairly.

State which kind of evidence you have. "The hot loop generated native `php::toInt` arithmetic"
is a structural claim you verified; "this is 8× faster" is a measurement you have not made.

## Idioms that keep code on the fast path

| Instead of | Write | Why |
|---|---|---|
| `(new Foo())->bar()` in a hot path | `$foo = new Foo(); $foo->bar();` | a temporary gives the compiler no receiver type → dynamic call |
| `global $cfg; $cfg->load();` | pass it as a typed parameter | `global` slots are `php::Var` → dynamic call |
| `$fn = 'str_repeat'; $fn(...)` | `str_repeat(...)` | variable function names cannot become known calls |
| `$v = $arr['k']; $sum += $v;` | `$sum += (int) $arr['k'];` | array elements are zvals |
| `function f(mixed $x)` on a hot path | `function f(int $x)` | `mixed` erases |
| `public $count;` | `public int $count;` | typed property gets a fixed slot and offset access |
| `std::any($a)` inside a loop | `$a = 0;` in the loop, erase once at the boundary | per-iteration erasure |
| `std::any($x)` "just in case" | let inference type it | one erasure boxes every use downstream |
| `readonly` / property hooks on hot fields | `private` + `#[Getter]`, read the backing field internally | hooks are runtime features; docs describe order-of-magnitude cost in dense access |
| `$arr = []` for numeric sequences | `std::vector(Type::Int)` | native storage, no hash lookup |
| `$map = []` for fixed-shape key→value | `std::orderedMap` / `std::map` | typed, contiguous |
| `$arr['obj']->foo()` | `$arr['obj']->toObject(Foo::class)->foo()` | restores class info for a native call |
| loose dynamic calls | static calls with declared param types | dynamic dispatch cannot be inlined |

Note the `toObject` row's cost: it is a runtime `instanceof`. Do it once at the boundary, not per
iteration — otherwise the fix becomes the new bottleneck.

The general principle from `typephp-idioms.md` applies in reverse here: do not *preemptively*
avoid ordinary PHP for correctness reasons, but once you have identified a genuine hot loop, the
difference between boxed and static is the difference between AOT and an interpreter.

## A realistic reading order

1. Find the hot path by measurement (profiler, or just knowing your program).
2. `--dry` that one file, grep `php::Var` inside its loops.
3. If boxed, fix the specific widening; re-grep to confirm the fix.
4. Build and time it only if the change matters to a real workload.

Skipping step 1 is the common mistake: optimizing a file that runs once at startup.
