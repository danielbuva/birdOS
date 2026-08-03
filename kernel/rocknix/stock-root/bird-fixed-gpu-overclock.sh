#!/bin/sh
# Keep the RG34XX-SP's user-selectable H700 GPU overclock without loading the
# generic platform/profile stack. Both frequencies come from the fixed device
# contract and the retained DT/driver capture.

set -u

SETTINGS=${BIRD_SETTINGS:-/storage/.config/system/configs/system.cfg}
GPU_MAX=${BIRD_GPU_MAX:-/sys/devices/platform/soc/1800000.gpu/devfreq/1800000.gpu/max_freq}
BIRD_GPU_OC=0

if [ -f "$SETTINGS" ]; then
	while IFS='=' read -r BIRD_KEY BIRD_VALUE; do
		if [ "$BIRD_KEY" = enable.gpu-overclock ]; then
			BIRD_GPU_OC=$BIRD_VALUE
			break
		fi
	done <"$SETTINGS"
fi

case "$BIRD_GPU_OC" in
	1) BIRD_GPU_HZ=648000000 ;;
	*) BIRD_GPU_OC=0; BIRD_GPU_HZ=600000000 ;;
esac

[ -f "$GPU_MAX" ] || exit 1
printf '%s\n' "$BIRD_GPU_HZ" >"$GPU_MAX" || exit 1
printf 'fixed_gpu_overclock=%s max_hz=%s\n' "$BIRD_GPU_OC" "$BIRD_GPU_HZ"
