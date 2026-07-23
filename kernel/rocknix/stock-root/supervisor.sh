#!/bin/bash
# Bird stays a small UI process. ROCKNIX owns all hardware, service and content
# setup; this supervisor only exchanges the launch request and redraws Bird.

set -u

LAUNCHER=/storage/.config/bird/dani-launcher
RUNNER=/storage/.config/bird/run-content.sh
REQUEST=/run/muos/dani-launch-request
FIRST_FRAME=/run/muos/dani-first-frame-ready
ATTEMPTS=/storage/bird-data/MUOS/Bird/boot-state/stock-root-attempts
LOG_DIR=/storage/bird-data/MUOS/Bird/log
LOG=$LOG_DIR/stock-root-supervisor.log

mkdir -p /run/muos "$LOG_DIR" "${ATTEMPTS%/*}"
exec >>"$LOG" 2>&1

mark_healthy() {
	for _ in $(seq 1 250); do
		if [ -e "$FIRST_FRAME" ]; then
			printf '0\n' >"$ATTEMPTS"
			sync "$ATTEMPTS"
			printf 'bird stock-root first frame uptime='
			cut -d ' ' -f 1 /proc/uptime
			return 0
		fi
		usleep 20000
	done
	printf 'bird stock-root first-frame timeout uptime='
	cut -d ' ' -f 1 /proc/uptime
	return 1
}

while :; do
	rm -f "$FIRST_FRAME"
	"$LAUNCHER" &
	LAUNCHER_PID=$!
	mark_healthy || systemctl reboot --force
	wait "$LAUNCHER_PID"
	RESULT=$?
	printf 'bird launcher result=%s uptime=' "$RESULT"
	cut -d ' ' -f 1 /proc/uptime
	case "$RESULT" in
		10) "$RUNNER" "$REQUEST" ;;
		11) systemctl poweroff ; exit 0 ;;
		12) "$RUNNER" --portmaster ;;
		*) usleep 50000 ;;
	esac
done
