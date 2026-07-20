#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
SOURCE="$ROM_MOUNT/MUOS/bespoke-launcher/lr-fixed.sh"
TARGET="/opt/muos/script/launch/lr-general.sh"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/libretro-launch"
MARKER="$WORK_DIR/fixed-installed"
LOG_FILE="$WORK_DIR/fixed-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/89-install-libretro-fixed.sh"
PROFILE_SHA="319a95a46f9c9bab4f3f513b5a39677db0a4a6d76ac7f672d7127cfd8e6070d8"
FIXED_SHA="a75526b7ec1d3787c24468fffc99a1dad24b1e8bf968de4e6fa98c88f8c2f2d9"
TEMP="/opt/muos/script/launch/.lr-general.dani-fixed-new"

mkdir -p "$WORK_DIR"
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

printf 'fixed libretro bridge installer start\n'
[ -f "$SOURCE" ] || fail "fixed bridge source missing"
[ -f "$TARGET" ] || fail "root launch target missing"
[ "$(sha_file "$SOURCE")" = "$FIXED_SHA" ] || fail "fixed bridge checksum mismatch"

CURRENT_SHA=$(sha_file "$TARGET")
printf 'current target SHA-256: %s\n' "$CURRENT_SHA"
if [ "$CURRENT_SHA" = "$FIXED_SHA" ]; then
	printf '%s\n' "$FIXED_SHA" >"$MARKER"
	disable_installer
	printf 'fixed bridge already installed\n'
	exit 0
fi
[ "$CURRENT_SHA" = "$PROFILE_SHA" ] || fail "refusing unknown launch wrapper"

for REQUIRED in \
	/opt/muos/share/info/config/retroarch.cfg \
	/opt/muos/device/control/retroarch.device.cfg \
	/opt/muos/device/control/retroarch.resolution.cfg \
	/opt/muos/device/control/retroarch.threaded.cfg; do
	[ -f "$REQUIRED" ] || fail "prepared RetroArch file missing: $REQUIRED"
done

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
[ "$(sha_file "$TEMP")" = "$FIXED_SHA" ] || fail "temporary target checksum mismatch"
mv "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$FIXED_SHA" ] || fail "installed target checksum mismatch"

printf '%s\n' "$FIXED_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: fixed direct libretro bridge installed\n'
