#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE_BOOT=${1:-$ROOT/firmware/work/power-key-128-build/dani-boot-power-key-128.img}
OUTPUT_DIR=${2:-$ROOT/firmware/work/trimmed-initramfs}
REMOVE_LIST="$ROOT/firmware/trimmed-initramfs-remove.list"
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}
POWER_BASE_SHA="a6bafa83add62af92a27450594f6da4e8dfacdbcc0c247c08c512a7b1495b6b5"
TRIMMED_BASE_SHA="ff447e7243f7031d99f3559a57868e2116cbf8508fc0654926ef66e5b4460f70"
BOOT_BYTES=67108864

case "$OUTPUT_DIR" in
/*) ;;
*) OUTPUT_DIR="$PWD/$OUTPUT_DIR" ;;
esac

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

compile_static() {
	SOURCE=$1
	OBJECT=$2
	OUTPUT=$3
	shift 3
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
		"$@" \
		-c "$SOURCE" \
		-o "$OBJECT"
	"$LLD" -static --build-id=none -z noexecstack -s -e _start \
		-o "$OUTPUT" "$OBJECT"
	chmod 755 "$OUTPUT"
	file "$OUTPUT" | grep -q 'ARM aarch64.*statically linked' ||
		fail "not a static AArch64 executable: $OUTPUT"
	if "$READELF" -l "$OUTPUT" | grep -q ' INTERP '; then
		fail "program interpreter found in static executable: $OUTPUT"
	fi
}

[ -f "$BASE_BOOT" ] || fail "active power-key boot image missing: $BASE_BOOT"
[ -f "$REMOVE_LIST" ] || fail "trim manifest missing: $REMOVE_LIST"
[ -x "$CLANG" ] || fail "LLVM clang is required"
[ -x "$LLD" ] || fail "LLVM lld is required"
[ -x "$READELF" ] || fail "llvm-readelf is required"
[ ! -e "$OUTPUT_DIR" ] || fail "output already exists: $OUTPUT_DIR"
ACTUAL_BASE_SHA=$(shasum -a 256 "$BASE_BOOT" | awk '{print $1}')
case "$ACTUAL_BASE_SHA" in
"$POWER_BASE_SHA" | "$TRIMMED_BASE_SHA") ;;
*) fail "base is not a hardware-verified fixed initramfs: $ACTUAL_BASE_SHA" ;;
esac
[ "$(stat -f %z "$BASE_BOOT")" -eq "$BOOT_BYTES" ] ||
	fail "base boot image is not exactly 64 MiB"

UNPACKED="$OUTPUT_DIR/base"
VERIFY="$OUTPUT_DIR/verify"
RAMDISK="$UNPACKED/ramdisk"
FIRST_INIT="$RAMDISK/init"
ROOT_INIT="$RAMDISK/opt/dani-root-init"
FIRST_OBJECT="$OUTPUT_DIR/dani-fixed-init-trimmed.o"
ROOT_OBJECT="$OUTPUT_DIR/dani-root-init.o"
RAMDISK_CPIO="$OUTPUT_DIR/dani-trimmed-initramfs.cpio"
RAMDISK_GZ="$OUTPUT_DIR/dani-trimmed-initramfs.gz"
CANDIDATE="$OUTPUT_DIR/dani-boot-trimmed-initramfs.img"

mkdir -p "$OUTPUT_DIR"
"$ROOT/firmware/unpack-boot.sh" "$BASE_BOOT" "$UNPACKED"
find "$RAMDISK" \( -type f -o -type l \) -print | sort \
	>"$OUTPUT_DIR/payload-before.txt"

while read -r KIND RELATIVE; do
	case "$KIND" in
	'' | \#*) continue ;;
	D) rm -rf "$RAMDISK/$RELATIVE" ;;
	F) rm -f "$RAMDISK/$RELATIVE" ;;
	*) fail "invalid trim manifest entry: $KIND $RELATIVE" ;;
	esac
done <"$REMOVE_LIST"

compile_static "$ROOT/firmware/dani-fixed-init.c" "$FIRST_OBJECT" \
	"$FIRST_INIT" -DDANI_STATIC_ROOT_INIT=1
compile_static "$ROOT/firmware/dani-root-init.c" "$ROOT_OBJECT" "$ROOT_INIT"

# Preserve only the exact ext4 repair implementation and its dependency
# closure alongside BusyBox, which remains the deliberate shell fallback.
for REQUIRED in \
	bin/busybox \
	bin/sh \
	sbin/switch_root \
	usr/sbin/e2fsck \
	lib/ld-linux-aarch64.so.1 \
	lib/libc.so.6 \
	lib/libpthread.so.0 \
	lib/libblkid.so.1 \
	lib/libuuid.so.1 \
	usr/lib/libcom_err.so.2 \
	usr/lib/libe2p.so.2 \
	usr/lib/libext2fs.so.2; do
	[ -e "$RAMDISK/$REQUIRED" ] || [ -L "$RAMDISK/$REQUIRED" ] ||
		fail "required recovery payload missing: $REQUIRED"
done

[ ! -e "$RAMDISK/usr/share/misc/magic.mgc" ] || fail "magic database retained"
[ ! -e "$RAMDISK/usr/share/alsa" ] || fail "generic ALSA profiles retained"
[ ! -e "$RAMDISK/usr/bin/file" ] || fail "file utility retained"
[ ! -e "$RAMDISK/usr/sbin/mke2fs" ] || fail "filesystem creator retained"

find "$RAMDISK" \( -type f -o -type l \) -print | sort \
	>"$OUTPUT_DIR/payload-after.txt"
comm -23 "$OUTPUT_DIR/payload-before.txt" "$OUTPUT_DIR/payload-after.txt" \
	>"$OUTPUT_DIR/payload-removed.txt"

# Directory mtimes change when their children are deleted. Normalize every
# directory as well as the two rebuilt executables for reproducible archives.
find "$RAMDISK" -type d -exec touch -t 202601010000 {} +
touch -t 202601010000 "$FIRST_INIT" "$ROOT_INIT"

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
	"$VERIFY/ramdisk/opt/dani-launcher" || fail "launcher changed"
cmp "$UNPACKED/ramdisk/init.stock" \
	"$VERIFY/ramdisk/init.stock" || fail "shell recovery changed"
cmp "$FIRST_INIT" "$VERIFY/ramdisk/init" || fail "first-stage init changed"
cmp "$ROOT_INIT" "$VERIFY/ramdisk/opt/dani-root-init" || fail "root init changed"
[ ! -e "$VERIFY/ramdisk/usr/share/misc/magic.mgc" ] || fail "magic returned"
[ ! -e "$VERIFY/ramdisk/usr/share/alsa" ] || fail "ALSA profiles returned"
[ "$(stat -f %z "$CANDIDATE")" -eq "$BOOT_BYTES" ] ||
	fail "candidate is not exactly 64 MiB"

strings "$VERIFY/ramdisk/init" | grep -q 'fsck-clean-skip' ||
	fail "clean-filesystem policy missing"
strings "$VERIFY/ramdisk/init" | grep -q 'dani-trimmed-initramfs-v1' ||
	fail "trimmed-initramfs marker missing"
strings "$VERIFY/ramdisk/init" | grep -q 'direct-handoff-static-pid1' ||
	fail "direct static PID 1 handoff missing"
strings "$VERIFY/ramdisk/opt/dani-root-init" | grep -q 'dani-root-init-active' ||
	fail "static root PID 1 marker missing"

CANDIDATE_SHA=$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')
FIRST_SHA=$(shasum -a 256 "$FIRST_INIT" | awk '{print $1}')
ROOT_SHA=$(shasum -a 256 "$ROOT_INIT" | awk '{print $1}')
printf '%s  %s\n' "$CANDIDATE_SHA" "${CANDIDATE##*/}" \
	>"$OUTPUT_DIR/candidate.sha256"

printf '\nTrimmed fixed-initramfs candidate verified offline.\n'
printf 'First-stage /init: %10s bytes  %s\n' "$(stat -f %z "$FIRST_INIT")" "$FIRST_SHA"
printf 'Root PID 1:        %10s bytes  %s\n' "$(stat -f %z "$ROOT_INIT")" "$ROOT_SHA"
printf 'Previous ramdisk:  %10s bytes\n' "$(stat -f %z "$UNPACKED/ramdisk.gz")"
printf 'Trimmed ramdisk:   %10s bytes\n' "$(stat -f %z "$RAMDISK_GZ")"
printf 'Removed entries:   %10s\n' "$(wc -l <"$OUTPUT_DIR/payload-removed.txt" | tr -d ' ')"
printf 'Candidate SHA-256: %s\n' "$CANDIDATE_SHA"
printf 'Candidate: %s\n' "$CANDIDATE"
