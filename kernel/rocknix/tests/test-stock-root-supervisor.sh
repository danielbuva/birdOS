#!/bin/bash
# Host-only regression coverage for the final-root launcher health race and
# atomic boot-attempt reset. Nothing in this test can address a block device,
# invoke systemd, or write outside its temporary directory.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SUPERVISOR=$ROOT/kernel/rocknix/stock-root/supervisor.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-supervisor.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

grep -Fq 'LAUNCHER=/flash/bird/bird-launcher' "$SUPERVISOR"
grep -Fq 'RUNNER=/flash/bird/run-content.sh' "$SUPERVISOR"
grep -Fq 'PIDWAIT=/flash/bird/bird-pidwait' "$SUPERVISOR"

FUNCTIONS=$TMP/supervisor-functions.sh
awk '
	/^uptime_now\(\) \{/,/^}/ { print; next }
	/^classify_exit_status\(\) \{/,/^}/ { print; next }
	/^read_single_line_file\(\) \{/,/^}/ { print; next }
	/^poweroff_client\(\) \{/ { emit = 1 }
	/^reset_boot_attempts\(\) \{/ { emit = 1 }
	/^wait_content_cleanup$/ { exit }
	emit { print }
' "$SUPERVISOR" >"$FUNCTIONS"

grep -q '^uptime_now() {' "$FUNCTIONS"
grep -q '^classify_exit_status() {' "$FUNCTIONS"
grep -q '^read_single_line_file() {' "$FUNCTIONS"
grep -q '^poweroff_client() {' "$FUNCTIONS"
grep -q '^request_poweroff() {' "$FUNCTIONS"
grep -q '^reboot_client() {' "$FUNCTIONS"
grep -q '^request_reboot() {' "$FUNCTIONS"
grep -q '^reset_boot_attempts() {' "$FUNCTIONS"
grep -q '^mark_healthy() {' "$FUNCTIONS"
grep -q '^classify_startup_failure() {' "$FUNCTIONS"
grep -q '^early_launcher_adoptable() {' "$FUNCTIONS"

STATE=$TMP/state
mkdir -p "$STATE"
CONTENT_STATE_DIR=$STATE/content
mkdir -p "$CONTENT_STATE_DIR"

RELEASE_ID=v6.23
ATTEMPTS=$STATE/releases/$RELEASE_ID/attempts
ATTEMPTS_TMP=$ATTEMPTS.tmp.test
FIRST_FRAME=$STATE/first-frame
HANDOFF_ACTION=$STATE/handoff-action
EARLY_LOG=$STATE/early.log
EARLY_PID=$STATE/early.pid
LOG_DIR=$STATE/log
PIDWAIT_MISSING=$STATE/missing-pidwait
PIDWAIT_HELPER=$STATE/pidwait
PIDWAIT_EXIT_HELPER=$STATE/pidwait-exit
PIDWAIT_ERROR_HELPER=$STATE/pidwait-error
PIDWAIT=$PIDWAIT_MISSING
HEALTH_REASON=
LAUNCHER_RESULT=0
EARLY_LAUNCHER_PID=
EARLY_HEALTH_COMMITTED=0
MOCK_LAUNCHER_EXITED=0
MOCK_LAUNCHER_PID=4242
MOCK_LAUNCHER_EXE=/opt/bird/bird-launcher
MOCK_EXIT_ON_CHECK=0
MOCK_LAUNCHER_CHECKS=0
MOCK_EXIT_AFTER_SLEEP=0
MOCK_MARKER_AFTER_SLEEP=0
MOCK_LEASE_REMOVE_AFTER_SLEEP=0
MOCK_LEASE_PATH=
MOCK_TERM_EXITS=0
REBOOT_CALLS=0
SLEEP_CALLS=0
KILL_LOG=$STATE/kill.log
SYNC_MODE=success
SYNC_LOG=$STATE/sync.log

mkdir -p "$LOG_DIR" "${ATTEMPTS%/*}"
printf '%s\n' '#!/bin/sh' 'sleep 60' >"$PIDWAIT_HELPER"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$PIDWAIT_EXIT_HELPER"
printf '%s\n' '#!/bin/sh' 'exit 3' >"$PIDWAIT_ERROR_HELPER"
chmod 0755 "$PIDWAIT_HELPER" "$PIDWAIT_EXIT_HELPER" \
	"$PIDWAIT_ERROR_HELPER"

# shellcheck source=/dev/null
. "$FUNCTIONS"

SINGLE_LINE_TEST=$STATE/single-line
printf '10\n' >"$SINGLE_LINE_TEST"
read_single_line_file "$SINGLE_LINE_TEST"
[ "$SINGLE_LINE_VALUE" = 10 ]
printf '10' >"$SINGLE_LINE_TEST"
if read_single_line_file "$SINGLE_LINE_TEST"; then
	printf '%s\n' 'single-line reader accepted missing terminator' >&2
	exit 1
fi
printf '10\n11\n' >"$SINGLE_LINE_TEST"
if read_single_line_file "$SINGLE_LINE_TEST"; then
	printf '%s\n' 'single-line reader accepted a second record' >&2
	exit 1
fi
printf '10\n11' >"$SINGLE_LINE_TEST"
if read_single_line_file "$SINGLE_LINE_TEST"; then
	printf '%s\n' 'single-line reader accepted unterminated second record' >&2
	exit 1
fi
rm -f "$SINGLE_LINE_TEST"

classify_exit_status 0
[ "$CONTENT_EXIT_CLASS" = success ]
classify_exit_status 7
[ "$CONTENT_EXIT_CLASS" = exit-7 ]
classify_exit_status 137
[ "$CONTENT_EXIT_CLASS" = sigkill ]
classify_exit_status 143
[ "$CONTENT_EXIT_CLASS" = sigterm ]
classify_exit_status 130
[ "$CONTENT_EXIT_CLASS" = signal-2 ]
classify_exit_status 128
[ "$CONTENT_EXIT_CLASS" = exit-128 ]
classify_exit_status 192
[ "$CONTENT_EXIT_CLASS" = signal-64 ]
classify_exit_status 193
[ "$CONTENT_EXIT_CLASS" = exit-193 ]
classify_exit_status 255
[ "$CONTENT_EXIT_CLASS" = exit-255 ]

if grep -Eq '\$\(cat "\$(ATTEMPTS_TMP|ATTEMPTS|HANDOFF_ACTION|EARLY_PID)"' \
	"$SUPERVISOR"; then
	printf '%s\n' 'tiny supervisor state still forks cat' >&2
	exit 1
fi
if grep -Fq 'wc -c <"$HANDOFF_ACTION"' "$SUPERVISOR"; then
	printf '%s\n' 'handoff validation still forks wc' >&2
	exit 1
fi

# The production implementation reads /proc to recognize unreaped zombies.
# Hosts running this test may be macOS, so model only that one process-state
# primitive while exercising the real health state machine around it.
launcher_exited() {
	PID=$1
	if [ "$PID" -eq "$MOCK_LAUNCHER_PID" ]; then
		MOCK_LAUNCHER_CHECKS=$((MOCK_LAUNCHER_CHECKS + 1))
		if [ "$MOCK_EXIT_ON_CHECK" -gt 0 ] && \
			[ "$MOCK_LAUNCHER_CHECKS" -ge "$MOCK_EXIT_ON_CHECK" ]; then
			return 0
		fi
		[ "$MOCK_LAUNCHER_EXITED" -eq 1 ]
		return
	fi
	return 1
}

readlink() {
	if [ "$1" = "/proc/$MOCK_LAUNCHER_PID/exe" ]; then
		printf '%s\n' "$MOCK_LAUNCHER_EXE"
		return 0
	fi
	command readlink "$@"
}

usleep() {
	SLEEP_CALLS=$((SLEEP_CALLS + 1))
	if [ "$MOCK_MARKER_AFTER_SLEEP" -gt 0 ] && \
		[ "$SLEEP_CALLS" -ge "$MOCK_MARKER_AFTER_SLEEP" ]; then
		: >"$FIRST_FRAME"
	fi
	if [ "$MOCK_EXIT_AFTER_SLEEP" -gt 0 ] && \
		[ "$SLEEP_CALLS" -ge "$MOCK_EXIT_AFTER_SLEEP" ]; then
		MOCK_LAUNCHER_EXITED=1
	fi
	if [ "$MOCK_LEASE_REMOVE_AFTER_SLEEP" -gt 0 ] && \
		[ "$SLEEP_CALLS" -ge "$MOCK_LEASE_REMOVE_AFTER_SLEEP" ]; then
		rm -f "$MOCK_LEASE_PATH"
		MOCK_LEASE_REMOVE_AFTER_SLEEP=0
	fi
}

cut() {
	printf '%s\n' 0.00
}

systemctl() {
	REBOOT_CALLS=$((REBOOT_CALLS + 1))
	return 0
}

kill() {
	TARGET=${!#}
	if [ "$TARGET" = "$MOCK_LAUNCHER_PID" ]; then
		SIGNAL=TERM
		case "${1:-}" in
			-*) SIGNAL=${1#-} ;;
		esac
		printf '%s\n' "$SIGNAL" >>"$KILL_LOG"
		case "$SIGNAL" in
			KILL) MOCK_LAUNCHER_EXITED=1 ;;
			TERM) [ "$MOCK_TERM_EXITS" -eq 0 ] || MOCK_LAUNCHER_EXITED=1 ;;
		esac
		return 0
	fi
	command kill "$@"
}

sync() {
	printf '%s\n' "$*" >>"$SYNC_LOG"
	if [ "$SYNC_MODE" = fail-directory ]; then
		case "$*" in
			"${ATTEMPTS%/*}"|"-f ${ATTEMPTS%/*}"|'') return 1 ;;
		esac
	fi
	return 0
}

