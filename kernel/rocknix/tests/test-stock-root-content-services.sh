#!/bin/sh
# Verify content service startup stays demand-driven for fixed-provider sessions.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
RUNNER=$ROOT/kernel/rocknix/stock-root/run-content.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-content-services.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

extract_ensure_content_services() {
	python3 - "$RUNNER" "$TMP/run-content-services.sh" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text().splitlines()
start = None
end = None
for index, line in enumerate(source):
	if line.startswith('ensure_content_services() {'):
		start = index
		break
if start is None:
	raise SystemExit('ensure_content_services function not found')
for index in range(start + 1, len(source)):
	if source[index].startswith('stop_sway() {'):
		end = index
		break
if end is None:
	raise SystemError('matching stop_sway() marker not found')
Path(sys.argv[2]).write_text("\n".join(source[start:end]) + "\n")
PY
}

make_runner_harness() {
	cat >"$TMP/runner-harness.sh" <<'EOF'
#!/bin/sh
set -eu

. "$1"

[ -n "${BIRD_TEST_EVENT_ROOT:-}" ] || {
	printf 'BIRD_TEST_EVENT_ROOT missing\n' >&2
	exit 1
}

content_stage() {
	:
}

systemctl() {
	printf '%s\n' "$*" >>"$BIRD_TEST_EVENTS"
}

assert_contains() {
	FILE=$1
	PATTERN=$2
	if ! grep -Fq -- "$PATTERN" "$FILE"; then
		printf 'missing expected event: %s\n' "$PATTERN" >&2
		exit 1
	fi
}

assert_absent() {
	FILE=$1
	PATTERN=$2
	if grep -Fq -- "$PATTERN" "$FILE"; then
		printf 'unexpected event present: %s\n' "$PATTERN" >&2
		exit 1
	fi
}

test_case() {
	SESSION_MODE=$1
	KIND=$2
	BIRD_TEST_EVENTS=$3
	export BIRD_TEST_EVENTS
	: >"$BIRD_TEST_EVENTS"
	ensure_content_services
}

for KIND in 1 2 3 4 5 7; do
	test_case content "$KIND" "$BIRD_TEST_EVENT_ROOT/events-content-$KIND"
	assert_contains "$BIRD_TEST_EVENT_ROOT/events-content-$KIND" 'start dbus.service'
	assert_absent "$BIRD_TEST_EVENT_ROOT/events-content-$KIND" 'start pipewire.service'
	assert_absent "$BIRD_TEST_EVENT_ROOT/events-content-$KIND" 'bird-volume.sh restore'
done

test_case content 6 "$BIRD_TEST_EVENT_ROOT/events-content-6"
assert_contains "$BIRD_TEST_EVENT_ROOT/events-content-6" 'start dbus.service'
assert_contains "$BIRD_TEST_EVENT_ROOT/events-content-6" \
	'start pipewire.service wireplumber.service pipewire-pulse.service'
assert_contains "$BIRD_TEST_EVENT_ROOT/events-content-6" 'bird-volume.sh restore'

test_case portmaster 1 "$BIRD_TEST_EVENT_ROOT/events-portmaster-1"
assert_contains "$BIRD_TEST_EVENT_ROOT/events-portmaster-1" 'start dbus.service'
assert_absent "$BIRD_TEST_EVENT_ROOT/events-portmaster-1" \
	'start pipewire.service wireplumber.service pipewire-pulse.service'
assert_absent "$BIRD_TEST_EVENT_ROOT/events-portmaster-1" 'bird-volume.sh restore'

printf '%s\n' 'stock-root content services tests passed'
EOF
	chmod 0755 "$TMP/runner-harness.sh"
}

extract_ensure_content_services

cat >"$TMP/timeout" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$BIRD_TEST_EVENTS"
exit 0
EOF
chmod 0755 "$TMP/timeout"
export BIRD_TEST_EVENT_ROOT=$TMP
export TIMEOUT_PROGRAM=$TMP/timeout

make_runner_harness

sh "$TMP/runner-harness.sh" "$TMP/run-content-services.sh"

