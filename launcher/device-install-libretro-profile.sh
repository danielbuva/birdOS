#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
SOURCE="$ROM_MOUNT/MUOS/bespoke-launcher/lr-profiled.sh"
TARGET="/opt/muos/script/launch/lr-general.sh"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/libretro-launch"
BACKUP="$WORK_DIR/backup/lr-general.sh.stock"
MARKER="$WORK_DIR/profile-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/90-install-libretro-profile.sh"
STOCK_SHA="2e5decf0a977258253f0e8bc56252d42a524ed607dc3dbd42ad0b39dc793c475"
PROFILE_SHA="20747bbeb2ec6964997087754922594f470b7eb6ebd0b6ece094011098d5fc06"
TEMP="/opt/muos/script/launch/.lr-general.bird-profile-new"

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

printf 'libretro launch profiler installer start\n'
[ -f "$SOURCE" ] || fail "profile source missing"
[ -f "$TARGET" ] || fail "root launch target missing"
[ "$(sha_file "$SOURCE")" = "$PROFILE_SHA" ] || fail "profile source checksum mismatch"

CURRENT_SHA=$(sha_file "$TARGET")
printf 'current target SHA-256: %s\n' "$CURRENT_SHA"
if [ "$CURRENT_SHA" = "$PROFILE_SHA" ]; then
	printf '%s\n' "$PROFILE_SHA" >"$MARKER"
	disable_installer
	printf 'profile already installed\n'
	exit 0
fi
[ "$CURRENT_SHA" = "$STOCK_SHA" ] || fail "refusing unknown launch wrapper"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$STOCK_SHA" ] || fail "existing backup checksum mismatch"
else
	cp "$TARGET" "$BACKUP"
	[ "$(sha_file "$BACKUP")" = "$STOCK_SHA" ] || fail "new backup checksum mismatch"
fi

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
[ "$(sha_file "$TEMP")" = "$PROFILE_SHA" ] || fail "temporary target checksum mismatch"
mv "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$PROFILE_SHA" ] || fail "installed target checksum mismatch"

printf '%s\n' "$PROFILE_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: behavior-identical profiled libretro wrapper installed\n'