reset_case() {
	printf '%s\n' 2 >"$ATTEMPTS"
	rm -f "$ATTEMPTS_TMP" "$FIRST_FRAME" "$HANDOFF_ACTION" "$SYNC_LOG" \
		"$KILL_LOG"
	HEALTH_REASON=
	EARLY_LAUNCHER_PID=
	EARLY_ACCEPT_REASON=
	EARLY_HEALTH_COMMITTED=0
	MOCK_LAUNCHER_EXITED=0
	MOCK_LAUNCHER_EXE=/opt/bird/bird-launcher
	MOCK_EXIT_ON_CHECK=0
	MOCK_LAUNCHER_CHECKS=0
	MOCK_EXIT_AFTER_SLEEP=0
	MOCK_MARKER_AFTER_SLEEP=0
	MOCK_LEASE_REMOVE_AFTER_SLEEP=0
	MOCK_LEASE_PATH=
	MOCK_TERM_EXITS=0
	REBOOT_CALLS=0
	SLEEP_CALLS=0
	SYNC_MODE=success
	PIDWAIT=$PIDWAIT_MISSING
}

grep -Fq 'shutdown-$OLD_BOOT_ID.log' "$SUPERVISOR"
grep -Fq ': >"$SHUTDOWN_LOG"' "$SUPERVISOR"

