#!/bin/bash
# Bird stays a small UI process. ROCKNIX owns all hardware, service and content
# setup; this supervisor begins at the stable graphical boundary, adopts the
# original initramfs process and dispatches each request exactly once.

set -u

LAUNCHER=/flash/bird/bird-launcher
RUNNER=/flash/bird/run-content.sh
REQUEST=/run/muos/bird-launch-request
FIRST_FRAME=/run/muos/bird-first-frame-ready
HANDOFF_ACTION=/run/muos/bird-launch-action
EARLY_LOG=/run/muos/initramfs-launcher.log
EARLY_PID=/run/muos/initramfs-launcher.pid
PIDWAIT=/storage/.config/bird/bird-pidwait
RELEASE_ID=v6.23
ATTEMPTS=/storage/bird-data/MUOS/Bird/boot-state/releases/$RELEASE_ID/attempts
LOG_DIR=/storage/bird-data/MUOS/Bird/log
LOG=$LOG_DIR/stock-root-supervisor.log
LOG_BOOT_ID=$LOG_DIR/stock-root-supervisor.boot-id
EARLY_LATEST=$LOG_DIR/early-initramfs-latest.log
BOOT_STATE_LATEST=$LOG_DIR/stock-root-boot-state-latest.log
SHUTDOWN_LOG=$LOG_DIR/shutdown-latest.log
CONTENT_STATE_DIR=/run/bird
STARTUP_FAILURE_LIMIT=3
ATTEMPTS_TMP=$ATTEMPTS.tmp.$$
HEALTH_REASON=
LAUNCHER_RESULT=0
EARLY_LAUNCHER_PID=
EARLY_ACCEPT_REASON=
EARLY_HEALTH_COMMITTED=0

mkdir -p /run/muos "$LOG_DIR" "${ATTEMPTS%/*}"
BOOT_ID=$(cut -c1-8 /proc/sys/kernel/random/boot_id 2>/dev/null || :)
[ -n "$BOOT_ID" ] || BOOT_ID=unknown
OLD_BOOT_ID=$(cat "$LOG_BOOT_ID" 2>/dev/null || :)
if [ "$OLD_BOOT_ID" != "$BOOT_ID" ]; then
	case "$OLD_BOOT_ID" in
		????????)
			[ -s "$LOG" ] && cp -f "$LOG" \
				"$LOG_DIR/stock-root-supervisor-$OLD_BOOT_ID.log"
			[ -s "$EARLY_LATEST" ] && cp -f "$EARLY_LATEST" \
				"$LOG_DIR/early-initramfs-$OLD_BOOT_ID.log"
			[ -s "$BOOT_STATE_LATEST" ] && cp -f "$BOOT_STATE_LATEST" \
				"$LOG_DIR/stock-root-boot-state-$OLD_BOOT_ID.log"
			if [ -s "$SHUTDOWN_LOG" ] && cp -f "$SHUTDOWN_LOG" \
				"$LOG_DIR/shutdown-$OLD_BOOT_ID.log"; then
				# A later forced reset must not attribute this older trace to
				# the boot that is starting now.
				: >"$SHUTDOWN_LOG"
			fi
			;;
	esac
	: >"$LOG"
	printf '%s\n' "$BOOT_ID" >"$LOG_BOOT_ID"
fi
exec >>"$LOG" 2>&1
printf 'bird supervisor boot_id=%s release_id=%s start uptime=' \
	"$BOOT_ID" "$RELEASE_ID"
cut -d ' ' -f 1 /proc/uptime

supervisor_signal() {
	rm -f "$ATTEMPTS_TMP"
	printf 'bird supervisor signal=%s uptime=' "$1"
	cut -d ' ' -f 1 /proc/uptime
	exit 0
}
trap 'supervisor_signal TERM' TERM
trap 'supervisor_signal HUP' HUP
trap 'supervisor_signal INT' INT

