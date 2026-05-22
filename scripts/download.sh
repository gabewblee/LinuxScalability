#!/usr/bin/env bash
set -euo pipefail

ver="${1:?Usage: $0 <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/platform.sh"

arch="$(get_target_arch)"
dest="$(get_kernel_path "$root" "$ver")"
base="https://kernel.ubuntu.com/mainline/v${ver}"
subdir="${base}/${arch}"

mkdir -p "$(dirname "$dest")"
if [ -f "$dest" ]; then
    echo "[kernel] ${arch} vmlinuz-${ver} already present, skipping."
    exit 0
fi

listing=""
origin=""
for candidate in "${subdir}" "${base}"; do
    echo "[kernel] Trying directory listing from ${candidate}/ ..."
    page=$(curl -fsSL "${candidate}/" 2>/dev/null || true)
    case "$page" in
    *".deb"*)
        listing="$page"
        origin="$candidate"
        break
        ;;
    esac
done

if [ -z "$listing" ] || [ -z "$origin" ]; then
    echo "[kernel] ERROR: Cannot fetch a usable listing from ${subdir}/ or ${base}/"
    echo "[kernel] Check network, the kernel version, or whether Ubuntu mainline publishes ${arch} builds for v${ver}."
    exit 1
fi

package=$(printf '%s\n' "$listing" | awk -v arch="$arch" '
    match($0, /href="[^"]*linux-image-unsigned-[^"]*\.deb"/) {
        package = substr($0, RSTART + 6, RLENGTH - 7)
        if (package ~ arch "\\.deb$" && package ~ /generic/ && package !~ /lowlatency/) {
            print package
            exit
        }
    }
')

if [ -z "$package" ]; then
    package=$(printf '%s\n' "$listing" | awk -v arch="$arch" '
        match($0, /href="[^"]*linux-image-[^"]*\.deb"/) {
            package = substr($0, RSTART + 6, RLENGTH - 7)
            if (package ~ arch "\\.deb$" && package ~ /generic/ && package !~ /lowlatency/) {
                print package
                exit
            }
        }
    ')
fi

if [ -z "$package" ]; then
    echo "[kernel] ERROR: No generic ${arch} image .deb found for version ${ver}."
    echo "[kernel] Available .deb files at ${origin}/:"
    echo "$listing" | sed -n 's/.*href="\([^"]*\.deb\)".*/\1/p' | head -20 || true
    exit 1
fi

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT

echo "[kernel] Downloading from ${origin}/ : ${package}"
if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -P "$workspace" "${origin}/${package}"
else
    curl -fL "${origin}/${package}" -o "$workspace/$(basename "$package")"
fi

echo "[kernel] Extracting vmlinuz..."
dpkg-deb -x "$workspace/$(basename "$package")" "$workspace/extract/"

source=$(find "$workspace/extract/boot" -name 'vmlinuz-*' | head -1)
if [ -z "$source" ]; then
    echo "[kernel] ERROR: vmlinuz not found inside the .deb package."
    exit 1
fi

cp "$source" "$dest"
echo "[kernel] Saved: ${dest}"
