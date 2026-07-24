#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
AUDIO_WORK="$CARD/MUOS/boot-timing/audio-on-demand"
LAUNCHER_WORK="$CARD/MUOS/bespoke-launcher"
INIT_DIR="$CARD/MUOS/init"

[ -d "$INIT_DIR" ] || {
	printf 'error: mounted birdOS card not found: %s\n' "$CARD" >&2
	exit 1
}

for SCRIPT in \
	"$ROOT/userspace/S30dbus-on-demand" \
	"$ROOT/userspace/pipewire-on-demand" \
	"$ROOT/userspace/patch-postmenu-audio-sysinit.sh" \
	"$ROOT/userspace/device-capture-audio-profile.sh" \
	"$ROOT/userspace/device-install-postmenu-audio.sh" \
	"$ROOT/launcher/S03birdlauncher" \
	"$ROOT/99-frontend-native-log.sh"; do
	sh -n "$SCRIPT"
done

mkdir -p "$AUDIO_WORK" "$LAUNCHER_WORK"

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
stage_file "$ROOT/userspace/patch-postmenu-audio-sysinit.sh" "$AUDIO_WORK/patch-postmenu-audio-sysinit.sh"
stage_file "$ROOT/launcher/S03birdlauncher" "$LAUNCHER_WORK/S03birdlauncher"
stage_file "$ROOT/userspace/device-capture-audio-profile.sh" "$INIT_DIR/74-capture-audio-profile.sh"
stage_file "$ROOT/userspace/device-install-postmenu-audio.sh" "$INIT_DIR/75-install-postmenu-audio.sh"
stage_file "$ROOT/99-frontend-native-log.sh" "$INIT_DIR/99-boot-timing-marker.sh"

chmod 755 \
	"$AUDIO_WORK/S30dbus-on-demand" \
	"$AUDIO_WORK/pipewire-on-demand" \
	"$AUDIO_WORK/patch-postmenu-audio-sysinit.sh" \
	"$LAUNCHER_WORK/S03birdlauncher" \
	"$INIT_DIR/74-capture-audio-profile.sh" \
	"$INIT_DIR/75-install-postmenu-audio.sh" \
	"$INIT_DIR/99-boot-timing-marker.sh"

rm -f \
	"$AUDIO_WORK"/._S30dbus-on-demand \
	"$AUDIO_WORK"/._pipewire-on-demand \
	"$AUDIO_WORK"/._patch-postmenu-audio-sysinit.sh \
	"$LAUNCHER_WORK"/._S03birdlauncher \
	"$INIT_DIR"/._74-capture-audio-profile.sh \
	"$INIT_DIR"/._75-install-postmenu-audio.sh \
	"$INIT_DIR"/._99-boot-timing-marker.sh

sync
printf 'Staged: audio-profile capture, concurrent post-menu session warm-up, and logs.\n'
printf 'Boot once to install; the following boot tests the new runtime policy.\n'
