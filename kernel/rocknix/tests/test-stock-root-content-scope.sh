#!/bin/sh
# Host-side fault injection for birdOS's foreground scope exit contract.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
RUNNER=$ROOT/kernel/rocknix/stock-root/run-content.sh
EXIT_HELPER=$ROOT/kernel/rocknix/stock-root/bird-fixed-control-exit.sh
CONTRACT_PRODUCER=$ROOT/kernel/rocknix/stock-root/999-export
TIMEOUT_PROGRAM=$(command -v timeout)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-content-scope.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

grep -Fq 'PORT_PREP=/flash/bird/prepare-ports.sh' "$RUNNER"
grep -Fq 'NETWORK=/flash/bird/bird-network.sh' "$RUNNER"
grep -Fq '/flash/bird/bird-volume.sh restore' "$RUNNER"
grep -Fq 'bird-content-guard /flash/bird/bird-pidwait' "$RUNNER"
grep -Fq '/flash/bird/bird-fixed-control-exit.sh "$NETWORK"' "$RUNNER"

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
CRASH_KOREADER_WRAPPER=$TMP/KOReader-$CRASH_TOKEN.sh
cp "$GUARD_BODY" "$GUARD_TEST_BODY"
sh -n "$GUARD_TEST_BODY"
: >"$CRASH_KOREADER_WRAPPER"
: >"$CRASH_KOREADER_WRAPPER.tmp"
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
	"$TMP/crash-scope.cancel" "$GUARD_PROC" \
	"$CRASH_KOREADER_WRAPPER" &
CRASH_GUARD_PID=$!
sleep 0.05
CRASH_GUARD_PRECHECK=0
[ -e "$CRASH_STATE" ] || CRASH_GUARD_PRECHECK=1
kill -0 "$CRASH_GUARD_PID" 2>/dev/null || CRASH_GUARD_PRECHECK=1
: >"$GUARD_RELEASE"
wait_pid_bounded "$CRASH_GUARD_PID" 10 crash-guard
[ "$CRASH_GUARD_PRECHECK" -eq 0 ]
[ ! -e "$CRASH_STATE" ]
[ ! -e "$CRASH_KOREADER_WRAPPER" ]
[ ! -e "$CRASH_KOREADER_WRAPPER.tmp" ]

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

# Sway startup is a transaction: an early content request joins seatd before
# claiming ownership, and any later failure rolls that exact ownership back.
SWAY_START_BODY=$TMP/sway-start-functions.sh
python3 - "$RUNNER" "$SWAY_START_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("rollback_sway_start() {")
end = source.index("\nensure_content_services() {", start)
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
sh -n "$SWAY_START_BODY"
cat >"$TMP/sway-start-harness.sh" <<'EOF'
#!/bin/sh
set -eu
. "$1"
MODE=$2
CASE_DIR=$3
EVENTS=$CASE_DIR/events
SWAY_OWNER=$CASE_DIR/sway.owner
SWAY_SOCKET=/tmp/bird-sway-start-$$.sock
SESSION_TOKEN=test-session
SWAY_OWNED=0
rm -f "$SWAY_SOCKET"
trap 'rm -f "$SWAY_SOCKET"' EXIT INT TERM HUP
: >"$EVENTS"
resource_lock() { printf '%s\n' lock >>"$EVENTS"; }
resource_unlock() { printf '%s\n' unlock >>"$EVENTS"; }
claim_owner() {
	printf '%s\n' claim >>"$EVENTS"
	printf '%s\n' "$SESSION_TOKEN" >"$1"
}
publish_runner_state() { printf 'publish-%s\n' "$1" >>"$EVENTS"; }
content_stage() { printf 'stage-%s\n' "$1" >>"$EVENTS"; }
stop_sway() {
	printf '%s\n' rollback >>"$EVENTS"
	SWAY_OWNED=0
	rm -f "$SWAY_OWNER"
}
systemctl() {
	printf 'systemctl-%s\n' "$*" >>"$EVENTS"
	case "$MODE:$*" in
		seatd-fail:'start seatd.service'|sway-fail:'start --no-block sway.service') return 1 ;;
		*) return 0 ;;
	esac
}
seq() { printf '%s\n' 1 2; }
usleep() { :; }

SOCKET_PID=
if [ "$MODE" = success ]; then
	python3 - "$SWAY_SOCKET" <<'PY' &
import socket
import sys
import time
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.listen(1)
time.sleep(10)
PY
	SOCKET_PID=$!
	COUNT=0
	while [ ! -S "$SWAY_SOCKET" ] && [ "$COUNT" -lt 100 ]; do
		COUNT=$((COUNT + 1))
		sleep 0.01
	done
	[ -S "$SWAY_SOCKET" ]
fi

if start_sway; then START_STATUS=0; else START_STATUS=$?; fi
[ -z "$SOCKET_PID" ] || {
	kill "$SOCKET_PID" 2>/dev/null || :
	wait "$SOCKET_PID" 2>/dev/null || :
}
rm -f "$SWAY_SOCKET"
case "$MODE" in
	seatd-fail)
		[ "$START_STATUS" -eq 1 ]
		[ "$SWAY_OWNED" -eq 0 ]
		[ "$(grep -c '^claim$' "$EVENTS" || :)" -eq 0 ]
		[ "$(grep -c '^rollback$' "$EVENTS" || :)" -eq 0 ]
		;;
	sway-fail|socket-timeout)
		[ "$START_STATUS" -eq 1 ]
		[ "$SWAY_OWNED" -eq 0 ]
		[ ! -e "$SWAY_OWNER" ]
		[ "$(grep -c '^rollback$' "$EVENTS")" -eq 1 ]
		;;
	success)
		[ "$START_STATUS" -eq 0 ]
		[ "$SWAY_OWNED" -eq 1 ]
		[ -s "$SWAY_OWNER" ]
		[ "$(grep -c '^rollback$' "$EVENTS" || :)" -eq 0 ]
		grep -q '^systemctl-start --no-block sway.service$' "$EVENTS"
		grep -q '^stage-sway-ready$' "$EVENTS"
		;;
esac
EOF
chmod 0755 "$TMP/sway-start-harness.sh"
for MODE in seatd-fail sway-fail socket-timeout success; do
	CASE_DIR=$TMP/sway-start-$MODE
	mkdir -p "$CASE_DIR"
	if ! "$TMP/sway-start-harness.sh" "$SWAY_START_BODY" "$MODE" "$CASE_DIR" \
			>"$CASE_DIR/harness.log" 2>&1; then
		printf 'Sway startup transaction case failed: %s\n' "$MODE" >&2
		cat "$CASE_DIR/harness.log" >&2
		exit 1
	fi
done

# Every systemd client call in the foreground runner passes through a bounded
# wrapper. A timeout remains a failure; it is never treated as completed state.
SYSTEMCTL_WRAPPER=$TMP/systemctl-wrapper.sh
python3 - "$RUNNER" "$SYSTEMCTL_WRAPPER" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("systemctl() {")
end = source.index("\n}\n\ncontent_stage() {", start) + 2
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
sh -n "$SYSTEMCTL_WRAPPER"
cat >"$TMP/systemctl-wrapper-harness.sh" <<'EOF'
#!/bin/sh
set -eu
. "$1"
CASE_DIR=$2
TIMEOUT_PROGRAM=$CASE_DIR/timeout
SYSTEMCTL_PROGRAM=$CASE_DIR/systemctl
cat >"$TIMEOUT_PROGRAM" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >"$BIRD_TEST_TIMEOUT_ARGS"
exit 124
SCRIPT
cat >"$SYSTEMCTL_PROGRAM" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
chmod 0755 "$TIMEOUT_PROGRAM" "$SYSTEMCTL_PROGRAM"
if BIRD_TEST_TIMEOUT_ARGS=$CASE_DIR/args systemctl start sway.service; then
	printf '%s\n' 'bounded systemctl accepted timeout as success' >&2
	exit 1
else
	STATUS=$?
