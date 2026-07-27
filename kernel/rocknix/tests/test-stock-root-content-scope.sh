#!/bin/sh
# Host-side fault injection for birdOS's foreground scope exit contract.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
RUNNER=$ROOT/kernel/rocknix/stock-root/run-content.sh
EXIT_HELPER=$ROOT/kernel/rocknix/stock-root/bird-fixed-control-exit.sh
CONTRACT_PRODUCER=$ROOT/kernel/rocknix/stock-root/999-export
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-content-scope.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

wait_pid_bounded() {
	WAIT_TARGET=$1
	WAIT_SECONDS=$2
	WAIT_LABEL=$3
	WAIT_TIMEOUT=$TMP/wait-timeout-$WAIT_TARGET
	rm -f "$WAIT_TIMEOUT"
	(
		sleep "$WAIT_SECONDS"
		if kill -0 "$WAIT_TARGET" 2>/dev/null; then
			: >"$WAIT_TIMEOUT"
			kill -KILL "$WAIT_TARGET" 2>/dev/null || :
		fi
	) &
	WAIT_WATCHDOG=$!
	if wait "$WAIT_TARGET"; then WAIT_STATUS=0; else WAIT_STATUS=$?; fi
	kill "$WAIT_WATCHDOG" 2>/dev/null || :
	wait "$WAIT_WATCHDOG" 2>/dev/null || :
	if [ -e "$WAIT_TIMEOUT" ]; then
		printf 'timed out waiting for %s\n' "$WAIT_LABEL" >&2
		return 124
	fi
	return "$WAIT_STATUS"
}

mkdir -p "$TMP/bin" "$TMP/state"

cat >"$TMP/bin/usleep" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$TMP/bin/flock" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$TMP/bin/systemd-run" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$TMP/flock-probe.py" <<'PY'
#!/usr/bin/env python3
import fcntl
import sys

if sys.argv[1] == "acquire-fd":
    fcntl.flock(int(sys.argv[2]), fcntl.LOCK_EX)
else:
    with open(sys.argv[2], "a+") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit(1)
PY

cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/sh
set -eu
STATE=$MOCK_STATE_DIR
case "$1" in
	show)
		PROPERTY=
		for ARG in "$@"; do
			case "$ARG" in --property=*) PROPERTY=${ARG#--property=} ;; esac
		done
		[ "$(cat "$STATE/show-mode" 2>/dev/null || printf ok)" = ok ] || exit 1
		case "$PROPERTY" in
			InvocationID)
				COUNT=$(cat "$STATE/invocation-count" 2>/dev/null || printf 0)
				COUNT=$((COUNT + 1))
				printf '%s\n' "$COUNT" >"$STATE/invocation-count"
				AFTER=$(cat "$STATE/replace-after" 2>/dev/null || printf 0)
				if [ "$AFTER" -gt 0 ] && [ "$COUNT" -gt "$AFTER" ]; then
					cat "$STATE/replacement-invocation"
				else
					cat "$STATE/invocation"
				fi
				;;
			ActiveState) cat "$STATE/active" ;;
			ControlGroup) printf '%s\n' /bird-test.scope ;;
			LoadState) cat "$STATE/load-state" ;;
			*) exit 1 ;;
		esac
		;;
	list-units)
		[ "$(cat "$STATE/list-mode" 2>/dev/null || printf absent)" != fail ] || exit 1
		if [ "$(cat "$STATE/list-mode" 2>/dev/null || printf absent)" = present ]; then
			printf '%s\n' 'bird-content-11111111-42-100.scope loaded active running test'
		fi
		;;
	kill)
		SIGNAL=
		for ARG in "$@"; do
			case "$ARG" in --signal=*) SIGNAL=${ARG#--signal=} ;; esac
		done
		printf '%s\n' "$SIGNAL" >>"$STATE/signals"
		case "$SIGNAL:$(cat "$STATE/mode")" in
			TERM:term-exits|KILL:*) printf '%s\n' inactive >"$STATE/active" ;;
		esac
		;;
	*) exit 1 ;;
esac
EOF

chmod 0755 "$TMP/bin/systemctl" "$TMP/bin/usleep" "$TMP/bin/flock" \
	"$TMP/bin/systemd-run"

assert_survivor_does_not_hold_fd8() {
	LOCK_FILE=$TMP/session-fd.lock
	READY_FILE=$TMP/session-fd.ready
	CHILD_FILE=$TMP/session-fd.child
	(
		exec 8>"$LOCK_FILE"
		python3 "$TMP/flock-probe.py" acquire-fd 8
		sleep 30 8>&- 9>&- &
		printf '%s\n' "$!" >"$CHILD_FILE"
		: >"$READY_FILE"
		while :; do sleep 1 8>&- 9>&-; done
	) &
	LOCK_PARENT=$!
	READY_COUNT=0
	while { [ ! -s "$CHILD_FILE" ] || [ ! -e "$READY_FILE" ]; } && \
		[ "$READY_COUNT" -lt 500 ]; do
		READY_COUNT=$((READY_COUNT + 1))
		sleep 0.01
	done
	if [ ! -s "$CHILD_FILE" ] || [ ! -e "$READY_FILE" ]; then
		kill -KILL "$LOCK_PARENT" 2>/dev/null || :
		wait "$LOCK_PARENT" 2>/dev/null || :
		printf '%s\n' 'fd8 fixture readiness timed out' >&2
		return 1
	fi
	LOCK_CHILD=$(cat "$CHILD_FILE")
	if python3 "$TMP/flock-probe.py" try-path "$LOCK_FILE"; then
		printf '%s\n' 'fd8 test parent did not hold its session lock' >&2
		kill "$LOCK_PARENT" "$LOCK_CHILD" 2>/dev/null || :
		exit 1
	fi
	kill -KILL "$LOCK_PARENT"
	wait "$LOCK_PARENT" 2>/dev/null || :
	kill -0 "$LOCK_CHILD"
	if ! python3 "$TMP/flock-probe.py" try-path "$LOCK_FILE"; then
		printf '%s\n' 'surviving child inherited fd8 session lock' >&2
		kill "$LOCK_CHILD" 2>/dev/null || :
		exit 1
	fi
	kill "$LOCK_CHILD" 2>/dev/null || :
}

