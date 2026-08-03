#!/bin/sh
# Preserve the RG34XX-SP's adjustable CPU boost setting through its one fixed
# H700 sysfs endpoint instead of loading the generic settings profile.

set -u

SETTINGS=${BIRD_SETTINGS:-/storage/.config/system/configs/system.cfg}
TURBO=${BIRD_TURBO_PATH:-/sys/devices/system/cpu/cpufreq/boost}
BIRD_TURBO=0

if [ -f "$SETTINGS" ]; then
	while IFS='=' read -r BIRD_KEY BIRD_VALUE; do
		if [ "$BIRD_KEY" = enable.turbo-mode ]; then
			BIRD_TURBO=$BIRD_VALUE
			break
		fi
	done <"$SETTINGS"
fi

[ "$BIRD_TURBO" = 1 ] || BIRD_TURBO=0
[ -f "$TURBO" ] || exit 1
printf '%s\n' "$BIRD_TURBO" >"$TURBO" || exit 1
printf 'fixed_turbo=%s\n' "$BIRD_TURBO"
