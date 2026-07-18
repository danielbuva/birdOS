#!/bin/sh
set -eu

INPUT=${1:-}
OUTPUT=${2:-}
LEVEL=${3:-25}
NODE="/soc@03000000/lcd0@01c0c000"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -n "$INPUT" ] && [ -n "$OUTPUT" ] || \
	fail "usage: $0 INPUT_DTB OUTPUT_DTB [PERCENT]"
[ -f "$INPUT" ] || fail "device tree not found: $INPUT"
[ "$INPUT" != "$OUTPUT" ] || fail "refusing to modify the source DTB in place"
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"
command -v fdtget >/dev/null 2>&1 || fail "fdtget is required; install it with: brew install dtc"
command -v fdtput >/dev/null 2>&1 || fail "fdtput is required; install it with: brew install dtc"

case "$LEVEL" in
	'' | *[!0-9]*) fail "brightness must be an integer from 1 to 100" ;;
esac
[ "$LEVEL" -ge 1 ] && [ "$LEVEL" -le 100 ] || fail "brightness must be from 1 to 100"

OLD_LEVEL=$(fdtget -t i "$INPUT" "$NODE" lcd_backlight)
cp "$INPUT" "$OUTPUT"
fdtput -t i "$OUTPUT" "$NODE" lcd_backlight "$LEVEL"
NEW_LEVEL=$(fdtget -t i "$OUTPUT" "$NODE" lcd_backlight)
[ "$NEW_LEVEL" -eq "$LEVEL" ] || fail "device-tree verification failed"

printf 'RG34XX-SP DTB lcd_backlight: %s -> %s (%s)\n' "$OLD_LEVEL" "$NEW_LEVEL" "$OUTPUT"
