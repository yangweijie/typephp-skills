#!/usr/bin/env bash
# Scaffold a minimal, runnable TypePHP + Qt project.
#
#   scaffold.sh [--tray] <target-dir> <app_name> [qt_root]
#
# Options:
#   --tray   generate a system-tray app instead of a window app
#   -h       show this help
#
# Window app (default) creates:
#   <target-dir>/main.php
#   <target-dir>/app/AppStore.php        (demo data layer — replace it)
#   <target-dir>/app/AppController.php   (event handling + view refresh)
#   <target-dir>/php-src/<app_name>.stub.php
#   <target-dir>/cpp-src/<app_name>.cc
#
# Tray app (--tray) creates:
#   <target-dir>/main.php
#   <target-dir>/app/TrayController.php
#   <target-dir>/php-src/tray.stub.php
#   <target-dir>/cpp-src/tray.cc
#   <target-dir>/assets/icon.png         (placeholder — replace it)
#
# Both also create project.yml, runtime.ini, assets/README.txt, build.bat,
# run.bat and package.bat. The generated project compiles and runs as-is once
# PHP_HOME and QT_ROOT point at your installs; the .bat files check both up
# front and say exactly what is missing instead of failing at link time. Only
# the UI, the data layer and the assets are meant to be replaced.
#
# <app_name> must be a lowercase identifier (letters, digits, underscore).

set -euo pipefail

TRAY=0
POSITIONAL=()

for arg in "$@"; do
  case "$arg" in
    --tray)   TRAY=1 ;;
    -h|--help)
      sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
  echo "usage: scaffold.sh [--tray] <target-dir> <app_name> [qt_root]" >&2
  exit 2
fi

TARGET="${POSITIONAL[0]}"
APP="${POSITIONAL[1]}"
QT_ROOT="${POSITIONAL[2]:-}"

# Where the TypePHP toolchain lives. Substituted into runtime.ini *and* into the
# generated .bat files, so it is written once and stays in sync. Resolution:
#   1. PHP_HOME_DIR=<path>  explicit, wins
#   2. $PHP_HOME            whatever the shell already exports
#   3. empty — the generated .bat files then stop with "PHP_HOME is not set"
# Never bake a machine-specific default in here: a plausible-looking wrong path
# is worse than no path, because it fails later at link time instead of up front.
PHP_HOME_DIR="${PHP_HOME_DIR:-${PHP_HOME:-}}"

# The `set` lines written into the generated .bat files. Empty when the value is
# unknown, so the file carries no meaningless `set "X="` line — the guard in the
# .bat then reports "not set" instead of pointing at a path that never existed.
PHP_HOME_LINE=""
if [ -n "$PHP_HOME_DIR" ]; then
  PHP_HOME_LINE="if not defined PHP_HOME set \"PHP_HOME=$PHP_HOME_DIR\""
fi
QT_ROOT_LINE=""
if [ -n "$QT_ROOT" ]; then
  QT_ROOT_LINE="if not defined QT_ROOT set \"QT_ROOT=$QT_ROOT\""
fi

if ! printf '%s' "$APP" | grep -Eq '^[a-z][a-z0-9_]*$'; then
  echo "error: app_name must match ^[a-z][a-z0-9_]*\$ (got: $APP)" >&2
  exit 2
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$HERE/../assets/templates"

if [ ! -d "$TPL" ]; then
  echo "error: templates not found at $TPL" >&2
  exit 1
fi

if [ -e "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null || true)" ]; then
  echo "error: $TARGET already exists and is not empty" >&2
  exit 1
fi

mkdir -p "$TARGET/app" "$TARGET/php-src" "$TARGET/cpp-src" "$TARGET/assets"

# Copy a template and substitute the placeholders. The window templates use
# <APP> inside function names so the PHP stub and the C++ php_<APP>_* symbols
# stay in sync automatically. The tray templates use fixed tray_* names, which
# the tray stub and tray bridge both agree on.
render() {
  local src="$1" dst="$2"
  sed -e "s|<APP>|$APP|g" \
      -e "s|<QT_ROOT>|$QT_ROOT|g" \
      -e "s|<PHP_HOME>|$PHP_HOME_DIR|g" \
      "$src" > "$dst"
}

