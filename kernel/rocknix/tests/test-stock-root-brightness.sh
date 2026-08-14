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
UPTIME=$TMP/uptime
ORDER_LOG=$TMP/order.log
mkdir -p "$BACKLIGHT"
printf '2499\n' >"$BACKLIGHT/max_brightness"
printf '0\n' >"$BACKLIGHT/brightness"
printf '4\n' >"$BACKLIGHT/bl_power"
printf '123.45 67.89\n' >"$UPTIME"

# Linux may register the inherited cold-boot backlight as blanked. Early init
# stores the proven ten-percent starting level before unblanking it, without
# replaying the timed resume strike.
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
(
	. "$EARLY_FUNCTION"
	set_early_brightness
) >"$TMP/early.log"
[ "$(cat "$BACKLIGHT/bl_power")" = 0 ]
[ "$(cat "$BACKLIGHT/brightness")" = 250 ]
[ ! -s "$TMP/early.log" ]
! grep -Eq 'STRIKE|usleep' "$EARLY_FUNCTION"
python3 - "$EARLY_FUNCTION" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
brightness = source.index('"$RAW" >"$BACKLIGHT/brightness"')
unblank = source.index('0 >"$BACKLIGHT/bl_power"')
if brightness >= unblank:
    raise SystemExit("cold backlight was unblanked before target storage")
if source.count('>"$BACKLIGHT/brightness"') != 1:
    raise SystemExit("cold brightness must be written exactly once")
PY
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
	BIRD_SUSPEND_UPTIME=$UPTIME \
	BIRD_TEST_ORDER_LOG=$ORDER_LOG \
	BIRD_TEST_SETTLE_LOG=$SETTLE_LOG \
		"$SOURCE" lid "$1"
}

printf '%s\n' \
	'#!/bin/sh' \
	'case "$2" in' \
	'  close) printf "4\n" >"$BIRD_BACKLIGHT/bl_power"; printf "0\n" >"$BIRD_BACKLIGHT/brightness" ;;' \
	'  open) printf "0\n" >"$BIRD_BACKLIGHT/bl_power"; printf "0\n" >"$BIRD_BACKLIGHT/brightness" ;;' \
	'esac' \
	'printf "provider-return\n" >>"$BIRD_TEST_ORDER_LOG"' >"$PROVIDER"
printf '%s\n' \
	'#!/bin/sh' \
	'printf "%s:%s\n" "$1" "$(cat "$BIRD_BACKLIGHT/brightness")" >>"$BIRD_TEST_SETTLE_LOG"' >"$SETTLE"
chmod 0755 "$PROVIDER" "$SETTLE"

printf '25\n' >"$BACKLIGHT/brightness"
: >"$ORDER_LOG"
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
grep -q 'stage=provider-return raw=0 bl_power=0 boottime_s=123.45' "$LOG"
[ "$(grep -c 'boottime_s=123.45' "$LOG")" -eq 5 ]
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
snapshot = source.index('snapshot_brightness\n\tPROVIDER_RAW=$RAW')
restore = source.index('log_brightness restored', snapshot)
ready = source.index(': >"$RESUME_READY"', restore)
emit = source.index('emit_brightness provider-return', ready)
if not snapshot < restore < ready < emit:
    raise SystemExit("provider-return evidence entered the restore/ready path")
PY

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
