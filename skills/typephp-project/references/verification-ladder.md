# The verification ladder — what each rung proves, and what it hides

Every claim you make about TypePHP code should name its rung. This file exists because the
single most costly mistake in this domain is reporting rung 1 as if it were rung 4.

All figures below are measured on **tpc v0.9.5, Windows x64, MSVC 14.44**, against the MCP
binary built from `tools/typephp-mcp`. Re-measure if the version has moved.

## Rung 1 — generate (`tpc --dry`, `check_code`)

Produces C++ without invoking a C++ compiler. Fast: ~150–250 ms for a single file.

**Catches:**

| Input | Result |
|---|---|
| Missing `]` | `Fatal error: Syntax error, unexpected T_ECHO, expecting ',' or ']' or ')' in file:5` |
| `$count = 1; $count = "one";` | `Cannot re-assign $count from php::Str to php::Int in file:5` |
| `$$name` | `The $$ syntax is not supported` |
| `Closure::bind(...)` | `Closure::bind() is not supported` |
| `echo` at global scope | `All execution code must be within a function, found stray code in file:2` |

**Does NOT catch — this is the important list:**

| Input | `check_code` says | Truth |
|---|---|---|
| `echoo("done")` | `OK ... diagnostics=0` | `Error: call to undefined function` at runtime |
| `new Calc()` with no `Calc` declared anywhere | `OK ... diagnostics=0` | `Error: class 'Calc' is undefined` at runtime |
| `no_such_function(1)` | `OK ... diagnostics=0` | fatal at runtime |
| `Missing::make()` | `OK ... diagnostics=0` | fatal at runtime |

Reason: undefined symbols are resolved at **runtime** through the PHP class/function table, not
at compile time. The generated C++ looks like this — note the dynamic lookup:

```cpp
c = php::newObject(get_class(RequestClassId{0}, get_str(0)));
php::echo(php::toString(typephp_call_method_cached(c, get_str(1), ...)));
```

So the compiler happily emits a dynamic lookup and defers the failure. `--dry` has no reason to
complain, and it doesn't.

**Practical rule:** a green `check_code` on a file that calls a symbol you just invented is
worth nothing. Cross-check new type/function names with `get_symbol` or `search_code` when the
symbol is not obvious PHP.

## Rung 2 — compile

Invokes `cl` (Windows) or `g++`/`clang++` per translation unit. This is where environment faults
surface, and they are frequent:

| Symptom | Real cause |
|---|---|
| `fatal error C1083: cannot open include file "malloc.h"` | `INCLUDE` not initialized → `call vcvars64.bat` |
| `fatal error C1083: cannot open include file "cstring"` | same |
| `C/C++ compiler executable not found: cl` | no compiler on PATH at all |
| `php8embed.lib not found` | `PHP_HOME` not set / wrong package |
| `0xC0000139` running `tpc.exe` itself | using the repo-root `tpc.exe` instead of the release package |

None of these are PHP bugs. Note that **`check_code` shields you from the first two** by
prepending the vswhere-located MSVC bin to PATH. That is helpful while iterating and dangerous
as evidence — it proves the code is checkable, not that the user's machine can build.

## Rung 3 — link

Same `tpc` invocation, link phase. Catches missing libraries and symbol collisions. If the
project links native code (`.stub.php` + `cpp-src/`), this is where a mismatched `php_` prefix
or a non-`php::` type in the stub shows up.

## Rung 4 — run

The only rung that proves the artifact works. Two failure families live here and nowhere else:

**Missing runtime DLLs.** A freshly built `app.exe` fails with

```
app.exe: error while loading shared libraries: ?: cannot open shared object file
exit = 127            (0xC0000135 on Windows)
```

`dumpbin /DEPENDENTS` on the same binary shows `phpx.dll`, `php8ts.dll`, `libmpdec++-4.0.1.dll`,
VC runtime. They come from the tpc release package, so the binary runs only where that package's
directory is on `PATH`. This is documented (README: "must be available in the deployment
package") but routinely forgotten because "AOT produces a native binary" suggests otherwise.

**Runtime capability gaps.** Something compiles and links but the runtime lacks the driver:

```
Fatal error: Uncaught PDOException: could not find driver
exit = 255
```

Measured on a fixture using `array_push()` + `new PDO('sqlite::memory:')`: compile ✓, link ✓,
run ✗ — and splitting it showed `array_push` alone was perfectly correct (`array(4)`), so the
failure was 100% the PDO driver, not the array translation.

## Choosing how far to climb

| Situation | Minimum rung |
|---|---|
| Iterating on one file's logic | 1 (`check_code`), and only when you trust the symbols |
| About to tell the user "this is done" | 4 |
| Touching `project.yml`, `sources`, or link flags | 3 |
| Raising a PR / handing off | 4, plus the dependency list |
| Investigating "it compiles but crashes" | start at 4 and read `debugging.md` |

## Cost reality

Rungs 2–4 are expensive compared to rung 1: a small project's compile is tens of seconds and
links a full PHP runtime. That is precisely why the discipline matters — you want to spend
rung-1 calls liberally and rung-2+ calls deliberately, and when you do climb, make it count by
actually running the artifact instead of stopping at "Build successful".