if [ "$TRAY" -eq 1 ]; then
  render "$TPL/tray-main.skeleton.php"       "$TARGET/main.php"
  render "$TPL/tray-controller.skeleton.php" "$TARGET/app/TrayController.php"
  render "$TPL/tray.stub.skeleton.php"       "$TARGET/php-src/tray.stub.php"
  render "$TPL/tray.skeleton.cc"             "$TARGET/cpp-src/tray.cc"
  base64 -d < "$TPL/placeholder-icon.b64" > "$TARGET/assets/icon.png"
  SHOT_VAR="TRAY_SCREENSHOT"
  KIND="tray app"
else
  render "$TPL/main.skeleton.php"        "$TARGET/main.php"
  render "$TPL/store.skeleton.php"       "$TARGET/app/AppStore.php"
  render "$TPL/controller.skeleton.php"  "$TARGET/app/AppController.php"
  render "$TPL/stub.skeleton.php"        "$TARGET/php-src/$APP.stub.php"
  render "$TPL/bridge.skeleton.cc"       "$TARGET/cpp-src/$APP.cc"
  SHOT_VAR="${APP}_SCREENSHOT"
  KIND="window app"
fi

render "$TPL/project.windows.yml" "$TARGET/project.yml"
render "$TPL/runtime.ini"         "$TARGET/runtime.ini"

cat > "$TARGET/assets/README.txt" <<'EOF'
Runtime files for this app.

Anything in this folder is copied next to the executable by package.bat.
windeployqt handles Qt and nothing else — your own files are exactly what it
does NOT copy, which is why this folder exists.

The folder structure is preserved: a file at assets/icon.png ends up at
<app-dir>/assets/icon.png, so reference it from PHP as 'assets/icon.png'.

Paths are resolved relative to the executable's folder, not the process CWD,
so they keep working no matter where the app is launched from.
EOF

cat > "$TARGET/build.bat" <<EOF
@echo off
REM Build the ${APP} TypePHP + Qt app.
REM PHP_HOME / QT_ROOT were written by scaffold.sh. Override either one by
REM setting it in your shell before running this file.
setlocal
${PHP_HOME_LINE}
${QT_ROOT_LINE}

REM --- Qt kit -------------------------------------------------------------
if not defined QT_ROOT (
  echo error: QT_ROOT is not set.
  echo        Pass it as the 3rd argument to scaffold.sh, or set QT_ROOT to
  echo        your Qt kit folder, e.g. C:\\Qt\\6.8.0\\msvc2022_64
  exit /b 1
)
if not exist "%QT_ROOT%\\include\\QtWidgets" (
  echo error: QT_ROOT does not look like a Qt kit: "%QT_ROOT%"
  echo        expected: %QT_ROOT%\\include\\QtWidgets
  echo        Set QT_ROOT, or pass it as the 3rd argument to scaffold.sh.
  exit /b 1
)

REM --- MSVC environment ---------------------------------------------------
REM cl.exe on PATH is not enough: INCLUDE must point at the MSVC headers, or
REM tpc dies with C1083 "cannot open include file malloc.h".
REM Order: an explicit VCVARS wins, then the default VS 2022 / 2019 locations.
if defined VCVARS goto :have_vcvars
for %%S in (BuildTools Community Professional Enterprise) do (
  if exist "%ProgramFiles%\\Microsoft Visual Studio\\2022\\%%S\\VC\\Auxiliary\\Build\\vcvars64.bat" set "VCVARS=%ProgramFiles%\\Microsoft Visual Studio\\2022\\%%S\\VC\\Auxiliary\\Build\\vcvars64.bat"
)
if defined VCVARS goto :have_vcvars
for %%S in (BuildTools Community Professional Enterprise) do (
  if exist "%ProgramFiles(x86)%\\Microsoft Visual Studio\\2019\\%%S\\VC\\Auxiliary\\Build\\vcvars64.bat" set "VCVARS=%ProgramFiles(x86)%\\Microsoft Visual Studio\\2019\\%%S\\VC\\Auxiliary\\Build\\vcvars64.bat"
)
:have_vcvars
if not defined VCVARS (
  echo error: vcvars64.bat not found.
  echo        Install "Desktop development with C++", or set VCVARS to your copy.
  exit /b 1
)
if not exist "%VCVARS%" (
  echo error: VCVARS points at a file that does not exist: "%VCVARS%"
  exit /b 1
)
call "%VCVARS%" >nul