# A launcher can publish a usable frame and a shutdown action, then exit before
# the persistent-root supervisor exists. The two canonical artifacts together
# clear the charged attempt before dispatch, without consuming the action.
reset_case
: >"$FIRST_FRAME"
printf '11\n' >"$HANDOFF_ACTION"
accept_completed_early_action
[ "$(cat "$ATTEMPTS")" = 0 ]
[ -s "$HANDOFF_ACTION" ]

# Each half of that proof fails closed. A canonical action without the
# interactive marker remains authoritative for dispatch but cannot clear boot
# attempts; a marker plus malformed action is not accepted as boot health.
reset_case
printf '11\n' >"$HANDOFF_ACTION"
accept_completed_early_action
[ "$(cat "$ATTEMPTS")" = 2 ]
[ -s "$HANDOFF_ACTION" ]

reset_case
: >"$FIRST_FRAME"
printf '11\nextra\n' >"$HANDOFF_ACTION"
accept_completed_early_action
[ "$(cat "$ATTEMPTS")" = 2 ]
[ -s "$HANDOFF_ACTION" ]

# Exercise transaction order with isolated mocks: reset must finish before
# dispatch. If reset fails, dispatch is skipped and the action remains intact
# for the systemd retry.
reset_case
: >"$FIRST_FRAME"
printf '11\n' >"$HANDOFF_ACTION"
ORDER_LOG=$STATE/handoff-order.log
rm -f "$ORDER_LOG"
(
	reset_boot_attempts() {
		[ -s "$HANDOFF_ACTION" ]
		printf '%s\n' 0 >"$ATTEMPTS"
		printf '%s\n' reset >>"$ORDER_LOG"
	}
	request_poweroff() { printf '%s\n' poweroff >>"$ORDER_LOG"; exit 0; }
	service_handoff_action
)
[ "$(tr '\n' ' ' <"$ORDER_LOG" | sed 's/ $//')" = 'reset poweroff' ]
[ "$(cat "$ATTEMPTS")" = 0 ]
[ ! -e "$HANDOFF_ACTION" ]

