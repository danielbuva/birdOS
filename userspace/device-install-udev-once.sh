#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/udev-once"
SOURCE="$WORK_DIR/S10udev-once"
TARGET="/opt/muos/script/init/S10udev"
BACKUP="$WORK_DIR/backup/S10minimal-udev"
MARKER="$WORK_DIR/udev-once-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/85-install-udev-once.sh"
MINIMAL_SHA="65409a71180644525425ee9e0f6dac3c74234022523ebc3411275b89d711aecd"
ONCE_SHA="39d962fbefca6b4f241c89b4afce79c9257fa0a93a84b0dfb95cab4c7a306a5f"
TEMP="/opt/muos/script/init/.S10udev.bird-once-new"

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

printf 'one-shot RG34XX-SP udev metadata installer start\n'
[ -f "$SOURCE" ] || fail "one-shot udev source missing"
[ -f "$TARGET" ] || fail "S10udev target missing"
[ "$(sha_file "$SOURCE")" = "$ONCE_SHA" ] || fail "one-shot udev source checksum mismatch"

CURRENT_SHA=$(sha_file "$TARGET")
printf 'current target SHA-256: %s\n' "$CURRENT_SHA"
if [ "$CURRENT_SHA" = "$ONCE_SHA" ]; then
	printf '%s\n' "$ONCE_SHA" >"$MARKER"
	disable_installer
	printf 'one-shot udev metadata path already installed\n'
	exit 0
fi
[ "$CURRENT_SHA" = "$MINIMAL_SHA" ] || fail "refusing unknown S10udev"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$MINIMAL_SHA" ] || fail "existing minimal-udev backup mismatch"
else
	cp "$TARGET" "$BACKUP"
	[ "$(sha_file "$BACKUP")" = "$MINIMAL_SHA" ] || fail "new minimal-udev backup mismatch"
fi

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
[ "$(sha_file "$TEMP")" = "$ONCE_SHA" ] || fail "temporary target mismatch"
mv "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$ONCE_SHA" ] || fail "installed target mismatch"

printf '%s\n' "$ONCE_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: one-shot input/sound metadata generation installed; active next boot\n'
