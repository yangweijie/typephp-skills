# Project layout — from an empty directory to something that builds

## The decision that shapes everything: directory input vs file input

`tpc` accepts either. They are not equivalent, and the difference causes the most common
newcomer failure in the whole ecosystem.

| Input | Behaviour | Use for |
|---|---|---|
| `tpc src/main.php` (single file) | compiles that file only | a quick check, or a genuinely single-file program |
| `tpc src/` (directory) | scans and compiles **all** `.php` under it | a real project |
| `tpc project.yml` | explicit sources, flags, mode, metadata | anything beyond a toy |

Because directory input collects files automatically, **do not put `require_once` at global scope
to pull in sibling files.** It is both forbidden (global scope is declaration-only) and
unnecessary:

```php
<?php
require_once 'Calculator.php';   // ← Fatal error: All execution code must be within a function
function main(): void { ... }
```

Drop the line and the directory build picks `Calculator.php` up on its own. This exact snippet
ships in `docs/zh-cn/QUICKSTART.md:86` and `docs/en/QUICKSTART.md:86`, in both languages — so if
the user is following the quickstart and hits `stray code`, that is the reason, not their setup.
`main()` works with or without `: void`, despite the docs saying `void` is required.

A second consequence of single-file input: sibling files are **not** visible. `tpc --dry main.php`
still exits 0 when `main.php` instantiates a class defined in a neighbour file, because undefined
classes resolve dynamically at runtime (see `verification-ladder.md`). So a single-file check can
be green on a program that will die on line 2. Prefer directory or `project.yml` input whenever
the program has more than one file.

## Minimal `project.yml`

```yaml
name: my-app
mode: bin
version: 0.1.0
cxx-std: c++17
sources:
  - src
```

That builds. Fields worth knowing (call `get_build_config_help` for the authoritative list):

| Field | Notes |
|---|---|
| `output` | output path, equivalent to `-o`. `name` only changes the file name, never the directory |
| `name`, `version` | `version` is written into the Zend module entry and readable via reflection |
| `mode` | `bin` (default, needs `main()`), `lib` (shared lib + generated `.stub.php`), `ext` (PHP extension). Aliases: `binary`, `library`/`shared`, `extension` |
| `sources` | files or directories; accepts `.php`, `.cpp`, `.c`, `.s`, `.m`, `.mm`; conditional entries via `if:` + `path:` |
| `ignore` | exclude paths. **No wildcards, no regex** — each entry is an explicit path; a directory excludes recursively; nonexistent paths are silently skipped |
| `objects` | pre-built `.o`/`.obj` linked as-is; `tpc` never recompiles them |
| `optimize`, `job`, `debug` | `-O` level (**default 0**), parallel jobs (**default 4**), debug switch |
| `include-paths`, `defines`, `link-paths`, `link-libs` | native toolchain inputs |
| `ext-deps` (alias `extension-dependencies`) | Zend module dependencies; **not** native link libs. Use only one of the two names |
| `embedded-files` | `bin` mode only: bake `vendor/`, resources into the executable |
| `entry`, `sapi` | SAPI selection is **`bin`-only**; `cli`/`fpm` require `php-builder`; `entry` is required when `cli` is selected |
| `sanitize`, `lto`, `format`, `march`, `target-platform` | optimization/diagnostic knobs, all exposed as CLI flags too |

`cxx-flags`, `ld-flags` (and `c-flags`, `asm-flags`) set per-language flags. Command-line
arguments override the same-named YAML fields, which override defaults.

### Conditional sources

```yaml
sources:
  - src/
  - if: PHP_OS_FAMILY == "Windows"
    path: src/windows_shim.php
  - if: PHP_VERSION_ID >= 80400
    path: compat/php84.php
```

Useful for the common case where a compat shim only applies on one platform or PHP version.

### `ignore` is not a glob

Counter-intuitive but explicit in the docs: `ignore` takes **explicit paths only**. `src/*.tmp` will
not match anything; write `src/cache` or the exact file. Missing paths are skipped without a
warning, so a typo fails silently and your excluded file still compiles.

### `sapi` is not a mode

`cli` and `fpm` are SAPIs, not build modes — `mode` stays `bin`. They also force `php-builder`
(Windows cannot do it), and selecting `cli` without `entry` is a warning where the entry point
silently does nothing. Multi-SAPI builds get `-embed`/`-cli`/`-fpm` suffixes on the output name.

## Recommended layout

```
my-app/
├── project.yml
├── src/
│   ├── main.php          # only defines main(), no top-level statements
│   ├── Calculator.php    # one class per file
│   └── ...
└── tests/                # plain-PHP unit tests, no build required
```

Keep `main.php` free of side effects beyond calling into your classes — it makes the domain layer
testable with a stock `php` binary, which is orders of magnitude faster than any build.

## Adding native code (only when you must)

A `.stub.php` declares signatures with **empty bodies**; a matching `cpp-src/*.cc` implements
them with a `php_` prefix:

| File | Role |
|---|---|
| `php-src/<name>.stub.php` | PHP-visible signature. Bodies must be `{}`. This is the only place the compiler learns bridge types. |
| `cpp-src/<name>.cc` | Implementation; PHP function `foo_bar()` ↔ C++ `php_foo_bar()` |

Two rules that break builds silently otherwise: `.stub.php` accepts only `php::` types, and stub
classes may not carry `#[Native]`. For the full bridge pattern, see the `typephp-qt-app` skill.

## Where things land

Pass `--build-dir` explicitly, always:

```bash
tpc project.yml --no-progress --build-dir build/
```

Without it, generated `.cc` files are written into the **toolchain install directory**
(observed: `$PHP_HOME/build/extension-*.cc`). That pollutes the SDK, makes subsequent error
output point at paths that are not yours, and can make an otherwise clean rebuild behave
unexpectedly.

## What actually ships

`build/` is intermediate output, never the release artifact. A `mode: bin` package needs:

- the executable;
- `libphp` and `libphpx` (dynamic linking is deliberate — that is how binaries stay small);
- `vendor/` if you did **not** use `embedded-files`;
- any dynamically loaded extension `.so` files.

With `embedded-files` you drop the disk `vendor/` and the PHP CLI/Composer requirement entirely,
but `libphp`/`libphpx` still ship. `ignore` does **not** remove anything from `embedded-files` —
those are two independent lists.

Target OS and base library set must match the build machine; compile PHP extensions statically
into the PHP runtime where possible rather than loading them at runtime.

## Two runtime-path traps

**`__DIR__` and `__FILE__` are frozen at compile time.** They resolve to the build machine's
paths, not the deployment location. Do not use them to locate data files at runtime — use
`getcwd()`, an environment variable, or a config file. (Counterpoint worth knowing: `__DIR__` in a
`bin` build does resolve against the running executable's directory in practice, which is why
"run from another cwd" tests pass — but that is not a guarantee to build a data-path strategy on.)

**`vendor/` should usually stay dynamic.** The documented recommendation is to keep third-party
frameworks on Composer autoload and selectively compile only what you need via a whitelist in
`sources`, adding `ignore` entries for individual incompatible files. Compiling all of `vendor/`
is how you inherit someone else's `eval()` and dynamic dispatch.

There is one hard constraint if you do compile into a vendor class: **the entire inheritance chain
must be statically compiled**. If `App\Controller` extends `Framework\Controller` extends
`Framework\BaseController`, all three must be in `sources` — a partially compiled chain fails.
