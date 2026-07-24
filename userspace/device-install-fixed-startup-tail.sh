#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/fixed-startup-tail"
PATCH_SOURCE="$WORK_DIR/patch-fixed-startup-tail.sh"
TARGET="/opt/muos/script/system/startup.sh"
BACKUP="$WORK_DIR/backup/startup.sh.pre-fixed-tail"
MARKER="$WORK_DIR/fixed-startup-tail-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/72-install-fixed-startup-tail.sh"
PATCH_SHA="69d0a7e1cec99134f36acf76fc1f71da722b0330cf74c46f77cac7d6aaee427d"
OLD_SHA="889a1eb899b04815ae873495abfa59c61a0ae19fcf7f3afa5c7d95eb61b8ff02"
NEW_SHA="880051ffe89a134798a2f72ac4690530b3cecb8eb492c10195be9f6240ad3e3a"
TEMP="$TARGET.bird-fixed-tail-new"

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

printf 'fixed startup tail installer start\n'
[ "$(sha_file "$PATCH_SOURCE")" = "$PATCH_SHA" ] || fail "startup patch source mismatch"
[ -f "$TARGET" ] || fail "startup target missing"
CURRENT_SHA=$(sha_file "$TARGET")
printf 'current startup SHA-256: %s\n' "$CURRENT_SHA"

if [ "$CURRENT_SHA" = "$NEW_SHA" ]; then
	printf '%s\n' "$NEW_SHA" >"$MARKER"
	disable_installer
	printf 'fixed startup tail already installed\n'
	exit 0
fi
[ "$CURRENT_SHA" = "$OLD_SHA" ] || fail "refusing unknown startup.sh"

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$OLD_SHA" ] || fail "existing startup backup mismatch"
else
	cp "$TARGET" "$BACKUP"
fi

rm -f "$TEMP"
cp "$TARGET" "$TEMP"
chmod 755 "$TEMP"
"$PATCH_SOURCE" "$TEMP"
[ "$(sha_file "$TEMP")" = "$NEW_SHA" ] || fail "temporary startup mismatch"
mv -f "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$NEW_SHA" ] || fail "installed startup mismatch"

printf '%s\n' "$NEW_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: delayed generic startup jobs removed; active next boot\n'
