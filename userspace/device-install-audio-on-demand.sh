#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/audio-on-demand"
PW_SOURCE="$WORK_DIR/pipewire-on-demand"
DBUS_SOURCE="$WORK_DIR/S30dbus-on-demand"
LAUNCHER_SOURCE="$ROM_MOUNT/MUOS/bespoke-launcher/S03danilauncher"
PW_TARGET="/opt/muos/script/system/pipewire.sh"
DBUS_TARGET="/opt/muos/script/init/S30dbus"
LAUNCHER_TARGET="/opt/muos/script/init/S03danilauncher"
PW_REAL="$PW_TARGET.dani-real"
DBUS_REAL="$DBUS_TARGET.dani-real"
PW_BACKUP="$WORK_DIR/backup/pipewire.sh.stock"
DBUS_BACKUP="$WORK_DIR/backup/S30dbus.stock"
LAUNCHER_BACKUP="$WORK_DIR/backup/S03danilauncher.pre-audio-demand"
MARKER="$WORK_DIR/audio-on-demand-installed"
LOG_FILE="$WORK_DIR/install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/77-install-audio-on-demand.sh"
PW_OLD_SHA="81c6890f17deafec9d9afe214fba0badcb2b2c42a334ef3e57a74f3810a4d79d"
DBUS_OLD_SHA="726c0803e66157bbb9aca253b3d0c5146d577a8264032a6cd82deebdb870cd37"
LAUNCHER_OLD_SHA="d747b32432f19845dcc80d6a8b9fae2c6f10ef39ed711e396829be4da03464ac"
PW_NEW_SHA="3c03475cddde170325b707b0cfc3a07c935c4ddd7d5883863f66b9436b254e85"
DBUS_NEW_SHA="68fe4472c703bde2515bbce956add89ef329813921aa04c8ec1f28199f3d0cdb"
LAUNCHER_NEW_SHA="70e1aa1485357a5cf0951641976a9121f9aaa1a388e75366d0287582db25b766"
PW_TEMP="$PW_TARGET.dani-new"
DBUS_TEMP="$DBUS_TARGET.dani-new"
LAUNCHER_TEMP="$LAUNCHER_TARGET.dani-new"
INSTALL_STARTED=0

mkdir -p "$WORK_DIR/backup"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

disable_installer() {
	[ ! -f "$CARD_INSTALLER" ] || mv -f "$CARD_INSTALLER" "$CARD_INSTALLER.done"
}

rollback() {
	[ "$INSTALL_STARTED" -eq 1 ] || return 0
	[ -f "$PW_REAL" ] && cp -f "$PW_REAL" "$PW_TARGET"
	[ -f "$DBUS_REAL" ] && cp -f "$DBUS_REAL" "$DBUS_TARGET"
	[ -f "$LAUNCHER_BACKUP" ] && cp -f "$LAUNCHER_BACKUP" "$LAUNCHER_TARGET"
	chmod 755 "$PW_TARGET" "$DBUS_TARGET" "$LAUNCHER_TARGET" 2>/dev/null || :
	rm -f "$PW_REAL" "$DBUS_REAL"
}

fail() {
	printf 'FAILED: %s\n' "$*"
	rollback
	exit 1
}

printf 'content-triggered D-Bus/PipeWire installer start\n'
[ "$(sha_file "$PW_SOURCE")" = "$PW_NEW_SHA" ] || fail "PipeWire wrapper source mismatch"
[ "$(sha_file "$DBUS_SOURCE")" = "$DBUS_NEW_SHA" ] || fail "D-Bus wrapper source mismatch"
[ "$(sha_file "$LAUNCHER_SOURCE")" = "$LAUNCHER_NEW_SHA" ] || fail "launcher source mismatch"
[ -f "$PW_TARGET" ] && [ -f "$DBUS_TARGET" ] && [ -f "$LAUNCHER_TARGET" ] || fail "active target missing"

CURRENT_PW=$(sha_file "$PW_TARGET")
CURRENT_DBUS=$(sha_file "$DBUS_TARGET")
CURRENT_LAUNCHER=$(sha_file "$LAUNCHER_TARGET")
printf 'current PipeWire/D-Bus/launcher SHA-256: %s %s %s\n' \
	"$CURRENT_PW" "$CURRENT_DBUS" "$CURRENT_LAUNCHER"

