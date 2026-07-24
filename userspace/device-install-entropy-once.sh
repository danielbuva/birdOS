#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/entropy-once"
SOURCE="$WORK_DIR/S01entropy-once"
TARGET="/opt/muos/script/init/S01entropy"
BACKUP="$WORK_DIR/backup/S01entropy.stock"
MARKER="$WORK_DIR/entropy-once-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/78-install-entropy-crng.sh"
OLD_SHA="542385cc824591a1a6fddde078a339c2e8467341a65e025026f95ac4623fbe02"
INTERMEDIATE_SHA="8c70010ae701961582f64199abd1c42905df11c0e8c780ed6cfb967b7e0d2799"
NEW_SHA="aabd64646311c81d8fd18d24e9fcb8804896d652bf985fd59051e01934d2f312"
TEMP="/opt/muos/script/init/.S01entropy.bird-once-new"

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

printf 'one-shot entropy service installer start\n'
[ "$(sha_file "$SOURCE")" = "$NEW_SHA" ] || fail "entropy source mismatch"
[ -f "$TARGET" ] || fail "S01entropy target missing"
CURRENT_SHA=$(sha_file "$TARGET")
printf 'current entropy SHA-256: %s\n' "$CURRENT_SHA"
if [ "$CURRENT_SHA" = "$NEW_SHA" ]; then
	printf '%s\n' "$NEW_SHA" >"$MARKER"
	disable_installer
	printf 'one-shot entropy service already installed\n'
	exit 0
fi
case "$CURRENT_SHA" in
	"$OLD_SHA" | "$INTERMEDIATE_SHA") ;;
	*) fail "refusing unknown S01entropy" ;;
esac

if [ -f "$BACKUP" ]; then
	[ "$(sha_file "$BACKUP")" = "$OLD_SHA" ] || fail "existing entropy backup mismatch"
else
	[ "$CURRENT_SHA" = "$OLD_SHA" ] || fail "stock entropy backup missing"
	cp "$TARGET" "$BACKUP"
fi

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
[ "$(sha_file "$TEMP")" = "$NEW_SHA" ] || fail "temporary entropy mismatch"
mv "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$NEW_SHA" ] || fail "installed entropy mismatch"

printf '%s\n' "$NEW_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: CRNG-event one-shot entropy lifecycle installed; active next boot\n'
