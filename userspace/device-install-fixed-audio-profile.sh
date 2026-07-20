#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/audio-profile/fixed"
MAIN_SOURCE="$WORK_DIR/89-dani-fixed-main.lua"
BLUETOOTH_SOURCE="$WORK_DIR/89-dani-fixed-bluetooth.lua"
MAIN_TARGET="/usr/share/wireplumber/main.lua.d/89-dani-fixed-device.lua"
BLUETOOTH_TARGET="/usr/share/wireplumber/bluetooth.lua.d/89-dani-fixed-device.lua"
MARKER="$WORK_DIR/fixed-audio-profile-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/73-install-fixed-audio-profile.sh"
MAIN_SHA="b5d07c1ac663d4c7b1bc18fd3d3814e02af76c03b6598efe8abfb5a4f4df7e2d"
BLUETOOTH_SHA="22e81c52689f7662a7481692421d7d8341b042453950bb5440889810da78c6e6"
MAIN_TEMP="$MAIN_TARGET.dani-new"
BLUETOOTH_TEMP="$BLUETOOTH_TARGET.dani-new"
INSTALL_STARTED=0

mkdir -p "$WORK_DIR"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

disable_installer() {
	[ ! -f "$CARD_INSTALLER" ] || mv -f "$CARD_INSTALLER" "$CARD_INSTALLER.done"
}

rollback() {
	[ "$INSTALL_STARTED" -eq 1 ] || return 0
	rm -f "$MAIN_TARGET" "$BLUETOOTH_TARGET" "$MAIN_TEMP" "$BLUETOOTH_TEMP"
}

fail() {
	printf 'FAILED: %s\n' "$*"
	rollback
	exit 1
}

printf 'fixed WirePlumber device profile installer start\n'
[ "$(sha_file "$MAIN_SOURCE")" = "$MAIN_SHA" ] || fail "main override source mismatch"
[ "$(sha_file "$BLUETOOTH_SOURCE")" = "$BLUETOOTH_SHA" ] || fail "Bluetooth override source mismatch"

if [ -f "$MAIN_TARGET" ] || [ -f "$BLUETOOTH_TARGET" ]; then
	[ -f "$MAIN_TARGET" ] && [ "$(sha_file "$MAIN_TARGET")" = "$MAIN_SHA" ] || \
		fail "refusing unknown or incomplete main override"
	[ -f "$BLUETOOTH_TARGET" ] && [ "$(sha_file "$BLUETOOTH_TARGET")" = "$BLUETOOTH_SHA" ] || \
		fail "refusing unknown or incomplete Bluetooth override"
	printf '%s %s\n' "$MAIN_SHA" "$BLUETOOTH_SHA" >"$MARKER"
	disable_installer
	printf 'fixed WirePlumber device profile already installed\n'
	exit 0
fi

rm -f "$MAIN_TEMP" "$BLUETOOTH_TEMP"
cp "$MAIN_SOURCE" "$MAIN_TEMP"
cp "$BLUETOOTH_SOURCE" "$BLUETOOTH_TEMP"
[ "$(sha_file "$MAIN_TEMP")" = "$MAIN_SHA" ] || fail "temporary main override mismatch"
[ "$(sha_file "$BLUETOOTH_TEMP")" = "$BLUETOOTH_SHA" ] || fail "temporary Bluetooth override mismatch"

INSTALL_STARTED=1
mv -f "$MAIN_TEMP" "$MAIN_TARGET"
mv -f "$BLUETOOTH_TEMP" "$BLUETOOTH_TARGET"
sync
[ "$(sha_file "$MAIN_TARGET")" = "$MAIN_SHA" ] || fail "installed main override mismatch"
[ "$(sha_file "$BLUETOOTH_TARGET")" = "$BLUETOOTH_SHA" ] || fail "installed Bluetooth override mismatch"

INSTALL_STARTED=0
printf '%s %s\n' "$MAIN_SHA" "$BLUETOOTH_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: camera, V4L2, MIDI, Bluetooth and logind audio discovery disabled; active next boot\n'

