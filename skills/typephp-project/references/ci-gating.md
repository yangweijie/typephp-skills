# CI gating — using TypePHP as a guard rail, not a build

`tpc --dry` and `check_code` are cheap enough to run on every change (150–270 ms per file).
That makes them suitable as a *fast* gate that catches the TypePHP-subset class of errors before
a real build ever starts. It is not a replacement for building.

## Exit codes, measured — read this before writing a gate

| Situation | exit |
|---|---|
| File passes | **0** |
| **bin-mode tool pointed at library code** (`requires a global main()`) | **1** |
| Real diagnostic (syntax error, type mismatch, forbidden construct) | **255** |
| File does not exist | **255** |

The `1` vs `255` split matters: a naive `if tpc …; then ok; else fail; fi` turns every library
file into a failing build. `exit=1` means *the gate is configured wrong for this input*, not that
someone broke the code. Treat it as a configuration error and fix the gate, don't page anyone.

`check_code` collapses all of this into one boolean for you: `isError: true` = tool/environment
problem, flag absent = your code's verdict. That is exactly the split a gate wants, which is the
main argument for using MCP in CI rather than raw `tpc`.

## Two gate designs, different costs

**Gate A — subset check only (fast, catches most authoring mistakes)**

```
changed .php files  →  check_code (or tpc --dry)  →  fail on 255 / FAILED
```

Catches syntax, parse, static type inference, forbidden constructs, global-scope violations.
Misses everything downstream: undefined classes/functions, link errors, runtime capability,
missing DLLs. A green gate here means "this file is inside the TypePHP subset", nothing more.

**Gate B — subset check + real build (slow, catches integration)**

```
gate A  →  tpc project.yml  →  (optionally) run the artifact once
```

Gate A exists to make gate B fail fast and fail *cheaply*. Do not skip A: a real build takes tens
of seconds and links a full PHP runtime, and you want the 200 ms answer first.

Neither gate proves correctness. Gate B still cannot see runtime capability gaps (`PDO` without
a driver) — only actually running the binary does that.

## What to gate on, concretely

| Input type | Command | Treat `exit=1` as |
|---|---|---|
| App `.php` (compilation unit has `main()`) | `check_code` or `tpc --dry <file>` | real failure |
| Library `.php` | `tpc --dry --mode=lib <dir>/` — **directory**, not file | n/a (lib mode has no `main()` requirement) |
| Whole project | `tpc --dry <dir>/project.yml` | real failure |

Never gate a single library file. Per-file compilation cannot resolve cross-file inheritance and
produces ~25% false positives (see `auditing-code.md`).

## Version drift is the silent gate breaker

A gate that passed on tpc 0.9.5 can fail wholesale after an upgrade, and the failure looks like
"the team suddenly wrote bad code". Two cheap protections:

- call `get_index_info` in CI and record `tpc_version` + `git_commit` alongside the gate result —
  when a gate result changes, you can tell whether the compiler moved;
- call `get_changelog` before bumping, and re-run gate A across the repo as a pre-upgrade sweep.

`use native_types` was removed in 0.8.0; that class of change silently invalidates code that was
correct last week. The changelog is the cheapest way to see it coming.

## Environment preconditions

Gate A via `check_code` auto-repairs the Windows MSVC path (vswhere), so it survives a bare CI
shell. Raw `tpc` does **not** — it needs `vcvars64` or the equivalent, otherwise every file fails
with `C1083 cannot open include file "malloc.h"`, which reads like a code problem and is not.
Run `scripts/preflight.sh` / `preflight.bat` once per job before the gate.

## Where a gate earns its keep

Worth it when more than one person writes TypePHP, or when an agent writes code that a human
reviews. The value is that the subset rules stop being tribal knowledge and become a machine
check — the red-line summary injected by MCP helps the author get it right the first time, and the
gate catches what slips through.

Not worth it for a single-author throwaway project: the preflight and version-drift bookkeeping
costs more than it saves.
