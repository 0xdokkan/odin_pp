#!/bin/sh
set -eu

cd -- "$(dirname -- "$0")/.."
case "${1:-}" in
    ""|--headless) ;;
    *) printf '%s\n' 'usage: sh scripts/check.sh [--headless]' >&2; exit 2 ;;
esac

odin_compiler="${ODIN:-odin}"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/odin_pp-check.XXXXXX")"
trap 'rm -rf -- "$check_dir"' EXIT HUP INT TERM

"$odin_compiler" version
"$odin_compiler" check src -vet -strict-style
"$odin_compiler" check src -vet -strict-style -disable-assert
"$odin_compiler" test src -all-packages -define:ODIN_TEST_THREADS=1 -o:none -out:"$check_dir/tests"
"$odin_compiler" test src -all-packages -define:ODIN_TEST_THREADS=1 -o:none -disable-assert -out:"$check_dir/tests-no-assert"

if [ "${1:-}" != --headless ]; then
    "$odin_compiler" build src -o:none -out:"$check_dir/odin_pp"
    "$odin_compiler" build src -o:none -disable-assert -out:"$check_dir/odin_pp-no-assert"
fi
