#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/fixed-startup"
SOURCE="$WORK_DIR/startup-rg34xxsp.sh"
TARGET="/opt/muos/script/system/startup.sh"
BACKUP="$WORK_DIR/backup/startup.sh.fixed-v1"
MARKER="$WORK_DIR/fixed-startup-v2-installed"
LOG_FILE="$WORK_DIR/v2-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/60-install-fixed-startup-v2.sh"
OLD_SHA="8c18047f9ef36b6edf82f3e5b1197d26ce2bdda7bde5551ad942ed900944323e"
NEW_SHA="ab769b0ac647e0f71be729296ace613c3e432d912b14d31749cb2710bba1d0a1"
TEMP="$TARGET.bird-v2"

mkdir -p "$WORK_DIR/backup"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

fail() {
	printf 'FAILED: %s\n' "$*"
	exit 1
}

printf 'fixed RG34XX-SP startup v2 installer start\n'
[ "$(sha_file "$SOURCE")" = "$NEW_SHA" ] || fail "startup v2 source mismatch"
[ -f "$TARGET" ] || fail "startup target missing"
CURRENT_SHA=$(sha_file "$TARGET")

if [ "$CURRENT_SHA" != "$NEW_SHA" ]; then
	[ "$CURRENT_SHA" = "$OLD_SHA" ] || fail "refusing unknown startup $CURRENT_SHA"
	if [ -f "$BACKUP" ]; then
		[ "$(sha_file "$BACKUP")" = "$OLD_SHA" ] || fail "startup v1 backup mismatch"
	else
		cp "$TARGET" "$BACKUP"
	fi
	cp "$SOURCE" "$TEMP"
	chmod 755 "$TEMP"
	sh -n "$TEMP" || fail "startup v2 syntax check failed"
	[ "$(sha_file "$TEMP")" = "$NEW_SHA" ] || fail "startup v2 temporary mismatch"
	mv -f "$TEMP" "$TARGET"
fi

# Values that never change for this build are written once here instead of on
# every boot by startup.sh.
printf '%s' 0 >/opt/muos/config/system/idle_inhibit
printf '%s' 0 >/opt/muos/config/boot/device_mode
printf '%s' 720 >/opt/muos/device/config/screen/width
printf '%s' 480 >/opt/muos/device/config/screen/height
printf '%s' 720 >/opt/muos/device/config/mux/width
printf '%s' 480 >/opt/muos/device/config/mux/height
rm -f /opt/update.sh

sync
[ "$(sha_file "$TARGET")" = "$NEW_SHA" ] || fail "installed startup v2 mismatch"
printf '%s\n' "$NEW_SHA" >"$MARKER"
[ ! -f "$CARD_INSTALLER" ] || mv -f "$CARD_INSTALLER" "$CARD_INSTALLER.done"
printf 'SUCCESS: redundant fixed startup probes and writes removed\n'
