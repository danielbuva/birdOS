#!/bin/sh
# Request-only structural sample for Stage 5 comparisons. Counter snapshots are
# deliberately instantaneous: calibrated energy and rates are computed outside
# this process so the sampler's own work is never presented as an idle result.

set -u

PROC_ROOT=${BIRD_PROC_ROOT:-/proc}
SYS_ROOT=${BIRD_SYS_ROOT:-/sys}
LABEL=${BIRD_STAGE5_LABEL:-unspecified}

case "$LABEL" in
	*[!A-Za-z0-9_.-]*|'') LABEL=invalid ;;
esac

printf 'bird_stage5_snapshot_version=1 label=%s\n' "$LABEL"
if IFS=' ' read -r UPTIME _REST <"$PROC_ROOT/uptime"; then
	printf 'uptime_seconds=%s\n' "$UPTIME"
else
	printf '%s\n' 'uptime_seconds=unavailable'
fi

printf '%s\n' '--- scheduler counters ---'
if [ -r "$PROC_ROOT/stat" ]; then
	awk '/^(cpu([0-9]+)? |ctxt |intr |processes |procs_running |procs_blocked )/' \
		"$PROC_ROOT/stat"
fi

printf '%s\n' '--- process pss and uss KiB ---'
PSS_AVAILABLE=0
for ROLLUP in "$PROC_ROOT"/[0-9]*/smaps_rollup; do
	[ -e "$ROLLUP" ] || continue
	PID_ROOT=${ROLLUP%/smaps_rollup}
	PID=${PID_ROOT##*/}
	PSS=0
	PRIVATE_KIB=0
	PSS_SEEN=0
	if { while IFS=' ' read -r KEY VALUE _REST; do
		case "$KEY" in
			Pss:) PSS=$((PSS + VALUE)); PSS_SEEN=1 ;;
			Private_Clean:|Private_Dirty:|Private_Hugetlb:)
				PRIVATE_KIB=$((PRIVATE_KIB + VALUE))
				;;
		esac
	done <"$ROLLUP"; } 2>/dev/null && [ "$PSS_SEEN" -eq 1 ]; then
		COMM=unknown
		[ ! -r "$PID_ROOT/comm" ] || IFS= read -r COMM <"$PID_ROOT/comm"
		printf 'pid=%s comm=%s pss_kib=%s uss_kib=%s\n' \
			"$PID" "$COMM" "$PSS" "$PRIVATE_KIB"
		PSS_AVAILABLE=1
	fi
done
[ "$PSS_AVAILABLE" -eq 1 ] || printf '%s\n' 'smaps_rollup=unavailable'

printf '%s\n' '--- wakeup sources ---'
if [ -r "$SYS_ROOT/kernel/debug/wakeup_sources" ]; then
	cat "$SYS_ROOT/kernel/debug/wakeup_sources"
else
	printf '%s\n' 'wakeup_sources=unavailable'
fi

printf '%s\n' '--- interrupts ---'
[ ! -r "$PROC_ROOT/interrupts" ] || cat "$PROC_ROOT/interrupts"
printf '%s\n' '--- softirqs ---'
[ ! -r "$PROC_ROOT/softirqs" ] || cat "$PROC_ROOT/softirqs"

printf '%s\n' '--- cpu idle counters ---'
for STATE_ROOT in "$SYS_ROOT"/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*; do
	[ -d "$STATE_ROOT" ] || continue
	CPU=${STATE_ROOT%/cpuidle/*}
	CPU=${CPU##*/}
	STATE=${STATE_ROOT##*/}
	NAME=unknown
	TIME=unavailable
	USAGE=unavailable
	[ ! -r "$STATE_ROOT/name" ] || IFS= read -r NAME <"$STATE_ROOT/name"
	[ ! -r "$STATE_ROOT/time" ] || IFS= read -r TIME <"$STATE_ROOT/time"
	[ ! -r "$STATE_ROOT/usage" ] || IFS= read -r USAGE <"$STATE_ROOT/usage"
	printf 'cpu=%s state=%s name=%s time_us=%s usage=%s\n' \
		"$CPU" "$STATE" "$NAME" "$TIME" "$USAGE"
done

printf '%s\n' '--- battery counters ---'
for SUPPLY_ROOT in "$SYS_ROOT"/class/power_supply/*; do
	[ -d "$SUPPLY_ROOT" ] || continue
	SUPPLY=${SUPPLY_ROOT##*/}
	for PROPERTY in status capacity voltage_now current_now charge_now \
		energy_now power_now online; do
		[ -r "$SUPPLY_ROOT/$PROPERTY" ] || continue
		IFS= read -r VALUE <"$SUPPLY_ROOT/$PROPERTY" || VALUE=unavailable
		printf 'supply=%s property=%s value=%s\n' \
			"$SUPPLY" "$PROPERTY" "$VALUE"
	done
done
