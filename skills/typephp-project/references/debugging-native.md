# Debugging native code: GDB, LLDB, sanitizers

TypePHP compiles to native binaries, so **there is no Xdebug and no Zend breakpoints**. You debug
generated C++ with GDB/LLDB. This is a different skill from PHP debugging and it is where people
give up too early.

## Preconditions — all three, or you will chase ghosts

1. **`--debug`** (or `-d`): sets `-O0` and adds `-g`. Without it, variables are optimized away and
   functions are inlined out of existence.
2. **No optimisation**: `-O0`, which `--debug` already gives you.
3. **Debug builds of PHPX/PHP** (recommended) if you want to step into PHP internals:
   `cmake . -DCMAKE_BUILD_TYPE=Debug`, `./configure --enable-debug`.

```bash
tpc app.php --debug            # -O0 + -g
tpc app.php --debug --sanitize=address   # plus ASAN
```

## Symbol names — the part that makes this work

AOT-compiled PHP functions are exported with C linkage under a predictable scheme. Once you know
it, breakpoints are trivial.

| PHP | Symbol |
|---|---|
| `function my_add()` | `php_my_add` |
| `Foo\Bar\baz()` | `php_foo__bar__baz` |
| `class UserService { function create() }` | `php_userservice__create` |
| built-in function | `zif_*` (e.g. `zif_array_merge`) |
| built-in method | `zim_*` (e.g. `zim_arrayobject_count`) |

Rules: namespaces use `__` for `/`, and **the whole symbol is lowercase**.

```bash
gdb ./app
(gdb) b php_userservice__create     # method entry
(gdb) b build/main.cc:42            # generated C++ line
(gdb) r
```

## Reading PHP values at a breakpoint

Plain C++ types (`int64_t`, `double`, `bool`) print normally. PHP values need `.print()`, which is
only available in Debug builds:

```bash
(gdb) call var.print()      # var_dump-like output for php::Variant
(gdb) call arr.print()      # php::Array
(gdb) call obj.print()      # php::Object
(gdb) call str.toCString()  # php::String -> const char*
```

Box types (BigInt / Decimal / BigFloat) do **not** print directly — go through the static helper:

```bash
(gdb) call php::BigInt::toString(bi).print()
(gdb) call php::Decimal::toString(dec).print()
```

## Reading the generated C++

`tpc --debug` leaves `.cc` files under the build dir (`build/main.cc`, `build/src__utils.cc`, …).
Two identifiers tell you a lot:

| You see | It means |
|---|---|
| `tmp_var_N` | compiler-generated temporary |
| `php_my_func()` | a PHP function call that stayed native |
| `php::zend_call("func", args)` | a dynamic call — this is the slow path |
| `php::toBigInt(expr)` | numeric conversion to a box |

Grepping for `php::zend_call` in generated code tells you where your code fell off the static path.
That is often faster than any profiler for answering "why is this slow".

## Memory errors

**AddressSanitizer** — the first tool to reach for on a crash:

```bash
tpc app.php --debug --sanitize=address
ASAN_OPTIONS=detect_leaks=1:abort_on_error=1:halt_on_error=1 ./app
```

Catches buffer overflows (heap/stack/global), use-after-free, double free, leaks (`detect_leaks=1`).
`--sanitize=undefined` catches integer overflow and null dereference.

**Valgrind** — PHP's `zend_alloc` interferes; disable it with `USE_ZEND_ALLOC=0`.

```bash
USE_ZEND_ALLOC=0 valgrind --leak-check=full --track-origins=yes ./app
```

## The typical crash causes

| Symptom | Likely cause |
|---|---|
| segfault immediately | null from `.toBox<T>()`, array index out of range, use-after-free |
| crash only in release | a `--debug`-only assumption; or undefined behaviour that ASAN will name |
| crash inside a coroutine | exception escaping a coroutine boundary — catch `\Throwable` **inside** the callback, or the process dies with `terminate called after throwing an instance of '_zend_object*'` |
| leak on shutdown | exception thrown from `__destruct()`; it interrupts the two-phase cleanup. Catch inside the destructor |

The coroutine one deserves emphasis because it is not a normal PHP failure mode: an uncaught
exception in a Swoole/Swow callback **aborts the process**, and the message names a C++ type, not
your code. Every coroutine/event entry point needs its own `try { … } catch (\Throwable) {}`,
including `\Swoole\Coroutine\run`, `go()`, and server callbacks. Catching only `\Exception` is not
enough — PHP `Error` escapes too.

## Extension load failures

Different toolchain, different checks:

```bash
ldd ./promo.so                                    # missing libraries
nm -D ./promo.so | grep typephp                   # exported symbols
php -d display_startup_errors=1 -d extension=$(pwd)/promo.so -m
```

A silent no-op usually means a module-name mismatch: the registered name is `typephp_<name>`, not
the file name. See `ext-mode.md`.

## What you cannot do

- No step-through debugging of PHP source. You step through generated C++.
- No `debug_backtrace()` inside native calls — they have no Zend stack frame. Do not use backtraces
  for hot-path attribution.
- `--profile` and `perf` are Linux-only; macOS/Windows need manual `microtime(true)` instrumentation.
