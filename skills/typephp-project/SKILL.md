---
name: typephp-project
description: Create, modify, debug, and audit TypePHP (PHP→C++ AOT compiler) projects, driven by the typephp-mcp server. Covers the real build ladder (--dry → compile → link → run), the four tools that prevent wasted rounds (list_restrictions, get_build_config_help, search_docs, check_code), what check_code silently cannot see, project.yml authoring, the main()/global-scope contract, native type inference traps, std containers, debugging runtime-only and deploy-only failures, and auditing existing PHP libraries for TypePHP portability (bin vs lib mode, per-file false positives, bulk scans). Use this skill whenever the user works on a TypePHP project or the aot-compiler/tpc repo, mentions tpc, project.yml, .stub.php, phpx, TypePHP restrictions, check_code failures, "my TypePHP program compiles but crashes", or asks to port, rewrite or evaluate PHP for ahead-of-time compilation, judge whether a codebase can migrate to AOT, or audit vendored/library code — even if they never say "TypePHP" but clearly fight an AOT PHP build.
---

# TypePHP project work, with typephp-mcp

TypePHP compiles PHP to native binaries through C++. That single fact explains almost every
failure mode you will hit: the source language is PHP, but the *acceptance criteria* are a
C++ compiler's, and the *runtime* is a linked PHP runtime rather than a stock interpreter.

The typephp-mcp server exists to shorten the loop between those three worlds. Use it as a
sensor array, not as an oracle — it answers a narrower question than most people assume.

## The one thing to internalize first

`check_code` runs `tpc --dry`, which **only generates C++**. It does not compile, does not
link, and does not run.

Measured on tpc v0.9.5 / Windows / MCP binary from this repo:

| Program | `check_code` | Real build | Run |
|---|---|---|---|
| `echoo("done")` — misspelled function | **OK, diagnostics=0** | succeeds | `Error: call to undefined function` |
| `new Calc()` with no `Calc` class anywhere | **OK, diagnostics=0** | succeeds | `class 'Calc' is undefined` |
| `no_such_function(1)` | **OK, diagnostics=0** | succeeds | fatal at runtime |
| Missing `]` (real syntax error) | FAILED with `file:line` | — | — |
| `$count = 1; $count = "one";` | FAILED, type mismatch | — | — |

So the division of labour is sharp:

- **Syntax, parse, and static-type-inference errors** → `check_code` catches them, with `file:line`.
- **Undefined symbols, signatures, and anything link- or runtime-level** → `check_code` says OK
  and means nothing by it. A green check is *necessary, never sufficient*.

Treat "check_code is green" as "the compiler accepted the syntax and types", not "this works".
If you report to the user that the code is correct on the strength of a green check, you will
eventually be wrong, and it will be at runtime in front of them.

For the full evidence behind this table, and what each failure class looks like, read
`references/verification-ladder.md`.

## The build ladder — know which rung you are on

TypePHP has four rungs, and each one catches a different class of bug. Most wasted time comes
from climbing only the first rung and declaring victory.

| Rung | Command | Catches | Misses |
|---|---|---|---|
| 1. Generate | `tpc --dry <file>` / `check_code` | syntax, parse, static type inference, forbidden constructs | everything downstream |
| 2. Compile | `tpc <file>` (runs cl/g++ per TU) | C++ codegen bugs, missing SDK headers, **toolchain not initialized** | link errors, runtime |
| 3. Link | same command, link phase | missing libs, symbol conflicts | runtime capability |
| 4. Run | `./app` | **missing runtime DLLs**, unsupported extensions, wrong data | — |

A practical consequence: **a project is not verified until rung 4 has actually executed once.**
Everything above it can be green while the binary dies instantly on a missing `php8ts.dll`.

## Workflow

### 0. Confirm the environment before blaming the code

This is the single highest-yield check, because two environment faults masquerade as code bugs.

