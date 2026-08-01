#!/bin/sh
# Host-side checks for fixed audio reconciliation and MPV position-only resume.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
VOLUME=$ROOT/kernel/rocknix/stock-root/bird-volume.sh
RUNNER=$ROOT/kernel/rocknix/stock-root/run-content.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-media-audio.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

mkdir -p "$TMP/bin" "$TMP/storage/.config/system/configs" \
	"$TMP/storage/.config/mpv/watch_later" \
	"$TMP/storage/.local/state/mpv/watch_later"
printf '%s\n' 'system.audio.volume=50' \
	>"$TMP/storage/.config/system/configs/system.cfg"

cat >"$TMP/bin/volume" <<'EOF'
#!/bin/sh
printf 'volume %s\n' "$*" >>"$BIRD_TEST_EVENTS"
[ "${BIRD_TEST_VOLUME_FAIL:-0}" -eq 0 ]
EOF
cat >"$TMP/bin/pactl" <<'EOF'
#!/bin/sh
printf 'pactl %s\n' "$*" >>"$BIRD_TEST_EVENTS"
case "$*" in
	'get-sink-volume @DEFAULT_SINK@')
		printf 'Volume: front-left: 32768 / %s%% / -18.06 dB, front-right: 32768 / %s%% / -18.06 dB\n' \
			"$BIRD_TEST_VOLUME" "$BIRD_TEST_VOLUME"
		;;
	'get-sink-mute @DEFAULT_SINK@') printf 'Mute: %s\n' "$BIRD_TEST_MUTE" ;;
esac
EOF
cat >"$TMP/bin/amixer" <<'EOF'
#!/bin/sh
printf 'amixer %s\n' "$*" >>"$BIRD_TEST_EVENTS"
case "$*" in
	*"cget iface=CARD,name='Headphone Jack'"*)
		[ "$BIRD_TEST_JACK" != fail ] || exit 1
		printf '  : values=%s\n' "$BIRD_TEST_JACK"
		;;
	*"cget name='Speaker Switch'"*)
		[ "$BIRD_TEST_SPEAKER" != fail ] || exit 1
		printf '  : values=%s\n' "$BIRD_TEST_SPEAKER"
		;;
esac
EOF
chmod 0755 "$TMP/bin/volume" "$TMP/bin/pactl" "$TMP/bin/amixer"

sed -e "s#/usr/bin/volume#$TMP/bin/volume#" \
	-e "s#pactl#$TMP/bin/pactl#g" \
	-e "s#/usr/bin/amixer#$TMP/bin/amixer#" \
	-e "s#/storage#$TMP/storage#g" "$VOLUME" >"$TMP/volume-test.sh"
chmod 0755 "$TMP/volume-test.sh"
export BIRD_TEST_EVENTS=$TMP/audio-events
export BIRD_TEST_VOLUME=50 BIRD_TEST_MUTE=no

run_restore() {
	: >"$BIRD_TEST_EVENTS"
	"$TMP/volume-test.sh" restore >"$TMP/audio-result"
}

# An already-correct speaker route, volume, and mute state must be read-only.
BIRD_TEST_JACK=off; BIRD_TEST_SPEAKER=on
export BIRD_TEST_JACK BIRD_TEST_SPEAKER
run_restore
if grep -Eq ' cset |set-sink-(volume|mute)|^volume ' "$BIRD_TEST_EVENTS"; then
	printf '%s\n' 'correct audio state was rewritten' >&2
	exit 1
fi
grep -Fq 'route=unchanged' "$TMP/audio-result"
grep -Fq 'volume=unchanged' "$TMP/audio-result"

