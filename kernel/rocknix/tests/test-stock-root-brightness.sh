#!/bin/sh
# Host regression for low-end brightness preservation across the retained
# ROCKNIX fake-suspend provider.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SOURCE=$ROOT/kernel/rocknix/stock-root/bird-suspend.sh
EARLY_SOURCE=$ROOT/kernel/rocknix/stock-root/bird-early.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-brightness.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

BACKLIGHT=$TMP/backlight
STATE=$TMP/state/pre-suspend
LOG=$TMP/suspend.log
PROVIDER=$TMP/provider.sh
SETTLE=$TMP/settle.sh
SETTLE_LOG=$TMP/settle.log
mkdir -p "$BACKLIGHT"
printf '2499\n' >"$BACKLIGHT/max_brightness"
printf '4\n' >"$BACKLIGHT/bl_power"

# Cold boot uses the same measured wake contract as resume: unblank, hold a
# ten-percent strike for 50 ms, then restore the accepted five-percent level.
EARLY_FUNCTION=$TMP/early-brightness-function.sh
python3 - "$EARLY_SOURCE" "$EARLY_FUNCTION" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("trace_early() {")
end = source.index("\n}\n\ncase ", start) + 2
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
sh -n "$EARLY_FUNCTION"
[ "$(
	. "$EARLY_FUNCTION"
	EARLY_TRACE=0
	BUSYBOX=/forbidden-busybox
	trace_early 'forbidden diagnostic\n'
	trace_leds start
)" = '' ]
grep -Fq '$BUSYBOX dmesg | $BUSYBOX tail -n 30' "$EARLY_SOURCE"
EARLY_BUSYBOX=$TMP/early-busybox.sh
EARLY_SETTLE_LOG=$TMP/early-settle.log
cat >"$EARLY_BUSYBOX" <<'EOF'
#!/bin/sh
case "$1" in
	cat) shift; exec cat "$@" ;;
	usleep)
		printf '%s:%s\n' "$2" "$(cat "$BIRD_TEST_BACKLIGHT/brightness")" \
			>>"$BIRD_TEST_SETTLE_LOG"
		;;
	*) exit 1 ;;
esac
EOF
chmod 0755 "$EARLY_BUSYBOX"
(
	. "$EARLY_FUNCTION"
	BUSYBOX=$EARLY_BUSYBOX
	BIRD_TEST_BACKLIGHT=$BACKLIGHT
	BIRD_TEST_SETTLE_LOG=$EARLY_SETTLE_LOG
	export BIRD_TEST_BACKLIGHT BIRD_TEST_SETTLE_LOG
	EARLY_TRACE=0
	set_early_brightness
) >"$TMP/early.log"
[ "$(cat "$BACKLIGHT/bl_power")" = 0 ]
[ "$(cat "$BACKLIGHT/brightness")" = 124 ]
[ "$(cat "$EARLY_SETTLE_LOG")" = 50000:250 ]
[ ! -s "$TMP/early.log" ]

# Trace builds retain the same post-hoc brightness evidence without making
# normal release boot issue diagnostic writes before the usable frame.
printf '4\n' >"$BACKLIGHT/bl_power"
: >"$EARLY_SETTLE_LOG"
(
	. "$EARLY_FUNCTION"
	BUSYBOX=$EARLY_BUSYBOX
	BIRD_TEST_BACKLIGHT=$BACKLIGHT
	BIRD_TEST_SETTLE_LOG=$EARLY_SETTLE_LOG
	export BIRD_TEST_BACKLIGHT BIRD_TEST_SETTLE_LOG
	EARLY_TRACE=1
	set_early_brightness
) >"$TMP/early-trace.log"
[ "$(cat "$BACKLIGHT/bl_power")" = 0 ]
[ "$(cat "$BACKLIGHT/brightness")" = 124 ]
[ "$(cat "$EARLY_SETTLE_LOG")" = 50000:250 ]
grep -q 'stage=wake-strike raw=250 max=2499' "$TMP/early-trace.log"
grep -q 'stage=restored raw=124 max=2499' "$TMP/early-trace.log"

printf '0\n' >"$BACKLIGHT/bl_power"

apply_suspend() {
	BIRD_BACKLIGHT=$BACKLIGHT \
	BIRD_SUSPEND_STATE=$STATE \
	BIRD_SUSPEND_LOG=$LOG \
	BIRD_SUSPEND_PROVIDER=$PROVIDER \
	BIRD_SUSPEND_SETTLE=$SETTLE \
	BIRD_TEST_SETTLE_LOG=$SETTLE_LOG \
		"$SOURCE" lid "$1"
}

printf '%s\n' \
	'#!/bin/sh' \
	'case "$2" in' \
	'  close) printf "4\n" >"$BIRD_BACKLIGHT/bl_power"; printf "0\n" >"$BIRD_BACKLIGHT/brightness" ;;' \
	'  open) printf "0\n" >"$BIRD_BACKLIGHT/bl_power"; printf "0\n" >"$BIRD_BACKLIGHT/brightness" ;;' \
	'esac' >"$PROVIDER"
printf '%s\n' \
	'#!/bin/sh' \
	'printf "%s:%s\n" "$1" "$(cat "$BIRD_BACKLIGHT/brightness")" >>"$BIRD_TEST_SETTLE_LOG"' >"$SETTLE"
chmod 0755 "$PROVIDER" "$SETTLE"

printf '25\n' >"$BACKLIGHT/brightness"
apply_suspend close
[ "$(cat "$STATE")" = 25 ]
[ "$(cat "$BACKLIGHT/brightness")" = 0 ]
[ "$(cat "$BACKLIGHT/bl_power")" = 4 ]
apply_suspend open
[ ! -e "$STATE" ]
[ "$(cat "$BACKLIGHT/brightness")" = 25 ]
[ "$(cat "$BACKLIGHT/bl_power")" = 0 ]
[ "$(cat "$SETTLE_LOG")" = 50000:250 ]
grep -q 'stage=wake-strike raw=250 bl_power=0' "$LOG"
grep -q 'stage=restored raw=25 bl_power=0' "$LOG"

# If close observes the display-off sentinel, never persist zero as the wake
# target. The stable one-percent floor for max 2499 is raw 25.
: >"$SETTLE_LOG"
printf '0\n' >"$BACKLIGHT/brightness"
printf '0\n' >"$BACKLIGHT/bl_power"
apply_suspend close
[ "$(cat "$STATE")" = 25 ]
apply_suspend open
[ "$(cat "$BACKLIGHT/brightness")" = 25 ]
[ "$(cat "$BACKLIGHT/bl_power")" = 0 ]
[ "$(cat "$SETTLE_LOG")" = 50000:250 ]

sh -n "$SOURCE"
printf '%s\n' 'stock-root brightness tests: PASS'
