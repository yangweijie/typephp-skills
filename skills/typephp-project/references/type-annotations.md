# Type annotations — the second attribute family

Compile-time attributes in `attributes-reference.md` generate **methods**. Type annotations declare
**types**: which container a parameter holds, and whether a class uses the fixed-layout native
object model.

They look identical at the syntax level (`#[...]`), so they are easy to confuse. The difference:
attributes expand into code; annotations are consumed by the type checker and change nothing at
runtime except adding an entry check.

All of them live in the **root namespace** — the same rule as every other built-in attribute. Inside
`namespace App;`, write `#[\StdVector(...)]` or `use \StdVector;`.

---

## Container annotations

Two groups, and the difference matters more than the syntax.

| Annotation | Backing storage | PHP type it accepts |
|---|---|---|
| `#[StdArray(T, N)]` | Box-wrapped C++ `std::array` | `box`, or omitted |
| `#[StdVector(T)]` | Box-wrapped C++ `std::vector` | `box`, or omitted |
| `#[StdMap(K, V)]` | Box-wrapped C++ `std::map` | `box`, or omitted |
| `#[StdOrderedMap(K, V)]` | Box-wrapped C++ `std::orderedMap` | `box`, or omitted |
| `#[StdList(T)]` | **plain PHP array** | `array`, or omitted |
| `#[StdDict(K, V)]` | **plain PHP array** | `array`, or omitted |

The first four give you C++ layout and zero-copy mutation. The last two only constrain key/value
types on an ordinary PHP array — you get checking, not speed.

Declaring any other PHP type alongside them is a compile error:

```
StdVector: a PHP type cannot also be declared unless it is box
```

That includes `mixed`, `?T`, and unions — you either omit the type or write `box` (for the C++
containers) / `array` (for list/dict).

### Type arguments

`T`, `K`, `V` must be compile-time type descriptors: `Type::*` constants or `ClassName::class`.
Runtime variables, string literals like `"int"`, and named arguments are rejected.

Keys are restricted:

```
std::map key only supports Type::Int or Type::String
```

Values are broadly typed (`Int`, `Float`, `Bool`, `Str`, `Array`, `Object`, `Any`, `ClassName::class`)
but **cannot hold native objects** in list/dict.

### `#[StdArray]` takes a shape

A fixed shape is part of the contract, not a hint:

```php
#[StdArray(Type::Int, [2, 3])] box $matrix     // 2×3, outer to inner
#[StdArray(Type::Int, 100)]    box $flat       // 100 is shorthand for [100]
```

Dimensions must be literal non-negative integers in a positional array — no names, no variables, no
constant expressions. Overriding a parent method must keep the exact shape: `[2, 3]` cannot become
`[3, 2]`.

`#[StdVector]` deliberately does **not** take an initial size; that belongs to the caller's
`std::vector(Type::Int, 100)`.

### What the annotation buys you

Without it, the callee has to recover the container by hand:

```php
function append_explicit($source): void {
    $values = $source->toStdVector(Type::Int);   // manual recovery
    $values[] = 42;
}
```

With it, the parameter is usable directly:

```php
function append(#[StdVector(Type::Int)] box $values): void {
    $values[] = 42;
}
```

This is a contract improvement, not a different storage model — the ABI still passes a `php::Var`
handle, and the entry check validates it. Verified end-to-end: after `append($vals)` the caller sees
`int(42)`, because the Box handle is shared, not copied.

### The entry check is real work

Each call validates the Box, the container kind, and the element type, then takes a C++ reference —
no element-by-element copy. Passing the wrong container kind, wrong key/value types, a plain PHP
array, `null`, or anything non-Box raises `TypeError` **at call time**, not compile time.

One consequence worth knowing: an annotation does **not** auto-convert. A plain PHP array passed to
a `#[StdVector]` parameter fails; you must convert at the boundary with `toStdVector(...)`.

### Overriding must preserve the contract

A subclass method that keeps a container parameter must repeat the identical annotation. Widening
the parameter to untyped or `mixed` silently drops the automatic recovery — no error, just a
dynamic parameter.

---

## `#[Native]` — the fixed-layout object model

`#[Native]` is not an optimization flag you sprinkle on classes. It selects a **different object
model**: the class compiles to a C++ object with fixed field offsets, is never registered with
ZendVM, and has no `zend_class_entry`, no dynamic property table, no Reflection metadata.