# Quit/Reboot is an equally authoritative completed handoff. Boot health is
# committed before the bounded reboot client is allowed to run.
reset_case
: >"$FIRST_FRAME"
printf '14\n' >"$HANDOFF_ACTION"
rm -f "$ORDER_LOG"
(
	reset_boot_attempts() {
		[ -s "$HANDOFF_ACTION" ]
		printf '%s\n' 0 >"$ATTEMPTS"
		printf '%s\n' reset >>"$ORDER_LOG"
	}
	request_reboot() { printf '%s\n' reboot >>"$ORDER_LOG"; exit 0; }
	service_handoff_action
)
[ "$(tr '\n' ' ' <"$ORDER_LOG" | sed 's/ $//')" = 'reset reboot' ]
[ "$(cat "$ATTEMPTS")" = 0 ]
[ ! -e "$HANDOFF_ACTION" ]

# An older already-running launcher may still publish action 13. Compatibility
# consumes it without starting content or a stock frontend; the current Home-B
# path refreshes in-process and does not emit this handoff.
reset_case
: >"$FIRST_FRAME"
printf '13\n' >"$HANDOFF_ACTION"
rm -f "$ORDER_LOG"
(
	reset_boot_attempts() {
		[ -s "$HANDOFF_ACTION" ]
		printf '%s\n' 0 >"$ATTEMPTS"
		printf '%s\n' reset >>"$ORDER_LOG"
	}
	run_content() { printf 'unexpected-content %s\n' "$*" >>"$ORDER_LOG"; }
	service_handoff_action
)
[ "$(cat "$ORDER_LOG")" = reset ]
[ "$(cat "$ATTEMPTS")" = 0 ]
[ ! -e "$HANDOFF_ACTION" ]

reset_case
: >"$FIRST_FRAME"
printf '12\n' >"$HANDOFF_ACTION"
rm -f "$ORDER_LOG"
if (
	reset_boot_attempts() { printf '%s\n' reset >>"$ORDER_LOG"; return 1; }
	dispatch_handoff_action() {
		printf '%s\n' dispatch >>"$ORDER_LOG"
		rm -f "$HANDOFF_ACTION"
	}
	service_handoff_action
); then
	printf '%s\n' 'failed completed-action reset reached dispatch' >&2
	exit 1
fi
[ "$(cat "$ORDER_LOG")" = reset ]
[ -s "$HANDOFF_ACTION" ]

# The ordinary systemd request is bounded as a client operation. Acceptance
# exits the supervisor; a client failure is logged and returns to the caller.
reset_case
SHUTDOWN_LOG=$STATE/shutdown.log
BOOT_ID=deadbeef
poweroff_client() { return 124; }
set +e
request_poweroff
POWEROFF_STATUS=$?
set -e
[ "$POWEROFF_STATUS" -eq 124 ]
grep -Fq 'Bird shutdown requested boot_id=deadbeef' "$SHUTDOWN_LOG"
grep -Fq 'Bird shutdown dispatch failed boot_id=deadbeef exit=124' \
	"$SHUTDOWN_LOG"
