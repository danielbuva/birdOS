#!/bin/sh
set -eu

# One-shot installer for the fixed C /init candidate. The current boot remains
# untouched until the menu and ROM partition are available. The entire 64 MiB
# boot partition is backed up, written, reread, and restored on any mismatch.
ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work"
BOOT_DEVICE="/dev/mmcblk0p4"
CANDIDATE="$WORK_DIR/dani-boot-fixed-initramfs.img"
CANDIDATE_SHA_FILE="$WORK_DIR/dani-boot-fixed-initramfs.sha256"
BACKUP="$WORK_DIR/device-boot-before-fixed-initramfs.img"
BACKUP_TEMP="$WORK_DIR/.device-boot-before-fixed-initramfs.tmp"
MARKER="$WORK_DIR/fixed-initramfs-installed"
LOG_FILE="$ROM_MOUNT/MUOS/log/firmware-fixed-initramfs-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/93-install-fixed-initramfs.sh"
BASE_SHA="316cb568015cf7d13ab5b33ab9b7d5fb8e274de59d5951951e5cbe8449fd5107"
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
log "RG34XX-SP fixed-initramfs installer start"

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

log "writing verified fixed-initramfs candidate"
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
log "SUCCESS: fixed-initramfs candidate raw-verified"
log "next power cycle tests static /init with stock root PID 1 fallback"