```php
#[Native]
class Point
{
    public int $x = 0;
    public int $y = 0;

    public function __construct(int $x, int $y) { $this->x = $x; $this->y = $y; }

    public function sum(): int { return $this->x + $this->y; }
}
```

Verified semantics:

| Behaviour | Result |
|---|---|
| `$p->sum()` | direct `php_*` call, no `zend_call_function` |
| pass `$p` to `function move(Point $p, ...)` and mutate | caller sees the change (`30` → `70`) |
| `$alias = $p; $alias->x = …` | **same object** — the variable is a pointer (`→ 3`) |
| property read/write | fixed-offset field access, no name lookup |

That pointer-assignment semantic is the one that surprises people: `$alias = $p` does **not** copy.
Ordinary PHP objects behave the same way, but with `#[Native]` there is no copy-on-write escape
hatch at all.

### Hard requirements

Every instance property must declare a type, and some types are excluded:

```
Native class properties must declare a type
Native class readonly properties are not supported
```

`readonly` is rejected because it depends on Zend's property-initialization state and runtime
property handlers, which the fixed-field model does not have.

### The ZendVM boundary is a wall, not a slope

Native objects have no zval representation, so the compiler **refuses** to let them cross into
dynamic PHP rather than silently boxing:

```
Native objects cannot be stored in PHP arrays
Native objects cannot be converted to mixed with std::any(); use an explicitly typed Native variable
```

The full list of blocked paths, all compile-time `FatalError`: PHP arrays, `mixed`/`object`
variables, `std::any()`, ordinary object properties, Box, `json_encode`, `serialize`,
`call_user_func`, variable method names, and dynamic property access.

### Where it also differs

| Area | Behaviour |
|---|---|
| inheritance | single inheritance only; **both** parent and child must declare `#[Native]`; cannot mix with plain classes |
| interfaces | compiler-checked contracts, but the relationship exists only at compile time — you cannot pass a native object as an interface type |
| `foreach` | requires implementing `Iterator`/`IteratorAggregate`; without it, **no public-property enumeration** (unlike plain objects) |
| `ArrayAccess` | `$bag['x']` maps to `offsetGet`/`offsetSet`, but `++`, `+=`, nested writes and `&$bag['x']` are rejected |
| property hooks | direct get/set supported, compiled to definite method calls; indirect writes and references rejected |
| destructor | tracing GC — do not rely on `__destruct()` for timely cleanup; call `close()`/`commit()` explicitly |
| magic methods | `__get`/`__set`/`__call`/`__serialize` and friends unsupported |
| comparison | `==` has no reliable semantics (compile error); use `===`/`!==`/`null` checks |

### Attributes that do compose

`#[Getter]`, `#[Setter]`, `#[Constructor]`, `#[Printer]`, `#[Arrayable]` — the ones that only need
compile-time AST — work on a `#[Native]` class, and their generated methods become native calls too.

### When to use it

Good fit: many small objects, object graphs, compute models, hot property access. Bad fit: anything
needing Reflection, dynamic properties, serialization, or interop with ordinary PHP extensions — for
those, keep a plain class. Do not treat `#[Native]` as an unconditional replacement; the docs are
explicit that the restrictions are the price of the layout guarantee.

---

## Quick decision table

| I need | Use |
|---|---|
| a function that appends to a typed vector without manual recovery | `#[StdVector(Type::Int)]` on the parameter |
| a fixed 2×3 matrix type | `#[StdArray(Type::Int, [2, 3])]` |
| a key/value table that stays a real PHP array | `#[StdDict(Type::Str, Type::Int)]` |
| maximum-speed small objects with fixed fields | `#[Native]` — and accept the ZendVM wall |
| to pass a native object into a framework | **not possible** — convert the design, not the object |

## Rejection messages you will actually see

All produced by compiling deliberately wrong inputs:

```
StdVector: a PHP type cannot also be declared unless it is box
std::map key only supports Type::Int or Type::String
Only typed lists support append writes
Native class properties must declare a type
Native class readonly properties are not supported
Native objects cannot be stored in PHP arrays
Native objects cannot be converted to mixed with std::any(); use an explicitly typed Native variable
```
