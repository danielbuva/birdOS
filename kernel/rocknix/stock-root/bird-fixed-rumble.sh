#!/bin/sh
# Preserve the RG34XX-SP's built-in PWM vibrator and its user setting while
# avoiding the generic recursive scan of every platform sysfs device.

set -u

SETTINGS=${BIRD_SETTINGS:-/storage/.config/system/configs/system.cfg}
RUMBLE=${BIRD_RUMBLE_PATH:-/sys/devices/platform/rocknix-singleadc-joypad/rumble_enable}
BIRD_RUMBLE=1

if [ -f "$SETTINGS" ]; then
	while IFS='=' read -r BIRD_KEY BIRD_VALUE; do
		if [ "$BIRD_KEY" = rumble.enabled ]; then
			BIRD_RUMBLE=$BIRD_VALUE
			break
		fi
	done <"$SETTINGS"
fi

[ "$BIRD_RUMBLE" = 0 ] || BIRD_RUMBLE=1
[ -f "$RUMBLE" ] || exit 1
printf '%s\n' "$BIRD_RUMBLE" >"$RUMBLE" || exit 1
printf 'fixed_rumble=%s\n' "$BIRD_RUMBLE"
