#!/bin/sh
set -eu

# One-shot RG34XX-SP installer. This is launched by muOS user-init only after
# ROM storage is mounted. It changes the next boot, never the running kernel.
ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work"
BOOT_DEVICE="/dev/mmcblk0p4"
CANDIDATE="$WORK_DIR/dani-boot-backlight-25.img"
BACKUP="$WORK_DIR/device-boot-before-backlight.img"
BACKUP_TEMP="$WORK_DIR/.device-boot-before-backlight.tmp"
MARKER="$WORK_DIR/backlight-25-installed"
LOG_DIR="$ROM_MOUNT/MUOS/log"
LOG_FILE="$LOG_DIR/firmware-backlight-25-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/98-install-backlight-25.sh"
STOCK_SHA="c16281cd871156d3b1dd01732232da782a50d6a94b463a080524e565e1d4501f"
CANDIDATE_SHA="eab1f16833a69c8e9a04297d87d0dee1b86980d27edc8e027ae3966b352865bd"
BOOT_BYTES=67108864

mkdir -p "$WORK_DIR" "$LOG_DIR"
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
	if [ -f "$CARD_INSTALLER" ]; then
		mv "$CARD_INSTALLER" "$CARD_INSTALLER.done"
	fi
}

fail() {
	log "FAILED: $*"
	exit 1
}

# Keep this one-time maintenance write away from the usable-screen path.
sleep 3
log "RG34XX-SP 25% firmware-backlight installer start"

[ -b "$BOOT_DEVICE" ] || fail "boot partition is not a block device: $BOOT_DEVICE"
[ -f "$CANDIDATE" ] || fail "candidate missing: $CANDIDATE"

CANDIDATE_BYTES=$(wc -c <"$CANDIDATE" | tr -d ' ')
[ "$CANDIDATE_BYTES" -eq "$BOOT_BYTES" ] || fail "candidate size is $CANDIDATE_BYTES, expected $BOOT_BYTES"

ACTUAL_CANDIDATE_SHA=$(sha_file "$CANDIDATE")
[ "$ACTUAL_CANDIDATE_SHA" = "$CANDIDATE_SHA" ] || fail "candidate checksum mismatch: $ACTUAL_CANDIDATE_SHA"

CURRENT_SHA=$(sha_boot_partition)
log "current boot SHA-256: $CURRENT_SHA"

if [ "$CURRENT_SHA" = "$CANDIDATE_SHA" ]; then
	printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
	disable_installer
	log "candidate already installed; installer disabled"
	exit 0
fi

[ "$CURRENT_SHA" = "$STOCK_SHA" ] || fail "refusing unknown current boot image"

if [ -f "$BACKUP" ]; then
	BACKUP_SHA=$(sha_file "$BACKUP")
	[ "$BACKUP_SHA" = "$STOCK_SHA" ] || fail "existing backup checksum mismatch: $BACKUP_SHA"
	log "verified existing stock backup"
else
	rm -f "$BACKUP_TEMP"
	log "backing up active stock boot partition"
	dd if="$BOOT_DEVICE" of="$BACKUP_TEMP" bs=1048576 count=64
	sync
	BACKUP_SHA=$(sha_file "$BACKUP_TEMP")
	[ "$BACKUP_SHA" = "$STOCK_SHA" ] || fail "new backup checksum mismatch: $BACKUP_SHA"
	mv "$BACKUP_TEMP" "$BACKUP"
	log "stock backup complete: $BACKUP"
fi

log "writing verified 25% candidate to $BOOT_DEVICE"
dd if="$CANDIDATE" of="$BOOT_DEVICE" bs=1048576 count=64
sync

WRITTEN_SHA=$(sha_boot_partition)
if [ "$WRITTEN_SHA" != "$CANDIDATE_SHA" ]; then
	log "candidate verification failed ($WRITTEN_SHA); restoring stock backup"
	dd if="$BACKUP" of="$BOOT_DEVICE" bs=1048576 count=64
	sync
	RESTORED_SHA=$(sha_boot_partition)
	[ "$RESTORED_SHA" = "$STOCK_SHA" ] || fail "automatic stock restore also failed: $RESTORED_SHA"
	fail "candidate write failed; stock boot image restored"
fi

printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
disable_installer
log "SUCCESS: candidate verified on raw boot partition"
log "next power cycle will use the fixed 25% firmware brightness"
