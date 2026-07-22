#!/bin/sh
# Guarded deployment of Bird clean-root v5.0. Only p1/KERNEL is replaced.
# P5 remains byte-untouched for an explicit init.stock/recovery build. Immediate
# setup failures invoke init.stock; a missing input-ready frame is bounded by a
# 20-second watchdog reboot rather than hanging indefinitely.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/dani-sp}
KERNEL=${KERNEL:-$ROOT/kernel/work/bird-clean-root-v5-kernel-a/build/Image}
DTB=${DTB:-$ROOT/kernel/work/bird-clean-root-v5-kernel-a/build/sun50i-h700-anbernic-rg34xx-sp.dtb}
RUNTIME=$DATA/MUOS/runtime/ROCKNIX-SYSTEM
RECOVERY=$DATA/MUOS/Bird/recovery

OLD_KERNEL_SHA=771c4bbb9696775fb135c6d21166106b84939873fd416956d95760f9d4596cf6
NEW_KERNEL_SHA=b585d2b59ffd735e16cfefe1fcafeaf4d2d56831d0d4bd937819a87440a4be64
DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
RUNTIME_SHA=6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac
BIRD_BYTES=134217728
BIRD_OFFSET=16777216
DISK_BYTES=512074186752
ROOT_BYTES=8589934592
ROOT_OFFSET=163577856
DATA_BYTES=503320672768
DATA_OFFSET=8753512448

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

field() {
	diskutil info "$1" | awk -F: -v key="$2" \
		'$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {sub(/^[[:space:]]*/, "", $2); print $2; exit}'
}

disk_bytes() {
	field "$1" 'Disk Size' | sed -n 's/.*(\([0-9][0-9]*\) Bytes).*/\1/p'
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

[ -d "$BIRD" ] || fail "BIRD volume missing: $BIRD"
[ -d "$DATA" ] || fail "data volume missing: $DATA"
[ -f "$KERNEL" ] || fail "clean-root kernel missing: $KERNEL"
[ -f "$DTB" ] || fail "clean-root DTB missing: $DTB"
[ -f "$RUNTIME" ] || fail "native runtime missing: $RUNTIME"

WHOLE=$(field "$BIRD" 'Part of Whole')
[ -n "$WHOLE" ] || fail 'cannot identify card parent'
[ "$WHOLE" = "$(field "$DATA" 'Part of Whole')" ] || \
	fail 'BIRD and data volumes are on different disks'
[ "$(field "/dev/$WHOLE" 'Device Location')" = External ] || \
	fail 'refusing non-external disk'
[ "$(field "/dev/$WHOLE" 'Removable Media')" = Removable ] || \
	fail 'refusing non-removable disk'
[ "$(disk_bytes "/dev/$WHOLE")" = "$DISK_BYTES" ] || \
	fail 'whole-card size changed'
[ "$(field "$BIRD" 'Device Identifier')" = "${WHOLE}s1" ] || \
	fail 'BIRD is not partition 1'
[ "$(field "$DATA" 'Device Identifier')" = "${WHOLE}s6" ] || \
	fail 'data is not partition 6'
[ "$(field "$BIRD" 'Partition Offset' | awk '{print $1}')" = "$BIRD_OFFSET" ] || \
	fail 'BIRD offset changed'
[ "$(disk_bytes "$BIRD")" = "$BIRD_BYTES" ] || fail 'BIRD size changed'
[ "$(field "/dev/${WHOLE}s5" 'Partition Offset' | awk '{print $1}')" = \
	"$ROOT_OFFSET" ] || fail 'p5 offset changed'
[ "$(disk_bytes "/dev/${WHOLE}s5")" = "$ROOT_BYTES" ] || \
	fail 'p5 size changed'
[ "$(field "$DATA" 'Partition Offset' | awk '{print $1}')" = "$DATA_OFFSET" ] || \
	fail 'p6 offset changed'
[ "$(disk_bytes "$DATA")" = "$DATA_BYTES" ] || fail 'p6 size changed'
[ "$(field "$BIRD" 'Volume Read-Only')" = No ] || fail 'BIRD is read-only'
[ "$(field "$DATA" 'Volume Read-Only')" = No ] || fail 'data is read-only'

[ "$(sha256 "$KERNEL")" = "$NEW_KERNEL_SHA" ] || \
	fail 'clean-root kernel checksum mismatch'
[ "$(sha256 "$DTB")" = "$DTB_SHA" ] || fail 'source DTB checksum mismatch'
[ "$(sha256 "$BIRD/dtb.img")" = "$DTB_SHA" ] || fail 'card DTB changed'
[ "$(sha256 "$RUNTIME")" = "$RUNTIME_SHA" ] || \
	fail 'native runtime checksum mismatch'

CURRENT=$(sha256 "$BIRD/KERNEL")
case "$CURRENT" in
	"$OLD_KERNEL_SHA" | "$NEW_KERNEL_SHA") ;;
	*) fail "card kernel is not v4.5 or clean-root v5.0: $CURRENT" ;;
esac

mkdir -p "$RECOVERY"
if [ "$CURRENT" = "$OLD_KERNEL_SHA" ] && [ ! -f "$RECOVERY/KERNEL-v4.5" ]; then
	COPYFILE_DISABLE=1 cp -f "$BIRD/KERNEL" "$RECOVERY/.KERNEL-v4.5.new"
	[ "$(sha256 "$RECOVERY/.KERNEL-v4.5.new")" = "$OLD_KERNEL_SHA" ] || \
		fail 'recovery kernel copy failed verification'
	mv -f "$RECOVERY/.KERNEL-v4.5.new" "$RECOVERY/KERNEL-v4.5"
fi

COPYFILE_DISABLE=1 cp -f "$KERNEL" "$BIRD/.KERNEL.bird-v5.new"
[ "$(sha256 "$BIRD/.KERNEL.bird-v5.new")" = "$NEW_KERNEL_SHA" ] || \
	fail 'temporary card kernel failed verification'
mv -f "$BIRD/.KERNEL.bird-v5.new" "$BIRD/KERNEL"
sync
[ "$(sha256 "$BIRD/KERNEL")" = "$NEW_KERNEL_SHA" ] || \
	fail 'installed clean-root kernel failed verification'

printf 'Bird clean-root v5.0 staged on /dev/%s.\n' "$WHOLE"
printf 'p1/KERNEL changed; p5 and p6 content were not modified except recovery copy.\n'
printf 'Kernel: %s\n' "$NEW_KERNEL_SHA"
printf 'Test: menu, game, return state, brightness, volume, movie, shutdown.\n'
