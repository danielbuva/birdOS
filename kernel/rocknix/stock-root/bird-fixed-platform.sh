#!/bin/sh
# Publish the immutable H700/RG34XX-SP application profile once. ROCKNIX's
# device-family loop normally launches separate scripts to rewrite each of
# these tiny constant files every boot.

set -eu

PROFILE=/storage/.config/profile.d
STAGE=/run/bird/fixed-platform
LOG=/storage/bird-data/Bird/log/fixed-platform-latest.log

mkdir -p "$PROFILE" "$STAGE" "${LOG%/*}"

log_uptime() {
	LABEL=$1
	NOW=unknown
	UNUSED=
	IFS=' ' read -r NOW UNUSED </proc/uptime || NOW=unknown
	printf '%s%s\n' "$LABEL" "$NOW"
}

install_profile() {
	NAME=$1
	shift
	CURRENT=$PROFILE/$NAME
	MATCH=0
	if [ -f "$CURRENT" ]; then
		MATCH=1
		exec 3<"$CURRENT"
		for EXPECTED in "$@"; do
			ACTUAL=
			if ! IFS= read -r ACTUAL <&3 || [ "$ACTUAL" != "$EXPECTED" ]; then
				MATCH=0
				break
			fi
		done
		if [ "$MATCH" -eq 1 ] && IFS= read -r ACTUAL <&3; then
			MATCH=0
		fi
		exec 3<&-
	fi
	printf '%s\n' "$@" >"$STAGE/$NAME"
	if [ "$MATCH" -eq 1 ]; then
		printf '%s=unchanged\n' "$NAME"
	else
		cp -f "$STAGE/$NAME" "$CURRENT"
		printf '%s=updated\n' "$NAME"
	fi
}

{
	log_uptime 'Bird fixed platform start uptime='
	install_profile 001-device_config \
		'DEVICE_TEMP_SENSOR="/sys/devices/virtual/thermal/thermal_zone2/temp"' \
		'DEVICE_GPU_OVERCLOCK="true"'
	install_profile 002-turbo-mode_config 'DEVICE_TURBO_MODE="true"'
	install_profile 010-governors \
		'CPU_FREQ=("/sys/devices/system/cpu/cpufreq/policy0")' \
		'GPU_FREQ=("/sys/devices/platform/soc/1800000.gpu/devfreq/1800000.gpu")'
	install_profile 010-led_control \
		'DEVICE_LED_CONTROL="true"' \
		'DEVICE_LED_BRIGHTNESS="false"' \
		'DEVICE_LED_CHARGING="false"'
	install_profile 020-fan_control 'DEVICE_HAS_FAN="false"'
	install_profile 050-modifiers \
		'DEVICE_FUNC_KEYA_MODIFIER="BTN_MODE"' \
		'DEVICE_FUNC_KEYB_MODIFIER="BTN_START"'
	install_profile 091-ui_shader 'UI_SHADER="slangp"'
	log_uptime 'Bird fixed platform ready uptime='
} >"$LOG" 2>&1
