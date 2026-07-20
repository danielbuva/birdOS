#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE=${1:-/Volumes/dani-sp/.firmware-work/dani-boot-static-pid1.img}
WORK=${2:-$ROOT/firmware/work/power-key-128-build}
OUTPUT="$WORK/dani-boot-power-key-128.img"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -f "$BASE" ] || fail "base boot image missing: $BASE"
[ ! -e "$WORK" ] || fail "work directory already exists: $WORK"
mkdir -p "$WORK"

"$ROOT/firmware/unpack-boot.sh" "$BASE" "$WORK/base"
"$ROOT/firmware/set-power-key-dtb.sh" \
	"$WORK/base/device-tree.dtb" "$WORK/power-key-128.dtb" 128
"$ROOT/firmware/repack-boot-dtb.sh" \
	"$BASE" "$WORK/power-key-128.dtb" "$OUTPUT"
"$ROOT/firmware/unpack-boot.sh" "$OUTPUT" "$WORK/verify"

cmp "$WORK/base/kernel.img" "$WORK/verify/kernel.img"
cmp "$WORK/base/ramdisk.gz" "$WORK/verify/ramdisk.gz"

NODE="/soc@03000000/twi@0x07081400/pmu/powerkey@0"
[ "$(fdtget -t i "$WORK/verify/device-tree.dtb" "$NODE" pmu_powkey_on_time)" -eq 128 ] || \
	fail "repacked power-key threshold is not 128 ms"
[ "$(fdtget -t i "$WORK/verify/device-tree.dtb" "$NODE" pmu_powkey_long_time)" -eq 1500 ] || \
	fail "repacked long-press threshold changed"
[ "$(fdtget -t i "$WORK/verify/device-tree.dtb" "$NODE" pmu_powkey_off_time)" -eq 6000 ] || \
	fail "repacked forced-off threshold changed"

shasum -a 256 "$OUTPUT" >"$WORK/candidate.sha256"
printf 'Built and verified Linux 128 ms power-key candidate: %s\n' "$OUTPUT"