```bash
# Is a compiler reachable?
which cl || which gcc || which clang
# On Windows/MSVC, PATH having cl.exe is NOT enough — INCLUDE must be set:
echo "$INCLUDE" | grep -i msvc
```

If `INCLUDE` is empty on Windows, `tpc` fails with `fatal error C1083: cannot open include file
"malloc.h"` / `"cstring"`. That is not a missing library and not a code problem — it means
`vcvars64.bat` was never sourced. Fix the shell, not the PHP.

Bundle `scripts/preflight.sh` (or `.bat`) checks this plus tpc/MCP reachability in one shot.
Run it first when the user says "nothing compiles", especially on a machine you have not built on.

Note the asymmetry that matters for trust: `check_code` **auto-repairs** the MSVC PATH via
vswhere (`ensureHostToolchain()`), so it stays green on a machine where a manual `tpc` fails.
That makes MCP excellent for logic iteration and useless as proof that the user's own shell works.

### 1. Load the rules before writing code — `list_restrictions`

Call `list_restrictions` (no topic = full summary, ~1.6 KB) or one topic:
`structure`, `types`, `refs`, `objects`, `control`, `runtime`, `std`, `stub`, `build`.

The summary is also injected into `initialize.instructions`, so it may already be in context —
check before spending a call. Reading it *before* writing is the difference between one round
and four; the compiler stops at the first error, so each unlearned rule costs a full round.

The traps that account for most real failures:

- **Global scope is declaration-only.** `require_once`, `echo`, assignments at top level are all
  rejected. This is also why a `require_once 'X.php';` line above `main()` fails — see
  `references/project-layout.md`.
- **`main()` is required in bin mode.** Both `function main()` and `function main(): void` are
  accepted by the compiler today, though the docs say `void`; prefer `: void`.
- **One local, one type.** Once `$x` is inferred `int`, assigning it a string is a hard error.
  Reach for `std::any()` when a variable genuinely changes type.
- **No `$$var`, no `Closure::bind/bindTo/call`, no `declare(ticks)`.**

**"Unsupported" is four different things.** Before deciding whether to rewrite or wait, find out
which: Hard Limit (permanent), Intentional Rule (permanent, but a mechanical fix), Pending
(implementable later — work around now), Partial (keep the code, learn the boundary). `$$var`,
`echo` with assignment, by-ref returning closures, nested `match` in arm conditions are all
**Pending**, not impossible. Treating them as permanent causes needless redesigns; treating a Hard
Limit as Pending causes a lost quarter. Full table in `references/incompatibility-taxonomy.md`.

Two things the restriction list does **not** say, which matter just as much:

**Most ordinary PHP works — do not preemptively avoid it.** `usort` with a closure, `array_map`,
`match`, `array_column`, `array_sum`, `json_decode`, by-ref `foreach`, `number_format` — all
measured working end-to-end. The restriction list is short and specific; if what you want to
write is not on it, write it the normal way and let the compiler object. Agents that skip this
step hand-roll insertion sorts and CSV parsers "just in case", which adds lines and adds exactly
the kind of dynamic call path that fails late at runtime.

**Type-first idioms are not universal methods.** `$s->length()` on a real `string` works, but
`$line->trim()` where `$line` came from `fgets`/`$fp->getLine()` compiles clean and dies at
runtime with `call method 'trim' on string`. Use the plain function (`trim($line)`) for scalar
values coming out of I/O, and reserve the method form for typed containers. Same for arrays:
`$row->name` on an associative array fails at runtime; iterate with `foreach (... as $k => $v)`
or index it. Neither of these is caught by `check_code` — they are runtime-only.

### 2. Learn the project shape — `get_build_config_help`

Before writing a `project.yml` or adding a second source file, call
`get_build_config_help`. It documents `sources`, `ignore`, `objects`, `include-paths`, `defines`,
`link-paths`, `link-libs`, `ext-deps`, `embedded-files`, `entry`, `sapi`, the three modes
(`bin`/`lib`/`ext`), and the `.stub.php` contract.

