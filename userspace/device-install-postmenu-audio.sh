#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/audio-on-demand"
PW_SOURCE="$WORK_DIR/pipewire-on-demand"
DBUS_SOURCE="$WORK_DIR/S30dbus-on-demand"
PATCH_SOURCE="$WORK_DIR/patch-postmenu-audio-sysinit.sh"
LAUNCHER_SOURCE="$ROM_MOUNT/MUOS/bespoke-launcher/S03danilauncher"
PW_TARGET="/opt/muos/script/system/pipewire.sh"
PW_REAL="$PW_TARGET.dani-real"
DBUS_TARGET="/opt/muos/script/init/S30dbus"
DBUS_VISIBLE_REAL="/opt/muos/script/init/S30dbus.dani-real"
DBUS_HIDDEN_REAL="/opt/muos/script/init/.S30dbus.dani-real"
LAUNCHER_TARGET="/opt/muos/script/init/S03danilauncher"
SYSINIT_TARGET="/opt/muos/script/init/sysinit"
BACKUP_DIR="$WORK_DIR/backup/postmenu-warm"
MARKER="$WORK_DIR/postmenu-audio-installed"
LOG_FILE="$WORK_DIR/postmenu-install.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/75-install-postmenu-audio.sh"

PW_OLD_SHA="3c03475cddde170325b707b0cfc3a07c935c4ddd7d5883863f66b9436b254e85"
DBUS_OLD_SHA="68fe4472c703bde2515bbce956add89ef329813921aa04c8ec1f28199f3d0cdb"
LAUNCHER_OLD_SHA="70e1aa1485357a5cf0951641976a9121f9aaa1a388e75366d0287582db25b766"
SYSINIT_OLD_SHA="a92e44ddc06d0ddf2d6b2279cfc74f270e980d0568ba99fbfd08493f4bdced76"
PW_STOCK_SHA="81c6890f17deafec9d9afe214fba0badcb2b2c42a334ef3e57a74f3810a4d79d"
DBUS_STOCK_SHA="726c0803e66157bbb9aca253b3d0c5146d577a8264032a6cd82deebdb870cd37"

PW_NEW_SHA="54aae202d0ca514dfc63d426d651bb4be99b7f5983936e49cb51575290782e62"
DBUS_NEW_SHA="b942c2877db0be3012ec46cfdbe3c555982dcf9dfeaf658fc21ca5d3169f9817"
LAUNCHER_NEW_SHA="ef3ae835a1ef9c74156967a9e52f7398ccb2f96e282773df0416cd771ee9c05a"
PATCH_SHA="f8e377affe5505146d28c03df9ab0b5234053be28bd8e99ffa59052d20982033"
SYSINIT_NEW_SHA="e0226ca38bc4127f2ac2ed2ce2f6d39483ca4ce8e962d9a63be5f7cf9b4d91a1"

PW_TEMP="$PW_TARGET.dani-postmenu-new"
DBUS_TEMP="$DBUS_TARGET.dani-postmenu-new"
DBUS_REAL_TEMP="/opt/muos/script/init/.S30dbus.dani-real-new"
LAUNCHER_TEMP="$LAUNCHER_TARGET.dani-postmenu-new"
SYSINIT_TEMP="$SYSINIT_TARGET.dani-postmenu-new"
INSTALL_STARTED=0

mkdir -p "$BACKUP_DIR"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

disable_installer() {
	[ ! -f "$CARD_INSTALLER" ] || mv -f "$CARD_INSTALLER" "$CARD_INSTALLER.done"
}

rollback() {
	[ "$INSTALL_STARTED" -eq 1 ] || return 0
	printf 'rollback: restoring pre-post-menu audio files\n'
	cp -f "$BACKUP_DIR/pipewire.sh" "$PW_TARGET" 2>/dev/null || :
	cp -f "$BACKUP_DIR/S30dbus" "$DBUS_TARGET" 2>/dev/null || :
	cp -f "$BACKUP_DIR/S03danilauncher" "$LAUNCHER_TARGET" 2>/dev/null || :
	cp -f "$BACKUP_DIR/sysinit" "$SYSINIT_TARGET" 2>/dev/null || :
	cp -f "$WORK_DIR/backup/S30dbus.stock" "$DBUS_VISIBLE_REAL" 2>/dev/null || :
	chmod 755 "$PW_TARGET" "$DBUS_TARGET" "$DBUS_VISIBLE_REAL" \
		"$LAUNCHER_TARGET" "$SYSINIT_TARGET" 2>/dev/null || :
	rm -f "$DBUS_HIDDEN_REAL" "$PW_TEMP" "$DBUS_TEMP" "$DBUS_REAL_TEMP" \
		"$LAUNCHER_TEMP" "$SYSINIT_TEMP"
}

