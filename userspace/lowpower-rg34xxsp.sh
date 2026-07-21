#!/bin/sh
# DANI_FIXED_RG34XXSP_LOWPOWER_V1

CHARGER="/sys/class/power_supply/axp2202-usb/online"
CAPACITY="/sys/class/power_supply/axp2202-battery/capacity"
LOW_LED="/sys/class/power_supply/axp2202-battery/lowpwr_led"
OVERLAY="/run/muos/overlay.battery"
THRESHOLD=25

trap 'printf "%s" 0 >"$LOW_LED" 2>/dev/null || :' 0 1 2 15

while :; do
	ONLINE=0
	LEVEL=
	read -r ONLINE <"$CHARGER" 2>/dev/null || ONLINE=0
	read -r LEVEL <"$CAPACITY" 2>/dev/null || LEVEL=

	case "$LEVEL" in
		'' | *[!0-9]*) ;;
		*)
			if [ "$ONLINE" -eq 0 ] && [ "$LEVEL" -le "$THRESHOLD" ]; then
				: >"$OVERLAY"
				printf '%s' 1 >"$LOW_LED"
				sleep 0.5
				printf '%s' 0 >"$LOW_LED"
			else
				rm -f "$OVERLAY"
			fi
			;;
	esac

	# One fixed check per minute replaces configuration and RGB discovery every
	# thirty seconds while preserving a generous 25 percent warning threshold.
	sleep 60
done