fi
[ "$STATUS" -eq 124 ]
grep -Fq -- '--signal=TERM --kill-after=1s 3s' "$CASE_DIR/args"
grep -Fq "$SYSTEMCTL_PROGRAM start sway.service" "$CASE_DIR/args"
EOF
chmod 0755 "$TMP/systemctl-wrapper-harness.sh"
SYSTEMCTL_CASE=$TMP/systemctl-wrapper
mkdir -p "$SYSTEMCTL_CASE"
"$TMP/systemctl-wrapper-harness.sh" "$SYSTEMCTL_WRAPPER" "$SYSTEMCTL_CASE"

grep -Fq 'systemctl stop --no-block sway.service' "$RUNNER"
grep -Fq '/usr/bin/timeout --signal=TERM --kill-after=1s 3s \' "$RUNNER"
for STAGE in session-start guard-ready contract-ready sway-start-request \
	sway-ready services-ready provider-start provider-returned cleanup-start \
	cleanup-complete; do
	grep -Fq "content_stage $STAGE" "$RUNNER"
done

SWAY_STOP_CONFIRM_BODY=$TMP/sway-stop-confirm-functions.sh
python3 - "$RUNNER" "$SWAY_STOP_CONFIRM_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("scope_query_property() {")
end = source.index("\n# Return 0 only for this exact invocation", start)
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
sh -n "$SWAY_STOP_CONFIRM_BODY"
cat >"$TMP/sway-stop-confirm-harness.sh" <<'EOF'
#!/bin/sh
set -eu
. "$1"
MODE=$2
SWAY_SOCKET=$3
systemctl() {
	COMMAND=$1
	shift
	PROPERTY=
	for ARG in "$@"; do
		case "$ARG" in --property=*) PROPERTY=${ARG#--property=} ;; esac
	done
	case "$COMMAND:$PROPERTY:$MODE" in
		show:ActiveState:inactive) printf '%s\n' inactive ;;
		show:ActiveState:failed) printf '%s\n' failed ;;
		show:ActiveState:active) printf '%s\n' active ;;
		show:LoadState:*) printf '%s\n' loaded ;;
		list-units::*) printf '%s\n' 'sway.service loaded active running test' ;;
		*) return 1 ;;
	esac
}
case "$MODE" in
	inactive|failed) sway_stopped_confirmed ;;
	active) ! sway_stopped_confirmed ;;
esac
EOF
chmod 0755 "$TMP/sway-stop-confirm-harness.sh"
for MODE in inactive failed active; do
	"$TMP/sway-stop-confirm-harness.sh" "$SWAY_STOP_CONFIRM_BODY" "$MODE" \
		"$TMP/nonexistent-sway.sock"
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
[ "$(grep -n '^sway-attempt-1$' "$EVENTS" | cut -d: -f1)" -gt \
	"$(grep -n '^network-attempt-2$' "$EVENTS" | cut -d: -f1)" ]
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
    ("stop_portmaster_network() {", "\nprepare_portmaster_python_cache() {"),
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

# A failed helper stop must report its real status and retain both the local
# cleanup bit and exact owner token. A later retry may release them only after
# the helper itself confirms the fixed stack and radio are stopped.
NETWORK_STOP_BODY=$TMP/network-stop-functions.sh
python3 - "$RUNNER" "$NETWORK_STOP_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
parts = []
for start_marker, end_marker in (
    ("owner_matches() {", "\nclaim_owner() {"),
    ("remove_owned_token() {", "\nrollback_sway_start() {"),
	    ("stop_portmaster_network() {", "\nprepare_portmaster_python_cache() {"),
):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    parts.append(source[start:end])
Path(sys.argv[2]).write_text("\n\n".join(parts) + "\n")
PY
sh -n "$NETWORK_STOP_BODY"
cat >"$TMP/network-stop-retry-harness.sh" <<'EOF'
#!/bin/sh
set -eu
. "$1"
CASE_DIR=$2
SESSION_TOKEN=retry-owner
NETWORK_OWNER=$CASE_DIR/network.owner
PORTMASTER_NETWORK=1
printf '%s\n' "$SESSION_TOKEN" >"$NETWORK_OWNER"
printf '%s\n' 0 >"$CASE_DIR/count"
resource_lock() { :; }
resource_unlock() { :; }
owner_relation() {
	OWNER_RELATION=unknown
	[ -s "$1" ] || return 0
	IFS= read -r OWNER_TOKEN <"$1" || return 0
	if [ "$OWNER_TOKEN" = "$SESSION_TOKEN" ]; then
		OWNER_RELATION=ours
	else
		OWNER_RELATION=transferred
	fi
}
publish_runner_state() { :; }
run_network_helper() {
	COUNT=$(cat "$CASE_DIR/count")
	COUNT=$((COUNT + 1))
	printf '%s\n' "$COUNT" >"$CASE_DIR/count"
	[ "$COUNT" -ge 2 ] || return 7
}
if stop_portmaster_network >"$CASE_DIR/first.log" 2>&1; then
	printf '%s\n' 'partial network stop unexpectedly succeeded' >&2
	exit 1
else
	FIRST_STATUS=$?
fi
[ "$FIRST_STATUS" -eq 7 ]
[ "$PORTMASTER_NETWORK" -eq 1 ]
[ "$(cat "$NETWORK_OWNER")" = "$SESSION_TOKEN" ]
grep -Fq 'Bird portmaster network stop status=7' "$CASE_DIR/first.log"
if ! stop_portmaster_network >"$CASE_DIR/second.log" 2>&1; then
	printf '%s\n' 'retry after confirmed stop failed' >&2
	exit 1
