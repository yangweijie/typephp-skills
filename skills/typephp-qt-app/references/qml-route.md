# The QML / Quick route

Widgets and QML are two ways to build the same Qt app. Since 2026-11 the **package has a first-class `qml` widget**, so the usual question — "how do I embed a QML scene?" — is answered by route 0 with one constructor and one compile-time flag. The hand-written `QQmlApplicationEngine` bridge (route 1) remains for apps whose *whole shell* is QML.

> **Verification scope (updated 2026-11-11, replaces the old "not run end-to-end" note):**
> - The **package `qml` widget** was verified end-to-end on real hardware on both desktop platforms — `examples/qmlclock` in the package repo: macOS (Qt 6.11/6.12, brew) and Windows (Qt 6.9.3 MSVC2022, local **and** CI runner), offscreen `--selftest` 9/9 green, including `QT_QUICK_BACKEND=software`. The measured scope is `import QtQuick`-only scenes.
> - Linux for QML is **untested** (the qmlclock `project.linux.yml` exists but has never been compiled — no Linux + qtdeclarative environment was available).
> - The hand-written `QQmlApplicationEngine` route below still follows standard Qt 6 practice and has not been run end-to-end here. Its deployment section is corrected to the measured facts, but treat it as unverified code.

## When to choose QML over Widgets

| Prefer QML when… | Prefer Widgets when… |
|---|---|
| The UI is animation-heavy or highly custom-styled | The UI is a form, table, or tool window |
| Touch / mobile / tablet is a target | It is a desktop keyboard-and-mouse tool |
| Designers hand you `.qml` files | You want the smallest deployment |
| You need `QtQuickControls2` styles (Material, Universal, FluentWinUI3) | You want plain native-looking controls |

The two coexist naturally: `WidgetTree::qml()` *is* `QtQuickWidgets` — a QML scene inside a Widgets window, in the same tree, diffed by the same id machinery, receiving events through the same queue.

## Route A — the package `qml` widget (default)

### Compile-time opt-in

QML is a compile-time switch (`QT_QML`), not a runtime capability. In the app's `project.yml`:

```yaml
include-paths:                  # + three include dirs
  - <QT_ROOT>/include/QtQml
  - <QT_ROOT>/include/QtQuick
  - <QT_ROOT>/include/QtQuickWidgets
link-libs:                      # + three libs
  - Qt6Qml.lib
  - Qt6Quick.lib
  - Qt6QuickWidgets.lib
cxx-flags:
  - /DQT_QML                    # the switch itself
```

The `qtphp new` scaffold already compiles `cpp-src/qt_qml.cc` into every app — **without** the flag it is a placeholder translation unit, and a `qml` widget degrades to a diagnostic `QLabel` ("QML 未启用 + 该 id + 怎么开") instead of failing the build. That is also why a QML-free app pays nothing for the feature. `QtApp::qmlAvailable()` tells you whether the flag was on — assert it in a selftest before asserting anything else about QML.

### The widget contract

```php
WidgetTree::qml(
    string $source = '',        // path to the .qml file, relative to the exe dir (usually 'assets/clock.qml')
    array  $props = [],         // PHP → QML: each key is set as a property on the QML root (and re-applied after reload)
) + node props: 'id', 'read' (list of property names exposed to PHP), 'signals' (list of signal names wired to events)
```

The three-channel boundary, all measured:

1. **PHP → QML (`props`)** — declarative. The bridge writes each key onto the QML root when it applies props, and **replays them after `qmlReload()`** (an early build silently lost first-frame props and let reload wipe them — both fixed; `value()` readbacks on a `speed` prop were the probe that caught it, because a readback of `1.0` that never changed was actually evidence the write never landed).
2. **QML → PHP (`signals`)** — the event **type is the signal name** (`$app->on('clock', 'tick', function (array $e) { … })`). The payload is a snapshot of the `read` properties at signal time. Under the hood the bridge wires each QML signal to a real moc slot trampoline (a hand-built static metaobject is **not** portable across Qt versions — Qt 6.12 rejects it with `Incompatible sender/receiver arguments` while 6.11 accepted it; the trampoline works on both). Signals must be wired **the same frame the source is set**: the root object is available synchronously on first frame, and waiting for the `status` to reach `Ready` before connecting gets you **zero events** under offscreen.
3. **PHP ← QML (`value()`)** — `value($id)` reads the `read` properties from the live root object, so QML-mutated state (a clock's `timeText`, a slider bound inside QML) crosses back without an event.

`QtApp::qmlReload($id)` re-instantiates the component (e.g. after editing the source file). Props are replayed and signals re-wired — a selftest proves the post-reload tick still arrives.

### The explicit error channel

A broken QML source never throws and never fails the build. Every failure — missing file, syntax error, missing import — lands in `qmlStatus($id)`:

```php
$st = $app->qmlStatus('clock');
// ['status' => 'ready'|'loading'|'error', 'errors' => [['line' => -1, 'message' => 'assets/clock.qml: No such file or directory'], …]]
```

So a QML selftest asserts: `qmlAvailable()` is true, the expected `value()` readbacks (PHP-written props *and* QML-side mutations), the expected events, and **`errors` is empty**. The `status` field itself is informational only — measured it stays `loading` under offscreen on macOS/Qt 6.12 but reaches `ready` on Windows/Qt 6.9.3, so it must never be a pass/fail criterion. If your criteria are not observable behavior, you are recording the defect as green: a selftest asserting a value readback that silently never worked stays green until someone asks what it proves.

### Headless / CI

`QT_QPA_PLATFORM=offscreen` + `QT_QUICK_BACKEND=software` (software scene graph, no GPU). Measured green on a CI runner this way. Do **not** assert on pixels from a `--shot` for QML content: `QWidget::grab()` does not capture QML content (measured) — assert via `value()` readbacks and events instead.

### Deployment — the part that was measured, not guessed

- **Windows**: a QML exe needs the 7-DLL closure — `Qt6Qml` `Qt6QmlModels` `Qt6QmlMeta` `Qt6QmlWorkerScript` `Qt6Quick` `Qt6QuickWidgets` `Qt6OpenGL`. The exe's own import table names only `Qml` and `QuickWidgets`; the rest is reachable only through Qt's DLLs (`Quick → QmlMeta → QmlWorkerScript`), so import-table probing one DLL at a time must miss them. `qtphp build` deploys the whole closure automatically (and cleans stale copies on a later non-QML build). By hand: `dumpbin /dependents` on the exe **and on each Qt DLL it names**, then copy until the closure is system-only. The failure mode of a missed transitive DLL is silent and anonymous: Git Bash prints `?: cannot open shared object file`, no name.
- **The `qml/` module directory is NOT needed for `import QtQuick`** — on either platform. Measured with `QML_IMPORT_TRACE=1`: the import path list contains a filesystem `build/qml` that does not exist, and the qmldir actually loads from the built-in resource `:/qt-project.org/imports/QtQuick/qmldir` — Qt 6 embeds first-party QML type registrations in the linked libraries (macOS frameworks and Windows DLLs alike). An app that imports only QtQuick is fully self-contained without shipping `qml/`.
- **Scope caution**: the measurement covers `import QtQuick` only. Scenes using `QtQuick.Controls` / `Dialogs` / `Effects` etc. were not tested without a `qml/` tree — for those, keep `windeployqt --qmldir` (route B) or ship the `qml/` subtree, and verify on a clean machine before trusting it.
- **macOS**: self-contained out of the box (same qrc mechanism); `macdeployqt` needs no `-qmldir` for QtQuick-only scenes.
- **CI Qt install**: do **not** pass `modules: qtdeclarative` to `jurplel/install-qt-action` — for Qt 6 desktop, qtdeclarative is in the **base** component's `DownloadableArchives` (measured in Qt's Updates.xml for 6.9.3 win64_msvc2022_64) and there is no `addons.qtdeclarative` entry, so the flag makes aqt die with `packages ['qtdeclarative'] were not found while parsing XML` before any compile. Drop the flag; the libraries are already in the default install.

