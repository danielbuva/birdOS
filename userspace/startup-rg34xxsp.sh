#!/bin/sh
# BIRD_FIXED_RG34XXSP_STARTUP_V2
# Fixed startup contract for the birdOS RG34XX-SP profile. The initramfs launcher is
# already interactive when this runs; this script prepares only the services
# needed by that one device and publishes runtime readiness for content.
# These completed-state markers keep the temporary card-side migration hook
# from trying to reapply superseded generic-script transforms.
# BOOT_TIMING_QUIET_STARTUP_V1
# BOOT_TIMING_BESPOKE_BACKGROUND_V1
# BOOT_TIMING_RESTORE_EARLY_ENTROPY_V2
# BIRD_EARLY_LAUNCHER_V1

. /opt/muos/script/var/func.sh

RUN_DIR="/run/muos"
TRACE="/tmp/muos/fixed-startup.tsv"
ROM_MOUNT="/mnt/mmc"

mkdir -p /tmp/muos "$RUN_DIR"
rm -f "$TRACE"
rm -rf /opt/muxtmp

mark() {
	read -r NOW _ </proc/uptime
	printf '%s\t%s\n' "$NOW" "$1" >>"$TRACE"
}

mark startup-begin

# Session state used by suspend, launch and stock-fallback paths.
read -r MU_UPTIME _ </proc/uptime
SET_VAR system resume_uptime "$MU_UPTIME"
SET_VAR device audio/ready 0
rm -f /opt/muos/device/config/screen/s_rotate \
	/opt/muos/device/config/screen/s_zoom &

# The launcher already requested performance mode in initramfs.  Repeat the
# fixed value after switch_root in case the kernel policy was recreated.
GOVERNOR=$(GET_VAR device cpu/governor)
printf '%s\n' performance >"$GOVERNOR"
mark core-state-ready

# Audio warms only after the system-ready marker. Mali is already loaded by
# fixed early hardware setup and SquashFS is built in on this kernel.
/opt/muos/script/system/pipewire.sh start &
ifconfig lo up &

# These independent fixed-device workers must never hold the visible menu.
/opt/muos/script/device/start.sh &
/opt/muos/script/mount/start.sh &
mark device-and-storage-dispatched

# Make system volume/brightness/power controls available while storage binds,
# instead of waiting for the complete ROM compatibility tree.
HOTKEY start
mark hotkeys-ready

echo 1 >"$MUOS_RUN_DIR/work_led_state"
: >"$MUOS_RUN_DIR/net_start"

# Content launchers may proceed only after the fixed storage service publishes
# its readiness marker.  Menu drawing and direct input remain independent.
until [ -f "$MUOS_STORE_DIR/mount_ready" ]; do sleep 0.01; done
mark storage-ready

# Charging state and LED policy are fixed handheld hardware work.  Preserve
# their proven ordering before publishing complete system readiness.
/opt/muos/script/device/charge.sh
LED_CONTROL_CHANGE
mark charge-and-led-ready

: >"$RUN_DIR/bird-system-ready"
if [ ! -e "$RUN_DIR/bird-launcher-active" ]; then
	FRONTEND start
fi
mark system-ready

# User init remains enabled for diagnostics and deliberate personal hooks.
/opt/muos/script/system/user_init.sh &

# Noninteractive maintenance stays outside the usable-menu path.
(
	sleep 12
	/opt/muos/script/system/lowpower.sh
) &
(
	sleep 20
	mkdir -p "$ROM_MOUNT/MUOS/log/dmesg"
	dmesg >"$ROM_MOUNT/MUOS/log/dmesg/dmesg__$(date +"%Y_%m_%d__%H_%M_%S").log"
) &

mark startup-complete
