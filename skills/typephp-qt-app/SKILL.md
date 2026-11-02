---
name: typephp-qt-app
description: Build native desktop GUI apps with TypePHP (PHP→C++ AOT) and Qt. Covers both routes — the default `yangweijie/typephp-qt` Composer package (declarative WidgetTree, `qtphp doctor/new/build/run/package`, a pure-PHP bridge double for tests) and the hand-written C++ bridge (`php_*` functions, `php::Box`, QString conversion, manual event loop) for widgets the package does not expose. Includes the AOT pitfalls that only surface in the compiled binary and never under the interpreter. Use when the user wants a desktop UI backed by compiled PHP, or mentions TypePHP together with Qt, QtWidgets, QML, QMainWindow, QPushButton, tpc, project.yml with Qt link flags, phpx, windeployqt, qtphp or WidgetTree — even if they never say "Qt" or "TypePHP" but are clearly building a native GUI on compiled PHP.
---

# TypePHP × Qt — Native Desktop Apps

TypePHP compiles PHP to native machine code. But it **cannot draw a window**. Qt (C++) draws the window. So the job always has the same shape. A thin C++ bridge exposes Qt to PHP. Every decision lives in PHP.

You can get that bridge in two ways. **Pick route 0 unless you have a reason not to.**

| Route | What it is | Use when |
|---|---|---|
| **0. The `typephp-qt` package** *(default)* | A Composer package that already contains the bridge, a declarative UI layer, a test double and a CLI. You write only PHP. | Almost always. Forms, tables, dashboards, tools, admin panels. |
| **1. Hand-write the bridge** | You write the `.stub.php` + `.cc` yourself and drive `tpc` by hand. | You need a Qt widget the package does not expose. Or you work inside the TypePHP compiler repo. |

---

## Route 0 — the `typephp-qt` package (default)

`yangweijie/typephp-qt` is the packaged form of everything in route 1. You never touch C++. You describe the UI as a PHP array. The bundled bridge diffs it against the live Qt widgets each frame.

Pin the minor version: the CLI flags and `WidgetTree` signatures below were written against **v0.9.x** (latest v0.9.5, 2026-10-15). A floating constraint will silently pick up a release that moves them.

```bash
composer require "yangweijie/typephp-qt:^0.9"
qtphp doctor            # check PHP / tpc / Qt / compiler / PHPUnit before anything else
qtphp new myapp         # scaffold a project that compiles as-is
cd myapp
qtphp build .           # tpc compile (+ auto-deploys runtime DLLs on Windows)
qtphp build . --nano    # nano mode: php-nano + PHPX compiled in, links NO PHP runtime (Apple Silicon verified)
qtphp run .             # run; args after the path pass straight through
qtphp package .         # self-contained bundle + self-check (scans every Mach-O, not just the exe)
```

### The shape of a package app

Three ideas make up the whole framework:

1. **State is plain PHP.** An array (or your own objects) holds everything the UI shows.
2. **`view()` describes the UI from state.** It runs every frame and returns a widget tree. You never mutate widgets.
3. **Handlers only change state.** The next frame re-describes the UI. The C++ side diffs by `id` and keeps widget state (cursor, selection, scroll) intact.

```php
use TypePHP\Qt\QtApp;
use TypePHP\Qt\WidgetTree;

function main(int $argc, array $argv): void
{
    $state = ['name' => 'World', 'greeting' => 'Hello, World!'];

    $app = new QtApp();
    $app->create(['name' => 'MyApp']);
    $app->createWindow('My App', ['width' => 720, 'height' => 480, 'centered' => true]);

    $app->view(function () use (&$state): array {
        return WidgetTree::vbox([
            WidgetTree::label($state['greeting'], ['id' => 'greeting']),
            WidgetTree::hbox([
                WidgetTree::lineEdit($state['name'], ['id' => 'name_input']),
                WidgetTree::button('打招呼', ['id' => 'greet_btn']),
            ]),
        ]);
    });

    $app->on('greet_btn', 'click', function () use ($app, &$state) {
        $state['name'] = $app->text('name_input');
        $state['greeting'] = 'Hello, ' . $state['name'] . '!';
    });

    $app->run();
}
```