assert_survivor_does_not_hold_fd9() {
	LOCK_FILE=$TMP/resource-fd.lock
	READY_FILE=$TMP/resource-fd.ready
	CHILD_FILE=$TMP/resource-fd.child
	(
		exec 9>"$LOCK_FILE"
		python3 "$TMP/flock-probe.py" acquire-fd 9
		sleep 30 8>&- 9>&- &
		printf '%s\n' "$!" >"$CHILD_FILE"
		: >"$READY_FILE"
		while :; do sleep 1 8>&- 9>&-; done
	) &
	LOCK_PARENT=$!
	READY_COUNT=0
	while { [ ! -s "$CHILD_FILE" ] || [ ! -e "$READY_FILE" ]; } && \
		[ "$READY_COUNT" -lt 500 ]; do
		READY_COUNT=$((READY_COUNT + 1))
		sleep 0.01
	done
	if [ ! -s "$CHILD_FILE" ] || [ ! -e "$READY_FILE" ]; then
		kill -KILL "$LOCK_PARENT" 2>/dev/null || :
		wait "$LOCK_PARENT" 2>/dev/null || :
		printf '%s\n' 'fd9 fixture readiness timed out' >&2
		return 1
	fi
	LOCK_CHILD=$(cat "$CHILD_FILE")
	if python3 "$TMP/flock-probe.py" try-path "$LOCK_FILE"; then
		printf '%s\n' 'fd9 test parent did not hold its resource lock' >&2
		kill "$LOCK_PARENT" "$LOCK_CHILD" 2>/dev/null || :
		exit 1
	fi
	kill -KILL "$LOCK_PARENT"
	wait "$LOCK_PARENT" 2>/dev/null || :
	kill -0 "$LOCK_CHILD"
	if ! python3 "$TMP/flock-probe.py" try-path "$LOCK_FILE"; then
		printf '%s\n' 'surviving child inherited fd9 resource lock' >&2
		kill "$LOCK_CHILD" 2>/dev/null || :
		exit 1
	fi
	kill "$LOCK_CHILD" 2>/dev/null || :
}

assert_survivor_does_not_hold_fd8
assert_survivor_does_not_hold_fd9

# The cleanup guard is a single-quoted program passed to `sh -c`, so parsing the
# outer runner cannot detect syntax errors inside it. Extract the exact payload,
# parse it independently, and execute its no-state early-exit path.
GUARD_BODY=$TMP/embedded-content-guard.sh
python3 - "$RUNNER" "$GUARD_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start_marker = "-- /bin/sh -c '\n"
end_marker = "\n\t' bird-content-guard "
start = source.index(start_marker) + len(start_marker)
end = source.index(end_marker, start)
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
[ -s "$GUARD_BODY" ]
sh -n "$GUARD_BODY"
GUARD_SOURCE=$(cat "$GUARD_BODY")
GUARD_PROC=$TMP/guard-proc
mkdir -p "$GUARD_PROC/sys/kernel/random"
printf '%s\n' host-test-boot >"$GUARD_PROC/sys/kernel/random/boot_id"
/bin/sh -c "$GUARD_SOURCE" bird-content-guard \
	/usr/bin/true "$$" "$TMP/missing-guard-state" 0 fake-boot \
	/usr/bin/true /usr/bin/true "$TMP/guard.log" "$TMP/exact.session" \
	"$TMP/global.session" token "$TMP/resource.lock" "$TMP/sway.owner" \
	"$TMP/network.owner" "$TMP/sway.sock" "$TMP/no-scope.start" \
	"$TMP/no-scope.ready" "$TMP/no-scope.cancel" "$GUARD_PROC"

# Model the SIGKILL edge with the real embedded guard body. The pid waiter is
# held until the assertion has observed an armed foreground state; only after
# the simulated parent-death edge may the guard remove that state, which is the
# supervisor's permission to resume the launcher.
GUARD_TEST_BODY=$TMP/embedded-content-guard-host.sh
GUARD_RELEASE=$TMP/guard-release
CRASH_STATE=$TMP/content-runner-crash.state
CRASH_TOKEN=crash-token
cp "$GUARD_BODY" "$GUARD_TEST_BODY"
sh -n "$GUARD_TEST_BODY"
cat >"$TMP/pidwait-gate" <<'EOF'
#!/bin/sh
COUNT=0
while [ ! -e "$BIRD_TEST_GUARD_RELEASE" ] && [ "$COUNT" -lt 1000 ]; do
	COUNT=$((COUNT + 1))
	sleep 0.01
done
[ -e "$BIRD_TEST_GUARD_RELEASE" ]
EOF
chmod 0755 "$TMP/pidwait-gate"
cat >"$CRASH_STATE" <<EOF
version=1
armed=1
session_token=$CRASH_TOKEN
boot_id=host-test-boot
runner_pid=$$
runner_start_ticks=0
scope_expected=0
scope_unit=
scope_invocation=pending
sway_owned=0
network_owned=0
EOF
GUARD_TEST_SOURCE=$(cat "$GUARD_TEST_BODY")
PATH="$TMP/bin:$PATH" BIRD_TEST_GUARD_RELEASE="$GUARD_RELEASE" \
	/bin/sh -c "$GUARD_TEST_SOURCE" bird-content-guard \
	"$TMP/pidwait-gate" "$$" "$CRASH_STATE" 0 host-test-boot \
	/usr/bin/true /usr/bin/true "$TMP/crash-guard.log" \
	"$TMP/crash-exact.session" "$TMP/crash-global.session" \
	"$CRASH_TOKEN" "$TMP/crash-resource.lock" "$TMP/crash-sway.owner" \
	"$TMP/crash-network.owner" "$TMP/crash-sway.sock" \
	"$TMP/crash-scope.start" "$TMP/crash-scope.ready" \
	"$TMP/crash-scope.cancel" "$GUARD_PROC" &
CRASH_GUARD_PID=$!
sleep 0.05
CRASH_GUARD_PRECHECK=0
[ -e "$CRASH_STATE" ] || CRASH_GUARD_PRECHECK=1
kill -0 "$CRASH_GUARD_PID" 2>/dev/null || CRASH_GUARD_PRECHECK=1
: >"$GUARD_RELEASE"
wait_pid_bounded "$CRASH_GUARD_PID" 10 crash-guard
[ "$CRASH_GUARD_PRECHECK" -eq 0 ]
[ ! -e "$CRASH_STATE" ]

# Kill the real gated-bootstrap control flow after its exact child identity is
# atomically published but before the gate is released. The detached guard must
# stop/wait that bootstrap, require stable manager absence, remove every gate
# artifact (including READY temporaries), and only then drop the foreground
# lease. The mocked systemd-run must never be contacted.
SCOPE_START_BODY=$TMP/scope-start-functions.sh
python3 - "$RUNNER" "$SCOPE_START_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
parts = []
for start_marker, end_marker in (
    ("process_stat_tail() {", "\nstop_and_reap_scope_runner() {"),
    ("stop_and_reap_scope_runner() {", "\nterminate_scope_until_gone() {"),
    ("start_scope_runner() {", "\nrun_managed() {"),
):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    parts.append(source[start:end])
body = "\n\n".join(parts).replace(
    "/usr/bin/systemd-run", '"$FAKE_SYSTEMD_RUN"')
Path(sys.argv[2]).write_text(body + "\n")
PY
bash -n "$SCOPE_START_BODY"

# READY is a canonical one-line handshake. EOF without its newline, an empty or
# different marker, and any trailing record must all fail closed.
READY_CASE=$TMP/ready-parser
mkdir -p "$READY_CASE"
cat >"$READY_CASE/harness.sh" <<'EOF'
#!/bin/bash
set -u
. "$1"
SCOPE_START_READY=$2
MODE=$3
case "$MODE" in
	valid) printf 'ready\n' >"$SCOPE_START_READY" ;;
	unterminated) printf ready >"$SCOPE_START_READY" ;;
	extra) printf 'ready\nextra\n' >"$SCOPE_START_READY" ;;
	empty) : >"$SCOPE_START_READY" ;;
	malformed) printf 'not-ready\n' >"$SCOPE_START_READY" ;;
