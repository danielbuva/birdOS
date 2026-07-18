#!/bin/sh
set -eu

INPUT=${1:-}
OUTPUT=${2:-}
LEVEL=${3:-25}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -n "$INPUT" ] && [ -n "$OUTPUT" ] || \
	fail "usage: $0 INPUT_DTB OUTPUT_DTB [RAW_LEVEL]"
[ -f "$INPUT" ] || fail "device tree not found: $INPUT"
[ "$INPUT" != "$OUTPUT" ] || fail "refusing to modify the source DTB in place"
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"
command -v fdtget >/dev/null 2>&1 || fail "fdtget is required; install it with: brew install dtc"
command -v fdtput >/dev/null 2>&1 || fail "fdtput is required; install it with: brew install dtc"

case "$LEVEL" in
	'' | *[!0-9]*) fail "brightness must be a positive integer" ;;
esac

NODE=""
for CANDIDATE in /lcd0@01c0c000 /soc@03000000/lcd0@01c0c000; do
	if fdtget "$INPUT" "$CANDIDATE" lcd_backlight >/dev/null 2>&1; then
		NODE="$CANDIDATE"
		break
	fi
done
[ -n "$NODE" ] || fail "lcd_backlight property not found"

MAX_LEVEL=$(fdtget -t i "$INPUT" "$NODE" lcd_pwm_max_limit 2>/dev/null || printf 255)
[ "$LEVEL" -ge 1 ] && [ "$LEVEL" -le "$MAX_LEVEL" ] || \
	fail "brightness must be from 1 to $MAX_LEVEL raw driver units"

OLD_LEVEL=$(fdtget -t i "$INPUT" "$NODE" lcd_backlight)
cp "$INPUT" "$OUTPUT"
fdtput -t i "$OUTPUT" "$NODE" lcd_backlight "$LEVEL"
NEW_LEVEL=$(fdtget -t i "$OUTPUT" "$NODE" lcd_backlight)
[ "$NEW_LEVEL" -eq "$LEVEL" ] || fail "device-tree verification failed"

printf 'RG34XX-SP DTB lcd_backlight: %s -> %s raw (maximum %s) (%s)\n' \
	"$OLD_LEVEL" "$NEW_LEVEL" "$MAX_LEVEL" "$OUTPUT"