REM --- toolchain ----------------------------------------------------------
if not defined PHP_HOME (
  echo error: PHP_HOME is not set.
  echo        Point it at your TypePHP toolchain folder (the one holding tpc.exe),
  echo        or re-run scaffold.sh with PHP_HOME=... exported.
  exit /b 1
)
if not exist "%PHP_HOME%\\tpc.exe" (
  echo error: tpc.exe not found in PHP_HOME="%PHP_HOME%"
  echo        Set PHP_HOME to your TypePHP toolchain folder.
  exit /b 1
)
set "PHPX_HOME=%PHP_HOME%\\phpx"
set "PATH=%QT_ROOT%\\bin;%PHP_HOME%;%PATH%"
cd /d "%~dp0"

"%PHP_HOME%\\tpc.exe" project.yml --job 2 --no-progress
set "RC=%errorlevel%"
echo BUILD_EXITCODE=%RC%
REM A bare endlocal would report success no matter what the build did.
endlocal & exit /b %RC%
EOF

# run.bat takes an optional screenshot path: \`run.bat shot.png\` renders one
# frame, saves the PNG and exits. Passing it as an argument avoids the fragile
# nested-quoting you get from \`set VAR=... && call run.bat\` on the command line.
cat > "$TARGET/run.bat" <<EOF
@echo off
REM Deploy Qt deps and run. Optional arg 1: a .png path -> render once and exit.
setlocal
${PHP_HOME_LINE}
${QT_ROOT_LINE}
if not defined PHP_HOME (
  echo error: PHP_HOME is not set - it holds the runtime DLLs this app loads.
  exit /b 1
)
if not defined QT_ROOT (
  echo error: QT_ROOT is not set.
  exit /b 1
)
if not exist "%QT_ROOT%\\bin\\windeployqt.exe" (
  echo error: windeployqt.exe not found under QT_ROOT="%QT_ROOT%"
  echo        Set QT_ROOT to your Qt kit folder, e.g. C:\\Qt\\6.8.0\\msvc2022_64
  exit /b 1
)
set "PHPX_HOME=%PHP_HOME%\\phpx"
set "PATH=%QT_ROOT%\\bin;%PHP_HOME%;%PHPX_HOME%\\lib;%PATH%"
cd /d "%~dp0"

if not exist "${APP}.exe" (
  echo error: ${APP}.exe not found - run build.bat first
  exit /b 1
)

REM >nul hides the verbose "Updating ..." lines; windeployqt's warnings go to
REM stderr and stay visible.
"%QT_ROOT%\\bin\\windeployqt.exe" --release --no-translations "${APP}.exe" >nul
set "PHPRC=%~dp0runtime.ini"
set "PHP_INI_SCAN_DIR="
if not "%~1"=="" set "${SHOT_VAR}=%~f1"

"${APP}.exe"
set "RC=%errorlevel%"
echo RUN_EXITCODE=%RC%
REM A bare endlocal would report success even if the app crashed.
endlocal & exit /b %RC%
EOF