Then read `references/project-layout.md` for the layout decisions that the help text does not
make for you — directory-input vs file-input, where `main.php` goes, and how `sources` interacts
with what `check_code` can see.

### 3. Write the code

Keep the PHP domain logic plain and Qt/framework-free where possible; it is ordinary PHP and
runs under a normal interpreter for unit tests, which is far faster than any build.

Then, per file, the loop is:

1. Write or edit the file.
2. `check_code(path)` — iterate until green. This is genuinely fast (~150–250 ms).
3. Move on. Do not build between every file edit; accumulate.

`check_code` needs an **absolute path, or a path relative to the MCP repo root**, and only
accepts `.php` files. Directory and `project.yml` inputs are refused by design — that refusal is
a safety feature: a `project.yml` can start a real php-src build even under `--dry`. Do not try
to work around it; verify the project with `tpc` at rung 2+ instead.

Absolute paths outside the compiler repo work fine (measured: 264 ms for a file in another
project), so there is no reason to copy a file into the repo just to check it.

**The one hard limit: `check_code` always runs bin mode.** Bin mode requires a global `main()`,
so a library file — anything without `main()` in its compilation unit — is rejected with
`The Embed SAPI requires a global main() function`, which is not a compatibility verdict. If you
are auditing vendored code or a library rather than an application entry, read
`references/auditing-code.md` first; using `check_code` there produces a confidently wrong
answer.

### 4. Look things up when you are unsure — `search_docs`, `search_code`, `get_symbol`

Reach for these *before* guessing an API. Recall is unreliable for a young compiler, and its
idioms are not PHP's:

- `search_docs(query, lang)` — docs, returns `docs/<lang>/<file>.md#heading (L<line>)`. Best for
  concepts ("how do I declare a typed map", "what does varint_types do").
- `search_code(query, dirs)` — real usage in `examples/`, `tests/std/`, `src/`. Best when you
  want a working pattern rather than prose. 1636 stdlib PHPT cases live here.
- `get_symbol(name, dirs)` — exact declaration + signature + `file:line`.
- `get_example(name)` — a whole runnable example (`hello`, `qt-taskboard`, `bigint`, …).
- `list_stdlib(category)` — enumerate stdlib coverage before concluding something is unsupported.

Efficiency note that pays off immediately: `search_docs` with a keyword that appears in the
docs' own vocabulary works well; grep-style guessing at C++ names (`std::vector`) does not —
the answer is usually the **universal method** form (`$arr->push()`). See
`references/typephp-idioms.md` for the idioms that differ most from stock PHP.

Pass `dirs` to scope code search at the user's own project. When the server detects a TypePHP
project (a `project.yml`, or `vendor/swoole/typephp`, or a `composer.json` requiring
`composer.json`-level `swoole/typephp`), it merges the project root and its installed framework
into the default search set automatically.

### 5. Build and run — and be honest about which rung passed

```bash
tpc project.yml --dry            # rung 1, fast sanity
tpc project.yml -O2 --no-progress    # rungs 2+3, the real build
./app                            # rung 4, the only real proof
```

Three habits that prevent confusing failures:

- **Remember the default is `-O0`.** `tpc --help` says `Optimization level (0-3, default: 0)`.
  Measured on `fib(30)`: 19.1 ms at the default vs 5.8 ms at `-O2` — a 3.3× difference from a flag
  nobody passed. Any performance claim made from a default build is wrong. `--debug` also forces
  `-O0`, so never benchmark or ship a debug build.
- **Always pass `--build-dir`.** Without it, generated `.cc` files land in the toolchain's own
  install directory (observed: `$PHP_HOME/build/extension-*.cc`, `*.cc`), mixing your artifacts
  into the SDK and making the next failure impossible to read.