## Route B — hand-write the engine bridge (whole-shell QML)

Everything here is what the package already does for you; read it when the *shell itself* must be QML, or when you work inside the TypePHP compiler repo.

Widgets route: C++ builds a widget tree.
QML route: C++ builds a `QQmlApplicationEngine`, loads a `.qml` file, and exposes data/objects to QML.

```cpp
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

static QGuiApplication *qt_application = nullptr;
static QQmlApplicationEngine *qt_engine = nullptr;

php::Variant php_ui_create(php::String qmlPath) {
    if (!qt_application) qt_application = new QGuiApplication(qt_argc, qt_argv);
    if (!qt_engine)      qt_engine = new QQmlApplicationEngine();
    qt_engine->load(QUrl::fromLocalFile(toQString(qmlPath)));
    return { /* a Box holding the engine, or a QObject bridge */ };
}
```

Two ways to push PHP data into QML:

1. **Context properties** — simplest. `qt_engine->rootContext()->setContextProperty("rows", qmlArrayFromPhp(rows));` and reference `rows` from QML. Good for read-mostly data that you re-push on each `set_view`.
2. **A `QObject` bridge with signals/slots** — register a C++ class with `qmlRegisterType`, expose `Q_INVOKABLE` methods that PHP calls, and `Q_PROPERTY`/signals for QML→PHP. More code, but it is the idiomatic route and scales better.

For a TypePHP app, start with **context properties** — it mirrors the Widgets bridge's "arrays in, arrays out" shape and needs no meta-object plumbing.

QML calling back into PHP works exactly like a widget signal: a QML signal handler calls a C++ slot, which `enqueue()`s an event, which PHP drains on the next tick. Same event-queue contract as `bridge-pattern.md`. The same-frame wiring rule from route A applies: `QQmlApplicationEngine::rootObjects()` is filled synchronously by `load()` — connect there, not from a status-changed callback.

## Link flags

In addition to the Widgets set, link the QML/Quick libraries you use:

```yaml
cxx-flags:
  - '/I"<QT_ROOT>/include/QtQml"'
  - '/I"<QT_ROOT>/include/QtQuick"'
  - '/I"<QT_ROOT>/include/QtQuickWidgets"'
  - '/DQT_QML'
ld-flags:
  - Qt6Qml.lib
  - Qt6Quick.lib
  - Qt6QuickWidgets.lib
```

`Qt6QuickControls2.lib` only if your scene uses Controls. Route A needs exactly these three; the rest of the closure is runtime DLLs (see the deployment section above), not link inputs.

## Practical guidance

- **Do not mix shells casually.** A Widgets shell with `qml()` panels (route A) is the cheap, verified path. A QML shell with widget views means rewriting the whole bridge — only worth it for a genuinely QML-first app.
- **Keep the PHP side identical.** The domain layer, the event queue and the PHP `main()` loop do not change at all between the two routes. Only `cpp-src/` and the deployment differ. That is the payoff of the "arrays in, arrays out" boundary.
- **Assert the capability before the behavior.** `qmlAvailable()` first, then readbacks/events/errors. A placeholder label in a forgotten-flag build otherwise passes any test that only checks "the app still runs".
- **Verify deployment on a clean machine, not the build machine.** "It works here" is exactly what a `qml/`-or-DLL miss looks like, because both failure modes are silent: a missing module prints a `qmlStatus` error (catchable), a missing DLL can abort before PHP flushes anything (uncatchable — the anonymous `?` loader error above).
