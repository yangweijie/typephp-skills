# Auditing code you did not write — libraries, vendored code, migration candidates

Everything here was measured on tpc v0.9.5 / Windows x64. It answers one question: **when you
point TypePHP at code that was never written for it, how do you get a trustworthy answer?**

The short version, if you only read one line: run
`scripts/audit-dir.sh` (or `audit-dir.bat` on Windows) on **directories**, and treat any
single-file "Trait/class not found" result as noise. Pass a directory containing `project.yml`
and it compiles the manifest; pass any other directory and it scans in lib mode.

For a worked example of the whole flow on a real library, run the script against
`vendor/symfony/polyfill-mbstring` (expected: 1 real failure, then 3 data files surface via
exclusion). For the app/library mix, try `examples/qt-taskboard` (whole-app PASS, and its
`php-src/` reports `N/A` because it holds only a `.stub.php`).

## The trap that ruins naive audits

`check_code` always runs tpc in **bin mode**. Bin mode requires a global `main()`. Library code
has no `main()`, so every single file is rejected — and it looks like a compatibility verdict:

```
The Embed SAPI requires a global `main()` function
```

Measured on `vendor/psr/log/src` (8 files): MCP `check_code` → **8/8 FAIL**, ~186 ms each.
The same 8 files with `tpc --dry --mode=lib` on the whole directory → **0 failures**.

If you audit a library with `check_code` and report the failures, you have produced a
completely wrong answer with authoritative-looking evidence. This is the single most expensive
mistake in this workflow.

**Rule: `check_code` is for application entry files (things with `main()`). For library code,
call `tpc` directly with `--mode=lib`.**

## Per-file scanning is not a valid proxy for directory scanning

Whole-directory compilation resolves cross-file inheritance, traits, and interfaces. Per-file
compilation does not, so anything that `extends` or `use`s a sibling reports "not found":

```
Fatal error: Trait `Psr\Log\LoggerTrait` not found
Fatal error: Class `NullLogger` inherits from a non-existent class `Psr\Log\AbstractLogger`
```

Measured twice, reproducibly, on `psr/log`:

| Scan mode | Result |
|---|---|
| per-file, lib mode | **2 / 8 FAIL** |
| whole directory, lib mode | **0 FAIL** |

So per-file scanning of library code carries roughly **25% false positives** on a small library
with ordinary inheritance. The number will vary by codebase, but the direction is always the
same: per-file over-reports.

**Rule: audit directories, not files. Only fall back to per-file when a directory is too large
to process, and treat every "not found / inherits from non-existent" result as suspect.**

## Syntax details that waste a round each

| Wrong | Right | Symptom |
|---|---|---|
| `-m lib` | `--mode=lib` | `Fatal error: path not exists: lib` — the flag is parsed as the input path |
| `--mode lib` | `--mode=lib` | same |

The `--mode` option only accepts the `=` form. `-m` works only in contexts where the parser is
not expecting an input positional, which is not the case here.

## How to get a full failure list, not just the first

tpc stops at the first fatal. One directory scan therefore yields **one** diagnostic, no matter
how many files are broken. If you ask "how many files are incompatible?" you get 1 for the price
of a scan and no more.

Two ways out, with different tradeoffs:

**A. Iterative exclusion** — delete (or move) the offending file and rescan, repeat.
`scripts/audit-dir.sh --max-exclusions N` automates this. Measured on `nikic/php-parser` (271
files):

```
ITER 1: stray code -> excl TokenPolyfill.php
ITER 2: stray code -> excl Lexer.php
ITER 3: stray code -> excl ArrayItem.php
ITER 4: stray code -> excl ClosureUse.php
ITER 5: stray code -> excl DeclareItem.php
ITER 6: stray code -> excl ArrayItem.php     ← already excluded, reported again
```

That last line is the catch: excluding a file causes cascading failures elsewhere, and the
compiler re-reports files you already removed. So the raw list **mixes two very different
problems** — genuine incompatibility and damage you caused by excluding. Never present it as
"these files are incompatible."

**B. Per-file scan** — get every file's verdict in one pass, but pay the ~25% false-positive
rate described above. Use it to *narrow* candidates, never as the final answer.

Practical combination: per-file scan to find the suspicious set, then confirm each candidate by
whole-directory compile with that file present. A file that fails per-file but passes in-directory
is a false positive; drop it.

## Cost, measured

| What | Size | Time |
|---|---|---|
| whole-directory scan, small lib | 8 files | ~240–270 ms |
| whole-directory scan, `psr/log` | 8 files | ~250 ms |
| whole-directory scan, `nikic/php-parser` | 271 files | **386 ms** |
| MCP `check_code`, per file | 1 file | ~186 ms |

Whole-directory scanning is fast enough for a pre-commit hook even on a few hundred files.
The MCP round-trip is ~186 ms per file when it is applicable at all — that is fine for an agent
checking the file it just edited, and the wrong tool for a 300-file sweep.