esac
scope_start_ready_valid
EOF
chmod 0755 "$READY_CASE/harness.sh"
"$READY_CASE/harness.sh" "$SCOPE_START_BODY" "$READY_CASE/ready" valid
for READY_MODE in unterminated extra empty malformed; do
	if "$READY_CASE/harness.sh" "$SCOPE_START_BODY" "$READY_CASE/ready" \
		"$READY_MODE"; then
		printf 'scope READY accepted invalid mode=%s\n' "$READY_MODE" >&2
		exit 1
	fi
done

# Linux stat field 2 may contain spaces and right parentheses. Exact process
# identity must strip through the final `) ` before reading state/starttime.
STAT_CASE=$TMP/stat-parser
mkdir -p "$STAT_CASE/proc/4242"
printf '%s\n' \
	'4242 (bird helper ) with spaces) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 987654 20' \
	>"$STAT_CASE/proc/4242/stat"
cat >"$STAT_CASE/harness.sh" <<'EOF'
#!/bin/bash
set -u
. "$1"
PROCESS_PROC_ROOT=$2
[ "$(process_start_ticks 4242)" = 987654 ]
process_pid_running 4242
process_identity_alive 4242 987654
sed 's/) S/) Z/' "$PROCESS_PROC_ROOT/4242/stat" \
	>"$PROCESS_PROC_ROOT/4242/stat.next"
mv -f "$PROCESS_PROC_ROOT/4242/stat.next" "$PROCESS_PROC_ROOT/4242/stat"
if process_pid_running 4242; then exit 1; fi
EOF
chmod 0755 "$STAT_CASE/harness.sh"
"$STAT_CASE/harness.sh" "$SCOPE_START_BODY" "$STAT_CASE/proc"

SPAWN_CASE=$TMP/spawn-kill
mkdir -p "$SPAWN_CASE"
cat >"$SPAWN_CASE/fake-systemd-run" <<'EOF'
#!/bin/sh
: >"$BIRD_TEST_SYSTEMD_CONTACTED"
exit 0
EOF
cat >"$SPAWN_CASE/fake-pidwait" <<'EOF'
#!/bin/sh
process_alive() {
	STATE=$(ps -o stat= -p "$1" 2>/dev/null | awk 'NR == 1 { print $1 }')
	case "$STATE" in ''|Z*) return 1 ;; *) return 0 ;; esac
}
if [ "${1:-}" = --terminate ]; then
	printf 'terminate %s %s\n' "$2" "$3" >>"$BIRD_TEST_GUARD_EVENTS"
	[ "$3" = 777 ] || exit 7
	if ! kill -TERM "$2" 2>/dev/null; then
		printf '%s\n' wrapper-stopped >>"$BIRD_TEST_GUARD_EVENTS"
		exit 0
	fi
	COUNT=0
	while process_alive "$2" && [ "$COUNT" -lt 100 ]; do
		COUNT=$((COUNT + 1))
		sleep 0.01
	done
	process_alive "$2" && kill -KILL "$2" 2>/dev/null || :
	COUNT=0
	while process_alive "$2" && [ "$COUNT" -lt 100 ]; do
		COUNT=$((COUNT + 1))
		sleep 0.01
	done
	process_alive "$2" && exit 8
	printf '%s\n' wrapper-stopped >>"$BIRD_TEST_GUARD_EVENTS"
	exit 0
fi
COUNT=0
while process_alive "$1" && [ "$COUNT" -lt 1000 ]; do
	COUNT=$((COUNT + 1))
	sleep 0.01
done
process_alive "$1" && exit 1
EOF
cat >"$SPAWN_CASE/fake-exit" <<'EOF'
#!/bin/sh
if ! grep -q '^wrapper-stopped$' "$BIRD_TEST_GUARD_EVENTS"; then
	printf '%s\n' helper-before-wrapper-gone >>"$BIRD_TEST_GUARD_EVENTS"
	exit 2
fi
printf 'helper stable=%s target=%s\n' \
	"${BIRD_STABLE_NOT_FOUND_COUNT:-missing}" "$BIRD_SESSION_PID" \
	>>"$BIRD_TEST_GUARD_EVENTS"
exit 0
EOF
chmod 0755 "$SPAWN_CASE/fake-systemd-run" "$SPAWN_CASE/fake-pidwait" \
	"$SPAWN_CASE/fake-exit"
cat >"$SPAWN_CASE/runner-harness.sh" <<'EOF'
#!/bin/bash
set -u
. "$1"
CASE_DIR=$2
RUNNER_STATE=$CASE_DIR/runner.state
PUBLISHED=$CASE_DIR/published
FAKE_SYSTEMD_RUN=$CASE_DIR/fake-systemd-run
RUNNER_START_TICKS=555
SESSION_TOKEN=spawn-kill
SCOPE_UNIT=bird-content-spawn-kill.scope
SCOPE_INVOCATION=
SCOPE_RUNNER_PID=
SCOPE_RUNNER_START_TICKS=
SCOPE_EXPECTED=1
SWAY_OWNED=0
PORTMASTER_NETWORK=0
SCOPE_START_GATE=$CASE_DIR/scope.start
SCOPE_START_READY=$CASE_DIR/scope.ready
SCOPE_START_CANCEL=$CASE_DIR/scope.cancel

process_start_ticks() { printf '%s\n' 777; }
process_pid_running() { kill -0 "$1" 2>/dev/null; }
process_identity_alive() {
	if [ "$1" = "$$" ]; then
		[ "$2" = 555 ] || return 1
	else
		[ "$2" = 777 ] || return 1
	fi
	kill -0 "$1" 2>/dev/null
}
usleep() { sleep 0.01; }
publish_runner_state() {
	TMP=$RUNNER_STATE.tmp.$$
	{
		printf '%s\n' version=1 armed=1 session_token=spawn-kill \
			boot_id=host-test-boot
		printf 'runner_pid=%s\n' "$$"
		printf '%s\n' runner_start_ticks=555 scope_expected=1 \
			scope_unit=bird-content-spawn-kill.scope \
			scope_invocation=pending
		printf 'scope_runner_pid=%s\n' "$SCOPE_RUNNER_PID"
		printf 'scope_runner_start_ticks=%s\n' \
			"$SCOPE_RUNNER_START_TICKS"
		printf '%s\n' sway_owned=0 network_owned=0
	} >"$TMP" && mv -f "$TMP" "$RUNNER_STATE"
	: >"$PUBLISHED"
	while :; do sleep 1; done
}
start_scope_runner /usr/bin/true
EOF
chmod 0755 "$SPAWN_CASE/runner-harness.sh"
BIRD_TEST_SYSTEMD_CONTACTED=$SPAWN_CASE/systemd-contacted \
	"$SPAWN_CASE/runner-harness.sh" "$SCOPE_START_BODY" "$SPAWN_CASE" \
	</dev/null >"$SPAWN_CASE/runner.log" 2>&1 &
