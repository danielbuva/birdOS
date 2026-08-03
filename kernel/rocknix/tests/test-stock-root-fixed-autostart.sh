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
make_step "$FLASH/bird-fixed-gpu-overclock.sh" gpu-overclock
make_step "$FLASH/bird-fixed-controller.sh" controller
make_step "$FLASH/bird-fixed-setup.sh" setup 7
make_step "$FLASH/bird-fixed-logging.sh" logging
printf '#!/bin/sh\nprintf "performance-%%s\\n" "$1" >>"$BIRD_TEST_EVENTS"\n' \
	>"$FLASH/bird-fixed-performance.sh"
chmod 0755 "$FLASH/bird-fixed-performance.sh"
make_step "$FLASH/bird-restore-suspend-policy.sh" suspend-policy
make_step "$FLASH/bird-fixed-pico8.sh" pico8
make_step "$FLASH/bird-fixed-rumble.sh" rumble
make_step "$AUTOSTART/common/050-audio" audio
make_step "$FLASH/bird-fixed-turbo.sh" turbo-mode
make_step "$FLASH/bird-fixed-sway.sh" fixed-sway
make_step "$FLASH/999-export" application-ready
make_step "$FLASH/bird-udev-idle.sh" udev-idle
make_step "$CUSTOM/010-first" custom-first
make_step "$CUSTOM/020-second" custom-second

printf '#!/bin/sh\nprintf "performance\\n" >>"$BIRD_TEST_EVENTS"\n' \
	>"$BIN/performance"
chmod 0755 "$BIN/performance"

export BIRD_TEST_EVENTS=$EVENTS
PATH=$BIN:$PATH \
BIRD_FLASH_ROOT=$FLASH \
BIRD_AUTOSTART_ROOT=$AUTOSTART \
BIRD_CUSTOM_ROOT=$CUSTOM \
BIRD_BOOTLOG=$BOOTLOG \
	"$SCRIPT"

cat >"$TMP/expected" <<'EOF'
performance
fixed-platform
ui-selection
gpu-overclock
controller
setup
logging
performance-prepare
suspend-policy
pico8
rumble
audio
turbo-mode
fixed-sway
application-ready
udev-idle
custom-first
custom-second
performance-governor
EOF
cmp "$TMP/expected" "$EVENTS"
grep -Fxq 'Bird autostart step failed: setup status=7' "$BOOTLOG"
[ ! -e "$TMP/start.games" ]

grep -q '^BIRD_AUTOSTART_REVISION=bird-fixed-autostart-v3$' "$SCRIPT"
if grep -Eq 'autostart/(common|quirks)/[*]|common/001-(controller|setup)|start[.]games|(^|[^[:alnum:]_])date([^[:alnum:]_]|$)|tocon|systemctl' \
	"$SCRIPT"; then
	printf '%s\n' 'fixed coordinator regained generic discovery or helpers' >&2
	exit 1
fi
if grep -Eq 'common/008-perfmode|common/020-rumble|common/095-turbo-mode|400-set_gpu_overclock|get_setting system.cpugovernor' \
	"$SCRIPT"; then
	printf '%s\n' 'generic performance or rumble policy returned' >&2
	exit 1
fi

printf '%s\n' 'stock-root fixed autostart tests passed'
