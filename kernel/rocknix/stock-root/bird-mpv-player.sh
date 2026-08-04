#!/bin/bash

# Run the retained ROCKNIX MPV provider with exactly one RG34XX-SP input owner.
# The stock start_mplayer.sh also starts mpv_sense while enabling MPV's SDL
# gamepad path; bird-mpv-controls replaces both overlapping translations.

set -u

CONTENT=${1:-}
PROFILE=${BIRD_PROFILE_PATH:-/etc/profile}
IPC_SOCKET=/tmp/mpvsocket
CONTROLS=${BIRD_MPV_CONTROLS:-/flash/bird/bird-mpv-controls}
MPV=${BIRD_MPV_PROGRAM:-/usr/bin/mpv}
FBWIDTH_PROGRAM=${BIRD_FBWIDTH_PROGRAM:-fbwidth}
FBHEIGHT_PROGRAM=${BIRD_FBHEIGHT_PROGRAM:-fbheight}
CONTROLS_PID=
KILL_PUBLISHED=0

[ -n "$CONTENT" ] && [ -f "$CONTENT" ] && [ -x "$CONTROLS" ] || exit 1
[ ! -r "$PROFILE" ] || . "$PROFILE"

cleanup_controls() {
	if [ -n "$CONTROLS_PID" ]; then
		kill "$CONTROLS_PID" 2>/dev/null || :
		wait "$CONTROLS_PID" 2>/dev/null || :
		CONTROLS_PID=
	fi
	if [ "$KILL_PUBLISHED" -eq 1 ]; then
		set_kill stop || :
		KILL_PUBLISHED=0
	fi
	rm -f "$IPC_SOCKET"
}

trap 'cleanup_controls' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

rm -f "$IPC_SOCKET" || exit 1
set_kill set "mpv" || exit 1
KILL_PUBLISHED=1
"$CONTROLS" &
CONTROLS_PID=$!

FBWIDTH=$("$FBWIDTH_PROGRAM") || exit 1
FBHEIGHT=$("$FBHEIGHT_PROGRAM") || exit 1
if [ "$FBWIDTH" -ge "$FBHEIGHT" ]; then
	RES=${FBWIDTH}x${FBHEIGHT}
else
	RES=${FBHEIGHT}x${FBWIDTH}
fi

run_mpv() {
	"$MPV" --fullscreen --geometry="$RES" --hwdec=auto-safe \
		--input-gamepad=no --input-default-bindings=no "$@" \
		--input-conf=/flash/bird/mpv-input.conf \
		--input-ipc-server="$IPC_SOCKET" "$CONTENT"
}

case ${BIRD_MPV_TRACE:-0} in
	1) run_mpv ;;
	*) run_mpv --term-osd=no --msg-level=all=warn ;;
esac
exit $?
