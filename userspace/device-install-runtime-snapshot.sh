#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/stable-runtime"
SOURCE="$WORK_DIR/S98dani-stable-snapshot"
TARGET="/opt/muos/script/init/async/S98dani-stable-snapshot"
LOG_FILE="$WORK_DIR/rearm.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/61-install-runtime-snapshot.sh"
SOURCE_SHA="2970f4077db1a75ab45509b3ffa8c66ecd014d59ba716ad151b512ae4a35c4ba"
TEMP="$TARGET.dani-new"

mkdir -p "${TARGET%/*}" "$WORK_DIR"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

fail() {
	printf 'FAILED: %s\n' "$*"
	exit 1
}

printf 'fixed runtime snapshot installer start\n'
[ "$(sha_file "$SOURCE")" = "$SOURCE_SHA" ] || fail "snapshot source mismatch"

if [ -f "$TARGET" ]; then
	[ "$(sha_file "$TARGET")" = "$SOURCE_SHA" ] || fail "refusing unknown snapshot hook"
else
	rm -f "$TEMP"
	cp "$SOURCE" "$TEMP"
	chmod 755 "$TEMP"
	sh -n "$TEMP" || fail "snapshot syntax check failed"
	[ "$(sha_file "$TEMP")" = "$SOURCE_SHA" ] || fail "temporary snapshot mismatch"
	mv -f "$TEMP" "$TARGET"
fi

sync
[ ! -f "$CARD_INSTALLER" ] || mv -f "$CARD_INSTALLER" "$CARD_INSTALLER.done"
printf 'SUCCESS: one-shot post-service snapshot armed for the following boot\n'