poweroff_client() {
	/usr/bin/timeout --signal=TERM --kill-after=1s 3s \
		systemctl --no-block poweroff
}

reboot_client() {
	/usr/bin/timeout --signal=TERM --kill-after=1s 3s \
		systemctl --no-block reboot
}

request_reboot() {
	local result
	if reboot_client; then
		printf 'bird reboot dispatch ready uptime='
		cut -d ' ' -f 1 /proc/uptime
		exit 0
	else
		result=$?
	fi
	printf 'bird reboot dispatch failed result=%s; resuming launcher uptime=' \
		"$result"
	cut -d ' ' -f 1 /proc/uptime
	return "$result"
}

request_poweroff() {
	local result
	{
		printf 'Bird shutdown requested boot_id=%s uptime=' "$BOOT_ID"
		cut -d ' ' -f 1 /proc/uptime
	} >"$SHUTDOWN_LOG"
	if poweroff_client; then
		{
			printf 'Bird shutdown dispatch ready boot_id=%s uptime=' "$BOOT_ID"
			cut -d ' ' -f 1 /proc/uptime
		} >>"$SHUTDOWN_LOG"
		exit 0
	else
		result=$?
	fi
	printf 'Bird shutdown dispatch failed boot_id=%s exit=%s uptime=' \
		"$BOOT_ID" "$result" >>"$SHUTDOWN_LOG"
	cut -d ' ' -f 1 /proc/uptime >>"$SHUTDOWN_LOG"
	printf 'bird shutdown dispatch failed result=%s; resuming launcher uptime=' \
		"$result"
	cut -d ' ' -f 1 /proc/uptime
	return "$result"
}

reset_boot_attempts() {
	# A torn zero can be parsed as another failed boot by the initramfs. Publish
	# the reset with one same-directory rename and verify both sides of it.
	rm -f "$ATTEMPTS_TMP"
	printf '0\n' >"$ATTEMPTS_TMP" || return 1
	[ "$(cat "$ATTEMPTS_TMP" 2>/dev/null || :)" = 0 ] || return 1
	sync "$ATTEMPTS_TMP" || return 1
	mv -f "$ATTEMPTS_TMP" "$ATTEMPTS" || return 1
	[ "$(cat "$ATTEMPTS" 2>/dev/null || :)" = 0 ] || return 1
	sync "$ATTEMPTS" || return 1
	# Persist the same-directory rename itself, not only the new file bytes. GNU
	# sync supports directory fsync directly; retain syncfs/global fallbacks for
	# the smaller recovery toolset.
	if sync "${ATTEMPTS%/*}" 2>/dev/null; then
		:
	elif sync -f "${ATTEMPTS%/*}" 2>/dev/null; then
		:
	elif sync; then
		:
	else
		return 1
	fi
	return 0
}

report_boot_attempt_reset_failure() {
	rm -f "$ATTEMPTS_TMP"
	printf 'bird boot-attempt reset failed path=%s uptime=' "$ATTEMPTS"
	cut -d ' ' -f 1 /proc/uptime
}

content_cleanup_pending() {
	local state
	for state in "$CONTENT_STATE_DIR"/content-runner-*.state; do
		# A malformed dangling symlink is still an unresolved lease. Only absence
		# of every matching directory entry permits foreground handoff.
		{ [ -e "$state" ] || [ -L "$state" ]; } && return 0
	done
	return 1
}

wait_content_cleanup() {
	local warned=0
	while content_cleanup_pending; do
		if [ "$warned" -eq 0 ]; then
			printf 'bird waiting for foreground content cleanup uptime='
			cut -d ' ' -f 1 /proc/uptime
			warned=1
		fi
		usleep 20000
	done
	[ "$warned" -eq 0 ] || {
		printf 'bird foreground content cleanup complete uptime='
		cut -d ' ' -f 1 /proc/uptime
	}
}

