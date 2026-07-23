#!/bin/bash
# Bird stays a small UI process. ROCKNIX owns all hardware, service and content
# setup; this supervisor only exchanges the launch request and redraws Bird.

set -u

LAUNCHER=/storage/.config/bird/dani-launcher
RUNNER=/storage/.config/bird/run-content.sh
REQUEST=/run/muos/dani-launch-request
FIRST_FRAME=/run/muos/dani-first-frame-ready
HANDOFF_ACTION=/run/muos/dani-launch-action
EARLY_LOG=/run/muos/initramfs-launcher.log
BRIDGE_LOG=/run/muos/initramfs-bridge.log
BRIDGE_PID=/run/muos/initramfs-bridge.pid
BRIDGE_BINARY=/run/muos/dani-launcher-bridge
ATTEMPTS=/storage/bird-data/MUOS/Bird/boot-state/stock-root-attempts
LOG_DIR=/storage/bird-data/MUOS/Bird/log
LOG=$LOG_DIR/stock-root-supervisor.log

mkdir -p /run/muos "$LOG_DIR" "${ATTEMPTS%/*}"
exec >>"$LOG" 2>&1

accept_early_frame() {
	[ -e "$FIRST_FRAME" ] || return 0
	printf '0\n' >"$ATTEMPTS"
	sync "$ATTEMPTS"
	[ -f "$EARLY_LOG" ] && \
		cp -f "$EARLY_LOG" "$LOG_DIR/early-initramfs-latest.log"
	printf 'bird accepted initramfs first frame uptime='
	cut -d ' ' -f 1 /proc/uptime
}

dispatch_handoff_action() {
	[ -s "$HANDOFF_ACTION" ] || return 0
	ACTION=$(cat "$HANDOFF_ACTION")
	printf 'bird initramfs handoff action=%s uptime=' "$ACTION"
	cut -d ' ' -f 1 /proc/uptime
	case "$ACTION" in
		10) "$RUNNER" "$REQUEST"; rm -f "$HANDOFF_ACTION" ;;
		11) rm -f "$HANDOFF_ACTION"; systemctl poweroff; exit 0 ;;
		12) "$RUNNER" --portmaster; rm -f "$HANDOFF_ACTION" ;;
		*) rm -f "$HANDOFF_ACTION" ;;
	esac
}

retire_root_bridge() {
	if [ -s "$BRIDGE_PID" ]; then
		PID=$(cat "$BRIDGE_PID")
		case "$PID" in *[!0-9]*|'') PID= ;; esac
		if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
			EXE=$(readlink "/proc/$PID/exe" 2>/dev/null || :)
			case "$EXE" in
				*/dani-launcher-bridge)
					printf 'bird retiring root bridge pid=%s uptime=' "$PID"
					cut -d ' ' -f 1 /proc/uptime
					kill "$PID" 2>/dev/null || :
					for _ in $(seq 1 100); do
						kill -0 "$PID" 2>/dev/null || break
						usleep 1000
					done
					;;
				*) printf 'bird ignored stale bridge pid=%s exe=%s\n' "$PID" "$EXE" ;;
			esac
		fi
	fi
	[ -f "$BRIDGE_LOG" ] && cp -f "$BRIDGE_LOG" "$LOG_DIR/root-bridge-latest.log"
	rm -f "$BRIDGE_PID" "$BRIDGE_BINARY"
}

mark_healthy() {
	# The early launcher intentionally races udev. Keep the menu visible while
	# allowing the fixed H700 input node the launcher's full 20-second deadline.
	for _ in $(seq 1 1000); do
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

accept_early_frame
retire_root_bridge
dispatch_handoff_action

while :; do
	rm -f "$FIRST_FRAME"
	"$LAUNCHER" &
	LAUNCHER_PID=$!
	if ! mark_healthy; then
		systemctl reboot --force
		exit 1
	fi
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
