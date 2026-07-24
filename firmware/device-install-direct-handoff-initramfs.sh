#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work"
BOOT_DEVICE="/dev/mmcblk0p4"
CANDIDATE="$WORK_DIR/bird-boot-direct-handoff-initramfs.img"
CANDIDATE_SHA_FILE="$WORK_DIR/bird-boot-direct-handoff-initramfs.sha256"
BACKUP="$WORK_DIR/device-boot-before-direct-handoff.img"
BACKUP_TEMP="$WORK_DIR/.device-boot-before-direct-handoff.tmp"
MARKER="$WORK_DIR/direct-handoff-initramfs-installed"
LOG_FILE="$ROM_MOUNT/MUOS/log/firmware-direct-handoff-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/58-install-direct-handoff-initramfs.sh"
BASE_SHA="ff447e7243f7031d99f3559a57868e2116cbf8508fc0654926ef66e5b4460f70"
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
	dd if="$BOOT_DEVICE" bs=1048576 count=64 2>/dev/null |
		sha256sum | awk '{print $1}'
}

disable_installer() {
	[ ! -f "$CARD_INSTALLER" ] || mv -f "$CARD_INSTALLER" "$CARD_INSTALLER.done"
}

fail() {
	log "FAILED: $*"
	exit 1
}

sleep 3
log "RG34XX-SP direct-init-handoff installer start"

[ -b "$BOOT_DEVICE" ] || fail "boot partition missing: $BOOT_DEVICE"
[ -f "$CANDIDATE" ] || fail "candidate missing: $CANDIDATE"
[ -f "$CANDIDATE_SHA_FILE" ] || fail "candidate checksum missing"

read -r CANDIDATE_SHA _ <"$CANDIDATE_SHA_FILE"
case "$CANDIDATE_SHA" in
*[!0-9a-f]* | '') fail "candidate checksum is malformed" ;;
esac
[ "${#CANDIDATE_SHA}" -eq 64 ] || fail "candidate checksum length is not 64"
[ "$(wc -c <"$CANDIDATE" | tr -d ' ')" -eq "$BOOT_BYTES" ] ||
	fail "candidate size mismatch"
[ "$(sha_file "$CANDIDATE")" = "$CANDIDATE_SHA" ] ||
	fail "candidate checksum mismatch"

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
	[ "$(sha_file "$BACKUP")" = "$BASE_SHA" ] || fail "existing backup mismatch"
	log "verified existing active-image backup"
else
	rm -f "$BACKUP_TEMP"
	log "backing up active boot partition"
	dd if="$BOOT_DEVICE" of="$BACKUP_TEMP" bs=1048576 count=64
	sync
	[ "$(sha_file "$BACKUP_TEMP")" = "$BASE_SHA" ] || fail "new backup mismatch"
	mv -f "$BACKUP_TEMP" "$BACKUP"
	log "active-image backup complete"
fi

log "writing verified direct-handoff candidate"
dd if="$CANDIDATE" of="$BOOT_DEVICE" bs=1048576 count=64
sync

WRITTEN_SHA=$(sha_boot_partition)
if [ "$WRITTEN_SHA" != "$CANDIDATE_SHA" ]; then
	log "candidate verification failed ($WRITTEN_SHA); restoring backup"
	dd if="$BACKUP" of="$BOOT_DEVICE" bs=1048576 count=64
	sync
	[ "$(sha_boot_partition)" = "$BASE_SHA" ] || fail "automatic restore also failed"
	fail "candidate write failed; previous boot image restored"
fi

printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
disable_installer
log "SUCCESS: direct-init-handoff candidate raw-verified"
log "next power cycle tests BusyBox-free normal handoff"
