#!/bin/sh
# Stage Bird source-kernel userspace compatibility v4.  The verified kernel is
# updated on p1 and a pinned, read-only ROCKNIX runtime is installed on p6.
# The preserved muOS root partition (p5) is deliberately untouched.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/BIRD-DATA}
KERNEL=${KERNEL:-$ROOT/kernel/work/rocknix-bird-kernel-compat-v4-final-deploy/build/Image}
CONFIG=${CONFIG:-$ROOT/kernel/rocknix/extlinux-bird.conf}
ROCKNIX_SYSTEM=${ROCKNIX_SYSTEM:-/Volumes/ROCKNIX/SYSTEM}
RUNTIME_DIR="$DATA/MUOS/runtime"
RUNTIME_TARGET="$RUNTIME_DIR/ROCKNIX-SYSTEM"

OLD_KERNEL_SHA=82f1a2ed941b55f5bb3a79421962f78029fa0559379c0651a4d4c82bd46d8653
NEW_KERNEL_SHA=1645639aec0ac16f1b2ef901f1bb922ab89e4ae54352580076bc42cd73fa4c8f
DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
RUNTIME_SHA=6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac
RUNTIME_BYTES=1206476800
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

file_bytes() {
	stat -f '%z' "$1"
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

[ -d "$BIRD" ] || fail "BIRD volume is not mounted: $BIRD"
[ -d "$DATA" ] || fail "data volume is not mounted: $DATA"
[ -f "$KERNEL" ] || fail "rebuilt kernel is missing: $KERNEL"
[ -f "$CONFIG" ] || fail "extlinux configuration is missing: $CONFIG"
[ -f "$ROCKNIX_SYSTEM" ] || fail "ROCKNIX runtime is missing: $ROCKNIX_SYSTEM"

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
[ "$(field "$DATA" 'Volume Read-Only')" = 'No' ] || fail 'data volume is read-only'

[ "$(sha256 "$KERNEL")" = "$NEW_KERNEL_SHA" ] || \
	fail 'rebuilt kernel checksum mismatch'
[ "$(sha256 "$BIRD/dtb.img")" = "$DTB_SHA" ] || \
	fail 'card DTB is not the verified RG34XX-SP reference'
[ "$(file_bytes "$ROCKNIX_SYSTEM")" = "$RUNTIME_BYTES" ] || \
	fail 'ROCKNIX runtime size mismatch'
[ "$(sha256 "$ROCKNIX_SYSTEM")" = "$RUNTIME_SHA" ] || \
	fail 'ROCKNIX runtime checksum mismatch'

CURRENT_KERNEL_SHA=$(sha256 "$BIRD/KERNEL")
case "$CURRENT_KERNEL_SHA" in
	"$OLD_KERNEL_SHA" | "$NEW_KERNEL_SHA") ;;
	*) fail "card kernel is not an accepted v3/v4 candidate: $CURRENT_KERNEL_SHA" ;;
esac

mkdir -p "$RUNTIME_DIR"
if [ -f "$RUNTIME_TARGET" ] && \
	[ "$(file_bytes "$RUNTIME_TARGET")" = "$RUNTIME_BYTES" ] && \
	[ "$(sha256 "$RUNTIME_TARGET")" = "$RUNTIME_SHA" ]; then
	printf 'Verified runtime already present; reusing it.\n'
else
	COPYFILE_DISABLE=1 cp -f "$ROCKNIX_SYSTEM" \
		"$RUNTIME_DIR/.ROCKNIX-SYSTEM.bird-v4.new"
	[ "$(file_bytes "$RUNTIME_DIR/.ROCKNIX-SYSTEM.bird-v4.new")" = \
		"$RUNTIME_BYTES" ] || fail 'temporary runtime size verification failed'
	[ "$(sha256 "$RUNTIME_DIR/.ROCKNIX-SYSTEM.bird-v4.new")" = \
		"$RUNTIME_SHA" ] || fail 'temporary runtime checksum verification failed'
	mv -f "$RUNTIME_DIR/.ROCKNIX-SYSTEM.bird-v4.new" "$RUNTIME_TARGET"
fi

mkdir -p "$BIRD/extlinux"
COPYFILE_DISABLE=1 cp -f "$KERNEL" "$BIRD/.KERNEL.bird-v4.new"
COPYFILE_DISABLE=1 cp -f "$CONFIG" "$BIRD/extlinux/.extlinux.conf.bird-v4.new"
[ "$(sha256 "$BIRD/.KERNEL.bird-v4.new")" = "$NEW_KERNEL_SHA" ] || \
	fail 'temporary card kernel verification failed'
cmp "$CONFIG" "$BIRD/extlinux/.extlinux.conf.bird-v4.new" || \
	fail 'temporary extlinux verification failed'

mv -f "$BIRD/.KERNEL.bird-v4.new" "$BIRD/KERNEL"
mv -f "$BIRD/extlinux/.extlinux.conf.bird-v4.new" \
	"$BIRD/extlinux/extlinux.conf"
sync

[ "$(sha256 "$RUNTIME_TARGET")" = "$RUNTIME_SHA" ] || \
	fail 'installed runtime verification failed'
[ "$(sha256 "$BIRD/KERNEL")" = "$NEW_KERNEL_SHA" ] || \
	fail 'installed card kernel verification failed'
cmp "$CONFIG" "$BIRD/extlinux/extlinux.conf" || \
	fail 'installed extlinux verification failed'

printf 'Bird/source-kernel compatibility v4 staged on /dev/%s.\n' "$BIRD_WHOLE"
printf 'p1 kernel and p6 on-demand runtime were updated; p5 root was not written.\n'
printf 'Kernel:  %s\n' "$NEW_KERNEL_SHA"
printf 'Runtime: %s\n' "$RUNTIME_SHA"
printf 'Next test: brightness, MP3, movie controls, RetroArch, PSP, NDS and a port.\n'
