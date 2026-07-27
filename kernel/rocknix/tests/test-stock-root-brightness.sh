#!/bin/sh
# Host regression for low-end brightness preservation across the retained
# ROCKNIX fake-suspend provider.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SOURCE=$ROOT/kernel/rocknix/stock-root/bird-suspend.sh
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
