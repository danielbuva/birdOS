#!/bin/bash
# Focused host coverage for post-coldplug udev quiescence and on-demand seatd.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
UDEV=$ROOT/kernel/rocknix/stock-root/bird-udev-idle.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-managers.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
EVENTS=$TMP/events
STATE=$TMP/state
: >"$EVENTS"

cat >"$TMP/udevadm" <<'EOF'
#!/bin/sh
printf 'udevadm %s\n' "$*" >>"$BIRD_TEST_EVENTS"
[ "${BIRD_TEST_SETTLE_FAIL:-0}" -eq 0 ]
EOF
cat >"$TMP/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >>"$BIRD_TEST_EVENTS"
case "$1" in
	stop) [ "${BIRD_TEST_STOP_FAIL:-0}" -eq 0 ] ;;
	show) printf '%s\n' "${BIRD_TEST_STATE:-inactive}" ;;
esac
EOF
cat >"$TMP/timeout" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
	case "$1" in --signal=*|--kill-after=*) shift ;; *) break ;; esac
done
[ "$1" = 3s ] && shift
exec "$@"
EOF
chmod 0755 "$TMP/udevadm" "$TMP/systemctl" "$TMP/timeout"
export BIRD_TEST_EVENTS=$EVENTS

BIRD_UDEVADM=$TMP/udevadm BIRD_SYSTEMCTL=$TMP/systemctl \
BIRD_TIMEOUT=$TMP/timeout "$UDEV" >"$STATE"
cat >"$TMP/expected" <<'EOF'
udevadm settle --timeout=10
systemctl stop systemd-udevd.service
systemctl show --property=ActiveState --value systemd-udevd.service
EOF
cmp "$TMP/expected" "$EVENTS"
grep -Fxq 'fixed_udev_manager=inactive sockets=retained' "$STATE"

for FAILURE in settle stop active; do
	: >"$EVENTS"
	case "$FAILURE" in
		settle) SETTLE=1; STOP=0; ACTIVE=inactive ;;
		stop) SETTLE=0; STOP=1; ACTIVE=inactive ;;
		active) SETTLE=0; STOP=0; ACTIVE=active ;;
	esac
	if BIRD_TEST_SETTLE_FAIL=$SETTLE BIRD_TEST_STOP_FAIL=$STOP \
		BIRD_TEST_STATE=$ACTIVE BIRD_UDEVADM=$TMP/udevadm \
		BIRD_SYSTEMCTL=$TMP/systemctl BIRD_TIMEOUT=$TMP/timeout \
		"$UDEV" >/dev/null 2>&1; then
		printf 'udev manager failure was accepted: %s\n' "$FAILURE" >&2
		exit 1
	fi
done

grep -Fqx 'ConditionPathExists=/run/bird/seat-request' \
	"$ROOT/kernel/rocknix/stock-root/bird-seatd.service"
grep -Fq 'request_seatd() {' "$ROOT/kernel/rocknix/stock-root/run-content.sh"
grep -Fq 'release_seatd() {' "$ROOT/kernel/rocknix/stock-root/run-content.sh"
grep -Fq 'rm -f /run/bird/seat-request' \
	"$ROOT/kernel/rocknix/stock-root/run-content.sh"

printf '%s\n' 'stock-root fixed manager tests passed'
