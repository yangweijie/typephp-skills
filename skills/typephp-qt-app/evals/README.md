# evals — behavioural, not executable

Unlike `typephp-project/evals/`, which runs compiler assertions and can be executed by a script,
these eight cases test **what the agent decides**, not what the compiler does. There is no runner,
and that is deliberate: grading one requires a model or a human reading the answer against
`expected_output`.

## Format

```json
{
  "skill_name": "typephp-qt-app",
  "evals": [
    { "id": 1, "prompt": "...", "expected_output": "...", "files": [] }
  ]
}
```

`expected_output` is a rubric, not an exact match. A response passes when it hits every
load-bearing point in it; wording, ordering and extra detail do not matter.

## The eight cases and what each one is actually guarding

| # | Case | The failure it catches |
|---|---|---|
| 1 | Greenfield todo app | Reaching for a hand-written C++ bridge when the package would do — the most expensive wrong turn in this skill |
| 2 | Wire an existing `TaskStore` into a window | Inventing a new state model instead of mapping the user's own class onto `view()` |
| 3 | `LNK2019` on `php_board_create` | Blaming `windeployqt` for a symbol-name mismatch, and not noticing the package route has no bridge to mismatch |
| 4 | Master-detail layout | Naming widgets with no regard for how the package maps them (`hbox`/`split`/`table`) and for the id-based refresh |
| 5 | Click crashes, unit tests green | Not recognising the AOT closure-arity trap, and treating a green suite as evidence — the skill's central claim |
| 6 | `PHPX runtime library was not found` | Reading it as a code regression when it is toolchain resolution ("nothing changed, worked yesterday") |
| 7 | Embedded web view with JS | Assuming one backend everywhere instead of branching on `webViewBackend()` |
| 8 | Shrink a 25 MB binary | Promising that `--nano` shrinks Qt, when the bulk is Qt + ICU |

## How to run them

1. Start a session with the skill installed and nothing else from this repo in context.
2. Paste one `prompt` verbatim. Do not add hints.
3. Score the answer against `expected_output` point by point.
4. Record pass/fail per case. A single miss on a load-bearing point is a fail — these are traps,
   not trivia.

Run the set again after any change to `SKILL.md`, and after upgrading `yangweijie/typephp-qt`
(packagist, latest v0.9.5): case 3, 6 and 8 all depend on package/toolchain behaviour that can move
between releases.

## Last run

2026-11-02, after the 0.9.5 end-to-end verification. Method: one fresh subagent per case, given only
`SKILL.md` (references on demand), answered in Chinese; graded against `expected_output`.

**8/8 pass.** Two grading notes:

- Case 3: the rubric lists `runtime.ini`/`PHPRC` among the causes to rank, but that is a runtime-stage
  concern — for a link-stage `LNK2019` naming it would be wrong. The passing answer correctly excluded
  it; consider rewording the rubric.
- Case 5: the rubric asks for a Reflection-based arity probe at registration. The passing answer fixed
  it by adding the parameter and prescribing `--selftest`, which is the simpler correct fix; treat the
  Reflection probe as an alternative, not a requirement.

Observed weakness this run exposed: both case 1 and case 2 guessed `WidgetTree::table()`'s shape wrong
(real signature is `table(array $columns, array $rows, array $props = [])`, row ids via a `row_ids`
prop). SKILL.md now pins those signatures directly, so re-run cases 1 and 2 after any package upgrade
that touches `WidgetTree`.
