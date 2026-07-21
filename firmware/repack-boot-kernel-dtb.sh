#!/bin/sh
set -eu

BOOT=${1:-}
KERNEL=${2:-}
DTB=${3:-}
OUTPUT=${4:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

u32() {
	od -An -j "$2" -N 4 -tu4 "$1" | tr -d ' '
}

pack_u32() {
	perl -e 'print pack("V", shift)' "$1"
}

[ -n "$BOOT" ] && [ -n "$KERNEL" ] && [ -n "$DTB" ] && \
	[ -n "$OUTPUT" ] || \
	fail "usage: $0 BASE_BOOT NEW_KERNEL NEW_DTB OUTPUT_BOOT"
[ -f "$BOOT" ] || fail "boot image not found: $BOOT"
[ -f "$KERNEL" ] || fail "kernel image not found: $KERNEL"
[ -f "$DTB" ] || fail "device tree not found: $DTB"
[ "$BOOT" != "$OUTPUT" ] || fail 'refusing to modify the source boot image in place'
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v openssl >/dev/null 2>&1 || fail 'openssl is required'
command -v perl >/dev/null 2>&1 || fail 'perl is required'

MAGIC=$(dd if="$BOOT" bs=8 count=1 2>/dev/null)
[ "$MAGIC" = 'ANDROID!' ] || fail 'not an Android boot image'

OLD_KERNEL_SIZE=$(u32 "$BOOT" 8)
RAMDISK_SIZE=$(u32 "$BOOT" 16)
SECOND_SIZE=$(u32 "$BOOT" 24)
KERNEL_ADDR=$(u32 "$BOOT" 12)
RAMDISK_ADDR=$(u32 "$BOOT" 20)
PAGE_SIZE=$(u32 "$BOOT" 36)
HEADER_VERSION=$(u32 "$BOOT" 40)
RECOVERY_DTBO_SIZE=$(u32 "$BOOT" 1632)
OLD_DTB_SIZE=$(u32 "$BOOT" 1648)
NEW_KERNEL_SIZE=$(stat -f %z "$KERNEL")
NEW_DTB_SIZE=$(stat -f %z "$DTB")
BOOT_SIZE=$(stat -f %z "$BOOT")

[ "$HEADER_VERSION" -eq 2 ] || \
	fail "expected Android boot header v2; found v$HEADER_VERSION"
[ "$PAGE_SIZE" -eq 2048 ] || fail "expected a 2048-byte page; found $PAGE_SIZE"
[ "$SECOND_SIZE" -eq 0 ] || fail 'second-stage payload is not supported'
[ "$RECOVERY_DTBO_SIZE" -eq 0 ] || fail 'recovery DTBO payload is not supported'

OLD_KERNEL_PAGES=$(((OLD_KERNEL_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
NEW_KERNEL_PAGES=$(((NEW_KERNEL_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
RAMDISK_PAGES=$(((RAMDISK_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
OLD_DTB_PAGES=$(((OLD_DTB_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
NEW_DTB_PAGES=$(((NEW_DTB_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
KERNEL_OFFSET=$PAGE_SIZE
OLD_RAMDISK_OFFSET=$(((1 + OLD_KERNEL_PAGES) * PAGE_SIZE))
NEW_RAMDISK_OFFSET=$(((1 + NEW_KERNEL_PAGES) * PAGE_SIZE))
OLD_DTB_OFFSET=$((OLD_RAMDISK_OFFSET + RAMDISK_PAGES * PAGE_SIZE))
NEW_DTB_OFFSET=$((NEW_RAMDISK_OFFSET + RAMDISK_PAGES * PAGE_SIZE))
OLD_END=$((OLD_DTB_OFFSET + OLD_DTB_PAGES * PAGE_SIZE))
NEW_END=$((NEW_DTB_OFFSET + NEW_DTB_PAGES * PAGE_SIZE))
CLEAR_END=$OLD_END
[ "$NEW_END" -le "$CLEAR_END" ] || CLEAR_END=$NEW_END

[ "$NEW_END" -le "$BOOT_SIZE" ] || \
	fail "new payload exceeds the $BOOT_SIZE-byte boot partition"
[ $((KERNEL_ADDR + NEW_KERNEL_SIZE)) -le "$RAMDISK_ADDR" ] || \
	fail 'loaded kernel overlaps the fixed ramdisk address'

WORK=$(mktemp -d -t dani-kernel-dtb-pack)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
RAMDISK="$WORK/ramdisk.gz"
DIGEST="$WORK/boot-id.sha1"

"$GDD" if="$BOOT" of="$RAMDISK" bs=1M skip="$OLD_RAMDISK_OFFSET" \
	count="$RAMDISK_SIZE" iflag=skip_bytes,count_bytes status=none

cp "$BOOT" "$OUTPUT"
CLEAR_BYTES=$((CLEAR_END - KERNEL_OFFSET))
"$GDD" if=/dev/zero of="$OUTPUT" bs=1M seek="$KERNEL_OFFSET" \
	count="$CLEAR_BYTES" iflag=count_bytes oflag=seek_bytes \
	conv=notrunc status=none
"$GDD" if="$KERNEL" of="$OUTPUT" bs=1M seek="$KERNEL_OFFSET" \
	oflag=seek_bytes conv=notrunc status=none
"$GDD" if="$RAMDISK" of="$OUTPUT" bs=1M seek="$NEW_RAMDISK_OFFSET" \
	oflag=seek_bytes conv=notrunc status=none
"$GDD" if="$DTB" of="$OUTPUT" bs=1M seek="$NEW_DTB_OFFSET" \
	oflag=seek_bytes conv=notrunc status=none

pack_u32 "$NEW_KERNEL_SIZE" | "$GDD" of="$OUTPUT" bs=1 seek=8 \
	conv=notrunc status=none
pack_u32 "$NEW_DTB_SIZE" | "$GDD" of="$OUTPUT" bs=1 seek=1648 \
	conv=notrunc status=none

(
	cat "$KERNEL"
	pack_u32 "$NEW_KERNEL_SIZE"
	cat "$RAMDISK"
	pack_u32 "$RAMDISK_SIZE"
	pack_u32 0
	pack_u32 0
	cat "$DTB"
	pack_u32 "$NEW_DTB_SIZE"
) | openssl dgst -sha1 -binary >"$DIGEST"

"$GDD" if=/dev/zero of="$OUTPUT" bs=1 seek=576 count=32 \
	conv=notrunc status=none
"$GDD" if="$DIGEST" of="$OUTPUT" bs=1 seek=576 conv=notrunc status=none

HEADER_DIGEST=$("$GDD" if="$OUTPUT" bs=1 skip=576 count=20 status=none | xxd -p -c 40)
CALCULATED_DIGEST=$(xxd -p -c 40 "$DIGEST")
[ "$HEADER_DIGEST" = "$CALCULATED_DIGEST" ] || fail 'boot ID verification failed'
[ "$(stat -f %z "$OUTPUT")" -eq "$BOOT_SIZE" ] || fail 'output size changed'

printf 'Repacked boot image with kernel and DTB: %s\n' "$OUTPUT"
printf 'Kernel: %s -> %s bytes; DTB: %s -> %s bytes\n' \
	"$OLD_KERNEL_SIZE" "$NEW_KERNEL_SIZE" "$OLD_DTB_SIZE" "$NEW_DTB_SIZE"
printf 'Ramdisk offset: %s -> %s; SHA-1 ID: %s\n' \
	"$OLD_RAMDISK_OFFSET" "$NEW_RAMDISK_OFFSET" "$HEADER_DIGEST"
