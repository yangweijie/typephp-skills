# Compile-time attribute reference

TypePHP reads these attributes **at compile time** and expands them into ordinary methods. No
reflection, no runtime metadata, no dynamic dispatch. Generated methods are indistinguishable from
hand-written ones.

## Rules that apply to every attribute on this page

1. **Root namespace.** Inside `namespace App;`, `#[Getter]` resolves to `App\Getter` and is
   **silently ignored** — no error, no method generated. Write `#[\Getter]` or `use \Getter;`.
2. **Silently ignored is the default failure mode**, not a compile error. If a generated method is
   "missing", check the namespace first.
3. **Duplicates and conflicts are compile errors**, and the diagnostic names both sides:
   `Duplicate method __toString [compile-time attribute: #[Printer]; target: class User; ...;
   conflict source: declaration at all.php:23]`.
4. **Wrong target is a compile error with the exact location**:
   `Getter can only be applied to instance properties [compile-time attribute: #[Getter];
   target: method __toString(); source: all.php:23]`.

All examples below were compiled and run on tpc v0.9.5 unless noted.

---

## The generated-method family (property level)

These four read or write a property. They compose on one property and each requires the property
to be a non-static instance property.

| Attribute | Generates | Notes |
|---|---|---|
| `#[Getter]` | `public function getName(): T` | works on `private`/`protected`/`public`, and on `readonly` |
| `#[Setter]` | `public function setName(T $v): void` | **not** on `readonly`, readonly-class, or hooked properties |
| `#[With]` | `public function withName(T $v): static` | `clone` + assign; same exclusions as `Setter` |
| `#[Constructor]` | `public function __construct(T $id, ...)` | see below |

Naming: `$name → getName`, `$userId → getUserId`, `$_value → get_value`.

Compose freely:

```php
final class User
{
    #[Constructor, Getter]
    private int $id;

    #[Constructor, Getter, Setter, With]
    private string $name = '';
}
```

Verified: `new User(7, 'rango')`, `getId()`, `getName()`, `setName()`, and
`$u->withName('finch')->getName() === 'finch'` all work.

### `#[Constructor]`

Goes on **properties**, not the class. The constructor is assembled from annotated properties in
declaration order, copying their types and defaults.

| Rule | Consequence |
|---|---|
| required property must not follow one with a default | compile error |
| class already declares `__construct()` | compile error — never merges |
| parent constructor has **required** args | compile error; write the constructor by hand |
| parent constructor exists with no required args | `parent::__construct()` inserted automatically |
| parent constructor is `private` | not called; your constructor is still generated |
| static properties, traits, enums | not supported |

It does **not** map parent constructor arguments — that is deliberate, to avoid implicit parameter
passing hidden inside property annotations.

### `#[With]`

Returns `static`, so it works correctly through inheritance. The clone follows normal
`clone`/`__clone()` semantics, so `__clone()` side effects run.

---

## The class-level family

### `#[Printer(fields: [...])]`

Generates `public function __toString(): string`. Default output: the short class name plus every
non-static **public** property of the class and its bases, in base-to-derived order.

```php
#[Printer(fields: ['name', 'id'])]
final class User { /* private $id, protected $name, public $email */ }

echo new User(...);   // User(name=..., id=...)
```

Verified output: `User(name=rango, id=7)`. `fields:` (or the positional form `#[Printer([...])]`)
selects and orders exactly those properties, and may reference `protected`/`private` ones.

`echo $obj` and `$obj->toString()` both land here — the compiler does not generate a second
`toString()` wrapper. Declaring your own `__toString()` alongside `#[Printer]` **collides**:
`Duplicate method __toString`.

### `#[Arrayable(fields: [...])]`

Generates `public function toArray(): array`, defaulting to all non-static public properties keyed
by name. Verified: `['id' => 7, 'name' => 'rango']`.

This interoperates with the keyword method `toArray()`: the built-in conversion helper detects a
zero-argument `toArray()` and calls it, asserting an array comes back. So a generated `toArray()`
works in both worlds — and a user `toArray(int $x)` would be a trap (keyword methods win).