run_content() {
	local result
	"$RUNNER" "$@"
	result=$?
	# A SIGKILLed runner returns to this shell before its detached guard can
	# reconcile the exact scope and display resources.  Its atomic state file is
	# the foreground lease and the guard removes it only after cleanup completes.
	wait_content_cleanup
	return "$result"
}

consume_handoff_action() {
	if rm -f "$HANDOFF_ACTION"; then
		return 0
	fi
	printf 'bird initramfs handoff consume failed path=%s uptime=' \
		"$HANDOFF_ACTION"
	cut -d ' ' -f 1 /proc/uptime
	return 1
}

dispatch_handoff_action() {
	[ -s "$HANDOFF_ACTION" ] || return 0
	ACTION=$(cat "$HANDOFF_ACTION")
	printf 'bird initramfs handoff action=%s uptime=' "$ACTION"
	cut -d ' ' -f 1 /proc/uptime
	case "$ACTION" in
		10) consume_handoff_action && run_content "$REQUEST" ;;
		11) consume_handoff_action && request_poweroff ;;
		12) consume_handoff_action && run_content --portmaster ;;
		13) consume_handoff_action ;;
		14) consume_handoff_action && request_reboot ;;
		*) rm -f "$HANDOFF_ACTION" ;;
	esac
}

read_completed_handoff_action() {
	local bytes trailing=
	ACTION=
	[ -s "$HANDOFF_ACTION" ] || return 1
	bytes=$(wc -c <"$HANDOFF_ACTION" 2>/dev/null) || return 1
	[ "$bytes" -eq 3 ] || return 1
	{
		# The early launcher publishes exactly two digits and one newline with
		# an atomic rename. Reject partial, extended and multi-line files rather
		# than treating a prefix as proof that a usable launcher completed.
		IFS= read -r ACTION || return 1
		if IFS= read -r trailing; then
			return 1
		fi
		[ -z "$trailing" ] || return 1
	} <"$HANDOFF_ACTION"
	case "$ACTION" in
		10|11|12|13|14) return 0 ;;
		*) return 1 ;;
	esac
}

accept_completed_early_action() {
	# A fast user action can make the initramfs launcher exit before this
	# supervisor is started. In that case process adoption is impossible, but
	# the interactive marker plus the launcher's atomically published action is
	# durable proof that the boot reached a usable frame. Neither file alone is
	# sufficient: a stale marker cannot forgive a crash and a partial handoff
	# cannot forgive an unready boot.
	[ "$EARLY_HEALTH_COMMITTED" -eq 0 ] || return 0
	[ -e "$FIRST_FRAME" ] || return 0
	read_completed_handoff_action || return 0
	if ! reset_boot_attempts; then
		report_boot_attempt_reset_failure
		return 1
	fi
	printf 'bird accepted completed initramfs action=%s uptime=' "$ACTION"
	cut -d ' ' -f 1 /proc/uptime
	return 0
}

service_handoff_action() {
	# Boot health must be durable before the authoritative action can be
	# consumed. On reset failure, leave the action intact so a systemd restart
	# can retry the transaction without losing or duplicating the request.
	accept_completed_early_action || return 1
	dispatch_handoff_action
	# Preserve the existing behavior for a runner or poweroff-client failure:
	# those results resume the launcher rather than becoming health failures.
	return 0
}

archive_early_launcher() {
	[ -f "$EARLY_LOG" ] && cp -f "$EARLY_LOG" "$LOG_DIR/early-initramfs-latest.log"
	rm -f "$EARLY_PID"
}

early_launcher_adoptable() {
	local pid=$1 exe
	[ -x "$PIDWAIT" ] || return 1
	if launcher_exited "$pid"; then
		printf 'bird ignored exited early pid=%s\n' "$pid"
		return 1
	fi
	exe=$(readlink "/proc/$pid/exe" 2>/dev/null || :)
	if [ "$exe" != /opt/bird/bird-launcher ] && \
		[ "$exe" != '/opt/bird/bird-launcher (deleted)' ]; then
		printf 'bird ignored stale early pid=%s exe=%s\n' "$pid" "$exe"
		return 1
	fi
	# The process may have exited or execed between the stat and exe reads.
	launcher_exited "$pid" && return 1
	return 0
}

