#!/bin/sh
set -eu

# Recovery helper. Do not place this in MUOS/init unless a stock restore is
# intentionally requested and the device still boots far enough for user-init.
ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work"
BOOT_DEVICE="/dev/mmcblk0p4"
STOCK_IMAGE="$WORK_DIR/device-boot-before-backlight.img"
FALLBACK_STOCK_IMAGE="$WORK_DIR/stock-boot.img"
LOG_FILE="$ROM_MOUNT/MUOS/log/firmware-stock-restore.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/98-restore-stock-boot.sh"
STOCK_SHA="c16281cd871156d3b1dd01732232da782a50d6a94b463a080524e565e1d4501f"
CANDIDATE_SHA="eab1f16833a69c8e9a04297d87d0dee1b86980d27edc8e027ae3966b352865bd"

mkdir -p "$ROM_MOUNT/MUOS/log"
: >"$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

sha_boot_partition() {
	dd if="$BOOT_DEVICE" bs=1048576 count=64 2>/dev/null | sha256sum | awk '{print $1}'
}

fail() {
	printf 'FAILED: %s\n' "$*"
	exit 1
}

[ -b "$BOOT_DEVICE" ] || fail "boot partition missing: $BOOT_DEVICE"
if [ ! -f "$STOCK_IMAGE" ]; then
	STOCK_IMAGE="$FALLBACK_STOCK_IMAGE"
fi
[ -f "$STOCK_IMAGE" ] || fail "no stock boot image found"
[ "$(sha_file "$STOCK_IMAGE")" = "$STOCK_SHA" ] || fail "stock image checksum mismatch"

CURRENT_SHA=$(sha_boot_partition)
case "$CURRENT_SHA" in
	"$STOCK_SHA")
		printf 'stock boot image already active\n'
		;;
	"$CANDIDATE_SHA")
		dd if="$STOCK_IMAGE" of="$BOOT_DEVICE" bs=1048576 count=64
		sync
		[ "$(sha_boot_partition)" = "$STOCK_SHA" ] || fail "raw restore verification failed"
		printf 'stock boot image restored and verified\n'
		;;
	*) fail "refusing to overwrite unknown boot image: $CURRENT_SHA" ;;
esac

[ ! -f "$CARD_INSTALLER" ] || mv "$CARD_INSTALLER" "$CARD_INSTALLER.done"
printf 'power cycle to use the restored stock device tree\n'