fail() {
	printf 'FAILED: %s\n' "$*"
	exit 1
}

trap rollback 0 1 2 15

printf 'post-menu session-warm audio migration start\n'
[ "$(sha_file "$PW_SOURCE")" = "$PW_NEW_SHA" ] || fail "PipeWire source mismatch"
[ "$(sha_file "$DBUS_SOURCE")" = "$DBUS_NEW_SHA" ] || fail "D-Bus source mismatch"
[ "$(sha_file "$LAUNCHER_SOURCE")" = "$LAUNCHER_NEW_SHA" ] || fail "launcher source mismatch"
[ "$(sha_file "$PATCH_SOURCE")" = "$PATCH_SHA" ] || fail "sysinit patch source mismatch"

for FILE in "$PW_TARGET" "$PW_REAL" "$DBUS_TARGET" "$LAUNCHER_TARGET" "$SYSINIT_TARGET"; do
	[ -f "$FILE" ] || fail "active file missing: $FILE"
done
[ "$(sha_file "$PW_REAL")" = "$PW_STOCK_SHA" ] || fail "stock PipeWire real mismatch"

CURRENT_PW=$(sha_file "$PW_TARGET")
CURRENT_DBUS=$(sha_file "$DBUS_TARGET")
CURRENT_LAUNCHER=$(sha_file "$LAUNCHER_TARGET")
CURRENT_SYSINIT=$(sha_file "$SYSINIT_TARGET")
printf 'current PipeWire/D-Bus/launcher/sysinit: %s %s %s %s\n' \
	"$CURRENT_PW" "$CURRENT_DBUS" "$CURRENT_LAUNCHER" "$CURRENT_SYSINIT"

if [ "$CURRENT_PW" = "$PW_NEW_SHA" ] && [ "$CURRENT_DBUS" = "$DBUS_NEW_SHA" ] && \
	[ "$CURRENT_LAUNCHER" = "$LAUNCHER_NEW_SHA" ] && \
	[ "$CURRENT_SYSINIT" = "$SYSINIT_NEW_SHA" ] && \
	[ -f "$DBUS_HIDDEN_REAL" ] && \
	[ "$(sha_file "$DBUS_HIDDEN_REAL")" = "$DBUS_STOCK_SHA" ]; then
	if [ -f "$DBUS_VISIBLE_REAL" ]; then
		[ "$(sha_file "$DBUS_VISIBLE_REAL")" = "$DBUS_STOCK_SHA" ] || \
			fail "unexpected visible D-Bus real file"
		rm -f "$DBUS_VISIBLE_REAL"
	fi
	printf '%s\n' "$PW_NEW_SHA $DBUS_NEW_SHA $LAUNCHER_NEW_SHA $SYSINIT_NEW_SHA" >"$MARKER"
	disable_installer
	INSTALL_STARTED=0
	trap - 0 1 2 15
	printf 'post-menu session-warm audio already installed\n'
	exit 0
fi

[ "$CURRENT_PW" = "$PW_OLD_SHA" ] || fail "refusing unknown PipeWire wrapper"
[ "$CURRENT_DBUS" = "$DBUS_OLD_SHA" ] || fail "refusing unknown D-Bus wrapper"
[ "$CURRENT_LAUNCHER" = "$LAUNCHER_OLD_SHA" ] || fail "refusing unknown launcher"
[ "$CURRENT_SYSINIT" = "$SYSINIT_OLD_SHA" ] || fail "refusing unknown sysinit"
[ -f "$DBUS_VISIBLE_REAL" ] || fail "visible stock D-Bus real missing"
[ "$(sha_file "$DBUS_VISIBLE_REAL")" = "$DBUS_STOCK_SHA" ] || fail "visible stock D-Bus real mismatch"
[ ! -e "$DBUS_HIDDEN_REAL" ] || fail "unexpected hidden D-Bus real exists"

