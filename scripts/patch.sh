#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

KERNELS="5.0 5.1 5.2 5.3 5.4 5.5 5.6 5.7 5.8 5.9 5.10 5.11 5.12 5.13 5.14 5.15 5.16 5.17 5.18 5.19 6.0 6.1 6.2 6.3 6.4 6.5 6.6 6.7 6.8 6.9 6.10 6.11 6.12 6.13 6.14 6.15 6.16 6.17 6.18 6.19 7.0 7.1-rc3"
LABEL="patched"
BRANCH="origin/patched"

while [ $# -gt 0 ]; do
    case "$1" in
        --kernels) KERNELS="$2"; shift 2 ;;
        --label) LABEL="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if ! git rev-parse "$BRANCH" >/dev/null 2>&1; then
    echo "[patch] Error: Branch '$BRANCH' not found"
    git branch -a
    exit 1
fi

CURRENT=$(git rev-parse --abbrev-ref HEAD)
trap "git checkout -f $CURRENT 2>/dev/null || true" EXIT

mkdir -p results logs kernels

if [ ! -d .venv ]; then
    echo "[patch] Setting up environment..."
    bash "$root/scripts/setup.sh"
fi

if [ ! -f build/initrd.gz ]; then
    echo "[patch] Building initramfs..."
    bash "$root/scripts/lebench.sh"
    bash "$root/scripts/initramfs.sh"
fi

for v in $KERNELS; do
    if [ -f "results/$v.csv" ]; then
        echo "[patch] Skipping $v (already tested)"
        continue
    fi
    echo ""; echo "=== Benchmarking $v ==="; echo ""
    bash "$root/scripts/download.sh" "$v" || true
    bash "$root/scripts/benchmark.sh" "$v" || true
done

echo ""; echo "=== Building $LABEL kernel from $BRANCH ==="; echo ""
git checkout -f "$BRANCH" 2>/dev/null

if [ ! -f kernels/vmlinuz-$LABEL ]; then
    if [ ! -f Makefile ] || ! grep -q "KERNELVERSION" Makefile; then
        echo "[patch] Error: '$BRANCH' is not a Linux kernel source tree"
        git checkout -f "$CURRENT" 2>/dev/null || true
        exit 1
    fi

    if ! echo '#include <gelf.h>' | "${CC:-gcc}" -E - >/dev/null 2>&1; then
        echo "[patch] gelf.h not found; fetching libelf locally (no root needed)..."
        deps="$root/.deps"
        mkdir -p "$deps/root"
        if (cd "$deps" && apt-get download libelf-dev libelf1 zlib1g-dev zlib1g 2>/dev/null) \
           && ls "$deps"/*.deb >/dev/null 2>&1; then
            for d in "$deps"/*.deb; do dpkg -x "$d" "$deps/root"; done
            libdir="$deps/root/usr/lib/x86_64-linux-gnu"
            export HOSTCFLAGS="-I$deps/root/usr/include ${HOSTCFLAGS:-}"
            export HOSTLDFLAGS="-L$libdir ${HOSTLDFLAGS:-}"
            export LD_LIBRARY_PATH="$libdir:${LD_LIBRARY_PATH:-}"
            echo "[patch] Using local libelf from $deps/root"
        else
            echo "[patch] ERROR: could not fetch libelf .deb packages."
            echo "[patch] Ask an admin to install: libelf-dev libssl-dev flex bison bc"
            git checkout -f "$CURRENT" 2>/dev/null || true
            exit 1
        fi
    fi

    echo "[patch] Generating .config (defconfig + kvm guest)..."
    make defconfig
    make kvm_guest.config 2>/dev/null || true
    ./scripts/config --enable BLK_DEV_INITRD                           \
                     --enable SERIAL_8250 --enable SERIAL_8250_CONSOLE \
                     --enable TMPFS --enable DEVTMPFS --enable DEVTMPFS_MOUNT
    make olddefconfig

    echo "[patch] Building kernel (this takes several minutes)..."
    make -j"$(nproc)" bzImage
    if [ ! -f arch/x86/boot/bzImage ]; then
        echo "[patch] Error: kernel build failed (no arch/x86/boot/bzImage)"
        git checkout -f "$CURRENT" 2>/dev/null || true
        exit 1
    fi
    cp arch/x86/boot/bzImage kernels/vmlinuz-$LABEL
    echo "[patch] Kernel built: kernels/vmlinuz-$LABEL"
else
    echo "[patch] Patched kernel already exists: kernels/vmlinuz-$LABEL"
fi

git checkout -f "$CURRENT" 2>/dev/null || true

echo ""; echo "=== Benchmarking $LABEL (patched) ==="; echo ""
bash "$root/scripts/benchmark.sh" "$LABEL" || true

echo ""; echo "[patch] Done! Run 'make plot' to build the heatmap."
