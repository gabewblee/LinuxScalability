#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/platform.sh"

arch="$(get_target_arch)"
echo "[setup] Architecture: ${arch}"

echo "[setup] Updating package index..."
sudo apt-get update

echo "[setup] Installing dependencies..."
sudo apt-get install -y \
    build-essential     \
    qemu-system         \
    make                \
    wget                \
    curl                \
    cpio                \
    gzip                \
    git                 \
    dpkg                \
    python3             \
    python3-venv

if [ ! -d "$root/.venv" ]; then
    echo "[setup] Creating Python virtual environment..."
    python3 -m venv "$root/.venv"
fi

pip="$root/.venv/bin/pip"
"$pip" install -r "$root/requirements.txt"

echo "[setup] Done."
