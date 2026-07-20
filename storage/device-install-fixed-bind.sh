#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/fixed-storage"
SOURCE="$WORK_DIR/fixed-bind.sh"
TARGET="/opt/muos/script/mount/bind.sh"
BACKUP="$WORK_DIR/backup/bind.sh.stock"
MARKER="$WORK_DIR/fixed-bind-installed"
LOG_FILE="$WORK_DIR/fixed-bind-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/82-install-fixed-bind.sh"
OLD_SHA="293620ae45db8b04de3b99bccfb3946fee4e05df025a618da2859d274d2ff675"
NEW_SHA="924b2dd081f3f8c511794a9a2755180b7e7165b7d612ec4a2e0884179d1a71d0"
TEMP="/opt/muos/script/mount/.bind.sh.dani-fixed-new"

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

printf 'fixed one-card bind map installer start\n'
[ "$(sha_file "$SOURCE")" = "$NEW_SHA" ] || fail "fixed bind source mismatch"
[ -f "$TARGET" ] || fail "bind.sh target missing"
CURRENT_SHA=$(sha_file "$TARGET")
printf 'current bind SHA-256: %s\n' "$CURRENT_SHA"
if [ "$CURRENT_SHA" = "$NEW_SHA" ]; then
	printf '%s\n' "$NEW_SHA" >"$MARKER"
	disable_installer
	printf 'fixed one-card bind map already installed\n'
	exit 0
fi
[ "$CURRENT_SHA" = "$OLD_SHA" ] || fail "refusing unknown bind.sh"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$OLD_SHA" ] || fail "existing bind backup mismatch"
else
	cp "$TARGET" "$BACKUP"
fi

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
[ "$(sha_file "$TEMP")" = "$NEW_SHA" ] || fail "temporary bind mismatch"
mv "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$NEW_SHA" ] || fail "installed bind mismatch"

printf '%s\n' "$NEW_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: fixed one-card bind map installed; active next boot\n'
