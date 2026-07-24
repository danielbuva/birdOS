#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/stable-runtime"
SOURCE="$WORK_DIR/S98bird-stable-snapshot"
TARGET="/opt/muos/script/init/async/S98bird-stable-snapshot"
MARKER="$WORK_DIR/snapshot-hook-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/71-install-stable-snapshot.sh"
SOURCE_SHA="8b4ed7d52d3592cefc968d3dcbad7502d802e6dd0319078029233a7737087d64"
TEMP="$TARGET.bird-new"

mkdir -p "$WORK_DIR" "${TARGET%/*}"
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

printf 'stable post-startup snapshot hook installer start\n'
[ "$(sha_file "$SOURCE")" = "$SOURCE_SHA" ] || fail "snapshot source mismatch"

if [ -f "$TARGET" ]; then
	[ "$(sha_file "$TARGET")" = "$SOURCE_SHA" ] || fail "refusing unknown snapshot hook"
	printf '%s\n' "$SOURCE_SHA" >"$MARKER"
	disable_installer
	printf 'stable snapshot hook already installed\n'
	exit 0
fi

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
[ "$(sha_file "$TEMP")" = "$SOURCE_SHA" ] || fail "temporary snapshot mismatch"
mv -f "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$SOURCE_SHA" ] || fail "installed snapshot mismatch"

printf '%s\n' "$SOURCE_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: one-shot stable runtime snapshot will run on the next armed boot\n'
