# "Unsupported" is four different things — and the difference decides your next move

The compiler repo classifies every incompatibility into one of four categories
(`docs/en/PHP_INCOMPATIBILITY_CLASSIFICATION.md`). Collapsing them into a single "not supported"
is the most common mistake in this domain, because the correct reaction is different in each case.

## The four categories

| Category | Meaning | What you should do |
|---|---|---|
| **Hard Limit** | conflicts with the AOT execution model; exact PHP compatibility would need unreasonable runtime mirroring | **rewrite permanently** — waiting will not help |
| **Intentional Rule** | implementable, but deliberately rejected to keep the AOT model explicit and optimizable | **rewrite** — it is a language rule, not missing work |
| **Pending** | technically implementable, currently unsupported | **work around now, revisit later** — check the changelog |
| **Partial** | exists, but diverges from PHP in specific edge cases | **learn the documented boundary**, usually keep the code |

This taxonomy comes with a documentation rule worth adopting in your own notes: never write
"unsupported" without also naming the category and the reason. "Unsupported" alone tells a reader
nothing about whether to refactor or wait.

## The ones that change design decisions

Measured / documented cases, grouped by what you should actually do:

**Rewrite permanently (Hard Limit / Intentional Rule)**

| Feature | Why |
|---|---|
| `eval()` accessing AOT local variables | AOT locals are C++ stack variables; Zend VM code cannot see that frame. Data exchange must go through return values or `$GLOBALS` |
| `unset($nativeTypedVar)` | native typed locals are C++ variables, not symbol-table zvals — cannot be deleted |
| executable statements in global scope | the compiler deliberately has no global execution block; initialization order and side effects stay explicit |
| reassigning an inferred native local to an incompatible type | the cost of native type optimization; use `std::any()` when you need PHP-style type changes |
| structural mutation of a `std` container inside `foreach` | native C++ iterators are invalidated; non-structural element updates are allowed |
| automatic reference inference for dynamic calls | a runtime callable's signature is unknown; `std::ref()` / `toRef()` must be explicit |

**Work around now, revisit later (Pending)**

These are the ones people wrongly give up on. All are implementable and explicitly tracked:

| Feature | Status note |
|---|---|
| `$$var` (variable variables) | needs a function-local symbol-table mirror — planned, not an impossibility |
| closure / arrow fn returning by reference | needs `ReturnRef` in closure metadata |
| `echo` with assignment expressions | needs expression lowering that preserves order and returns the value |
| nested `match` in arm conditions | needs recursive match lowering |
| `foreach` by-ref targets beyond simple variables | needs explicit lvalue/reference modeling |
| `foreach` list destructuring with by-ref items | same |
| dynamic `ClassName::class` | runtime class-name resolution |
| first-class callable in a nullable `Closure` typed property | needs refcount/typed-property write handling |
| PHP 8.5 `#[NoDiscard]` | warning behaviour parity not yet implemented |
| `static::class` in true compile-time constant contexts | runtime contexts work |

If a task hits one of these, say "currently unsupported, implementable later" rather than
"TypePHP cannot do this" — the user's decision changes: workaround now, or wait for a release.

**Keep the code, learn the boundary (Partial)**

| Feature | Boundary |
|---|---|
| `eval()` | executes via Zend VM, but cannot see compiled locals |
| dynamic calls / callbacks | work through the Zend fallback; by-ref args still need `std::ref()`, native-call optimization not guaranteed |
| dynamic properties | read/write via runtime property API; native optimization not guaranteed |
| native typed properties | fast paths may not preserve every PHP dynamic state transition |
| Reflection metadata | promotion and asymmetric visibility preserved; other AOT metadata may be incomplete |
| dynamic dimension assignment | ordinary paths correct; callback rebinding and exact diagnostic ordering not promised |

## Why this matters for an audit

When you find a failing file, the category decides the estimate:

- Hard Limit → that file needs a **redesign**, or must be excluded from the compiled set.
- Intentional Rule → usually a **mechanical fix** (move code into a function, add `std::any()`,
  make the reference explicit).
- Pending → **temporary workaround**, and the code may become compilable — do not budget a
  permanent rewrite.
- Partial → probably **no change needed**; understand where it diverges before promising behaviour.

A migration estimate that counts all four as "incompatible files" is wrong in both directions:
it over-charges for Pending items and under-charges for Hard Limits.

## A doc-hygiene note worth copying

While checking this classification I found the Chinese `docs/zh-cn/README.md` links to
`PHP_INCOMPATIBILITY_CLASSIFICATION.md`, but only `docs/en/` has that file — the `zh-cn` copy does
not exist. The link is dead for Chinese readers. It is the same translation-desync pattern as the
two quickstarts carrying an identical global-`require_once` example.

When you rely on a classification or a rule, resolve the link before trusting it. See
`knowledge-sync.md` for the general pattern.
