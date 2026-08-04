#!/bin/sh
# Capture the current volatile state before cancelling a wedged Bird foreground
# transaction and restarting only its UI supervisor. This is an operator-only
# recovery path; ordinary boot, input and idle never execute this file.

set -u
umask 077

LOG_ROOT=${BIRD_EMERGENCY_LOG_ROOT:-/storage/bird-data/Bird/log/emergency}
PROC_ROOT=${BIRD_EMERGENCY_PROC_ROOT:-/proc}
RUN_ROOT=${BIRD_EMERGENCY_RUN_ROOT:-/run}
EXIT_HELPER=${BIRD_EMERGENCY_EXIT_HELPER:-/flash/bird/bird-fixed-control-exit.sh}
SYSTEMCTL_PROGRAM=${BIRD_EMERGENCY_SYSTEMCTL:-systemctl}
TIMEOUT_PROGRAM=${BIRD_EMERGENCY_TIMEOUT:-timeout}
SYNC_PROGRAM=${BIRD_EMERGENCY_SYNC:-sync}
SIGNAL_PROGRAM=${BIRD_EMERGENCY_SIGNAL:-kill}
USLEEP_PROGRAM=${BIRD_EMERGENCY_USLEEP:-usleep}
READLINK_PROGRAM=${BIRD_EMERGENCY_READLINK:-readlink}
TAIL_PROGRAM=${BIRD_EMERGENCY_TAIL:-tail}
JOURNALCTL_PROGRAM=${BIRD_EMERGENCY_JOURNALCTL:-journalctl}
DMESG_PROGRAM=${BIRD_EMERGENCY_DMESG:-dmesg}
PS_PROGRAM=${BIRD_EMERGENCY_PS:-ps}
EARLY_PID=${BIRD_EMERGENCY_EARLY_PID:-$RUN_ROOT/muos/initramfs-launcher.pid}
REQUEST=${BIRD_EMERGENCY_REQUEST:-$RUN_ROOT/muos/bird-launch-request}
HANDOFF_ACTION=${BIRD_EMERGENCY_HANDOFF_ACTION:-$RUN_ROOT/muos/bird-launch-action}

mkdir -p "$LOG_ROOT" || exit 1
BOOT_ID=unknown
if [ -r "$PROC_ROOT/sys/kernel/random/boot_id" ]; then
	IFS= read -r BOOT_ID <"$PROC_ROOT/sys/kernel/random/boot_id" || BOOT_ID=unknown
fi
case "$BOOT_ID" in
	''|*[!0-9a-fA-F-]*) BOOT_ID=unknown ;;
esac
BOOT_TOKEN=$(printf '%s\n' "$BOOT_ID" | tr -d - | cut -c1-8)
[ -n "$BOOT_TOKEN" ] || BOOT_TOKEN=unknown
UPTIME=unknown
if [ -r "$PROC_ROOT/uptime" ]; then
	IFS=' ' read -r UPTIME _ <"$PROC_ROOT/uptime" || UPTIME=unknown
fi
case "$UPTIME" in
	''|*[!0-9.]*) UPTIME=unknown ;;
esac
UPTIME_TOKEN=${UPTIME%%.*}
[ -n "$UPTIME_TOKEN" ] || UPTIME_TOKEN=unknown
LOG=$LOG_ROOT/emergency-recovery-$BOOT_TOKEN-$UPTIME_TOKEN-$$.log
exec 9>"$LOG" || exit 1

section() {
	printf '\n--- %s ---\n' "$1" >&9
}

snapshot_command() {
	SNAPSHOT_LABEL=$1
	shift
	section "$SNAPSHOT_LABEL"
	"$TIMEOUT_PROGRAM" --signal=TERM --kill-after=1s 3s "$@" >&9 2>&1
	SNAPSHOT_STATUS=$?
	printf 'snapshot_status=%s\n' "$SNAPSHOT_STATUS" >&9
}

snapshot_file() {
	SNAPSHOT_LABEL=$1
	SNAPSHOT_PATH=$2
	section "$SNAPSHOT_LABEL path=$SNAPSHOT_PATH"
	if [ -f "$SNAPSHOT_PATH" ]; then
		"$TIMEOUT_PROGRAM" --signal=TERM --kill-after=1s 3s \
			"$TAIL_PROGRAM" -c 262144 "$SNAPSHOT_PATH" >&9 2>&1
		printf 'snapshot_status=%s\n' "$?" >&9
	else
		printf '%s\n' 'snapshot_status=missing' >&9
	fi
}

sync_log() {
	if "$SYNC_PROGRAM" "$LOG" 2>/dev/null; then
		return 0
	fi
	if "$SYNC_PROGRAM" -f "$LOG" 2>/dev/null; then
		return 0
	fi
	"$SYNC_PROGRAM" 2>/dev/null
}

