#!/bin/sh
# Capture the exact pre-kernel-experiment card state while the RG34XX-SP is off.
#
# The first 156 MiB contains the protective MBR, GPT, Allwinner boot payload,
# boot resources, environment and accepted Android boot image.  Partition 5 is
# the live, customized muOS root filesystem.  The large partition 6 is only the
# destination for the rootfs snapshot and is never read through a raw device.

set -eu

CARD=${1:-/Volumes/BIRD-DATA}
ACTION=${2:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}
PREFIX_BYTES=163577856
ROOTFS_BYTES=8589934592
DISK_BYTES=512074186752
LOCAL_PREFIX=${LOCAL_PREFIX:-$HOME/Downloads/bird-sp-before-rocknix-prefix.img}
CHECKPOINT_DIR="$CARD/.firmware-work/source-kernel-checkpoint"
ROOTFS_IMAGE="$CHECKPOINT_DIR/current-rootfs.ext4"
MANIFEST="$CHECKPOINT_DIR/manifest.sha256"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ "$ACTION" = '--capture' ] || \
	fail "usage: $0 /Volumes/BIRD-DATA --capture"
[ -d "$CARD" ] || fail "card volume not mounted: $CARD"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v diskutil >/dev/null 2>&1 || fail 'diskutil is required'
command -v plutil >/dev/null 2>&1 || fail 'plutil is required'

INFO=$(mktemp -t bird-card-info)
ROOT_INFO=$(mktemp -t bird-root-info)
cleanup() {
	rm -f "$INFO" "$ROOT_INFO"
}
trap cleanup EXIT HUP INT TERM

diskutil info -plist "$CARD" >"$INFO"
WHOLE=$(plutil -extract ParentWholeDisk raw -o - "$INFO")
VOLUME_ID=$(plutil -extract DeviceIdentifier raw -o - "$INFO")
INTERNAL=$(plutil -extract Internal raw -o - "$INFO")
REMOVABLE=$(plutil -extract Removable raw -o - "$INFO")
DISK_SIZE=$(diskutil info -plist "/dev/$WHOLE" |
	plutil -extract Size raw -o - -)
[ "$INTERNAL" = false ] || fail 'refusing an internal disk'
[ "$REMOVABLE" = true ] || fail 'refusing non-removable media'
[ "$DISK_SIZE" = "$DISK_BYTES" ] || fail "unexpected card size: $DISK_SIZE"
[ "$VOLUME_ID" = "${WHOLE}s6" ] || \
	fail "ROM volume is not partition 6 of $WHOLE"

RAW_DISK="/dev/r$WHOLE"
RAW_ROOTFS="/dev/r${WHOLE}s5"
[ -e "$RAW_DISK" ] || fail "whole raw device missing: $RAW_DISK"
[ -e "$RAW_ROOTFS" ] || fail "rootfs raw device missing: $RAW_ROOTFS"
diskutil info -plist "/dev/${WHOLE}s5" >"$ROOT_INFO"
[ "$(plutil -extract Size raw -o - "$ROOT_INFO")" = "$ROOTFS_BYTES" ] || \
	fail 'partition 5 size does not match the fixed RG34XX-SP layout'

mkdir -p "$CHECKPOINT_DIR"
rm -f "$LOCAL_PREFIX.tmp" "$ROOTFS_IMAGE.tmp"

printf 'Capturing exact first 156 MiB from %s...\n' "$RAW_DISK"
sudo "$GDD" if="$RAW_DISK" of="$LOCAL_PREFIX.tmp" bs=1M \
	count=156 iflag=fullblock status=progress
[ "$(stat -f %z "$LOCAL_PREFIX.tmp")" -eq "$PREFIX_BYTES" ] || \
	fail 'short early-disk checkpoint'
mv -f "$LOCAL_PREFIX.tmp" "$LOCAL_PREFIX"

printf 'Capturing exact customized 8 GiB rootfs from %s...\n' "$RAW_ROOTFS"
sudo "$GDD" if="$RAW_ROOTFS" of="$ROOTFS_IMAGE.tmp" bs=4M \
	count=2048 iflag=fullblock status=progress
[ "$(stat -f %z "$ROOTFS_IMAGE.tmp")" -eq "$ROOTFS_BYTES" ] || \
	fail 'short rootfs checkpoint'
mv -f "$ROOTFS_IMAGE.tmp" "$ROOTFS_IMAGE"

cp -f "$LOCAL_PREFIX" "$CHECKPOINT_DIR/current-prefix.img"
(
	cd "$CHECKPOINT_DIR"
	shasum -a 256 current-prefix.img current-rootfs.ext4 >"$MANIFEST.tmp"
	mv -f "$MANIFEST.tmp" "$MANIFEST"
)
sync

printf 'Checkpoint complete. Local recovery prefix:\n  %s\n' "$LOCAL_PREFIX"
printf 'Card-resident rootfs recovery image:\n  %s\n' "$ROOTFS_IMAGE"
printf 'Do not delete either file until the source-kernel trial is restored.\n'