poweroff_client() { return 0; }
(request_poweroff)
grep -Fq 'Bird shutdown dispatch ready boot_id=deadbeef' "$SHUTDOWN_LOG"
grep -Fq 'systemctl --no-block start poweroff.target' "$SUPERVISOR"
grep -Fq 'systemctl --no-block start reboot.target' "$SUPERVISOR"
if grep -Eq 'systemctl --no-block (poweroff|reboot)$' "$SUPERVISOR"; then
	printf '%s\n' 'logind-routed systemctl verb returned' >&2
	exit 1
fi
if grep -q 'systemctl .*--force.*poweroff' "$SUPERVISOR"; then
	printf '%s\n' 'forced poweroff bypass returned' >&2
	exit 1
fi

# A crash guard's atomic state is the foreground lease. A restarted supervisor
# must remain in the gate until that state disappears, rather than repainting
# Bird while the guard is still reconciling a scope or compositor.
reset_case
MOCK_LEASE_PATH=$CONTENT_STATE_DIR/content-runner-test.state
: >"$MOCK_LEASE_PATH"
content_cleanup_pending
MOCK_LEASE_REMOVE_AFTER_SLEEP=3
wait_content_cleanup
[ "$SLEEP_CALLS" -eq 3 ]
[ ! -e "$MOCK_LEASE_PATH" ]
if content_cleanup_pending; then
	printf '%s\n' 'content cleanup gate stayed charged after lease removal' >&2
	exit 1
fi
ln -s missing-target "$CONTENT_STATE_DIR/content-runner-dangling.state"
if ! content_cleanup_pending; then
	printf '%s\n' 'dangling foreground lease was treated as absent' >&2
	exit 1
fi
rm -f "$CONTENT_STATE_DIR/content-runner-dangling.state"

# Marker wins: a live launcher plus a published marker commits the atomic zero
# and is accepted without consuming the health timeout.
reset_case
: >"$FIRST_FRAME"
mark_healthy "$MOCK_LAUNCHER_PID"
[ "$(cat "$ATTEMPTS")" = 0 ]
[ "$SLEEP_CALLS" -eq 0 ]
[ "$REBOOT_CALLS" -eq 0 ]
[ ! -e "$ATTEMPTS_TMP" ]
[ "$(sed -n '1p' "$SYNC_LOG")" = "$ATTEMPTS_TMP" ]
[ "$(sed -n '2p' "$SYNC_LOG")" = "$ATTEMPTS" ]
[ "$(sed -n '3p' "$SYNC_LOG")" = "${ATTEMPTS%/*}" ]

# Child exit wins even if a stale marker is already visible. The supervisor
# must not enter any of the 1,000 20-ms sleeps or reset the boot-attempt file.
reset_case
: >"$FIRST_FRAME"
MOCK_LAUNCHER_EXITED=1
if mark_healthy "$MOCK_LAUNCHER_PID"; then
	printf '%s\n' 'dead launcher incorrectly won the first-frame race' >&2
	exit 1
fi
[ "$HEALTH_REASON" = child-exit ]
[ "$(cat "$ATTEMPTS")" = 2 ]
[ "$SLEEP_CALLS" -eq 0 ]
[ "$REBOOT_CALLS" -eq 0 ]

classify_startup_failure "$HEALTH_REASON" 6
[ "$STARTUP_CLASS" = recoverable-input-wait ]
startup_backoff "$STARTUP_CLASS" 1
[ "$SLEEP_CALLS" -eq 1 ]

classify_startup_failure child-exit 4
[ "$STARTUP_CLASS" = fatal-framebuffer-format ]
classify_startup_failure first-frame-timeout 143
[ "$STARTUP_CLASS" = recoverable-timeout ]

# The file data and rename can both succeed while persistence of the directory
# entry fails. Exercise all directory-sync fallbacks and require a failed
# health result: a visible frame alone must not be reported as boot success.
reset_case
: >"$FIRST_FRAME"
SYNC_MODE=fail-directory
if mark_healthy "$MOCK_LAUNCHER_PID"; then
	printf '%s\n' 'directory-sync failure incorrectly reported healthy' >&2
	exit 1
