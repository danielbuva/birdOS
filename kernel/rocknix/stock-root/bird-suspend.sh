#!/bin/sh
# Preserve Bird's exact fixed-panel level around ROCKNIX's retained fake
# suspend transaction. The provider owns audio, input, governors and LEDs;
# this wrapper narrows the display contract to one RG34XX-SP backlight.

BACKLIGHT=/sys/class/backlight/backlight
BRIGHTNESS=$BACKLIGHT/brightness
BL_POWER=$BACKLIGHT/bl_power
STATE=/run/muos/bird-pre-suspend-brightness
STOCK=/usr/bin/rocknix-fake-suspend
LOG=/storage/bird-data/MUOS/Bird/log/suspend-latest.log

log_brightness() {
	RAW=unavailable
	POWER=unavailable
	if [ -r "$BRIGHTNESS" ]; then
		IFS= read -r RAW <"$BRIGHTNESS"
	fi
	if [ -r "$BL_POWER" ]; then
		IFS= read -r POWER <"$BL_POWER"
	fi
	printf 'bird-suspend stage=%s raw=%s bl_power=%s\n' "$1" "$RAW" "$POWER"
	printf 'bird-suspend stage=%s raw=%s bl_power=%s\n' \
		"$1" "$RAW" "$POWER" >>"$LOG"
}

is_resume() {
	[ "${1:-}" = lid ] && [ "${2:-}" = open ] && return 0
	[ "${1:-}" = power ] && \
		[ -e /var/run/power-fake-suspend-active.flag ] && return 0
	return 1
}

mkdir -p "${LOG%/*}"
if is_resume "${1:-}" "${2:-}"; then
	SAVED=
	[ -r "$STATE" ] && IFS= read -r SAVED <"$STATE"
	log_brightness resume-request
	# The retained provider kills every rocknix-fake-suspend process as the final
	# resume action, including this child. The wrapper survives that expected
	# signal and restores the exact pre-suspend raw level afterward.
	"$STOCK" "$@" || :
	case "$SAVED" in
		''|*[!0-9]*) ;;
		*)
			[ -w "$BL_POWER" ] && printf '0\n' >"$BL_POWER"
			[ -w "$BRIGHTNESS" ] && printf '%s\n' "$SAVED" >"$BRIGHTNESS"
			;;
	esac
	rm -f "$STATE"
	log_brightness restored
	exit 0
fi

: >"$LOG"
if [ -r "$BRIGHTNESS" ]; then
	IFS= read -r SAVED <"$BRIGHTNESS"
	case "$SAVED" in
		''|*[!0-9]*) ;;
		*)
			mkdir -p "${STATE%/*}"
			printf '%s\n' "$SAVED" >"$STATE"
			;;
	esac
fi
log_brightness saved
exec "$STOCK" "$@"
