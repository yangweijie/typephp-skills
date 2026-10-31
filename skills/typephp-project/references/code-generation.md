# Generating TypePHP from scratch, and why the loop is unusually short

Most "have an LLM write code" tasks are limited by verification cost: the model produces
something, and checking it costs more than producing it. TypePHP inverts that ratio.

## The numbers that make this work

| Step | Cost |
|---|---|
| `check_code` per file | 150–270 ms |
| whole small project `--dry` | ~200–500 ms |
| red-line summary (injected, no call needed) | 0 |
| real build (rung 2+3) | tens of seconds |

Verification at rung 1 costs roughly as much as reading the code. That is the precondition for a
generate-and-converge loop to actually converge instead of drifting.

## Why the rule set is small enough to exhaust

The restrictions are a short, enumerable list (see `typephp-idioms.md`), not a fuzzy style guide:

- global scope is declaration-only
- `main(): void` in bin mode
- one local, one inferred type
- no `$$var`, no `Closure::bind*`, no `declare(ticks)`
- non-empty `switch` cases must terminate

That is checkable in one pass and injectable in ~1.6 KB. Compare with porting to a language whose
"don't do this" list is a book.

## The loop

```
write (red-line summary is already in context)
  → check_code
    → FAILED? read the file:line, fix that one thing, repeat
      → OK on all files → real build → run
```

Because the compiler stops at the first error, N mistakes cost N rounds. That is the argument for
loading the rules first rather than iterating reactively — each unlearned rule is a full round.

## Where generation genuinely pays off

**Narrow, well-specified transforms** — the sweet spot:

- rewrite a hot function from interpreted PHP into AOT-friendly form (typed locals, no dynamic lookup)
- port a small Python/JS utility whose logic is simple and whose dependencies are few
- generate `.stub.php` + `cpp-src` bridge skeletons from a written API description
- turn a spec into a CLI: "read CSV, group, sum, sort" is a 20-minute task with a converged loop

**Poor fits** — do not fight these:

- anything needing Composer autoloading as its load mechanism (the source list *is* the linker)
- heavy dynamic dispatch, `eval`, variable variables — the compiler will refuse, and rewriting to
  satisfy it usually destroys the reason you wanted the code
- UI/framework code with large surface area; the win is in hot paths, not in glue

## A caution specific to generated code

The failure modes that survive `check_code` are exactly the ones an LLM introduces confidently:

- calling a function that does not exist (`echoo`) → `check_code` says OK
- referencing a class never included in `sources` → OK
- `$line->trim()` on a scalar from I/O → OK
- forgetting `use App\X;` for a namespaced class → OK

All four were measured failing only at rung 4. So a generation pipeline that stops at "check_code
green" will ship broken code with a clean log. Budget one real build + one run per generated unit,
or you are not verifying.

## Prompt shape that works better than instructions

Rather than restating rules (MCP already injects them), give the model the *shape* to produce:

- a single `main(): void` with named helper functions below it
- explicit return types on every function — keeps inference clean
- one class per file under `src/`, listed via `sources: [src]`
- no `require`/`include` anywhere

Then let `check_code` disagree. Corrections cost 200 ms; a bad guess at the rules costs a round
either way.

## When the MCP server is absent

Generation degrades but still works: use `tpc --dry <file>` directly and read
`docs/zh-cn/INCOMPATIBLE_PHP_FEATURES.md` once at the start of the session. What you lose is the
automatic red-line injection, which is precisely the part that improves first-pass accuracy — so
expect more rounds and say so if you are reporting a timeline.
