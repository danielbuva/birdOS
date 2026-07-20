#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE_TOC1=${1:-$ROOT/firmware/work/bootloader/toc1-backlight-25.bin}
RAW_LEVEL=${2:-3}
OUTPUT_DIR=${3:-$ROOT/firmware/work/bootloader-backlight-$RAW_LEVEL}
BASE_SHA="6330ac906f69a283e76e4a2c4387f6480becefdc1abbadd79fbefd585dccd737"
PACKAGE_BYTES=1310720
DTB_OFFSET=1161216
DTB_BYTES=137756
DTB_NODE="/soc@03000000/lcd0@01c0c000"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

case "$RAW_LEVEL" in
	'' | *[!0-9]*) fail "raw brightness must be an integer" ;;
esac
[ "$RAW_LEVEL" -ge 1 ] && [ "$RAW_LEVEL" -le 255 ] ||
	fail "raw brightness must be from 1 to 255"
[ -f "$BASE_TOC1" ] || fail "verified U-Boot raw-25 package missing: $BASE_TOC1"
[ ! -e "$OUTPUT_DIR" ] || fail "output already exists: $OUTPUT_DIR"
command -v gdd >/dev/null 2>&1 || fail "GNU dd is required; install coreutils"
command -v fdtget >/dev/null 2>&1 || fail "fdtget is required; install dtc"

[ "$(shasum -a 256 "$BASE_TOC1" | awk '{print $1}')" = "$BASE_SHA" ] ||
	fail "base is not the hardware-verified raw-25 TOC1 package"
[ "$(stat -f %z "$BASE_TOC1")" -eq "$PACKAGE_BYTES" ] ||
	fail "base TOC1 package size mismatch"

mkdir -p "$OUTPUT_DIR"
BASE_DTB="$OUTPUT_DIR/uboot-backlight-25.dtb"
CANDIDATE_DTB="$OUTPUT_DIR/uboot-backlight-$RAW_LEVEL.dtb"
VERIFY_DTB="$OUTPUT_DIR/verify-uboot-backlight-$RAW_LEVEL.dtb"
NO_CHANGE="$OUTPUT_DIR/no-change-toc1.bin"
CANDIDATE="$OUTPUT_DIR/toc1-backlight-$RAW_LEVEL.bin"

gdd if="$BASE_TOC1" of="$BASE_DTB" bs=1 skip="$DTB_OFFSET" \
	count="$DTB_BYTES" status=none
[ "$(fdtget -t i "$BASE_DTB" "$DTB_NODE" lcd_backlight)" -eq 25 ] ||
	fail "base U-Boot DTB does not contain raw brightness 25"

"$ROOT/firmware/repack-toc1-dtb.sh" "$BASE_TOC1" "$BASE_DTB" "$NO_CHANGE"
cmp "$BASE_TOC1" "$NO_CHANGE" || fail "no-change TOC1 repack was not byte-identical"

"$ROOT/firmware/set-backlight-dtb.sh" "$BASE_DTB" "$CANDIDATE_DTB" "$RAW_LEVEL"
"$ROOT/firmware/repack-toc1-dtb.sh" "$BASE_TOC1" "$CANDIDATE_DTB" "$CANDIDATE"
[ "$(stat -f %z "$CANDIDATE")" -eq "$PACKAGE_BYTES" ] ||
	fail "candidate TOC1 package size mismatch"

gdd if="$CANDIDATE" of="$VERIFY_DTB" bs=1 skip="$DTB_OFFSET" \
	count="$DTB_BYTES" status=none
cmp "$CANDIDATE_DTB" "$VERIFY_DTB" || fail "candidate DTB changed during repack"
[ "$(fdtget -t i "$VERIFY_DTB" "$DTB_NODE" lcd_backlight)" -eq "$RAW_LEVEL" ] ||
	fail "repacked U-Boot brightness verification failed"

CHANGED_BYTES=$(cmp -l "$BASE_TOC1" "$CANDIDATE" | wc -l | tr -d ' ')
[ "$CHANGED_BYTES" -eq 2 ] ||
	fail "expected exactly two TOC1 byte changes; found $CHANGED_BYTES"

CANDIDATE_SHA=$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')
DTB_SHA=$(shasum -a 256 "$CANDIDATE_DTB" | awk '{print $1}')
printf '%s  %s\n' "$CANDIDATE_SHA" "${CANDIDATE##*/}" >"$OUTPUT_DIR/candidate.sha256"

printf '\nU-Boot startup-brightness candidate verified.\n'
printf 'Raw brightness:    25 -> %s of 255 (%.2f%%)\n' "$RAW_LEVEL" \
	"$(awk -v value="$RAW_LEVEL" 'BEGIN {print value * 100 / 255}')"
printf 'Changed TOC1 bytes: %s of %s\n' "$CHANGED_BYTES" "$PACKAGE_BYTES"
printf 'DTB SHA-256:       %s\n' "$DTB_SHA"
printf 'Candidate SHA-256: %s\n' "$CANDIDATE_SHA"
printf 'Candidate: %s\n' "$CANDIDATE"
