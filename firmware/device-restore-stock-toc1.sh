#!/bin/sh
set -eu

# Inert recovery helper for a device that still reaches muOS user-init.
ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work/bootloader"
RAW_DEVICE="/dev/mmcblk0"
SECTOR_OFFSET=32800
SECTOR_COUNT=2560
BACKUP="$WORK_DIR/device-toc1-before-backlight.bin"
LOG_FILE="$ROM_MOUNT/MUOS/log/firmware-stock-toc1-restore.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/96-restore-stock-toc1.sh"
STOCK_SHA="3973c37b2bc1f0b242c5d89b7a64a864d619dc9d9ae21aee40265c62dfc115e5"
CANDIDATE_SHA="6330ac906f69a283e76e4a2c4387f6480becefdc1abbadd79fbefd585dccd737"

mkdir -p "$ROM_MOUNT/MUOS/log"
: >"$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

sha_raw_package() {
	dd if="$RAW_DEVICE" bs=512 skip="$SECTOR_OFFSET" count="$SECTOR_COUNT" 2>/dev/null |
		sha256sum | awk '{print $1}'
}

fail() {
	printf 'FAILED: %s\n' "$*"
	exit 1
}

[ -b "$RAW_DEVICE" ] || fail "raw card device missing"
[ -f "$BACKUP" ] || fail "stock TOC1 backup missing"
[ "$(sha_file "$BACKUP")" = "$STOCK_SHA" ] || fail "stock TOC1 backup checksum mismatch"

CURRENT_SHA=$(sha_raw_package)
case "$CURRENT_SHA" in
	"$STOCK_SHA") printf 'stock TOC1 already active\n' ;;
	"$CANDIDATE_SHA")
		dd if="$BACKUP" of="$RAW_DEVICE" bs=512 seek="$SECTOR_OFFSET" count="$SECTOR_COUNT"
		sync
		[ "$(sha_raw_package)" = "$STOCK_SHA" ] || fail "raw TOC1 restore verification failed"
		printf 'stock TOC1 restored and verified\n'
		;;
	*) fail "refusing unknown raw TOC1 package: $CURRENT_SHA" ;;
esac

[ ! -f "$CARD_INSTALLER" ] || mv "$CARD_INSTALLER" "$CARD_INSTALLER.done"
printf 'power cycle to use the restored U-Boot device tree\n'
