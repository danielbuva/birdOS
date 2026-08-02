#!/bin/bash
# Host coverage for the post-recovery fixed suspend-policy verifier. Production
# uses fixed absolute paths; test overrides keep every effect in this directory.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SOURCE=$ROOT/kernel/rocknix/stock-root/bird-restore-suspend-policy.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-suspend-policy.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
POLICY=$TMP/policy.sh
CONFIG=$TMP/system.cfg
FIXED_SLEEP=$TMP/fixed-sleep.conf
SLEEP_CONFIG=$TMP/sleep.conf
PROVIDER=$TMP/suspendmode
BUSYBOX=$TMP/busybox
EVENTS=$TMP/events
BUSYBOX_EVENTS=$TMP/busybox-events

printf '%s\n' 'BIRD_SUSPEND_PROVIDER_MODE=off' >"$POLICY"
printf '%s\n' '[Sleep]' 'AllowSuspend=no' >"$FIXED_SLEEP"

cat >"$PROVIDER" <<'EOF'
#!/bin/bash
printf 'mode=%s\n' "$1" >>"$BIRD_SUSPEND_TEST_EVENTS"
[ "$1" = off ] || exit 2
[ "${BIRD_SUSPEND_TEST_STATUS:-0}" -eq 0 ] || exit "$BIRD_SUSPEND_TEST_STATUS"
/usr/bin/awk '!/^system[.]suspendmode=/' "$BIRD_SUSPEND_TEST_CONFIG" \
	>"$BIRD_SUSPEND_TEST_CONFIG.tmp"
printf '%s\n' 'system.suspendmode=off' >>"$BIRD_SUSPEND_TEST_CONFIG.tmp"
/bin/mv -f "$BIRD_SUSPEND_TEST_CONFIG.tmp" "$BIRD_SUSPEND_TEST_CONFIG"
printf '%s\n' '[Sleep]' 'AllowSuspend=no' >"$BIRD_SUSPEND_TEST_SLEEP"
EOF
chmod 0755 "$PROVIDER"

cat >"$BUSYBOX" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$BIRD_SUSPEND_TEST_BUSYBOX_EVENTS"
APPLET=$1
shift
case "$APPLET" in
	cmp) exec /usr/bin/cmp "$@" ;;
	cp) exec /bin/cp "$@" ;;
	chmod) exec /bin/chmod "$@" ;;
	mv) exec /bin/mv "$@" ;;
	rm) exec /bin/rm "$@" ;;
	*) exit 2 ;;
esac
EOF
chmod 0755 "$BUSYBOX"

export BIRD_SUSPEND_TEST_EVENTS=$EVENTS
export BIRD_SUSPEND_TEST_CONFIG=$CONFIG
export BIRD_SUSPEND_TEST_SLEEP=$SLEEP_CONFIG
export BIRD_SUSPEND_TEST_BUSYBOX_EVENTS=$BUSYBOX_EVENTS

run_policy() {
	BIRD_SUSPEND_POLICY=$POLICY \
	BIRD_SUSPEND_CONFIG=$CONFIG \
	BIRD_SUSPEND_FIXED_SLEEP=$FIXED_SLEEP \
	BIRD_SUSPEND_SLEEP_CONFIG=$SLEEP_CONFIG \
	BIRD_SUSPENDMODE_PROGRAM=$PROVIDER \
	BIRD_SUSPEND_BUSYBOX=$BUSYBOX \
		"$SOURCE"
}

# Model the returned-card failure after chksysconfig restored vendor defaults:
# no provider mode and AllowSuspend=yes. The fixed common/009 verifier must
# restore both before returning success.
printf '%s\n' 'system.suspend.enable=1' >"$CONFIG"
printf '%s\n' '[Sleep]' 'AllowSuspend=yes' >"$SLEEP_CONFIG"
: >"$EVENTS"
: >"$BUSYBOX_EVENTS"
run_policy
grep -Fxq 'system.suspendmode=off' "$CONFIG"
cmp "$FIXED_SLEEP" "$SLEEP_CONFIG"
grep -Fxq 'mode=off' "$EVENTS"

# A stale sleep file paired with an already-correct mode must be repaired
# without calling ROCKNIX's mode transaction or restarting logind.
printf '%s\n' 'system.suspendmode=off' >"$CONFIG"
printf '%s\n' '[Sleep]' 'AllowSuspend=yes' >"$SLEEP_CONFIG"
: >"$EVENTS"
: >"$BUSYBOX_EVENTS"
run_policy
[ ! -s "$EVENTS" ]
cmp "$FIXED_SLEEP" "$SLEEP_CONFIG"
grep -q '^cp -f ' "$BUSYBOX_EVENTS"

# The accepted steady state performs comparisons only and writes nothing.
: >"$EVENTS"
: >"$BUSYBOX_EVENTS"
run_policy
[ ! -s "$EVENTS" ]
[ "$(grep -c '^cmp -s ' "$BUSYBOX_EVENTS")" -eq 2 ]
! grep -Eq '^(cp|chmod|mv|rm) ' "$BUSYBOX_EVENTS"

BIRD_SUSPEND_TEST_STATUS=37
export BIRD_SUSPEND_TEST_STATUS
printf '%s\n' 'system.suspendmode=mem' >"$CONFIG"
set +e
run_policy
STATUS=$?
set -e
[ "$STATUS" -eq 1 ]
unset BIRD_SUSPEND_TEST_STATUS

printf '%s\n' 'BIRD_SUSPEND_PROVIDER_MODE=mem' >"$POLICY"
: >"$EVENTS"
set +e
run_policy
STATUS=$?
set -e
[ "$STATUS" -eq 1 ]
[ ! -s "$EVENTS" ]

printf '%s\n' 'stock-root suspend-policy tests: PASS'
