#!/bin/bash
# Host fault-injection tests for adjustable fixed RG34XX-SP performance and
# rumble policies.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
FIXED=$ROOT/kernel/rocknix/stock-root
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-performance.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

SETTINGS=$TMP/system.cfg
CPU=$TMP/cpu
POLICY=$CPU/cpufreq/policy0
GPU=$TMP/gpu
RUMBLE=$TMP/rumble_enable
TURBO=$TMP/boost
mkdir -p "$POLICY" "$GPU"
for CORE in 1 2 3; do
	mkdir -p "$CPU/cpu$CORE"
	printf '1\n' >"$CPU/cpu$CORE/online"
done
printf 'performance\n' >"$POLICY/scaling_governor"
printf 'performance\n' >"$GPU/governor"
printf '600000000\n' >"$GPU/max_freq"
printf '0\n' >"$RUMBLE"
printf '0\n' >"$TURBO"

cat >"$SETTINGS" <<'EOF'
system.threads=2
system.cpugovernor=schedutil
system.gpuperf=performance
enable.gpu-overclock=1
enable.turbo-mode=1
rumble.enabled=0
EOF

BIRD_SETTINGS=$SETTINGS BIRD_CPU_ROOT=$CPU BIRD_CPU_POLICY=$POLICY \
BIRD_GPU_ROOT=$GPU "$FIXED/bird-fixed-performance.sh" prepare
[ "$(<"$CPU/cpu1/online")" = 1 ]
[ "$(<"$CPU/cpu2/online")" = 0 ]
[ "$(<"$CPU/cpu3/online")" = 0 ]
[ "$(<"$GPU/governor")" = performance ]

BIRD_SETTINGS=$SETTINGS BIRD_CPU_ROOT=$CPU BIRD_CPU_POLICY=$POLICY \
BIRD_GPU_ROOT=$GPU "$FIXED/bird-fixed-performance.sh" governor
[ "$(<"$POLICY/scaling_governor")" = schedutil ]

BIRD_SETTINGS=$SETTINGS BIRD_GPU_MAX=$GPU/max_freq \
	"$FIXED/bird-fixed-gpu-overclock.sh"
[ "$(<"$GPU/max_freq")" = 648000000 ]
BIRD_SETTINGS=$SETTINGS BIRD_TURBO_PATH=$TURBO "$FIXED/bird-fixed-turbo.sh"
[ "$(<"$TURBO")" = 1 ]
BIRD_SETTINGS=$SETTINGS BIRD_RUMBLE_PATH=$RUMBLE "$FIXED/bird-fixed-rumble.sh"
[ "$(<"$RUMBLE")" = 0 ]

# Missing and malformed settings resolve to the safe fixed defaults without
# mutating persistent configuration.
cat >"$SETTINGS" <<'EOF'
system.threads=bogus
system.cpugovernor=bogus
system.gpuperf=bogus
enable.gpu-overclock=bogus
enable.turbo-mode=bogus
rumble.enabled=bogus
EOF
BEFORE=$(shasum -a 256 "$SETTINGS" | awk '{print $1}')
BIRD_SETTINGS=$SETTINGS BIRD_CPU_ROOT=$CPU BIRD_CPU_POLICY=$POLICY \
BIRD_GPU_ROOT=$GPU "$FIXED/bird-fixed-performance.sh" prepare
for CORE in 1 2 3; do [ "$(<"$CPU/cpu$CORE/online")" = 1 ]; done
[ "$(<"$GPU/governor")" = simple_ondemand ]
BIRD_SETTINGS=$SETTINGS BIRD_CPU_ROOT=$CPU BIRD_CPU_POLICY=$POLICY \
BIRD_GPU_ROOT=$GPU "$FIXED/bird-fixed-performance.sh" governor
[ "$(<"$POLICY/scaling_governor")" = ondemand ]
BIRD_SETTINGS=$SETTINGS BIRD_GPU_MAX=$GPU/max_freq \
	"$FIXED/bird-fixed-gpu-overclock.sh"
[ "$(<"$GPU/max_freq")" = 600000000 ]
BIRD_SETTINGS=$SETTINGS BIRD_TURBO_PATH=$TURBO "$FIXED/bird-fixed-turbo.sh"
[ "$(<"$TURBO")" = 0 ]
BIRD_SETTINGS=$SETTINGS BIRD_RUMBLE_PATH=$RUMBLE "$FIXED/bird-fixed-rumble.sh"
[ "$(<"$RUMBLE")" = 1 ]
[ "$BEFORE" = "$(shasum -a 256 "$SETTINGS" | awk '{print $1}')" ]

# Every advertised fixed-device value remains selectable.
for GOV in conservative ondemand userspace powersave performance schedutil; do
	printf 'system.cpugovernor=%s\n' "$GOV" >"$SETTINGS"
	BIRD_SETTINGS=$SETTINGS BIRD_CPU_ROOT=$CPU BIRD_CPU_POLICY=$POLICY \
	BIRD_GPU_ROOT=$GPU "$FIXED/bird-fixed-performance.sh" governor >/dev/null
	[ "$(<"$POLICY/scaling_governor")" = "$GOV" ]
done
for GOV in userspace powersave performance simple_ondemand; do
	printf 'system.gpuperf=%s\n' "$GOV" >"$SETTINGS"
	BIRD_SETTINGS=$SETTINGS BIRD_CPU_ROOT=$CPU BIRD_CPU_POLICY=$POLICY \
	BIRD_GPU_ROOT=$GPU "$FIXED/bird-fixed-performance.sh" prepare >/dev/null
	[ "$(<"$GPU/governor")" = "$GOV" ]
done

if rg -n 'find |/etc/profile|get_setting|set_setting|099-freqfunctions|001-functions' \
	"$FIXED/bird-fixed-performance.sh" \
	"$FIXED/bird-fixed-gpu-overclock.sh" \
	"$FIXED/bird-fixed-rumble.sh" \
	"$FIXED/bird-fixed-turbo.sh"; then
	printf '%s\n' 'generic discovery or profile helper returned' >&2
	exit 1
fi

printf '%s\n' 'stock-root fixed performance tests passed'