- **Give every control you touch an `id`.** Nodes without one get a structural-path id (`_p0.1.2`). That id is stable but unreadable. `text('name_input')` needs a real id.
- **Containers**: `vbox hbox grid form group frame scroll tabs tab stack page split spacer separator`.
- **Controls**: `label button lineedit textedit spin doublespin slider progress checkbox radio combo list table tree image link`.

Signatures that are easy to guess wrong (verified against `src/WidgetTree.php`): `WidgetTree::table(array $columns, array $rows, array $props = [])` — `$columns` is a flat list of header strings, `$rows` a list of cell-value arrays. Row identity for the `select` event and for selection restore across re-renders comes from a separate **`row_ids` prop** (positional strings; default is the row index). `WidgetTree::webView(string $url = '', array $props = [])`.
- **Embedded web**: `webview`. The build picks the backend at compile time, per platform. Windows = WebView2 (full Chromium + JS). macOS = the system WKWebView (JS + remote `https://`). Anything else = QTextBrowser (HTML subset, **no JS**, remote `url` unsupported). Ask at runtime with `QtApp::webViewBackend()` (`webview2` / `wkwebview` / `textbrowser`) and `webViewSupportsJs()`. Degrade instead of failing silently. History is driven by `webViewReload()` / `webViewGoBack()` / `webViewGoForward($id)`.
- **Events**: `click press release change submit commit toggle select activate itemClick cell expand collapse tab close menu timer tray loaded navigating title`. Register with `on($id, $type, $handler)` or `onAny($type, $handler)`. When both match, **both fire** (specific first, then the wildcard). That is why `onAny` is the place for logging and telemetry.
- **`patch()`** is the imperative escape hatch for hot paths (log streams, progress ticks). It can `set` props or `call` one of `appendRows / clear / setText / setValue / select / focus`. It is a bypass. The next `render()` re-syncs from the tree, so write long-lived changes back into state.

Full control/property/event tables: the package `README.md`. Multi-window and timers: also there. One `QtApp` is one window, so `run()` only pumps its own. Multi-window apps pump each in a `while` loop. The tray is declarative too: `setTray(['icon' => …, 'tooltip' => …, 'visible' => …, 'menu' => […]])`. Activation arrives as an **id-less** `tray` event. Catch it with `onAny('tray', …)`. The gesture is in `$event['value']` (`left` / `right` / `double` / `middle`). Once you pass `menu`, Qt owns the right-click and items fire ordinary `menu` events.

### Why this route first

- **No C++ to maintain.** The bridge can never drift from your Qt or PHPX version.
- **The domain layer is unit-testable without Qt.** The package ships `FakeBridge`, a pure-PHP stand-in for the `qt_*` functions. So `qtphp test` runs with no Qt and no compiler. Write your logic against it.
- **One CLI covers all three platforms.** `qtphp` picks the right entry yml, deploys runtime DLLs, and packages a `.app` / `dist/` / `ld-lib` bundle with a self-check.

### Check without a human

Every package app should keep three headless switches. The scaffold's do — well, two of them as of v0.9.5: the `qtphp new` template ships `--shot` and `--selftest`, but **not** `--difftest`; add that one yourself if you need the diff-boundary check.

```bash
qtphp run . --shot out.png   # render a few frames, save PNG, exit — visual check
qtphp run . --selftest       # fire every registered event — catches handler wiring bugs
qtphp run . --difftest       # table/tree diff boundaries (selection, row ids, patches)
```

Set `$app->headless(true)` for these. It makes `message()` return its default and file dialogs return empty. So a modal dialog cannot block a CI run forever. On a box with no GUI session, also set `QT_QPA_PLATFORM=offscreen`.

