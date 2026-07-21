#!/bin/sh
# DANI_RG34XXSP_FIXED_DEVICE_DTB_V1_CAPTURE

set -u

SELF=$0
WORK_DIR=/mnt/mmc/.firmware-work
MARKER="$WORK_DIR/fixed-device-dtb-v1-installed"
EXPECTED_SHA=872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f
RESULT_ROOT=/mnt/mmc/MUOS/boot-timing/fixed-device-dtb-v1

# The collector is staged before the installer. On the installation boot it
# remains armed; on the first candidate boot the marker exists and it runs.
[ -f "$MARKER" ] || exit 0
read -r INSTALLED_SHA _ <"$MARKER"
[ "$INSTALLED_SHA" = "$EXPECTED_SHA" ] || exit 1

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

capture_file /proc/cmdline cmdline.txt
capture_file /proc/interrupts interrupts.txt
capture_file /proc/iomem iomem.txt
capture_file /proc/meminfo meminfo.txt
capture_file /proc/modules modules.txt
capture_file /sys/firmware/fdt running.dtb
capture_command dmesg.txt dmesg
capture_command input-devices.txt cat /proc/bus/input/devices
capture_command mounts.txt cat /proc/mounts
capture_command sys-modules.txt find /sys/module -mindepth 1 -maxdepth 1 -type d
capture_command uname.txt uname -a

grep -E 'sunxi-(ehci|ohci).*controller|sdmmc@04022000|sunxi-mmc sdc2|uart1:|HDMI|hdmi|VIN|TC358743|deinterlace|sunxi-bt' \
	"$RESULT/dmesg.txt" >"$RESULT/unexpected-disabled-probes.txt" || true

if [ -s "$RESULT/unexpected-disabled-probes.txt" ]; then
	printf 'FAIL: one or more disabled subsystems still probed\n' >"$RESULT/probe-verdict.txt"
else
	printf 'PASS: disabled v1 subsystems did not probe\n' >"$RESULT/probe-verdict.txt"
fi

grep -E '\[DISP\]disp_module_init finish|AXP20X driver loaded|mmc0: new high speed|input: muOS-Keys|ALSA device list|#0: audiocodec|EXT4-fs|\[EXFAT\] mounted successfully' \
	"$RESULT/dmesg.txt" >"$RESULT/required-probes.txt" || true

(
	cd "$RESULT" || exit 1
	sha256sum running.dtb dmesg.txt interrupts.txt 2>/dev/null >sha256sums.txt || true
)

printf '%s\n' "$BOOT_ID" >"$RESULT_ROOT/latest"
sync

case "$SELF" in
*.done) ;;
*) mv -f "$SELF" "$SELF.done" ;;
esac

exit 0
