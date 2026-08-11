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
RESUME_READY=$TMP/run/resume-ready
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
start = source.index("set_early_brightness() {")
end = source.index("\n}\n\ncase ", start) + 2
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
sh -n "$EARLY_FUNCTION"
EARLY_BUSYBOX=$TMP/early-busybox.sh
EARLY_SETTLE_LOG=$TMP/early-settle.log
EARLY_BUSYBOX_CALLS=$TMP/early-busybox.calls
cat >"$EARLY_BUSYBOX" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >>"$BIRD_TEST_BUSYBOX_CALLS"
case "$1" in
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
	BIRD_TEST_BUSYBOX_CALLS=$EARLY_BUSYBOX_CALLS
	export BIRD_TEST_BACKLIGHT BIRD_TEST_SETTLE_LOG BIRD_TEST_BUSYBOX_CALLS
	set_early_brightness
) >"$TMP/early.log"
[ "$(cat "$BACKLIGHT/bl_power")" = 0 ]
[ "$(cat "$BACKLIGHT/brightness")" = 124 ]
[ "$(cat "$EARLY_SETTLE_LOG")" = 50000:250 ]
[ "$(cat "$EARLY_BUSYBOX_CALLS")" = usleep ]
[ ! -s "$TMP/early.log" ]
grep -Fq 'IFS= read -r MAX <"$BACKLIGHT/max_brightness"' "$EARLY_SOURCE"
! grep -Fq '$BUSYBOX cat "$BACKLIGHT/max_brightness"' "$EARLY_SOURCE"

# Normal start must dispatch the launcher without probing diagnostic LEDs.
# LED inspection and verbose uptime evidence remain failure-only.
! grep -q 'Bird early-init start uptime' "$EARLY_SOURCE"
! grep -q 'log_leds start' "$EARLY_SOURCE"
! grep -q 'early_storage_fifo=%s' "$EARLY_SOURCE"
! grep -q 'early_input_module=loaded' "$EARLY_SOURCE"
grep -Fq "'early_storage_fifo=failed'" "$EARLY_SOURCE"
grep -Fq "'early_input_module=failed'" "$EARLY_SOURCE"
! grep -q 'log_leds root-ready' "$EARLY_SOURCE"
! grep -Eq 'log_leds handoff([[:space:]]|$)' "$EARLY_SOURCE"
[ "$(grep -c 'log_leds root-timeout' "$EARLY_SOURCE")" = 1 ]
[ "$(grep -c 'log_leds handoff-missing' "$EARLY_SOURCE")" = 1 ]
grep -Fq 'storage-failed)' "$EARLY_SOURCE"
grep -Fq 'shutdown_countdown_s=3' "$EARLY_SOURCE"
grep -Fq '$BUSYBOX poweroff -f' "$EARLY_SOURCE"
grep -Fq '$BUSYBOX sync' "$EARLY_SOURCE"
[ "$(grep -c '\$BUSYBOX poweroff -f' "$EARLY_SOURCE")" = 1 ]
! grep -q 'final-root storage signalled' "$EARLY_SOURCE"
! grep -q 'storage anchor acknowledged' "$EARLY_SOURCE"
! grep -q 'persistent-owner uptime' "$EARLY_SOURCE"
# Additional reads exist only inside the storage-failure shutdown recorder.
[ "$(grep -c '/proc/uptime' "$EARLY_SOURCE")" = 4 ]

printf '0\n' >"$BACKLIGHT/bl_power"

apply_suspend() {
	BIRD_BACKLIGHT=$BACKLIGHT \
	BIRD_SUSPEND_STATE=$STATE \
	BIRD_SUSPEND_LOG=$LOG \
	BIRD_SUSPEND_PROVIDER=$PROVIDER \
	BIRD_SUSPEND_SETTLE=$SETTLE \
	BIRD_SUSPEND_RESUME_READY=$RESUME_READY \
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
[ -e "$RESUME_READY" ]
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
[ -e "$RESUME_READY" ]
[ "$(cat "$BACKLIGHT/brightness")" = 25 ]
[ "$(cat "$BACKLIGHT/bl_power")" = 0 ]
[ "$(cat "$SETTLE_LOG")" = 50000:250 ]

sh -n "$SOURCE"
printf '%s\n' 'stock-root brightness tests: PASS'
