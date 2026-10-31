# typephp-mcp tool map — 12 tools, and when each one earns its call

The server speaks MCP over stdio, runs locally, sends nothing out, and does not need a PHP
interpreter to answer read-only queries (only `check_code` needs `tpc`).

## The four that prevent wasted rounds

| Tool | Call it when | Output |
|---|---|---|
| `list_restrictions` | **before writing any TypePHP** | the red-line rules, ~1.6 KB. Topics: `structure`, `types`, `refs`, `objects`, `control`, `runtime`, `std`, `stub`, `build`. Empty topic returns everything |
| `get_build_config_help` | before authoring/editing `project.yml`, adding sources, or choosing a mode | field reference for the three modes, CLI flags, stub contract |
| `search_docs` | a concept question ("how do typed maps work", "what is varint_types") | doc chunks with `docs/<lang>/<file>.md#heading (L<line>)` citations; `lang` = `zh-cn` (default) / `en` / `all` |
| `check_code` | after every meaningful edit to a `.php` | `OK/FAILED stage=generate ... diagnostics=N` plus `- [error] file:line message` |

Two properties of `check_code` worth remembering:

- It accepts **one `.php` file**: absolute, or relative to the MCP repo root. Directories and
  `project.yml` are refused — deliberately, because parsing a project config can start a real
  runtime build even under `--dry`. Don't work around it.
- `isError` distinguishes *your code is wrong* (flag absent) from *the tool/environment failed*
  (`isError: true`). That bit is the main thing it has over bare `tpc`, whose failures are all
  `exit=255`.

Absolute paths **outside** the compiler repo work (measured 264 ms for a file in another
project), so there is no need to stage a file into the repo before checking it.

**`check_code` always runs bin mode, and that is a hard limit you cannot configure away.** Bin
mode requires a global `main()`. Point it at a library file and every file comes back rejected:

```
The Embed SAPI requires a global `main()` function
```

Measured: all 8 files of `vendor/psr/log/src` "FAIL" through `check_code`, while
`tpc --dry --mode=lib` on the same directory passes all 8. The failures are a mode mismatch, not
a compatibility verdict. For library or vendored code, call `tpc` directly and see
`auditing-code.md`.

## Code lookup

| Tool | Call it when | Notes |
|---|---|---|
| `search_code` | you want a **working pattern**, not prose | greps `examples/`, `tests/std/`, `src/`; returns `file:line` + enclosing declaration, max 3 hits per file |
| `get_symbol` | confirming a name/signature exists | exact name only (`TypePhp\Translator`, `Class::method`); reports coverage truncation explicitly rather than silently skipping |
| `get_example` | you want a whole runnable program to adapt | `hello`, `qt-taskboard`, `bigint`, `shop-fpm`, … |
| `list_stdlib` | before concluding something is unsupported | 1636 PHPT cases across `array`, `strings`, `core`, `file`, … |

Pass `dirs` (absolute) to scope any of the lookup tools at the user's own project instead of the
bundled repo. When the server detects a TypePHP project — `project.yml`, or `vendor/swoole/typephp`,
or a `composer.json` requiring `swoole/typephp` — the project root and its installed framework are
merged into the default search set, so this is often unnecessary.

## Contract and metadata

| Tool | Call it when |
|---|---|
| `get_stub_api` | inspecting `.stub.php` ABI declarations; without a path it lists all stub files |
| `get_changelog` | the user relies on behaviour that may have changed between versions |
| `list_topics` | you don't know what is documented, so you don't know what to search |
| `get_index_info` | you suspect version drift: returns repo root, tpc version, git commit, doc counts, and a `staleness` line |

## Environment knobs that change your results

| Variable | Effect |
|---|---|
| `TYPEPHP_MCP_ROOT` | **tool resources** (the compiler checkout), *not* the user's project. Must be set explicitly when running a deployed binary, because the AOT build bakes in the build machine's path |
| `TYPEPHP_MCP_TPC` | which `tpc` binary `check_code` runs. Pin it at the release package (`$PHP_HOME/tpc.exe`); the repo-root build is known to fail with `0xC0000139` on this machine |
| `TYPEPHP_MCP_PROJECT_ROOT` | adds the user's project to the search set when the client sends no MCP roots. Separator `;` (Windows only accepts `;`) |
| `TYPEPHP_MCP_COMPILE_TIMEOUT` | default 120 s; on timeout the whole process tree is killed and the temp dir cleaned |
| `TYPEPHP_MCP_COMPILE_MEMORY_LIMIT_MB` | default 4096; POSIX only |

## Known rough edges

- `get_symbol("stdMap")` returns nothing while `search_docs("map")` has the full `std::orderedMap`
  documentation. Different semantics (declaration vs prose), not a bug — pick the other tool.
- Tool descriptions total ~9.5 KB; the 1.6 KB red-line summary is also injected into
  `initialize.instructions`, so it is often already in context. Check before calling
  `list_restrictions` a second time.