SPAWN_PARENT=$!
SPAWN_WAIT=0
while [ ! -e "$SPAWN_CASE/published" ] && \
	kill -0 "$SPAWN_PARENT" 2>/dev/null && [ "$SPAWN_WAIT" -lt 500 ]; do
	SPAWN_WAIT=$((SPAWN_WAIT + 1))
	sleep 0.01
done
if [ ! -e "$SPAWN_CASE/published" ]; then
	cat "$SPAWN_CASE/runner.log" >&2
	printf '%s\n' 'gated bootstrap did not publish its exact identity' >&2
	kill -KILL "$SPAWN_PARENT" 2>/dev/null || :
	wait "$SPAWN_PARENT" 2>/dev/null || :
	exit 1
fi
SPAWN_WRAPPER=$(sed -n 's/^scope_runner_pid=//p' "$SPAWN_CASE/runner.state")
case "$SPAWN_WRAPPER" in ''|*[!0-9]*) exit 1 ;; esac
kill -0 "$SPAWN_WRAPPER"
[ ! -e "$SPAWN_CASE/scope.start" ]
[ ! -e "$SPAWN_CASE/systemd-contacted" ]
: >"$SPAWN_CASE/events"
GUARD_TEST_SOURCE=$(cat "$GUARD_TEST_BODY")
BIRD_TEST_GUARD_EVENTS=$SPAWN_CASE/events \
BIRD_TEST_SPAWN_STATE=$SPAWN_CASE/runner.state \
	PATH="$TMP/bin:$PATH" \
	/bin/sh -c "$GUARD_TEST_SOURCE" bird-content-guard \
	"$SPAWN_CASE/fake-pidwait" "$SPAWN_PARENT" \
	"$SPAWN_CASE/runner.state" 555 host-test-boot \
	"$SPAWN_CASE/fake-exit" /usr/bin/true "$SPAWN_CASE/guard.log" \
	"$SPAWN_CASE/exact.session" "$SPAWN_CASE/global.session" spawn-kill \
	"$SPAWN_CASE/resource.lock" "$SPAWN_CASE/sway.owner" \
	"$SPAWN_CASE/network.owner" "$SPAWN_CASE/sway.sock" \
	"$SPAWN_CASE/scope.start" "$SPAWN_CASE/scope.ready" \
	"$SPAWN_CASE/scope.cancel" "$GUARD_PROC" &
SPAWN_GUARD=$!
sleep 0.05
kill -KILL "$SPAWN_PARENT"
wait "$SPAWN_PARENT" 2>/dev/null || :
if ! wait_pid_bounded "$SPAWN_GUARD" 10 gated-bootstrap-guard; then
	cat "$SPAWN_CASE/events" >&2 || :
	cat "$SPAWN_CASE/guard.log" >&2 || :
	exit 1
fi
[ ! -e "$SPAWN_CASE/runner.state" ]
[ ! -e "$SPAWN_CASE/systemd-contacted" ]
if find "$SPAWN_CASE" -maxdepth 1 \( -name 'scope.start' -o \
	-name 'scope.ready' -o -name 'scope.cancel' -o \
	-name 'scope.ready.tmp.*' \) | grep -q .; then
	printf '%s\n' 'scope bootstrap artifacts survived SIGKILL recovery' >&2
	exit 1
fi
grep -q '^terminate ' "$SPAWN_CASE/events"
grep -q '^helper stable=20 ' "$SPAWN_CASE/events"
if grep -q '^helper-before-wrapper-gone$' "$SPAWN_CASE/events"; then
	printf '%s\n' 'guard reconciled scope before bootstrap termination' >&2
	exit 1
fi