---

## Extension methods — `#[MethodsFor(...)]`

Attaches methods to a type you do not own. The provider class contains `public static` methods; the
**first parameter is the receiver** and is supplied automatically.

```php
#[MethodsFor(\Type::String)]
final class StringExtensions
{
    public static function surround(string $value, string $left = '[', string $right = ']'): string
    {
        return $left . $value . $right;
    }
}

echo 'TypePHP'->surround('<', '>');   // <TypePHP>
```

Verified working. Call arguments map from the **second** parameter onward.

| Target | Receiver type | Meaning |
|---|---|---|
| `Type::Int` / `Float` / `Bool` / `String` / `Array` | `int` / `float` / `bool` / `string` / `array` | base types |
| `Type::Object` | `object` | generic `object`-typed values |
| `Type::Any` | `any` | **only** receivers statically typed `any` |
| `Type::Stream` / `Box` / `BigInt` / `BigFloat` / `Decimal` | `stream` / `box` / … | special values |
| `'*'` | `any` | **the** wildcard: matches every receiver |
| `SomeClass::class` | `SomeClass` | object extension |

`Type::Any` is **not** a wildcard — that is the most common misreading. Use `'*'`.

### Provider method rules

- must be `public static`, at least one parameter, receiver not by reference;
- `private`/`protected` members are not registered (usable as internal helpers);
- methods starting with `__` are not registered;
- a `public` **non-static** method is a compile error, not a silent skip;
- names register **verbatim** — `displayName` and `display_name` are different methods; lookup is
  case-insensitive (`DISPLAYNAME()` still hits `displayName`);
- return types feed static inference, so declare them precisely to keep chains static;
- keyword extensions cannot shadow built-in keyword methods (`toInt`, `toString`, `toArray`,
  `toAny`, `toRef`);
- `'*'` methods and per-type providers must not reuse the same method name — that is a conflict
  error, not last-one-wins.

Provider for an interface is a compile error (`MethodsFor(SomeInterface::class)`).
Extension methods cannot override a real instance method, but they take precedence over `__call()`.

### Conflict detection is lazy — measured

Duplicating a method name across two providers does **not** fail at declaration. It fails the first
time the method is *called*:

| Program | Result |
|---|---|
| two providers both define `dup()`, `main()` never calls it | **compiles clean** |
| same, but `main()` calls `'x'->dup()` | `Fatal error: Duplicate extension method php::Str::dup()` |

That is a real trap for test suites and CI: a duplicate can sit in the codebase indefinitely and
only surface when a new call site appears. Grep for provider method names rather than trusting a
green build.

Wildcard clashes are caught the same way, with a message naming both sides:

```
Extension method php::Int::dup() conflicts with keyword extension method *::dup()
```

### Built-in keyword methods win, silently

Defining a provider method named `toInt` on `Type::String` compiles and links without a word — but
the built-in wins:

```php
#[MethodsFor(\Type::String)]
final class P { public static function toInt(string $v): int { return 999; } }

$s = "42";
echo $s->toInt();    // 42, not 999
```

No warning, no error, no shadowing. If a provider method seems to be "not being called", check
whether the name collides with a keyword method (`toInt`, `toFloat`, `toBool`, `toString`,
`toArray`, `toAny`, `toRef`, `toObject`, `toStd*`).

---

## Parameter contracts

These insert a check at function entry. All three work on functions, methods, closures, and
promoted constructor parameters — but **not arrow functions** (no body to insert into).

| Attribute | Inserts | Fails on |
|---|---|---|
| `#[NotNull]` | `if ($p === null) throw new \ValueError(...)` | only strict `null` |
| `#[NotEmpty]` | `if (empty($p)) throw new \ValueError(...)` | `null`, `false`, `0`, `0.0`, `''`, `'0'`, `[]` |
| `#[Validate(FILTER_VALIDATE_*, options, message)]` | `filter_var($p, …, FILTER_NULL_ON_FAILURE)` checked `=== null` | per filter |