fi
[ "$HEALTH_REASON" = attempt-reset-failed ]
[ "$(cat "$ATTEMPTS")" = 0 ]
[ ! -e "$ATTEMPTS_TMP" ]
[ "$SLEEP_CALLS" -eq 0 ]
[ "$REBOOT_CALLS" -eq 0 ]
[ "$(sed -n '1p' "$SYNC_LOG")" = "$ATTEMPTS_TMP" ]
[ "$(sed -n '2p' "$SYNC_LOG")" = "$ATTEMPTS" ]
[ "$(sed -n '3p' "$SYNC_LOG")" = "${ATTEMPTS%/*}" ]
[ "$(sed -n '4p' "$SYNC_LOG")" = "-f ${ATTEMPTS%/*}" ]
[ -z "$(sed -n '5p' "$SYNC_LOG")" ]

# An early marker is accepted only for the exact live PID/executable named by
# the initramfs. This is also the normal persistent-owner adoption path.
reset_case
: >"$FIRST_FRAME"
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
load_early_launcher
[ "$EARLY_LAUNCHER_PID" -eq "$MOCK_LAUNCHER_PID" ]
accept_early_frame "$EARLY_LAUNCHER_PID"
[ "$(cat "$ATTEMPTS")" = 0 ]
PIDWAIT=$PIDWAIT_EXIT_HELPER
adopt_early_launcher "$EARLY_LAUNCHER_PID"
[ ! -e "$EARLY_PID" ]
[ "$REBOOT_CALLS" -eq 0 ]

# A pidfd_open failure uses the same zombie-aware process-state primitive. It
# must leave the fallback loop as soon as the retained owner exits.
reset_case
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_ERROR_HELPER
MOCK_EXIT_AFTER_SLEEP=2
adopt_early_launcher "$MOCK_LAUNCHER_PID"
[ "$SLEEP_CALLS" -eq 2 ]
[ "$MOCK_LAUNCHER_EXITED" -eq 1 ]
[ ! -e "$EARLY_PID" ]

# switch_root can unlink the initramfs file while its mapped process survives.
# Linux's one exact " (deleted)" rendering remains the same trusted owner.
reset_case
: >"$FIRST_FRAME"
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
MOCK_LAUNCHER_EXE='/opt/bird/bird-launcher (deleted)'
load_early_launcher
accept_early_frame "$EARLY_LAUNCHER_PID"
[ "$(cat "$ATTEMPTS")" = 0 ]
[ "$EARLY_ACCEPT_REASON" = first-frame ]
[ "$REBOOT_CALLS" -eq 0 ]

# A marker published after the persistent-root supervisor starts still wins
# within the bounded health window and clears the charged boot attempt.
reset_case
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
load_early_launcher
MOCK_MARKER_AFTER_SLEEP=3
accept_early_frame "$EARLY_LAUNCHER_PID"
[ "$EARLY_ACCEPT_REASON" = first-frame ]
[ "$SLEEP_CALLS" -eq 3 ]
[ "$(cat "$ATTEMPTS")" = 0 ]
[ ! -s "$KILL_LOG" ]

# With no marker, owner exit wins promptly and falls through without signalling
# a process that has already gone away or modifying the attempt journal.
reset_case
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
load_early_launcher
MOCK_EXIT_AFTER_SLEEP=3
if accept_early_frame "$EARLY_LAUNCHER_PID"; then
	printf '%s\n' 'exited unready owner was adopted' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
[ "$EARLY_ACCEPT_REASON" = owner-exit ]
[ "$SLEEP_CALLS" -eq 3 ]
[ "$(cat "$ATTEMPTS")" = 2 ]
[ ! -s "$KILL_LOG" ]
archive_early_launcher
[ ! -e "$EARLY_PID" ]

# A live owner that never publishes readiness is bounded. Before final-root can
# own input, the exact timed-out process is retired TERM -> bounded wait -> KILL.
reset_case
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
load_early_launcher
if accept_early_frame "$EARLY_LAUNCHER_PID"; then
	printf '%s\n' 'unready early owner bypassed the readiness timeout' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
