#!/bin/bash
# Focused host coverage for request-only Stage 5 structural counter capture.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SCRIPT=$ROOT/kernel/rocknix/stock-root/capture-stage5-state.sh
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
grep -Fxq 'pid=42 pss_kib=120 uss_kib=54' "$TMP/output"
grep -Fxq 'cpu=cpu0 state=state1 name=WFI time_us=5000 usage=7' "$TMP/output"
grep -Fxq 'supply=battery property=status value=Discharging' "$TMP/output"
grep -Fxq 'supply=battery property=capacity value=70' "$TMP/output"
grep -Fxq 'irq evidence' "$TMP/output"

BIRD_PROC_ROOT=$PROC BIRD_SYS_ROOT=$SYS BIRD_STAGE5_LABEL='bad label' \
	"$SCRIPT" >"$TMP/invalid"
grep -Fxq 'bird_stage5_snapshot_version=1 label=invalid' "$TMP/invalid"

printf '%s\n' 'stock-root Stage 5 snapshot tests passed'
