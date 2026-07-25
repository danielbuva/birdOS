#!/bin/sh
# Deterministic starting-to-active publication race for the global exit path.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
HELPER=$ROOT/kernel/rocknix/stock-root/bird-fixed-control-exit.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-exit-publication.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/log"

BOOT_ID=11111111-2222-3333-4444-555555555555
TOKEN=11111111-42-100
INVOCATION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
UNIT=bird-content-11111111-42-100.scope
SESSION=$TMP/content-session.pid
LOCK=$TMP/content-session.lock
READY=$TMP/publisher.ready
RELEASE=$TMP/publisher.release
SIGNALS=$TMP/state/signals
LOG=$TMP/log/content-exit.log
printf '%s\n' "$BOOT_ID" >"$TMP/boot-id"
printf '%s\n' '1.00 0.00' >"$TMP/uptime"
printf '%s\n' active >"$TMP/state/active"
: >"$SIGNALS"

cat >"$TMP/bin/usleep" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$TMP/bin/flock" <<'PY'
#!/usr/bin/env python3
import fcntl
import sys

fd = int(sys.argv[-1])
fcntl.flock(fd, fcntl.LOCK_UN if "-u" in sys.argv[1:] else fcntl.LOCK_EX)
PY
cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/sh
set -eu
case "$1" in
	show)
		PROPERTY=
		for ARG in "$@"; do
			case "$ARG" in --property=*) PROPERTY=${ARG#--property=} ;; esac
		done
		case "$PROPERTY" in
			InvocationID) printf '%s\n' "$MOCK_INVOCATION" ;;
			ActiveState) cat "$MOCK_STATE/active" ;;
			LoadState) printf '%s\n' loaded ;;
			*) exit 1 ;;
		esac
		;;
	list-units)
		printf '%s loaded active running test\n' "$MOCK_UNIT"
		;;
	kill)
		SIGNAL=
		for ARG in "$@"; do
			case "$ARG" in --signal=*) SIGNAL=${ARG#--signal=} ;; esac
		done
		printf '%s\n' "$SIGNAL" >>"$MOCK_STATE/signals"
		printf '%s\n' inactive >"$MOCK_STATE/active"
		;;
	*) exit 1 ;;
esac
EOF
cat >"$TMP/publisher.py" <<'PY'
#!/usr/bin/env python3
import fcntl
import os
from pathlib import Path
import sys
import time

lock_path, session_path, ready_path, release_path = map(Path, sys.argv[1:5])
boot_id, token, invocation, unit = sys.argv[5:9]

def publish(state, invocation_id, control_group):
    temporary = session_path.with_name(session_path.name + ".publisher")
    temporary.write_text(
        "version=2\n"
        "boundary=systemd-scope\n"
        f"state={state}\n"
        f"session_token={token}\n"
        f"boot_id={boot_id}\n"
        f"unit={unit}\n"
        f"invocation_id={invocation_id}\n"
        f"control_group={control_group}\n"
    )
    os.replace(temporary, session_path)

with lock_path.open("a+") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    publish("starting", "pending", "")
    ready_path.touch()
    while not release_path.exists():
        time.sleep(0.005)
    publish("active", invocation, "/bird-test.scope")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
PY
chmod 0755 "$TMP/bin/usleep" "$TMP/bin/flock" "$TMP/bin/systemctl" \
	"$TMP/publisher.py"

run_helper() {
	REQUIRE_RECORD=${1:-0}
	PATH="$TMP/bin:$PATH" MOCK_STATE="$TMP/state" \
	MOCK_INVOCATION="$INVOCATION" MOCK_UNIT="$UNIT" \
	BIRD_SESSION_PID="$SESSION" BIRD_SESSION_LOCK="$LOCK" \
	BIRD_REQUIRE_SESSION_RECORD="$REQUIRE_RECORD" \
	BIRD_EXIT_LOG="$LOG" BIRD_BOOT_ID_PATH="$TMP/boot-id" \
	BIRD_UPTIME_PATH="$TMP/uptime" "$HELPER"
}

# Command substitution normally erases trailing newlines. An unterminated
# eighth field must remain malformed, produce no signal and preserve the only
# recovery record rather than being normalized into a valid snapshot.
{
	printf '%s\n' 'version=2' 'boundary=systemd-scope' 'state=active'
	printf 'session_token=%s\nboot_id=%s\nunit=%s\ninvocation_id=%s\n' \
		"$TOKEN" "$BOOT_ID" "$UNIT" "$INVOCATION"
	printf '%s' 'control_group=/bird-test.scope'
} >"$SESSION"
if run_helper 1; then
	printf '%s\n' 'unterminated metadata unexpectedly passed validation' >&2
	exit 1
else
	[ "$?" -eq 2 ]
fi
[ ! -s "$SIGNALS" ]
[ -e "$SESSION" ]
grep -q 'none-or-invalid action=none' "$LOG"

python3 "$TMP/publisher.py" "$LOCK" "$SESSION" "$READY" "$RELEASE" \
	"$BOOT_ID" "$TOKEN" "$INVOCATION" "$UNIT" &
PUBLISHER_PID=$!
while [ ! -e "$READY" ]; do sleep 0.01; done

run_helper 0 &
EXIT_PID=$!

# A helper that reads unlocked fields can run before the active publication.
# The fixed helper must still be blocked and must not have signaled anything.
sleep 0.10
if [ -s "$SIGNALS" ] || ! kill -0 "$EXIT_PID" 2>/dev/null; then
	printf '%s\n' 'exit helper bypassed coherent metadata publication' >&2
	kill "$PUBLISHER_PID" "$EXIT_PID" 2>/dev/null || :
	exit 1
fi

: >"$RELEASE"
wait "$PUBLISHER_PID"
wait "$EXIT_PID"
[ "$(cat "$SIGNALS")" = TERM ]
[ ! -e "$SESSION" ]
grep -q 'state=empty' "$LOG"
sh -n "$HELPER"
printf '%s\n' 'fixed-control exit publication tests: PASS'
