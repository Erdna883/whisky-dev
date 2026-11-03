#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler_dir="${MINGW_BIN_DIR:-$(dirname "$project_dir")/toolchains/llvm-mingw-20261020-ucrt-macos-universal/bin}"
for target in x86_64 i686; do
    compiler="$compiler_dir/$target-w64-mingw32-gcc"
    if [[ ! -x "$compiler" ]]; then
        echo "Missing LLVM-MinGW compiler: $compiler" >&2
        exit 1
    fi
    "$compiler" -municode -mwindows -Os -s -static -Wl,--no-insert-timestamp \
        "$project_dir/scripts/steam-browser/adapter.c" \
        -o "$project_dir/Libraries/SteamBrowserAdapters/$target.exe"
done