**`--selftest` is not optional polish.** It is the only check that catches the AOT handler-arity trap below. The PHP unit tests run on a tolerant interpreter and cannot reproduce it.

---

## Route 1 — hand-write the bridge

Everything here is what the package already does for you. Read it when you need a widget the package does not expose. Read it also when you work inside the TypePHP compiler repo. That repo's `examples/qt-taskboard` is the canonical hand-written reference.

### The architecture (memorize this shape)

```
        PHP (brain)              C++ bridge (nerves)            Qt (face)
   ─────────────────────     ───────────────────────     ─────────────────────
    TaskStore.php        ──►  php_qt_board_create()    ──►  QApplication
    TaskBoardApplication      php_qt_board_set_view()      QMainWindow / QTableWidget
    main.php                  php_qt_board_poll_event()    QPushButton / QLineEdit
                              cpp-src/*.cc                   ← real Qt objects
```

- **PHP owns the brain.** Data, validation, state transitions, persistence, filtering. Because it is AOT-compiled it runs at C++ speed. Do not be shy about real logic here.
- **The C++ bridge is thin.** It creates Qt objects, paints PHP-supplied data onto them, and converts input into plain PHP arrays. Almost no business logic.
- **Qt only shows and captures.** A widget never decides anything. It reports "the user clicked X".

Two files declare the boundary. The compiler needs **both**:

| File | Role |
|---|---|
| `php-src/<name>.stub.php` | PHP-visible signatures. **Function bodies must be empty.** This is the only place the compiler learns the bridge's types. |
| `cpp-src/<name>.cc` | The implementations. PHP `foo_bar()` ⇄ C++ `php_foo_bar()`. |

### Step 0 — Pick the UI route

| Route | Use when | Cost |
|---|---|---|
| **Qt Widgets** | Desktop tools, forms, tables, dashboards. **Default.** | Lowest. No QML engine, no `qml/` directory to deploy. |
| **QML / Quick** | Heavy animation, touch/mobile feel, fully custom styling. | Needs Qt6Qml + Qt6Quick and `windeployqt --qmldir`. Without them the app starts blank. |

Start with Widgets unless the user explicitly asks for QML. If they do, read `references/qml-route.md`. You can also mix: `QtQuickWidgets` embeds a QML scene in a Widgets window.

### The workflow

1. **Domain layer first, no Qt.** Ordinary PHP classes for data and rules. Keep them Qt-free so they unit-test with a plain interpreter (`php tests/store_test.php`) and no build — `examples/qt-taskboard/tests/` runs with just `php`.
2. **Declare the bridge in `php-src/<name>.stub.php`** — PHP-visible signatures with **empty bodies**. This is the only place the compiler learns the bridge's types.

   ```php
   <?php
   function qt_board_create(string $title): mixed {}
   function qt_board_is_open(mixed $window): bool {}
   function qt_board_poll_event(mixed $window): array {}
   function qt_board_set_view(mixed $window, array $rows, array $metrics, string $selectedId): void {}
   function qt_board_destroy(mixed $window): void {}
   ```

   **Arrays in, arrays out.** `array` crosses cheaply and keeps C++ dumb. Opaque C++ objects travel as `mixed` (a `php::Box`), never as raw pointers.

3. **Implement `cpp-src/<name>.cc`** — always the same four parts: `QString ↔ php::String` helpers (UTF-8); a `php::Box` subclass holding every Qt pointer plus an event queue; a `QApplication` created lazily on the first `create`; one `php_*` entry point per stub function. Annotated code: `references/bridge-pattern.md`. Skeleton: `assets/templates/bridge.skeleton.cc`.
4. **Write `project.yml`** — `cxx-std: c++17`, `sources:` listing `main.php app php-src cpp-src` (directories are scanned), Qt include paths, `/Zc:__cplusplus` + `/permissive-`, and the three `Qt6*.lib`. Ready-to-edit Windows/macOS/Linux variants live in `assets/templates/`; what each flag does is in `references/build-and-deploy.md`.
5. **Compile, deploy, run** — `tpc project.yml --job 2 --no-progress`, then `windeployqt --release --no-translations <name>.exe`. `windeployqt` is **not enough** to ship: it copies Qt and nothing else, so you still need the TypePHP/PHPX runtime DLLs and your `assets/`. Per-platform commands and the DLL closure: `references/build-and-deploy.md`.

