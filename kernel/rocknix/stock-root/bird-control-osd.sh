#!/bin/sh
# Restore ROCKNIX's lightweight control notification without retaining its
# generic evtest/input_sense process. Notifications are meaningful only while
# the on-demand Sway application session exists.

[ -n "$(pgrep -x sway 2>/dev/null)" ] || exit 0

case "${1:-}" in
	volume)
		. /etc/profile.d/001-functions
		VALUE=$(get_setting audio.volume)
		case "$VALUE" in ''|*[!0-9]*) exit 0 ;; esac
		/usr/bin/mako-notify "Volume: $VALUE%" -no-es
		;;
	brightness)
		CURRENT=/sys/class/backlight/backlight/brightness
		MAXIMUM=/sys/class/backlight/backlight/max_brightness
		[ -r "$CURRENT" ] && [ -r "$MAXIMUM" ] || exit 0
		IFS= read -r RAW <"$CURRENT"
		IFS= read -r MAX <"$MAXIMUM"
		case "$RAW:$MAX" in *[!0-9:]*) exit 0 ;; esac
		[ "$MAX" -gt 0 ] || exit 0
		VALUE=$(((RAW * 100 + MAX / 2) / MAX))
		[ "$VALUE" -gt 0 ] || VALUE=1
		/usr/bin/mako-notify "Brightness: $VALUE%" -no-es
		;;
esac
