#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
POLICY=$ROOT/kernel/rocknix/stock-root/mpv-input.conf
CONTROLS=$ROOT/kernel/rocknix/stock-root/bird-mpv-controls.c
PLAYER=$ROOT/kernel/rocknix/stock-root/bird-mpv-player.sh
RUNNER=$ROOT/kernel/rocknix/stock-root/run-content.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-mpv-player.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

[ "$(awk 'NF && $1 !~ /^#/ { print $1 }' "$POLICY")" = \
"VOLUME_DOWN
VOLUME_UP" ] || {
	printf '%s\n' 'active MPV policy contains a second gamepad translation path' >&2
	exit 1
}
grep -Fxq 'VOLUME_DOWN ignore' "$POLICY"
grep -Fxq 'VOLUME_UP ignore' "$POLICY"
! grep -Eq '^GAMEPAD_' "$POLICY"

grep -Fq -- '--input-gamepad=no' "$PLAYER"
grep -Fq -- '--input-default-bindings=no' "$PLAYER"
grep -Fq -- '--input-conf=/flash/bird/mpv-input.conf' "$PLAYER"
grep -Fq -- '--term-osd=no' "$PLAYER"
grep -Fq -- '--msg-level=all=warn' "$PLAYER"
grep -Fq 'BIRD_MPV_TRACE' "$PLAYER"
grep -Fq '/flash/bird/bird-mpv-controls' "$PLAYER"
grep -Fq 'set_kill set "mpv"' "$PLAYER"
grep -Fq 'set_kill stop' "$PLAYER"
if awk '$1 !~ /^#/ { print }' "$PLAYER" | \
	grep -Eq 'start_mplayer|systemctl[[:space:]]+start[[:space:]]+mpv'; then
	printf '%s\n' 'fixed player still starts the retained mpv_sense reader' >&2
	exit 1
fi
grep -Fq 'run_managed "$MPV_PLAYER" "$CONTENT"' "$RUNNER"

# Fixed physical map from the accepted RG34XX-SP labels. X and
# shoulder+Select cycle audio; a bumper tap changes player-relative volume,
# while a held bumper remains the one-handed modifier. Menu+D-pad and
# Menu+bumper picture controls cannot overlap ordinary seeking or volume.
for TOKEN in \
	'#define BIRD_BUTTON_A BTN_EAST' \
	'#define BIRD_BUTTON_B BTN_SOUTH' \
	'#define BIRD_BUTTON_X BTN_WEST' \
	'#define BIRD_BUTTON_Y BTN_NORTH' \
	'command_pause' \
	'command_frame_step' \
	'command_audio' \
	'command_progress' \
	'command_volume_down' \
	'command_volume_up' \
	'command_brightness_down' \
	'command_brightness_up' \
	'command_chapter_previous' \
	'command_chapter_next' \
	'command_playlist_previous' \
	'command_playlist_next' \
	'PENDING_BUTTON_AUDIO' \
	'handle_shoulder' \
	'use_held_shoulders' \
	'command_contrast_down' \
	'command_contrast_up' \
	'command_saturation_down' \
	'command_saturation_up' \
	'BIRD_DEVICE_INPUT_PREFERRED_EVENT' \
	'h700_input_contract_matches' \
	'EVIOCGKEY_768' \
	'discard_until_syn_report' \
	'open_synchronized_input' \
	'disconnect_ipc' \
	'sys_ppoll'; do
	grep -Fq "$TOKEN" "$CONTROLS" || {
		printf 'missing fixed MPV control token: %s\n' "$TOKEN" >&2
		exit 1
	}
done

grep -Fq 'state->select_held && state->start_held' "$CONTROLS"
grep -Fq 'state->select_pending = PENDING_BUTTON_NONE' "$CONTROLS"
grep -Fq 'SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC' "$CONTROLS"
grep -Fq 'MSG_NOSIGNAL' "$CONTROLS"

# Exercise the exact player boundary with host stubs. It must start one fixed
# control owner, disable both retained MPV gamepad paths, preserve geometry and
# content arguments, and remove the IPC endpoint on return.
cat >"$TMP/controls" <<'EOF'
#!/bin/sh
printf '%s\n' start >>"$BIRD_TEST_EVENTS"
trap 'printf "%s\n" stop >>"$BIRD_TEST_EVENTS"; exit 0' TERM INT HUP
while :; do sleep 1; done
EOF
cat >"$TMP/mpv" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$BIRD_TEST_ARGS"
sleep 0.1
EOF
cat >"$TMP/profile" <<'EOF'
set_kill() {
	printf 'set_kill %s %s\n' "$1" "${2:-}" >>"$BIRD_TEST_EVENTS"
}
EOF
cat >"$TMP/fbwidth" <<'EOF'
#!/bin/sh
printf '%s\n' 720
EOF
cat >"$TMP/fbheight" <<'EOF'
#!/bin/sh
printf '%s\n' 480
EOF
chmod 0755 "$TMP/controls" "$TMP/mpv" "$TMP/fbwidth" "$TMP/fbheight"
: >"$TMP/movie.mkv"
[ ! -e /tmp/mpvsocket ] || {
	printf '%s\n' 'host MPV socket already exists; refusing destructive wrapper test' >&2
	exit 1
}
BIRD_MPV_CONTROLS=$TMP/controls \
BIRD_MPV_PROGRAM=$TMP/mpv \
BIRD_FBWIDTH_PROGRAM=$TMP/fbwidth \
BIRD_FBHEIGHT_PROGRAM=$TMP/fbheight \
BIRD_PROFILE_PATH=$TMP/profile \
BIRD_TEST_EVENTS=$TMP/events \
BIRD_TEST_ARGS=$TMP/args \
	"$PLAYER" "$TMP/movie.mkv"
grep -Fxq start "$TMP/events"
grep -Fxq stop "$TMP/events"
grep -Fxq 'set_kill set mpv' "$TMP/events"
grep -Fxq 'set_kill stop ' "$TMP/events"
grep -Fxq -- '--input-gamepad=no' "$TMP/args"
grep -Fxq -- '--input-default-bindings=no' "$TMP/args"
grep -Fxq -- '--term-osd=no' "$TMP/args"
grep -Fxq -- '--msg-level=all=warn' "$TMP/args"
grep -Fxq -- '--geometry=720x480' "$TMP/args"
grep -Fxq -- "$TMP/movie.mkv" "$TMP/args"
grep -Fxq -- '--input-ipc-server=/tmp/mpvsocket' "$TMP/args"
[ ! -e /tmp/mpvsocket ]

: >"$TMP/events"
BIRD_MPV_TRACE=1 \
BIRD_MPV_CONTROLS=$TMP/controls \
BIRD_MPV_PROGRAM=$TMP/mpv \
BIRD_FBWIDTH_PROGRAM=$TMP/fbwidth \
BIRD_FBHEIGHT_PROGRAM=$TMP/fbheight \
BIRD_PROFILE_PATH=$TMP/profile \
BIRD_TEST_EVENTS=$TMP/events \
BIRD_TEST_ARGS=$TMP/args \
	"$PLAYER" "$TMP/movie.mkv"
if grep -Eq '^--(term-osd=no|msg-level=all=warn)$' "$TMP/args"; then
	printf '%s\n' 'trace MPV invocation retained release output suppression' >&2
	exit 1
fi
[ ! -e /tmp/mpvsocket ]

"$ROOT/kernel/rocknix/tests/test-mpv-controls-c.sh"
printf '%s\n' 'stock-root MPV controls tests: PASS'
