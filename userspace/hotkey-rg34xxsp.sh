#!/bin/sh
# DANI_FIXED_RG34XXSP_HOTKEY_V1

RUN_DIR="/run/muos"
FIFO="$RUN_DIR/hotkey"
IS_IDLE="$RUN_DIR/is_idle"
IDLE_STATE="$RUN_DIR/idle_state"
HALL="/sys/class/power_supply/axp2202-battery/hallkey"
BRIGHTNESS="/opt/muos/config/settings/general/brightness"
RESUME_UPTIME="/opt/muos/config/system/resume_uptime"

mkdir -p "$RUN_DIR"
[ -p "$FIFO" ] || mkfifo "$FIFO"

display_set() {
	printf '%s' disp0 >/sys/kernel/debug/dispdbg/name
	printf '%s' setbl >/sys/kernel/debug/dispdbg/command
	printf '%s' "$1" >/sys/kernel/debug/dispdbg/param
	echo 1 >/sys/kernel/debug/dispdbg/start
}

display_idle() {
	[ ! -e "$IS_IDLE" ] || return 0
	amixer set Master mute >/dev/null 2>&1
	display_set 10
	: >"$IS_IDLE"
}

display_active() {
	[ -e "$IS_IDLE" ] || return 0
	amixer set Master unmute >/dev/null 2>&1
	VALUE=35
	read -r VALUE <"$BRIGHTNESS" 2>/dev/null || VALUE=35
	display_set "$VALUE"
	printf '%s' 0 >"$IDLE_STATE"
	rm -f "$IS_IDLE"
}

lid_closed() {
	VALUE=1
	read -r VALUE <"$HALL" 2>/dev/null || return 1
	[ "$VALUE" -eq 0 ]
}

suspend_device() {
	read -r NOW _ </proc/uptime
	NOW=${NOW%%.*}
	LAST=0
	read -r LAST <"$RESUME_UPTIME" 2>/dev/null || LAST=0
	LAST=${LAST%%.*}
	[ $((NOW - LAST)) -gt 5 ] || return 0
	printf '%s' "$NOW" >"$RESUME_UPTIME"
	/opt/muos/script/system/suspend.sh
}

while :; do
	/opt/muos/frontend/muhotkey >"$FIFO" &
	MU_PID=$!

	while IFS= read -r HOTKEY <"$FIFO"; do
		# Charge mode and a physically closed lid own the device exclusively.
		pgrep -x muxcharge >/dev/null 2>&1 && continue
		lid_closed && continue

		case "$HOTKEY" in
			IDLE_ACTIVE) display_active ;;
			IDLE_DISPLAY) display_idle ;;
			# Personal idle-sleep is disabled; explicit power shortcuts remain.
			IDLE_SLEEP) : ;;
			SLEEP_SHORT | SLEEP_LONG) suspend_device ;;
		esac
	done

	wait "$MU_PID" 2>/dev/null
	sleep 0.1
done