[ "$EARLY_ACCEPT_REASON" = first-frame-timeout ]
[ "$SLEEP_CALLS" -eq 1000 ]
[ "$(cat "$ATTEMPTS")" = 2 ]
retire_early_launcher "$EARLY_LAUNCHER_PID"
SIGNALS=$(tr '\n' ' ' <"$KILL_LOG" | sed 's/ $//')
[ "$SIGNALS" = 'TERM KILL' ]
[ "$MOCK_LAUNCHER_EXITED" -eq 1 ]
[ "$REBOOT_CALLS" -eq 0 ]
archive_early_launcher
[ ! -e "$EARLY_PID" ]

# A dead owner beats its stale marker before the boot-attempt transaction.
reset_case
: >"$FIRST_FRAME"
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
MOCK_LAUNCHER_EXITED=1
if load_early_launcher; then
	printf '%s\n' 'dead early PID was considered adoptable' >&2
	exit 1
fi
if accept_early_frame "$MOCK_LAUNCHER_PID"; then
	printf '%s\n' 'dead early PID cleared attempts through a stale marker' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
[ "$(cat "$ATTEMPTS")" = 2 ]
[ "$SLEEP_CALLS" -eq 0 ]
[ "$REBOOT_CALLS" -eq 0 ]

# Exit between the initial state read and executable validation also beats the
# marker. This covers the second liveness edge in early_launcher_adoptable.
reset_case
: >"$FIRST_FRAME"
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
MOCK_EXIT_ON_CHECK=2
if accept_early_frame "$MOCK_LAUNCHER_PID"; then
	printf '%s\n' 'early exit during identity validation cleared attempts' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
[ "$MOCK_LAUNCHER_CHECKS" -eq 2 ]
[ "$(cat "$ATTEMPTS")" = 2 ]
[ "$REBOOT_CALLS" -eq 0 ]

# PID text, pidwait availability and executable identity are all part of the
# adoption contract. Prefix/suffix matches must not pass the exact-path check.
reset_case
: >"$FIRST_FRAME"
printf '%s\n' invalid >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
if load_early_launcher; then
	printf '%s\n' 'malformed early PID was accepted' >&2
	exit 1
fi
[ "$(cat "$ATTEMPTS")" = 2 ]

printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_MISSING
if load_early_launcher; then
	printf '%s\n' 'early PID without pidfd adoption helper was accepted' >&2
	exit 1
fi
[ "$(cat "$ATTEMPTS")" = 2 ]

PIDWAIT=$PIDWAIT_HELPER
MOCK_LAUNCHER_EXE=/opt/bird/bird-launcher.old
if load_early_launcher; then
	printf '%s\n' 'near-match early executable was accepted' >&2
	exit 1
fi
if accept_early_frame "$MOCK_LAUNCHER_PID"; then
	printf '%s\n' 'near-match executable cleared attempts through a marker' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
[ "$(cat "$ATTEMPTS")" = 2 ]
[ "$REBOOT_CALLS" -eq 0 ]

reset_case
: >"$FIRST_FRAME"
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
MOCK_LAUNCHER_EXE='/opt/bird/bird-launcher (deleted) extra'
if load_early_launcher; then
	printf '%s\n' 'arbitrary deleted suffix was accepted' >&2
	exit 1
fi
if accept_early_frame "$MOCK_LAUNCHER_PID"; then
	printf '%s\n' 'arbitrary deleted suffix cleared attempts' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
[ "$(cat "$ATTEMPTS")" = 2 ]
[ "$REBOOT_CALLS" -eq 0 ]

# The early-adoption path has the same fail-closed reset rule and also leaves
# reboot policy to the bounded supervisor loop rather than rebooting directly.
reset_case
: >"$FIRST_FRAME"
printf '%s\n' "$MOCK_LAUNCHER_PID" >"$EARLY_PID"
PIDWAIT=$PIDWAIT_HELPER
SYNC_MODE=fail-directory
if accept_early_frame "$MOCK_LAUNCHER_PID"; then
	printf '%s\n' 'early frame accepted after directory-sync failure' >&2
	exit 1
else
	[ "$?" -eq 1 ]
fi
[ "$REBOOT_CALLS" -eq 0 ]

