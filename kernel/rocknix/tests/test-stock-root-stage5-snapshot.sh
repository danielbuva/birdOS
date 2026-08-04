#!/bin/bash
# Focused host coverage for request-only Stage 5 structural counter capture.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SCRIPT=$ROOT/kernel/rocknix/stock-root/capture-stage5-state.sh
WINDOW=$ROOT/kernel/rocknix/stock-root/capture-stage5-window-counters.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-stage5-snapshot.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
PROC=$TMP/proc
SYS=$TMP/sys
mkdir -p "$PROC/42" "$SYS/kernel/debug" \
	"$SYS/devices/system/cpu/cpu0/cpuidle/state1" \
	"$SYS/class/power_supply/battery"

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
	"$SCRIPT" >"$TMP/output"
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
START_INTERRUPTS=$(grep -n '^--- interrupts ---$' "$TMP/start" | cut -d: -f1)
END_SCHEDULER=$(grep -n '^--- scheduler counters ---$' "$TMP/end" | cut -d: -f1)
END_INTERRUPTS=$(grep -n '^--- interrupts ---$' "$TMP/end" | cut -d: -f1)
[ "$START_SCHEDULER" -gt "$START_INTERRUPTS" ]
[ "$END_SCHEDULER" -lt "$END_INTERRUPTS" ]
if BIRD_PROC_ROOT=$PROC BIRD_SYS_ROOT=$SYS "$WINDOW" invalid >/dev/null 2>&1; then
	printf '%s\n' 'invalid Stage 5 counter mode was accepted' >&2
	exit 1
fi

printf '%s\n' 'stock-root Stage 5 snapshot tests passed'
