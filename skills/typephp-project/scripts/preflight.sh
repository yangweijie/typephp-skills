#!/usr/bin/env bash
# TypePHP preflight — answer "is this machine able to build?" before blaming PHP code.
# Usage: bash preflight.sh [project-dir]
# Exit 0 = ready, non-zero = the listed problem will break every build.

set -u

proj="${1:-.}"
fail=0

say() { printf '%-22s %s\n' "$1" "$2"; }
ok()   { say "$1" "ok"; }
bad()  { say "$1" "FAIL"; fail=$((fail+1)); }
warn() { say "$1" "warn"; }

echo "== shell =="
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) os=windows ;;
    Darwin)               os=macos ;;
    *)                    os=linux ;;
esac
say "platform" "$os"

echo
echo "== C/C++ toolchain =="
if [ "$os" = windows ]; then
    if command -v cl >/dev/null 2>&1; then ok "cl on PATH"; else bad "cl on PATH (msvc)"; fi
    # The subtle one: cl.exe present is not enough, INCLUDE must point at the MSVC headers.
    if printf '%s' "${INCLUDE:-}" | grep -qi 'msvc'; then
        ok "INCLUDE (msvc)"
    else
        bad "INCLUDE (run vcvars64.bat)"
    fi
else
    for c in g++ clang++; do
        if command -v "$c" >/dev/null 2>&1; then ok "$c"; found=1; break; fi
    done
    [ "${found:-0}" = 1 ] || bad "g++/clang++"
fi

echo
echo "== TypePHP toolchain =="
if command -v tpc >/dev/null 2>&1; then
    ok "tpc on PATH ($(command -v tpc))"
elif [ -n "${PHP_HOME:-}" ] && [ -x "$PHP_HOME/tpc.exe" ]; then
    ok "tpc in PHP_HOME"
elif [ -n "${PHP_HOME:-}" ] && [ -x "$PHP_HOME/tpc" ]; then
    ok "tpc in PHP_HOME"
else
    bad "tpc (set PHP_HOME or put tpc on PATH)"
fi

if [ -n "${PHP_HOME:-}" ]; then ok "PHP_HOME"; else warn "PHP_HOME unset"; fi
if [ -n "${PHPX_HOME:-}" ]; then ok "PHPX_HOME"; else warn "PHPX_HOME unset"; fi

echo
echo "== project =="
if [ -f "$proj/project.yml" ]; then
    ok "project.yml"
    printf '   mode: %s\n' "$(sed -n 's/^mode:[[:space:]]*//p' "$proj/project.yml" | head -1)"
    printf '   sources: %s\n' "$(sed -n '/^sources:/,/^[a-z-]*:/p' "$proj/project.yml" | grep -c '^  -' ) entry(ies)"
elif [ -n "$(find "$proj" -maxdepth 2 -name '*.php' -print -quit 2>/dev/null)" ]; then
    warn "no project.yml (file/dir build only)"
else
    warn "no PHP sources found"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "READY — no blocking problem found."
    exit 0
fi
echo "$fail blocking problem(s). Fix those before debugging PHP code; they fail every build."
echo "Hint: on Windows, open a Developer Command Prompt or 'call ...\\VC\\Auxiliary\\Build\\vcvars64.bat'."
exit 1
