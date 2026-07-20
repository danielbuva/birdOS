#!/bin/sh

# Exact one-card compatibility bind map. All mutable muOS state comes from the
# OS card; there is no SD2/USB source selection and no discovery worker fanout.
ROM_ROOT="/mnt/mmc/MUOS"
STORE_ROOT="/run/muos/storage"
SHARE_ROOT="/opt/muos/share"
BINDMAP="$STORE_ROOT/bindmap"
MOUNT_FAILURE="/tmp/muos/fixed-bind-failure"
STAGES="/tmp/muos/fixed-bind.tsv"
KEYS=""

PRIORITY_LOCS="application bios init info/track music save theme"
STANDARD_LOCS="info/catalogue info/name info/collection info/history info/override network screenshot syncthing package/catalogue package/config"

mkdir -p /tmp/muos "$STORE_ROOT"
rm -f "$STORE_ROOT/mount_ready" "$MOUNT_FAILURE"
: >"$BINDMAP"
printf 'uptime_s\tevent\n' >"$STAGES"

mark() {
	IFS=' ' read -r NOW _ </proc/uptime
	printf '%s\t%s\n' "$NOW" "$1" >>"$STAGES"
}

is_mounted() {
	grep -q " $1 " /proc/self/mountinfo 2>/dev/null
}

loc_key() {
	case "$1" in
		info/catalogue*) echo catalogue ;;
		info/name*) echo name ;;
		info/collection*) echo collection ;;
		info/history*) echo history ;;
		info/track*) echo track ;;
		package/*) echo package ;;
		*) echo "$1" ;;
	esac
}

have_key() {
	case " $KEYS " in
		*" $1 "*) return 0 ;;
	esac
	return 1
}

write_map() {
	KEY="$1"
	BACKEND="$2"
	SOURCE="$3"
	have_key "$KEY" && return 0
	KEYS="$KEYS $KEY"
	printf '%s|%s|%s\n' "$KEY" "$BACKEND" "$SOURCE" >>"$BINDMAP"
}

bind_one() {
	LOC="$1"
	SRC="$ROM_ROOT/$LOC"
	TARGET="$STORE_ROOT/$LOC"
	KEY=$(loc_key "$LOC")

	mkdir -p "$SRC" "$TARGET" || return 1
	if is_mounted "$TARGET"; then
		umount "$TARGET" 2>/dev/null || return 1
	fi
	mount -n --bind "$SRC" "$TARGET" || return 1
	write_map "$KEY" ROM "$SRC"
}

bind_list() {
	for LOC in $1; do
		bind_one "$LOC" || {
			printf '%s\n' "$LOC" >>"$MOUNT_FAILURE"
			return 1
		}
	done
}

bind_emulator() {
	STORE_PATH="$1"
	EMU_PATH="$2"
	SRC="$STORE_ROOT/$STORE_PATH"
	TARGET="$SHARE_ROOT/emulator/$EMU_PATH"
	mkdir -p "$SRC" "$TARGET" || return 1
	if is_mounted "$TARGET"; then
		umount "$TARGET" 2>/dev/null || return 1
	fi
	mount -n --bind "$SRC" "$TARGET"
}

mark fixed-bind-start
bind_list "$PRIORITY_LOCS" || exit 1
: >"$STORE_ROOT/mount_ready"
mark fixed-bind-priority-ready

bind_list "$STANDARD_LOCS" || exit 1
mark fixed-bind-standard-ready

EMU_BINDS='
save/pico8|pico8/.lexaloffle/pico-8
save/drastic-legacy/backup|drastic-legacy/backup
save/drastic-legacy/savestates|drastic-legacy/savestates
save/file/OpenBOR-Ext|openbor/userdata/saves/openbor
screenshot|openbor/userdata/screenshots/openbor
save/game/PPSSPP-Ext|ppsspp/.config/ppsspp/PSP/GAME
save/file/PPSSPP-Ext|ppsspp/.config/ppsspp/PSP/SAVEDATA
save/state/PPSSPP-Ext|ppsspp/.config/ppsspp/PSP/PPSSPP_STATE
'

OLD_IFS=$IFS
IFS='
'
for LINE in $EMU_BINDS; do
	[ -n "$LINE" ] || continue
	bind_emulator "${LINE%%|*}" "${LINE#*|}" || {
		printf '%s\n' "$LINE" >>"$MOUNT_FAILURE"
		IFS=$OLD_IFS
		exit 1
	}
done
IFS=$OLD_IFS
mark fixed-bind-emulators-ready

RA_DIR="$SHARE_ROOT/emulator/retroarch"
write_map archive ROM /mnt/mmc/ARCHIVE
write_map assign INTERNAL "$SHARE_ROOT/info/assign"
write_map cheats INTERNAL "$RA_DIR/cheats"
write_map config INTERNAL "$SHARE_ROOT/info/config"
write_map content INTERNAL "$SHARE_ROOT/info/content"
write_map core INTERNAL "$SHARE_ROOT/core"
write_map emulator INTERNAL "$SHARE_ROOT/emulator"
write_map hotkey INTERNAL "$SHARE_ROOT/hotkey"
write_map info INTERNAL "$SHARE_ROOT/info"
write_map language INTERNAL "$SHARE_ROOT/language"
write_map overlays INTERNAL "$RA_DIR/overlays"
write_map override INTERNAL "$SHARE_ROOT/info/override"
write_map script INTERNAL /opt/muos/script
write_map shaders INTERNAL "$RA_DIR/shaders"
write_map task INTERNAL "$SHARE_ROOT/task"

LC_ALL=C awk -F'|' -v OFS='|' '$1 == "package" { sub(/\/package\/.*/, "/package", $3) } { print }' \
	"$BINDMAP" | LC_ALL=C sort -t'|' -k1,1 >"$BINDMAP.tmp" && mv "$BINDMAP.tmp" "$BINDMAP" || exit 1
mark fixed-bind-complete
