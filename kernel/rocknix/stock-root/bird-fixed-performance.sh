#!/bin/sh
# Apply only the adjustable CPU/core and GPU-governor policy supported by the
# fixed RG34XX-SP. The generic helper discovered policies, devfreq devices and
# CPU counts for many boards on every boot.

set -u

MODE=${1:-prepare}
SETTINGS=${BIRD_SETTINGS:-/storage/.config/system/configs/system.cfg}
CPU_ROOT=${BIRD_CPU_ROOT:-/sys/devices/system/cpu}
CPU_POLICY=${BIRD_CPU_POLICY:-$CPU_ROOT/cpufreq/policy0}
GPU_ROOT=${BIRD_GPU_ROOT:-/sys/devices/platform/soc/1800000.gpu/devfreq/1800000.gpu}

read_setting() {
	BIRD_SETTING=
	[ -f "$SETTINGS" ] || return 0
	while IFS='=' read -r BIRD_KEY BIRD_VALUE; do
		if [ "$BIRD_KEY" = "$1" ]; then
			BIRD_SETTING=$BIRD_VALUE
			return 0
		fi
	done <"$SETTINGS"
}

apply_threads() {
	read_setting system.threads
	case "$BIRD_SETTING" in
		1) BIRD_ONLINE=0 ;;
		2) BIRD_ONLINE=1 ;;
		3) BIRD_ONLINE=2 ;;
		4|all|default|'') BIRD_ONLINE=3 ;;
		*) BIRD_ONLINE=3 ;;
	esac

	BIRD_CPU=1
	while [ "$BIRD_CPU" -le 3 ]; do
		BIRD_NODE=$CPU_ROOT/cpu$BIRD_CPU/online
		[ -f "$BIRD_NODE" ] || return 1
		if [ "$BIRD_CPU" -le "$BIRD_ONLINE" ]; then
			printf '1\n' >"$BIRD_NODE" || return 1
		else
			printf '0\n' >"$BIRD_NODE" || return 1
		fi
		BIRD_CPU=$((BIRD_CPU + 1))
	done
	printf 'fixed_performance_threads=%s\n' "${BIRD_SETTING:-all}"
}

apply_gpu_governor() {
	read_setting system.gpuperf
	case "$BIRD_SETTING" in
		''|auto|default|ondemand|simple_ondemand)
			BIRD_GPU_GOVERNOR=simple_ondemand
			;;
		performance|powersave|userspace)
			BIRD_GPU_GOVERNOR=$BIRD_SETTING
			;;
		*)
			BIRD_GPU_GOVERNOR=simple_ondemand
			;;
	esac
	[ -f "$GPU_ROOT/governor" ] || return 1
	printf '%s\n' "$BIRD_GPU_GOVERNOR" >"$GPU_ROOT/governor" || return 1
	printf 'fixed_performance_gpu=%s\n' "$BIRD_GPU_GOVERNOR"
}

apply_cpu_governor() {
	read_setting system.cpugovernor
	case "$BIRD_SETTING" in
		conservative|ondemand|userspace|powersave|performance|schedutil)
			BIRD_CPU_GOVERNOR=$BIRD_SETTING
			;;
		*)
			BIRD_CPU_GOVERNOR=ondemand
			;;
	esac
	[ -f "$CPU_POLICY/scaling_governor" ] || return 1
	printf '%s\n' "$BIRD_CPU_GOVERNOR" >"$CPU_POLICY/scaling_governor" || return 1
	printf 'fixed_performance_cpu=%s\n' "$BIRD_CPU_GOVERNOR"
}

case "$MODE" in
	prepare)
		apply_threads && apply_gpu_governor
		;;
	governor)
		apply_cpu_governor
		;;
	*)
		printf 'unknown fixed performance mode: %s\n' "$MODE" >&2
		exit 2
		;;
esac