- **Quote the rung in your report.** "compiles" / "links" / "runs" are three different claims.
  If you only ran `--dry`, say so.

If it fails, follow `references/debugging.md`: it maps each observed error string to its real
cause, and separates code faults from environment faults. The distinction matters because half
of the `tpc` failures in practice are environment.

If the failure is a **crash** rather than a diagnostic, switch to `references/debugging-native.md`
— there is no Xdebug here, only GDB/LLDB with a documented symbol scheme (`php_userservice__create`),
plus `--sanitize=address` for memory faults.

### 6. Before declaring done

Walk this list explicitly, and report the result rather than asserting success:

- [ ] `check_code` green on every touched `.php`
- [ ] real build (rung 2+3) run, not just `--dry`
- [ ] binary actually executed once (rung 4)
- [ ] runtime dependencies known: `dumpbin /DEPENDENTS app.exe` (Windows) or `ldd ./app`, and the
      answer to "can this be copied to another machine?" — usually no, `phpx.dll`/`php8ts.dll`
      must ship with it, unless the project uses `--nano` and only system DLLs remain
- [ ] no generated artifacts dumped into the toolchain install dir

## When the MCP server is unavailable

Do not silently degrade to plain-PHP assumptions — that produces code the compiler will reject.
Instead:

- Read the restrictions from the repo: `docs/zh-cn/INCOMPATIBLE_PHP_FEATURES.md`,
  `docs/zh-cn/COMPILER_CLI.md`, `docs/zh-cn/STD_CONTAINERS.md`, `docs/zh-cn/UNIVERSAL_METHODS.md`.
- Use `tpc --dry <file>` directly as the checker. You lose the structured `isError` bit and the
  `file:line` normalization, but the verdict is identical because it is the same compiler.
- Tell the user you are working without MCP and that the red-line summary is therefore not
  injected — this affects first-pass accuracy, not just convenience.

## Auditing code you did not write

If the task is "is this existing PHP project portable to TypePHP" rather than "write or fix this
project", the right tools are different and the obvious approach gives wrong answers:

- `check_code` runs **bin mode**, so library files without `main()` are uniformly rejected — that
  is a mode mismatch, not a compatibility verdict.
- **Per-file scanning over-reports.** Measured on `psr/log`: 2/8 files "fail" per-file, 0/8 fail
  when the directory is compiled together, because inheritance and traits cannot resolve
  across separate compilations.
- `tpc` stops at the first fatal, so a directory scan yields one diagnostic no matter how many
  files are broken.

Read `references/auditing-code.md` before doing any of this. It has the measured numbers, the
working command forms (`--mode=lib` with `=` only; `--mode lib` is parsed as a path), how to get
a real failure list, and how to classify failures by fix cost instead of by error message.

## Beyond "write and fix a program"

Four more modes come up constantly, and each has its own traps. Load the matching reference
rather than improvising:

| The task | Read | The one thing that bites |
|---|---|---|
| Building a PHP extension (`mode: ext`) | `references/ext-mode.md` | "verified" means a host PHP loads it **and** returns correct values — not `Build successful` |
| Putting a subset check in CI | `references/ci-gating.md` | `exit=1` means the gate is misconfigured (library file in bin mode), only `255` is a real failure |
| Generating TypePHP from a spec | `references/code-generation.md` | the failures that survive `check_code` are exactly the ones an LLM introduces confidently |
| Making compiled code actually fast | `references/performance.md` | default is `-O0` (3.3× slower than `-O2`); boxed `php::Var` in a hot loop is the other killer |
| Keeping rules in sync with the compiler | `references/knowledge-sync.md` | a rule without a version stamp is a rumour; `get_changelog` before upgrading, not after |

## Two things that trip up experienced PHP people

