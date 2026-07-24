#!/bin/sh
set -eu

ROM_MOUNT=/mnt/mmc
WORK_DIR="$ROM_MOUNT/.firmware-work"
BOOT_DEVICE=/dev/mmcblk0p4
CANDIDATE="$WORK_DIR/bird-boot-mainline-diagnostic.img"
BACKUP="$WORK_DIR/device-boot-before-mainline-compat.img"
BACKUP_TEMP="$WORK_DIR/.device-boot-before-mainline-diagnostic.tmp"
MARKER="$WORK_DIR/mainline-diagnostic-installed"
LOG_FILE="$ROM_MOUNT/MUOS/log/firmware-mainline-diagnostic-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/58-install-mainline-diagnostic.sh"
BASE_SHA=872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f
CANDIDATE_SHA=8b9ba42467b9879b94a7f61241fc5065c31206b71da1f29c21c6c13e993f9078
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

log 'RG34XX-SP mainline boot-boundary diagnostic installer start'
[ -b "$BOOT_DEVICE" ] || fail "boot partition missing: $BOOT_DEVICE"
[ -f "$CANDIDATE" ] || fail "candidate missing: $CANDIDATE"
[ "$(wc -c <"$CANDIDATE" | tr -d ' ')" -eq "$BOOT_BYTES" ] || \
	fail 'candidate size mismatch'
[ "$(sha_file "$CANDIDATE")" = "$CANDIDATE_SHA" ] || \
	fail 'candidate checksum mismatch'

CURRENT_SHA=$(sha_boot_partition)
log "current boot SHA-256: $CURRENT_SHA"
if [ "$CURRENT_SHA" = "$CANDIDATE_SHA" ]; then
	printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
	disable_installer
	log 'diagnostic already installed; installer disabled'
	exit 0
fi
[ "$CURRENT_SHA" = "$BASE_SHA" ] || fail 'refusing unknown current boot image'

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$BASE_SHA" ] || fail 'existing backup mismatch'
	log 'verified existing accepted-kernel backup'
else
	rm -f "$BACKUP_TEMP"
	log 'backing up accepted boot partition for external recovery'
	dd if="$BOOT_DEVICE" of="$BACKUP_TEMP" bs=1048576 count=64
	sync
	[ "$(sha_file "$BACKUP_TEMP")" = "$BASE_SHA" ] || fail 'new backup mismatch'
	mv -f "$BACKUP_TEMP" "$BACKUP"
	log 'accepted boot backup complete'
fi

log 'writing verified mainline diagnostic candidate'
dd if="$CANDIDATE" of="$BOOT_DEVICE" bs=1048576 count=64
sync

WRITTEN_SHA=$(sha_boot_partition)
if [ "$WRITTEN_SHA" != "$CANDIDATE_SHA" ]; then
	log "candidate verification failed ($WRITTEN_SHA); restoring backup"
	dd if="$BACKUP" of="$BOOT_DEVICE" bs=1048576 count=64
	sync
	[ "$(sha_boot_partition)" = "$BASE_SHA" ] || fail 'automatic restore also failed'
	fail 'candidate write failed; accepted image restored'
fi

printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
disable_installer
log 'SUCCESS: mainline diagnostic candidate raw-verified'
log 'next power cycle: report red LED pattern and screen state'