Scaffold a whole project in one shot:

```bash
scripts/scaffold.sh <dir> <app_name> [qt_root]          # window app
scripts/scaffold.sh --tray <dir> <app_name> [qt_root]   # system-tray app
```

**The scaffold output is checked: it compiles and renders a real window as-is** — once `PHP_HOME` and `QT_ROOT` point at your installs. The generated `.bat` files resolve both (environment variable first, then whatever `scaffold.sh` wrote) and stop with a one-line error naming the missing piece, instead of failing later at link time. `vcvars64.bat` is located automatically (`VCVARS`, then the default VS 2022 / 2019 locations under `%ProgramFiles%` / `%ProgramFiles(x86)%`), so `INCLUDE` is always set — **but the probe only covers the C: default locations. VS installed on another drive is not found; export `VCVARS=<path>` in that case** (measured on a box with BuildTools under `D:\Program Files (x86)`). Treat the output as the known-good baseline: if your build fails in a way the scaffold does not, the difference is in your edits. `run.bat shot.png` renders one frame and exits.

---

## Hard rules

Each of these silently breaks a build, a run, or a click. Rules 1–8 are **AOT-specific**. They do not reproduce under a normal PHP interpreter, so a passing unit test proves nothing about them. Details and fixes: `references/aot-pitfalls.md` — its entries 1–8 are numbered to match, and entry 9 is rule 20.

