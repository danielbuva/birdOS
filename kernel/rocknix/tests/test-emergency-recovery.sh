#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
HELPER=$ROOT/kernel/rocknix/stock-root/bird-emergency-recover.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-emergency-recovery.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

PROC=$TMP/proc
RUN=$TMP/run
LOG_ROOT=$TMP/log/emergency
BIN=$TMP/bin
EVENTS=$TMP/events
mkdir -p "$PROC/sys/kernel/random" "$PROC/pressure" "$PROC/4242" \
	"$RUN/muos" "$RUN/bird" "$LOG_ROOT" "$BIN"
printf '%s\n' 12345678-1234-1234-1234-123456789abc \
	>"$PROC/sys/kernel/random/boot_id"
printf '%s\n' '12.34 56.78' >"$PROC/uptime"
printf '%s\n' 'MemTotal: 1024 kB' >"$PROC/meminfo"
printf '%s\n' 'some avg10=0.00' >"$PROC/pressure/cpu"
printf '%s\n' 'some avg10=0.00' >"$PROC/pressure/io"
printf '%s\n' 'some avg10=0.00' >"$PROC/pressure/memory"
printf '%s\n' '4242 (bird-launcher) S 1 2 3' >"$PROC/4242/stat"
ln -s /opt/bird/bird-launcher "$PROC/4242/exe"
printf '%s\n' 4242 >"$RUN/muos/initramfs-launcher.pid"
printf '%s\n' request >"$RUN/muos/bird-launch-request"
printf '%s\n' 10 >"$RUN/muos/bird-launch-action"
printf '%s\n' state >"$RUN/bird/content-runner-test.state"

cat >"$BIN/timeout" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
	case "$1" in
		--signal=*|--kill-after=*|[0-9]*s) shift ;;
		*) break ;;
	esac
done
exec "$@"
EOF
cat >"$BIN/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >>"$BIRD_TEST_EVENTS"
case "$1" in
	list-units) printf '%s\n' 'essway.service loaded active running' ;;
	show) printf '%s\n' 'Id=essway.service' 'ActiveState=active' ;;
	restart) exit "${BIRD_TEST_RESTART_STATUS:-0}" ;;
esac
EOF
cat >"$BIN/sync" <<'EOF'
#!/bin/sh
printf 'sync %s\n' "$*" >>"$BIRD_TEST_EVENTS"
EOF
cat >"$BIN/signal" <<'EOF'
#!/bin/sh
printf 'signal %s\n' "$*" >>"$BIRD_TEST_EVENTS"
EOF
cat >"$BIN/usleep" <<'EOF'
#!/bin/sh
exit 0
EOF
for PROGRAM in journalctl dmesg ps; do
	cat >"$BIN/$PROGRAM" <<EOF
#!/bin/sh
printf '%s output\n' '$PROGRAM'
EOF
done
cat >"$BIN/exit-helper" <<'EOF'
#!/bin/sh
printf '%s\n' exit-helper >>"$BIRD_TEST_EVENTS"
exit 0
EOF
chmod 0755 "$BIN"/*

BIRD_TEST_EVENTS=$EVENTS \
BIRD_EMERGENCY_LOG_ROOT=$LOG_ROOT \
BIRD_EMERGENCY_PROC_ROOT=$PROC \
BIRD_EMERGENCY_RUN_ROOT=$RUN \
BIRD_EMERGENCY_EXIT_HELPER=$BIN/exit-helper \
BIRD_EMERGENCY_SYSTEMCTL=$BIN/systemctl \
BIRD_EMERGENCY_TIMEOUT=$BIN/timeout \
BIRD_EMERGENCY_SYNC=$BIN/sync \
BIRD_EMERGENCY_SIGNAL=$BIN/signal \
BIRD_EMERGENCY_USLEEP=$BIN/usleep \
BIRD_EMERGENCY_JOURNALCTL=$BIN/journalctl \
BIRD_EMERGENCY_DMESG=$BIN/dmesg \
BIRD_EMERGENCY_PS=$BIN/ps \
	"$HELPER"

LOG=$(find "$LOG_ROOT" -type f -name 'emergency-recovery-*.log')
[ -n "$LOG" ] && [ -f "$LOG" ]
grep -Fq 'Bird emergency recovery version=1' "$LOG"
grep -Fq 'snapshot_complete=1' "$LOG"
grep -Fq 'foreground_exit_status=0' "$LOG"
grep -Fq 'pending_action_cancelled=1' "$LOG"
grep -Fq 'early_launcher_action=kill' "$LOG"
grep -Fq 'ui_restart_status=0' "$LOG"
[ ! -e "$RUN/muos/bird-launch-request" ]
[ ! -e "$RUN/muos/bird-launch-action" ]
grep -Fq 'exit-helper' "$EVENTS"
grep -Fq 'signal -TERM 4242' "$EVENTS"
grep -Fq 'signal -KILL 4242' "$EVENTS"
grep -Fq 'systemctl restart --no-block essway.service' "$EVENTS"
FIRST_SYNC=$(grep -n '^sync ' "$EVENTS" | head -n 1 | cut -d: -f1)
RESTART=$(grep -n '^systemctl restart ' "$EVENTS" | cut -d: -f1)
[ "$FIRST_SYNC" -lt "$RESTART" ]

sh -n "$HELPER"
printf '%s\n' 'emergency recovery tests: PASS'