load_early_launcher() {
	local pid
	EARLY_LAUNCHER_PID=
	[ -s "$EARLY_PID" ] || return 1
	pid=$(cat "$EARLY_PID")
	case "$pid" in *[!0-9]*|'') return 1 ;; esac
	early_launcher_adoptable "$pid" || return 1
	EARLY_LAUNCHER_PID=$pid
	return 0
}

accept_early_frame() {
	local pid=$1 check
	EARLY_ACCEPT_REASON=

	# The marker can legitimately arrive after switch_root. Race that event
	# against the exact retained process instead of entering indefinite adoption
	# with a still-charged boot attempt. The marker already requires this bounded
	# 20-ms poll; checking /proc in the same wakeup avoids a cancellable pre-exec
	# pidwait child and its signal race.
	for ((check = 0; check < 1000; check++)); do
		if launcher_exited "$pid"; then
			EARLY_ACCEPT_REASON=owner-exit
			return 2
		fi
		if [ -e "$FIRST_FRAME" ]; then
			# Revalidate executable identity and liveness after observing the
			# marker. Exit or exec therefore wins before persistent state changes.
			if ! early_launcher_adoptable "$pid"; then
				EARLY_ACCEPT_REASON=owner-invalid
				return 2
			fi
			if ! reset_boot_attempts; then
				report_boot_attempt_reset_failure
				EARLY_ACCEPT_REASON=attempt-reset-failed
				return 1
			fi
			[ -f "$EARLY_LOG" ] && \
				cp -f "$EARLY_LOG" "$LOG_DIR/early-initramfs-latest.log"
			EARLY_ACCEPT_REASON=first-frame
			printf 'bird accepted initramfs first frame pid=%s uptime=' "$pid"
			cut -d ' ' -f 1 /proc/uptime
			return 0
		fi
		usleep 20000
	done
	EARLY_ACCEPT_REASON=first-frame-timeout
	printf 'bird initramfs first-frame timeout pid=%s uptime=' "$pid"
	cut -d ' ' -f 1 /proc/uptime
	return 2
}

retire_early_launcher() {
	local pid=$1 check
	# Timeout is the only live-owner failure that reaches here. Revalidate the
	# exact mapped executable immediately before each signal so a stale PID can
	# never target an unrelated process.
	early_launcher_adoptable "$pid" || return 0
	printf 'bird retiring unready initramfs launcher pid=%s uptime=' "$pid"
	cut -d ' ' -f 1 /proc/uptime
	kill -TERM "$pid" 2>/dev/null || return 0
	for ((check = 0; check < 50; check++)); do
		launcher_exited "$pid" && return 0
		usleep 20000
	done
	early_launcher_adoptable "$pid" || return 0
	kill -KILL "$pid" 2>/dev/null || :
}

adopt_early_launcher() {
	local pid=$1
	early_launcher_adoptable "$pid" || return 1

	printf 'bird adopted persistent initramfs launcher pid=%s uptime=' "$pid"
	cut -d ' ' -f 1 /proc/uptime
	# pidfd_open + ppoll sleeps inside the kernel. The supervisor does no
	# periodic kill(2), /proc scan or timer wakeup while Bird owns the menu.
	if ! "$PIDWAIT" "$pid"; then
		printf 'bird persistent-owner pidfd fallback pid=%s uptime=' "$pid"
		cut -d ' ' -f 1 /proc/uptime
		while ! launcher_exited "$pid"; do usleep 20000; done
	fi
	printf 'bird persistent initramfs launcher exited pid=%s uptime=' "$pid"
	cut -d ' ' -f 1 /proc/uptime
	archive_early_launcher
	return 0
}

