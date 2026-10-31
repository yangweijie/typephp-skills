# Type system: what stays static, what decays to `php::Var`

TypePHP's performance comes from one thing: whether the compiler can prove a value's type at each
point. When it can, you get C++ storage and native calls. When it cannot, the value becomes
`php::Var` (a boxed zval) and every operation goes through a type-tag branch.

This file is the decision table.

## The decay rules

A value becomes `php::Var` if any of these apply:

| Source | Why |
|---|---|
| `mixed`, `callable`, `iterable`, `object`, untyped param/return/property | no static type to begin with |
| `int\|float`, `A&B`, `?A` | union/intersection/nullable cannot be a single C++ type |
| **any element read out of an ordinary PHP array** | array slots are inherently zval — the single most common hot-loop trap |
| `global` / `$GLOBALS[...]` | compiler cannot prove the slot's type |
| `std::any($x)` / `$x->toAny()` | explicit erasure |
| dynamic calls: `call_user_func`, variable function name, string callbacks | target unknown |
| `use varint_types` (whole file) | inferred ints map to `php::Var` on purpose |

Two of these are structural rather than mistakes: **array elements and `global` are always boxed**.
Do not "fix" them by sprinkling casts everywhere — fix them by not routing hot data through them.

## Recovery: the keyword methods

Erasure is one-way unless you restore the type explicitly. These are universal keyword methods and
cannot be overridden by user code:

| Method | Result |
|---|---|
| `->toInt()` / `->toFloat()` / `->toBool()` / `->toString()` / `->toArray()` | corresponding native type |
| `->toObject(Foo::class)` or `std::object($v, Foo::class)` | typed object with class info — **this is what restores native method calls** |
| `->toObject()` | `php::Object` with **no class info** — calls stay dynamic |
| `->toAny()` | back to dynamic (no arguments; `toAny($t)` is a compile error) |
| `->toStdVector(Type::Int)` etc. | typed container |

The asymmetric cost matters: scalar recovery is one conversion, but `toStdVector()` / `toStdList()`
validate the **whole array** (O(n)), and `toObject(C::class)` is a runtime `instanceof`. Calling
those inside a loop creates a new hot spot — restore once at the boundary.

```php
// array element -> native call, the standard fix
$payload['user']->toObject(User::class)->getName();

// wrong: (object) gives no class info, so the call stays dynamic
$obj = (object) $payload['user'];
```

## What never restores anything

`(object)`, `callable`, `iterable` casts give the compiler nothing. `toObject()` without a class
name gives it nothing either. If you want the fast path, the class must be named.

## Container choice, one line each

| Container | Use when |
|---|---|
| `std::vector(Type::T)` | append-heavy, single element type, random access — zero-overhead `std::vector` |
| `std::array(Type::T, N)` | fixed size known at compile time; literal indices bounds-checked at compile time |
| `std::map(K, V)` | large lookup table, order irrelevant — O(1) `unordered_map` |
| `std::orderedMap(K, V)` | ordered iteration / stable serialization — O(log n) `std::map` |
| `std::list(Type::T)` | must remain a real PHP array but want element-type constraints |
| `std::dict(K, V)` | same, but key/value constrained (typical `string → int` counter) |

Keys may only be `Int` or `String`. Both `std::list` and `std::dict` are still `php::Array`
underneath — you get type checking, not C++ layout. Do not use them where you wanted speed.

## Container gotchas that produce wrong answers, not errors

| Behaviour | PHP | TypePHP |
|---|---|---|
| `unset($vector[$i])` | removes | **resets to `T{}`**, count unchanged, iteration still sees it |
| read missing key on `std::map` | null + warning | **throws `std::out_of_range`** — use `isset()` first |
| `$array[null] = 1` | key `''` | **treated as append** — use `$array['']` if you want the empty key |
| uninitialized typed property | `Error` on read | **zero value** (`0`, `''`, `[]`); `isset()`/`??` semantics differ |
| `unset($intLocal)` | variable undefined | resets to `0` |
| two ints divided | float when not exact | **stays int**; use `$a / 3.0` or `std::any()` |

Each of these compiles fine and behaves differently. They are the most likely source of a bug that
passes `check_code` and fails in production.

## Object properties are hard-typed

This is a bigger deal than it sounds. `int`/`float`/`bool`/`string`/`array` properties get fixed
slots — that is why property access approaches C struct speed. The price:

- no `unset()`, no assigning `null` to them; use `?int $id = null` when you need absence;
- an object-typed property may be `unset()` but not assigned `null` unless nullable;
- `is-a` assignment is allowed (child into a base-typed property), the reverse is not;
- a child class may **not** redeclare a parent's `private` property under the same name.

## References are deliberately narrow

Native references (`&T`) work only where the compiler knows both sides at compile time:

- statically resolved functions/methods with matching `&T` parameters — plain arguments;
- a native class's fixed property passed to a matching `&` parameter;
- local aliases `$alias =& $name`: once, unconditional, function-scope only, no rebinding, no
  escaping into arrays/properties/globals, no returning by reference.

Anything dynamic needs `std::ref($v)` or `$v->toRef()`, at the call site only, on an lvalue.
Cannot be referenced at all: fixed objects, resources, high-precision values, `#[Native]` handles,
typed-object locals, Box, std containers.

## The practical rule

Read your hot path and ask one question per value: **did this come from an array, a `global`, an
untyped signature, or an explicit `std::any()`?** If yes, it is boxed. Restore it with a keyword
method at the boundary, or change the shape of the data so it never goes through a plain array.

Full measurement technique for confirming this in generated code: `performance.md`.
