#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/udev-minimal"
SOURCE="$WORK_DIR/S10minimal-udev"
TARGET="/opt/muos/script/init/S10udev"
BACKUP="$WORK_DIR/backup/S10fixed-devices"
REJECTED_ONCE="$WORK_DIR/backup/S10udev-once.rejected"
MARKER="$WORK_DIR/minimal-udev-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/86-install-minimal-udev.sh"
FIXED_SHA="de60cebfb559f7a9e7abb6ed7ec1781047425d22043db97d63d6c87713b78773"
MINIMAL_SHA="65409a71180644525425ee9e0f6dac3c74234022523ebc3411275b89d711aecd"
ONCE_SHA="39d962fbefca6b4f241c89b4afce79c9257fa0a93a84b0dfb95cab4c7a306a5f"
TEMP="/opt/muos/script/init/.S10udev.bird-minimal-new"

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

printf 'minimal RG34XX-SP udev compatibility installer start\n'
[ -f "$SOURCE" ] || fail "minimal udev source missing"
[ -f "$TARGET" ] || fail "S10udev target missing"
[ "$(sha_file "$SOURCE")" = "$MINIMAL_SHA" ] || fail "minimal udev source checksum mismatch"

CURRENT_SHA=$(sha_file "$TARGET")
printf 'current target SHA-256: %s\n' "$CURRENT_SHA"
if [ "$CURRENT_SHA" = "$MINIMAL_SHA" ]; then
	printf '%s\n' "$MINIMAL_SHA" >"$MARKER"
	disable_installer
	printf 'minimal udev compatibility already installed\n'
	exit 0
fi
case "$CURRENT_SHA" in
	"$FIXED_SHA")
		if [ -f "$BACKUP" ]; then
			[ "$(sha_file "$BACKUP")" = "$FIXED_SHA" ] || fail "existing fixed-device backup mismatch"
		else
			cp "$TARGET" "$BACKUP"
			[ "$(sha_file "$BACKUP")" = "$FIXED_SHA" ] || fail "new fixed-device backup mismatch"
		fi
		;;
	"$ONCE_SHA")
		if [ -f "$REJECTED_ONCE" ]; then
			[ "$(sha_file "$REJECTED_ONCE")" = "$ONCE_SHA" ] || fail "existing rejected one-shot backup mismatch"
		else
			cp "$TARGET" "$REJECTED_ONCE"
			[ "$(sha_file "$REJECTED_ONCE")" = "$ONCE_SHA" ] || fail "new rejected one-shot backup mismatch"
		fi
		;;
	*) fail "refusing unknown S10udev" ;;
esac

rm -f "$TEMP"
cp "$SOURCE" "$TEMP"
chmod 755 "$TEMP"
[ "$(sha_file "$TEMP")" = "$MINIMAL_SHA" ] || fail "temporary target mismatch"
mv "$TEMP" "$TARGET"
sync
[ "$(sha_file "$TARGET")" = "$MINIMAL_SHA" ] || fail "installed target mismatch"

printf '%s\n' "$MINIMAL_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: minimal input/sound udev compatibility installed; active next boot\n'
