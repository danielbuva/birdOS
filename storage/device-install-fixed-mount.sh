#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/fixed-storage"
STORAGE_SOURCE="$WORK_DIR/fixed-storage.sh"
START_SOURCE="$WORK_DIR/fixed-start.sh"
STORAGE_TARGET="/opt/muos/script/mount/storage.sh"
START_TARGET="/opt/muos/script/mount/start.sh"
STORAGE_BACKUP="$WORK_DIR/backup/storage-wrapper.sh.pre-fixed"
START_BACKUP="$WORK_DIR/backup/start.sh.stock"
MARKER="$WORK_DIR/fixed-mount-installed"
LOG_FILE="$WORK_DIR/fixed-mount-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/81-install-fixed-mount.sh"
STORAGE_OLD_SHA="9bc10f44ef86c0a1043679d6aeb9d07394ce4ce1fbfce3dc23d92dc065a8dce9"
START_OLD_SHA="9a21c3d26eab162a482adec2f82f6fe03a9ec72a1e131d192b8e57f87069c950"
STORAGE_NEW_SHA="fd22f192ab70c3b405598611307d8450d056de18a0d95a1a18471ef32d33372e"
START_NEW_SHA="6ce5ef2d96ec3af819df4b109e1fb8e47c473dad4477d614ed6f9e95d45454f2"
STORAGE_TEMP="/opt/muos/script/mount/.storage.sh.dani-fixed-new"
START_TEMP="/opt/muos/script/mount/.start.sh.dani-fixed-new"

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

printf 'fixed ROM mount and orchestration installer start\n'
[ "$(sha_file "$STORAGE_SOURCE")" = "$STORAGE_NEW_SHA" ] || fail "fixed storage source mismatch"
[ "$(sha_file "$START_SOURCE")" = "$START_NEW_SHA" ] || fail "fixed start source mismatch"
[ -f "$STORAGE_TARGET" ] || fail "storage.sh target missing"
[ -f "$START_TARGET" ] || fail "start.sh target missing"

CURRENT_STORAGE=$(sha_file "$STORAGE_TARGET")
CURRENT_START=$(sha_file "$START_TARGET")
printf 'current storage/start SHA-256: %s %s\n' "$CURRENT_STORAGE" "$CURRENT_START"
if [ "$CURRENT_STORAGE" = "$STORAGE_NEW_SHA" ] && [ "$CURRENT_START" = "$START_NEW_SHA" ]; then
	printf '%s %s\n' "$STORAGE_NEW_SHA" "$START_NEW_SHA" >"$MARKER"
	disable_installer
	printf 'fixed ROM mount and orchestration already installed\n'
	exit 0
fi
[ "$CURRENT_STORAGE" = "$STORAGE_OLD_SHA" ] || fail "refusing unknown storage.sh"
[ "$CURRENT_START" = "$START_OLD_SHA" ] || fail "refusing unknown start.sh"

if [ -f "$STORAGE_BACKUP" ]; then
	[ "$(sha_file "$STORAGE_BACKUP")" = "$STORAGE_OLD_SHA" ] || fail "storage backup mismatch"
else
	cp "$STORAGE_TARGET" "$STORAGE_BACKUP"
fi
if [ -f "$START_BACKUP" ]; then
	[ "$(sha_file "$START_BACKUP")" = "$START_OLD_SHA" ] || fail "start backup mismatch"
else
	cp "$START_TARGET" "$START_BACKUP"
fi

rm -f "$STORAGE_TEMP" "$START_TEMP"
cp "$STORAGE_SOURCE" "$STORAGE_TEMP"
cp "$START_SOURCE" "$START_TEMP"
chmod 755 "$STORAGE_TEMP" "$START_TEMP"
[ "$(sha_file "$STORAGE_TEMP")" = "$STORAGE_NEW_SHA" ] || fail "temporary storage mismatch"
[ "$(sha_file "$START_TEMP")" = "$START_NEW_SHA" ] || fail "temporary start mismatch"

mv "$STORAGE_TEMP" "$STORAGE_TARGET"
mv "$START_TEMP" "$START_TARGET"
sync
[ "$(sha_file "$STORAGE_TARGET")" = "$STORAGE_NEW_SHA" ] || fail "installed storage mismatch"
[ "$(sha_file "$START_TARGET")" = "$START_NEW_SHA" ] || fail "installed start mismatch"

printf '%s %s\n' "$STORAGE_NEW_SHA" "$START_NEW_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: fixed ROM mount and storage orchestration installed; active next boot\n'