1. **The compiler checks closure arity exactly.** AOT-compiled closures raise `ArgumentCountError` on an extra argument. Plain PHP silently ignores it. `function () {}` called as `$f($event)` works everywhere except in the compiled binary. There it fails **only when that control is actually clicked**. Call each handler with the argument count it declares, or dispatch defensively.
2. **Global scope takes declarations only.** No `require_once`/`require` anywhere, not at global scope and not inside a function. It is `All execution code must be within a function, found stray code`. Cross-file visibility comes from `project.yml`'s `sources:`, never from `require`.
3. **`main()` must be a global function.** Several shapes compile and run — `main()`, `main(): void`, `main(): int`, and `main(int $argc, array $argv): void` when you need the arguments. The scaffold's templates use `main(): int`; the compiler's own examples use all of them. What breaks is `global $argv`, which crashes the AOT binary (`0xC0000409`).
4. **Closure parameters need explicit types** — `function (array $event)`, not `function ($event)`. Without them you get `The variable $event is undefined`.
5. **A modal dialog blocks forever with no user.** `QMessageBox::exec()` / `QFileDialog::get*()` spin a nested loop. In CI, `--selftest`, or any headless run, gate them behind a headless flag so they return a default instead.
6. **Do not reuse one variable for two reflection types.** `$ref = new ReflectionMethod(...)` then `$ref = new ReflectionFunction(...)` is `Cannot re-assign typed object`. Use two variables. AOT **does** support reflection. `getNumberOfRequiredParameters()` works on closures, `[obj,'method']`, and function-name strings.
7. **`php::Array` converts to `bool` implicitly, so `&$array` through the bridge is not a reference.** Pass `&$spec` where the parameter is pointer-typed and you get `Array(true)` — an array whose value is a bool. It surfaces at runtime as `parameter 1 must be of type array, bool given`. Drop the `&` when an `array`-typed value crosses the bridge.
8. **Bridge calls from a namespaced file need a leading `\`.** The `qt_*` functions are global. Inside `namespace App;`, write `\qt_board_create(...)`; otherwise the call resolves against your namespace and fails to compile.

Rules 9–16 apply to both routes:

9. **Stub bodies must be empty.** A body in a `.stub.php` is a compile error.
10. **The C++ symbol needs the `php_` prefix.** PHP `qt_board_create` ⇄ C++ `php_qt_board_create`. Wrong ⇒ unresolved symbol at link time.
11. **`QApplication` must exist before any widget.** Create it lazily behind a null check, so it happens exactly once.
12. **You drive the event loop yourself.** Qt must not block on `exec()`. Pump in ~16 ms slices and drain a queue into PHP. The package does this for you.
13. **Deploy plugins, not just DLLs.** Skipping `windeployqt` gives "could not find or load the Qt platform plugin windows". For QML add `--qmldir`.
14. **UTF-8 at the boundary** — always `QString::fromUtf8` / `toUtf8`, or CJK text mangles.
15. **Include the header for every class you name.** Also declare a file-scope `static` *above* the class that uses it. Qt has no guaranteed transitive includes. Both mistakes surface as unrelated-looking `C2027` / `C2065`.
16. **A tray app inverts two assumptions**: `setQuitOnLastWindowClosed(false)`, and loop `while (is_alive)` not `while (is_open)`. See `references/system-tray.md`.

Rules 17–20 are API/compiler traps found by running a real app. Rules 17–19 compile fine and fail silently at runtime. Rule 20 fails at compile time, but points at generated code, not your source:

17. **`WidgetTree::tabs()` takes a `title => children` map, not tab nodes.** `tabs(['页一' => [...], '页二' => [...]], ['id' => 't'])`. The implementation re-wraps every element with `tab()`. That function's `$title` is `string`. So passing pre-built `tab(...)` nodes throws `ArgumentTypeError: Argument #1 ($title) must be of type string, int given` (the int is the array index). The package's own `docs/` shows the wrong form. `tests/WidgetTreeTest.php` shows the right one. The same shape applies to `stack()`.
18. **The bridge applies tab/stack `current` *before* the children exist, so first-frame declarative selection silently no-ops.** `buildNode` runs `applyNodeProps` and only then recurses into children. So on the frame the bridge creates a `QTabWidget`, it clamps `setCurrentIndex(1)` back to 0. Because the prop signature was already recorded, no later frame retries it. Changing `current` on a *later* frame works. `patch(['op'=>'call','method'=>'select',...])` works immediately. **Consequence for `--shot`**: a tab you select only via `current` on frame 1 will not appear. Render one frame, `patch` the `select`, then render again. Also pass an **int**, not a string. The bridge does `value.toInt()`, and `'1'` becomes `0`. (Upstream defect. Fixed by deferring the apply to after `syncChildren`.)
19. **`table` has no row-height control, so the widget elides multi-line cell text to `…`.** Row height comes from the widget default. `qtRebuildTable` never calls `resizeRowsToContents()`. A 3-line cell in a normal-height row renders as `...`. Do you want a multi-line cell (a graph column, a wrapped diff)? Then keep it to **one line**. Otherwise add the `row_height` prop or an auto-resize to the bridge. (Upstream gap.)
20. **A property read inside a `&&` short-circuit cannot be written in the same `if` body.** `if ($n > 0 && $n !== $obj->limit) { $obj->limit = $n; }` fails to compile with `use of undeclared identifier '_object_prop_state_x__limit'` in a generated `.cc`. The short-circuit becomes an immediately-invoked lambda, and that lambda declares the property reference inside its own scope. Hoist the read into a local first. Details: `references/aot-pitfalls.md` #9.

## Windows runtime + toolchain

