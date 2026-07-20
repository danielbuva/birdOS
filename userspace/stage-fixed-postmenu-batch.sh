#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
STARTUP_WORK="$CARD/MUOS/boot-timing/fixed-startup-tail"
AUDIO_WORK="$CARD/MUOS/boot-timing/audio-profile/fixed"
SNAPSHOT_WORK="$CARD/MUOS/boot-timing/stable-runtime"
INIT_DIR="$CARD/MUOS/init"

[ -d "$INIT_DIR" ] || {
	printf 'error: mounted Dani SP card not found: %s\n' "$CARD" >&2
	exit 1
}

for SCRIPT in \
	"$ROOT/userspace/patch-fixed-startup-tail.sh" \
	"$ROOT/userspace/device-install-fixed-startup-tail.sh" \
	"$ROOT/userspace/device-install-fixed-audio-profile.sh" \
	"$ROOT/userspace/S98dani-stable-snapshot" \
	"$ROOT/userspace/device-install-stable-snapshot.sh" \
	"$ROOT/99-frontend-native-log.sh"; do
	sh -n "$SCRIPT"
done

mkdir -p "$STARTUP_WORK" "$AUDIO_WORK" "$SNAPSHOT_WORK" "$INIT_DIR"

stage_file() {
	SOURCE="$1"
	TARGET="$2"
	TEMP="${TARGET%/*}/.${TARGET##*/}.new"
	COPYFILE_DISABLE=1 cp -f "$SOURCE" "$TEMP"
	cmp "$SOURCE" "$TEMP"
	mv -f "$TEMP" "$TARGET"
}

stage_file "$ROOT/userspace/patch-fixed-startup-tail.sh" "$STARTUP_WORK/patch-fixed-startup-tail.sh"
stage_file "$ROOT/userspace/89-dani-fixed-main.lua" "$AUDIO_WORK/89-dani-fixed-main.lua"
stage_file "$ROOT/userspace/89-dani-fixed-bluetooth.lua" "$AUDIO_WORK/89-dani-fixed-bluetooth.lua"
stage_file "$ROOT/userspace/S98dani-stable-snapshot" "$SNAPSHOT_WORK/S98dani-stable-snapshot"
stage_file "$ROOT/userspace/device-install-stable-snapshot.sh" "$INIT_DIR/71-install-stable-snapshot.sh"
stage_file "$ROOT/userspace/device-install-fixed-startup-tail.sh" "$INIT_DIR/72-install-fixed-startup-tail.sh"
stage_file "$ROOT/userspace/device-install-fixed-audio-profile.sh" "$INIT_DIR/73-install-fixed-audio-profile.sh"
stage_file "$ROOT/99-frontend-native-log.sh" "$INIT_DIR/99-boot-timing-marker.sh"

chmod 755 \
	"$STARTUP_WORK/patch-fixed-startup-tail.sh" \
	"$SNAPSHOT_WORK/S98dani-stable-snapshot" \
	"$INIT_DIR/71-install-stable-snapshot.sh" \
	"$INIT_DIR/72-install-fixed-startup-tail.sh" \
	"$INIT_DIR/73-install-fixed-audio-profile.sh" \
	"$INIT_DIR/99-boot-timing-marker.sh"

rm -f \
	"$STARTUP_WORK"/._patch-fixed-startup-tail.sh \
	"$AUDIO_WORK"/._89-dani-fixed-main.lua \
	"$AUDIO_WORK"/._89-dani-fixed-bluetooth.lua \
	"$SNAPSHOT_WORK"/._S98dani-stable-snapshot \
	"$INIT_DIR"/._71-install-stable-snapshot.sh \
	"$INIT_DIR"/._72-install-fixed-startup-tail.sh \
	"$INIT_DIR"/._73-install-fixed-audio-profile.sh \
	"$INIT_DIR"/._99-boot-timing-marker.sh

printf 'armed\n' >"$SNAPSHOT_WORK/armed"
sync
printf 'Staged three independent parts: fixed startup tail, fixed audio profile, and one-shot stable snapshot.\n'
printf 'Boot once to install; the following boot tests and captures the new behavior.\n'

