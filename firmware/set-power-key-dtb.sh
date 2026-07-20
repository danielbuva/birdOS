#!/bin/sh
set -eu

INPUT=${1:-}
OUTPUT=${2:-}
TARGET_MS=${3:-128}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -n "$INPUT" ] && [ -n "$OUTPUT" ] || \
	fail "usage: $0 INPUT_DTB OUTPUT_DTB [ON_TIME_MS]"
[ -f "$INPUT" ] || fail "device tree not found: $INPUT"
[ "$INPUT" != "$OUTPUT" ] || fail "refusing to modify the source DTB in place"
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"
command -v fdtget >/dev/null 2>&1 || fail "fdtget is required"
command -v fdtput >/dev/null 2>&1 || fail "fdtput is required"
[ "$TARGET_MS" -eq 128 ] || fail "this proof permits only the PMIC minimum of 128 ms"

NODE="/soc@03000000/twi@0x07081400/pmu/powerkey@0"
OLD_ON=$(fdtget -t i "$INPUT" "$NODE" pmu_powkey_on_time)
OLD_LONG=$(fdtget -t i "$INPUT" "$NODE" pmu_powkey_long_time)
OLD_OFF=$(fdtget -t i "$INPUT" "$NODE" pmu_powkey_off_time)
[ "$OLD_ON" -eq 512 ] || fail "expected active Linux on-time 512 ms; found $OLD_ON"

cp "$INPUT" "$OUTPUT"
fdtput -t i "$OUTPUT" "$NODE" pmu_powkey_on_time "$TARGET_MS"

NEW_ON=$(fdtget -t i "$OUTPUT" "$NODE" pmu_powkey_on_time)
NEW_LONG=$(fdtget -t i "$OUTPUT" "$NODE" pmu_powkey_long_time)
NEW_OFF=$(fdtget -t i "$OUTPUT" "$NODE" pmu_powkey_off_time)
[ "$NEW_ON" -eq "$TARGET_MS" ] || fail "power-key on-time verification failed"
[ "$NEW_LONG" -eq "$OLD_LONG" ] || fail "long-press threshold changed unexpectedly"
[ "$NEW_OFF" -eq "$OLD_OFF" ] || fail "forced-off threshold changed unexpectedly"

printf 'RG34XX-SP Linux power-key threshold: %s -> %s ms; long/off remain %s/%s ms\n' \
	"$OLD_ON" "$NEW_ON" "$NEW_LONG" "$NEW_OFF"

