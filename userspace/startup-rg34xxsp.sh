#!/bin/sh
# DANI_FIXED_RG34XXSP_STARTUP_V1
# Fixed startup contract for Dani's RG34XX-SP.  The initramfs launcher is
# already interactive when this runs; this script prepares only the services
# needed by that one device and publishes runtime readiness for content.
# These completed-state markers keep the temporary card-side migration hook
# from trying to reapply superseded generic-script transforms.
# BOOT_TIMING_QUIET_STARTUP_V1
# BOOT_TIMING_BESPOKE_BACKGROUND_V1
# BOOT_TIMING_RESTORE_EARLY_ENTROPY_V2
# DANI_EARLY_LAUNCHER_V1

. /opt/muos/script/var/func.sh

RUN_DIR="/run/muos"
TRACE="/tmp/muos/fixed-startup.tsv"
ROM_MOUNT="/mnt/mmc"

mkdir -p /tmp/muos "$RUN_DIR"
rm -f "$TRACE" /opt/update.sh
rm -rf /opt/muxtmp

mark() {
	read -r NOW _ </proc/uptime
	printf '%s\t%s\n' "$NOW" "$1" >>"$TRACE"
}

mark startup-begin

# Session state used by suspend, launch and stock-fallback paths.
read -r MU_UPTIME _ </proc/uptime
SET_VAR system resume_uptime "$MU_UPTIME"
SET_VAR system idle_inhibit 0
SET_VAR config boot/device_mode 0
SET_VAR device audio/ready 0
rm -f /opt/muos/device/config/screen/s_rotate \
	/opt/muos/device/config/screen/s_zoom &

# The launcher already requested performance mode in initramfs.  Repeat the
# fixed value after switch_root in case the kernel policy was recreated.
GOVERNOR=$(GET_VAR device cpu/governor)
printf '%s\n' performance >"$GOVERNOR"
mark core-state-ready

# Audio warms only after the system-ready marker.  Mali is already loaded by
# the fixed early hardware service; squashfs is the only remaining RG module
# required by packaged applications.
/opt/muos/script/system/pipewire.sh start &
modprobe -q squashfs &
ifconfig lo up &

# These independent fixed-device workers must never hold the visible menu.
/opt/muos/script/device/start.sh &
/opt/muos/script/mount/start.sh &
mark device-and-storage-dispatched

# Make system volume/brightness/power controls available while storage binds,
# instead of waiting for the complete ROM compatibility tree.
HOTKEY start
mark hotkeys-ready

# RG34XX-SP internal display geometry is invariant.  There is no HDMI branch.
SET_VAR device screen/width 720 &
SET_VAR device screen/height 480 &
SET_VAR device mux/width 720 &
SET_VAR device mux/height 480 &

echo 1 >"$MUOS_RUN_DIR/work_led_state"
: >"$MUOS_RUN_DIR/net_start"
/opt/muos/script/system/swap.sh &

# Content launchers may proceed only after the fixed storage service publishes
# its readiness marker.  Menu drawing and direct input remain independent.
until [ -f "$MUOS_STORE_DIR/mount_ready" ]; do sleep 0.01; done
mark storage-ready

# Charging state and LED policy are fixed handheld hardware work.  Preserve
# their proven ordering before publishing complete system readiness.
/opt/muos/script/device/charge.sh
LED_CONTROL_CHANGE
mark charge-and-led-ready

: >"$RUN_DIR/dani-system-ready"
if [ ! -e "$RUN_DIR/dani-launcher-active" ]; then
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
