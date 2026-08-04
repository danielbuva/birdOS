#!/bin/bash
# Focused host coverage for request-only Stage 5 structural counter capture.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SCRIPT=$ROOT/kernel/rocknix/stock-root/capture-stage5-state.sh
WINDOW=$ROOT/kernel/rocknix/stock-root/capture-stage5-window-counters.sh
ACQUIRE=$ROOT/kernel/rocknix/stock-root/capture-stage5-window.sh
DISPATCH=$ROOT/kernel/rocknix/stock-root/capture-requested-diagnostics.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-stage5-snapshot.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
PROC=$TMP/proc
SYS=$TMP/sys
mkdir -p "$PROC/42" "$SYS/kernel/debug" \
	"$SYS/devices/system/cpu/cpu0/cpuidle/state1" \
	"$SYS/class/power_supply/battery"
mkdir -p "$PROC/43/smaps_rollup"

printf '%s\n' '12.50 2.00' >"$PROC/uptime"
cat >"$PROC/stat" <<'EOF'
cpu  1 2 3 4 5 6 7 8 9 10
cpu0 1 2 3 4 5 6 7 8 9 10
ctxt 99
processes 4
procs_running 1
procs_blocked 0
EOF
cat >"$PROC/42/smaps_rollup" <<'EOF'
Pss:                  120 kB
Private_Clean:         20 kB
Private_Dirty:         30 kB
Private_Hugetlb:        4 kB
EOF
printf '%s\n' 'bird-launcher' >"$PROC/42/comm"
printf '%s\n' '1000 2000 3' >"$PROC/42/schedstat"
cat >"$PROC/42/status" <<'EOF'
Name:	bird-launcher
voluntary_ctxt_switches:	4
nonvoluntary_ctxt_switches:	5
EOF
printf '%s\n' 'irq evidence' >"$PROC/interrupts"
printf '%s\n' 'softirq evidence' >"$PROC/softirqs"
printf '%s\n' 'name active_count event_count' >"$SYS/kernel/debug/wakeup_sources"
printf '%s\n' 'WFI' >"$SYS/devices/system/cpu/cpu0/cpuidle/state1/name"
printf '%s\n' '5000' >"$SYS/devices/system/cpu/cpu0/cpuidle/state1/time"
printf '%s\n' '7' >"$SYS/devices/system/cpu/cpu0/cpuidle/state1/usage"
printf '%s\n' 'Discharging' >"$SYS/class/power_supply/battery/status"
printf '%s\n' '70' >"$SYS/class/power_supply/battery/capacity"

BIRD_PROC_ROOT=$PROC BIRD_SYS_ROOT=$SYS BIRD_STAGE5_LABEL=menu-idle \
	"$SCRIPT" >"$TMP/output" 2>"$TMP/stderr"
[ ! -s "$TMP/stderr" ]
grep -Fxq 'bird_stage5_snapshot_version=1 label=menu-idle' "$TMP/output"
grep -Fxq 'uptime_seconds=12.50' "$TMP/output"
grep -Fxq 'pid=42 comm=bird-launcher pss_kib=120 uss_kib=54' "$TMP/output"
grep -Fxq 'cpu=cpu0 state=state1 name=WFI time_us=5000 usage=7' "$TMP/output"
grep -Fxq 'supply=battery property=status value=Discharging' "$TMP/output"
grep -Fxq 'supply=battery property=capacity value=70' "$TMP/output"
grep -Fxq 'irq evidence' "$TMP/output"

BIRD_PROC_ROOT=$PROC BIRD_SYS_ROOT=$SYS BIRD_STAGE5_LABEL='bad label' \
	"$SCRIPT" >"$TMP/invalid"
grep -Fxq 'bird_stage5_snapshot_version=1 label=invalid' "$TMP/invalid"

BIRD_PROC_ROOT=$PROC BIRD_SYS_ROOT=$SYS "$WINDOW" start >"$TMP/start"
BIRD_PROC_ROOT=$PROC BIRD_SYS_ROOT=$SYS "$WINDOW" end >"$TMP/end"
grep -Fxq 'bird_stage5_window_version=1 mode=start' "$TMP/start"
grep -Fxq 'bird_stage5_window_version=1 mode=end' "$TMP/end"
grep -Fxq 'pid=42 comm=bird-launcher runtime_ns=1000 wait_ns=2000 timeslices=3 voluntary=4 nonvoluntary=5' "$TMP/start"
START_SCHEDULER=$(grep -n '^--- scheduler counters ---$' "$TMP/start" | cut -d: -f1)
START_PROCESSES=$(grep -n '^--- process scheduler counters ---$' "$TMP/start" | cut -d: -f1)
END_SCHEDULER=$(grep -n '^--- scheduler counters ---$' "$TMP/end" | cut -d: -f1)
END_PROCESSES=$(grep -n '^--- process scheduler counters ---$' "$TMP/end" | cut -d: -f1)
[ "$START_SCHEDULER" -gt "$START_PROCESSES" ]
[ "$END_SCHEDULER" -lt "$END_PROCESSES" ]
if BIRD_PROC_ROOT=$PROC BIRD_SYS_ROOT=$SYS "$WINDOW" invalid >/dev/null 2>&1; then
	printf '%s\n' 'invalid Stage 5 counter mode was accepted' >&2
	exit 1
