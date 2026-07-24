#!/bin/bash
# Bird stays a small UI process. ROCKNIX owns all hardware, service and content
# setup; this supervisor begins at the stable graphical boundary, adopts the
# original initramfs process and dispatches each request exactly once.

set -u

LAUNCHER=/storage/.config/bird/dani-launcher
RUNNER=/storage/.config/bird/run-content.sh
REQUEST=/run/muos/dani-launch-request
FIRST_FRAME=/run/muos/dani-first-frame-ready
HANDOFF_ACTION=/run/muos/dani-launch-action
EARLY_LOG=/run/muos/initramfs-launcher.log
EARLY_PID=/run/muos/initramfs-launcher.pid
PIDWAIT=/storage/.config/bird/bird-pidwait
ATTEMPTS=/storage/bird-data/MUOS/Bird/boot-state/stock-root-attempts
LOG_DIR=/storage/bird-data/MUOS/Bird/log
LOG=$LOG_DIR/stock-root-supervisor.log
LOG_BOOT_ID=$LOG_DIR/stock-root-supervisor.boot-id
SHUTDOWN_LOG=$LOG_DIR/shutdown-latest.log

mkdir -p /run/muos "$LOG_DIR" "${ATTEMPTS%/*}"
BOOT_ID=$(cut -c1-8 /proc/sys/kernel/random/boot_id 2>/dev/null || :)
[ -n "$BOOT_ID" ] || BOOT_ID=unknown
if [ "$(cat "$LOG_BOOT_ID" 2>/dev/null || :)" != "$BOOT_ID" ]; then
	: >"$LOG"
	printf '%s\n' "$BOOT_ID" >"$LOG_BOOT_ID"
fi
exec >>"$LOG" 2>&1
printf 'bird supervisor boot_id=%s start uptime=' "$BOOT_ID"
cut -d ' ' -f 1 /proc/uptime

supervisor_signal() {
	printf 'bird supervisor signal=%s uptime=' "$1"
	cut -d ' ' -f 1 /proc/uptime
	exit 0
}
trap 'supervisor_signal TERM' TERM
trap 'supervisor_signal HUP' HUP
trap 'supervisor_signal INT' INT

request_poweroff() {
	{
		printf 'Bird shutdown requested boot_id=%s uptime=' "$BOOT_ID"
		cut -d ' ' -f 1 /proc/uptime
	} >"$SHUTDOWN_LOG"
	systemctl --no-block poweroff
	exit 0
}

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
		11) rm -f "$HANDOFF_ACTION"; request_poweroff ;;
		12) "$RUNNER" --portmaster; rm -f "$HANDOFF_ACTION" ;;
		*) rm -f "$HANDOFF_ACTION" ;;
	esac
}

archive_early_launcher() {
	[ -f "$EARLY_LOG" ] && cp -f "$EARLY_LOG" "$LOG_DIR/early-initramfs-latest.log"
	rm -f "$EARLY_PID"
}

adopt_early_launcher() {
	[ -s "$EARLY_PID" ] || return 1
	[ -x "$PIDWAIT" ] || return 1
	PID=$(cat "$EARLY_PID")
	case "$PID" in *[!0-9]*|'') return 1 ;; esac
	kill -0 "$PID" 2>/dev/null || return 1
	EXE=$(readlink "/proc/$PID/exe" 2>/dev/null || :)
	case "$EXE" in
		*/opt/bird/dani-launcher*) ;;
		*) printf 'bird ignored stale early pid=%s exe=%s\n' "$PID" "$EXE"
			return 1 ;;
	esac

	printf 'bird adopted persistent initramfs launcher pid=%s uptime=' "$PID"
	cut -d ' ' -f 1 /proc/uptime
	# pidfd_open + ppoll sleeps inside the kernel. The supervisor does no
	# periodic kill(2), /proc scan or timer wakeup while Bird owns the menu.
	if ! "$PIDWAIT" "$PID"; then
		printf 'bird persistent-owner pidfd fallback pid=%s uptime=' "$PID"
		cut -d ' ' -f 1 /proc/uptime
		while kill -0 "$PID" 2>/dev/null; do usleep 20000; done
	fi
	printf 'bird persistent initramfs launcher exited pid=%s uptime=' "$PID"
	cut -d ' ' -f 1 /proc/uptime
	archive_early_launcher
	return 0
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
if ! adopt_early_launcher; then
	archive_early_launcher
fi
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
		11) request_poweroff ;;
		12) "$RUNNER" --portmaster ;;
		*) usleep 50000 ;;
	esac
done
