#!/bin/sh
# App-scoped H700 clock diagnostics. Bird's menu never calls this. The source
# kernel's native CPU/GPU governors already reached 1.416 GHz and 648 MHz in
# hardware tests. Writing devfreq policy from userspace instead lowered the GPU
# ceiling to 600 MHz and repeatedly tripped the H700 PLL lock warning, so Bird
# now observes this boundary without perturbing it.

ACTION=${1:-snapshot}
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
	snapshot native-policy-preserved
}

leave() {
	snapshot native-policy-unchanged
}

case "$ACTION" in
	enter) enter ;;
	leave) leave ;;
	snapshot) snapshot observed ;;
	*) printf 'Usage: %s {enter|leave|snapshot}\n' "$0" >&2; exit 1 ;;
esac
