#!/bin/sh
set -eu

ROM_MOUNT=/mnt/mmc
WORK_DIR="$ROM_MOUNT/.firmware-work"
MARKER="$WORK_DIR/mainline-compat-installed"
SELF="$ROM_MOUNT/MUOS/init/57-capture-mainline-compat.sh"
RESULT_ROOT="$ROM_MOUNT/MUOS/boot-timing/mainline-compat"

[ -f "$MARKER" ] || exit 0
[ "$(uname -r)" = '7.0.11-bird-compat' ] || exit 0

BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)
OUTPUT="$RESULT_ROOT/$BOOT_ID"
mkdir -p "$OUTPUT"

capture() {
	SOURCE=$1
	DEST=$2
	[ ! -r "$SOURCE" ] || cp "$SOURCE" "$OUTPUT/$DEST"
}

uname -a >"$OUTPUT/uname.txt"
cat /proc/uptime >"$OUTPUT/uptime.txt"
capture /proc/cmdline cmdline.txt
capture /proc/mounts mounts.txt
capture /proc/interrupts interrupts.txt
capture /proc/iomem iomem.txt
capture /proc/meminfo meminfo.txt
capture /proc/devices devices.txt
capture /proc/modules modules.txt
capture /proc/config.gz config.gz
capture /sys/firmware/fdt running.dtb
capture /proc/bus/input/devices input-devices.txt
dmesg >"$OUTPUT/dmesg.txt" 2>&1 || true
find /sys/class/drm -maxdepth 2 -type f -o -type l 2>/dev/null |
	sort >"$OUTPUT/drm-files.txt" || true
find /sys/class/power_supply -maxdepth 2 -type f -o -type l 2>/dev/null |
	sort >"$OUTPUT/power-files.txt" || true
find /sys/class/backlight -maxdepth 2 -type f -o -type l 2>/dev/null |
	sort >"$OUTPUT/backlight-files.txt" || true
sha256sum "$OUTPUT"/* >"$OUTPUT/sha256sums.txt" 2>/dev/null || true
sync

[ ! -f "$SELF" ] || mv -f "$SELF" "$SELF.done"
