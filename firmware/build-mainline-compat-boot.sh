#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE=${1:-$ROOT/firmware/work/fixed-device-dtb-v1/dani-boot-fixed-device-dtb-v1.img}
KERNEL_DIR=${2:-$ROOT/kernel/work/mainline-compat}
WORK=${3:-$ROOT/firmware/work/mainline-compat-boot}
OUTPUT="$WORK/dani-boot-mainline-compat.img"
BASE_SHA=872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f
BOOT_BYTES=67108864

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -f "$BASE" ] || fail "accepted boot image missing: $BASE"
[ "$(shasum -a 256 "$BASE" | awk '{print $1}')" = "$BASE_SHA" ] || \
	fail 'base is not the hardware-verified fixed-device image'
[ -f "$KERNEL_DIR/Image" ] || fail 'mainline Image is missing'
[ -f "$KERNEL_DIR/sun50i-h700-anbernic-rg34xx-sp-dani.dtb" ] || \
	fail 'mainline fixed-device DTB is missing'
[ ! -e "$WORK" ] || fail "work directory already exists: $WORK"
[ "$(stat -f %z "$BASE")" -eq "$BOOT_BYTES" ] || \
	fail 'base boot image is not exactly 64 MiB'

"$ROOT/kernel/audit-mainline-compat.sh" "$KERNEL_DIR"
mkdir -p "$WORK"
"$ROOT/firmware/unpack-boot.sh" "$BASE" "$WORK/base"
"$ROOT/firmware/repack-boot-kernel-dtb.sh" \
	"$BASE" \
	"$KERNEL_DIR/Image" \
	"$KERNEL_DIR/sun50i-h700-anbernic-rg34xx-sp-dani.dtb" \
	"$OUTPUT"
"$ROOT/firmware/unpack-boot.sh" "$OUTPUT" "$WORK/verify"

cmp "$KERNEL_DIR/Image" "$WORK/verify/kernel.img" || fail 'kernel repack mismatch'
cmp "$KERNEL_DIR/sun50i-h700-anbernic-rg34xx-sp-dani.dtb" \
	"$WORK/verify/device-tree.dtb" || fail 'DTB repack mismatch'
cmp "$WORK/base/ramdisk.gz" "$WORK/verify/ramdisk.gz" || \
	fail 'accepted direct-handoff ramdisk changed'
cmp "$WORK/base/ramdisk/init" "$WORK/verify/ramdisk/init" || \
	fail 'accepted first-stage init changed'
cmp "$WORK/base/ramdisk/opt/dani-launcher" \
	"$WORK/verify/ramdisk/opt/dani-launcher" || fail 'launcher changed'

KERNEL_BYTES=$(stat -f %z "$WORK/verify/kernel.img")
KERNEL_ADDR=$(od -An -j 12 -N 4 -tu4 "$OUTPUT" | tr -d ' ')
RAMDISK_ADDR=$(od -An -j 20 -N 4 -tu4 "$OUTPUT" | tr -d ' ')
[ $((KERNEL_ADDR + KERNEL_BYTES)) -le "$RAMDISK_ADDR" ] || \
	fail 'kernel load range overlaps the fixed ramdisk address'
[ "$KERNEL_BYTES" -le 33554432 ] || fail 'kernel exceeds U-Boot 32 MiB bootm limit'
[ "$(stat -f %z "$OUTPUT")" -eq "$BOOT_BYTES" ] || \
	fail 'candidate is not exactly 64 MiB'

shasum -a 256 "$OUTPUT" >"$WORK/candidate.sha256"
printf 'Built non-deploying mainline compatibility boot image: %s\n' "$OUTPUT"
cat "$WORK/candidate.sha256"
