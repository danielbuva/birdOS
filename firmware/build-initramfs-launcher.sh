#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE_BOOT=${1:-/Volumes/dani-sp/.firmware-work/dani-boot-backlight-25.img}
OUTPUT_DIR=${2:-$ROOT/firmware/work/initramfs-launcher}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
BASE_SHA="eab1f16833a69c8e9a04297d87d0dee1b86980d27edc8e027ae3966b352865bd"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -f "$BASE_BOOT" ] || fail "active boot-image base not found: $BASE_BOOT"
[ -x "$LLD" ] || fail "LLVM lld is required; install it with: brew install lld"
[ ! -e "$OUTPUT_DIR" ] || fail "output already exists: $OUTPUT_DIR"

ACTUAL_BASE_SHA=$(shasum -a 256 "$BASE_BOOT" | awk '{print $1}')
[ "$ACTUAL_BASE_SHA" = "$BASE_SHA" ] ||
	fail "base boot image is not the installed backlight-25 image: $ACTUAL_BASE_SHA"

UNPACKED="$OUTPUT_DIR/base"
VERIFY="$OUTPUT_DIR/verify"
RAMDISK="$UNPACKED/ramdisk"
LAUNCHER="$RAMDISK/opt/dani-launcher"
RAMDISK_CPIO="$OUTPUT_DIR/dani-initramfs.cpio"
RAMDISK_GZ="$OUTPUT_DIR/dani-initramfs.gz"
CANDIDATE="$OUTPUT_DIR/dani-boot-initramfs-launcher.img"

mkdir -p "$OUTPUT_DIR"
"$ROOT/firmware/unpack-boot.sh" "$BASE_BOOT" "$UNPACKED"

"$LLD" -static --build-id=none -z noexecstack -s -e _start \
	-o "$LAUNCHER" "$ROOT/launcher/dani-launcher.o"
chmod 755 "$LAUNCHER"
"$ROOT/firmware/patch-initramfs-early-launcher.sh" "$RAMDISK/init"
touch -t 202601010000 "$LAUNCHER" "$RAMDISK/init"

(
	cd "$RAMDISK"
	find . -print | LC_ALL=C sort | cpio -o --format newc --owner 0:0 \
		>"$RAMDISK_CPIO" 2>"$OUTPUT_DIR/cpio.log"
)
gzip -n -9 -c "$RAMDISK_CPIO" >"$RAMDISK_GZ"

"$ROOT/firmware/repack-boot-ramdisk.sh" "$BASE_BOOT" "$RAMDISK_GZ" "$CANDIDATE"
"$ROOT/firmware/unpack-boot.sh" "$CANDIDATE" "$VERIFY"

cmp "$UNPACKED/kernel.img" "$VERIFY/kernel.img" || fail "kernel changed"
cmp "$UNPACKED/device-tree.dtb" "$VERIFY/device-tree.dtb" || fail "DTB changed"
cmp "$LAUNCHER" "$VERIFY/ramdisk/opt/dani-launcher" || fail "embedded launcher changed"
grep -q 'DANI_INITRAMFS_LAUNCHER_V1' "$VERIFY/ramdisk/init" || fail "init patch missing"
sh -n "$VERIFY/ramdisk/init" || fail "patched init syntax invalid"

CANDIDATE_SHA=$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')
printf '%s  %s\n' "$CANDIDATE_SHA" "${CANDIDATE##*/}" >"$OUTPUT_DIR/candidate.sha256"

printf '\nInitramfs launcher candidate verified.\n'
printf 'Linked launcher:  %10s bytes\n' "$(stat -f %z "$LAUNCHER")"
printf 'Stock ramdisk:    %10s bytes\n' "$(stat -f %z "$UNPACKED/ramdisk.gz")"
printf 'New ramdisk:      %10s bytes\n' "$(stat -f %z "$RAMDISK_GZ")"
printf 'Candidate SHA-256: %s\n' "$CANDIDATE_SHA"
printf 'Candidate: %s\n' "$CANDIDATE"
