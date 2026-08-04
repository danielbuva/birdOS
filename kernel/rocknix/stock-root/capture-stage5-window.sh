#!/bin/sh
# Explicit one-shot Stage 5 window. It is independent from the broad boot
# diagnostic so that diagnostic enumeration cannot keep managers busy inside
# the measured interval.

set -eu

REQUEST=${BIRD_STAGE5_REQUEST:-/storage/bird-data/Bird/stage5-idle-window.request}
LOG_DIR=${BIRD_STAGE5_LOG_DIR:-/storage/bird-data/Bird/log}
COUNTERS=${BIRD_STAGE5_COUNTERS:-/flash/bird/capture-stage5-window-counters.sh}
SNAPSHOT=${BIRD_STAGE5_SNAPSHOT:-/flash/bird/capture-stage5-state.sh}
SLEEP=${BIRD_STAGE5_SLEEP:-sleep}
SETTLE_SECONDS=${BIRD_STAGE5_SETTLE_SECONDS:-30}
WINDOW_SECONDS=${BIRD_STAGE5_WINDOW_SECONDS:-60}
BOOT_ID_FILE=${BIRD_STAGE5_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}

STATE=
while IFS='=' read -r KEY VALUE; do
	[ "$KEY" != state ] || STATE=$VALUE
done <"$REQUEST"
case "$STATE" in
	menu-idle|marquee-idle|game-paused|audio-playback|video-playback|external-power-menu-idle) ;;
	*) printf 'invalid Stage 5 state: %s\n' "$STATE" >&2; exit 2 ;;
esac
case "$SETTLE_SECONDS:$WINDOW_SECONDS" in
	*[!0-9:]*|:*|*:) printf '%s\n' 'invalid Stage 5 duration' >&2; exit 2 ;;
esac

IFS= read -r BOOT_ID_FULL <"$BOOT_ID_FILE" || BOOT_ID_FULL=
BOOT_ID=$(printf '%.8s' "$BOOT_ID_FULL")
[ -n "$BOOT_ID" ] || BOOT_ID=unknown
LOG=$LOG_DIR/stage5-window-$BOOT_ID-$STATE.log
LATEST=$LOG_DIR/stage5-window-latest.log
TMP=$LOG.tmp.$$

cleanup() {
	rm -f "$TMP" 2>/dev/null || :
}
trap cleanup EXIT HUP INT TERM

{
	printf 'bird_stage5_acquisition_version=1 state=%s\n' "$STATE"
	printf 'settle_seconds=%s window_seconds=%s\n' \
		"$SETTLE_SECONDS" "$WINDOW_SECONDS"
	"$SLEEP" "$SETTLE_SECONDS"
	"$COUNTERS" start
	"$SLEEP" "$WINDOW_SECONDS"
	"$COUNTERS" end
	BIRD_STAGE5_LABEL=$STATE-final "$SNAPSHOT"
} >"$TMP" 2>&1

mv -f "$TMP" "$LOG"
cp -f "$LOG" "$LATEST"
rm -f "$REQUEST"
sync
trap - EXIT HUP INT TERM
