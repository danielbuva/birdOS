#!/bin/bash
# Apply the persisted fixed-panel brightness before Bird paints. The stock
# display setup later repeats the same value, so no asynchronous brightness
# transition is visible over the menu.

set -u

CONFIG=/storage/.config/system/configs/system.cfg
BACKLIGHT=/sys/class/backlight/backlight
LOG=/storage/bird-data/MUOS/Bird/log/first-frame-prep-latest.log
PERCENT=$(awk -F= '$1 == "display.brightness" {print $2; exit}' "$CONFIG" 2>/dev/null)

case "$PERCENT" in
	''|*[!0-9]*) PERCENT=5 ;;
esac
[ "$PERCENT" -gt 100 ] && PERCENT=100
[ "$PERCENT" -lt 1 ] && PERCENT=1

for _ in $(seq 1 500); do
	[ -r "$BACKLIGHT/max_brightness" ] && \
		[ -w "$BACKLIGHT/brightness" ] && break
	usleep 1000
done

{
	printf 'Bird first-frame preparation start uptime='
	cut -d ' ' -f 1 /proc/uptime
	if [ -r "$BACKLIGHT/max_brightness" ] && \
		[ -w "$BACKLIGHT/brightness" ]; then
		MAX=$(cat "$BACKLIGHT/max_brightness")
		# Match the exact ROCKNIX brightness helper's integer truncation so its
		# later compatibility pass writes the identical raw value.
		RAW=$((PERCENT * MAX / 100))
		[ "$RAW" -lt 1 ] && RAW=1
		printf '%s\n' "$RAW" >"$BACKLIGHT/brightness"
		printf 'brightness_percent=%s raw=%s max=%s\n' \
			"$PERCENT" "$RAW" "$MAX"
	else
		printf 'brightness_device_not_ready=%s\n' "$BACKLIGHT"
	fi
	printf 'Bird first-frame preparation ready uptime='
	cut -d ' ' -f 1 /proc/uptime
} >"$LOG" 2>&1
