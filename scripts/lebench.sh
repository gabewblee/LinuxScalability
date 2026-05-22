#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/platform.sh"

arch="$(get_target_arch)"
dir="$root/LEBench/TEST_DIR"
src="$dir/OS_Eval.c"
build="$(get_build_dir "$root")"
bin="$build/OS_Eval"

if [ ! -f "$src" ]; then
    echo "[lebench] ERROR: ${src} not found"
    exit 1
fi

compiler="$(get_compiler)"
quoted="$(printf '%q' "$bin")"
mkdir -p "$build"

echo "[lebench] Compiling OS_Eval for ${arch}..."
cd "$dir"
eval "$compiler -static -O0 OS_Eval.c -pthread -o $quoted"

echo "[lebench] Built: ${bin}"