fi

mkdir -p "$TMP/log"
printf '%s\n' 'state=menu-idle' >"$TMP/request"
printf '%s\n' '12345678-rest' >"$TMP/boot-id"
cat >"$TMP/counters" <<'EOF'
#!/bin/sh
printf 'counter=%s\n' "$1"
EOF
cat >"$TMP/snapshot" <<'EOF'
#!/bin/sh
printf 'snapshot=%s\n' "$BIRD_STAGE5_LABEL"
EOF
cat >"$TMP/sleep" <<'EOF'
#!/bin/sh
printf 'sleep=%s\n' "$1"
EOF
chmod +x "$TMP/counters" "$TMP/snapshot" "$TMP/sleep"
BIRD_STAGE5_REQUEST=$TMP/request BIRD_STAGE5_LOG_DIR=$TMP/log \
	BIRD_STAGE5_COUNTERS=$TMP/counters BIRD_STAGE5_SNAPSHOT=$TMP/snapshot \
	BIRD_STAGE5_SLEEP=$TMP/sleep BIRD_STAGE5_BOOT_ID_FILE=$TMP/boot-id \
	"$ACQUIRE"
[ ! -e "$TMP/request" ]
ACQUIRED=$TMP/log/stage5-window-12345678-menu-idle.log
cmp "$ACQUIRED" "$TMP/log/stage5-window-latest.log"
grep -Fxq 'bird_stage5_acquisition_version=1 state=menu-idle' "$ACQUIRED"
grep -Fxq 'settle_seconds=30 window_seconds=60' "$ACQUIRED"
grep -Fxq 'sleep=30' "$ACQUIRED"
grep -Fxq 'counter=start' "$ACQUIRED"
grep -Fxq 'sleep=60' "$ACQUIRED"
grep -Fxq 'counter=end' "$ACQUIRED"
grep -Fxq 'snapshot=menu-idle-final' "$ACQUIRED"

printf '%s\n' 'state=invalid' >"$TMP/request"
if BIRD_STAGE5_REQUEST=$TMP/request BIRD_STAGE5_LOG_DIR=$TMP/log \
	BIRD_STAGE5_COUNTERS=$TMP/counters BIRD_STAGE5_SNAPSHOT=$TMP/snapshot \
	BIRD_STAGE5_SLEEP=$TMP/sleep BIRD_STAGE5_BOOT_ID_FILE=$TMP/boot-id \
	"$ACQUIRE" >/dev/null 2>&1; then
	printf '%s\n' 'invalid Stage 5 acquisition state was accepted' >&2
	exit 1
fi
[ -e "$TMP/request" ]

printf '%s\n' '#!/bin/sh' 'printf stage5' >"$TMP/stage5-capture"
printf '%s\n' '#!/bin/sh' 'printf boot' >"$TMP/boot-capture"
chmod +x "$TMP/stage5-capture" "$TMP/boot-capture"
: >"$TMP/stage5-request"
: >"$TMP/boot-request"
BIRD_STAGE5_REQUEST=$TMP/stage5-request \
	BIRD_BOOT_DIAGNOSTICS_REQUEST=$TMP/boot-request \
	BIRD_STAGE5_CAPTURE=$TMP/stage5-capture \
	BIRD_BOOT_DIAGNOSTICS_CAPTURE=$TMP/boot-capture \
	"$DISPATCH" >"$TMP/dispatched"
[ "$(cat "$TMP/dispatched")" = stage5 ]
rm "$TMP/stage5-request"
BIRD_STAGE5_REQUEST=$TMP/stage5-request \
	BIRD_BOOT_DIAGNOSTICS_REQUEST=$TMP/boot-request \
	BIRD_STAGE5_CAPTURE=$TMP/stage5-capture \
	BIRD_BOOT_DIAGNOSTICS_CAPTURE=$TMP/boot-capture \
	"$DISPATCH" >"$TMP/dispatched"
[ "$(cat "$TMP/dispatched")" = boot ]

printf '%s\n' 'stock-root Stage 5 snapshot tests passed'
