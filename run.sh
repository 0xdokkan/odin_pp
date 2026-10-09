#!/bin/sh
set -eu

# Development startup: avoid the optimizer before each interactive run.
cd -- "$(dirname -- "$0")"
exec "${ODIN:-odin}" run src -o:none -- "$@"
