#!/bin/sh
# Restore the current GPT/Anbernic boot chain and customized rootfs after an
# exact ROCKNIX-layout trial.  The local prefix makes partition 6 visible
# again; the rootfs image stored on partition 6 then repairs partition 5.

set -eu

DEVICE=${1:-}
ACTION=${2:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}
PREFIX_BYTES=163577856
ROOTFS_BYTES=8589934592
DISK_BYTES=512074186752
LOCAL_PREFIX=${LOCAL_PREFIX:-$HOME/Downloads/bird-sp-before-rocknix-prefix.img}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -n "$DEVICE" ] && [ "$ACTION" = '--restore' ] || \
	fail "usage: $0 /dev/diskN --restore"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v diskutil >/dev/null 2>&1 || fail 'diskutil is required'
[ -f "$LOCAL_PREFIX" ] || fail "local recovery prefix missing: $LOCAL_PREFIX"
[ "$(stat -f %z "$LOCAL_PREFIX")" -eq "$PREFIX_BYTES" ] || \
	fail 'local recovery prefix size mismatch'

WHOLE=${DEVICE#/dev/}
case "$WHOLE" in
disk[0-9]*) ;;
*) fail 'device must be a whole disk such as /dev/disk4' ;;
esac

INFO=$(mktemp -t bird-card-info)
MOUNTED=1
cleanup() {
	if [ "$MOUNTED" -eq 0 ]; then
		diskutil mountDisk "/dev/$WHOLE" >/dev/null 2>&1 || true
	fi
	rm -f "$INFO"
}
trap cleanup EXIT HUP INT TERM

diskutil info -plist "/dev/$WHOLE" >"$INFO"
INTERNAL=$(plutil -extract Internal raw -o - "$INFO")
REMOVABLE=$(plutil -extract Removable raw -o - "$INFO")
DISK_SIZE=$(plutil -extract Size raw -o - "$INFO")
[ "$INTERNAL" = false ] || fail 'refusing an internal disk'
[ "$REMOVABLE" = true ] || fail 'refusing non-removable media'
[ "$DISK_SIZE" = "$DISK_BYTES" ] || fail "unexpected card size: $DISK_SIZE"

RAW_DISK="/dev/r$WHOLE"
printf 'Restoring the exact GPT and first four partitions to %s...\n' "$RAW_DISK"
diskutil unmountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=0
sudo "$GDD" if="$LOCAL_PREFIX" of="$RAW_DISK" bs=1M count=156 \
	conv=fsync status=progress
PREFIX_SHA=$(shasum -a 256 "$LOCAL_PREFIX" | awk '{print $1}')
DEVICE_PREFIX_SHA=$(sudo "$GDD" if="$RAW_DISK" bs=1M count=156 \
	iflag=fullblock status=none | shasum -a 256 | awk '{print $1}')
[ "$DEVICE_PREFIX_SHA" = "$PREFIX_SHA" ] || \
	fail 'raw early-disk restore verification failed'

diskutil mountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=1
CARD=/Volumes/BIRD-DATA
CHECKPOINT_DIR="$CARD/.firmware-work/source-kernel-checkpoint"
ROOTFS_IMAGE="$CHECKPOINT_DIR/current-rootfs.ext4"
MANIFEST="$CHECKPOINT_DIR/manifest.sha256"
[ -d "$CARD" ] || fail 'restored partition 6 did not mount as /Volumes/BIRD-DATA'
[ -f "$ROOTFS_IMAGE" ] || fail "rootfs recovery image missing: $ROOTFS_IMAGE"
[ -f "$MANIFEST" ] || fail "checkpoint manifest missing: $MANIFEST"
[ "$(stat -f %z "$ROOTFS_IMAGE")" -eq "$ROOTFS_BYTES" ] || \
	fail 'rootfs recovery image size mismatch'
(
	cd "$CHECKPOINT_DIR"
	shasum -a 256 -c manifest.sha256
)

RAW_ROOTFS="/dev/r${WHOLE}s5"
[ -e "$RAW_ROOTFS" ] || fail "restored rootfs partition missing: $RAW_ROOTFS"
diskutil unmount "/dev/${WHOLE}s5" >/dev/null 2>&1 || true
printf 'Restoring the exact customized rootfs to %s...\n' "$RAW_ROOTFS"
sudo "$GDD" if="$ROOTFS_IMAGE" of="$RAW_ROOTFS" bs=4M count=2048 \
	conv=fsync status=progress
ROOTFS_SHA=$(shasum -a 256 "$ROOTFS_IMAGE" | awk '{print $1}')
DEVICE_ROOTFS_SHA=$(sudo "$GDD" if="$RAW_ROOTFS" bs=4M count=2048 \
	iflag=fullblock status=none | shasum -a 256 | awk '{print $1}')
[ "$DEVICE_ROOTFS_SHA" = "$ROOTFS_SHA" ] || \
	fail 'raw rootfs restore verification failed'

diskutil mountDisk "/dev/$WHOLE" >/dev/null
printf 'Exact pre-ROCKNIX card state restored and raw-verified.\n'
