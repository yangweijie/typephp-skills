# Keeping the rules in sync with the compiler

TypePHP moves fast and it is young. A rule that was correct last month can be wrong this month,
and nothing in your project will tell you — the same code keeps compiling, or suddenly stops.

The compiler repo shows a live example: `use native_types` existed and was removed in 0.8.0. Two
`docs/` quickstarts (zh + en) shipped an example with a global `require_once` that has been a hard
error for some time; both were last touched in a translation-split commit and never re-checked.
Neither problem announces itself.

## What drift actually looks like

Three distinct failure shapes, each needing a different fix:

| Shape | Symptom | Detection |
|---|---|---|
| Rule removed/relaxed | code that used to fail now works; your notes are needlessly restrictive | changelog + `list_restrictions` |
| Rule added | code that used to work now fails | gate A across the repo |
| Documentation stale | you follow docs and get an error that the docs say cannot happen | try it, don't trust the prose |

The third is the most expensive because it burns trust: the user follows the official quickstart,
hits `All execution code must be within a function`, and concludes the toolchain is broken. When
this happens, check whether the doc predates the rule before debugging the code.

## Cheap practices that actually work

**Pin the version in anything you write down.** `get_index_info` returns `tpc_version`, `git_commit`
and a `staleness` line. Record those next to any conclusion, note, or AGENTS.md snippet you hand
to a team. A rule without a version is a rumour.

**Read `get_changelog` before you upgrade, not after.** It gives the latest section or a specific
version prefix (`get_changelog(version: "0.8")`). One call before a bump answers "did anything I
rely on change?" — which is otherwise unanswerable.

**Re-run the subset gate as a pre-upgrade sweep.** `check_code` across the repo on the *old*
version, upgrade, run again, diff. Newly-failing files are the breaking changes that matter to
you, filtered out of the whole changelog. Costs ~200 ms per file.

**Prefer `list_restrictions` over your own notes.** It is generated from `docs/` at call time, so
it tracks the checkout. Hand-written team notes do not. If you maintain a summary, note where it
came from and when.

## When you write rules down

If you snapshot the red lines into an `AGENTS.md` or a team doc, the snapshot will drift. Two ways
to keep it honest:

- make the doc **point** at the source (`list_restrictions`, `docs/zh-cn/INCOMPATIBLE_PHP_FEATURES.md`)
  rather than restating it, so there is one thing to update;
- if you must restate, stamp it: `# rules as of tpc 0.9.5 (git 4cbb9c0d) — check get_index_info`.

The second is worse in principle and better in practice for humans who will not call a tool before
writing code. Choose deliberately.

## Auditing docs themselves

A doc statement is a claim; `check_code` is cheap enough to test it. The pattern that found two
real defects during this skill's authoring:

1. take the example verbatim from the doc;
2. run it through `check_code` (or `tpc --dry`);
3. if it fails, the doc is stale — verify the fix compiles before reporting, then report both.

Two measured cases, worth knowing because they are still live in the repo:

| Doc | Claim | Reality |
|---|---|---|
| `docs/{zh-cn,en}/QUICKSTART.md:86` | `require_once 'Calculator.php';` above `main()` | `All execution code must be within a function` |
| `docs/{zh-cn,en}/QUICKSTART.md:122` | "runs standalone without a PHP environment" | binary needs `phpx.dll` / `php8ts.dll` at runtime |

Both languages carry the identical defect because the second was translated from the first. When
you fix a doc, fix every language copy in the same change or it comes back.

**A third shape: the Chinese index links to a file only English has.** `docs/zh-cn/README.md` lists
`PHP_INCOMPATIBILITY_CLASSIFICATION.md` among its authoritative documents, but `docs/zh-cn/` does
not contain it — only `docs/en/PHP_INCOMPATIBILITY_CLASSIFICATION.md` exists. A Chinese reader
following the index hits a dead link, and the taxonomy it describes (Hard Limit / Intentional Rule
/ Pending / Partial — see `incompatibility-taxonomy.md`) is exactly what you need to judge whether
a failure is permanent.

When a `zh-cn` link 404s but the `en` sibling exists, read the English one rather than concluding
the topic is undocumented.

## Documentation that is authoritative vs. historical

`docs/zh-cn/README.md` splits its own contents explicitly: the "current authoritative" list
(compatibility checklist, classification, CLI, build modes) versus a "research and historical"
group (`hhvm-review.md`, `kphp-review.md`, `peachpie-review.md`, patent drafts) that is kept for
background and **must not be read as a current feature list**.

That distinction saves a specific failure: a historical doc describing how `kphp` solved something
may read like a description of how TypePHP works. Check which list a file is in before quoting it,
and prefer the compatibility checklist plus PHPT tests as the source of truth.

## The limits of this

None of it removes the need to re-verify after an upgrade. What it buys you is knowing *where* to
look: the changelog narrows the whole surface to a paragraph, and a gate sweep narrows it further
to the files that actually broke. That is the difference between a 10-minute upgrade and an
afternoon of bisecting compiler behaviour.
