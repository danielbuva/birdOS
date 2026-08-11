#!/bin/bash
# Host-only regression coverage for the final-root supervisor's fail-stopped
# launcher ownership and request-dispatch contracts.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SUPERVISOR=$ROOT/kernel/rocknix/stock-root/supervisor.sh
SERVICE=$ROOT/kernel/rocknix/stock-root/essway.service
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-supervisor.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

grep -Fq 'LAUNCHER=/flash/bird/bird-launcher' "$SUPERVISOR"
grep -Fq 'RUNNER=/flash/bird/run-content.sh' "$SUPERVISOR"
grep -Fq 'INPUT_TESTER=/flash/bird/bird-input-tester' "$SUPERVISOR"
grep -Fq 'PIDWAIT=/flash/bird/bird-pidwait' "$SUPERVISOR"
grep -Fq 'bird launcher startup failure reason=%s result=%s; stopping' \
	"$SUPERVISOR"
grep -Fq 'bird launcher unexpected post-frame exit=%s; stopping' "$SUPERVISOR"
grep -Fqx 'Restart=no' "$SERVICE"

if grep -Eq 'KERNEL\.fallback|extlinux\.fallback|ATTEMPTS|boot-attempt|reset_boot_attempts|systemctl reboot --force|startup_backoff|runtime_backoff' \
		"$SUPERVISOR" "$SERVICE"; then
	printf '%s\n' 'automatic launcher recovery remains in final-root supervisor' >&2
	exit 1
fi

# Preserve the small pure helpers used by content diagnostics and atomic
# handoff parsing, including their strict terminating-newline contract.
FUNCTIONS=$TMP/functions.sh
awk '
	/^classify_exit_status\(\) \{/,/^}/ {print; next}
	/^read_single_line_file\(\) \{/,/^}/ {print; next}
' "$SUPERVISOR" >"$FUNCTIONS"
# shellcheck source=/dev/null
. "$FUNCTIONS"

classify_exit_status 0
[ "$CONTENT_EXIT_CLASS" = success ]
classify_exit_status 7
[ "$CONTENT_EXIT_CLASS" = exit-7 ]
classify_exit_status 137
[ "$CONTENT_EXIT_CLASS" = sigkill ]
classify_exit_status 143
[ "$CONTENT_EXIT_CLASS" = sigterm ]

LINE=$TMP/line
printf '10\n' >"$LINE"
read_single_line_file "$LINE"
[ "$SINGLE_LINE_VALUE" = 10 ]
printf '10' >"$LINE"
! read_single_line_file "$LINE"
printf '10\n11\n' >"$LINE"
! read_single_line_file "$LINE"

grep -Fq '10) consume_handoff_action && run_content "$REQUEST" ;;' "$SUPERVISOR"
grep -Fq '11) consume_handoff_action && request_poweroff ;;' "$SUPERVISOR"
grep -Fq '12) consume_handoff_action && run_content --portmaster ;;' "$SUPERVISOR"
grep -Fq '14) consume_handoff_action && request_reboot ;;' "$SUPERVISOR"
grep -Fq '15) consume_handoff_action && run_input_tester ;;' "$SUPERVISOR"
grep -Fq '15) run_input_tester ;;' "$SUPERVISOR"
grep -Fq 'bird input tester result=%s class=%s uptime=' "$SUPERVISOR"
grep -Fq 'wait_content_cleanup' "$SUPERVISOR"
grep -Fq 'early_launcher_adoptable' "$SUPERVISOR"
grep -Fq 'retire_early_launcher' "$SUPERVISOR"

printf '%s\n' 'stock-root supervisor tests passed'
