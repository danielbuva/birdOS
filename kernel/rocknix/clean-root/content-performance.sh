#!/bin/sh
# App-scoped H700 performance policy and diagnostics. Bird's menu never calls
# this: expensive clocks are raised only for content that benefits from them,
# then the previous governors are restored before the launcher redraws.

ACTION=${1:-snapshot}
STATE=/run/bird/content-performance-state
GPU=/sys/devices/platform/soc/1800000.gpu/devfreq/1800000.gpu

read_value() {
	[ -r "$1" ] && cat "$1" || printf '%s\n' unavailable
}

snapshot() {
	printf 'performance stage=%s uptime=' "$1"
	cut -d ' ' -f 1 /proc/uptime
	for POLICY in /sys/devices/system/cpu/cpufreq/policy*; do
		[ -d "$POLICY" ] || continue
		printf 'cpu policy=%s governor=%s current_khz=%s min_khz=%s max_khz=%s\n' \
			"${POLICY##*/}" \
			"$(read_value "$POLICY/scaling_governor")" \
			"$(read_value "$POLICY/scaling_cur_freq")" \
			"$(read_value "$POLICY/scaling_min_freq")" \
			"$(read_value "$POLICY/scaling_max_freq")"
	done
	if [ -d "$GPU" ]; then
		printf 'gpu governor=%s current_hz=%s min_hz=%s max_hz=%s available=%s\n' \
			"$(read_value "$GPU/governor")" \
			"$(read_value "$GPU/cur_freq")" \
			"$(read_value "$GPU/min_freq")" \
			"$(read_value "$GPU/max_freq")" \
			"$(read_value "$GPU/available_frequencies")"
	else
		printf '%s\n' 'gpu devfreq=unavailable'
	fi
}

enter() {
	rm -rf "$STATE"
	mkdir -p "$STATE"
	for POLICY in /sys/devices/system/cpu/cpufreq/policy*; do
		[ -w "$POLICY/scaling_governor" ] || continue
		NAME=${POLICY##*/}
		cat "$POLICY/scaling_governor" >"$STATE/cpu-$NAME"
		printf '%s\n' performance >"$POLICY/scaling_governor" || :
	done
	if [ -w "$GPU/governor" ]; then
		cat "$GPU/governor" >"$STATE/gpu-governor"
		[ ! -r "$GPU/max_freq" ] || cat "$GPU/max_freq" >"$STATE/gpu-max"
		# 600 MHz is ROCKNIX's normal H700 ceiling. 648 MHz remains an
		# explicit overclock and is not part of Bird's fixed default.
		[ ! -w "$GPU/max_freq" ] || printf '%s\n' 600000000 >"$GPU/max_freq"
		printf '%s\n' performance >"$GPU/governor" || :
	fi
	snapshot entered
}

leave() {
	for SAVED in "$STATE"/cpu-*; do
		[ -f "$SAVED" ] || continue
		NAME=${SAVED##*/cpu-}
		TARGET=/sys/devices/system/cpu/cpufreq/$NAME/scaling_governor
		[ ! -w "$TARGET" ] || cat "$SAVED" >"$TARGET" || :
	done
	if [ -f "$STATE/gpu-max" ] && [ -w "$GPU/max_freq" ]; then
		cat "$STATE/gpu-max" >"$GPU/max_freq" || :
	fi
	if [ -f "$STATE/gpu-governor" ] && [ -w "$GPU/governor" ]; then
		cat "$STATE/gpu-governor" >"$GPU/governor" || :
	fi
	snapshot restored
	rm -rf "$STATE"
}

case "$ACTION" in
	enter) enter ;;
	leave) leave ;;
	snapshot) snapshot observed ;;
	*) printf 'Usage: %s {enter|leave|snapshot}\n' "$0" >&2; exit 1 ;;
esac
