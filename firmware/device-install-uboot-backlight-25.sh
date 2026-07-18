#!/bin/sh
set -eu

# One-shot RG34XX-SP TOC1 installer. It runs after the usable menu and changes
# only the next cold boot. The candidate sets U-Boot's raw 0..255 backlight
# value from 50 to 25; this is an ownership test, not a claim of 25 percent.
ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work/bootloader"
RAW_DEVICE="/dev/mmcblk0"
SECTOR_OFFSET=32800
SECTOR_COUNT=2560
PACKAGE_BYTES=1310720
CANDIDATE="$WORK_DIR/toc1-backlight-25.bin"
BACKUP="$WORK_DIR/device-toc1-before-backlight.bin"
BACKUP_TEMP="$WORK_DIR/.device-toc1-before-backlight.tmp"
MARKER="$WORK_DIR/uboot-backlight-25-installed"
LOG_DIR="$ROM_MOUNT/MUOS/log"
LOG_FILE="$LOG_DIR/firmware-uboot-backlight-25-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/96-install-uboot-backlight-25.sh"
STOCK_SHA="3973c37b2bc1f0b242c5d89b7a64a864d619dc9d9ae21aee40265c62dfc115e5"
CANDIDATE_SHA="6330ac906f69a283e76e4a2c4387f6480becefdc1abbadd79fbefd585dccd737"

# Refresh the observer so the next boot logs both Linux-DTB and U-Boot handoff
# values. Replacing the file cannot affect the already-running observer.
PROBE_SOURCE="$ROM_MOUNT/.firmware-work/device-backlight-probe.sh"
PROBE_TARGET="/opt/muos/script/init/async/S04backlightprobe.sh"
PROBE_NEW="$PROBE_TARGET.dani-new"
PROBE_SHA="a7ec727e80c2f55c79d09f5f0bec0a7a48d6aea3cf9c3b9c59f1930c8b792bdf"

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

sha_raw_package() {
	dd if="$RAW_DEVICE" bs=512 skip="$SECTOR_OFFSET" count="$SECTOR_COUNT" 2>/dev/null |
		sha256sum | awk '{print $1}'
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

sleep 3
log "RG34XX-SP U-Boot raw-backlight diagnostic installer start"

[ -b "$RAW_DEVICE" ] || fail "raw card device is missing: $RAW_DEVICE"
[ -f "$CANDIDATE" ] || fail "TOC1 candidate missing: $CANDIDATE"
[ "$(wc -c <"$CANDIDATE" | tr -d ' ')" -eq "$PACKAGE_BYTES" ] || \
	fail "TOC1 candidate size mismatch"
[ "$(sha_file "$CANDIDATE")" = "$CANDIDATE_SHA" ] || \
	fail "TOC1 candidate checksum mismatch"

[ -f "$PROBE_SOURCE" ] || fail "updated backlight probe is missing"
[ "$(sha_file "$PROBE_SOURCE")" = "$PROBE_SHA" ] || \
	fail "updated backlight probe checksum mismatch"
cp -f "$PROBE_SOURCE" "$PROBE_NEW"
chmod 755 "$PROBE_NEW"
[ "$(sha_file "$PROBE_NEW")" = "$PROBE_SHA" ] || fail "probe staging verification failed"
mv -f "$PROBE_NEW" "$PROBE_TARGET"
log "updated early backlight observer installed"

CURRENT_SHA=$(sha_raw_package)
log "current raw TOC1 SHA-256: $CURRENT_SHA"

if [ "$CURRENT_SHA" = "$CANDIDATE_SHA" ]; then
	printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
	disable_installer
	log "U-Boot candidate already installed; installer disabled"
	exit 0
fi

[ "$CURRENT_SHA" = "$STOCK_SHA" ] || fail "refusing unknown raw TOC1 package"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$STOCK_SHA" ] || fail "existing TOC1 backup checksum mismatch"
	log "verified existing stock TOC1 backup"
else
	rm -f "$BACKUP_TEMP"
	log "backing up active stock TOC1 package"
	dd if="$RAW_DEVICE" of="$BACKUP_TEMP" bs=512 skip="$SECTOR_OFFSET" count="$SECTOR_COUNT"
	sync
	[ "$(sha_file "$BACKUP_TEMP")" = "$STOCK_SHA" ] || fail "new TOC1 backup checksum mismatch"
	mv "$BACKUP_TEMP" "$BACKUP"
	log "stock TOC1 backup complete"
fi

log "writing verified raw-backlight=25 TOC1 package"
dd if="$CANDIDATE" of="$RAW_DEVICE" bs=512 seek="$SECTOR_OFFSET" count="$SECTOR_COUNT"
sync

WRITTEN_SHA=$(sha_raw_package)
if [ "$WRITTEN_SHA" != "$CANDIDATE_SHA" ]; then
	log "candidate verification failed ($WRITTEN_SHA); restoring stock TOC1"
	dd if="$BACKUP" of="$RAW_DEVICE" bs=512 seek="$SECTOR_OFFSET" count="$SECTOR_COUNT"
	sync
	[ "$(sha_raw_package)" = "$STOCK_SHA" ] || fail "automatic TOC1 restore also failed"
	fail "candidate write failed; stock TOC1 restored"
fi

printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
disable_installer
log "SUCCESS: raw TOC1 candidate verified"
log "next cold boot will test U-Boot lcd_backlight=25 raw (stock was 50 of 255)"
