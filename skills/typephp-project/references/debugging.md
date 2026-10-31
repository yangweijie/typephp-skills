# Debugging — from error string to actual cause

`tpc` reports faithfully but not always helpfully: the message often names the symptom, not the
cause. This file is a lookup table from what you see to what is actually wrong, ordered by how
often it happens.

## First question: is this a code fault or an environment fault?

Answer this before touching the PHP, because the two have nothing in common and guessing wrong
can burn an hour.

Cheap discriminator — build a file you know is good:

```bash
tpc examples/hello.php -o /tmp/probe.exe --build-dir /tmp/probe-build --no-progress
```

If the known-good file also fails, it is the environment. Do not edit the user's code.

## Environment faults

| What you see | Cause | Fix |
|---|---|---|
| `fatal error C1083: cannot open include file "malloc.h"` (or `"cstring"`) | MSVC `INCLUDE` not set; `vcvars64.bat` never sourced | run inside a Developer shell, or `call "...\VC\Auxiliary\Build\vcvars64.bat"` first. `cl.exe` merely being on `PATH` is not enough. |
| `C/C++ compiler executable not found: cl` | no compiler on `PATH` | install MSVC Build Tools, or pass `--compiler`, or set `cpp-compiler` in `project.yml` |
| `php8embed.lib not found` | `PHP_HOME` unset or pointing at a package without the embed lib | point `PHP_HOME` at the tpc release package |
| `The host PHP embed library is missing` | macOS/Linux: `PHP_HOME` lacks `libphp.a`/`.dylib` (Homebrew's php has no libphp) | use a package that ships the embed library |
| `tpc.exe` dies with `0xC0000139` (entry point not found) | using the **repo-root** `tpc.exe` instead of the release package build | use `$PHP_HOME/tpc.exe`; if configuring MCP, set `TYPEPHP_MCP_TPC` accordingly |
| MCP connection closes immediately after config | launcher stripped backslashes (`D:\\git\\…` → `D:git…`) | use **forward slashes** in MCP config paths |

`check_code` auto-repairs the first two on Windows (it prepends the vswhere-located MSVC bin).
If MCP is green but a manual `tpc` fails, that divergence is the explanation — not a flaky tool.

## Compile-stage faults

| What you see | Cause | Fix |
|---|---|---|
| `All execution code must be within a function, found stray code in file:2` | a top-level statement — most often `require_once` added to pull in a sibling file | delete it; directory and `project.yml` inputs collect files automatically |
| `Cannot re-assign $x from php::Str to php::Int` | a local's inferred native type changed | wrap the initial assignment in `std::any(...)`, or use distinct variables |
| `The $$ syntax is not supported` | variable variables | restructure to an array or explicit switch |
| `Closure::bind() is not supported` | `Closure::bind`/`bindTo`/`call` | pass values explicitly, or use a closure with `use` |
| `not supported` on a language feature | genuine design limit | check `docs/zh-cn/INCOMPATIBLE_PHP_FEATURES.md`; it separates hard limits from pending work |
| `switch` case fallthrough complaint | every non-empty case must terminate | add `break`/`return`/`throw` |

## Link-stage faults

| What you see | Cause |
|---|---|
| undefined symbol `php_xxx` | `.stub.php` declares it but no `cpp-src` implements `php_xxx` |
| duplicate symbol | two translation units define the same bridge function, or two classes with colliding constants |
| missing `-l` library | add `link-libs` / `link-paths` in `project.yml` |

## Run-stage faults — the ones `check_code` cannot see

| What you see | Cause | Fix |
|---|---|---|
| `error while loading shared libraries` / `0xC0000135`, exit 127 | binary needs `phpx.dll`, `php8ts.dll`, math libs from the tpc package; they are not on `PATH` | ship them next to the binary, or add the package dir to `PATH`. Verify with `dumpbin /DEPENDENTS` (Windows) / `ldd` (POSIX) |
| `class 'X' is undefined` | the class does not exist in the compiled set — wrong file omitted from `sources`, or the name is misspelled. **`check_code` reported OK** | add the file to `sources`; confirm the name with `get_symbol` / `search_code` |
| `call to undefined function yyy` | same: dynamic lookup failed at runtime, compile was silent | same |
| `PDOException: could not find driver` | the linked runtime lacks that driver | use a runtime/extension config that includes it, or avoid the driver |
| fatal on a stock-PHP idiom that compiled fine | runtime capability gap, not a translation bug | confirm what the runtime actually provides before redesigning the code |

The pattern in that middle block deserves emphasis: **undefined symbols surface at rung 4.** When
a program compiles and links but dies with "undefined", the compiler was never going to help. Look
at which files were actually included (`prepare completed: N source files` in the log) — N being
1 when you expected 3 is the answer.

## Reading tpc's output efficiently

tpc stops at the first fatal and prints a PHP stack trace. Only one line carries information:

```
Fatal error: Cannot re-assign `$count` from `php::Str` to `php::Int` in ...\e2.php:7   ← the diagnosis
#0 [internal function]: CliDiagnosticReporter->fatal('...')                             ← noise
#1 [internal function]: Translator->convert(Array)                                      ← noise
#2 [internal function]: ProjectBuildRunner->run(Array)                                  ← noise
#3 D:\a\typephp\typephp\src\compiler.php(14): main(5, Array)                           ← noise, and a build-machine path
```

Roughly 11–14% of the output is signal. Read line one, ignore `D:\a\typephp\...` (that path is
baked into the distributed binary and does not exist on this machine).

Because it stops at the first error, **N independent mistakes cost N build rounds**. That is the
argument for learning the rules up front rather than fixing reactively — see
`typephp-idioms.md`.

## Handy probes

```bash
# is the toolchain usable at all?
tpc --version

# what does this file generate? (inspect the C++, often fastest to diagnose)
tpc --dry src/main.php --build-dir /tmp/bd && sed -n '1,60p' /tmp/bd/main.cc

# which files did the build actually pick up?
tpc project.yml --dry --no-progress | grep '^prepare'
```
