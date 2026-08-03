#!/bin/bash
# Host regression coverage for the exact post-frame coordinator sequence.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SCRIPT=$ROOT/kernel/rocknix/stock-root/bird-autostart
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-autostart.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

FLASH=$TMP/flash
AUTOSTART=$TMP/autostart
CUSTOM=$TMP/custom
BIN=$TMP/bin
EVENTS=$TMP/events
BOOTLOG=$TMP/boot.log
LOCK=$TMP/start.games
mkdir -p "$FLASH" "$AUTOSTART/quirks/platforms/H700" \
	"$AUTOSTART/common" "$CUSTOM" "$BIN"
: >"$EVENTS"
: >"$BOOTLOG"

make_step() {
	STEP_PATH=$1
	STEP_NAME=$2
	STEP_STATUS=${3:-0}
	printf '#!/bin/sh\nprintf "%%s\\n" "%s" >>"$BIRD_TEST_EVENTS"\nexit %s\n' \
		"$STEP_NAME" "$STEP_STATUS" >"$STEP_PATH"
	chmod 0755 "$STEP_PATH"
}

make_step "$FLASH/bird-fixed-platform.sh" fixed-platform
make_step "$FLASH/090-ui_service" ui-selection
make_step "$AUTOSTART/quirks/platforms/H700/400-set_gpu_overclock" gpu-overclock
make_step "$AUTOSTART/common/001-controller" controller
make_step "$AUTOSTART/common/001-setup" setup 7
make_step "$AUTOSTART/common/003-logging" logging
make_step "$AUTOSTART/common/008-perfmode" perfmode
make_step "$FLASH/bird-restore-suspend-policy.sh" suspend-policy
make_step "$AUTOSTART/common/010-pico8" pico8
make_step "$AUTOSTART/common/020-rumble" rumble
make_step "$AUTOSTART/common/050-audio" audio
make_step "$AUTOSTART/common/095-turbo-mode" turbo-mode
make_step "$FLASH/bird-fixed-sway.sh" fixed-sway
make_step "$FLASH/999-export" application-ready
make_step "$CUSTOM/010-first" custom-first
make_step "$CUSTOM/020-second" custom-second

printf '#!/bin/sh\nprintf "performance\\n" >>"$BIRD_TEST_EVENTS"\n' \
	>"$BIN/performance"
printf '#!/bin/sh\nprintf "governor\\n" >>"$BIRD_TEST_EVENTS"\n' \
	>"$BIN/test-governor"
printf '#!/bin/sh\nprintf "%%s\\n" "$BIRD_TEST_GOVERNOR"\n' \
	>"$BIN/get_setting"
chmod 0755 "$BIN/performance" "$BIN/test-governor" "$BIN/get_setting"

export BIRD_TEST_EVENTS=$EVENTS
export BIRD_TEST_GOVERNOR=$BIN/test-governor
PATH=$BIN:$PATH \
BIRD_FLASH_ROOT=$FLASH \
BIRD_AUTOSTART_ROOT=$AUTOSTART \
BIRD_CUSTOM_ROOT=$CUSTOM \
BIRD_BOOTLOG=$BOOTLOG \
BIRD_START_GAMES_LOCK=$LOCK \
	"$SCRIPT"

cat >"$TMP/expected" <<'EOF'
performance
fixed-platform
ui-selection
gpu-overclock
controller
setup
logging
perfmode
suspend-policy
pico8
rumble
audio
turbo-mode
fixed-sway
application-ready
custom-first
custom-second
governor
EOF
cmp "$TMP/expected" "$EVENTS"
grep -Fxq 'Bird autostart step failed: setup status=7' "$BOOTLOG"
[ -f "$LOCK" ]

grep -q '^BIRD_AUTOSTART_REVISION=bird-fixed-autostart-v1$' "$SCRIPT"
if grep -Eq 'autostart/(common|quirks)/[*]|(^|[^[:alnum:]_])date([^[:alnum:]_]|$)|tocon|systemctl' \
	"$SCRIPT"; then
	printf '%s\n' 'fixed coordinator regained generic discovery or helpers' >&2
	exit 1
fi

printf '%s\n' 'stock-root fixed autostart tests passed'
