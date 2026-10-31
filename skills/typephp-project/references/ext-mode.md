# `mode: ext` — building a PHP extension

An extension is not a standalone program. It is a `.dll`/`.so` that a **host PHP** loads, and
that changes both the build and the meaning of "verified". Measured end-to-end on
`examples/promo-ext` with tpc v0.9.5 / Windows x64 / PHP 8.5.11 ZTS.

## The verification chain is longer than bin mode

| Rung | What | Command | promo-ext result |
|---|---|---|---|
| 1 | generate | `tpc project.yml --dry` | PASS |
| 2+3 | compile + link | `tpc project.yml --no-progress` | `Build successful: promo.dll` (65,536 B) |
| 4a | **loads into a host** | `php -d extension=…/promo.dll -r 'var_dump(extension_loaded("…"));'` | `true` |
| 4b | **behaves correctly in the host** | run the caller script | 6/6 cases correct |

Rung 4 in bin mode means "run the binary". In ext mode it means **"a real PHP process loads the
module and the exported functions return the right values"**. Skipping that and stopping at
`Build successful` is the ext-specific version of the same mistake — a `.dll` that links fine but
never registers is indistinguishable from a working one until you load it.

## Worked example: `examples/promo-ext`

```
promo-ext/
├── project.yml          mode: ext, sources: [src]
├── src/promo.php        defines promo_quote(), PROMO_VERSION
└── demo.php             host-PHP caller — NOT compiled, run by the interpreter
```

`demo.php` is ordinary PHP run by the host; only `src/promo.php` is compiled. That split is the
point of ext mode: the hot logic ships as native code, the surrounding app stays interpreted.

Verified run:

```bash
php -d extension=D:/Temp/ext-test/promo.dll demo.php
```

```
扩展 typephp_promo：已加载，版本 1.0.0

A. 黄金会员 + SAVE20
  小计 539.00  会员 -53.90  满减 -80.00  券 -20.00  运费 +0.00  =>  应付 385.10
...
F. 不存在的券码
  小计 539.00  会员 -53.90  满减 -80.00  券 -0.00  运费 +0.00  =>  应付 405.10
  券 FAKE 未生效：unknown_coupon
```

Note `extension_loaded('typephp_promo')` is true — the module name comes from `name:` in
`project.yml` prefixed with `typephp_`, not from the output filename. Confirm the real name
before writing any `extension=` line; guessing from the `.dll` basename will silently no-op.

## Things that differ from bin mode

| Concern | bin | ext |
|---|---|---|
| `main()` | required | **not used** — no entry point, functions are exported |
| Output | executable | shared library + `.lib`/`.a` import lib |
| `ext-deps` | module deps | **load-order deps**: Zend refuses to load your module if a listed extension is missing |
| `info:` block | ignored | written into the module entry, shown in `phpinfo()` |
| Verification | run the binary | load into a host of the **same PHP version/thread-safety** |
| ZTS/NTS | irrelevant | must match the host exactly, or the load fails or crashes |

The ZTS point is the one that wastes an afternoon: the tpc release package here is ZTS
(`php8ts.dll`), so the host must be ZTS too. `php -i | grep -i thread` is a one-second check.

### The runtime dependency differs from bin mode

A bin artifact links the whole runtime and drags `php8ts.dll`/`phpx.dll` with it. An **extension**
links PHPX only — Zend/PHP symbols are resolved from the host SAPI at load time. So:

- the host PHP must match the ABI the extension was built against (version, ZTS/NTS, debug flags);
  a mismatch is a load failure or a crash, not a readable diagnostic;
- the target machine still needs **`libphpx`** available. The build writes an rpath, so this
  normally works, but a relocated deployment must ship it.

This is the ext-mode analogue of "the binary is not self-contained": the artifact does not stand
alone here either, it just depends on a different set of things.

## Build and load

```bat
:: build (Windows)
tpc project.yml --no-progress --build-dir build -o promo

:: load — note the module name is typephp_promo, not promo
php -d extension=D:/path/to/promo.dll demo.php
```

```bash
# Linux/macOS
tpc project.yml --no-progress --build-dir build -o promo
php -d extension=$(pwd)/promo.so demo.php
```

An absolute path in `-d extension=` avoids relying on `extension_dir`. Use forward slashes in
paths even on Windows, for the same launcher-stripping reasons as MCP config.

## `--dry` is even weaker here

`--dry` proves the PHP is inside the TypePHP subset. It says nothing about Zend module
registration, `ext-deps` load order, ZTS compatibility, or whether the exported symbol table
matches what the host will call. For ext work, `--dry` is a syntax gate only — budget the real
build every time you touch module metadata.

## `mode: lib` — the third sibling, and its own contract

A library is not an extension and not a binary. It produces a shared object **plus a generated
stub** that other TypePHP projects compile against:

```
demo.dll / libdemo.so      the implementation
demo.stub.php              the published ABI — this is what consumers see
```

Measured on `examples/lib-demo` (`-m lib`, Windows): the build emits
`generate library import stub: demo.stub.php`, and the stub is a plain `.php` file with empty
bodies and an `@import-library` marker:

```php
<?php

/** @import-library */

namespace {
    function demo_add(int $a, int $b): int
    {
    }
    function demo_public_array(): array
    {
    }
}
```

Three consequences worth knowing:

**The stub is the contract, and it is generated from what you wrote.** Every public function and
class lands in it. Helpers you did not intend to publish become part of the ABI — that is what
`#[NoExport]` exists to prevent (see `attributes-reference.md`, which has the measured before/after).

**Library name is tied to the stub file name.** The stub filename derives from `name:` in
`project.yml`; renaming it breaks consumers. Ship the stub and the shared object **from the same
build** — a new stub against an old library will mis-resolve symbols.

**Consumers link by path, not by explicit library name.** Their `project.yml` lists the stub in
`sources` and the directory in `link-paths`; the library name comes from the stub's
`@import-library` marker, so writing `link-libs: [demo]` as well is redundant.

Runtime requirements differ from both other modes: the consumer needs the `.dll`/`.so` discoverable
(`PATH`, `LD_LIBRARY_PATH`, or rpath), and on Windows the `.lib` is link-time only. Version drift is
strict — library and consumer must agree on OS, architecture, PHP major version, ZTS/NTS, PHPX and
TypePHP versions, or you get a link failure or a crash.
