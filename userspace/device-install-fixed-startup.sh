#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/fixed-startup"
SOURCE="$WORK_DIR/startup-rg34xxsp.sh"
TARGET="/opt/muos/script/system/startup.sh"
BACKUP="$WORK_DIR/backup/startup.sh.pre-fixed-rg34xxsp"
MARKER="$WORK_DIR/fixed-startup-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/68-install-fixed-startup.sh"
SOURCE_SHA="ab769b0ac647e0f71be729296ace613c3e432d912b14d31749cb2710bba1d0a1"
OLD_SHA="880051ffe89a134798a2f72ac4690530b3cecb8eb492c10195be9f6240ad3e3a"
TEMP="$TARGET.bird-new"

mkdir -p "$WORK_DIR/backup"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

disable_installer() {
	[ ! -f "$CARD_INSTALLER" ] || mv -f "$CARD_INSTALLER" "$CARD_INSTALLER.done"
}

fail() {
	printf 'FAILED: %s\n' "$*"
	exit 1
}

printf 'fixed RG34XX-SP startup installer start\n'
[ "$(sha_file "$SOURCE")" = "$SOURCE_SHA" ] || fail "startup source mismatch"
[ -f "$TARGET" ] || fail "startup target missing"
CURRENT_SHA=$(sha_file "$TARGET")
printf 'current startup SHA-256: %s\n' "$CURRENT_SHA"

if [ "$CURRENT_SHA" = "$SOURCE_SHA" ]; then
	printf '%s\n' "$SOURCE_SHA" >"$MARKER"
	disable_installer
	printf 'fixed RG34XX-SP startup already installed\n'
	exit 0
fi
[ "$CURRENT_SHA" = "$OLD_SHA" ] || fail "refusing unknown startup.sh"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$OLD_SHA" ] || fail "existing startup backup mismatch"
else
	cp "$TARGET" "$BACKUP"
fi

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
sh -n "$TEMP" || fail "fixed startup syntax check failed"
[ "$(sha_file "$TEMP")" = "$SOURCE_SHA" ] || fail "temporary startup mismatch"
mv -f "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$SOURCE_SHA" ] || fail "installed startup mismatch"

printf '%s\n' "$SOURCE_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: fixed RG34XX-SP startup installed; active next boot\n'
