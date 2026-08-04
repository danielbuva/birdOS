#!/bin/sh
# Observe the inherited fixed-panel state without writing it. Bird already
# painted and may already have accepted a manual brightness input; no later
# compatibility job is allowed to reset that visible state.

set -u

BACKLIGHT=/sys/class/backlight/backlight
LOG=/storage/bird-data/Bird/log/first-frame-prep-latest.log

{
	printf 'Bird first-frame preparation start uptime='
	cut -d ' ' -f 1 /proc/uptime
	if [ -r "$BACKLIGHT/max_brightness" ] && \
		[ -r "$BACKLIGHT/brightness" ]; then
		MAX=$(cat "$BACKLIGHT/max_brightness")
		RAW=$(cat "$BACKLIGHT/brightness")
		printf 'brightness_write=none raw=%s max=%s\n' "$RAW" "$MAX"
	else
		printf 'brightness_device_not_ready=%s\n' "$BACKLIGHT"
	fi
	printf 'Bird first-frame preparation ready uptime='
	cut -d ' ' -f 1 /proc/uptime
} >"$LOG" 2>&1