Fixed order regardless of how you write them: **`NotNull` → `NotEmpty` → `Validate`**.

### Measured behaviour

Built and run, not inferred. Each line is an actual program output:

```
NotEmpty(empty string): Parameter $name must not be empty     # '' rejected
NotEmpty(string zero):  Parameter $name must not be empty     # '0' rejected — empty('0') is true
ok:rango                                                      # normal value passes
NotNull(null):          Parameter $id must not be null        # null rejected
NotNull(0) -> 0                                               # 0 is NOT null, passes
Validate(bad):          Parameter $email is invalid
mail:a@b.com                                                  # valid email passes all three
```

And on an `int` parameter:

```
int 0 -> Parameter $n must not be empty
ok:5
```

That last pair is the one to remember: **`#[NotEmpty]` follows PHP `empty()` semantics, so a
legitimate `0` or `0.0` or `false` is rejected.** For a numeric parameter where zero is valid, use
`#[NotNull]` (or a `#[Validate]` range) instead — this is the most likely way to break a working
function by adding a "harmless" annotation.

Everything throws `\ValueError`, so a call site that does not catch it will surface as an uncaught
`ValueError` at the boundary — which for a compiled CLI means a fatal at run time, not a compile
error. The checks are runtime work even though the *insertion* is compile-time.

### Arrow functions are rejected

```
Fatal error: Syntax error in e2.php: NotEmpty is not supported on arrow function parameters
[compile-time attribute: #[NotEmpty]; target: parameter $n; source: e2.php:6]
```

Closures (`function (...) use (...)`) are fine — they have a body. Arrow functions
(`fn(...) => expr`) do not, so there is nowhere to insert the check.

### `#[NotNull]` on a nullable parameter

Contradictory by construction (`?string` says null is allowed, `#[NotNull]` rejects it). The
compiler emits a **non-fatal warning** and continues:

```
NotNull is applied to nullable parameter `$s` in w1.php:3
```

Note that it prints as a bare line during `prepare`, not the word "Warning" — grepping for
`Warning` will miss it. Read it as a type bug: the parameter should probably be `string`.

### `#[Validate]` specifics

```php
function register(
    #[Validate(FILTER_VALIDATE_EMAIL)]
    string $email,
): void {}

function connect(
    #[Validate(FILTER_VALIDATE_INT, options: ['options' => ['min_range' => 1, 'max_range' => 65535]],
              message: '端口号必须在 1 到 65535 之间')]
    int $port,
): void {}
```

- Only `FILTER_VALIDATE_*`. Passing `FILTER_SANITIZE_*` is a **compile error** — this attribute
  validates, it never sanitizes, and it never rewrites the parameter.
- The compiler rejects statically impossible combinations: `FILTER_VALIDATE_EMAIL` on `int` is a
  compile error. `FILTER_VALIDATE_INT` is fine on `int` or `string` because `filter_var` stringifies.
- `array` parameters need `FILTER_REQUIRE_ARRAY` / `FILTER_FORCE_ARRAY` to be accepted.
- Default failure is `ValueError('Parameter $email is invalid')`; `message:` overrides it.

---

## Compiler-level contracts

| Attribute | Effect | Cost |
|---|---|---|
| `#[Immutable]` | `$this` (or a parameter) is read-only for the whole body | pure compile-time, **zero runtime** |
| `#[MustUse]` | the return value may not be discarded | zero runtime |
| `#[Override]` | method must override a parent or interface method | zero runtime |
| `#[NoExport]` | keep out of the generated lib stub and symbol table | zero runtime |
| `#[Hot]` / `#[Cold]` | GCC/Clang `hot`/`cold` hints | zero runtime, real layout effect |

### The diagnostics you will actually see

Each of these came from compiling a deliberately wrong file. All of them name the attribute, the
target, and the source line — which is why "the attribute silently did nothing" is almost never a
compiler bug, it is the namespace rule at the top of this page.

