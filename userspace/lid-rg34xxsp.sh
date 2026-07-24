#!/bin/sh
# BIRD_FIXED_RG34XXSP_LID_V1

RUN_DIR="/run/muos"
QUIT="$RUN_DIR/quit_lid_proc"
PID_FILE="$RUN_DIR/lid.pid"
HALL="/sys/class/power_supply/axp2202-battery/hallkey"

is_running() {
	[ -f "$PID_FILE" ] || return 1
	PID=
	read -r PID <"$PID_FILE" 2>/dev/null || return 1
	[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null
}

case "${1:-start}" in
	start)
		is_running && exit 0
		rm -f "$PID_FILE"
		setsid -f "$0" run </dev/null >/dev/null 2>&1
		exit 0
		;;
	run)
		printf '%s\n' "$$" >"$PID_FILE"
		trap 'rm -f "$PID_FILE"' 0 1 2 15
		[ -r "$HALL" ] || exit 0

		STATE=1
		read -r STATE <"$HALL" 2>/dev/null || STATE=1
		LAST=$STATE
		while [ ! -e "$QUIT" ]; do
			STATE=1
			read -r STATE <"$HALL" 2>/dev/null || STATE=1
			if [ "$STATE" -eq 0 ] && [ "$LAST" -eq 1 ]; then
				/opt/muos/script/system/suspend.sh
			fi
			LAST=$STATE
			sleep 1
		done
		;;
	*)
		printf 'Usage: %s {start | run}\n' "$0" >&2
		exit 1
		;;
esac
