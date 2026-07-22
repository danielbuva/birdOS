#!/bin/sh
# Preserve muOS's R/U/D/numeric brightness interface while writing the
# standard mainline backlight class used by the RG34XX-SP panel driver.

. /opt/muos/script/var/func.sh

BACKLIGHT=/sys/class/backlight/backlight
REQUEST=${1-}

[ -w "$BACKLIGHT/brightness" ] || exit 1
[ -n "$REQUEST" ] || exit 0

DEVICE_MODE=$(GET_VAR "config" "boot/device_mode")
[ -n "$DEVICE_MODE" ] && [ "$DEVICE_MODE" -ne 0 ] && exit 0

CURRENT=$(GET_VAR "config" "settings/general/brightness")
INCREMENT=$(GET_VAR "config" "settings/advanced/incbright")
DEVICE_MAX=$(GET_VAR "device" "screen/bright")
case "$DEVICE_MAX" in '' | *[!0-9]*) DEVICE_MAX=255 ;; esac
case "$CURRENT" in '' | *[!0-9]*) CURRENT=1 ;; esac
case "$INCREMENT" in '' | *[!0-9]*) INCREMENT=16 ;; esac
[ "$DEVICE_MAX" -gt 0 ] 2>/dev/null || DEVICE_MAX=255
[ "$INCREMENT" -gt 0 ] 2>/dev/null || INCREMENT=16

case "$REQUEST" in
	R | F) LEVEL=$CURRENT ;;
	U) LEVEL=$((CURRENT + INCREMENT)) ;;
	D) LEVEL=$((CURRENT - INCREMENT)) ;;
	*[!0-9]*) exit 0 ;;
	*) LEVEL=$REQUEST ;;
esac

MAX=255
IFS= read -r MAX <"$BACKLIGHT/max_brightness" 2>/dev/null || MAX=255
[ "$MAX" -gt 0 ] 2>/dev/null || MAX=255

[ "$LEVEL" -lt 1 ] && LEVEL=1
[ "$LEVEL" -gt "$DEVICE_MAX" ] && LEVEL=$DEVICE_MAX
RAW=$(((LEVEL * MAX + (DEVICE_MAX / 2)) / DEVICE_MAX))
[ "$RAW" -lt 1 ] && RAW=1
printf '%s\n' "$RAW" >"$BACKLIGHT/brightness"
SET_VAR "config" "settings/general/brightness" "$LEVEL"
