#!/bin/sh
# Preserve the reference boot's mutable storage and boot evidence before the
# Bird GPT/rootfs checkpoint is restored.

set -eu

DEVICE=${1:-}
ACTION=${2:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}
RESULT=${RESULT:-/Users/dani/rocknix-reference-result}
DISK_BYTES=512074186752
PREFIX_BYTES=16777216
STORAGE_BYTES=268435456

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -n "$DEVICE" ] && [ "$ACTION" = '--capture' ] || \
	fail "usage: $0 /dev/diskN --capture"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v diskutil >/dev/null 2>&1 || fail 'diskutil is required'
command -v plutil >/dev/null 2>&1 || fail 'plutil is required'

WHOLE=${DEVICE#/dev/}
case "$WHOLE" in
disk[0-9]*) ;;
*) fail 'device must be a whole disk such as /dev/disk4' ;;
esac

INFO=$(mktemp -t dani-card-info)
P2_INFO=$(mktemp -t dani-card-p2-info)
cleanup() {
	find "$INFO" "$P2_INFO" -delete
}
trap cleanup EXIT HUP INT TERM

diskutil info -plist "/dev/$WHOLE" >"$INFO"
INTERNAL=$(plutil -extract Internal raw -o - "$INFO")
REMOVABLE=$(plutil -extract Removable raw -o - "$INFO")
DISK_SIZE=$(plutil -extract Size raw -o - "$INFO")
[ "$INTERNAL" = false ] || fail 'refusing an internal disk'
[ "$REMOVABLE" = true ] || fail 'refusing non-removable media'
[ "$DISK_SIZE" = "$DISK_BYTES" ] || fail "unexpected card size: $DISK_SIZE"

diskutil info -plist "/dev/${WHOLE}s2" >"$P2_INFO"
[ "$(plutil -extract Size raw -o - "$P2_INFO")" = "$STORAGE_BYTES" ] || \
	fail 'reference storage partition size mismatch'
[ -d /Volumes/ROCKNIX ] || fail 'ROCKNIX FAT partition is not mounted'
[ -f /Volumes/ROCKNIX/KERNEL ] || fail 'ROCKNIX KERNEL is missing'
[ -f /Volumes/ROCKNIX/SYSTEM ] || fail 'ROCKNIX SYSTEM is missing'
[ -f /Volumes/ROCKNIX/dtb.img ] || fail 'provisioned dtb.img is missing'
[ ! -e "$RESULT" ] || fail "refusing to overwrite result directory: $RESULT"

mkdir -p "$RESULT"
shasum -a 256 \
	/Volumes/ROCKNIX/KERNEL \
	/Volumes/ROCKNIX/SYSTEM \
	/Volumes/ROCKNIX/dtb.img \
	>"$RESULT/payloads.sha256"
COPYFILE_DISABLE=1 cp -fp /Volumes/ROCKNIX/extlinux/extlinux.conf \
	"$RESULT/extlinux.conf"

printf 'Capturing the post-boot 16 MiB MBR/SPL/U-Boot prefix...\n'
sudo "$GDD" if="/dev/r$WHOLE" of="$RESULT/boot-prefix-16m.bin" \
	bs=1M count=16 iflag=fullblock status=progress
[ "$(stat -f %z "$RESULT/boot-prefix-16m.bin")" -eq "$PREFIX_BYTES" ] || \
	fail 'short boot-prefix capture'

printf 'Capturing the post-boot 256 MiB storage filesystem...\n'
sudo "$GDD" if="/dev/r${WHOLE}s2" of="$RESULT/storage.ext4" \
	bs=4M count=64 iflag=fullblock status=progress
[ "$(stat -f %z "$RESULT/storage.ext4")" -eq "$STORAGE_BYTES" ] || \
	fail 'short storage capture'

(
	cd "$RESULT"
	shasum -a 256 boot-prefix-16m.bin storage.ext4 >raw.sha256
)
sync
printf 'ROCKNIX reference result captured under:\n  %s\n' "$RESULT"