fi
[ "$PORTMASTER_NETWORK" -eq 0 ]
[ ! -e "$NETWORK_OWNER" ]
grep -Fq 'Bird portmaster network stop status=ok' "$CASE_DIR/second.log"
EOF
chmod 0755 "$TMP/network-stop-retry-harness.sh"
NETWORK_STOP_CASE=$TMP/network-stop-retry
mkdir -p "$NETWORK_STOP_CASE"
if ! "$TMP/network-stop-retry-harness.sh" "$NETWORK_STOP_BODY" \
	"$NETWORK_STOP_CASE"; then
	printf '%s\n' 'network stop retry fixture failed' >&2
	for RETRY_LOG in "$NETWORK_STOP_CASE"/*.log; do
		[ -e "$RETRY_LOG" ] && cat "$RETRY_LOG" >&2
	done
	exit 1
fi

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
CONTROLLER_PROFILE=$CONTRACT_ROOT/flash/bird/bird-controller-profile
CONTRACT_UPTIME=$CONTRACT_ROOT/proc/uptime
CONTRACT_READY=$READY_DIR/application-contract-ready
CONTRACT_UNDER_TEST=$CONTRACT_ROOT/999-export
mkdir -p "$PROFILE_DIR" "$SWAY_DIR" "$PLATFORM_STAGE" "$SWAY_STAGE" \
	"${SYSTEM_EXPORT%/*}" "${CONTROLLER_PROFILE%/*}" \
	"${CONTRACT_UPTIME%/*}" "$READY_DIR"
printf '%s\n' 'export BIRD_TEST_PROFILE=ready' >"$SYSTEM_EXPORT"
cp "$ROOT/kernel/rocknix/stock-root/bird-controller-profile" \
	"$CONTROLLER_PROFILE"
cp "$CONTROLLER_PROFILE" "$PROFILE_DIR/098-controller"
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
	-e "s#^CONTROLLER_PROFILE_SOURCE=.*#CONTROLLER_PROFILE_SOURCE=$CONTROLLER_PROFILE#" \
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
[ "$(grep -Fc -- '--expand-environment=no' "$RUNNER")" -eq 2 ]
if grep -Eq "cut -d ['\"] ['\"] -f 1 /proc/uptime" "$RUNNER"; then
	printf '%s\n' 'content path still forks cut only to read uptime' >&2
	exit 1
fi
if grep -Fq "printf '%s' \"\$HOST_PATH\" | wc -c" "$RUNNER" || \
	grep -Fq "printf '%s' \"\$HOST_PATH\" | grep" "$RUNNER"; then
	printf '%s\n' 'content path still forks to validate a catalog path' >&2
	exit 1
fi
if grep -Fq "sed -n 's/^session_token=//p'" "$RUNNER" || \
	grep -Fq '$(cat "$NETWORK_OWNER")' "$RUNNER"; then
	printf '%s\n' 'content metadata or owner logging still forks parsers' >&2
	exit 1
fi
grep -Fq 'contract_revision=$APPLICATION_CONTRACT_REVISION' "$RUNNER"
grep -Fq 'systemctl kill --kill-whom=all --signal=KILL' "$EXIT_HELPER"
grep -Fq 'for TARGET in "$SESSION_RECORD" "$GLOBAL_SESSION"' "$RUNNER"
grep -Fq 'owner_relation "$SWAY_OWNER"' "$RUNNER"
grep -Fq 'CATALOG_PATH_MAX_BYTES=4095' "$RUNNER"
grep -Fq '*[[:cntrl:]]*) HOST_PATH_CONTROL=1 ;;' "$RUNNER"
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
no_expand = guard.index("--expand-environment=no", service_exec)
shell_exec = guard.index("-- /bin/sh -c", no_expand)
guard_ready = guard.index("GUARD_STARTED=1", service_exec)
lease_armed = guard.index("publish_runner_state 1 || return 1", guard_ready)
assert service_exec < no_expand < shell_exec < guard_ready < lease_armed

scope_exec = source.index("/usr/bin/systemd-run --quiet --scope --collect")
scope_no_expand = source.index("--expand-environment=no", scope_exec)
scope_command = source.index(' -- "$@" 8>&- 9>&-', scope_no_expand)
assert scope_exec < scope_no_expand < scope_command

services_start = source.index("ensure_content_services() {")
services_end = source.index("\n}", services_start)
services = source[services_start:services_end]
assert services.count("systemctl start") == 2
dbus = services.index("systemctl start dbus.service")
audio = services.index("systemctl start pipewire.service wireplumber.service")
assert dbus < audio
assert "pipewire-pulse.service" in services

# The only permitted pre-guard work is validation and local bookkeeping. The
# first compositor, network, or content-scope acquisition must remain behind
# the successful guard/lease handshake in the top-level dispatch path.
dispatch = source.index("if ! start_cleanup_guard; then", guard_end)
first_sway = source.index("start_sway", dispatch)
assert dispatch < first_sway
PY

STATUS_CLASSIFIER=$TMP/status-classifier.sh
sed -n '/^classify_exit_status() {/,/^}/p' "$RUNNER" >"$STATUS_CLASSIFIER"
# shellcheck source=/dev/null
. "$STATUS_CLASSIFIER"
classify_exit_status 0
[ "$BIRD_EXIT_CLASS" = success ]
classify_exit_status 7
[ "$BIRD_EXIT_CLASS" = exit-7 ]
classify_exit_status 137
[ "$BIRD_EXIT_CLASS" = sigkill ]
classify_exit_status 143
[ "$BIRD_EXIT_CLASS" = sigterm ]
classify_exit_status 130
[ "$BIRD_EXIT_CLASS" = signal-2 ]
classify_exit_status 128
[ "$BIRD_EXIT_CLASS" = exit-128 ]
classify_exit_status 192
[ "$BIRD_EXIT_CLASS" = signal-64 ]
classify_exit_status 193
[ "$BIRD_EXIT_CLASS" = exit-193 ]
classify_exit_status 255
[ "$BIRD_EXIT_CLASS" = exit-255 ]

METADATA_MATCHER=$TMP/scope-metadata-matcher.sh
sed -n '/^scope_metadata_matches() {/,/^}/p' "$RUNNER" >"$METADATA_MATCHER"
# shellcheck source=/dev/null
. "$METADATA_MATCHER"
SESSION_TOKEN=test-session
SCOPE_UNIT=bird-content-test.scope
SCOPE_INVOCATION=0123456789abcdef
METADATA_RECORD=$TMP/scope-metadata
printf '%s\n' \
	version=2 \
	session_token="$SESSION_TOKEN" \
	unit="$SCOPE_UNIT" \
	invocation_id="$SCOPE_INVOCATION" >"$METADATA_RECORD"
scope_metadata_matches "$METADATA_RECORD"
printf '%s\n' \
	session_token="$SESSION_TOKEN" \
	session_token=wrong-later-value \
	unit="$SCOPE_UNIT" \
	invocation_id="$SCOPE_INVOCATION" >"$METADATA_RECORD"
scope_metadata_matches "$METADATA_RECORD"
printf '%s\n' \
	session_token=wrong-first-value \
	session_token="$SESSION_TOKEN" \
	unit="$SCOPE_UNIT" \
	invocation_id="$SCOPE_INVOCATION" >"$METADATA_RECORD"
if scope_metadata_matches "$METADATA_RECORD"; then
	printf '%s\n' 'metadata matcher ignored first-value semantics' >&2
	exit 1
fi
printf '%s\n' \
	session_token="$SESSION_TOKEN" \
	unit="$SCOPE_UNIT" \
	invocation_id=pending >"$METADATA_RECORD"
SCOPE_INVOCATION=
scope_metadata_matches "$METADATA_RECORD"
rm -f "$METADATA_RECORD"
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
grep -Fq 'run_network_helper "$NETWORK_START_MODE"' "$RUNNER"
grep -Fq '"$NETWORK_HELPER" stop 8>&- 9>&-' "$RUNNER"
grep -Fq 'Bird portmaster prepare start' "$RUNNER"
grep -Fq 'Bird portmaster prepare status=' "$RUNNER"
grep -Fq 'Bird portmaster network-start status=' "$RUNNER"
grep -Fq 'Bird portmaster launch start' "$RUNNER"
grep -Fq 'Bird portmaster launch status=' "$RUNNER"
grep -Fq 'Bird portmaster network start mode=' "$RUNNER"
grep -Fq 'Bird portmaster network owner relation=' "$RUNNER"
grep -Fq 'Bird network request flag present before start' "$RUNNER"
grep -Fq 'Bird network request flag absent before stop' "$RUNNER"
grep -Fq 'Bird portmaster network stop status=' "$RUNNER"
grep -Fq 'network_unit_summary() {' \
	"$ROOT/kernel/rocknix/stock-root/bird-network.sh"
grep -Fq 'Bird network services active=' \
	"$ROOT/kernel/rocknix/stock-root/bird-network.sh"
grep -Fq 'Bird network step=systemctl-start-systemd-rfkill status=' \
	"$ROOT/kernel/rocknix/stock-root/bird-network.sh"
grep -Fq 'Bird network step=systemctl-start-networkmanager status=' \
	"$ROOT/kernel/rocknix/stock-root/bird-network.sh"
grep -Fq 'Bird network step=nm-online status=' \
	"$ROOT/kernel/rocknix/stock-root/bird-network.sh"
grep -Fq 'Bird network step=systemctl-stop-network-stack status=' \
	"$ROOT/kernel/rocknix/stock-root/bird-network.sh"
grep -Fq 'shareability=private-raw' "$RUNNER"
if grep -Eq -- '--rocknix|start_es[.]sh|start-interactive|stock_rocknix_diagnostics|write_shareable_stock_diagnostics' \
	"$RUNNER"; then
	printf '%s\n' 'temporary stock frontend path remained in content runner' >&2
	exit 1
fi

# Execute the installed network helper against fixed command fixtures. This
# covers strict direct readiness and a partial stop whose request survives for
# a safe retry.
NETWORK_SCRIPT=$ROOT/kernel/rocknix/stock-root/bird-network.sh
NETWORK_FIXTURE=$TMP/network-fixture
mkdir -p "$NETWORK_FIXTURE/bin"
cat >"$NETWORK_FIXTURE/bin/systemctl" <<'EOF'
#!/bin/sh
set -eu
MODE=$BIRD_NETWORK_TEST_MODE
STATE=$BIRD_NETWORK_TEST_STATE
case "$1" in
	start|stop) exit 0 ;;
	is-active)
		shift
		STATUS=0
		for UNIT in "$@"; do
			UNIT_STATE=active
			case "$MODE:$UNIT" in
				manager-down:NetworkManager.service) UNIT_STATE=inactive ;;
				stop-partial:*)
					ATTEMPT=$(cat "$STATE/attempt" 2>/dev/null || printf 0)
					if [ "$ATTEMPT" -ge 2 ]; then
						UNIT_STATE=inactive
					fi
					;;
			esac
			printf '%s\n' "$UNIT_STATE"
			[ "$UNIT_STATE" = active ] || STATUS=3
		done
		exit "$STATUS"
		;;
	*) exit 1 ;;
esac
EOF
cat >"$NETWORK_FIXTURE/bin/nmcli" <<'EOF'
#!/bin/sh
set -eu
trap 'exit 143' TERM
[ "$BIRD_NETWORK_TEST_MODE" != hung-nmcli ] || sleep 20
case " $* " in
	*" connection show "*) printf '%s\n' 'saved-profile:wifi' ;;
	*" connection up "*)
		[ "$BIRD_NETWORK_TEST_MODE" != direct-activation-fail ]
		;;
	*) : ;;
esac
EOF
cat >"$NETWORK_FIXTURE/bin/nm-online" <<'EOF'
#!/bin/sh
set -eu
[ "$BIRD_NETWORK_TEST_MODE" != direct-offline ]
EOF
cat >"$NETWORK_FIXTURE/bin/iwctl" <<'EOF'
#!/bin/sh
printf '%s\n' wlan0
EOF
cat >"$NETWORK_FIXTURE/bin/rfkill" <<'EOF'
#!/bin/sh
set -eu
STATE=$BIRD_NETWORK_TEST_STATE
case "$1" in
	block)
		ATTEMPT=$(cat "$STATE/attempt" 2>/dev/null || printf 0)
		printf '%s\n' $((ATTEMPT + 1)) >"$STATE/attempt"
		;;
	list)
		ATTEMPT=$(cat "$STATE/attempt" 2>/dev/null || printf 0)
		printf '%s\n' '0: phy0: Wireless LAN'
		if [ "$BIRD_NETWORK_TEST_MODE" = stop-partial ] && \
			[ "$ATTEMPT" -lt 2 ]; then
			printf '%s\n' 'Soft blocked: no'
		else
			printf '%s\n' 'Soft blocked: yes'
		fi
		;;
	unblock) : ;;
	*) exit 1 ;;
esac
EOF
cat >"$NETWORK_FIXTURE/bin/ip" <<'EOF'
#!/bin/sh
printf '%s\n' 'default dev wlan0'
EOF
cat >"$NETWORK_FIXTURE/bin/journalctl" <<'EOF'
#!/bin/sh
printf '%s\n' 'bounded journal fixture'
EOF
chmod 0755 "$NETWORK_FIXTURE/bin"/*

run_network_fixture() {
	NETWORK_CASE_MODE=$1
	NETWORK_CASE_COMMAND=$2
	NETWORK_EXPECTED_STATUS=$3
	NETWORK_CASE=$NETWORK_FIXTURE/$NETWORK_CASE_MODE-$NETWORK_CASE_COMMAND
	mkdir -p "$NETWORK_CASE/state" "$NETWORK_CASE/sys-net"
	printf '%s\n' '1.00 0.00' >"$NETWORK_CASE/uptime"
	[ "$NETWORK_CASE_MODE" = no-device ] || mkdir -p "$NETWORK_CASE/sys-net/wlan0"
	NETWORK_CASE_STATUS=0
	"$TIMEOUT_PROGRAM" 5s env \
		BIRD_NETWORK_TEST_MODE="$NETWORK_CASE_MODE" \
		BIRD_NETWORK_TEST_STATE="$NETWORK_CASE/state" \
		BIRD_NETWORK_FLAG="$NETWORK_CASE/network-request" \
		BIRD_NETWORK_LOG="$NETWORK_CASE/network.log" \
		BIRD_UPTIME_PATH="$NETWORK_CASE/uptime" \
		BIRD_SYS_CLASS_NET="$NETWORK_CASE/sys-net" \
		BIRD_TIMEOUT_PROGRAM="$TIMEOUT_PROGRAM" \
		BIRD_SYSTEMCTL_PROGRAM="$NETWORK_FIXTURE/bin/systemctl" \
		BIRD_NMCLI_PROGRAM="$NETWORK_FIXTURE/bin/nmcli" \
		BIRD_NM_ONLINE_PROGRAM="$NETWORK_FIXTURE/bin/nm-online" \
		BIRD_IWCTL_PROGRAM="$NETWORK_FIXTURE/bin/iwctl" \
		BIRD_RFKILL_PROGRAM="$NETWORK_FIXTURE/bin/rfkill" \
		BIRD_IP_PROGRAM="$NETWORK_FIXTURE/bin/ip" \
		BIRD_JOURNALCTL_PROGRAM="$NETWORK_FIXTURE/bin/journalctl" \
		BIRD_LS_PROGRAM=/bin/ls BIRD_HEAD_PROGRAM=/usr/bin/head \
		BIRD_USLEEP_PROGRAM=/usr/bin/true \
		"$NETWORK_SCRIPT" "$NETWORK_CASE_COMMAND" || NETWORK_CASE_STATUS=$?
	[ "$NETWORK_CASE_STATUS" -eq "$NETWORK_EXPECTED_STATUS" ] || {
		printf 'network fixture %s/%s status=%s expected=%s\n' \
			"$NETWORK_CASE_MODE" "$NETWORK_CASE_COMMAND" \
			"$NETWORK_CASE_STATUS" "$NETWORK_EXPECTED_STATUS" >&2
		cat "$NETWORK_CASE/network.log" >&2
		exit 1
	}
}

run_network_fixture ready start 0
run_network_fixture direct-offline start 1
grep -Fq 'request readiness=degraded mode=start' \
	"$NETWORK_FIXTURE/direct-offline-start/network.log"

STOP_RETRY_CASE=$NETWORK_FIXTURE/stop-partial-stop
mkdir -p "$STOP_RETRY_CASE/state" "$STOP_RETRY_CASE/sys-net/wlan0"
: >"$STOP_RETRY_CASE/network-request"
run_network_fixture stop-partial stop 1
[ -e "$STOP_RETRY_CASE/network-request" ]
grep -Fq 'release unresolved request=retained' "$STOP_RETRY_CASE/network.log"
run_network_fixture stop-partial stop 0
[ ! -e "$STOP_RETRY_CASE/network-request" ]
grep -Fq 'stop confirmation units=1 radio=1' "$STOP_RETRY_CASE/network.log"
grep -Fq 'release ready request=removed' "$STOP_RETRY_CASE/network.log"

# Exercise the active run-content deadline and provider gating, rather than
# relying only on source ordering. A helper ignoring TERM is killed within the
# direct bound, and PortMaster never starts after readiness failure.
NETWORK_BOUND_BODY=$TMP/network-bound-function.sh
python3 - "$RUNNER" "$NETWORK_BOUND_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("run_network_helper() {")
end = source.index("\n}\n\nstart_portmaster_network() {", start) + 2
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
sh -n "$NETWORK_BOUND_BODY"
NETWORK_BOUND_CASE=$TMP/network-hard-bound
mkdir -p "$NETWORK_BOUND_CASE"
cat >"$NETWORK_BOUND_CASE/hung-helper" <<'EOF'
#!/bin/sh
trap 'exit 143' TERM
sleep 20
EOF
chmod 0755 "$NETWORK_BOUND_CASE/hung-helper"
cat >"$NETWORK_BOUND_CASE/harness.sh" <<'EOF'
#!/bin/sh
set -eu
. "$1"
TIMEOUT_PROGRAM=$2
NETWORK=$3
NETWORK_DIRECT_BOUND=0.2s
NETWORK_DIRECT_HARD_BOUND=1.2s
NETWORK_STOP_BOUND=2s
NETWORK_STOP_HARD_BOUND=3s
if run_network_helper start; then
	printf '%s\n' 'hung direct helper unexpectedly succeeded' >&2
	exit 1
else
	STATUS=$?
fi
[ "$STATUS" -eq 124 ]
[ "$NETWORK_HELPER_HARD_BOUND" = 1.2s ]
EOF
chmod 0755 "$NETWORK_BOUND_CASE/harness.sh"
"$TIMEOUT_PROGRAM" 3s "$NETWORK_BOUND_CASE/harness.sh" \
	"$NETWORK_BOUND_BODY" "$TIMEOUT_PROGRAM" "$NETWORK_BOUND_CASE/hung-helper"

RUN_SELECTED_BODY=$TMP/run-selected-function.sh
python3 - "$RUNNER" "$RUN_SELECTED_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("run_selected() {")
end = source.index("\n}\n\npublish_runner_state() {", start) + 2
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
bash -n "$RUN_SELECTED_BODY"
cat >"$TMP/run-selected-network-harness.sh" <<'EOF'
#!/bin/bash
set -eu
. "$1"
MODE=$2
CASE_DIR=$3
TIMEOUT_PROGRAM=$4
PORT_PREP=/usr/bin/true
cut() { printf '%s\n' 1.00; }
start_portmaster_network() {
	[ "$MODE" != direct-fail ] || return 7
}
prepare_portmaster_python_cache() { :; }
prepare_portmaster_battery_cache() { :; }
run_managed() {
	printf '%s\n' frontend >>"$CASE_DIR/events"
	return 0
}
: >"$CASE_DIR/events"
SESSION_MODE=portmaster
if run_selected >"$CASE_DIR/output" 2>&1; then
	printf '%s\n' 'direct readiness failure launched provider' >&2
	exit 1
else
	STATUS=$?
fi
[ "$STATUS" -eq 7 ]
[ ! -s "$CASE_DIR/events" ]
EOF
chmod 0755 "$TMP/run-selected-network-harness.sh"
RUN_SELECTED_CASE=$TMP/run-selected-direct-fail
mkdir -p "$RUN_SELECTED_CASE"
"$TMP/run-selected-network-harness.sh" "$RUN_SELECTED_BODY" \
	direct-fail "$RUN_SELECTED_CASE" "$TIMEOUT_PROGRAM"

# Kind 7 keeps the downloaded PortMaster launcher, its archive and the selected
# ebook immutable. Only a session-specific /run copy is transformed, and the
# transform accepts exactly the audited upstream extraction block and launch
# line. A Bird-owned atomic completion record plus the multi-file completeness
# check safely resumes a partial first unzip.
grep -Fq \
	'KOREADER_ARCHIVE_SHA=be706d106d80063ec7471249011da6ee483ac18b77adb8d61571f272c88d3a57' \
	"$RUNNER"
KOREADER_FUNCTIONS=$TMP/koreader-functions.sh
python3 - "$RUNNER" "$KOREADER_FUNCTIONS" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("remove_koreader_port_script() {")
end = source.index("\n\nrun_selected() {", start)
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
bash -n "$KOREADER_FUNCTIONS"
KOREADER_CASE=$TMP/koreader-transform
KOREADER_APP=$KOREADER_CASE/app
KOREADER_SOURCE=$KOREADER_CASE/KOReader.sh
KOREADER_SOURCE_REFERENCE=$KOREADER_CASE/KOReader.reference
KOREADER_ARCHIVE_REFERENCE=$KOREADER_CASE/koreader.reference.zip
KOREADER_SCRIPT=$KOREADER_CASE/run/KOReader-session.sh
KOREADER_TEMP=$KOREADER_SCRIPT.tmp
mkdir -p "$KOREADER_APP/koreader" "$KOREADER_CASE/bin"
cat >"$KOREADER_SOURCE" <<'EOF'
#!/bin/bash
GAMEDIR="$BIRD_TEST_GAMEDIR/"
cd "$GAMEDIR"
ZIPFILE="koreader.zip"
TARGET_DIR="./koreader"

if [ -f "$ZIPFILE" ]; then
    echo "Unzipping $ZIPFILE to $TARGET_DIR..."
    unzip "$ZIPFILE" -d "$TARGET_DIR"
elif [ -f "$GAMEDIR/koreader/luajit" ]; then
    echo "ZIP IS ALREADY EXTRACTED"
    rm $ZIPFILE
else
    echo "File $ZIPFILE does not exist 😢"
fi

cd koreader
LD_PRELOAD=$GAMEDIR/libcrusty.so CRUSTY_BLOCK_INPUT=1 ./luajit reader.lua ../books
EOF
printf '%s\n' archive-must-remain >"$KOREADER_APP/koreader.zip"
cp "$KOREADER_SOURCE" "$KOREADER_SOURCE_REFERENCE"
cp "$KOREADER_APP/koreader.zip" "$KOREADER_ARCHIVE_REFERENCE"
cat >"$KOREADER_CASE/bin/unzip" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = -o ]
[ "$2" = koreader.zip ]
[ "$3" = -d ]
[ "$4" = ./koreader ]
printf '%s\n' "$*" >>"$BIRD_TEST_UNZIP_LOG"
TARGET=$BIRD_TEST_GAMEDIR/koreader
mkdir -p "$TARGET/frontend/apps/reader" "$TARGET/libs"
: >"$TARGET/reader.lua"
: >"$TARGET/frontend/apps/reader/readerui.lua"
: >"$TARGET/libs/libkoreader-cre.so"
: >"$TARGET/libs/libwrap-mupdf.so"
: >"$TARGET/defaults.custom.lua"
cat >"$TARGET/luajit" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$@" >"$BIRD_TEST_LUA_ARGS"
printf '%s\n' "$BIRD_EBOOK_PATH" >"$BIRD_TEST_LUA_PATH"
SCRIPT
chmod 0755 "$TARGET/luajit"
exit "${BIRD_TEST_UNZIP_STATUS:-0}"
EOF
chmod 0755 "$KOREADER_CASE/bin/unzip"

. "$KOREADER_FUNCTIONS"
KOREADER_PORT_SOURCE=$KOREADER_SOURCE
KOREADER_SHA256_PROGRAM=$(command -v sha256sum)
KOREADER_ARCHIVE_SHA=$(
	"$KOREADER_SHA256_PROGRAM" "$KOREADER_APP/koreader.zip" | awk '{print $1}'
)
KOREADER_EXTRACTION_STATE_DIR=$KOREADER_CASE/extraction-state
KOREADER_PORT_SOURCE_SHA=$(
	"$KOREADER_SHA256_PROGRAM" "$KOREADER_SOURCE" | awk '{print $1}'
)
KOREADER_PORT_SCRIPT=$KOREADER_SCRIPT
KOREADER_PORT_TEMP=$KOREADER_TEMP
prepare_koreader_port_script
[ -f "$KOREADER_SCRIPT" ]
[ ! -e "$KOREADER_TEMP" ]
bash -n "$KOREADER_SCRIPT"
cmp "$KOREADER_SOURCE" "$KOREADER_SOURCE_REFERENCE"
cmp "$KOREADER_APP/koreader.zip" "$KOREADER_ARCHIVE_REFERENCE"
grep -Fq 'unzip -o "$ZIPFILE" -d "$TARGET_DIR" || exit 1' \
	"$KOREADER_SCRIPT"
grep -Fq './luajit reader.lua "$BIRD_EBOOK_PATH"' "$KOREADER_SCRIPT"
grep -Fq "BIRD_KOREADER_ARCHIVE_SHA=\"$KOREADER_ARCHIVE_SHA\"" \
	"$KOREADER_SCRIPT"
if grep -Fq 'rm $ZIPFILE' "$KOREADER_SCRIPT"; then
	printf '%s\n' 'volatile KOReader wrapper still deletes its archive' >&2
	exit 1
fi

KOREADER_EBOOK="$KOREADER_CASE/Book's exact title.epub"
KOREADER_EBOOK_REFERENCE=$KOREADER_CASE/ebook.reference
printf '%s\n' 'selected ebook must remain byte-identical' >"$KOREADER_EBOOK"
cp "$KOREADER_EBOOK" "$KOREADER_EBOOK_REFERENCE"
KOREADER_COMPLETE=$KOREADER_EXTRACTION_STATE_DIR/$KOREADER_ARCHIVE_SHA.complete
KOREADER_COMPLETE_TEMP=$KOREADER_COMPLETE.tmp
for KOREADER_RUN in first complete; do
	PATH="$KOREADER_CASE/bin:$PATH" \
		BIRD_TEST_GAMEDIR="$KOREADER_APP" \
		BIRD_TEST_UNZIP_LOG="$KOREADER_CASE/unzip.log" \
		BIRD_TEST_LUA_ARGS="$KOREADER_CASE/lua.args" \
		BIRD_TEST_LUA_PATH="$KOREADER_CASE/lua.path" \
		BIRD_EBOOK_PATH="$KOREADER_EBOOK" \
		"$KOREADER_SCRIPT" >/dev/null 2>&1
done
[ "$(wc -l <"$KOREADER_CASE/unzip.log" | tr -d ' ')" -eq 1 ]
[ "$(cat "$KOREADER_COMPLETE")" = "$KOREADER_ARCHIVE_SHA" ]
[ ! -e "$KOREADER_COMPLETE_TEMP" ]
[ "$(sed -n '1p' "$KOREADER_CASE/lua.args")" = reader.lua ]
[ "$(sed -n '2p' "$KOREADER_CASE/lua.args")" = "$KOREADER_EBOOK" ]
[ "$(cat "$KOREADER_CASE/lua.path")" = "$KOREADER_EBOOK" ]

# A missing late sentinel models power loss after luajit was written. The next
# invocation must rerun overwrite extraction once and then open the same path.
rm -f "$KOREADER_APP/koreader/reader.lua"
PATH="$KOREADER_CASE/bin:$PATH" \
	BIRD_TEST_GAMEDIR="$KOREADER_APP" \
	BIRD_TEST_UNZIP_LOG="$KOREADER_CASE/unzip.log" \
	BIRD_TEST_LUA_ARGS="$KOREADER_CASE/lua.args" \
	BIRD_TEST_LUA_PATH="$KOREADER_CASE/lua.path" \
	BIRD_EBOOK_PATH="$KOREADER_EBOOK" \
	"$KOREADER_SCRIPT" >/dev/null 2>&1
[ "$(wc -l <"$KOREADER_CASE/unzip.log" | tr -d ' ')" -eq 2 ]
[ "$(cat "$KOREADER_COMPLETE")" = "$KOREADER_ARCHIVE_SHA" ]
cmp "$KOREADER_SOURCE" "$KOREADER_SOURCE_REFERENCE"
cmp "$KOREADER_APP/koreader.zip" "$KOREADER_ARCHIVE_REFERENCE"
cmp "$KOREADER_EBOOK" "$KOREADER_EBOOK_REFERENCE"

# A failed unzip may have written every sentinel. Because it cannot publish
# the atomic completion record, the next invocation must still unzip again.
rm -f "$KOREADER_COMPLETE" "$KOREADER_COMPLETE_TEMP" \
	"$KOREADER_CASE/lua.args" "$KOREADER_CASE/lua.path"
KOREADER_UNZIP_BEFORE=$(wc -l <"$KOREADER_CASE/unzip.log" | tr -d ' ')
if PATH="$KOREADER_CASE/bin:$PATH" \
	BIRD_TEST_GAMEDIR="$KOREADER_APP" \
	BIRD_TEST_UNZIP_LOG="$KOREADER_CASE/unzip.log" \
	BIRD_TEST_UNZIP_STATUS=23 \
	BIRD_TEST_LUA_ARGS="$KOREADER_CASE/lua.args" \
	BIRD_TEST_LUA_PATH="$KOREADER_CASE/lua.path" \
	BIRD_EBOOK_PATH="$KOREADER_EBOOK" \
	"$KOREADER_SCRIPT" >/dev/null 2>&1; then
	printf '%s\n' 'failed KOReader unzip unexpectedly launched the reader' >&2
	exit 1
fi
[ "$(wc -l <"$KOREADER_CASE/unzip.log" | tr -d ' ')" -eq \
	$((KOREADER_UNZIP_BEFORE + 1)) ]
for KOREADER_REQUIRED in luajit reader.lua \
	frontend/apps/reader/readerui.lua libs/libkoreader-cre.so \
	libs/libwrap-mupdf.so defaults.custom.lua; do
	[ -f "$KOREADER_APP/koreader/$KOREADER_REQUIRED" ]
done
[ ! -e "$KOREADER_COMPLETE" ]
[ ! -e "$KOREADER_COMPLETE_TEMP" ]
[ ! -e "$KOREADER_CASE/lua.args" ]
cmp "$KOREADER_SOURCE" "$KOREADER_SOURCE_REFERENCE"
cmp "$KOREADER_APP/koreader.zip" "$KOREADER_ARCHIVE_REFERENCE"
cmp "$KOREADER_EBOOK" "$KOREADER_EBOOK_REFERENCE"

PATH="$KOREADER_CASE/bin:$PATH" \
	BIRD_TEST_GAMEDIR="$KOREADER_APP" \
	BIRD_TEST_UNZIP_LOG="$KOREADER_CASE/unzip.log" \
	BIRD_TEST_LUA_ARGS="$KOREADER_CASE/lua.args" \
	BIRD_TEST_LUA_PATH="$KOREADER_CASE/lua.path" \
	BIRD_EBOOK_PATH="$KOREADER_EBOOK" \
	"$KOREADER_SCRIPT" >/dev/null 2>&1
[ "$(wc -l <"$KOREADER_CASE/unzip.log" | tr -d ' ')" -eq \
	$((KOREADER_UNZIP_BEFORE + 2)) ]
[ "$(cat "$KOREADER_COMPLETE")" = "$KOREADER_ARCHIVE_SHA" ]
[ "$(cat "$KOREADER_CASE/lua.path")" = "$KOREADER_EBOOK" ]
cmp "$KOREADER_SOURCE" "$KOREADER_SOURCE_REFERENCE"
cmp "$KOREADER_APP/koreader.zip" "$KOREADER_ARCHIVE_REFERENCE"
cmp "$KOREADER_EBOOK" "$KOREADER_EBOOK_REFERENCE"

# Extraction also fails before unzip when the archive does not match the
# pinned identity. This deliberately corrupts and restores only the fixture.
rm -f "$KOREADER_COMPLETE"
printf '%s\n' tampered >>"$KOREADER_APP/koreader.zip"
cp "$KOREADER_APP/koreader.zip" "$KOREADER_CASE/koreader.tampered.reference"
KOREADER_UNZIP_BEFORE=$(wc -l <"$KOREADER_CASE/unzip.log" | tr -d ' ')
if PATH="$KOREADER_CASE/bin:$PATH" \
	BIRD_TEST_GAMEDIR="$KOREADER_APP" \
	BIRD_TEST_UNZIP_LOG="$KOREADER_CASE/unzip.log" \
	BIRD_TEST_LUA_ARGS="$KOREADER_CASE/lua.args" \
	BIRD_TEST_LUA_PATH="$KOREADER_CASE/lua.path" \
	BIRD_EBOOK_PATH="$KOREADER_EBOOK" \
	"$KOREADER_SCRIPT" >/dev/null 2>&1; then
	printf '%s\n' 'mismatched KOReader archive unexpectedly accepted' >&2
	exit 1
fi
[ "$(wc -l <"$KOREADER_CASE/unzip.log" | tr -d ' ')" -eq \
	"$KOREADER_UNZIP_BEFORE" ]
[ ! -e "$KOREADER_COMPLETE" ]
cmp "$KOREADER_APP/koreader.zip" \
	"$KOREADER_CASE/koreader.tampered.reference"
cmp "$KOREADER_SOURCE" "$KOREADER_SOURCE_REFERENCE"
cmp "$KOREADER_EBOOK" "$KOREADER_EBOOK_REFERENCE"
cp "$KOREADER_ARCHIVE_REFERENCE" "$KOREADER_APP/koreader.zip"

# Even a one-line upstream structural change refuses publication and removes
# both possible volatile artifacts.
sed 's/^    rm \$ZIPFILE$/    :/' "$KOREADER_SOURCE_REFERENCE" \
	>"$KOREADER_CASE/KOReader.changed.sh"
KOREADER_PORT_SOURCE=$KOREADER_CASE/KOReader.changed.sh
KOREADER_PORT_SOURCE_SHA=$(
	"$KOREADER_SHA256_PROGRAM" "$KOREADER_PORT_SOURCE" | awk '{print $1}'
)
if prepare_koreader_port_script; then
	printf '%s\n' 'changed KOReader source unexpectedly transformed' >&2
	exit 1
fi
[ ! -e "$KOREADER_SCRIPT" ]
[ ! -e "$KOREADER_TEMP" ]
KOREADER_PORT_SOURCE=$KOREADER_SOURCE
KOREADER_PORT_SOURCE_SHA=$(
	"$KOREADER_SHA256_PROGRAM" "$KOREADER_PORT_SOURCE" | awk '{print $1}'
)
prepare_koreader_port_script
remove_koreader_port_script
[ ! -e "$KOREADER_SCRIPT" ]
[ ! -e "$KOREADER_TEMP" ]

# Exercise the exact kind-7 run_selected contract independently of the
# transform. EPUB/PDF paths are restricted to MEDIA/READ, the selected path is
# one environment argument, networking is untouched, and the wrapper is
# removed after both provider success and failure.
cat >"$TMP/run-selected-koreader-harness.sh" <<'EOF'
#!/bin/bash
set -eu
. "$1"
CASE_DIR=$2
SESSION_MODE=content
KIND=7
HOST_PATH='/storage/media/READ/Book With Space.EPUB'
CONTENT="$CASE_DIR/Book's exact title.epub"
KOREADER_PORT_SCRIPT=$CASE_DIR/KOReader-session.sh
KOREADER_PORT_TEMP=$KOREADER_PORT_SCRIPT.tmp
PORT_PREP=$CASE_DIR/port-prep
: >"$CONTENT"
cat >"$PORT_PREP" <<'SCRIPT'
#!/bin/sh
printf '%s\n' port-prep >>"$BIRD_TEST_EVENTS"
exit "${BIRD_TEST_PREP_STATUS:-0}"
SCRIPT
chmod 0755 "$PORT_PREP"
prepare_koreader_port_script() {
	printf '%s\n' wrapper-prepare >>"$CASE_DIR/events"
	: >"$KOREADER_PORT_SCRIPT"
}
remove_koreader_port_script() {
	printf '%s\n' wrapper-remove >>"$CASE_DIR/events"
	rm -f "$KOREADER_PORT_SCRIPT" "$KOREADER_PORT_TEMP"
}
run_managed() {
	printf '%s\n' managed >>"$CASE_DIR/events"
	: >"$CASE_DIR/args"
	for ARG in "$@"; do printf '%s\n' "$ARG" >>"$CASE_DIR/args"; done
	return "${BIRD_TEST_RUN_STATUS:-0}"
}
start_portmaster_network() {
	printf '%s\n' network-called >>"$CASE_DIR/events"
	return 99
}
prepare_portmaster_python_cache() { :; }
prepare_portmaster_battery_cache() { :; }

: >"$CASE_DIR/events"
BIRD_TEST_EVENTS=$CASE_DIR/events run_selected
[ ! -e "$KOREADER_PORT_SCRIPT" ]
[ "$(sed -n '1p' "$CASE_DIR/args")" = env ]
[ "$(sed -n '2p' "$CASE_DIR/args")" = "BIRD_EBOOK_PATH=$CONTENT" ]
[ "$(sed -n '3p' "$CASE_DIR/args")" = /usr/bin/runemu.sh ]
[ "$(sed -n '4p' "$CASE_DIR/args")" = "$KOREADER_PORT_SCRIPT" ]
[ "$(sed -n '5p' "$CASE_DIR/args")" = -Pports ]
[ "$(grep -c '^network-called$' "$CASE_DIR/events" || :)" -eq 0 ]
[ "$(sed -n '1p' "$CASE_DIR/events")" = port-prep ]
[ "$(sed -n '2p' "$CASE_DIR/events")" = wrapper-prepare ]
[ "$(sed -n '3p' "$CASE_DIR/events")" = managed ]
[ "$(sed -n '4p' "$CASE_DIR/events")" = wrapper-remove ]

: >"$CASE_DIR/events"
if BIRD_TEST_EVENTS=$CASE_DIR/events BIRD_TEST_RUN_STATUS=7 run_selected; then
	printf '%s\n' 'failed KOReader provider unexpectedly succeeded' >&2
	exit 1
else
	STATUS=$?
fi
[ "$STATUS" -eq 7 ]
[ ! -e "$KOREADER_PORT_SCRIPT" ]
grep -q '^wrapper-remove$' "$CASE_DIR/events"

for INVALID_HOST in \
	'/storage/media/READ/not-a-book.txt' \
	'/storage/media/WATCH/not-a-book.epub'; do
	HOST_PATH=$INVALID_HOST
	: >"$CASE_DIR/events"
	if BIRD_TEST_EVENTS=$CASE_DIR/events run_selected; then
		printf 'invalid KOReader host path accepted: %s\n' "$INVALID_HOST" >&2
		exit 1
	fi
	[ ! -s "$CASE_DIR/events" ]
done
EOF
chmod 0755 "$TMP/run-selected-koreader-harness.sh"
RUN_SELECTED_KOREADER_CASE=$TMP/run-selected-koreader
mkdir -p "$RUN_SELECTED_KOREADER_CASE"
"$TMP/run-selected-koreader-harness.sh" "$RUN_SELECTED_BODY" \
	"$RUN_SELECTED_KOREADER_CASE"

# Foreground signal/exit cleanup removes a prepared wrapper after the managed
# scope is gone. The embedded guard test above covers the SIGKILL edge.
KOREADER_CLEANUP_BODY=$TMP/koreader-cleanup-function.sh
python3 - "$RUNNER" "$KOREADER_CLEANUP_BODY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("cleanup_runtime() {")
end = source.index("\n\ncleanup_on_exit() {", start)
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
bash -n "$KOREADER_CLEANUP_BODY"
cat >"$TMP/koreader-cleanup-harness.sh" <<'EOF'
#!/bin/bash
set -eu
. "$1"
. "$2"
CASE_DIR=$3
CLEANUP_STATE=not-started
SCOPE_RUNNER_PID=
SCOPE_RUNNER_START_TICKS=
KOREADER_PORT_SCRIPT=$CASE_DIR/KOReader-cleanup.sh
KOREADER_PORT_TEMP=$KOREADER_PORT_SCRIPT.tmp
: >"$KOREADER_PORT_SCRIPT"
: >"$KOREADER_PORT_TEMP"
terminate_scope_until_gone() { :; }
release_owned_resources_until_done() { :; }
cleanup_runtime
[ "$CLEANUP_STATE" = succeeded ]
[ ! -e "$KOREADER_PORT_SCRIPT" ]
[ ! -e "$KOREADER_PORT_TEMP" ]
EOF
chmod 0755 "$TMP/koreader-cleanup-harness.sh"
KOREADER_CLEANUP_CASE=$TMP/koreader-cleanup
mkdir -p "$KOREADER_CLEANUP_CASE"
"$TMP/koreader-cleanup-harness.sh" "$KOREADER_FUNCTIONS" \
	"$KOREADER_CLEANUP_BODY" "$KOREADER_CLEANUP_CASE"

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
	BIRD_TEST_HOST_PATH='/storage/roms/SNES/game.sfc' "$RUNNER"
if BIRD_TEST_VALIDATE_HOST_PATH=1 \
	BIRD_TEST_HOST_PATH='/storage/roms/../secret' "$RUNNER"; then
	printf '%s\n' 'traversal path unexpectedly accepted' >&2
	exit 1
fi
if BIRD_TEST_VALIDATE_HOST_PATH=1 \
	BIRD_TEST_HOST_PATH="$(printf '/storage/roms/bad\rname')" "$RUNNER"; then
	printf '%s\n' 'control-delimited path unexpectedly accepted' >&2
	exit 1
fi
LONG_PATH=/storage/roms/$(awk 'BEGIN { for (i = 0; i < 4082; i++) printf "x" }')
if BIRD_TEST_VALIDATE_HOST_PATH=1 BIRD_TEST_HOST_PATH="$LONG_PATH" "$RUNNER"; then
	printf '%s\n' 'overlong path unexpectedly accepted' >&2
	exit 1
fi
if BIRD_TEST_VALIDATE_HOST_PATH=1 BIRD_TEST_EXTRA_LINE=1 \
	BIRD_TEST_HOST_PATH='/storage/roms/SNES/game.sfc' "$RUNNER"; then
	printf '%s\n' 'newline-extended request unexpectedly accepted' >&2
	exit 1
fi

[ "$(BIRD_TEST_SESSION_MODE=1 BIRD_TEST_SESSION_REQUEST=--rocknix \
	"$RUNNER")" = content ]
[ "$(BIRD_TEST_SESSION_MODE=1 BIRD_TEST_SESSION_REQUEST=--portmaster \
	"$RUNNER")" = portmaster ]
[ "$(BIRD_TEST_SESSION_MODE=1 \
	BIRD_TEST_SESSION_REQUEST=/run/bird/bird-launch-request "$RUNNER")" = \
	content ]

# Direct PortMaster must prepare its provider, require confirmed network
# readiness and only then enter its managed foreground scope.
python3 - "$RUNNER" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
cache_start = source.index('prepare_portmaster_python_cache() {')
cache_end = source.index('\n}\n', cache_start) + 2
cache_helper = source[cache_start:cache_end]
assert 'PORTMASTER_PYCACHE=/run/bird/portmaster-pycache' in cache_helper
assert 'export PYTHONPYCACHEPREFIX="$PORTMASTER_PYCACHE"' in cache_helper
assert 'export PYTHONDONTWRITEBYTECODE=1' in cache_helper
assert source.count('prepare_portmaster_python_cache || return 1') == 3
battery_start = source.index('prepare_portmaster_battery_cache() {')
battery_end = source.index('\n}\n', battery_start) + 2
battery_helper = source[battery_start:battery_end]
assert 'BIRD_PORTMASTER_POWER_LOG' in battery_helper
assert 'BIRD_PORTMASTER_BATTERY_CACHE' in battery_helper
assert 'capacity=([0-9]{1,3})' in battery_helper
assert 'PORTMASTER_BATTERY_CACHE}.bird-new.$$' in battery_helper
port_start = source.index('if [ "$SESSION_MODE" = portmaster ]; then')
port_end = source.index('\n\tcase "$KIND" in', port_start)
port_branch = source[port_start:port_end]
prepare = port_branch.index('"$PORT_PREP"')
cache_call = port_branch.index('prepare_portmaster_python_cache || return 1')
battery_call = port_branch.index('prepare_portmaster_battery_cache || {')
direct_network = port_branch.index('start_portmaster_network start')
readiness_gate = port_branch.index('[ "$PORTMASTER_NETWORK_STATUS" -eq 0 ]')
portmaster = port_branch.index('/usr/bin/start_portmaster.sh')
assert cache_call < prepare < battery_call < direct_network < readiness_gate < portmaster
PY

# The provider handoff chooses the newest valid power-owner sample, publishes
# one exact regular tmpfs file, and fails closed on path substitution.
PORTMASTER_BATTERY_FUNCTION=$TMP/portmaster-battery-function.sh
python3 - "$RUNNER" "$PORTMASTER_BATTERY_FUNCTION" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index('prepare_portmaster_battery_cache() {')
end = source.index('\n}\n', start) + 2
Path(sys.argv[2]).write_text(source[start:end] + '\n')
PY
bash -n "$PORTMASTER_BATTERY_FUNCTION"
PORTMASTER_BATTERY_CASE=$TMP/portmaster-battery
mkdir -p "$PORTMASTER_BATTERY_CASE"
cat >"$PORTMASTER_BATTERY_CASE/power.log" <<'EOF'
initial status=discharging capacity=51 low=no
event status=external-power capacity=unavailable low=no
event status=discharging capacity=49 low=no
EOF
(
	set -eu
	. "$PORTMASTER_BATTERY_FUNCTION"
	BIRD_PORTMASTER_POWER_LOG=$PORTMASTER_BATTERY_CASE/power.log
	BIRD_PORTMASTER_BATTERY_CACHE=$PORTMASTER_BATTERY_CASE/battery.percent
	export BIRD_PORTMASTER_POWER_LOG BIRD_PORTMASTER_BATTERY_CACHE
	prepare_portmaster_battery_cache
)
[ "$(cat "$PORTMASTER_BATTERY_CASE/battery.percent")" = 49 ]
[ "$(stat -f '%Lp' "$PORTMASTER_BATTERY_CASE/battery.percent")" = 644 ]
ln -s "$PORTMASTER_BATTERY_CASE/elsewhere" \
	"$PORTMASTER_BATTERY_CASE/battery-link"
if BIRD_PORTMASTER_POWER_LOG=$PORTMASTER_BATTERY_CASE/power.log \
	BIRD_PORTMASTER_BATTERY_CACHE=$PORTMASTER_BATTERY_CASE/battery-link \
	bash -c '. "$1"; prepare_portmaster_battery_cache' _ \
	"$PORTMASTER_BATTERY_FUNCTION"; then
	printf '%s\n' 'PortMaster battery cache accepted a symlink target' >&2
	exit 1
fi
printf '%s\n' 'capacity=unavailable' >"$PORTMASTER_BATTERY_CASE/power.log"
printf '%s\n' 47 >"$PORTMASTER_BATTERY_CASE/existing.percent"
BIRD_PORTMASTER_POWER_LOG=$PORTMASTER_BATTERY_CASE/power.log \
	BIRD_PORTMASTER_BATTERY_CACHE=$PORTMASTER_BATTERY_CASE/existing.percent \
	bash -c '. "$1"; prepare_portmaster_battery_cache' _ \
	"$PORTMASTER_BATTERY_FUNCTION" >/dev/null
[ "$(cat "$PORTMASTER_BATTERY_CASE/existing.percent")" = 47 ]

REQUEST_CASE=$TMP/request-record
printf '1\nsnes9x\nGame\n/storage/roms/SNES/game.sfc\n' >"$REQUEST_CASE"
BIRD_TEST_PARSE_LAUNCH_REQUEST=1 \
	BIRD_TEST_REQUEST_PATH="$REQUEST_CASE" "$RUNNER"
printf '1\nsnes9x\nGame\n/storage/roms/SNES/game.sfc\nfifth' \
	>"$REQUEST_CASE"
if BIRD_TEST_PARSE_LAUNCH_REQUEST=1 \
	BIRD_TEST_REQUEST_PATH="$REQUEST_CASE" "$RUNNER"; then
	printf '%s\n' 'unterminated fifth request line unexpectedly accepted' >&2
	exit 1
fi
printf '1\nsnes9x\nGame\n/storage/roms/SNES/game.sfc' >"$REQUEST_CASE"
if BIRD_TEST_PARSE_LAUNCH_REQUEST=1 \
	BIRD_TEST_REQUEST_PATH="$REQUEST_CASE" "$RUNNER"; then
	printf '%s\n' 'unterminated required request line unexpectedly accepted' >&2
	exit 1
fi

printf '%s\n' 'stock-root content-scope tests: PASS'