# Drive the real wait_for_scope_registration -> run_managed branches with a
# mocked manager that remains unknown. Both live-wrapper status 2 and
# exited-wrapper status 3 must remain blocked until the fourth, confirmed
# scope-gone observation.
RECONCILE_BODY=$TMP/registration-reconcile.sh
python3 - "$RUNNER" "$RECONCILE_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("wait_for_scope_registration() {")
end = source.index("\nrocknix_tuple() {", start)
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
sh -n "$RECONCILE_BODY"
cat >"$TMP/term-resistant-wrapper.py" <<'PY'
#!/usr/bin/env python3
from pathlib import Path
import signal
import sys
import time

events = Path(sys.argv[1])
ready = Path(sys.argv[2])

def on_term(_signum, _frame):
    with events.open("a") as stream:
        stream.write("late-registration-attempt\n")

signal.signal(signal.SIGTERM, on_term)
ready.touch()
while True:
    time.sleep(0.01)
PY
cat >"$TMP/reconcile-harness.sh" <<'EOF'
#!/bin/sh
set -eu
. "$1"
REGISTRATION_STATUS=$2
CASE_DIR=$3
EVENTS=$CASE_DIR/events
ATTEMPTS=$CASE_DIR/attempts
: >"$EVENTS"
printf '%s\n' 0 >"$ATTEMPTS"

session_unlock() { printf '%s\n' session-unlocked >>"$EVENTS"; }
usleep() { sleep 0.002; }
session_lock() { printf '%s\n' session-locked >>"$EVENTS"; }
publish_runner_state() { :; }
scope_metadata_matches() { return 0; }
discard_unlaunched_metadata() { return 0; }
write_scope_metadata() { return 0; }
scope_query_property() {
	SCOPE_QUERY_RESULT=unknown
	SCOPE_QUERY_VALUE=
}
runner_process_alive() {
	[ "$REGISTRATION_STATUS" -eq 2 ]
}
process_identity_alive() {
	kill -0 "$1" 2>/dev/null
}
terminate_scope() {
	if kill -0 "$ORIGINAL_WRAPPER_PID" 2>/dev/null; then
		printf '%s\n' scope-query-before-wrapper-reaped >>"$EVENTS"
		exit 1
	fi
	COUNT=$(cat "$ATTEMPTS")
	COUNT=$((COUNT + 1))
	printf '%s\n' "$COUNT" >"$ATTEMPTS"
	printf 'scope-attempt-%s\n' "$COUNT" >>"$EVENTS"
	[ "$COUNT" -ge 4 ] || return 1
	printf '%s\n' scope-gone >>"$EVENTS"
	SCOPE_RUNNER_PID=
	return 0
}

start_scope_runner() {
	if [ "$REGISTRATION_STATUS" -eq 2 ]; then
		WRAPPER_READY=$CASE_DIR/wrapper.ready
		python3 "${CASE_DIR%/*}/term-resistant-wrapper.py" \
			"$EVENTS" "$WRAPPER_READY" &
		SCOPE_RUNNER_PID=$!
		WRAPPER_READY_COUNT=0
		while [ ! -e "$WRAPPER_READY" ] && \
			[ "$WRAPPER_READY_COUNT" -lt 500 ]; do
			WRAPPER_READY_COUNT=$((WRAPPER_READY_COUNT + 1))
			sleep 0.01
		done
		if [ ! -e "$WRAPPER_READY" ]; then
			kill -KILL "$SCOPE_RUNNER_PID" 2>/dev/null || :
			wait "$SCOPE_RUNNER_PID" 2>/dev/null || :
			printf '%s\n' 'registration wrapper readiness timed out' >&2
			exit 1
		fi
	else
		( exit 0 ) &
		SCOPE_RUNNER_PID=$!
	fi
	ORIGINAL_WRAPPER_PID=$SCOPE_RUNNER_PID
	SCOPE_RUNNER_START_TICKS=test-start
}

BOOT_ID=11111111
BOOT_ID_FULL=11111111-2222-3333-4444-555555555555
SESSION_TOKEN=test-session
SESSION_RECORD=$CASE_DIR/exact.session
SESSION_PID=$CASE_DIR/global.session
RUNNER_STATE=$CASE_DIR/runner.state
SCOPE_UNIT=
SCOPE_INVOCATION=
SCOPE_CONTROL_GROUP=
SCOPE_RUNNER_PID=
SCOPE_RUNNER_START_TICKS=
SCOPE_START_GATE=$CASE_DIR/scope.start
SCOPE_START_READY=$CASE_DIR/scope.ready
SCOPE_START_CANCEL=$CASE_DIR/scope.cancel
SCOPE_EXPECTED=0
if run_managed /usr/bin/true; then
	printf '%s\n' 'run_managed unexpectedly returned success' >&2
	exit 1
fi
printf '%s\n' runner-returned >>"$EVENTS"
[ "$(cat "$ATTEMPTS")" -eq 4 ]
[ "$(tail -n 2 "$EVENTS" | tr '\n' ' ')" = 'scope-gone runner-returned ' ]
if [ "$REGISTRATION_STATUS" -eq 2 ]; then
	grep -q '^late-registration-attempt$' "$EVENTS"
	LATE_LINE=$(grep -n '^late-registration-attempt$' "$EVENTS" | cut -d: -f1)
	QUERY_LINE=$(grep -n '^scope-attempt-1$' "$EVENTS" | cut -d: -f1)
	[ "$LATE_LINE" -lt "$QUERY_LINE" ]
fi
EOF
chmod 0755 "$TMP/reconcile-harness.sh"
for REGISTRATION_STATUS in 2 3; do
	CASE_DIR=$TMP/reconcile-$REGISTRATION_STATUS
	mkdir -p "$CASE_DIR"
	PATH="$TMP/bin:$PATH" "$TMP/reconcile-harness.sh" \
		"$RECONCILE_BODY" "$REGISTRATION_STATUS" "$CASE_DIR" \
		>"$CASE_DIR/harness.log" 2>&1
done

cat >"$TMP/resource-release-harness.sh" <<'EOF'
#!/bin/sh
set -eu
. "$1"
CASE_DIR=$2
EVENTS=$CASE_DIR/events
SWAY_COUNT=$CASE_DIR/sway-count
NETWORK_COUNT=$CASE_DIR/network-count
: >"$EVENTS"
printf '%s\n' 0 >"$SWAY_COUNT"
printf '%s\n' 0 >"$NETWORK_COUNT"
SWAY_OWNED=1
PORTMASTER_NETWORK=1
usleep() { :; }
stop_sway() {
	COUNT=$(cat "$SWAY_COUNT")
	COUNT=$((COUNT + 1))
	printf '%s\n' "$COUNT" >"$SWAY_COUNT"
	printf 'sway-attempt-%s\n' "$COUNT" >>"$EVENTS"
	[ "$COUNT" -ge 3 ] || return 1
	SWAY_OWNED=0
}
stop_portmaster_network() {
	COUNT=$(cat "$NETWORK_COUNT")
	COUNT=$((COUNT + 1))
	printf '%s\n' "$COUNT" >"$NETWORK_COUNT"
	printf 'network-attempt-%s\n' "$COUNT" >>"$EVENTS"
	[ "$COUNT" -ge 2 ] || return 1
	PORTMASTER_NETWORK=0
}
release_owned_resources_until_done
printf '%s\n' resources-released >>"$EVENTS"
[ "$(cat "$SWAY_COUNT")" -eq 3 ]
[ "$(cat "$NETWORK_COUNT")" -eq 2 ]
[ "$SWAY_OWNED" -eq 0 ]
[ "$PORTMASTER_NETWORK" -eq 0 ]
[ "$(tail -n 1 "$EVENTS")" = resources-released ]
[ "$(grep -n '^network-attempt-1$' "$EVENTS" | cut -d: -f1)" -gt \
	"$(grep -n '^sway-attempt-3$' "$EVENTS" | cut -d: -f1)" ]
EOF
chmod 0755 "$TMP/resource-release-harness.sh"
RESOURCE_CASE=$TMP/resource-release
mkdir -p "$RESOURCE_CASE"
"$TMP/resource-release-harness.sh" "$RECONCILE_BODY" "$RESOURCE_CASE" \
	>"$RESOURCE_CASE/harness.log" 2>&1

# Exercise the real owner-token transfer branches. An older cleanup retries its
# own failures, but must immediately release local ownership without stopping a
# newer session's Sway or network resources.
TRANSFER_BODY=$TMP/resource-transfer-functions.sh
python3 - "$RUNNER" "$TRANSFER_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
parts = []
for start_marker, end_marker in (
    ("owner_relation() {", "\nclaim_owner() {"),
    ("stop_sway() {", "\ninstall_mpv_input_policy() {"),
    ("stop_portmaster_network() {", "\nrun_selected() {"),
):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    parts.append(source[start:end])
Path(sys.argv[2]).write_text("\n\n".join(parts) + "\n")
PY
sh -n "$TRANSFER_BODY"
cat >"$TMP/resource-transfer-harness.sh" <<'EOF'
#!/bin/sh
set -eu
. "$1"
. "$2"
CASE_DIR=$3
EVENTS=$CASE_DIR/events
: >"$EVENTS"
SESSION_TOKEN=old-session
SWAY_OWNER=$CASE_DIR/sway.owner
NETWORK_OWNER=$CASE_DIR/network.owner
SWAY_OWNED=1
PORTMASTER_NETWORK=1
printf '%s\n' newer-session >"$SWAY_OWNER"
printf '%s\n' newer-session >"$NETWORK_OWNER"
resource_lock() { printf '%s\n' lock >>"$EVENTS"; }
resource_unlock() { printf '%s\n' unlock >>"$EVENTS"; }
publish_runner_state() { printf '%s\n' publish >>"$EVENTS"; }
systemctl() { printf '%s\n' forbidden-systemctl >>"$EVENTS"; return 1; }
NETWORK=/forbidden-network-helper
usleep() { :; }
release_owned_resources_until_done
[ "$SWAY_OWNED" -eq 0 ]
[ "$PORTMASTER_NETWORK" -eq 0 ]
[ "$(grep -c '^lock$' "$EVENTS")" -eq 2 ]
[ "$(grep -c '^publish$' "$EVENTS")" -eq 2 ]
if grep -q '^forbidden-systemctl$' "$EVENTS"; then
	printf '%s\n' 'older owner touched transferred Sway' >&2
	exit 1
fi
EOF
chmod 0755 "$TMP/resource-transfer-harness.sh"
TRANSFER_CASE=$TMP/resource-transfer
mkdir -p "$TRANSFER_CASE"
"$TMP/resource-transfer-harness.sh" "$RECONCILE_BODY" "$TRANSFER_BODY" \
	"$TRANSFER_CASE" >"$TRANSFER_CASE/harness.log" 2>&1

BOOT_ID=11111111-2222-3333-4444-555555555555
INVOCATION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
REPLACEMENT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SESSION=$TMP/session
GLOBAL_SESSION=$TMP/global-session
LOG=$TMP/exit.log
SESSION_TOKEN=11111111-42-100

reset_case() {
	MODE=$1
	rm -f "$TMP/state"/* "$SESSION" "$GLOBAL_SESSION" "$LOG"
	printf '%s\n' "$BOOT_ID" >"$TMP/boot-id"
	printf '%s\n' '1.00 0.00' >"$TMP/uptime"
	printf '%s\n' "$INVOCATION" >"$TMP/state/invocation"
	printf '%s\n' "$REPLACEMENT" >"$TMP/state/replacement-invocation"
	printf '%s\n' 0 >"$TMP/state/replace-after"
	printf '%s\n' active >"$TMP/state/active"
	printf '%s\n' loaded >"$TMP/state/load-state"
	printf '%s\n' "$MODE" >"$TMP/state/mode"
	printf '%s\n' ok >"$TMP/state/show-mode"
	printf '%s\n' present >"$TMP/state/list-mode"
	: >"$TMP/state/signals"
}

write_metadata() {
	RECORDED_INVOCATION=$1
	RECORDED_BOOT=${2:-$BOOT_ID}
	RECORDED_STATE=active
	RECORDED_CONTROL_GROUP=/bird-test.scope
	if [ "$RECORDED_INVOCATION" = pending ]; then
		RECORDED_STATE=starting
		RECORDED_CONTROL_GROUP=
	fi
	cat >"$SESSION" <<EOF
version=2
boundary=systemd-scope
state=$RECORDED_STATE
session_token=$SESSION_TOKEN
boot_id=$RECORDED_BOOT
unit=bird-content-11111111-42-100.scope
invocation_id=$RECORDED_INVOCATION
control_group=$RECORDED_CONTROL_GROUP
EOF
}

run_helper() {
	TARGET_SESSION=${1:-$SESSION}
	EXPECTED_TOKEN=${2:-}
	REQUIRE_RECORD=${3:-0}
	STABLE_NOT_FOUND=${4:-1}
	PATH="$TMP/bin:$PATH" \
	MOCK_STATE_DIR="$TMP/state" \
	BIRD_SESSION_PID="$TARGET_SESSION" \
	BIRD_EXPECTED_SESSION_TOKEN="$EXPECTED_TOKEN" \
	BIRD_REQUIRE_SESSION_RECORD="$REQUIRE_RECORD" \
	BIRD_STABLE_NOT_FOUND_COUNT="$STABLE_NOT_FOUND" \
	BIRD_EXIT_LOG="$LOG" \
	BIRD_BOOT_ID_PATH="$TMP/boot-id" \
	BIRD_UPTIME_PATH="$TMP/uptime" \
	BIRD_SESSION_LOCK="$TMP/session.lock" \
		"$EXIT_HELPER"
}

assert_signals() {
	EXPECTED=$1
	ACTUAL=$(tr '\n' ' ' <"$TMP/state/signals" | sed 's/ $//')
	[ "$ACTUAL" = "$EXPECTED" ] || {
		printf 'expected signals "%s", got "%s"\n' "$EXPECTED" "$ACTUAL" >&2
		exit 1
	}
}

reset_case term-exits
write_metadata "$INVOCATION"
run_helper
assert_signals TERM
[ ! -e "$SESSION" ]
grep -q 'state=empty' "$LOG"

reset_case term-ignored
write_metadata "$INVOCATION"
run_helper
assert_signals 'TERM KILL'
[ ! -e "$SESSION" ]

reset_case term-exits
write_metadata pending
run_helper
assert_signals TERM

# systemd uses the all-zero InvocationID while a transient scope is not fully
# registered. It is pending/unknown, never an identity that can be adopted or
# classified as replaced when the real InvocationID appears on the next query.
reset_case term-exits
printf '%s\n' 00000000000000000000000000000000 >"$TMP/state/invocation"
printf '%s\n' "$INVOCATION" >"$TMP/state/replacement-invocation"
printf '%s\n' 1 >"$TMP/state/replace-after"
write_metadata pending
run_helper
assert_signals TERM

reset_case term-exits
write_metadata "$REPLACEMENT"
run_helper
assert_signals ''
grep -q 'state=gone-or-replaced' "$LOG"

reset_case term-exits
write_metadata "$INVOCATION" 99999999-2222-3333-4444-555555555555
run_helper
assert_signals ''

# The old invocation receives TERM, then systemd reports a later unit with the
# same name. Immediate InvocationID checks must never send KILL to that unit.
reset_case term-ignored
printf '%s\n' 10 >"$TMP/state/replace-after"
write_metadata "$INVOCATION"
run_helper
assert_signals TERM

reset_case term-exits
printf '%s\n' 12345 >"$SESSION"
run_helper
assert_signals ''

# A manager/bus failure is unknown, never inactive. It must not signal or
# remove the only record that can be retried later.
reset_case term-exits
printf '%s\n' fail >"$TMP/state/show-mode"
printf '%s\n' fail >"$TMP/state/list-mode"
write_metadata "$INVOCATION"
if run_helper; then
	printf '%s\n' 'query failure unexpectedly succeeded' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
assert_signals ''
[ -e "$SESSION" ]
grep -q 'query-unknown metadata=preserved' "$LOG"

# A successful unit-list query with no exact unit is confirmed gone and may
# remove the old record even when `systemctl show` returns not-found.
reset_case term-exits
printf '%s\n' fail >"$TMP/state/show-mode"
printf '%s\n' absent >"$TMP/state/list-mode"
write_metadata "$INVOCATION"
run_helper
assert_signals ''
[ ! -e "$SESSION" ]

# Simulate an old SIGKILL guard after a new session has replaced the global
# record. Exact old cleanup succeeds, but the token-constrained global pass
# cannot signal or unlink the newer session.
reset_case term-exits
write_metadata "$INVOCATION"
cp "$SESSION" "$GLOBAL_SESSION"
sed 's/session_token=.*/session_token=newer-session/' "$SESSION" >"$GLOBAL_SESSION"
run_helper "$SESSION" "$SESSION_TOKEN"
[ ! -e "$SESSION" ]
: >"$TMP/state/signals"
run_helper "$GLOBAL_SESSION" "$SESSION_TOKEN"
assert_signals ''
[ -e "$GLOBAL_SESSION" ]
grep -q 'newer-session action=none' "$LOG"

# A token-specific crash-guard record is mandatory and therefore retryable
# when missing; the shared latest-session pointer is optional after exact
# cleanup and must not trap the guard in an infinite retry.
reset_case term-exits
if run_helper "$SESSION" "$SESSION_TOKEN" 1; then
	printf '%s\n' 'missing required exact record unexpectedly succeeded' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
run_helper "$GLOBAL_SESSION" "$SESSION_TOKEN" 0

reset_case term-exits
write_metadata "$INVOCATION"
sed 's/session_token=.*/session_token=wrong-exact-token/' "$SESSION" >"$SESSION.tmp"
mv "$SESSION.tmp" "$SESSION"
if run_helper "$SESSION" "$SESSION_TOKEN" 1; then
	printf '%s\n' 'mismatched required exact record unexpectedly succeeded' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
[ -e "$SESSION" ]

# An empty property plus LoadState=not-found is a confirmed absent unit, not a
# manager error. This covers systemctl versions that succeed with empty output.
reset_case term-exits
: >"$TMP/state/invocation"
printf '%s\n' not-found >"$TMP/state/load-state"
write_metadata "$INVOCATION"
run_helper
[ ! -e "$SESSION" ]

# Stable absence is required after killing the gated bootstrap because its
# already-queued manager request can become visible late. A real InvocationID
# appearing during that window must be adopted and terminated, not discarded.
reset_case term-exits
: >"$TMP/state/invocation"
printf '%s\n' not-found >"$TMP/state/load-state"
printf '%s\n' 5 >"$TMP/state/replace-after"
write_metadata pending
run_helper "$SESSION" "" 0 20
assert_signals TERM
[ ! -e "$SESSION" ]

# Execute the real producer against a temporary fixed-profile tree, then feed
# its genuine two-line marker through the runner's actual wait path. This keeps
# producer and consumer formats coupled instead of testing either in isolation.
CONTRACT_ROOT=$TMP/contract
PROFILE_DIR=$CONTRACT_ROOT/storage/.config/profile.d
SWAY_DIR=$CONTRACT_ROOT/storage/.config/sway
PLATFORM_STAGE=$CONTRACT_ROOT/run/bird/fixed-platform
SWAY_STAGE=$CONTRACT_ROOT/run/bird/fixed-sway
READY_DIR=$CONTRACT_ROOT/run/bird
SYSTEM_EXPORT=$CONTRACT_ROOT/etc/profile.d/999-export
CONTRACT_UPTIME=$CONTRACT_ROOT/proc/uptime
CONTRACT_READY=$READY_DIR/application-contract-ready
CONTRACT_UNDER_TEST=$CONTRACT_ROOT/999-export
mkdir -p "$PROFILE_DIR" "$SWAY_DIR" "$PLATFORM_STAGE" "$SWAY_STAGE" \
	"${SYSTEM_EXPORT%/*}" "${CONTRACT_UPTIME%/*}" "$READY_DIR"
printf '%s\n' 'export BIRD_TEST_PROFILE=ready' >"$SYSTEM_EXPORT"
printf '%s\n' '1.25 0.50' >"$CONTRACT_UPTIME"
for PROFILE_NAME in 001-device_config 002-turbo-mode_config 010-governors \
	010-led_control 020-fan_control 050-modifiers 091-ui_shader; do
	printf 'profile=%s\n' "$PROFILE_NAME" >"$PLATFORM_STAGE/$PROFILE_NAME"
	cp "$PLATFORM_STAGE/$PROFILE_NAME" "$PROFILE_DIR/$PROFILE_NAME"
done
printf '%s\n' 'sway fixed config' >"$SWAY_STAGE/config"
cp "$SWAY_STAGE/config" "$SWAY_DIR/config"
printf '%s\n' 'sway fixed profile' >"$SWAY_STAGE/095-sway"
cp "$SWAY_STAGE/095-sway" "$PROFILE_DIR/095-sway"
printf '%s\n' 'UI_SERVICE="essway.service"' >"$PROFILE_DIR/090-ui_service"
sed \
	-e "s#^PROFILE_DIR=.*#PROFILE_DIR=$PROFILE_DIR#" \
	-e "s#^SWAY_DIR=.*#SWAY_DIR=$SWAY_DIR#" \
	-e "s#^PLATFORM_STAGE=.*#PLATFORM_STAGE=$PLATFORM_STAGE#" \
	-e "s#^SWAY_STAGE=.*#SWAY_STAGE=$SWAY_STAGE#" \
	-e "s#^SYSTEM_EXPORT=.*#SYSTEM_EXPORT=$SYSTEM_EXPORT#" \
	-e "s#^READY_DIR=.*#READY_DIR=$READY_DIR#" \
	-e 's#^VOLUME_HELPER=.*#VOLUME_HELPER=/usr/bin/true#' \
	-e "s#/proc/uptime#$CONTRACT_UPTIME#g" \
	"$CONTRACT_PRODUCER" >"$CONTRACT_UNDER_TEST"
chmod 0755 "$CONTRACT_UNDER_TEST"
"$CONTRACT_UNDER_TEST"
BIRD_APPLICATION_READY="$CONTRACT_READY" \
	BIRD_TEST_WAIT_APPLICATION_CONTRACT=1 "$RUNNER"
cp "$CONTRACT_READY" "$CONTRACT_READY.good"
printf '%s\n' 'unexpected=third-line' >>"$CONTRACT_READY"
if PATH="$TMP/bin:$PATH" MOCK_STATE_DIR="$TMP/state" \
	BIRD_APPLICATION_READY="$CONTRACT_READY" \
	BIRD_TEST_WAIT_APPLICATION_CONTRACT=1 "$RUNNER"; then
	printf '%s\n' 'consumer accepted an extended contract marker' >&2
	exit 1
fi
cp "$CONTRACT_READY.good" "$CONTRACT_READY"
sed 's/^published_uptime=.*/published_uptime=1.2.3/' \
	"$CONTRACT_READY.good" >"$CONTRACT_READY"
if PATH="$TMP/bin:$PATH" MOCK_STATE_DIR="$TMP/state" \
	BIRD_APPLICATION_READY="$CONTRACT_READY" \
	BIRD_TEST_WAIT_APPLICATION_CONTRACT=1 "$RUNNER"; then
	printf '%s\n' 'consumer accepted a malformed contract uptime' >&2
	exit 1
fi
sed -n '1p' "$CONTRACT_READY.good" >"$CONTRACT_READY"
if PATH="$TMP/bin:$PATH" MOCK_STATE_DIR="$TMP/state" \
	BIRD_APPLICATION_READY="$CONTRACT_READY" \
	BIRD_TEST_WAIT_APPLICATION_CONTRACT=1 "$RUNNER"; then
	printf '%s\n' 'consumer accepted a one-line contract marker' >&2
	exit 1
fi

bash -n "$RUNNER"
sh -n "$EXIT_HELPER"
grep -Fq '/usr/bin/systemd-run --quiet --scope --collect' "$RUNNER"
grep -Fq 'contract_revision=$APPLICATION_CONTRACT_REVISION' "$RUNNER"
grep -Fq 'systemctl kill --kill-whom=all --signal=KILL' "$EXIT_HELPER"
grep -Fq 'for TARGET in "$SESSION_RECORD" "$GLOBAL_SESSION"' "$RUNNER"
grep -Fq 'owner_relation "$SWAY_OWNER"' "$RUNNER"
grep -Fq 'CATALOG_PATH_MAX_BYTES=4085' "$RUNNER"
grep -Fq "grep -q '[[:cntrl:]]'" "$RUNNER"
grep -Fq '*/../*|*/..|../*|..)' "$RUNNER"
grep -Fq 'scope_expected=%s' "$RUNNER"
grep -Fq 'if ! session_lock; then' "$RUNNER"
grep -Fq 'GUARD_STARTED=1' "$RUNNER"
python3 - "$RUNNER" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
guard_start = source.index("start_cleanup_guard() {")
guard_end = source.index("\n}\n\ncleanup_runtime() {", guard_start)
guard = source[guard_start:guard_end]
service_exec = guard.index("/usr/bin/systemd-run --quiet --collect --service-type=exec")
guard_ready = guard.index("GUARD_STARTED=1", service_exec)
lease_armed = guard.index("publish_runner_state 1 || return 1", guard_ready)
assert service_exec < guard_ready < lease_armed

# The only permitted pre-guard work is validation and local bookkeeping. The
# first compositor, network, or content-scope acquisition must remain behind
# the successful guard/lease handshake in the top-level dispatch path.
dispatch = source.index("if ! start_cleanup_guard; then", guard_end)
first_sway = source.index("start_sway", dispatch)
assert dispatch < first_sway
PY
grep -Fq 'reconcile_registration_failure 2 || :' "$RUNNER"
grep -Fq 'reconcile_registration_failure 3 || :' "$RUNNER"
grep -Fq '2) stop_and_reap_scope_runner "$UNRESOLVED_RUNNER_PID" \' "$RUNNER"
grep -Fq '"$UNRESOLVED_RUNNER_START" ;;' "$RUNNER"
grep -Fq '3) wait "$UNRESOLVED_RUNNER_PID" 2>/dev/null || : ;;' "$RUNNER"
grep -Fq 'terminate_scope_until_gone cleanup' "$RUNNER"
grep -Fq 'release_owned_resources_until_done' "$RUNNER"
grep -Fq -- '--description='"'"'birdOS foreground content'"'"' -- "$@" 8>&- 9>&-' "$RUNNER"
grep -Fq 'scope_runner_pid=%s' "$RUNNER"
grep -Fq 'scope_runner_start_ticks=%s' "$RUNNER"
grep -Fq 'if ! : >"$SCOPE_START_GATE"; then' "$RUNNER"
grep -Fq 'BIRD_STABLE_NOT_FOUND_COUNT=' "$RUNNER"
grep -Fq '"$NETWORK" start 8>&- 9>&-' "$RUNNER"
grep -Fq '"$NETWORK_HELPER" stop 8>&- 9>&-' "$RUNNER"
grep -Fq '8>&- 9>&- </dev/null >/dev/null 2>&1' "$RUNNER"
grep -Fq '"$UNIT_NAME" 8>&- 9>&- 2>/dev/null' "$EXIT_HELPER"
if grep -Fq 'systemctl start --wait "$SCOPE_UNIT"' "$RUNNER"; then
	printf '%s\n' 'scope still joins the completed start job' >&2
	exit 1
fi

# A child surviving for twenty seconds causes at most 106 backed-off manager
# observations, rather than a CPU-tight loop around an already-complete job.
POLL_COUNT=$(BIRD_TEST_SCOPE_POLL_STEPS=200 "$RUNNER" | awk '
	{ total += $1; count += 1 }
	total >= 20000000 { print count; exit }
')
[ -n "$POLL_COUNT" ] && [ "$POLL_COUNT" -le 106 ] || {
	printf 'scope poll wake bound exceeded: %s\n' "${POLL_COUNT:-none}" >&2
	exit 1
}

BIRD_TEST_VALIDATE_HOST_PATH=1 \
	BIRD_TEST_HOST_PATH='/mnt/mmc/ROMS/SNES/game.sfc' "$RUNNER"
if BIRD_TEST_VALIDATE_HOST_PATH=1 \
	BIRD_TEST_HOST_PATH='/mnt/mmc/ROMS/../secret' "$RUNNER"; then
	printf '%s\n' 'traversal path unexpectedly accepted' >&2
	exit 1
fi
if BIRD_TEST_VALIDATE_HOST_PATH=1 \
	BIRD_TEST_HOST_PATH="$(printf '/mnt/mmc/ROMS/bad\rname')" "$RUNNER"; then
	printf '%s\n' 'control-delimited path unexpectedly accepted' >&2
	exit 1
fi
LONG_PATH=/mnt/mmc/$(awk 'BEGIN { for (i = 0; i < 4080; i++) printf "x" }')
if BIRD_TEST_VALIDATE_HOST_PATH=1 BIRD_TEST_HOST_PATH="$LONG_PATH" "$RUNNER"; then
	printf '%s\n' 'overlong path unexpectedly accepted' >&2
	exit 1
fi
if BIRD_TEST_VALIDATE_HOST_PATH=1 BIRD_TEST_EXTRA_LINE=1 \
	BIRD_TEST_HOST_PATH='/mnt/mmc/ROMS/SNES/game.sfc' "$RUNNER"; then
	printf '%s\n' 'newline-extended request unexpectedly accepted' >&2
	exit 1
fi

REQUEST_CASE=$TMP/request-record
printf '1\nsnes9x\nGame\n/mnt/mmc/ROMS/SNES/game.sfc\n' >"$REQUEST_CASE"
BIRD_TEST_PARSE_LAUNCH_REQUEST=1 \
	BIRD_TEST_REQUEST_PATH="$REQUEST_CASE" "$RUNNER"
printf '1\nsnes9x\nGame\n/mnt/mmc/ROMS/SNES/game.sfc\nfifth' \
	>"$REQUEST_CASE"
if BIRD_TEST_PARSE_LAUNCH_REQUEST=1 \
	BIRD_TEST_REQUEST_PATH="$REQUEST_CASE" "$RUNNER"; then
	printf '%s\n' 'unterminated fifth request line unexpectedly accepted' >&2
	exit 1
fi
printf '1\nsnes9x\nGame\n/mnt/mmc/ROMS/SNES/game.sfc' >"$REQUEST_CASE"
if BIRD_TEST_PARSE_LAUNCH_REQUEST=1 \
	BIRD_TEST_REQUEST_PATH="$REQUEST_CASE" "$RUNNER"; then
	printf '%s\n' 'unterminated required request line unexpectedly accepted' >&2
	exit 1
fi

printf '%s\n' 'stock-root content-scope tests: PASS'
