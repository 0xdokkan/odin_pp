#!/bin/sh
set -eu

# Default to quick development builds; --release enables the game optimizer.
cd -- "$(dirname -- "$0")"
mkdir -p build
optimization=none
if [ "${1:-}" = --release ]; then
    optimization=speed
    shift
fi
exec "${ODIN:-odin}" run src "-o:$optimization" -out:build/odin_pp -- "$@"