- **Bare `tpc project.yml` without the MSVC environment dies with a misleading error.** Measured on tpc 0.9.4 and 0.9.5: outside `vcvars64.bat`, even a trivial one-file project fails in `Translator::prepare()` with `Uncaught TypeError: TypePhp\Translator::getAbsolutePath(): Return value must be of type string, bool returned` — a missing-path symptom, not a yml problem. Set `INCLUDE`/`LIB` manually is **not** enough; the full `vcvars64.bat` environment is what it probes. Build through the generated `build.bat` (which calls vcvars) or wrap the call the same way.
- **`qtphp new` rejects absolute target paths.** It joins the argument onto `getcwd()`, so `qtphp new D:\proj\app` writes into `<cwd>\D:\proj\app` and every mkdir fails. Pass a relative name from the directory you want the project in. (Measured v0.9.5.)

- **`PDO_SQLITE` (or any PHP extension) needs a runtime ini.** Point `PHPRC` at an ini that sets `extension_dir` and `extension=php_pdo_sqlite.dll`. Also clear `PHP_INI_SCAN_DIR`. Otherwise the app starts and dies inside the embedded PHP runtime.
- **`--no-console`** for a GUI-subsystem build on Windows (not needed for macOS bundles).
- **`/Zc:__cplusplus` and `/permissive-` are mandatory** with the Qt MSVC SDK.
- **Two `tpc` distributions exist and their runtimes differ.** A native release package is self-contained (`phpx.dll`/`SDK/` sit beside the executable). The Composer-installed driver instead needs a `swoole/phpx` source tree whose build artifacts usually do not exist yet. Picking the wrong one fails with `The PHPX runtime library was not found at: ...\phpx\build\phpx.dll`. `qtphp` probes for the one that has a runtime. `TPC`/`TPC_DIR` override it. See `references/aot-pitfalls.md`.
- **In a *consumer* project `qtphp` cannot find `tpc` on its own.** `bin/qtphp` sets `$GLOBALS['rootDir'] = dirname(__DIR__)`. That is the **package** directory (`vendor/yangweijie/typephp-qt`), not your project. So it looks for `vendor/yangweijie/typephp-qt/vendor/bin/tpc.php`, which does not exist. Then `qtphp doctor` reports `tpc: 未找到`. Fix: install the driver in your own project (`composer require --dev swoole/typephp`) **and** export `TPC="$PWD/vendor/bin/tpc.php"` (or add it to `composer.json` `scripts`). Without it every `build`/`run`/`package` fails at the toolchain probe, not at compile time.

## Reference index

Read the file matching what you are doing. Do not read them all.

- `references/aot-pitfalls.md` — **read this before your first compiled run.** The AOT traps (rules 1–8, plus rule 20 as entry 9). Each entry gives the symptom, the root cause and the fix. Also the two-`tpc` supply routes.
- `references/bridge-pattern.md` — the C++/PHP bridge in depth: conversion helpers, `php::Box`, the event queue, the event loop, every `php_*` entry-point pattern, and the declarative diff the package uses.
- `references/qt-widgets-catalog.md` — **every** Qt Widgets class in the install, grouped by purpose. Consult when choosing controls.
- `references/qt-modules.md` — which Qt modules the install has, which it does not, and the three edits to link a new one.
- `references/build-and-deploy.md` — per-platform build/deploy/run, `runtime.ini`, packaging (`windeployqt`, macOS `.app`, Linux bundle), and the shell gotchas that waste the most time.
- `references/qml-route.md` — the QML/Quick route: `QQmlApplicationEngine` bridge, `.qml` deployment, when to prefer it.
- `references/system-tray.md` — system tray with `QSystemTrayIcon`, cross-platform (Windows notification area / macOS menu bar / Linux SNI).

Templates: `assets/templates/` (`project.windows.yml`, `project.macos.yml`, `project.linux.yml`, `runtime.ini`, `stub.skeleton.php`, `bridge.skeleton.cc`, `main.skeleton.php`, `store.skeleton.php`, `controller.skeleton.php`, and for tray apps `tray.stub.skeleton.php` + `tray.skeleton.cc`).
