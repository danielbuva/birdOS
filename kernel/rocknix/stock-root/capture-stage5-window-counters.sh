#!/bin/sh
# Minimal paired-counter endpoint. Start records the broad counters first and
# scheduler totals last; end records scheduler totals first. The timed scheduler
# delta therefore excludes the start sampler's structural reads.

set -u

PROC_ROOT=${BIRD_PROC_ROOT:-/proc}
SYS_ROOT=${BIRD_SYS_ROOT:-/sys}
MODE=${1:-}
case "$MODE" in start|end) ;; *) exit 2 ;; esac

capture_scheduler() {
	printf '%s\n' '--- scheduler counters ---'
	[ ! -r "$PROC_ROOT/stat" ] || \
		awk '/^(cpu([0-9]+)? |ctxt |intr |processes |procs_running |procs_blocked )/' \
			"$PROC_ROOT/stat"
}

capture_structural() {
	printf '%s\n' '--- process scheduler counters ---'
	for PID_ROOT in "$PROC_ROOT"/[0-9]*; do
		[ -d "$PID_ROOT" ] || continue
		PID=${PID_ROOT##*/}
		COMM=unknown
		RUNTIME_NS=unavailable
		WAIT_NS=unavailable
		TIMESLICES=unavailable
		VOLUNTARY=unavailable
		NONVOLUNTARY=unavailable
		[ ! -r "$PID_ROOT/comm" ] || IFS= read -r COMM <"$PID_ROOT/comm"
		if [ -r "$PID_ROOT/schedstat" ]; then
			IFS=' ' read -r RUNTIME_NS WAIT_NS TIMESLICES \
				<"$PID_ROOT/schedstat" || continue
		fi
		if [ -r "$PID_ROOT/status" ]; then
			while IFS=' 	' read -r KEY VALUE _REST; do
				case "$KEY" in
					voluntary_ctxt_switches:)
						VOLUNTARY=$VALUE
						;;
					nonvoluntary_ctxt_switches:)
						NONVOLUNTARY=$VALUE
						;;
				esac
			done <"$PID_ROOT/status" 2>/dev/null || continue
		fi
		printf 'pid=%s comm=%s runtime_ns=%s wait_ns=%s timeslices=%s voluntary=%s nonvoluntary=%s\n' \
			"$PID" "$COMM" "$RUNTIME_NS" "$WAIT_NS" "$TIMESLICES" \
			"$VOLUNTARY" "$NONVOLUNTARY"
	done
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
}

printf 'bird_stage5_window_version=1 mode=%s\n' "$MODE"
if [ "$MODE" = start ]; then
	capture_structural
	capture_scheduler
else
	capture_scheduler
	capture_structural
fi