```
Hot and Cold cannot be applied to the same function or method
[compile-time attribute: #[Hot]; target: function f(); source: t1.php:2; conflict source: #[Cold] at t1.php:3]

The return value of `openFile()` must be used
[compile-time attribute: #[MustUse]; target: function openFile(); source: t2.php:3; conflict source: discarded call at t2.php:5]

Validate filter FILTER_VALIDATE_EMAIL is incompatible with parameter `$e` declared as `int`
[compile-time attribute: #[Validate]; target: parameter $e; source: t3.php:3]

Cannot call mutable method `U::rename()` on immutable value `$this` in t4.php:4

Immutable object `$u` cannot escape through a return value
Immutable object `$u` cannot be stored in mutable state
Immutable can only be applied to methods, property hooks, or function parameters

Duplicate extension method php::Str::dup()          // only when the method is CALLED
Extension method php::Int::dup() conflicts with keyword extension method *::dup()
```

### `#[Immutable]`

On an instance method, `$this` becomes const-like. On a parameter, the parameter and the object it
references are frozen.

Forbidden inside: reassignment, property/element writes, `+=`/`.=`/`++`/`--`, `unset()`, taking a
reference **to the immutable value itself** ($r =& $u->prop, foreach over its property by
reference), calling a non-`#[Immutable]` method, passing to a non-`#[Immutable]` parameter or a
writable reference, storing into a mutable slot, and `return`/`yield` that would let it escape.
Local aliases do not lift the restriction; `clone` does, because the clone is a new object.

**Refinement measured during regression:** taking a reference to a *copy* is fine. Returning an
array from an `#[Immutable]` method and then doing `foreach ($copy as &$v)` compiles — PHP
copy-on-write means you are mutating your own copy, not the frozen object. What fails is anything
that would write through to the immutable value:

```php
function g(#[Immutable] U $u): void {
    $copy = $u->items();
    foreach ($copy as &$v) { $v = $v * 2; }   // OK — the copy is yours
    $r =& $u->items()[0];                     // FAIL — writes through to $u
    foreach ($u->items() as &$v) { }          // FAIL — same, over the object's own array
}
```

**Each of those was compiled and rejected.** The messages are terse and consistent:

| Attempt | Message |
|---|---|
| `$this->n = "b"` in an `#[Immutable]` method | `Cannot modify immutable value $this` |
| `unset($u)` on an immutable parameter | `Cannot modify immutable value $u` |
| `foreach ($u->n as &$v)` | `Cannot modify immutable value $u` |
| return it from the function | `Immutable object $u cannot escape through a return value` |
| assign into a mutable property | `Immutable object $u cannot be stored in mutable state` |
| push into an array | `Immutable object $u cannot be stored in mutable state` |
| call a non-`#[Immutable]` method | `Cannot call mutable method U::rename() on immutable value $this` |

Two notes from the failures:

- "stored in mutable state" covers properties and arrays alike — the same message, because the
  check is about escaping into mutable storage, not about the container kind.
- `#[Immutable]` on a plain function is itself rejected: *"Immutable can only be applied to
  methods, property hooks, or function parameters"*. There is no `$this` to freeze, so put it on
  the parameter instead.

Related but separate: **objects cannot be passed by reference at all** —
*"References are only supported for int, string, float, bool, array, mixed, or union types"*. So
the "passing to a writable reference" rule often never gets a chance to fire for object types.

It is a static tool, not a sandbox: dynamic method names, variable callables, Reflection and
`eval()` are explicit escape hatches.

Not for plain functions (no `$this`).

### `#[MustUse]`

```php
#[MustUse]
function openFile(string $file): Result {}

openFile('a.txt');              // compile error
$r = openFile('a.txt');         // fine
```

Assignment, returning, passing as an argument, using in an expression, or chaining a method all
count as "used". Only a bare expression statement triggers it. Not allowed on `void` functions.

### `#[Override]`

Fails compilation (`fatal`, not affected by `error_reporting`) when nothing matches:

