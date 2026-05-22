#!/usr/bin/env bash
set -euo pipefail

ver="${1:?Usage: $0 <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/platform.sh"

arch="$(get_target_arch)"
kernel="$(get_kernel_path "$root" "$ver")"
initrd="$(get_initrd_path "$root")"
log="$(get_log_path "$root" "$ver")"
csv="$(get_csv_path "$root" "$ver")"
qemu="$(get_qemu_bin)"
console="$(get_kernel_console)"

mkdir -p "$(dirname "$csv")" "$(dirname "$log")"
if [ ! -f "$kernel" ]; then
    echo "[run] ERROR: Kernel not found: ${kernel}"
    echo "[run] Run: make download VERSION=${ver} ARCH=${arch}"
    exit 1
fi

if [ ! -f "$initrd" ]; then
    echo "[run] ERROR: Initramfs not found: ${initrd}"
    echo "[run] Run: make initramfs ARCH=${arch}"
    exit 1
fi

require "$qemu"

if [ -s "$csv" ]; then
    echo "[run] Result for ${arch} kernel ${ver} already exists at ${csv}"
    echo "[run] Delete: rm ${csv}"
    exit 0
fi

timeout=""
if command -v timeout >/dev/null 2>&1; then
    timeout="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    timeout="gtimeout"
fi

read -r -a machine_args <<< "$(get_qemu_args)"

echo "[run] Booting ${arch} kernel ${ver} in QEMU..."
echo "[run] Log: ${log}"

rm -f "$log"
qemu_cmd=(
    "$qemu"
    "${machine_args[@]}"
    -kernel "$kernel"
    -initrd "$initrd"
    -append "$console"
    -display none
    -serial "file:${log}"
    -m 2048
    -smp 2
    -no-reboot
)

if [ -n "$timeout" ]; then
    "$timeout" 7200 "${qemu_cmd[@]}" || true
else
    echo "[run] WARNING: timeout/gtimeout not found."
    "${qemu_cmd[@]}" || true
fi

echo "[run] QEMU exited."
if awk '
    /=== LEBENCH_CSV_START ===/ { inside = 1; found = 1; next }
    /=== LEBENCH_CSV_END ===/ { inside = 0 }
    inside { print }
    END { exit found ? 0 : 1 }
' "$log" > "$csv"; then
    if [ ! -s "$csv" ]; then
        echo "[run] WARNING: Extracted CSV is empty."
        echo "[run] Inspect: ${log}"
        rm -f "$csv"
        exit 1
    fi
    echo "[run] Result saved: ${csv}"
else
    echo "[run] WARNING: CSV markers not found in QEMU output."
    echo "[run] Inspect: ${log}"
    exit 1
fi
