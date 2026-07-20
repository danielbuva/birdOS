#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/fixed-storage"
SOURCE="$WORK_DIR/fixed-union.sh"
TARGET="/opt/muos/script/mount/union.sh"
BACKUP="$WORK_DIR/backup/union.sh.stock"
MARKER="$WORK_DIR/fixed-union-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/84-install-fixed-union.sh"
STOCK_SHA="813a874a1476008601b2284beab245aac66a5046a32b7b524ace50f7a9a9f633"
FIXED_SHA="3c7b804789b865d6f088ad738ff26b293f03513d9291419a601f71b6f4305c0f"
TEMP="/opt/muos/script/mount/.union.sh.dani-fixed-new"

mkdir -p "$WORK_DIR/backup"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

disable_installer() {
	[ ! -f "$CARD_INSTALLER" ] || mv "$CARD_INSTALLER" "$CARD_INSTALLER.done"
}

fail() {
	printf 'FAILED: %s\n' "$*"
	exit 1
}

printf 'fixed one-card union replacement installer start\n'
[ -f "$SOURCE" ] || fail "fixed-union source missing"
[ -f "$TARGET" ] || fail "union.sh target missing"
[ "$(sha_file "$SOURCE")" = "$FIXED_SHA" ] || fail "fixed-union source checksum mismatch"

CURRENT_SHA=$(sha_file "$TARGET")
printf 'current target SHA-256: %s\n' "$CURRENT_SHA"
if [ "$CURRENT_SHA" = "$FIXED_SHA" ]; then
	printf '%s\n' "$FIXED_SHA" >"$MARKER"
	disable_installer
	printf 'fixed one-card union replacement already installed\n'
	exit 0
fi
[ "$CURRENT_SHA" = "$STOCK_SHA" ] || fail "refusing unknown union.sh"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$STOCK_SHA" ] || fail "existing stock union backup mismatch"
else
	cp "$TARGET" "$BACKUP"
	[ "$(sha_file "$BACKUP")" = "$STOCK_SHA" ] || fail "new stock union backup mismatch"
fi

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
[ "$(sha_file "$TEMP")" = "$FIXED_SHA" ] || fail "temporary target mismatch"
mv "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$FIXED_SHA" ] || fail "installed target mismatch"

printf '%s\n' "$FIXED_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: fixed one-card bind compatibility installed; active next boot\n'