launcher_exited() {
	# kill -0 remains true for an unreaped child. Read the process state as the
	# fallback for kernels without pidfd_open so a zombie is still an exit edge.
	local pid=$1 stat rest state
	[ -r "/proc/$pid/stat" ] || return 0
	IFS= read -r stat <"/proc/$pid/stat" || return 0
	rest=${stat##*) }
	state=${rest%% *}
	case "$state" in
		Z|X|x) return 0 ;;
	esac
	return 1
}

mark_healthy() {
	local pid=$1 check
	HEALTH_REASON=

	# The final-root launcher intentionally races the remaining service graph.
	# Allow the fixed H700 input node its full 20-second launcher deadline, but
	# stop waiting as soon as that launcher can no longer publish a frame. The
	# marker poll also checks /proc, avoiding a cancellable background pidwait.
	for ((check = 0; check < 1000; check++)); do
		if launcher_exited "$pid"; then
			HEALTH_REASON=child-exit
			printf 'bird stock-root launcher exited before first frame uptime='
			cut -d ' ' -f 1 /proc/uptime
			return 1
		fi
		if [ -e "$FIRST_FRAME" ]; then
			# Re-check the child after observing the marker. This makes a marker
			# left by a process that already died lose the race.
			if launcher_exited "$pid"; then
				HEALTH_REASON=child-exit
				printf 'bird stock-root stale first frame after exit uptime='
				cut -d ' ' -f 1 /proc/uptime
				return 1
			fi
			if ! reset_boot_attempts; then
				report_boot_attempt_reset_failure
				HEALTH_REASON=attempt-reset-failed
				return 1
			fi
			printf 'bird stock-root first frame uptime='
			cut -d ' ' -f 1 /proc/uptime
			return 0
		fi
		usleep 20000
	done
	HEALTH_REASON=first-frame-timeout
	printf 'bird stock-root first-frame timeout uptime='
	cut -d ' ' -f 1 /proc/uptime
	return 1
}

reap_launcher() {
	local pid=$1
	if wait "$pid"; then
		LAUNCHER_RESULT=0
	else
		LAUNCHER_RESULT=$?
	fi
}

stop_and_reap_launcher() {
	local pid=$1 check
	if ! launcher_exited "$pid"; then
		kill -TERM "$pid" 2>/dev/null || :
		for ((check = 0; check < 50; check++)); do
			launcher_exited "$pid" && break
			usleep 20000
		done
	fi
	if ! launcher_exited "$pid"; then
		kill -KILL "$pid" 2>/dev/null || :
	fi
	reap_launcher "$pid"
}

classify_startup_failure() {
	local reason=$1 result=$2
	case "$reason:$result" in
		first-frame-timeout:*) STARTUP_CLASS=recoverable-timeout ;;
		child-exit:2) STARTUP_CLASS=recoverable-framebuffer-wait ;;
		child-exit:3) STARTUP_CLASS=recoverable-framebuffer-ioctl ;;
		child-exit:5) STARTUP_CLASS=recoverable-framebuffer-map ;;
		child-exit:6) STARTUP_CLASS=recoverable-input-wait ;;
		child-exit:4) STARTUP_CLASS=fatal-framebuffer-format ;;
		child-exit:126|child-exit:127) STARTUP_CLASS=fatal-exec ;;
		child-exit:*)
			if [ "$result" -ge 128 ]; then
				STARTUP_CLASS=fatal-signal
			else
				STARTUP_CLASS=unexpected-exit
			fi
			;;
		*) STARTUP_CLASS=unexpected-health-failure ;;
	esac
}

startup_backoff() {
	local class=$1 attempt=$2
	case "$class:$attempt" in
		recoverable-*:1) usleep 100000 ;;
		recoverable-*:2) usleep 300000 ;;
		recoverable-*:*) usleep 600000 ;;
		*:1) usleep 500000 ;;
		*:2) usleep 1000000 ;;
		*) usleep 1500000 ;;
	esac
}

runtime_backoff() {
	case "$1" in
		1) usleep 50000 ;;
		2) usleep 100000 ;;
		3) usleep 250000 ;;
		*) usleep 500000 ;;
	esac
}

