#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
ROOT="$ROM_MOUNT/MUOS/boot-timing/audio-profile"
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)
DEST="$ROOT/capture/$BOOT_ID"
LOG_FILE="$ROOT/capture.log"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/74-capture-audio-profile.sh"

mkdir -p "$DEST"
exec >>"$LOG_FILE" 2>&1

copy_tree() {
	SOURCE="$1"
	NAME="$2"
	[ -e "$SOURCE" ] || return 0
	cp -R "$SOURCE" "$DEST/$NAME"
}

printf 'audio profile capture start: %s\n' "$BOOT_ID"
copy_tree /usr/share/pipewire usr-share-pipewire
copy_tree /usr/share/wireplumber usr-share-wireplumber

find /opt/muos/share/conf -maxdepth 2 -type f 2>/dev/null | LC_ALL=C sort \
	>"$DEST/muos-conf-files.txt"
while IFS= read -r FILE; do
	case "$FILE" in
		*pipewire* | *wireplumber* | *alsa*)
			REL=${FILE#/opt/muos/share/conf/}
			REL_DIR=${REL%/*}
			[ "$REL_DIR" != "$REL" ] || REL_DIR=.
			mkdir -p "$DEST/muos-conf/$REL_DIR"
			cp "$FILE" "$DEST/muos-conf/$REL"
			;;
	esac
done <"$DEST/muos-conf-files.txt"

find "$DEST" -type f ! -name sha256sums.txt -exec sha256sum {} \; >"$DEST/sha256sums.txt"
ps -eo pid,ppid,ni,stat,comm,args >"$DEST/processes.txt" 2>/dev/null || ps >"$DEST/processes.txt"
{
	printf 'dbus='; pidof dbus-daemon 2>/dev/null || :
	printf '\npipewire='; pidof pipewire 2>/dev/null || :
	printf '\nwireplumber='; pidof wireplumber 2>/dev/null || :
	printf '\n'
} >"$DEST/audio-pids.txt"

cp -f "$DEST/sha256sums.txt" "$ROOT/latest-sha256sums.txt"
printf '%s\n' "$BOOT_ID" >"$ROOT/latest-capture"
[ ! -f "$CARD_INSTALLER" ] || mv -f "$CARD_INSTALLER" "$CARD_INSTALLER.done"
printf 'SUCCESS: exact PipeWire/WirePlumber configuration captured\n'