# package.bat is the one that matters for shipping. windeployqt covers Qt and
# only Qt; the PHP/PHPX runtime DLLs and your own assets/ have to be copied by
# hand, and forgetting either is the classic "works here, broken there" bug.
cat > "$TARGET/package.bat" <<EOF
@echo off
REM Assemble a redistributable folder in dist\\.
REM   dist\\${APP}.exe
REM   dist\\                Qt DLLs + plugins            (windeployqt)
REM   dist\\                TypePHP / PHPX runtime DLLs  (windeployqt does NOT do these)
REM   dist\\assets\\         your own runtime files       (nor these)
REM   dist\\runtime.ini     PHP extension config, if the app uses one
REM
REM It then runs the packaged app with a crippled PATH to prove nothing is
REM missing. Pass --no-verify to skip that (e.g. on a headless CI box).
setlocal
${PHP_HOME_LINE}
${QT_ROOT_LINE}
if not defined PHP_HOME (
  echo error: PHP_HOME is not set - it holds the runtime DLLs this package ships.
  exit /b 1
)
if not defined QT_ROOT (
  echo error: QT_ROOT is not set.
  exit /b 1
)
if not exist "%QT_ROOT%\\bin\\windeployqt.exe" (
  echo error: windeployqt.exe not found under QT_ROOT="%QT_ROOT%"
  echo        Set QT_ROOT to your Qt kit folder, e.g. C:\\Qt\\6.8.0\\msvc2022_64
  exit /b 1
)
set "PHPX_HOME=%PHP_HOME%\\phpx"
set "PATH=%QT_ROOT%\\bin;%PHP_HOME%;%PHPX_HOME%\\lib;%PATH%"
cd /d "%~dp0"

set "APP=${APP}"
set "DIST=%~dp0dist"

if not exist "%APP%.exe" (
  echo error: %APP%.exe not found - run build.bat first
  exit /b 1
)

echo [1/5] clean dist
if exist "%DIST%" rmdir /S /Q "%DIST%"
mkdir "%DIST%"

echo [2/5] executable
copy /Y "%APP%.exe" "%DIST%\\" >nul

echo [3/5] Qt runtime
"%QT_ROOT%\\bin\\windeployqt.exe" --release --no-translations "%DIST%\\%APP%.exe" >nul

echo [4/5] TypePHP/PHPX runtime + assets
REM The non-Qt DLLs the executable needs. Derived from the import table;
REM add more if you load extra PHP extensions (e.g. libsqlite3.dll for pdo_sqlite).
for %%D in (phpx.dll php8ts.dll libmpdec++-4.0.1.dll libmpdec-4.0.1.dll gmp-10.dll mpfr-6.dll) do (
  copy /Y "%PHP_HOME%\\%%D" "%DIST%\\" >nul
)
if exist "assets" (
  xcopy /E /I /Y /Q "assets" "%DIST%\\assets" >nul
  echo       assets\\ copied
) else (
  echo       no assets\\ folder - nothing to copy
)
if exist "runtime.ini" (
  copy /Y "runtime.ini" "%DIST%\\" >nul
  echo       runtime.ini copied - launch with PHPRC pointing at it if the
  echo       app loads PHP extensions (e.g. pdo_sqlite)
)

REM ---- self-containment check --------------------------------------------
REM Run the packaged app with a crippled PATH so nothing can leak in from the
REM build machine. This is the only check that actually catches a missing DLL
REM or an asset that never made it into dist\\.
if /I "%~1"=="--no-verify" (
  echo [5/5] self-containment check - SKIPPED
  goto :packaged
)

echo [5/5] self-containment check ^(clean PATH^)
set "CHECK_SHOT=%DIST%\\selfcheck.png"
if exist "%CHECK_SHOT%" del /Q "%CHECK_SHOT%"
set "SAVED_PATH=%PATH%"
set "PATH=%SystemRoot%\\System32;%SystemRoot%"
set "PHP_INI_SCAN_DIR="
if exist "%DIST%\\runtime.ini" set "PHPRC=%DIST%\\runtime.ini"
set "${SHOT_VAR}=%CHECK_SHOT%"
set "CHECK_OUT=%DIST%\\selfcheck.out"
set "CHECK_ERR=%DIST%\\selfcheck.err"
if exist "%CHECK_OUT%" del /Q "%CHECK_OUT%"
if exist "%CHECK_ERR%" del /Q "%CHECK_ERR%"
pushd "%DIST%"
REM Capture both streams: the embedded PHP runtime writes its startup warnings
REM to stdout, not to stderr.
"%APP%.exe" >"%CHECK_OUT%" 2>"%CHECK_ERR%"
set "RC=%errorlevel%"
popd
set "PATH=%SAVED_PATH%"
set "${SHOT_VAR}="

