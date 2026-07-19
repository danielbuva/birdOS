#!/bin/sh
set -eu

# One-shot installer. It runs from user-init after the menu and ROM storage are
# ready, modifies only the next boot, and raw-verifies the entire 64 MiB write.
ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work"
BOOT_DEVICE="/dev/mmcblk0p4"
CANDIDATE="$WORK_DIR/dani-boot-initramfs-launcher.img"
CANDIDATE_SHA_FILE="$WORK_DIR/dani-boot-initramfs-launcher.sha256"
BACKUP="$WORK_DIR/device-boot-before-initramfs-launcher.img"
BACKUP_TEMP="$WORK_DIR/.device-boot-before-initramfs-launcher.tmp"
MARKER="$WORK_DIR/initramfs-launcher-installed"
LOG_FILE="$ROM_MOUNT/MUOS/log/firmware-initramfs-launcher-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/94-install-initramfs-launcher.sh"
BASE_SHA="eab1f16833a69c8e9a04297d87d0dee1b86980d27edc8e027ae3966b352865bd"
BOOT_BYTES=67108864

mkdir -p "$WORK_DIR" "${LOG_FILE%/*}"
: >"$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

uptime_ms() {
	awk '{printf "%d", $1 * 1000}' /proc/uptime
}

log() {
	printf '[%s ms] %s\n' "$(uptime_ms)" "$*"
}

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

sha_boot_partition() {
	dd if="$BOOT_DEVICE" bs=1048576 count=64 2>/dev/null | sha256sum | awk '{print $1}'
}

disable_installer() {
	[ ! -f "$CARD_INSTALLER" ] || mv "$CARD_INSTALLER" "$CARD_INSTALLER.done"
}

fail() {
	log "FAILED: $*"
	exit 1
}

sleep 3
log "RG34XX-SP initramfs-launcher installer start"

[ -b "$BOOT_DEVICE" ] || fail "boot partition missing: $BOOT_DEVICE"
[ -f "$CANDIDATE" ] || fail "candidate missing: $CANDIDATE"
[ -f "$CANDIDATE_SHA_FILE" ] || fail "candidate checksum missing"

read -r CANDIDATE_SHA _ <"$CANDIDATE_SHA_FILE"
case "$CANDIDATE_SHA" in
	*[!0-9a-f]* | '') fail "candidate checksum is malformed" ;;
esac
[ "${#CANDIDATE_SHA}" -eq 64 ] || fail "candidate checksum length is not 64"

CANDIDATE_BYTES=$(wc -c <"$CANDIDATE" | tr -d ' ')
[ "$CANDIDATE_BYTES" -eq "$BOOT_BYTES" ] ||
	fail "candidate size is $CANDIDATE_BYTES, expected $BOOT_BYTES"
ACTUAL_CANDIDATE_SHA=$(sha_file "$CANDIDATE")
[ "$ACTUAL_CANDIDATE_SHA" = "$CANDIDATE_SHA" ] ||
	fail "candidate checksum mismatch: $ACTUAL_CANDIDATE_SHA"

CURRENT_SHA=$(sha_boot_partition)
log "current boot SHA-256: $CURRENT_SHA"

if [ "$CURRENT_SHA" = "$CANDIDATE_SHA" ]; then
	printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
	disable_installer
	log "candidate already installed; installer disabled"
	exit 0
fi

[ "$CURRENT_SHA" = "$BASE_SHA" ] || fail "refusing unknown current boot image"

if [ -f "$BACKUP" ]; then
	BACKUP_SHA=$(sha_file "$BACKUP")
	[ "$BACKUP_SHA" = "$BASE_SHA" ] || fail "existing backup mismatch: $BACKUP_SHA"
	log "verified existing active-image backup"
else
	rm -f "$BACKUP_TEMP"
	log "backing up active boot partition"
	dd if="$BOOT_DEVICE" of="$BACKUP_TEMP" bs=1048576 count=64
	sync
	BACKUP_SHA=$(sha_file "$BACKUP_TEMP")
	[ "$BACKUP_SHA" = "$BASE_SHA" ] || fail "new backup mismatch: $BACKUP_SHA"
	mv "$BACKUP_TEMP" "$BACKUP"
	log "active-image backup complete"
fi

log "writing verified initramfs-launcher candidate"
dd if="$CANDIDATE" of="$BOOT_DEVICE" bs=1048576 count=64
sync

WRITTEN_SHA=$(sha_boot_partition)
if [ "$WRITTEN_SHA" != "$CANDIDATE_SHA" ]; then
	log "candidate verification failed ($WRITTEN_SHA); restoring active-image backup"
	dd if="$BACKUP" of="$BOOT_DEVICE" bs=1048576 count=64
	sync
	RESTORED_SHA=$(sha_boot_partition)
	[ "$RESTORED_SHA" = "$BASE_SHA" ] || fail "automatic restore also failed: $RESTORED_SHA"
	fail "candidate write failed; previous boot image restored"
fi

printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
disable_installer
log "SUCCESS: initramfs-launcher candidate raw-verified"
log "next power cycle starts the menu before switch_root"