# Audio-bearing content explicitly resumes the sink only while it is muted.
: >"$BIRD_TEST_EVENTS"
"$TMP/volume-test.sh" prepare >"$TMP/audio-result"
PREPARE_WRITES=$(grep -E 'set-sink-mute|suspend-sink' "$BIRD_TEST_EVENTS")
[ "$PREPARE_WRITES" = "pactl -- set-sink-mute @DEFAULT_SINK@ 1
pactl suspend-sink @DEFAULT_SINK@ 0
pactl -- set-sink-mute @DEFAULT_SINK@ 0" ]
grep -Fq 'prewake=ready' "$TMP/audio-result"

# A boot-time headphone mismatch changes only the speaker amplifier. It must
# not wake the suspended PCM sink with a pre-route PulseAudio write.
BIRD_TEST_JACK=on; BIRD_TEST_SPEAKER=on
export BIRD_TEST_JACK BIRD_TEST_SPEAKER
run_restore
[ "$(grep -c ' cset ' "$BIRD_TEST_EVENTS")" -eq 1 ]
if grep -Eq 'set-sink-(volume|mute)|^volume ' "$BIRD_TEST_EVENTS"; then
	printf '%s\n' 'route-only repair woke the PCM sink' >&2
	exit 1
fi
grep -Fq 'route=changed' "$TMP/audio-result"

# Numeric volume and route mute are changed only when they differ.
BIRD_TEST_JACK=off; BIRD_TEST_SPEAKER=on
BIRD_TEST_VOLUME=35; BIRD_TEST_MUTE=yes
export BIRD_TEST_JACK BIRD_TEST_SPEAKER BIRD_TEST_VOLUME BIRD_TEST_MUTE
run_restore
[ "$(grep -c '^volume restore$' "$BIRD_TEST_EVENTS")" -eq 1 ]
[ "$(grep -c 'set-sink-mute @DEFAULT_SINK@ 0' "$BIRD_TEST_EVENTS")" -eq 1 ]
grep -Fq 'volume=changed' "$TMP/audio-result"
grep -Fq 'mute_action=changed' "$TMP/audio-result"

# Unavailable controls are observable but never block unrelated content.
BIRD_TEST_JACK=fail; BIRD_TEST_SPEAKER=fail
BIRD_TEST_VOLUME=50; BIRD_TEST_MUTE=no
export BIRD_TEST_JACK BIRD_TEST_SPEAKER BIRD_TEST_VOLUME BIRD_TEST_MUTE
run_restore
grep -Fq 'route=inspect-failed' "$TMP/audio-result"

# Volume buttons keep their direct accepted path.
: >"$BIRD_TEST_EVENTS"
"$TMP/volume-test.sh" up
[ "$(sed -n '1p' "$BIRD_TEST_EVENTS")" = 'volume up' ]
[ "$(sed -n '2p' "$BIRD_TEST_EVENTS")" = \
	'pactl -- set-sink-mute @DEFAULT_SINK@ 0' ]

# Exercise the exact active MPV migration function in a redirected fixture.
MPV_FUNCTION=$TMP/install-mpv-policy.sh
awk '
	/^install_mpv_input_policy\(\) \{/ { copy=1 }
	/^prepare_fmsx_bios\(\) \{/ { exit }
	copy { print }
' "$RUNNER" | sed \
	-e "s#/flash/bird#$TMP/flash/bird#g" \
	-e "s#/storage#$TMP/storage#g" >"$MPV_FUNCTION"
mkdir -p "$TMP/flash/bird"
printf '%s\n' 'VOLUME_UP ignore' >"$TMP/flash/bird/mpv-input.conf"
cat >"$TMP/storage/.config/mpv/watch_later/AUDIO" <<'EOF'
# audio state
start=12.500000
aid=no
volume=27.000000
speed=1.250000
EOF
cat >"$TMP/storage/.local/state/mpv/watch_later/VIDEO" <<'EOF'
# video state
start=33.000000
sid=2
mute=yes
EOF

. "$MPV_FUNCTION"
install_mpv_input_policy
grep -Eq '^save-position-on-quit=yes$' "$TMP/storage/.config/mpv/mpv.conf"
grep -Eq '^watch-later-options=start$' "$TMP/storage/.config/mpv/mpv.conf"
grep -Eq '^start=12\.500000$' "$TMP/storage/.config/mpv/watch_later/AUDIO"
grep -Eq '^start=33\.000000$' "$TMP/storage/.local/state/mpv/watch_later/VIDEO"
if grep -Eq '^(aid|vid|sid|volume|mute|speed)=' \
	"$TMP/storage/.config/mpv/watch_later/AUDIO" \
	"$TMP/storage/.local/state/mpv/watch_later/VIDEO"; then
	printf '%s\n' 'legacy non-position MPV state survived migration' >&2
	exit 1
fi
[ -e "$TMP/storage/.config/mpv/.bird-watch-later-start-only-v1" ]

printf '%s\n' 'stock-root media/audio policy tests passed'
