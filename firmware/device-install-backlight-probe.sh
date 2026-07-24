#!/bin/sh
set -eu

# One-shot user-init installer for the read-only early backlight observer.
ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/.firmware-work"
SOURCE="$WORK_DIR/device-backlight-probe.sh"
TARGET="/opt/muos/script/init/async/S04backlightprobe.sh"
TARGET_NEW="$TARGET.bird-new"
STATE="$WORK_DIR/backlight-probe-installed"
LOG="$ROM_MOUNT/MUOS/log/brightness-probe-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/97-install-backlight-probe.sh"
EXPECTED_SHA="a7ec727e80c2f55c79d09f5f0bec0a7a48d6aea3cf9c3b9c59f1930c8b792bdf"

mkdir -p "$ROM_MOUNT/MUOS/log"
: >"$LOG"
exec >>"$LOG" 2>&1

disable_installer() {
	if [ -f "$CARD_INSTALLER" ]; then
		mv "$CARD_INSTALLER" "$CARD_INSTALLER.done"
	fi
}

fail() {
	printf 'FAILED: %s\n' "$*"
	exit 1
}

[ -f "$SOURCE" ] || fail "probe payload missing: $SOURCE"
SOURCE_SHA=$(sha256sum "$SOURCE" | awk '{print $1}')
[ "$SOURCE_SHA" = "$EXPECTED_SHA" ] || fail "probe payload checksum mismatch: $SOURCE_SHA"

if [ -f "$TARGET" ] && [ "$(sha256sum "$TARGET" | awk '{print $1}')" = "$EXPECTED_SHA" ]; then
	printf '%s\n' "$EXPECTED_SHA" >"$STATE"
	disable_installer
	printf 'early backlight probe already installed\n'
	exit 0
fi

mkdir -p "${TARGET%/*}"
rm -f "$TARGET_NEW"
cp -f "$SOURCE" "$TARGET_NEW"
chmod 755 "$TARGET_NEW"
[ "$(sha256sum "$TARGET_NEW" | awk '{print $1}')" = "$EXPECTED_SHA" ] || \
	fail "temporary target verification failed"
mv -f "$TARGET_NEW" "$TARGET"
[ "$(sha256sum "$TARGET" | awk '{print $1}')" = "$EXPECTED_SHA" ] || \
	fail "installed target verification failed"

printf '%s\n' "$EXPECTED_SHA" >"$STATE"
disable_installer
printf 'installed asynchronous read-only backlight probe; active next boot\n'