## Reading the verdicts

Genuine failures seen in real libraries, and what they actually mean:

| Message | Library | Real cause | Cost to fix |
|---|---|---|---|
| `All execution code must be within a function, found stray code` | `nikic/php-parser` `TokenPolyfill.php:5` | conditional `function_exists()` guard at file scope | **structural** — the file's whole loading pattern has to change |
| `Unsupported statement: Stmt_Return` | `symfony/polyfill-mbstring` `caseFolding.php:3` | a file whose body is `return [...];` — a data file, not code | **cheap** — it should not be compiled as code at all |
| `Trait X not found` / `inherits from a non-existent class` | any library, per-file scan | sibling file not in the compilation unit | **not a real failure** — rescan as a directory |

The important pattern: **the same word "FAIL" hides two orders of magnitude of effort.** A data
file that should be excluded from `sources` is minutes of work; a file-scope execution guard is a
refactor. Classify by *fix cost*, not by *error message*, or your migration estimate will be
wrong in both directions.

## The judgement the docs make for you: do not compile `vendor/`

Before scanning anything, know the official position (`docs/zh-cn/best_practice.md`): **third-party
frameworks and libraries in `vendor/` should stay on Composer autoload and not be compiled.** The
recommended shape is a whitelist — put only the specific vendor subdirectories you need into
`sources`, and use `ignore` for individual files that refuse to compile:

```yaml
sources:
  - ./src
  - ./vendor/topthink/think-helper/src
  - ./vendor/topthink/think-orm/src
ignore:
  - ./vendor/topthink/think-helper/src/functions.php   # explicit path, no globs
```

This reframes what an audit is for. You are usually not asking "can I compile all of vendor?" —
you are asking **which few directories are worth compiling**, and the rest stays dynamic. An audit
that reports "60% of vendor fails" is answering a question nobody should be asking.

Two hard constraints when you do pull vendor code in:

- **the whole inheritance chain must be compiled** — a controller extending a framework base class
  extending another framework class requires all three in `sources`;
- **Templates, config files, and anything with inline HTML cannot be compiled at all** (no stray
  code, no embedded HTML). They are `include`/`require`d dynamically, which means they belong in
  `embedded-files` for a `bin` build, not in `sources`.

## Auditing a project that mixes app and library code

Most real projects have both, and the right unit of analysis differs per part:

| The target | Correct command | Why |
|---|---|---|
| A project directory containing `project.yml` | `tpc --dry <dir>/project.yml` | the manifest already lists `sources`, `cpp-src`, `ignore`; compiling the manifest is the only faithful check |
| A library directory with no manifest | `tpc --dry --mode=lib <dir>/` | whole-directory so inheritance and traits resolve |
| An entry file | `check_code` | gives the structured verdict and the `isError` split |

`scripts/audit-dir.sh` / `audit-dir.bat` pick the mode automatically: pass a directory with a
`project.yml` and they compile the manifest (whole-app mode), otherwise they scan in lib mode.

**Do not decompose an app into per-directory scans.** Measured on `examples/qt-taskboard`:

```
qt-taskboard/
├── main.php          ← entry
├── app/              ← lib mode: PASS (3 files)
├── php-src/          ← only taskboard.stub.php → "No valid source file found"
└── cpp-src/          ← C++, not PHP
```

Scanning `php-src/` returns `No valid source file found` — **neither PASS nor FAIL**. It is a
`.stub.php`-only directory, which declares an ABI and is not a compilable source. Reporting that
as a compatibility failure would be wrong; reporting it as PASS would also be wrong, because the
directory was never actually compiled. The scripts emit `N/A` for this case and for any empty
directory.

The whole manifest compiles cleanly (5 PHP files, ~300 ms), which is the answer that matters.

## Two verdicts that are neither PASS nor FAIL

Distinguish these before counting anything:

| Output | Meaning | How to report |
|---|---|---|
| `No valid source file found` | nothing compilable was collected — stubs only, or the wrong directory | **N/A**, not a failure |
| `The Embed SAPI requires a global main() function` | you pointed a bin-mode tool at library code | **tool mismatch**, re-run with `--mode=lib` |

Both look like the tool is telling you something about compatibility. Neither is.

## Where `check_code` genuinely shines

It is not the wrong tool, just a narrow one. It is right when:

- the file is an application entry or a file reachable from one (has `main()` in its compilation unit);
- you want the `isError` bit to tell "your code is wrong" from "the tool/environment broke";
- an agent is iterating on the file it just wrote and needs a 200 ms verdict;
- you need a stable `file:line` diagnostic format rather than a PHP stack trace.

It is wrong when: auditing libraries, sweeping hundreds of files, or asking anything about
compile/link/runtime behaviour (it never compiles).
