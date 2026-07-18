#!/bin/sh
# Read-only RG34XX-SP early-backlight observer.
# The init dispatcher runs this from its asynchronous directory before the
# custom launcher, so none of these diagnostics delay the first usable frame.

TMP_DIR="/tmp/muos"
TMP_LOG="$TMP_DIR/backlight-probe.tsv"
DEBUGFS="/sys/kernel/debug"
DISPDBG="$DEBUGFS/dispdbg"
ROM_MOUNT="/mnt/mmc"
FINAL_DIR="$ROM_MOUNT/MUOS/log/brightness"

mkdir -p "$TMP_DIR"

if [ -r /proc/sys/kernel/random/boot_id ]; then
	IFS= read -r BOOT_ID </proc/sys/kernel/random/boot_id
else
	BOOT_ID="unknown"
fi

FINAL_LOG="$FINAL_DIR/backlight-$BOOT_ID.tsv"
LATEST_LOG="$FINAL_DIR/backlight-latest.tsv"

printf 'boot_id\tuptime_s\tfield\tvalue\n' >"$TMP_LOG"

LOG_VALUE() {
	FIELD="$1"
	VALUE="$2"
	IFS=' ' read -r UPTIME_S _ </proc/uptime
	printf '%s\t%s\t%s\t%s\n' "$BOOT_ID" "$UPTIME_S" "$FIELD" "$VALUE" >>"$TMP_LOG"
}

ONE_LINE() {
	tr '\n\t' '  ' | sed 's/[ ][ ]*/ /g; s/^ //; s/ $//'
}

IS_MOUNTED() {
	WANTED="$1"
	while IFS=' ' read -r _ MOUNT_POINT _; do
		[ "$MOUNT_POINT" = "$WANTED" ] && return 0
	done </proc/mounts
	return 1
}

READ_DISP_BACKLIGHT() {
	if [ ! -w "$DISPDBG/name" ] || [ ! -w "$DISPDBG/command" ] ||
		[ ! -w "$DISPDBG/start" ] || [ ! -r "$DISPDBG/info" ]; then
		printf '%s' "unavailable"
		return
	fi

	if ! printf '%s' "disp0" >"$DISPDBG/name" 2>/dev/null ||
		! printf '%s' "getbl" >"$DISPDBG/command" 2>/dev/null ||
		! printf '%s' "1" >"$DISPDBG/start" 2>/dev/null; then
		printf '%s' "read-error"
		return
	fi

	ONE_LINE <"$DISPDBG/info"
}

# device/start.sh normally mounts debugfs much later. Mounting it here only
# exposes the driver's diagnostic interface; it does not set or repaint the LCD.
if ! IS_MOUNTED "$DEBUGFS"; then
	mount -t debugfs debugfs "$DEBUGFS" 2>/dev/null || :
fi

LOG_VALUE "probe" "start"

DT_BACKLIGHT="/proc/device-tree/lcd0@01c0c000/lcd_backlight"
if [ -r "$DT_BACKLIGHT" ]; then
	DT_HEX=$(od -An -tx1 "$DT_BACKLIGHT" 2>/dev/null | tr -d ' \n')
	LOG_VALUE "device_tree.lcd_backlight.hex" "${DT_HEX:-unreadable}"
else
	LOG_VALUE "device_tree.lcd_backlight.hex" "missing"
fi

if [ -r /opt/muos/script/var/func.sh ]; then
	# shellcheck source=/dev/null
	. /opt/muos/script/var/func.sh
	LOG_VALUE "config.settings.general.brightness" \
		"$(GET_VAR "config" "settings/general/brightness" 2>/dev/null | ONE_LINE)"
	LOG_VALUE "config.settings.advanced.brightness" \
		"$(GET_VAR "config" "settings/advanced/brightness" 2>/dev/null | ONE_LINE)"
	LOG_VALUE "device.screen.bright" \
		"$(GET_VAR "device" "screen/bright" 2>/dev/null | ONE_LINE)"
	LOG_VALUE "device.board.name" \
		"$(GET_VAR "device" "board/name" 2>/dev/null | ONE_LINE)"
fi

BACKLIGHT_FOUND=0
for BACKLIGHT_DIR in /sys/class/backlight/*; do
	[ -d "$BACKLIGHT_DIR" ] || continue
	BACKLIGHT_FOUND=1
	BACKLIGHT_NAME=${BACKLIGHT_DIR##*/}
	for BACKLIGHT_FIELD in brightness actual_brightness max_brightness bl_power; do
		[ -r "$BACKLIGHT_DIR/$BACKLIGHT_FIELD" ] || continue
		IFS= read -r BACKLIGHT_VALUE <"$BACKLIGHT_DIR/$BACKLIGHT_FIELD"
		LOG_VALUE "sysfs.$BACKLIGHT_NAME.$BACKLIGHT_FIELD" "$BACKLIGHT_VALUE"
	done
done
[ "$BACKLIGHT_FOUND" -eq 1 ] || LOG_VALUE "sysfs.backlight" "none"

if [ -r "$DEBUGFS/pwm" ]; then
	PWM_STATE=$(ONE_LINE <"$DEBUGFS/pwm")
	LOG_VALUE "debugfs.pwm" "${PWM_STATE:-empty}"
fi

# These are relative waits, producing samples at approximately 0, 0.1, 0.25,
# 0.5, 1.0, 1.5, 2.0, 3.0 and 4.0 seconds after the early dispatcher starts.
# The probe remains asynchronous for its entire lifetime.
SAMPLE=0
for WAIT in 0 0.1 0.15 0.25 0.5 0.5 0.5 1 1; do
	[ "$WAIT" = "0" ] || sleep "$WAIT"
	VALUE=$(READ_DISP_BACKLIGHT)
	LOG_VALUE "disp0.getbl.$SAMPLE" "${VALUE:-empty}"
	SAMPLE=$((SAMPLE + 1))
done

LOG_VALUE "probe" "end"

# ROM storage mounts concurrently. Persist the completed temporary log without
# ever holding up the dispatcher or launcher.
WAIT_COUNT=0
while ! IS_MOUNTED "$ROM_MOUNT" && [ "$WAIT_COUNT" -lt 100 ]; do
	sleep 0.2
	WAIT_COUNT=$((WAIT_COUNT + 1))
done

if IS_MOUNTED "$ROM_MOUNT"; then
	mkdir -p "$FINAL_DIR"
	cp -f "$TMP_LOG" "$FINAL_LOG"
	cp -f "$TMP_LOG" "$LATEST_LOG"
fi

exit 0