launcher_exited() {
	LAUNCHER_PID=$1
	[ -r "$PROC_ROOT/$LAUNCHER_PID/stat" ] || return 0
	IFS= read -r LAUNCHER_STAT <"$PROC_ROOT/$LAUNCHER_PID/stat" || return 0
	LAUNCHER_REST=${LAUNCHER_STAT##*) }
	LAUNCHER_STATE=${LAUNCHER_REST%% *}
	case "$LAUNCHER_STATE" in
		Z|X|x) return 0 ;;
	esac
	return 1
}

early_launcher_exact() {
	LAUNCHER_PID=$1
	launcher_exited "$LAUNCHER_PID" && return 1
	LAUNCHER_EXE=$("$READLINK_PROGRAM" "$PROC_ROOT/$LAUNCHER_PID/exe" \
		2>/dev/null || :)
	case "$LAUNCHER_EXE" in
		/opt/bird/bird-launcher|'/opt/bird/bird-launcher (deleted)') ;;
		*) return 1 ;;
	esac
	launcher_exited "$LAUNCHER_PID" && return 1
	return 0
}

terminate_early_launcher() {
	EARLY_RESULT=absent
	[ -s "$EARLY_PID" ] || return 0
	IFS= read -r LAUNCHER_PID <"$EARLY_PID" || return 0
	case "$LAUNCHER_PID" in
		''|*[!0-9]*|0|1) EARLY_RESULT=invalid; return 0 ;;
	esac
	if ! early_launcher_exact "$LAUNCHER_PID"; then
		EARLY_RESULT=stale
		return 0
	fi
	EARLY_RESULT=term
	"$SIGNAL_PROGRAM" -TERM "$LAUNCHER_PID" 2>/dev/null || return 0
	EARLY_WAIT=0
	while [ "$EARLY_WAIT" -lt 50 ]; do
		launcher_exited "$LAUNCHER_PID" && { EARLY_RESULT=exited; return 0; }
		EARLY_WAIT=$((EARLY_WAIT + 1))
		"$USLEEP_PROGRAM" 20000
	done
	if early_launcher_exact "$LAUNCHER_PID"; then
		EARLY_RESULT=kill
		"$SIGNAL_PROGRAM" -KILL "$LAUNCHER_PID" 2>/dev/null || :
	fi
}

printf 'Bird emergency recovery version=1 boot_id=%s uptime=%s pid=%s\n' \
	"$BOOT_ID" "$UPTIME" "$$" >&9
snapshot_command command-line cat "$PROC_ROOT/cmdline"
snapshot_command units "$SYSTEMCTL_PROGRAM" list-units --all --no-pager
snapshot_command bird-units "$SYSTEMCTL_PROGRAM" show \
	--property=Id,LoadState,ActiveState,SubState,MainPID,ControlGroup,NRestarts \
	essway.service sway.service input.service powerstate.service \
	rocknix-autostart.service rocknix.target
snapshot_command processes "$PS_PROGRAM" -eo pid,ppid,state,etimes,rss,comm,args
snapshot_file meminfo "$PROC_ROOT/meminfo"
for PRESSURE in cpu io memory; do
	snapshot_file pressure-$PRESSURE "$PROC_ROOT/pressure/$PRESSURE"
done
snapshot_file early-launcher "$RUN_ROOT/muos/initramfs-launcher.log"
snapshot_file supervisor /storage/bird-data/Bird/log/stock-root-supervisor.log
snapshot_file content /storage/bird-data/Bird/log/stock-root-content-latest.log
snapshot_file content-exit /storage/bird-data/Bird/log/content-exit-latest.log
snapshot_file launch-request "$REQUEST"
snapshot_file handoff-action "$HANDOFF_ACTION"
for STATE in "$RUN_ROOT"/bird/content-runner-*.state \
	"$RUN_ROOT"/bird/content-session*.pid; do
	[ -e "$STATE" ] || continue
	snapshot_file foreground-state "$STATE"
done
snapshot_command journal "$JOURNALCTL_PROGRAM" -b --no-pager -n 500
snapshot_command kernel "$DMESG_PROGRAM"
printf '\nsnapshot_complete=1\n' >&9
sync_log || printf 'snapshot_sync=failed\n' >&9

"$TIMEOUT_PROGRAM" --signal=TERM --kill-after=1s 4s "$EXIT_HELPER"
EXIT_STATUS=$?
printf 'foreground_exit_status=%s\n' "$EXIT_STATUS" >&9
snapshot_file content-exit-after /storage/bird-data/Bird/log/content-exit-latest.log

rm -f "$REQUEST" "$HANDOFF_ACTION" "$HANDOFF_ACTION.tmp"
printf 'pending_action_cancelled=1\n' >&9
terminate_early_launcher
printf 'early_launcher_action=%s\n' "$EARLY_RESULT" >&9
printf 'ui_restart_requested=1\n' >&9
sync_log || printf 'pre_restart_sync=failed\n' >&9

"$TIMEOUT_PROGRAM" --signal=TERM --kill-after=1s 4s \
	"$SYSTEMCTL_PROGRAM" restart --no-block essway.service
RESTART_STATUS=$?
printf 'ui_restart_status=%s\n' "$RESTART_STATUS" >&9
sync_log || :
exit "$RESTART_STATUS"
