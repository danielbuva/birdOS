#!/bin/sh
# BIRD_FIXED_RG34XXSP_DEVICE_START_V1

# Brightness, suspend and manual display controls use Allwinner's debugfs
# interface.  Mount it once; there is no per-board discovery.
grep -q ' /sys/kernel/debug debugfs ' /proc/mounts 2>/dev/null ||
	mount -t debugfs debugfs /sys/kernel/debug

# No display value is written after the menu appears.  The bootloader handoff
# remains untouched; final fixed colour/brightness belongs in firmware.
# Apply the one required fixed normal-stereo mixer map without board branches.
(
	amixer -q -c 0 set 'OutputL Mixer DACL' on
	amixer -q -c 0 set 'OutputL Mixer DACR' off
	amixer -q -c 0 set 'OutputR Mixer DACL' off
	amixer -q -c 0 set 'OutputR Mixer DACR' on
) &

# The SP lid is the only device-specific resident worker required here.
/opt/muos/script/device/lid.sh start &