```
Fatal error: UserService::execute() has #[\Override] attribute,
but no matching parent method exists
```

Implementing an interface method counts as a valid override. Does not match `private` parent
methods, and does not apply to `__construct()`. In a trait, it is verified at the using class.

### `#[NoExport]`

Only meaningful for `-m lib`. The declaration compiles, stays callable **inside** the library, and
is removed from the published surface. It does nothing in a normal (non-lib) project.

Measured with a controlled A/B on `examples/lib-demo` (same sources, `#[NoExport]` present vs
stripped), both built with `-m lib`:

| | with `#[NoExport]` | without |
|---|---|---|
| `demo.stub.php` | only `demo_add`, `demo_public_array` | also `demo_secret`, `class InternalCache` |
| `dumpbin /EXPORTS` | no `php_demo_secret`, no `php_internalcache__bump` | both present |
| library-internal call from `demo_public_array()` | **compiles and links fine** | same |

Two failure modes this prevents:

- **ABI surface leak** — a helper you never intended to publish becomes part of the library's
  contract, and you can no longer change it without breaking consumers;
- **documentation noise** — the generated stub is what consumers read; every internal class in it
  looks like supported API.

The mechanism is precise: the `php_*` symbol loses its export decoration (no `dllexport` on
Windows, hidden visibility on Linux) and the declaration is omitted from the stub. It is **not**
dead-code elimination — the implementation stays in the binary, which is exactly why internal
calls keep working.

Interacts with the generated-method family: annotating a whole class `#[NoExport]` also removes its
`#[Getter]`/`#[Setter]`-generated methods from the stub, since they are public members of that
class.

### `#[Hot]` / `#[Cold]`

Map to `__attribute__((hot))` / `((cold))`. Mutually exclusive — using both on one function is a
compile error. Use `Hot` only for profiled hot paths, `Cold` for error/diagnostic/rare fallback
paths. Mis-marking is actively harmful: it inflates code size and can defeat better compiler
decisions. Cross-file benefit depends on LTO.

---

## Cheat sheet by intent

| I want to… | Use |
|---|---|
| expose a read-only view of a private field | `private` + `#[Getter]` (not `readonly`, which costs runtime) |
| remove DTO boilerplate | `#[Constructor, Getter, Setter, With]` on each field |
| immutable updates | `#[With]` |
| a debug/log string for a class | `#[Printer]` |
| serialize to an array | `#[Arrayable]` |
| add helper methods to strings/ints/arrays | `#[MethodsFor(Type::String)]` |
| add a method to *everything* | `#[MethodsFor('*')]` (receiver param `any`) |
| guard a parameter | `#[NotNull]` / `#[NotEmpty]` / `#[Validate(...)]` |
| stop a discarded result | `#[MustUse]` |
| lock a query method | `#[Immutable]` |
| catch a broken override | `#[Override]` |
| shrink a library's public surface | `#[NoExport]` |
| hint a profiled hot path | `#[Hot]` / `#[Cold]` |

## What is *not* an attribute

Some features look like they should be attributes but are keyword methods or language keywords:

| Thing | It is |
|---|---|
| `toInt()` / `toString()` / `toArray()` / `toAny()` / `toRef()` / `toObject()` | universal keyword methods — cannot be overridden |
| `std::any($x)` / `std::ref($v)` / `std::int($v)` | compile-time functions |
| `std::expected()` / `std::unexpected()` | branch-probability hints, not attributes |
| `use varint_types` | file-level mode (and it boxes integers — see `performance.md`) |

## Meta-documentation of attributes themselves

PHP attribute syntax is supported with non-empty arrays, nested arrays, constant expressions, named
arguments and `new` expressions. Function calls inside attribute arguments are rejected:

```php
#[MyAttribute(new Options(enabled: true), [1, 2, 'x'], 100 + 200)]   // ok
#[MyAttribute(loadOptions())]                                         // compile error
```

User-defined attributes are allowed, but have **no compile-time semantics** — they are ordinary
runtime attributes.
