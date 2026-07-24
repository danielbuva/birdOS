#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/udev-profile"
SOURCE="$WORK_DIR/S10udev-profile"
TARGET="/opt/muos/script/init/S10udev"
BACKUP="$WORK_DIR/backup/S10udev.stock"
MARKER="$WORK_DIR/profile-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/88-install-udev-profile.sh"
STOCK_SHA="0e4e4126489b6e41fe018ede4ad0858826a5ffdef902ccebe87a090421ba5a05"
PROFILE_SHA="cdef27f4e6cb77641364de29008dd5a469e06f2c046333ec352fb76c68b25cec"
TEMP="/opt/muos/script/init/.S10udev.bird-profile-new"

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

printf 'udev pre/post profiler installer start\n'
[ -f "$SOURCE" ] || fail "profile source missing"
[ -f "$TARGET" ] || fail "S10udev target missing"
[ "$(sha_file "$SOURCE")" = "$PROFILE_SHA" ] || fail "profile source checksum mismatch"

CURRENT_SHA=$(sha_file "$TARGET")
printf 'current target SHA-256: %s\n' "$CURRENT_SHA"
if [ "$CURRENT_SHA" = "$PROFILE_SHA" ]; then
	printf '%s\n' "$PROFILE_SHA" >"$MARKER"
	disable_installer
	printf 'udev profile already installed\n'
	exit 0
fi
[ "$CURRENT_SHA" = "$STOCK_SHA" ] || fail "refusing unknown S10udev"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$STOCK_SHA" ] || fail "existing backup mismatch"
else
	cp "$TARGET" "$BACKUP"
	[ "$(sha_file "$BACKUP")" = "$STOCK_SHA" ] || fail "new backup mismatch"
fi

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
[ "$(sha_file "$TEMP")" = "$PROFILE_SHA" ] || fail "temporary target mismatch"
mv "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$PROFILE_SHA" ] || fail "installed target mismatch"

printf '%s\n' "$PROFILE_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: behavior-identical udev pre/post profiler installed\n'
