#!/bin/sh
set -eu

ROM_MOUNT=/mnt/mmc
WORK_DIR="$ROM_MOUNT/.firmware-work"
MARKER="$WORK_DIR/mainline-diagnostic-installed"
EXPECTED_SHA=8b9ba42467b9879b94a7f61241fc5065c31206b71da1f29c21c6c13e993f9078
EXPECTED_RELEASE=7.0.11-dani-compat

[ -f "$MARKER" ] || exit 0
[ "$(cat "$MARKER")" = "$EXPECTED_SHA" ] || exit 0
[ "$(uname -r)" = "$EXPECTED_RELEASE" ] || exit 0

BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)
RESULT="$ROM_MOUNT/MUOS/boot-timing/mainline-diagnostic/$BOOT_ID"
mkdir -p "$RESULT"

capture() {
	NAME=$1
	shift
	"$@" >"$RESULT/$NAME" 2>&1 || \
		printf 'command failed: %s\n' "$*" >>"$RESULT/$NAME"
}

capture uname.txt uname -a
capture cmdline.txt cat /proc/cmdline
capture uptime.txt cat /proc/uptime
capture dmesg.txt dmesg
capture mounts.txt cat /proc/mounts
capture partitions.txt cat /proc/partitions
capture devices.txt find /dev -maxdepth 2 -type b -o -type c
capture leds.txt find /sys/class/leds -maxdepth 2 -type f -print
capture framebuffer.txt sh -c 'ls -l /dev/fb* /sys/class/graphics 2>&1'
capture drm.txt sh -c 'find /sys/class/drm -maxdepth 2 -print 2>&1'
capture input.txt sh -c 'cat /proc/bus/input/devices; ls -l /dev/input 2>&1'
capture backlight.txt sh -c 'find /sys/class/backlight -maxdepth 2 -print 2>&1'
sync