# A restarted supervisor must honor an armed crash guard from its predecessor
# before adopting or starting any launcher process.
wait_content_cleanup

if load_early_launcher; then
	if accept_early_frame "$EARLY_LAUNCHER_PID"; then
		EARLY_HEALTH_COMMITTED=1
		if ! adopt_early_launcher "$EARLY_LAUNCHER_PID"; then
			archive_early_launcher
		fi
	else
		EARLY_ACCEPT_RESULT=$?
		if [ "$EARLY_ACCEPT_RESULT" -eq 1 ] && \
			early_launcher_adoptable "$EARLY_LAUNCHER_PID"; then
			# Keep the already-visible initramfs launcher alive. systemd can
			# restart this supervisor and retry the persistence transaction.
			printf 'bird early frame not accepted; supervisor retry required uptime='
			cut -d ' ' -f 1 /proc/uptime
			exit 1
		fi
		if [ "$EARLY_ACCEPT_REASON" = first-frame-timeout ]; then
			retire_early_launcher "$EARLY_LAUNCHER_PID"
		fi
		archive_early_launcher
	fi
else
	archive_early_launcher
fi
if ! service_handoff_action; then
	printf 'bird completed early action not accepted; supervisor retry required uptime='
	cut -d ' ' -f 1 /proc/uptime
	exit 1
fi

STARTUP_FAILURES=0
RUNTIME_FAILURES=0
while :; do
	rm -f "$FIRST_FRAME"
	"$LAUNCHER" &
	LAUNCHER_PID=$!
	if ! mark_healthy "$LAUNCHER_PID"; then
		if launcher_exited "$LAUNCHER_PID"; then
			reap_launcher "$LAUNCHER_PID"
		else
			stop_and_reap_launcher "$LAUNCHER_PID"
		fi
		STARTUP_FAILURES=$((STARTUP_FAILURES + 1))
		classify_startup_failure "$HEALTH_REASON" "$LAUNCHER_RESULT"
		printf 'bird launcher startup failure=%s result=%s attempt=%s/%s uptime=' \
			"$STARTUP_CLASS" "$LAUNCHER_RESULT" "$STARTUP_FAILURES" \
			"$STARTUP_FAILURE_LIMIT"
		cut -d ' ' -f 1 /proc/uptime
		if [ "$STARTUP_FAILURES" -lt "$STARTUP_FAILURE_LIMIT" ]; then
			# Recoverable device timing gets a short retry. A fatal class is
			# relaunched only to establish repeated boot-level failure before the
			# fallback-driving reboot; it receives the slower backoff.
			startup_backoff "$STARTUP_CLASS" "$STARTUP_FAILURES"
			continue
		fi
		printf 'bird repeated boot-level launcher failure; rebooting uptime='
		cut -d ' ' -f 1 /proc/uptime
		systemctl reboot --force
		exit 1
	fi
	STARTUP_FAILURES=0
	reap_launcher "$LAUNCHER_PID"
	RESULT=$LAUNCHER_RESULT
	printf 'bird launcher result=%s uptime=' "$RESULT"
	cut -d ' ' -f 1 /proc/uptime
	case "$RESULT" in
		10) RUNTIME_FAILURES=0; run_content "$REQUEST" ;;
		11) RUNTIME_FAILURES=0; request_poweroff ;;
		12) RUNTIME_FAILURES=0; run_content --portmaster ;;
		13)
			RUNTIME_FAILURES=0
			printf 'bird launcher user-requested reload\n'
			;;
		14) RUNTIME_FAILURES=0; request_reboot ;;
		*)
			RUNTIME_FAILURES=$((RUNTIME_FAILURES + 1))
			printf 'bird launcher unexpected post-frame exit streak=%s\n' \
				"$RUNTIME_FAILURES"
			runtime_backoff "$RUNTIME_FAILURES"
			;;
	esac
done
