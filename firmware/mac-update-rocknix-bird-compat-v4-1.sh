#!/bin/sh
# Stage Bird source-kernel compatibility v4.1. The embedded initramfs removes
# a failing per-launch PortMaster bind and provides the fixed mainline controls
# service. PortMaster's policy is installed directly on p6; p5 stays untouched.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/dani-sp}
KERNEL=${KERNEL:-$ROOT/kernel/work/rocknix-bird-kernel-compat-v4-1-final-deploy/build/Image}
CONFIG=${CONFIG:-$ROOT/kernel/rocknix/extlinux-bird.conf}
PORT_POLICY=${PORT_POLICY:-$ROOT/kernel/rocknix/root-overrides/portmaster-libgl-mainline.sh}
RUNTIME_TARGET="$DATA/MUOS/runtime/ROCKNIX-SYSTEM"
PORT_POLICY_TARGET="$DATA/MUOS/PortMaster/libgl_muOS.txt"

OLD_KERNEL_SHA=1645639aec0ac16f1b2ef901f1bb922ab89e4ae54352580076bc42cd73fa4c8f
NEW_KERNEL_SHA=dd2a9dd38e33d4625ac774458d13401d90f6f35513c43e63c405eb76a746f47a
DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
RUNTIME_SHA=6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac
PORT_POLICY_SHA=9d65f67c706d23a3b651659c11c6771da039a199b5f03d4e7a8d0d8e689a2e36
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
[ -f "$PORT_POLICY" ] || fail "PortMaster policy is missing: $PORT_POLICY"
[ -f "$RUNTIME_TARGET" ] || fail "installed ROCKNIX runtime is missing: $RUNTIME_TARGET"

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
[ "$(file_bytes "$RUNTIME_TARGET")" = "$RUNTIME_BYTES" ] || \
	fail 'installed ROCKNIX runtime size mismatch'
[ "$(sha256 "$RUNTIME_TARGET")" = "$RUNTIME_SHA" ] || \
	fail 'installed ROCKNIX runtime checksum mismatch'
[ "$(sha256 "$PORT_POLICY")" = "$PORT_POLICY_SHA" ] || \
	fail 'PortMaster policy checksum mismatch'

CURRENT_KERNEL_SHA=$(sha256 "$BIRD/KERNEL")
case "$CURRENT_KERNEL_SHA" in
	"$OLD_KERNEL_SHA" | "$NEW_KERNEL_SHA") ;;
	*) fail "card kernel is not an accepted v4/v4.1 candidate: $CURRENT_KERNEL_SHA" ;;
esac

mkdir -p "$DATA/MUOS/PortMaster" "$BIRD/extlinux"
COPYFILE_DISABLE=1 cp -f "$PORT_POLICY" \
	"$DATA/MUOS/PortMaster/.libgl_muOS.txt.bird-v4-1.new"
COPYFILE_DISABLE=1 cp -f "$KERNEL" "$BIRD/.KERNEL.bird-v4-1.new"
COPYFILE_DISABLE=1 cp -f "$CONFIG" \
	"$BIRD/extlinux/.extlinux.conf.bird-v4-1.new"

[ "$(sha256 "$DATA/MUOS/PortMaster/.libgl_muOS.txt.bird-v4-1.new")" = \
	"$PORT_POLICY_SHA" ] || fail 'temporary PortMaster policy verification failed'
[ "$(sha256 "$BIRD/.KERNEL.bird-v4-1.new")" = "$NEW_KERNEL_SHA" ] || \
	fail 'temporary card kernel verification failed'
cmp "$CONFIG" "$BIRD/extlinux/.extlinux.conf.bird-v4-1.new" || \
	fail 'temporary extlinux verification failed'

mv -f "$DATA/MUOS/PortMaster/.libgl_muOS.txt.bird-v4-1.new" \
	"$PORT_POLICY_TARGET"
mv -f "$BIRD/.KERNEL.bird-v4-1.new" "$BIRD/KERNEL"
mv -f "$BIRD/extlinux/.extlinux.conf.bird-v4-1.new" \
	"$BIRD/extlinux/extlinux.conf"
sync

[ "$(sha256 "$PORT_POLICY_TARGET")" = "$PORT_POLICY_SHA" ] || \
	fail 'installed PortMaster policy verification failed'
[ "$(sha256 "$BIRD/KERNEL")" = "$NEW_KERNEL_SHA" ] || \
	fail 'installed card kernel verification failed'
cmp "$CONFIG" "$BIRD/extlinux/extlinux.conf" || \
	fail 'installed extlinux verification failed'

printf 'Bird/source-kernel compatibility v4.1 staged on /dev/%s.\n' "$BIRD_WHOLE"
printf 'p1 kernel and p6 PortMaster policy were updated; p5 root was not written.\n'
printf 'Kernel:     %s\n' "$NEW_KERNEL_SHA"
printf 'Port policy: %s\n' "$PORT_POLICY_SHA"
printf 'Next test: brightness, volume, MP3, movie, RetroArch, PSP, NDS and a port.\n'
