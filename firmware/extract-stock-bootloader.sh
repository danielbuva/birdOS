#!/bin/sh
set -eu

SOURCE=${1:-/Users/dani/Downloads/MustardOS_RG34XX-SP_2601.1_FUNKY_JACARANDA-bc38efa0.img.gz}
OUTPUT=${2:-/Volumes/dani-sp/.firmware-work/bootloader}
PREPARTITION="$OUTPUT/stock-prepartition.img"
TOC1="$OUTPUT/stock-toc1.bin"
DTB="$OUTPUT/stock-uboot.dtb"

fail() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] || fail "source archive not found: $SOURCE"
command -v gdd >/dev/null 2>&1 || fail "GNU dd is required; install it with: brew install coreutils"
command -v fdtget >/dev/null 2>&1 || fail "fdtget is required; install it with: brew install dtc"

mkdir -p "$OUTPUT"
for FILE in "$PREPARTITION" "$TOC1" "$DTB"; do
	[ ! -e "$FILE" ] || fail "refusing to overwrite: $FILE"
done

# Allwinner boot0 and the TOC1/U-Boot package live in the 36 MiB before the
# first GPT partition. GNU dd's fullblock mode is required for a gzip pipe.
gzip -dc "$SOURCE" |
	gdd of="$PREPARTITION" bs=1M count=36 iflag=fullblock status=none

[ "$(wc -c <"$PREPARTITION" | tr -d ' ')" -eq 37748736 ] || \
	fail "pre-partition extraction has the wrong size"

# The H700 ROM loads the package at sector 32800 (0x1004000). Its header says
# the complete checksummed package is 0x140000 bytes.
gdd if="$PREPARTITION" of="$TOC1" bs=1 skip=16793600 count=1310720 status=none

# The fourth TOC1 item is the U-Boot device tree: relative offset 0x11b800,
# exact length 0x21a1c.
gdd if="$TOC1" of="$DTB" bs=1 skip=1161216 count=137756 status=none

[ "$(gdd if="$TOC1" bs=1 count=13 status=none)" = "sunxi-package" ] || \
	fail "TOC1 package magic mismatch"
[ "$(fdtget -t i "$DTB" /soc@03000000/lcd0@01c0c000 lcd_backlight)" -eq 50 ] || \
	fail "unexpected stock U-Boot backlight"

shasum -a 256 "$PREPARTITION" "$TOC1" "$DTB"