if [ "$CURRENT_PW" = "$PW_NEW_SHA" ] && [ "$CURRENT_DBUS" = "$DBUS_NEW_SHA" ] && \
	[ "$CURRENT_LAUNCHER" = "$LAUNCHER_NEW_SHA" ] && \
	[ -f "$PW_REAL" ] && [ "$(sha_file "$PW_REAL")" = "$PW_OLD_SHA" ] && \
	[ -f "$DBUS_REAL" ] && [ "$(sha_file "$DBUS_REAL")" = "$DBUS_OLD_SHA" ]; then
	printf '%s %s %s\n' "$PW_NEW_SHA" "$DBUS_NEW_SHA" "$LAUNCHER_NEW_SHA" >"$MARKER"
	disable_installer
	printf 'content-triggered audio already installed\n'
	exit 0
fi

[ "$CURRENT_PW" = "$PW_OLD_SHA" ] || fail "refusing unknown pipewire.sh"
[ "$CURRENT_DBUS" = "$DBUS_OLD_SHA" ] || fail "refusing unknown S30dbus"
[ "$CURRENT_LAUNCHER" = "$LAUNCHER_OLD_SHA" ] || fail "refusing unknown launcher supervisor"
[ ! -e "$PW_REAL" ] || fail "unexpected existing PipeWire real script"
[ ! -e "$DBUS_REAL" ] || fail "unexpected existing D-Bus real script"

for PAIR in "$PW_TARGET|$PW_BACKUP|$PW_OLD_SHA" \
	"$DBUS_TARGET|$DBUS_BACKUP|$DBUS_OLD_SHA" \
	"$LAUNCHER_TARGET|$LAUNCHER_BACKUP|$LAUNCHER_OLD_SHA"; do
	SOURCE=${PAIR%%|*}
	REST=${PAIR#*|}
	BACKUP=${REST%%|*}
	EXPECTED=${REST#*|}
	if [ -f "$BACKUP" ]; then
		[ "$(sha_file "$BACKUP")" = "$EXPECTED" ] || fail "existing backup mismatch: $BACKUP"
	else
		cp -p "$SOURCE" "$BACKUP"
	fi
done

rm -f "$PW_TEMP" "$DBUS_TEMP" "$LAUNCHER_TEMP"
cp "$PW_SOURCE" "$PW_TEMP"
cp "$DBUS_SOURCE" "$DBUS_TEMP"
cp "$LAUNCHER_SOURCE" "$LAUNCHER_TEMP"
chmod 755 "$PW_TEMP" "$DBUS_TEMP" "$LAUNCHER_TEMP"
[ "$(sha_file "$PW_TEMP")" = "$PW_NEW_SHA" ] || fail "temporary PipeWire wrapper mismatch"
[ "$(sha_file "$DBUS_TEMP")" = "$DBUS_NEW_SHA" ] || fail "temporary D-Bus wrapper mismatch"
[ "$(sha_file "$LAUNCHER_TEMP")" = "$LAUNCHER_NEW_SHA" ] || fail "temporary launcher mismatch"

INSTALL_STARTED=1
cp -p "$PW_TARGET" "$PW_REAL"
cp -p "$DBUS_TARGET" "$DBUS_REAL"
[ "$(sha_file "$PW_REAL")" = "$PW_OLD_SHA" ] || fail "PipeWire real copy mismatch"
[ "$(sha_file "$DBUS_REAL")" = "$DBUS_OLD_SHA" ] || fail "D-Bus real copy mismatch"

mv -f "$PW_TEMP" "$PW_TARGET" || fail "PipeWire wrapper activation failed"
mv -f "$DBUS_TEMP" "$DBUS_TARGET" || fail "D-Bus wrapper activation failed"
mv -f "$LAUNCHER_TEMP" "$LAUNCHER_TARGET" || fail "launcher activation failed"
sync || fail "sync failed"

[ "$(sha_file "$PW_TARGET")" = "$PW_NEW_SHA" ] || fail "installed PipeWire wrapper mismatch"
[ "$(sha_file "$DBUS_TARGET")" = "$DBUS_NEW_SHA" ] || fail "installed D-Bus wrapper mismatch"
[ "$(sha_file "$LAUNCHER_TARGET")" = "$LAUNCHER_NEW_SHA" ] || fail "installed launcher mismatch"

INSTALL_STARTED=0
printf '%s %s %s\n' "$PW_NEW_SHA" "$DBUS_NEW_SHA" "$LAUNCHER_NEW_SHA" >"$MARKER"
disable_installer
printf 'SUCCESS: D-Bus and PipeWire are now content-triggered; active next boot\n'
