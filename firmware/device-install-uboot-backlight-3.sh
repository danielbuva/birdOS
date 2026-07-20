#!/bin/sh
set -eu

# One-shot installer for approximately 1% startup brightness. U-Boot owns the
# inherited panel level, so this writes no userspace brightness value and adds
# no boot process. The raw package is backed up and reread after writing.
ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work/bootloader"
RAW_DEVICE="/dev/mmcblk0"
SECTOR_OFFSET=32800
SECTOR_COUNT=2560
PACKAGE_BYTES=1310720
CANDIDATE="$WORK_DIR/toc1-backlight-3.bin"
CANDIDATE_SHA_FILE="$WORK_DIR/toc1-backlight-3.sha256"
BACKUP="$WORK_DIR/device-toc1-before-backlight-3.bin"
BACKUP_TEMP="$WORK_DIR/.device-toc1-before-backlight-3.tmp"
MARKER="$WORK_DIR/uboot-backlight-3-installed"
LOG_FILE="$ROM_MOUNT/MUOS/log/firmware-uboot-backlight-3-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/92-install-uboot-backlight-3.sh"
BASE_SHA="6330ac906f69a283e76e4a2c4387f6480becefdc1abbadd79fbefd585dccd737"

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

sha_raw_package() {
	dd if="$RAW_DEVICE" bs=512 skip="$SECTOR_OFFSET" count="$SECTOR_COUNT" 2>/dev/null |
		sha256sum | awk '{print $1}'
}

disable_installer() {
	[ ! -f "$CARD_INSTALLER" ] || mv "$CARD_INSTALLER" "$CARD_INSTALLER.done"
}

fail() {
	log "FAILED: $*"
	exit 1
}

sleep 3
log "RG34XX-SP U-Boot one-percent startup-brightness installer start"

[ -b "$RAW_DEVICE" ] || fail "raw card device is missing: $RAW_DEVICE"
[ -f "$CANDIDATE" ] || fail "TOC1 candidate missing: $CANDIDATE"
[ -f "$CANDIDATE_SHA_FILE" ] || fail "TOC1 candidate checksum missing"
[ "$(wc -c <"$CANDIDATE" | tr -d ' ')" -eq "$PACKAGE_BYTES" ] ||
	fail "TOC1 candidate size mismatch"

read -r CANDIDATE_SHA _ <"$CANDIDATE_SHA_FILE"
case "$CANDIDATE_SHA" in
	*[!0-9a-f]* | '') fail "candidate checksum is malformed" ;;
esac
[ "${#CANDIDATE_SHA}" -eq 64 ] || fail "candidate checksum length is not 64"
[ "$(sha_file "$CANDIDATE")" = "$CANDIDATE_SHA" ] ||
	fail "TOC1 candidate checksum mismatch"

CURRENT_SHA=$(sha_raw_package)
log "current raw TOC1 SHA-256: $CURRENT_SHA"

if [ "$CURRENT_SHA" = "$CANDIDATE_SHA" ]; then
	printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
	disable_installer
	log "U-Boot candidate already installed; installer disabled"
	exit 0
fi

[ "$CURRENT_SHA" = "$BASE_SHA" ] || fail "refusing unknown raw TOC1 package"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$BASE_SHA" ] ||
		fail "existing raw-25 TOC1 backup checksum mismatch"
	log "verified existing raw-25 TOC1 backup"
else
	rm -f "$BACKUP_TEMP"
	log "backing up active raw-25 TOC1 package"
	dd if="$RAW_DEVICE" of="$BACKUP_TEMP" bs=512 skip="$SECTOR_OFFSET" count="$SECTOR_COUNT"
	sync
	[ "$(sha_file "$BACKUP_TEMP")" = "$BASE_SHA" ] ||
		fail "new raw-25 TOC1 backup checksum mismatch"
	mv "$BACKUP_TEMP" "$BACKUP"
	log "raw-25 TOC1 backup complete"
fi

log "writing verified raw-backlight=3 TOC1 package"
dd if="$CANDIDATE" of="$RAW_DEVICE" bs=512 seek="$SECTOR_OFFSET" count="$SECTOR_COUNT"
sync

WRITTEN_SHA=$(sha_raw_package)
if [ "$WRITTEN_SHA" != "$CANDIDATE_SHA" ]; then
	log "candidate verification failed ($WRITTEN_SHA); restoring raw-25 TOC1"
	dd if="$BACKUP" of="$RAW_DEVICE" bs=512 seek="$SECTOR_OFFSET" count="$SECTOR_COUNT"
	sync
	[ "$(sha_raw_package)" = "$BASE_SHA" ] || fail "automatic TOC1 restore also failed"
	fail "candidate write failed; raw-25 TOC1 restored"
fi

printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
disable_installer
log "SUCCESS: raw-backlight=3 TOC1 candidate verified"
log "next cold boot inherits raw 3 of 255 (1.18%) with no userspace write"