# Pin the outer-loop contract without executing its infinite production loop.
# Two local retries precede the only reboot call.
grep -q '^STARTUP_FAILURE_LIMIT=3$' "$SUPERVISOR"
grep -q '^RELEASE_ID=v6\.23$' "$SUPERVISOR"
grep -Fq 'boot-state/releases/$RELEASE_ID/attempts' "$SUPERVISOR"
[ "$(grep -Fc 'systemctl reboot --force' "$SUPERVISOR")" -eq 1 ]
LOAD_LINE=$(grep -nF 'if load_early_launcher; then' "$SUPERVISOR" | \
	command cut -d: -f1)
GATE_LINE=$(grep -nF 'wait_content_cleanup' "$SUPERVISOR" | tail -n 1 | \
	command cut -d: -f1)
ACCEPT_LINE=$(grep -nF 'if accept_early_frame "$EARLY_LAUNCHER_PID"; then' \
	"$SUPERVISOR" | command cut -d: -f1)
HANDOFF_SERVICE_LINE=$(grep -nF 'if ! service_handoff_action; then' \
	"$SUPERVISOR" | command cut -d: -f1)
[ "$(grep -Fc 'if ! service_handoff_action; then' "$SUPERVISOR")" -eq 1 ]
[ "$GATE_LINE" -lt "$LOAD_LINE" ]
[ "$LOAD_LINE" -lt "$ACCEPT_LINE" ]
[ "$ACCEPT_LINE" -lt "$HANDOFF_SERVICE_LINE" ]
grep -Fq 'accept_completed_early_action || return 1' "$SUPERVISOR"
grep -Fq 'dispatch_handoff_action' "$SUPERVISOR"
grep -Fq 'completed early action not accepted; supervisor retry required' \
	"$SUPERVISOR"
grep -Fq '10) consume_handoff_action && run_content "$REQUEST" ;;' \
	"$SUPERVISOR"
grep -Fq '12) consume_handoff_action && run_content --portmaster ;;' \
	"$SUPERVISOR"
grep -Fq '13) consume_handoff_action ;;' "$SUPERVISOR"
grep -Fq '14) consume_handoff_action && request_reboot ;;' "$SUPERVISOR"
grep -Fq '10|11|12|13|14) return 0 ;;' "$SUPERVISOR"
grep -Fq "printf 'bird launcher user-requested reload\\n'" "$SUPERVISOR"
[ "$(grep -Fc '"$RUNNER" "$@"' "$SUPERVISOR")" -eq 1 ]
if grep -Fq -- '--rocknix' "$SUPERVISOR"; then
	printf '%s\n' 'temporary stock frontend dispatch remained in supervisor' >&2
	exit 1
fi
grep -Fq '[ "$EARLY_ACCEPT_REASON" = first-frame-timeout ]' "$SUPERVISOR"
grep -Fq 'retire_early_launcher "$EARLY_LAUNCHER_PID"' "$SUPERVISOR"
grep -Fq 'if ! "$PIDWAIT" "$pid"; then' "$SUPERVISOR"
if grep -Fq '"$PIDWAIT" "$pid" &' "$SUPERVISOR"; then
	printf '%s\n' 'cancellable background pidwait returned' >&2
	exit 1
fi
grep -Fq 'while ! launcher_exited "$pid"; do usleep 20000; done' \
	"$SUPERVISOR"
if grep -Fq 'while kill -0 "$pid"' "$SUPERVISOR"; then
	printf '%s\n' 'zombie-blind early adoption loop returned' >&2
	exit 1
fi
INCREMENT_LINE=$(grep -nF 'STARTUP_FAILURES=$((STARTUP_FAILURES + 1))' \
	"$SUPERVISOR" | command cut -d: -f1)
LIMIT_LINE=$(grep -nF \
	'if [ "$STARTUP_FAILURES" -lt "$STARTUP_FAILURE_LIMIT" ]; then' \
	"$SUPERVISOR" | command cut -d: -f1)
REBOOT_LINE=$(grep -nF 'systemctl reboot --force' "$SUPERVISOR" | \
	command cut -d: -f1)
[ "$INCREMENT_LINE" -lt "$LIMIT_LINE" ]
[ "$LIMIT_LINE" -lt "$REBOOT_LINE" ]

bash -n "$SUPERVISOR"
printf '%s\n' 'stock-root supervisor tests: PASS'