if not "%RC%"=="0" (
  echo.
  echo   FAILED - the packaged app exited with %RC%.
  type "%CHECK_OUT%" 2>nul
  type "%CHECK_ERR%" 2>nul
  echo   The message above names the missing file. Check the runtime DLL list
  echo   and the assets\\ copy step against it.
  exit /b 1
)

REM A clean exit code is not enough: the embedded PHP runtime reports a missing
REM extension as a warning and carries on, so the app "works" while quietly
REM missing a feature. Treat that as a packaging failure too.
findstr /I /C:"PHP Startup" /C:"Fatal error" "%CHECK_OUT%" "%CHECK_ERR%" >nul 2>&1
if not errorlevel 1 (
  echo.
  echo   FAILED - the PHP runtime reported a startup problem:
  type "%CHECK_OUT%" 2>nul
  type "%CHECK_ERR%" 2>nul
  echo   Usually a PHP extension that was enabled in runtime.ini but not
  echo   shipped. See the notes at the top of runtime.ini.
  exit /b 1
)

if not exist "%CHECK_SHOT%" (
  echo.
  echo   FAILED - the app exited cleanly but rendered nothing.
  echo   It probably started without its assets, or there is no display.
  exit /b 1
)
type "%CHECK_OUT%" 2>nul
type "%CHECK_ERR%" 2>nul
if exist "%CHECK_SHOT%" del /Q "%CHECK_SHOT%"
if exist "%CHECK_OUT%" del /Q "%CHECK_OUT%"
if exist "%CHECK_ERR%" del /Q "%CHECK_ERR%"
set "VERIFIED=1"
echo   OK - started and rendered with only System32 on PATH.

:packaged
echo.
echo packaged to %DIST%
if defined VERIFIED (
  echo verified self-contained - ship the whole folder.
) else (
  echo NOT verified - run package.bat without --no-verify before shipping.
)
endlocal
EOF

# cmd.exe needs CRLF. With LF-only files it tolerates plain commands but fails
# on labels with "The system cannot find the batch label specified" — which is
# exactly what package.bat's --no-verify path would hit.
# awk rather than `sed -i`: BSD sed (macOS) reads the -i argument as a backup
# suffix and then treats the filename as the script, so `sed -i 's/.../.../'`
# dies with "unterminated substitute pattern".
for bat in "$TARGET"/*.bat; do
  [ -f "$bat" ] || continue
  tmp="$bat.tmp"
  awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$bat" > "$tmp" && mv "$tmp" "$bat"
done

# Lint before handing over. cmd has no dry-run or syntax-check mode, so these
# static rules stand in for one — they encode the cmd behaviours that have
# actually bitten this scaffold (see references/build-and-deploy.md).
if ! bash "$HERE/lint-bats.sh" "$TARGET"; then
  echo "error: generated .bat files failed linting - fix the templates in $TPL" >&2
  exit 1
fi

echo "scaffolded $KIND '$APP' into $TARGET"
if [ -n "$PHP_HOME_DIR" ]; then
  echo "  PHP_HOME = $PHP_HOME_DIR"
else
  echo "  PHP_HOME = (not set) — export PHP_HOME, or set it before running build.bat"
fi
if [ -n "$QT_ROOT" ]; then
  echo "  QT_ROOT  = $QT_ROOT"
else
  echo "  QT_ROOT  = (not set) — pass it as the 3rd argument, or export QT_ROOT before build.bat"
fi
echo "next:"
echo "  1. run $TARGET/build.bat      (fails fast if PHP_HOME / QT_ROOT / MSVC are not found)"
echo "  2. run $TARGET/run.bat        (or: run.bat shot.png to render once and exit)"
echo "  3. run $TARGET/package.bat    to assemble dist/ for shipping"
if [ "$TRAY" -eq 1 ]; then
  echo "  4. replace assets/icon.png with your own icon (PNG / ICO / SVG)."
else
  echo "  4. then replace app/AppStore.php with your real data layer"
fi