**Compile-time attributes are real here.** TypePHP has `#[Getter]`, `#[Setter]`, `#[Constructor]`,
`#[With]`, `#[Printer]`, `#[Arrayable]`, `#[Immutable]`, `#[MustUse]`, `#[Override]`, `#[NoExport]`,
`#[Hot]`/`#[Cold]`, `#[MethodsFor(Type::String)]`, and the parameter contracts `#[NotNull]` /
`#[NotEmpty]` / `#[Validate(...)]` — all expanded at compile time into ordinary methods, with no
reflection and no runtime cost. Verified working end-to-end. The catch: **they live in the root
namespace**, so inside `namespace App;` you must write `#[\Getter]` or `use \Getter;`, otherwise
they are silently ignored with no error at all. Full syntax, composition rules and measured
diagnostics: `references/attributes-reference.md`.

**The type system has sharp edges that compile fine.** `unset()` on a `std::vector` element resets
it to the zero value instead of removing it; reading a missing `std::map` key throws instead of
returning null; `$array[null] = 1` appends instead of using the `''` key; an uninitialized typed
property reads as `0` instead of raising. None of these are caught by `check_code` — they are
semantics, not syntax. See `references/type-system.md`.

**Two attribute families, same syntax, different jobs.** Method-generating attributes
(`#[Getter]`, `#[Printer]`, …) expand into code. Type annotations (`#[StdVector(Type::Int)]`,
`#[StdDict(K,V)]`, `#[Native]`) are consumed by the type checker and change what a parameter
*accepts*. Both live in the root namespace and both are silently ignored without a leading `\`.
Getting the family wrong is a common way to produce code that looks annotated but is not.
See `references/type-annotations.md`.

## Reference map

| File | Read it when |
|---|---|
| `references/verification-ladder.md` | Deciding how far to verify, or explaining why `check_code` OK ≠ works |
| `references/project-layout.md` | Creating a new project, choosing directory vs file input, writing `project.yml` |
| `references/typephp-idioms.md` | Writing PHP that must compile — the parts that differ from stock PHP |
| `references/type-system.md` | Something is slow or a cast feels wrong — what stays static vs decays to `php::Var` |
| `references/compile-time-attributes.md` | Removing boilerplate: `#[Getter]`, `#[Constructor]`, `#[MethodsFor]`, `#[Immutable]` |
| `references/attributes-reference.md` | **Complete attribute reference** — every built-in attribute, exact syntax, measured diagnostics |
| `references/type-annotations.md` | **Complete type-annotation reference** — `#[StdVector]`…`#[StdDict]` contracts and `#[Native]` |
| `references/incompatibility-taxonomy.md` | A feature is unsupported — is it permanent, or coming later? |
| `references/debugging.md` | A build or run failed and you need the actual cause, not a guess |
| `references/debugging-native.md` | A crash, a memory fault, or you need to step through generated C++ (GDB/ASAN) |
| `references/auditing-code.md` | Auditing libraries/vendored code, judging migration feasibility, or any bulk scan |
| `references/ext-mode.md` | `mode: ext` — building and loading a PHP extension |
| `references/ci-gating.md` | Designing a fast gate for a repo or pipeline |
| `references/code-generation.md` | Generating TypePHP from a spec, or porting a small utility |
| `references/performance.md` | A hot path seems slow, or you need to know if code will actually be fast |
| `references/knowledge-sync.md` | Upgrading tpc, writing rules down for a team, or a doc seems wrong |
| `references/mcp-tools.md` | Choosing the right MCP tool, or the user asks what the server can do |
| `scripts/preflight.sh` / `scripts/preflight.bat` | "Nothing compiles" on an unfamiliar machine |
| `scripts/audit-dir.sh` / `scripts/audit-dir.bat` | Bulk-scanning PHP you did not write. Pass a `project.yml` dir for whole-app, a plain dir for lib mode |
| `evals/attribute-regression/run.php` | Re-verifying the attribute/type-annotation claims in this skill after a compiler upgrade. `php run.php evals/attribute-regression/cases` for the 25 dry cases (`--build` adds the 5 run cases) |
