#!/bin/sh
# Host-side checks for fixed audio routing and MPV position-only resume state.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
VOLUME=$ROOT/kernel/rocknix/stock-root/bird-volume.sh
RUNNER=$ROOT/kernel/rocknix/stock-root/run-content.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-media-audio.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

mkdir -p "$TMP/bin" "$TMP/storage/.config/mpv/watch_later" \
	"$TMP/storage/.local/state/mpv/watch_later"

cat >"$TMP/bin/volume" <<'EOF'
#!/bin/sh
printf 'volume %s\n' "$*" >>"$BIRD_TEST_EVENTS"
EOF
cat >"$TMP/bin/pactl" <<'EOF'
#!/bin/sh
printf 'pactl %s\n' "$*" >>"$BIRD_TEST_EVENTS"
EOF
cat >"$TMP/bin/amixer" <<'EOF'
#!/bin/sh
printf 'amixer %s\n' "$*" >>"$BIRD_TEST_EVENTS"
case "$*" in
	*"cget name='Headphone Jack'"*) printf '  : values=%s\n' "$BIRD_TEST_JACK" ;;
esac
EOF
chmod 0755 "$TMP/bin/volume" "$TMP/bin/pactl" "$TMP/bin/amixer"

# Execute the exact policy with only absolute executable paths redirected.
sed -e "s#/usr/bin/volume#$TMP/bin/volume#" \
	-e "s#pactl --#$TMP/bin/pactl --#" \
	-e "s#/usr/bin/amixer#$TMP/bin/amixer#" "$VOLUME" >"$TMP/volume-test.sh"
chmod 0755 "$TMP/volume-test.sh"
export BIRD_TEST_EVENTS=$TMP/audio-events

: >"$BIRD_TEST_EVENTS"
BIRD_TEST_JACK=on; export BIRD_TEST_JACK
"$TMP/volume-test.sh" restore
grep -Fq "amixer -q -c 0 cset name='Speaker Switch' off" "$BIRD_TEST_EVENTS"

: >"$BIRD_TEST_EVENTS"
BIRD_TEST_JACK=off; export BIRD_TEST_JACK
"$TMP/volume-test.sh" restore
grep -Fq "amixer -q -c 0 cset name='Speaker Switch' on" "$BIRD_TEST_EVENTS"

: >"$BIRD_TEST_EVENTS"
BIRD_TEST_JACK=unknown; export BIRD_TEST_JACK
if "$TMP/volume-test.sh" restore; then
	printf '%s\n' 'unknown headphone state was accepted' >&2
	exit 1
fi

# Extract the active MPV policy function and redirect its fixed roots into the
# host fixture.  This exercises the migration rather than a reimplementation.
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

# The marker makes later launches O(1) and preserves newly written position
# state without rescanning the directory.
printf '%s\n' 'aid=no' >>"$TMP/storage/.config/mpv/watch_later/AUDIO"
install_mpv_input_policy
grep -Eq '^aid=no$' "$TMP/storage/.config/mpv/watch_later/AUDIO"

printf '%s\n' 'stock-root media/audio policy tests passed'
