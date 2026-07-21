#!/bin/sh
# DANI_RG34XXSP_KERNEL_BASELINE_V1
#
# This is a one-boot, post-menu inventory.  It records the running kernel's
# exact configuration and the hardware/resources it actually exposes before
# any CONFIG options are removed.  The launcher is already interactive when
# user-init reaches this script.

set -u

SELF=$0
RESULT_ROOT=/mnt/mmc/MUOS/boot-timing/kernel-baseline
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
[ -n "$BOOT_ID" ] || BOOT_ID=unknown
RESULT="$RESULT_ROOT/$BOOT_ID"

mkdir -p "$RESULT" || exit 1

capture_file() {
	SOURCE=$1
	NAME=$2
	if [ -r "$SOURCE" ]; then
		cp -f "$SOURCE" "$RESULT/$NAME"
	else
		printf 'unavailable: %s\n' "$SOURCE" >"$RESULT/$NAME.unavailable"
	fi
}

capture_command() {
	NAME=$1
	shift
	"$@" >"$RESULT/$NAME" 2>&1 ||
		printf 'command failed with status %s\n' "$?" >>"$RESULT/$NAME"
}

capture_file /proc/config.gz config.gz
capture_file /proc/cmdline cmdline.txt
capture_file /proc/version version.txt
capture_file /proc/cpuinfo cpuinfo.txt
capture_file /proc/modules modules.txt
capture_file /proc/filesystems filesystems.txt
capture_file /proc/interrupts interrupts.txt
capture_file /proc/iomem iomem.txt
capture_file /proc/meminfo meminfo.txt
capture_file /sys/firmware/fdt running.dtb

capture_command uname.txt uname -a
capture_command dmesg.txt dmesg
capture_command mounts.txt cat /proc/mounts
capture_command sys-modules.txt find /sys/module -mindepth 1 -maxdepth 1 -type d
capture_command input-devices.txt cat /proc/bus/input/devices
capture_command device-tree-model.txt cat /proc/device-tree/model
capture_command device-tree-compatible.txt cat /proc/device-tree/compatible

if [ -r "$RESULT/config.gz" ]; then
	gzip -dc "$RESULT/config.gz" >"$RESULT/config" 2>/dev/null ||
		printf 'could not expand /proc/config.gz\n' >"$RESULT/config.unavailable"
fi

(
	cd "$RESULT" || exit 1
	sha256sum config.gz config running.dtb 2>/dev/null >sha256sums.txt || true
)

rm -f "$RESULT_ROOT/latest"
ln -s "$BOOT_ID" "$RESULT_ROOT/latest"
sync

case "$SELF" in
*.done) ;;
*) mv -f "$SELF" "$SELF.done" ;;
esac

exit 0
