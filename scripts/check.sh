#!/bin/sh
set -eu

cd -- "$(dirname -- "$0")/.."
headless=false
full_tests=true
for option in "$@"; do
    case "$option" in
        --headless) headless=true ;;
        --quick) full_tests=false ;;
        --help|-h) printf '%s\n' 'usage: sh scripts/check.sh [--quick] [--headless]'; exit 0 ;;
        *) printf '%s\n' 'usage: sh scripts/check.sh [--quick] [--headless]' >&2; exit 2 ;;
    esac
done

odin_compiler="${ODIN:-odin}"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/odin_pp-check.XXXXXX")"
trap 'rm -rf -- "$check_dir"' EXIT HUP INT TERM

"$odin_compiler" version
printf 'Test profile: %s\n' "$(if "$full_tests"; then printf full; else printf quick; fi)"
"$odin_compiler" check src -vet -strict-style -define:ODIN_TEST_FULL="$full_tests"
"$odin_compiler" test src -all-packages -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FULL="$full_tests" -o:none -out:"$check_dir/tests"
if "$full_tests"; then
    "$odin_compiler" check src -vet -strict-style -disable-assert
    "$odin_compiler" test src -all-packages -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FULL=true -o:none -disable-assert -out:"$check_dir/tests-no-assert"
fi
# All registered engine and minigame packages are reachable from src.
# Full checks repeat the suite with asserts disabled.

if ! "$headless"; then
    "$odin_compiler" build src -o:none -out:"$check_dir/odin_pp"
    if "$full_tests"; then
        "$odin_compiler" build src -o:none -disable-assert -out:"$check_dir/odin_pp-no-assert"
    fi
fi
