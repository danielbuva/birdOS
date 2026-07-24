#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/stable-runtime"
SOURCE="$WORK_DIR/S98bird-stable-snapshot"
TARGET="/opt/muos/script/init/async/S98bird-stable-snapshot"
BACKUP="$WORK_DIR/backup/S98bird-stable-snapshot.pre-mount-wait"
MARKER="$WORK_DIR/snapshot-hook-installed"
LOG_FILE="$WORK_DIR/update.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/67-update-stable-snapshot.sh"
SOURCE_SHA="8b4ed7d52d3592cefc968d3dcbad7502d802e6dd0319078029233a7737087d64"
OLD_SHA="89bddeeeea6557f756c3d1c079f4bb119b5d495eb221477eb8e746ca585f7aa7"
TEMP="$TARGET.bird-new"

mkdir -p "$WORK_DIR/backup" "${TARGET%/*}"
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

printf 'stable snapshot mount-wait update start\n'
[ "$(sha_file "$SOURCE")" = "$SOURCE_SHA" ] || fail "snapshot source mismatch"

if [ -f "$TARGET" ]; then
	CURRENT_SHA=$(sha_file "$TARGET")
	printf 'current snapshot hook SHA-256: %s\n' "$CURRENT_SHA"
	if [ "$CURRENT_SHA" = "$SOURCE_SHA" ]; then
		printf '%s\n' "$SOURCE_SHA" >"$MARKER"
		disable_installer
		printf 'stable snapshot hook already updated\n'
		exit 0
	fi
	[ "$CURRENT_SHA" = "$OLD_SHA" ] || fail "refusing unknown snapshot hook"
	if [ -f "$BACKUP" ]; then
		[ "$(sha_file "$BACKUP")" = "$OLD_SHA" ] || fail "snapshot backup mismatch"
	else
		cp "$TARGET" "$BACKUP"
	fi
fi

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
sh -n "$TEMP" || fail "snapshot hook syntax check failed"
[ "$(sha_file "$TEMP")" = "$SOURCE_SHA" ] || fail "temporary snapshot mismatch"
mv -f "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$SOURCE_SHA" ] || fail "installed snapshot mismatch"

printf '%s\n' "$SOURCE_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: stable snapshot now waits for ROM mount and self-removes after capture\n'
