#!/bin/sh
# Update only the mounted FAT boot payload from compatibility v2 to v3.
# The root and data partitions are deliberately untouched.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/dani-sp}
KERNEL=${KERNEL:-$ROOT/kernel/work/rocknix-bird-kernel-compat-v3/build/Image}
CONFIG=${CONFIG:-$ROOT/kernel/rocknix/extlinux-bird.conf}

OLD_KERNEL_SHA=0fa4d5d2d30423302bb83be86761465799b21f0fda396544e09c3e700789f597
NEW_KERNEL_SHA=82f1a2ed941b55f5bb3a79421962f78029fa0559379c0651a4d4c82bd46d8653
DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
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

[ -d "$BIRD" ] || fail "BIRD volume is not mounted: $BIRD"
[ -d "$DATA" ] || fail "data volume is not mounted: $DATA"
[ -f "$KERNEL" ] || fail "rebuilt kernel is missing: $KERNEL"
[ -f "$CONFIG" ] || fail "extlinux configuration is missing: $CONFIG"

BIRD_WHOLE=$(field "$BIRD" 'Part of Whole')
DATA_WHOLE=$(field "$DATA" 'Part of Whole')
[ -n "$BIRD_WHOLE" ] || fail 'cannot identify BIRD parent disk'
[ "$BIRD_WHOLE" = "$DATA_WHOLE" ] || fail 'BIRD and data are not on the same card'
[ "$(field "/dev/$BIRD_WHOLE" 'Device Location')" = 'External' ] || \
	fail 'refusing a non-external disk'
[ "$(field "/dev/$BIRD_WHOLE" 'Removable Media')" = 'Removable' ] || \
	fail 'refusing non-removable media'
[ "$(disk_bytes "/dev/$BIRD_WHOLE")" = "$DISK_BYTES" ] || \
	fail 'whole-card size changed'
[ "$(field "$BIRD" 'Device Identifier')" = "${BIRD_WHOLE}s1" ] || \
	fail 'BIRD is not partition 1'
[ "$(field "$DATA" 'Device Identifier')" = "${BIRD_WHOLE}s6" ] || \
	fail 'data is not partition 6'
[ "$(field "$BIRD" 'Partition Offset' | awk '{print $1}')" = "$BIRD_OFFSET" ] || \
	fail 'BIRD partition offset changed'
[ "$(disk_bytes "$BIRD")" = "$BIRD_BYTES" ] || fail 'BIRD partition size changed'
[ "$(field "/dev/${BIRD_WHOLE}s5" 'Partition Offset' | awk '{print $1}')" = \
	"$ROOT_OFFSET" ] || fail 'root partition offset changed'
[ "$(disk_bytes "/dev/${BIRD_WHOLE}s5")" = "$ROOT_BYTES" ] || \
	fail 'root partition size changed'
[ "$(field "$DATA" 'Partition Offset' | awk '{print $1}')" = "$DATA_OFFSET" ] || \
	fail 'data partition offset changed'
[ "$(disk_bytes "$DATA")" = "$DATA_BYTES" ] || fail 'data partition size changed'
[ "$(field "$BIRD" 'Volume Read-Only')" = 'No' ] || fail 'BIRD is read-only'

[ "$(shasum -a 256 "$KERNEL" | awk '{print $1}')" = "$NEW_KERNEL_SHA" ] || \
	fail 'rebuilt kernel checksum mismatch'
[ "$(shasum -a 256 "$BIRD/dtb.img" | awk '{print $1}')" = "$DTB_SHA" ] || \
	fail 'card DTB is not the verified RG34XX-SP reference'

CURRENT_KERNEL_SHA=$(shasum -a 256 "$BIRD/KERNEL" | awk '{print $1}')
case "$CURRENT_KERNEL_SHA" in
	"$OLD_KERNEL_SHA" | "$NEW_KERNEL_SHA") ;;
	*) fail "card kernel is not an accepted v2/v3 candidate: $CURRENT_KERNEL_SHA" ;;
esac

mkdir -p "$BIRD/extlinux"
COPYFILE_DISABLE=1 cp -f "$KERNEL" "$BIRD/.KERNEL.bird-v3.new"
COPYFILE_DISABLE=1 cp -f "$CONFIG" "$BIRD/extlinux/.extlinux.conf.bird-v3.new"
[ "$(shasum -a 256 "$BIRD/.KERNEL.bird-v3.new" | awk '{print $1}')" = \
	"$NEW_KERNEL_SHA" ] || fail 'temporary card kernel verification failed'
cmp "$CONFIG" "$BIRD/extlinux/.extlinux.conf.bird-v3.new" || \
	fail 'temporary extlinux verification failed'

mv -f "$BIRD/.KERNEL.bird-v3.new" "$BIRD/KERNEL"
mv -f "$BIRD/extlinux/.extlinux.conf.bird-v3.new" \
	"$BIRD/extlinux/extlinux.conf"
sync

[ "$(shasum -a 256 "$BIRD/KERNEL" | awk '{print $1}')" = "$NEW_KERNEL_SHA" ] || \
	fail 'installed card kernel verification failed'
cmp "$CONFIG" "$BIRD/extlinux/extlinux.conf" || \
	fail 'installed extlinux verification failed'

printf 'Bird/source-kernel compatibility v3 staged on /dev/%s.\n' "$BIRD_WHOLE"
printf 'Only p1 was updated; p5 root and p6 data were not written.\n'
printf 'Kernel: %s\n' "$NEW_KERNEL_SHA"
printf 'Next test: early H700 input, D-pad/A/B, suspend/wake, audio and brightness.\n'
