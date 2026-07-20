#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
AUDIO_WORK="$CARD/MUOS/boot-timing/audio-on-demand"
ENTROPY_WORK="$CARD/MUOS/boot-timing/entropy-once"
STORAGE_WORK="$CARD/MUOS/boot-timing/fixed-storage"
LAUNCHER_WORK="$CARD/MUOS/bespoke-launcher"
INIT_DIR="$CARD/MUOS/init"

[ -d "$INIT_DIR" ] || {
	printf 'error: mounted Dani SP card not found: %s\n' "$CARD" >&2
	exit 1
}

for SCRIPT in \
	"$ROOT/userspace/S30dbus-on-demand" \
	"$ROOT/userspace/pipewire-on-demand" \
	"$ROOT/userspace/device-install-audio-on-demand.sh" \
	"$ROOT/userspace/S01entropy-once" \
	"$ROOT/userspace/device-install-entropy-once.sh" \
	"$ROOT/storage/fixed-bind.sh" \
	"$ROOT/storage/device-install-fixed-bind.sh" \
	"$ROOT/launcher/S03danilauncher" \
	"$ROOT/99-frontend-native-log.sh"; do
	sh -n "$SCRIPT"
done

mkdir -p "$AUDIO_WORK" "$ENTROPY_WORK" "$STORAGE_WORK" "$LAUNCHER_WORK"

stage_file() {
	SOURCE="$1"
	TARGET="$2"
	TEMP="${TARGET%/*}/.${TARGET##*/}.new"
	COPYFILE_DISABLE=1 cp -f "$SOURCE" "$TEMP"
	cmp "$SOURCE" "$TEMP"
	mv -f "$TEMP" "$TARGET"
}

stage_file "$ROOT/userspace/S30dbus-on-demand" "$AUDIO_WORK/S30dbus-on-demand"
stage_file "$ROOT/userspace/pipewire-on-demand" "$AUDIO_WORK/pipewire-on-demand"
stage_file "$ROOT/launcher/S03danilauncher" "$LAUNCHER_WORK/S03danilauncher"
stage_file "$ROOT/userspace/S01entropy-once" "$ENTROPY_WORK/S01entropy-once"
stage_file "$ROOT/storage/fixed-bind.sh" "$STORAGE_WORK/fixed-bind.sh"
stage_file "$ROOT/userspace/device-install-audio-on-demand.sh" "$INIT_DIR/77-install-audio-on-demand.sh"
stage_file "$ROOT/userspace/device-install-entropy-once.sh" "$INIT_DIR/78-install-entropy-crng.sh"
stage_file "$ROOT/storage/device-install-fixed-bind.sh" "$INIT_DIR/79-install-fixed-bind-final-log.sh"
stage_file "$ROOT/99-frontend-native-log.sh" "$INIT_DIR/99-boot-timing-marker.sh"

chmod 755 \
	"$AUDIO_WORK/S30dbus-on-demand" \
	"$AUDIO_WORK/pipewire-on-demand" \
	"$LAUNCHER_WORK/S03danilauncher" \
	"$ENTROPY_WORK/S01entropy-once" \
	"$STORAGE_WORK/fixed-bind.sh" \
	"$INIT_DIR/77-install-audio-on-demand.sh" \
	"$INIT_DIR/78-install-entropy-crng.sh" \
	"$INIT_DIR/79-install-fixed-bind-final-log.sh" \
	"$INIT_DIR/99-boot-timing-marker.sh"

rm -f \
	"$AUDIO_WORK"/._S30dbus-on-demand \
	"$AUDIO_WORK"/._pipewire-on-demand \
	"$LAUNCHER_WORK"/._S03danilauncher \
	"$ENTROPY_WORK"/._S01entropy-once \
	"$STORAGE_WORK"/._fixed-bind.sh \
	"$INIT_DIR"/._77-install-audio-on-demand.sh \
	"$INIT_DIR"/._78-install-entropy-crng.sh \
	"$INIT_DIR"/._79-install-fixed-bind-final-log.sh \
	"$INIT_DIR"/._99-boot-timing-marker.sh

sync
printf 'Staged legacy combined proof. For the active card use stage-postmenu-audio-batch.sh.\n'
printf 'Boot once to install; the following boot is the behavior test.\n'
