#!/bin/sh
set -eu

CARD=${1:-/Volumes/BIRD-DATA}
ACTION=${2:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}
BASE_SHA=872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f
CANDIDATE_SHA=8b9ba42467b9879b94a7f61241fc5065c31206b71da1f29c21c6c13e993f9078
BOOT_BYTES=67108864

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ "$ACTION" = '--restore' ] || fail "usage: $0 /Volumes/BIRD-DATA --restore"
[ -d "$CARD" ] || fail "card volume not mounted: $CARD"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v diskutil >/dev/null 2>&1 || fail 'diskutil is required'
command -v plutil >/dev/null 2>&1 || fail 'plutil is required'

INFO=$(mktemp -t bird-card-info)
RECOVERY=$(mktemp -t bird-mainline-recovery)
MOUNTED=1
cleanup() {
	if [ "$MOUNTED" -eq 0 ]; then
		diskutil mountDisk "/dev/$WHOLE" >/dev/null 2>&1 || true
	fi
	rm -f "$INFO" "$RECOVERY"
}
trap cleanup EXIT HUP INT TERM

diskutil info -plist "$CARD" >"$INFO"
WHOLE=$(plutil -extract ParentWholeDisk raw -o - "$INFO")
VOLUME_ID=$(plutil -extract DeviceIdentifier raw -o - "$INFO")
INTERNAL=$(plutil -extract Internal raw -o - "$INFO")
REMOVABLE=$(plutil -extract Removable raw -o - "$INFO")
[ "$INTERNAL" = false ] || fail 'refusing an internal disk'
[ "$REMOVABLE" = true ] || fail 'refusing non-removable media'
[ "$VOLUME_ID" = "${WHOLE}s6" ] || fail "ROM volume is not partition 6 of $WHOLE"
RAW_BOOT="/dev/r${WHOLE}s4"
[ -e "$RAW_BOOT" ] || fail "boot partition missing: $RAW_BOOT"

BACKUP="$CARD/.firmware-work/device-boot-before-mainline-compat.img"
[ -f "$BACKUP" ] || fail 'device-created recovery image missing'
[ "$(stat -f %z "$BACKUP")" -eq "$BOOT_BYTES" ] || fail 'recovery image size mismatch'
[ "$(shasum -a 256 "$BACKUP" | awk '{print $1}')" = "$BASE_SHA" ] || \
	fail 'recovery image checksum mismatch'
cp "$BACKUP" "$RECOVERY"
[ "$(shasum -a 256 "$RECOVERY" | awk '{print $1}')" = "$BASE_SHA" ] || \
	fail 'host recovery copy mismatch'

CURRENT_SHA=$(sudo "$GDD" if="$RAW_BOOT" bs=1M count=64 status=none |
	shasum -a 256 | awk '{print $1}')
if [ "$CURRENT_SHA" = "$BASE_SHA" ]; then
	printf 'Accepted boot image is already installed on %s.\n' "$RAW_BOOT"
	exit 0
fi
[ "$CURRENT_SHA" = "$CANDIDATE_SHA" ] || fail "refusing unknown boot image: $CURRENT_SHA"

printf 'Restoring accepted boot image to %s (%s).\n' "$RAW_BOOT" "$WHOLE"
diskutil unmountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=0
sudo "$GDD" if="$RECOVERY" of="$RAW_BOOT" bs=1M count=64 conv=fsync status=progress
RESTORED_SHA=$(sudo "$GDD" if="$RAW_BOOT" bs=1M count=64 status=none |
	shasum -a 256 | awk '{print $1}')
[ "$RESTORED_SHA" = "$BASE_SHA" ] || fail "raw restore verification failed: $RESTORED_SHA"
diskutil mountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=1
printf 'Accepted kernel restored and raw-verified. Eject the card before removal.\n'