for PAIR in \
	"$PW_TARGET|$BACKUP_DIR/pipewire.sh|$PW_OLD_SHA" \
	"$DBUS_TARGET|$BACKUP_DIR/S30dbus|$DBUS_OLD_SHA" \
	"$LAUNCHER_TARGET|$BACKUP_DIR/S03danilauncher|$LAUNCHER_OLD_SHA" \
	"$SYSINIT_TARGET|$BACKUP_DIR/sysinit|$SYSINIT_OLD_SHA"; do
	SOURCE=${PAIR%%|*}
	REST=${PAIR#*|}
	BACKUP=${REST%%|*}
	EXPECTED=${REST#*|}
	if [ -f "$BACKUP" ]; then
		[ "$(sha_file "$BACKUP")" = "$EXPECTED" ] || fail "backup mismatch: $BACKUP"
	else
		cp "$SOURCE" "$BACKUP"
	fi
done

rm -f "$PW_TEMP" "$DBUS_TEMP" "$DBUS_REAL_TEMP" "$LAUNCHER_TEMP" "$SYSINIT_TEMP"
cp "$PW_SOURCE" "$PW_TEMP"
cp "$DBUS_SOURCE" "$DBUS_TEMP"
cp "$DBUS_VISIBLE_REAL" "$DBUS_REAL_TEMP"
cp "$LAUNCHER_SOURCE" "$LAUNCHER_TEMP"
cp "$SYSINIT_TARGET" "$SYSINIT_TEMP"
chmod 755 "$PW_TEMP" "$DBUS_TEMP" "$DBUS_REAL_TEMP" "$LAUNCHER_TEMP" "$SYSINIT_TEMP"
"$PATCH_SOURCE" "$SYSINIT_TEMP"

[ "$(sha_file "$PW_TEMP")" = "$PW_NEW_SHA" ] || fail "temporary PipeWire mismatch"
[ "$(sha_file "$DBUS_TEMP")" = "$DBUS_NEW_SHA" ] || fail "temporary D-Bus mismatch"
[ "$(sha_file "$DBUS_REAL_TEMP")" = "$DBUS_STOCK_SHA" ] || fail "temporary D-Bus real mismatch"
[ "$(sha_file "$LAUNCHER_TEMP")" = "$LAUNCHER_NEW_SHA" ] || fail "temporary launcher mismatch"
[ "$(sha_file "$SYSINIT_TEMP")" = "$SYSINIT_NEW_SHA" ] || fail "temporary sysinit mismatch"

INSTALL_STARTED=1
mv -f "$DBUS_REAL_TEMP" "$DBUS_HIDDEN_REAL"
mv -f "$PW_TEMP" "$PW_TARGET"
mv -f "$DBUS_TEMP" "$DBUS_TARGET"
mv -f "$LAUNCHER_TEMP" "$LAUNCHER_TARGET"
mv -f "$SYSINIT_TEMP" "$SYSINIT_TARGET"
rm -f "$DBUS_VISIBLE_REAL"
sync

[ "$(sha_file "$PW_TARGET")" = "$PW_NEW_SHA" ] || fail "installed PipeWire mismatch"
[ "$(sha_file "$DBUS_TARGET")" = "$DBUS_NEW_SHA" ] || fail "installed D-Bus mismatch"
[ "$(sha_file "$DBUS_HIDDEN_REAL")" = "$DBUS_STOCK_SHA" ] || fail "installed hidden D-Bus real mismatch"
[ "$(sha_file "$LAUNCHER_TARGET")" = "$LAUNCHER_NEW_SHA" ] || fail "installed launcher mismatch"
[ "$(sha_file "$SYSINIT_TARGET")" = "$SYSINIT_NEW_SHA" ] || fail "installed sysinit mismatch"
[ ! -e "$DBUS_VISIBLE_REAL" ] || fail "visible D-Bus real was not removed"

printf '%s\n' "$PW_NEW_SHA $DBUS_NEW_SHA $LAUNCHER_NEW_SHA $SYSINIT_NEW_SHA" >"$MARKER"
disable_installer
INSTALL_STARTED=0
trap - 0 1 2 15
printf 'SUCCESS: audio now warms concurrently after the menu and remains session-resident\n'
