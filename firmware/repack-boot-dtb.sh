#!/bin/sh
set -eu

BOOT=${1:-}
DTB=${2:-}
OUTPUT=${3:-}
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

[ -n "$BOOT" ] && [ -n "$DTB" ] && [ -n "$OUTPUT" ] || \
	fail "usage: $0 STOCK_BOOT NEW_DTB OUTPUT_BOOT"
[ -f "$BOOT" ] || fail "boot image not found: $BOOT"
[ -f "$DTB" ] || fail "device tree not found: $DTB"
[ "$BOOT" != "$OUTPUT" ] || fail "refusing to modify the source boot image in place"
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"
[ -x "$GDD" ] || fail "GNU dd is required; install it with: brew install coreutils"
command -v openssl >/dev/null 2>&1 || fail "openssl is required"
command -v perl >/dev/null 2>&1 || fail "perl is required"

MAGIC=$(dd if="$BOOT" bs=8 count=1 2>/dev/null)
[ "$MAGIC" = "ANDROID!" ] || fail "not an Android boot image"

KERNEL_SIZE=$(u32 "$BOOT" 8)
RAMDISK_SIZE=$(u32 "$BOOT" 16)
SECOND_SIZE=$(u32 "$BOOT" 24)
PAGE_SIZE=$(u32 "$BOOT" 36)
HEADER_VERSION=$(u32 "$BOOT" 40)
RECOVERY_DTBO_SIZE=$(u32 "$BOOT" 1632)
OLD_DTB_SIZE=$(u32 "$BOOT" 1648)
NEW_DTB_SIZE=$(stat -f %z "$DTB")

[ "$HEADER_VERSION" -eq 2 ] || fail "expected Android boot header v2; found v$HEADER_VERSION"
[ "$PAGE_SIZE" -eq 2048 ] || fail "expected a 2048-byte page; found $PAGE_SIZE"
[ "$SECOND_SIZE" -eq 0 ] || fail "second-stage payload is not supported"
[ "$RECOVERY_DTBO_SIZE" -eq 0 ] || fail "recovery DTBO payload is not supported"

KERNEL_PAGES=$(((KERNEL_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
RAMDISK_PAGES=$(((RAMDISK_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
OLD_DTB_PAGES=$(((OLD_DTB_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
NEW_DTB_PAGES=$(((NEW_DTB_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
KERNEL_OFFSET=$PAGE_SIZE
RAMDISK_OFFSET=$(((1 + KERNEL_PAGES) * PAGE_SIZE))
DTB_SKIP=$((1 + KERNEL_PAGES + RAMDISK_PAGES))
DTB_OFFSET=$((DTB_SKIP * PAGE_SIZE))
ID_OFFSET=576

[ "$NEW_DTB_PAGES" -le "$OLD_DTB_PAGES" ] || \
	fail "new DTB needs $NEW_DTB_PAGES pages; fixed layout has $OLD_DTB_PAGES"

DIGEST=$(mktemp -t dani-boot-sha1)
trap 'rm -f "$DIGEST"' EXIT HUP INT TERM

cp "$BOOT" "$OUTPUT"

# Preserve every byte outside the fixed DTB slot. Clear the old slot first so
# a shorter replacement cannot leave stale device-tree bytes behind.
"$GDD" if=/dev/zero of="$OUTPUT" bs="$PAGE_SIZE" seek="$DTB_SKIP" \
	count="$OLD_DTB_PAGES" conv=notrunc status=none
"$GDD" if="$DTB" of="$OUTPUT" bs="$PAGE_SIZE" seek="$DTB_SKIP" \
	conv=notrunc status=none
pack_u32 "$NEW_DTB_SIZE" | "$GDD" of="$OUTPUT" bs=1 seek=1648 \
	conv=notrunc status=none

# Android boot header v2 stores SHA-1 over each payload followed by its
# little-endian size. Empty second and recovery-DTBO payloads still contribute
# a zero size. The 20-byte digest occupies the first part of the 32-byte ID.
(
	"$GDD" if="$OUTPUT" bs=1M skip="$KERNEL_OFFSET" count="$KERNEL_SIZE" \
		iflag=skip_bytes,count_bytes status=none
	pack_u32 "$KERNEL_SIZE"
	"$GDD" if="$OUTPUT" bs=1M skip="$RAMDISK_OFFSET" count="$RAMDISK_SIZE" \
		iflag=skip_bytes,count_bytes status=none
	pack_u32 "$RAMDISK_SIZE"
	pack_u32 0
	pack_u32 0
	"$GDD" if="$DTB" bs=1M status=none
	pack_u32 "$NEW_DTB_SIZE"
) | openssl dgst -sha1 -binary >"$DIGEST"

"$GDD" if=/dev/zero of="$OUTPUT" bs=1 seek="$ID_OFFSET" count=32 \
	conv=notrunc status=none
"$GDD" if="$DIGEST" of="$OUTPUT" bs=1 seek="$ID_OFFSET" \
	conv=notrunc status=none

HEADER_DIGEST=$("$GDD" if="$OUTPUT" bs=1 skip="$ID_OFFSET" count=20 status=none | xxd -p -c 40)
CALCULATED_DIGEST=$(xxd -p -c 40 "$DIGEST")
[ "$HEADER_DIGEST" = "$CALCULATED_DIGEST" ] || fail "boot ID verification failed"

printf 'Repacked fixed-layout boot image: %s\n' "$OUTPUT"
printf 'DTB: %s -> %s bytes; SHA-1 ID: %s\n' "$OLD_DTB_SIZE" "$NEW_DTB_SIZE" "$HEADER_DIGEST"
