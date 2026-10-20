#!/bin/sh
set -eu

# Development startup: avoid the optimizer before each interactive run.
cd -- "$(dirname -- "$0")"
mkdir -p build
exec "${ODIN:-odin}" run src -o:none -out:build/odin_pp -- "$@"
