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
	/^content_process_identity_status\(\) \{/,/^}/ {print; next}
	/^content_cleanup_guard_active\(\) \{/,/^}/ {print; next}
	/^content_network_owner_matches\(\) \{/,/^}/ {print; next}
	/^content_cleanup_is_background_network\(\) \{/,/^}/ {print; next}
	/^content_cleanup_pending\(\) \{/,/^}/ {print; next}
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

cat >"$TMP/fake-timeout" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
	case "$1" in
		--signal=*|--kill-after=*|1s) shift ;;
		*) break ;;
	esac
done
exec "$@"
EOF
cat >"$TMP/fake-systemctl" <<'EOF'
#!/bin/sh
cat "$BIRD_TEST_GUARD_ACTIVE"
EOF
chmod 0755 "$TMP/fake-timeout" "$TMP/fake-systemctl"
CONTENT_STATE_DIR=$TMP/content-state
NETWORK_OWNER=$TMP/network-owner
PROCESS_PROC_ROOT=$TMP/proc
CONTENT_TIMEOUT_PROGRAM=$TMP/fake-timeout
CONTENT_SYSTEMCTL_PROGRAM=$TMP/fake-systemctl
BIRD_TEST_GUARD_ACTIVE=$TMP/guard-active
export BIRD_TEST_GUARD_ACTIVE
BOOT_ID_FULL=12345678-aaaa-bbbb-cccc-123456789abc
BOOT_ID=12345678
RUNNER_PID=4242
RUNNER_START=777
TOKEN=$BOOT_ID-$RUNNER_PID-$RUNNER_START
STATE=$CONTENT_STATE_DIR/content-runner-$TOKEN.state
mkdir -p "$CONTENT_STATE_DIR" "$PROCESS_PROC_ROOT"
printf '%s\n' active >"$BIRD_TEST_GUARD_ACTIVE"
printf '%s\n' "$TOKEN" >"$NETWORK_OWNER"
write_background_state() {
	printf '%s\n' \
		version=2 \
		armed=1 \
		"session_token=$TOKEN" \
		"boot_id=$BOOT_ID_FULL" \
		"runner_pid=$RUNNER_PID" \
		"runner_start_ticks=$RUNNER_START" \
		scope_expected=0 \
		scope_unit= \
		scope_invocation=none \
		scope_runner_pid= \
		scope_runner_start_ticks= \
		sway_owned=0 \
		network_owned=1 \
		cleanup_mode=background-network-active \
		"guard_unit=bird-content-guard-$TOKEN.service" \
		"session_log=/storage/bird-data/Bird/log/stock-root-content-$BOOT_ID-12345-portmaster.log" \
		>"$STATE"
}

write_background_state
! content_cleanup_pending

sed 's/cleanup_mode=background-network-active/cleanup_mode=background-network-pending/' \
	"$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
mkdir -p "$PROCESS_PROC_ROOT/$RUNNER_PID"
printf '%s\n' \
	"$RUNNER_PID (bird runner) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 $RUNNER_START 20" \
	>"$PROCESS_PROC_ROOT/$RUNNER_PID/stat"
content_cleanup_pending
printf '%s\n' malformed >"$PROCESS_PROC_ROOT/$RUNNER_PID/stat"
content_cleanup_pending
printf '%s\n' \
	"$RUNNER_PID (replacement) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 778 20" \
	>"$PROCESS_PROC_ROOT/$RUNNER_PID/stat"
! content_cleanup_pending
rm -rf "$PROCESS_PROC_ROOT/$RUNNER_PID"

sed 's/cleanup_mode=background-network-active/cleanup_mode=foreground/' "$STATE" \
	>"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's/scope_expected=0/scope_expected=1/' "$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's/^armed=1$/armed=0/' "$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's/^scope_unit=$/scope_unit=bird-content-stale.scope/' "$STATE" \
	>"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's/^scope_invocation=none$/scope_invocation=stale/' "$STATE" \
	>"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's/^sway_owned=0$/sway_owned=1/' "$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's/^network_owned=1$/network_owned=0/' "$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's/^version=2$/version=1/' "$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's/^boot_id=.*/boot_id=wrong-boot/' "$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's/^guard_unit=.*/guard_unit=wrong.service/' "$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
sed 's#^session_log=.*#session_log=/storage/bird-data/Bird/log/wrong.log#' \
	"$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
awk 'NR == 1 { first = $0; next } NR == 2 { print; print first; next } { print }' \
	"$STATE" >"$STATE.next"
mv -f "$STATE.next" "$STATE"
content_cleanup_pending

write_background_state
WRONG_STATE=$CONTENT_STATE_DIR/content-runner-wrong.state
mv "$STATE" "$WRONG_STATE"
content_cleanup_pending
mv "$WRONG_STATE" "$STATE"

write_background_state
printf '%s' "$(cat "$STATE")" >"$STATE"
content_cleanup_pending

write_background_state
printf '%s\n' unexpected=field >>"$STATE"
content_cleanup_pending

write_background_state
printf '%s\n' replacement-owner >"$NETWORK_OWNER"
content_cleanup_pending

write_background_state
: >"$NETWORK_OWNER"
content_cleanup_pending

printf '%s' "$TOKEN" >"$NETWORK_OWNER"
content_cleanup_pending

printf '%s\n%s\n' "$TOKEN" extra >"$NETWORK_OWNER"
content_cleanup_pending

printf '%s\n' "$TOKEN" >"$TMP/network-owner-target"
rm -f "$NETWORK_OWNER"
ln -s "$TMP/network-owner-target" "$NETWORK_OWNER"
content_cleanup_pending
rm -f "$NETWORK_OWNER"

write_background_state
printf '%s\n' "$TOKEN" >"$NETWORK_OWNER"
printf '%s\n' malformed >"$CONTENT_STATE_DIR/content-runner-invalid.state"
content_cleanup_pending
rm -f "$CONTENT_STATE_DIR/content-runner-invalid.state"
! content_cleanup_pending

printf '%s\n' "$TOKEN" >"$NETWORK_OWNER"
printf '%s\n' inactive >"$BIRD_TEST_GUARD_ACTIVE"
content_cleanup_pending

printf '%s\n' active >"$BIRD_TEST_GUARD_ACTIVE"
rm -f "$STATE"
ln -s "$TMP/missing-state" "$STATE"
content_cleanup_pending
rm -f "$STATE"
! content_cleanup_pending

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
