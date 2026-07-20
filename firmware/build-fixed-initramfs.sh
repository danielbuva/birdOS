#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE_BOOT=${1:-$ROOT/firmware/work/initramfs-launcher/dani-boot-initramfs-launcher.img}
OUTPUT_DIR=${2:-$ROOT/firmware/work/fixed-initramfs}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}
BASE_SHA="316cb568015cf7d13ab5b33ab9b7d5fb8e274de59d5951951e5cbe8449fd5107"
BOOT_BYTES=67108864

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -f "$BASE_BOOT" ] || fail "verified initramfs-launcher base not found: $BASE_BOOT"
[ -x "$CLANG" ] || fail "LLVM clang is required; install it with: brew install llvm"
[ -x "$LLD" ] || fail "LLVM lld is required; install it with: brew install lld"
[ -x "$READELF" ] || fail "llvm-readelf is required: $READELF"
[ ! -e "$OUTPUT_DIR" ] || fail "output already exists: $OUTPUT_DIR"

ACTUAL_BASE_SHA=$(shasum -a 256 "$BASE_BOOT" | awk '{print $1}')
[ "$ACTUAL_BASE_SHA" = "$BASE_SHA" ] ||
	fail "base is not the hardware-verified initramfs-launcher image: $ACTUAL_BASE_SHA"
[ "$(stat -f %z "$BASE_BOOT")" -eq "$BOOT_BYTES" ] ||
	fail "base boot image is not exactly 64 MiB"

UNPACKED="$OUTPUT_DIR/base"
VERIFY="$OUTPUT_DIR/verify"
RAMDISK="$UNPACKED/ramdisk"
STOCK_INIT="$RAMDISK/init.stock"
FIXED_INIT="$RAMDISK/init"
FIXED_INIT_OBJECT="$OUTPUT_DIR/dani-fixed-init.o"
RAMDISK_CPIO="$OUTPUT_DIR/dani-fixed-initramfs.cpio"
RAMDISK_GZ="$OUTPUT_DIR/dani-fixed-initramfs.gz"
CANDIDATE="$OUTPUT_DIR/dani-boot-fixed-initramfs.img"

mkdir -p "$OUTPUT_DIR"
"$ROOT/firmware/unpack-boot.sh" "$BASE_BOOT" "$UNPACKED"
cp -p "$FIXED_INIT" "$STOCK_INIT"

"$CLANG" \
	--target=aarch64-linux-gnu \
	-mcpu=cortex-a53 \
	-O2 \
	-ffreestanding \
	-fno-builtin \
	-fno-stack-protector \
	-fno-unwind-tables \
	-fno-asynchronous-unwind-tables \
	-fno-ident \
	-fvisibility=hidden \
	-nostdlib \
	-Wall -Wextra -Werror \
	-c "$ROOT/firmware/dani-fixed-init.c" \
	-o "$FIXED_INIT_OBJECT"

"$LLD" -static --build-id=none -z noexecstack -s -e _start \
	-o "$FIXED_INIT" "$FIXED_INIT_OBJECT"
chmod 755 "$FIXED_INIT" "$STOCK_INIT"
# Creating init.stock also changes the archive root directory timestamp. Keep
# every entry affected by this build normalized so the compressed ramdisk and
# complete Android boot image are reproducible.
touch -t 202601010000 "$RAMDISK" "$FIXED_INIT" "$STOCK_INIT"

file "$FIXED_INIT" >"$OUTPUT_DIR/fixed-init.file.txt"
grep -q 'ARM aarch64' "$OUTPUT_DIR/fixed-init.file.txt" || fail "fixed init is not AArch64"
grep -q 'statically linked' "$OUTPUT_DIR/fixed-init.file.txt" || fail "fixed init is not static"
if "$READELF" -l "$FIXED_INIT" | grep -q ' INTERP '; then
	fail "fixed init unexpectedly has a program interpreter"
fi

(
	cd "$RAMDISK"
	find . -print | LC_ALL=C sort | cpio -o --format newc --owner 0:0 \
		>"$RAMDISK_CPIO" 2>"$OUTPUT_DIR/cpio.log"
)
"$ROOT/firmware/normalize-newc.py" "$RAMDISK_CPIO"
gzip -n -9 -c "$RAMDISK_CPIO" >"$RAMDISK_GZ"

"$ROOT/firmware/repack-boot-ramdisk.sh" "$BASE_BOOT" "$RAMDISK_GZ" "$CANDIDATE"
"$ROOT/firmware/unpack-boot.sh" "$CANDIDATE" "$VERIFY"

cmp "$UNPACKED/kernel.img" "$VERIFY/kernel.img" || fail "kernel changed"
cmp "$UNPACKED/device-tree.dtb" "$VERIFY/device-tree.dtb" || fail "DTB changed"
cmp "$UNPACKED/ramdisk/opt/dani-launcher" \
	"$VERIFY/ramdisk/opt/dani-launcher" || fail "embedded launcher changed"
cmp "$FIXED_INIT" "$VERIFY/ramdisk/init" || fail "fixed init changed during repack"
cmp "$STOCK_INIT" "$VERIFY/ramdisk/init.stock" || fail "stock fallback changed during repack"
grep -q 'DANI_INITRAMFS_LAUNCHER_V1' "$VERIFY/ramdisk/init.stock" ||
	fail "verified shell fallback marker missing"
[ "$(stat -f %z "$CANDIDATE")" -eq "$BOOT_BYTES" ] ||
	fail "candidate is not exactly 64 MiB"

CANDIDATE_SHA=$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')
FIXED_INIT_SHA=$(shasum -a 256 "$FIXED_INIT" | awk '{print $1}')
printf '%s  %s\n' "$CANDIDATE_SHA" "${CANDIDATE##*/}" >"$OUTPUT_DIR/candidate.sha256"
printf '%s  %s\n' "$FIXED_INIT_SHA" "init" >"$OUTPUT_DIR/fixed-init.sha256"

printf '\nFixed initramfs candidate verified.\n'
printf 'Fixed /init:       %10s bytes  %s\n' "$(stat -f %z "$FIXED_INIT")" "$FIXED_INIT_SHA"
printf 'Shell fallback:    %10s bytes\n' "$(stat -f %z "$STOCK_INIT")"
printf 'Previous ramdisk:  %10s bytes\n' "$(stat -f %z "$UNPACKED/ramdisk.gz")"
printf 'New ramdisk:       %10s bytes\n' "$(stat -f %z "$RAMDISK_GZ")"
printf 'Candidate SHA-256: %s\n' "$CANDIDATE_SHA"
printf 'Candidate: %s\n' "$CANDIDATE"
