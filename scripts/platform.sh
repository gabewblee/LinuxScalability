#!/usr/bin/env bash

normalize() {
    case "${1:-}" in
        x86_64|amd64) 
            echo "amd64"
            ;;
        aarch64|arm64) 
            echo "arm64"
            ;;
        armv7l|armhf|arm)
            echo "armhf"
            ;;
        ppc64le|powerpc64le|ppc64el)
            echo "ppc64el"
            ;;
        riscv64)
            echo "riscv64"
            ;;
        s390x) 
            echo "s390x"
            ;;
        *)
            echo "[platform] ERROR: Unsupported architecture: ${1:-<empty>}" >&2
            echo "[platform] Supported: amd64, arm64, armhf, ppc64el, riscv64, s390x" >&2
            return 1
            ;;
    esac
}

get_target_arch() {
    normalize "${TARGET_ARCH:-${ARCH:-$(uname -m)}}"
}

get_build_dir() {
    local root="${1:?Usage: get_build_dir <root>}"
    echo "$root/build"
}

get_kernel_path() {
    local root="${1:?Usage: get_kernel_path <root> <version>}"
    local ver="${2:?Usage: get_kernel_path <root> <version>}"
    echo "$root/kernels/vmlinuz-$ver"
}

get_initrd_path() {
    local root="${1:?Usage: get_initrd_path <root>}"
    echo "$root/build/initrd.gz"
}

get_csv_path() {
    local root="${1:?Usage: get_csv_path <root> <version>}"
    local ver="${2:?Usage: get_csv_path <root> <version>}"
    echo "$root/results/$ver.csv"
}

get_log_path() {
    local root="${1:?Usage: get_log_path <root> <version>}"
    local ver="${2:?Usage: get_log_path <root> <version>}"
    echo "$root/logs/$ver.log"
}

get_compiler() {
    if [ -n "${CC:-}" ]; then
        echo "$CC"
        return
    fi

    if command -v gcc >/dev/null 2>&1; then
        echo "gcc"
        return
    fi

    echo "[platform] ERROR: No C compiler found (gcc or musl-gcc required)." >&2
    return 1
}

get_qemu_bin() {
    case "$(get_target_arch)" in
        amd64)
            echo "qemu-system-x86_64"
            ;;
        arm64)
            echo "qemu-system-aarch64"
            ;;
        armhf)
            echo "qemu-system-arm"
            ;;
        ppc64el)
            echo "qemu-system-ppc64"
            ;;
        riscv64)
            echo "qemu-system-riscv64"
            ;;
        s390x)
            echo "qemu-system-s390x"
            ;;
    esac
}

get_qemu_args() {
    case "$(get_target_arch)" in
        amd64)
            echo ""
            ;;
        arm64)
            echo "-machine virt -cpu max"
            ;;
        armhf)
            echo "-machine virt -cpu cortex-a15"
            ;;
        ppc64el)
            echo "-machine pseries"
            ;;
        riscv64)
            echo "-machine virt"
            ;;
        s390x)
            echo "-machine s390-ccw-virtio"
            ;;
    esac
}

get_kernel_console() {
    case "$(get_target_arch)" in
        s390x)
            echo "console=ttyS0 console=ttysclp0"
            ;;
        *)
            echo "console=ttyS0"
            ;;
    esac
}

require() {
    local cmd="${1:?Usage: require <command>}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[platform] ERROR: Required command not found: $cmd" >&2
        return 1
    fi
}
