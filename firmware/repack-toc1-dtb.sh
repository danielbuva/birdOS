#!/bin/sh
set -eu

INPUT=${1:-}
NEW_DTB=${2:-}
OUTPUT=${3:-}

PACKAGE_BYTES=1310720
HEADER_MAGIC=2299631616       # 0x89119800
CHECKSUM_STAMP=1594518585     # 0x5f0a6c39
ITEM_COUNT=4
DTB_ITEM_HEADER=1164          # 0x48c
DTB_OFFSET=1161216            # 0x11b800
DTB_BYTES=137756              # 0x21a1c
DTB_NODE="/soc@03000000/lcd0@01c0c000"

fail() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

usage() {
	fail "usage: $0 STOCK_TOC1 NEW_UBOOT_DTB OUTPUT_TOC1"
}

read_u32le() {
	od -An -N4 -j "$2" -tu4 "$1" | tr -d ' \n'
}

sum32() {
	od -An -v -tu4 "$1" |
		awk '{for (i = 1; i <= NF; i++) sum = (sum + $i) % 4294967296} END {printf "%.0f\n", sum}'
}

write_u32le() {
	FILE="$1"
	OFFSET="$2"
	VALUE="$3"
	B0=$((VALUE & 255))
	B1=$(((VALUE >> 8) & 255))
	B2=$(((VALUE >> 16) & 255))
	B3=$(((VALUE >> 24) & 255))
	ESCAPED=$(printf '\\%03o\\%03o\\%03o\\%03o' "$B0" "$B1" "$B2" "$B3")
	printf '%b' "$ESCAPED" |
		gdd of="$FILE" bs=1 seek="$OFFSET" conv=notrunc status=none
}

[ -n "$INPUT" ] && [ -n "$NEW_DTB" ] && [ -n "$OUTPUT" ] || usage
[ -f "$INPUT" ] || fail "stock TOC1 package not found: $INPUT"
[ -f "$NEW_DTB" ] || fail "replacement U-Boot DTB not found: $NEW_DTB"
[ "$INPUT" != "$OUTPUT" ] || fail "refusing to modify the source package in place"
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"
command -v gdd >/dev/null 2>&1 || fail "GNU dd is required; install it with: brew install coreutils"
command -v fdtget >/dev/null 2>&1 || fail "fdtget is required; install it with: brew install dtc"

[ "$(wc -c <"$INPUT" | tr -d ' ')" -eq "$PACKAGE_BYTES" ] || \
	fail "TOC1 package size mismatch"
[ "$(wc -c <"$NEW_DTB" | tr -d ' ')" -eq "$DTB_BYTES" ] || \
	fail "replacement DTB size mismatch"
[ "$(gdd if="$INPUT" bs=1 count=13 status=none)" = "sunxi-package" ] || \
	fail "TOC1 package name mismatch"
[ "$(read_u32le "$INPUT" 16)" -eq "$HEADER_MAGIC" ] || \
	fail "TOC1 header magic mismatch"
[ "$(read_u32le "$INPUT" 32)" -eq "$ITEM_COUNT" ] || \
	fail "TOC1 item count mismatch"
[ "$(read_u32le "$INPUT" 36)" -eq "$PACKAGE_BYTES" ] || \
	fail "TOC1 valid-length mismatch"
[ "$(gdd if="$INPUT" bs=1 skip="$DTB_ITEM_HEADER" count=4 status=none)" = "IIE;" ] || \
	fail "DTB item magic mismatch"
[ "$(gdd if="$INPUT" bs=1 skip=$((DTB_ITEM_HEADER + 4)) count=3 status=none)" = "dtb" ] || \
	fail "DTB item name mismatch"
[ "$(read_u32le "$INPUT" $((DTB_ITEM_HEADER + 68)))" -eq "$DTB_OFFSET" ] || \
	fail "DTB item offset mismatch"
[ "$(read_u32le "$INPUT" $((DTB_ITEM_HEADER + 72)))" -eq "$DTB_BYTES" ] || \
	fail "DTB item length mismatch"

ORIGINAL_DTB="${OUTPUT}.original-dtb"
gdd if="$INPUT" of="$ORIGINAL_DTB" bs=1 skip="$DTB_OFFSET" count="$DTB_BYTES" status=none
OLD_LEVEL=$(fdtget -t i "$ORIGINAL_DTB" "$DTB_NODE" lcd_backlight 2>/dev/null || printf '')
rm -f "$ORIGINAL_DTB"
[ -n "$OLD_LEVEL" ] || fail "stock U-Boot DTB is invalid"
NEW_LEVEL=$(fdtget -t i "$NEW_DTB" "$DTB_NODE" lcd_backlight 2>/dev/null || printf '')
[ -n "$NEW_LEVEL" ] || fail "replacement U-Boot DTB is invalid"

cp "$INPUT" "$OUTPUT"
gdd if="$NEW_DTB" of="$OUTPUT" bs=1 seek="$DTB_OFFSET" conv=notrunc status=none

# Allwinner checksum: place the stamp in add_sum, sum every little-endian u32
# across valid_len, then replace the stamp with that sum.
write_u32le "$OUTPUT" 20 "$CHECKSUM_STAMP"
CHECKSUM=$(sum32 "$OUTPUT")
write_u32le "$OUTPUT" 20 "$CHECKSUM"

STORED=$(read_u32le "$OUTPUT" 20)
TOTAL=$(sum32 "$OUTPUT")
RECALCULATED=$(((TOTAL - STORED + CHECKSUM_STAMP) & 0xffffffff))
[ "$STORED" -eq "$RECALCULATED" ] || fail "TOC1 checksum verification failed"

printf 'U-Boot DTB lcd_backlight: %s -> %s\n' "$OLD_LEVEL" "$NEW_LEVEL"
printf 'TOC1 checksum: 0x%08x\n' "$STORED"
shasum -a 256 "$OUTPUT"
