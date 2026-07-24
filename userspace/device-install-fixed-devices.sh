#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/udev-fixed"
SOURCE="$WORK_DIR/S10fixed-devices"
TARGET="/opt/muos/script/init/S10udev"
BACKUP="$WORK_DIR/backup/S10udev.profiled"
MARKER="$WORK_DIR/fixed-devices-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/87-install-fixed-devices.sh"
PROFILE_SHA="cdef27f4e6cb77641364de29008dd5a469e06f2c046333ec352fb76c68b25cec"
FIXED_SHA="de60cebfb559f7a9e7abb6ed7ec1781047425d22043db97d63d6c87713b78773"
TEMP="/opt/muos/script/init/.S10udev.bird-fixed-new"

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

printf 'fixed RG34XX-SP device setup installer start\n'
[ -f "$SOURCE" ] || fail "fixed-device source missing"
[ -f "$TARGET" ] || fail "S10udev target missing"
[ "$(sha_file "$SOURCE")" = "$FIXED_SHA" ] || fail "fixed-device source checksum mismatch"

CURRENT_SHA=$(sha_file "$TARGET")
printf 'current target SHA-256: %s\n' "$CURRENT_SHA"
if [ "$CURRENT_SHA" = "$FIXED_SHA" ]; then
	printf '%s\n' "$FIXED_SHA" >"$MARKER"
	disable_installer
	printf 'fixed device setup already installed\n'
	exit 0
fi
[ "$CURRENT_SHA" = "$PROFILE_SHA" ] || fail "refusing unknown S10udev"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$PROFILE_SHA" ] || fail "existing profile backup mismatch"
else
	cp "$TARGET" "$BACKUP"
	[ "$(sha_file "$BACKUP")" = "$PROFILE_SHA" ] || fail "new profile backup mismatch"
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
printf 'SUCCESS: fixed RG34XX-SP device setup installed; udevd will not start next boot\n'
