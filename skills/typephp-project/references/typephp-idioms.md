# TypePHP idioms — the parts that differ from stock PHP

Write PHP the way the compiler wants it and most rounds disappear. This file collects the
differences that actually bite, with measured behaviour.

## Structure

Executor code lives in functions; global scope is declaration-only.

```php
<?php
// global scope: classes, functions, const, use, declare — nothing else
const LIMIT = 100;

function helper(): int { return LIMIT; }

function main(): void          // bin mode entry point
{
    echo helper();
}
```

- `function main()` and `function main(): void` both compile today. Prefer `: void` — it matches
  the documentation and the examples.
- `main(int $argc, array $argv)` is the accepted parameterized form.
- Functions and named classes may **not** be declared inside a function.

## One local, one type

```php
$count = 1;
$count = "one";     // Fatal error: Cannot re-assign $count from php::Str to php::Int
```

Type inference is deliberate: inferred `int`/`float`/`bool` get fixed native storage. When a
variable genuinely needs to change shape, opt in explicitly:

```php
$value = std::any(1);      // erase the static type for this expression
$value = "one";            // now fine
```

`use varint_types` at file scope switches inferred integers to PHP-compatible overflow/division
semantics — reach for it when integer behaviour, not speed, is what you need.

## Use the universal methods, not the C++ names

The idiomatic TypePHP form of array/string operations is a method on the value. This is the
biggest source of "I searched and found nothing" — the answer usually is not `array_push`:

```php
$arr = [1, 2, 3];
$arr->push(4);            // array_push($arr, 4)          → [1,2,3,4]
$arr->push(5, 6, 7);      // multiple args supported
$arr->count();

$s = "hello world";
$s->length();             // strlen
$s->upper();              // strtoupper
$s->substr(0, 5);

$a = 100;
$a->add(50);              // a += 50 → 150
$a->toString();
```

Classic function forms still work in most cases (`array_push($items, 4)` compiles and runs
correctly — measured), so this is a style/performance choice, not a hard rule. But when you are
*searching* for an API, search the method form: `search_docs("push")` finds the universal-method
section, whereas grepping `std::vector` leads you astray.

## std containers

`std::array`, `std::vector`, `std::orderedMap`, `std::map` give typed, allocation-light storage.
They are not drop-in PHP arrays: element types are fixed, and structural mutation during
`foreach` over them is forbidden.

```php
$map = std::orderedMap('string', 'int');
$map['a'] = 1;

foreach ($map as $k => $v) {
    // do not insert/remove here — structural change during iteration is rejected
}
```

Match container to intent: `orderedMap` when iteration order matters, `map` when it does not,
`vector` for append-heavy sequences, `array` for fixed-size.

## References

Dynamic and closure calls need explicit `std::ref()` / `toRef()`:

```php
function bump(int &$n): void { $n++; }

$n = 1;
$fn = 'bump';
$fn(std::ref($n));      // bare $fn($n) cannot bind a reference
```

Native reference bindings must be unconditional, single, inside a function, and non-escaping.
Conditional/looping first binds, rebinding, `unset`, returning by reference, and storing into
properties/arrays/globals are all compile-time errors.

`Closure::bind`, `Closure::bindTo`, and `Closure::call` are unsupported. `use (&$v)` degrades the
captured local to `php::Var`.

## Things that are simply not there

- `$$var` (variable variables)
- `declare(ticks=…)`; `declare(strict_types=1)` is accepted but a no-op (TypePHP is always strict)
- `eval()` cannot see AOT locals
- `#[NoDiscard]` (PHP 8.5)
- switch fallthrough: every non-empty `case` must end with `return`/`break`/`continue`/`exit`/`throw`

## Closures, `match`, and other modern syntax

These work. Verified with `--dry` during skill authoring:

```php
$doubled = array_map(fn($x) => $x * 2, $items);      // arrow fn ✓

return match (true) {                                 // match ✓
    $n < 0 => 'neg',
    $n === 0 => 'zero',
    default => 'pos',
};
```

`foreach ($data as $k => &$v)` by-reference iteration also compiles; remember to `unset($v)`
afterwards, exactly as in stock PHP.

## Namespaced classes: keep the `use` import

If a class is namespaced (`namespace App;`), the calling file **must** import it:

```php
use App\PriceFormatter;      // ← required, even though the short name is used below

function main(): void
{
    echo PriceFormatter::format(120);   // short name only resolves via the import
}
```

Drop that line and everything up to link still passes — `--dry` green, `Build successful` — then
the first run dies:

```
Fatal error: Uncaught Error: Invalid callback PriceFormatter::format,
class "PriceFormatter" not found
```

Measured both ways during skill authoring. The static call is lowered to a runtime name lookup,
so the compiler has no opinion about whether the alias exists. Copying a class out of a
namespaced file into the global namespace, or forgetting the import while porting, produces
exactly this.

## Sorting, and a caution about over-engineering

**`usort` with a closure works.** Measured end-to-end (compile, link, run, correct descending
output) during skill authoring:

```php
$order = [];
foreach ($totals as $name => $sum) {
    $order[] = [$sum, (string) $name];
}
usort($order, fn ($a, $b) => $b[0] <=> $a[0]);

foreach ($order as $row) {
    echo $row[1] . ': ' . $row[0] . "\n";
}
```

This matters because it is the *normal* way to sort a PHP array, and it is easy to assume AOT
constraints forbid it. Two independent agents handed this problem both assumed the closure would
break type inference and hand-wrote insertion sort instead — roughly 30 extra lines each, and
more surface area for the runtime-only bugs that `check_code` cannot catch.

The general lesson, which is worth more than this one API: **do not preemptively avoid ordinary
PHP out of fear of AOT limits.** The documented restrictions are a short, specific list
(see "Things that are simply not there" above and `list_restrictions`). If something is not on
that list, write it the normal way and let the compiler tell you. Hand-rolling substitutes
"just in case" costs readability and adds exactly the kind of dynamic code path that fails late.

The one signature worth pinning down: when a value may be `false` (e.g. `fgets`), an explicit
cast or a typed helper (`function trimmed(string $s): string`) keeps inference clean and avoids
feeding a union into a comparison.

## Quick self-check before submitting

- No executable statement outside a function or method
- `main(): void` present (bin mode)
- No variable that changes between incompatible inferred types without `std::any()`
- No `$$`, no `Closure::bind*`, no `declare(ticks)`
- Every non-empty `switch` case terminates
- New type/function names actually exist (`get_symbol`) — the checker will not tell you
- Ordinary PHP (`usort`, `array_map`, `match`, by-ref `foreach`) kept as-is unless it is on the
  documented restriction list
