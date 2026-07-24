#!/bin/sh
set -eu

# Install the Linux-DTB PMIC threshold candidate. The new kernel must boot once
# before it can program the PMIC for the following cold-power attempt.
ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work"
BOOT_DEVICE="/dev/mmcblk0p4"
CANDIDATE="$WORK_DIR/bird-boot-power-key-128.img"
CANDIDATE_SHA_FILE="$WORK_DIR/bird-boot-power-key-128.sha256"
BACKUP="$WORK_DIR/device-boot-before-power-key-128.img"
BACKUP_TEMP="$WORK_DIR/.device-boot-before-power-key-128.tmp"
MARKER="$WORK_DIR/power-key-128-installed"
LOG_FILE="$ROM_MOUNT/MUOS/log/firmware-power-key-128-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/80-install-power-key-128.sh"
BASE_SHA="c8e5e713488bb334e083ba1c686ac3b405ea96b7b98c3e7957ca3f32edec5bf3"
CANDIDATE_SHA="a6bafa83add62af92a27450594f6da4e8dfacdbcc0c247c08c512a7b1495b6b5"
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
log "RG34XX-SP Linux 128 ms power-key installer start"
[ -b "$BOOT_DEVICE" ] || fail "boot partition missing: $BOOT_DEVICE"
[ -f "$CANDIDATE" ] || fail "candidate missing: $CANDIDATE"
[ -f "$CANDIDATE_SHA_FILE" ] || fail "candidate checksum file missing"

read -r LISTED_SHA _ <"$CANDIDATE_SHA_FILE"
[ "$LISTED_SHA" = "$CANDIDATE_SHA" ] || fail "listed candidate checksum mismatch"
[ "$(wc -c <"$CANDIDATE" | tr -d ' ')" -eq "$BOOT_BYTES" ] || fail "candidate size mismatch"
[ "$(sha_file "$CANDIDATE")" = "$CANDIDATE_SHA" ] || fail "candidate checksum mismatch"

CURRENT_SHA=$(sha_boot_partition)
log "current boot SHA-256: $CURRENT_SHA"
if [ "$CURRENT_SHA" = "$CANDIDATE_SHA" ]; then
	printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
	disable_installer
	log "128 ms power-key candidate already installed"
	exit 0
fi
[ "$CURRENT_SHA" = "$BASE_SHA" ] || fail "refusing unknown current boot image"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$BASE_SHA" ] || fail "existing boot backup mismatch"
else
	rm -f "$BACKUP_TEMP"
	dd if="$BOOT_DEVICE" of="$BACKUP_TEMP" bs=1048576 count=64
	sync
	[ "$(sha_file "$BACKUP_TEMP")" = "$BASE_SHA" ] || fail "new boot backup mismatch"
	mv "$BACKUP_TEMP" "$BACKUP"
fi

log "writing verified Linux 128 ms power-key candidate"
dd if="$CANDIDATE" of="$BOOT_DEVICE" bs=1048576 count=64
sync

WRITTEN_SHA=$(sha_boot_partition)
if [ "$WRITTEN_SHA" != "$CANDIDATE_SHA" ]; then
	log "candidate verification failed ($WRITTEN_SHA); restoring previous boot image"
	dd if="$BACKUP" of="$BOOT_DEVICE" bs=1048576 count=64
	sync
	[ "$(sha_boot_partition)" = "$BASE_SHA" ] || fail "automatic boot restore failed"
	fail "candidate write failed; previous boot image restored"
fi

printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
disable_installer
log "SUCCESS: Linux 128 ms power-key candidate raw-verified"
log "boot and shut down once before testing cold-power tap latency"

