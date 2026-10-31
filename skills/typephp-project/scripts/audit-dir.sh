#!/usr/bin/env bash
# TypePHP compatibility audit for PHP code you did not write.
#
#   bash audit-dir.sh <dir-or-file>... [--mode lib|bin] [--max-exclusions N]
#
# Why this exists: the obvious approach (point check_code at each file) is wrong for
# library code, because check_code always runs bin mode and bin mode demands a global
# main(). Every library file is rejected and it reads like a compatibility verdict.
# This script runs tpc directly, in lib mode by default, and compiles whole directories
# so inheritance and traits resolve.
#
# It also knows that tpc stops at the first fatal, so a single scan reports one problem.
# With --max-exclusions it will exclude offenders iteratively to enumerate more, but it
# labels those results as CONTAMINATED because excluding a file causes cascade failures.

set -u

MODE="lib"
MAX_EXCL=0
TARGETS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --mode)            MODE="$2"; shift 2 ;;
        --mode=*)          MODE="${1#*=}"; shift ;;
        --max-exclusions)  MAX_EXCL="$2"; shift 2 ;;
        --max-exclusions=*) MAX_EXCL="${1#*=}"; shift ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)                 TARGETS+=("$1"); shift ;;
    esac
done

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "usage: bash audit-dir.sh <dir-or-file>... [--mode lib|bin] [--max-exclusions N]" >&2
    echo "       bash audit-dir.sh <project-dir-with-project.yml>   # whole-app mode" >&2
    exit 2
fi

# tpc lives either on PATH or in PHP_HOME. Prefer the release package: the repo-root
# build has been observed to fail with 0xC0000139 on Windows.
if [ -n "${PHP_HOME:-}" ] && [ -x "$PHP_HOME/tpc.exe" ]; then
    TPC="$PHP_HOME/tpc.exe"
elif [ -n "${PHP_HOME:-}" ] && [ -x "$PHP_HOME/tpc" ]; then
    TPC="$PHP_HOME/tpc"
elif command -v tpc >/dev/null 2>&1; then
    TPC="$(command -v tpc)"
else
    echo "tpc not found; set PHP_HOME or put tpc on PATH" >&2
    exit 2
fi

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/typephp-audit-$$")"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# NOTE: --mode=lib, with "=". `--mode lib` is parsed as an input path and yields
# "Fatal error: path not exists: lib".
SCAN_FLAGS="--dry --mode=$MODE --no-progress"

scan() { # $1 = path, $2 = build dir
    "$TPC" $SCAN_FLAGS "$1" --build-dir "$2" 2>&1
}

echo "tpc:    $TPC"
echo "mode:   $MODE${MODE:+  (check_code uses bin -- irrelevant for libraries)}"
echo

for target in "${TARGETS[@]}"; do
    if [ ! -e "$target" ]; then
        echo "SKIP  $target  (does not exist)"
        continue
    fi

    files=$(find "$target" -name '*.php' 2>/dev/null | wc -l | tr -d ' ')

    # Whole-app mode: a directory with project.yml is compiled through the manifest, not
    # by scanning subdirectories. Splitting an application into per-directory scans is
    # wrong -- php-src/ may contain only .stub.php, and sources can include cpp-src.
    if [ -d "$target" ] && [ -f "$target/project.yml" ]; then
        start=$(date +%s%N 2>/dev/null || echo 0)
        out=$(scan "$target/project.yml" "$WORK/bd-app")
        end=$(date +%s%N 2>/dev/null || echo 0)
        ms=$(( (end - start) / 1000000 ))
        if echo "$out" | grep -q '^Fatal error'; then
            msg=$(echo "$out" | grep -m1 '^Fatal error')
            echo "FAIL  $target/project.yml  (whole app, $files files, ${ms}ms)"
            echo "      $(echo "$msg" | cut -c1-120)"
        elif echo "$out" | grep -q '^No valid source file found'; then
            echo "N/A   $target/project.yml  (no compilable source)"
        else
            echo "PASS  $target/project.yml  (whole app, $files files, ${ms}ms)"
        fi
        continue
    fi

    # .stub.php files declare an ABI; they are not compilable sources on their own.
    # A directory containing only stubs yields "No valid source file found", which is
    # not a compatibility verdict and must not be scored as PASS or FAIL.
    stubs=$(find "$target" -name '*.stub.php' 2>/dev/null | wc -l | tr -d ' ')
    realfiles=$((files - stubs))
    if [ -d "$target" ] && [ "$realfiles" -le 0 ]; then
        echo "N/A   $target  ($files file(s), all .stub.php — nothing to compile)"
        continue
    fi

    start=$(date +%s%N 2>/dev/null || echo 0)
    out=$(scan "$target" "$WORK/bd-a")
    end=$(date +%s%N 2>/dev/null || echo 0)
    ms=$(( (end - start) / 1000000 ))

    if echo "$out" | grep -q '^No valid source file found'; then
        # Nothing compilable was collected: wrong directory, or stubs only.
        echo "N/A   $target  ($files files, ${ms}ms — no compilable source)"
    elif echo "$out" | grep -q '^Fatal error'; then
        msg=$(echo "$out" | grep -m1 '^Fatal error')
        echo "FAIL  $target  ($files files, ${ms}ms)"
        echo "      $(echo "$msg" | cut -c1-120)"
        # tpc stops at the first error, so this is ONE problem, not the whole list.
        if [ "$MAX_EXCL" -gt 0 ]; then
            echo "      enumerating more via exclusion (results are CONTAMINATED)..."
            rm -rf "$WORK/w"; cp -r "$target" "$WORK/w" 2>/dev/null || { echo "      (cannot copy; stopping)"; continue; }
            for i in $(seq 1 "$MAX_EXCL"); do
                o=$(scan "$WORK/w" "$WORK/bd-b")
                f=$(echo "$o" | sed -n 's/.* in \(.*\):[0-9]*$/\1/p' | head -1)
                [ -z "$f" ] && { echo "      [$i] no more errors"; break; }
                # The compiler echoes native (Windows) absolute paths while this shell
                # may see /tmp/... for the same directory. Derive the offending file
                # from the error message, then locate it by searching for the same
                # relative suffix inside the copy -- robust across path styles.
                tail_rel=$(echo "$f" | sed 's|.*[\\/]w[\\/]||' | tr '\\' '/')
                hit=$(find "$WORK/w" -path "*$tail_rel" -type f 2>/dev/null | head -1)
                if [ -z "$hit" ]; then
                    echo "      [$i] cannot locate $tail_rel inside the copy; stopping"
                    break
                fi
                rel="${hit#"$WORK/w"/}"
                echo "      [$i] exclude $rel"
                rm -f "$hit"
            done
            echo "      ^ each exclusion can cause cascades; confirm each file individually"
        fi
    else
        echo "PASS  $target  ($files files, ${ms}ms)"
    fi
done

cat <<'EON'

Reading the result
  PASS  whole-directory compile succeeded: no known incompatibility in these sources.
  FAIL  compile stopped at the first problem. With >=1 file it is real; with a single
        file it may be a false positive -- see below.

Do not trust per-file FAILs that say "Trait X not found" or "inherits from a non-existent
class". Those resolve when the directory is compiled together. Measured on psr/log:
2/8 files fail per-file, 0/8 fail as a directory.
EON
