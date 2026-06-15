#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

IMAGE="lebench-patched"
PLATFORM="linux/amd64"

if ! command -v docker >/dev/null 2>&1; then
    echo "[docker] Error: docker not found. Install Docker Desktop first."
    exit 1
fi

mkdir -p kernels results plots build

echo "[docker] Building image '$IMAGE'..."
docker build --platform "$PLATFORM" -t "$IMAGE" -f Dockerfile .

echo "[docker] Running benchmark in container..."
docker run --rm --platform "$PLATFORM" \
    -v "$root":/host:ro                \
    -v "$root/kernels":/out/kernels    \
    -v "$root/results":/out/results    \
    -v "$root/plots":/out/plots        \
    -v "$root/build":/out/build        \
    "$IMAGE" bash -euc '
        git clone --quiet /host /build
        cd /build
        git fetch --quiet /host "+refs/remotes/origin/*:refs/remotes/origin/*"
        rm -rf kernels results plots build
        ln -s /out/kernels kernels
        ln -s /out/results results
        ln -s /out/plots plots
        ln -s /out/build build
        python3 -m venv .venv
        .venv/bin/pip install --quiet -r requirements.txt
        bash scripts/patch.sh "$@"
    ' _ "$@"

echo ""
echo "[docker] Done. Results in results/, plots in plots/"
