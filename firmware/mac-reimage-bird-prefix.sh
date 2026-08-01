#!/bin/sh
# Recreate the fixed Bird MBR/FAT prefix while preserving p5 root and p6 data.
# The recovery oracle and v3 prefix are written and verified in one unmounted
# transaction so macOS cannot mutate the intermediate GPT environment volume.

set -eu

DEVICE=${1:-}
ACTION=${2:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}
RECOVERY_PREFIX=${RECOVERY_PREFIX:-$HOME/muos-kernel-source/checkpoints/20260721-bird-current-prefix.img}
BIRD_PREFIX=${BIRD_PREFIX:-$HOME/birdOS/kernel/work/rocknix-bird-prefix-compat-v3/bird-rocknix-prefix.img}

PREFIX_BYTES=163577856
RECOVERY_SHA=0bcacc83bf7345306ef7615be1012b5c7dd0a92630cf764f34b049f88e9b9f78
BIRD_PREFIX_SHA=6f5f6cec067c9e03c088d629c9a31f9f382d6302e1095fbacd66fde1476761cb
BIRD_KERNEL_SHA=82f1a2ed941b55f5bb3a79421962f78029fa0559379c0651a4d4c82bd46d8653
BIRD_DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
BIRD_CONFIG_SHA=c71cbdad3a43d400435af1d94edac992cb15355dac8d3ba21fc644994ef0b393
DISK_BYTES=512074186752
ROOT_OFFSET=163577856
ROOT_BYTES=8589934592
DATA_OFFSET=8753512448
DATA_BYTES=503320672768

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

plist_value() {
	diskutil info -plist "$1" | plutil -extract "$2" raw -o - -
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/mac-removable-device.sh"

[ -n "$DEVICE" ] && [ "$ACTION" = '--reimage-bird-prefix' ] ||
	fail "usage: $0 /dev/diskN --reimage-bird-prefix"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v diskutil >/dev/null 2>&1 || fail 'diskutil is required'
command -v plutil >/dev/null 2>&1 || fail 'plutil is required'

for IMAGE in "$RECOVERY_PREFIX" "$BIRD_PREFIX"; do
	[ -f "$IMAGE" ] || fail "prefix artifact missing: $IMAGE"
	[ "$(stat -f %z "$IMAGE")" -eq "$PREFIX_BYTES" ] ||
		fail "prefix artifact size mismatch: $IMAGE"
done
[ "$(sha256 "$RECOVERY_PREFIX")" = "$RECOVERY_SHA" ] ||
	fail 'local recovery prefix checksum mismatch'
[ "$(sha256 "$BIRD_PREFIX")" = "$BIRD_PREFIX_SHA" ] ||
	fail 'local Bird v3 prefix checksum mismatch'

WHOLE=${DEVICE#/dev/}
case "$WHOLE" in
disk[0-9]*) ;;
*) fail 'device must be a whole disk such as /dev/disk4' ;;
esac
bird_require_safe_removable_device "/dev/$WHOLE"
[ "$(plist_value "/dev/$WHOLE" Size)" = "$DISK_BYTES" ] ||
	fail 'unexpected card size'
[ "$(plist_value "/dev/${WHOLE}s5" PartitionMapPartitionOffset)" = "$ROOT_OFFSET" ] ||
	fail 'current root partition offset differs from the fixed contract'
[ "$(plist_value "/dev/${WHOLE}s5" Size)" = "$ROOT_BYTES" ] ||
	fail 'current root partition size differs from the fixed contract'
[ "$(plist_value "/dev/${WHOLE}s6" PartitionMapPartitionOffset)" = "$DATA_OFFSET" ] ||
	fail 'current data partition offset differs from the fixed contract'
[ "$(plist_value "/dev/${WHOLE}s6" Size)" = "$DATA_BYTES" ] ||
	fail 'current data partition size differs from the fixed contract'

RAW_DISK=/dev/r$WHOLE
MOUNTED=1
cleanup() {
	if [ "$MOUNTED" -eq 0 ]; then
		diskutil mountDisk "/dev/$WHOLE" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT HUP INT TERM

printf 'Reimaging the fixed Bird prefix on %s...\n' "$RAW_DISK"
diskutil unmountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=0

sudo "$GDD" if="$RECOVERY_PREFIX" of="$RAW_DISK" bs=4M \
	conv=fsync,notrunc status=progress
# Rewriting the partition table can make Disk Arbitration rediscover and
# automatically mount p6 even though the whole disk was unmounted above.
# Quiesce it again before the raw verification and the second prefix write.
diskutil unmountDisk "/dev/$WHOLE" >/dev/null
DEVICE_SHA=$(sudo "$GDD" if="$RAW_DISK" bs=4M count="$PREFIX_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')
[ "$DEVICE_SHA" = "$RECOVERY_SHA" ] ||
	fail "intermediate recovery verification failed: $DEVICE_SHA"

sudo "$GDD" if="$BIRD_PREFIX" of="$RAW_DISK" bs=4M \
	conv=fsync,notrunc status=progress

# Disk Arbitration may mount the new FAT immediately and Spotlight may add
# filesystem metadata before a whole-prefix reread can open the raw device.
# Prefer the raw digest when the disk can be quiesced in time; otherwise verify
# every boot payload after mounting.  The source image digest, fixed geometry,
# and complete three-file payload still remain independently covered.
RAW_VERIFIED=0
if diskutil unmountDisk force "/dev/$WHOLE" >/dev/null 2>&1; then
	DEVICE_SHA=$(sudo "$GDD" if="$RAW_DISK" bs=4M count="$PREFIX_BYTES" \
		iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')
	if [ "$DEVICE_SHA" = "$BIRD_PREFIX_SHA" ]; then
		RAW_VERIFIED=1
	fi
fi

diskutil mountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=1
[ "$(plist_value "/dev/${WHOLE}s5" PartitionMapPartitionOffset)" = "$ROOT_OFFSET" ] ||
	fail 'reimaged root partition offset is wrong'
[ "$(plist_value "/dev/${WHOLE}s5" Size)" = "$ROOT_BYTES" ] ||
	fail 'reimaged root partition size is wrong'
[ "$(plist_value "/dev/${WHOLE}s6" PartitionMapPartitionOffset)" = "$DATA_OFFSET" ] ||
	fail 'reimaged data partition offset is wrong'
[ "$(plist_value "/dev/${WHOLE}s6" Size)" = "$DATA_BYTES" ] ||
	fail 'reimaged data partition size is wrong'
BIRD_MOUNT=$(plist_value "/dev/${WHOLE}s1" MountPoint)
[ -d "$BIRD_MOUNT" ] && [ ! -L "$BIRD_MOUNT" ] ||
	fail 'reimaged BIRD volume did not mount safely'
[ "$(sha256 "$BIRD_MOUNT/KERNEL")" = "$BIRD_KERNEL_SHA" ] ||
	fail 'reimaged Bird kernel verification failed'
[ "$(sha256 "$BIRD_MOUNT/dtb.img")" = "$BIRD_DTB_SHA" ] ||
	fail 'reimaged Bird DTB verification failed'
[ "$(sha256 "$BIRD_MOUNT/extlinux/extlinux.conf")" = "$BIRD_CONFIG_SHA" ] ||
	fail 'reimaged Bird extlinux verification failed'

if [ "$RAW_VERIFIED" -eq 1 ]; then
	printf 'Bird v3 prefix installed and raw-verified.\n'
else
	printf 'Bird v3 prefix installed; all boot payloads verified after macOS metadata mount.\n'
fi
printf 'The existing p5 root and p6 data bytes were not written.\n'
