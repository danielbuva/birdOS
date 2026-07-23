#!/bin/bash
# One diagnostic snapshot ordered after normal ROCKNIX autostart. This is
# deliberately post-frame and never blocks Bird interaction.

set -u

LOG=/storage/bird-data/MUOS/Bird/log/stock-root-boot-state-latest.log

{
	printf 'Bird post-frame boot snapshot uptime='
	cut -d ' ' -f 1 /proc/uptime
	printf '%s\n' '--- selected unit timestamps ---'
	for UNIT in rocknix-automount.service essway.service \
		rocknix-autostart.service input.service pipewire.service \
		wireplumber.service powerstate.service; do
		systemctl show "$UNIT" --no-pager \
			-p Id -p LoadState -p ActiveState -p SubState \
			-p InactiveExitTimestampMonotonic \
			-p ActiveEnterTimestampMonotonic 2>&1 || :
	done
	printf '%s\n' '--- running services ---'
	systemctl list-units --type=service --state=running --no-pager 2>&1 || :
	printf '%s\n' '--- failed units ---'
	systemctl --failed --no-pager 2>&1 || :
	printf '%s\n' '--- remaining jobs ---'
	systemctl list-jobs --no-pager 2>&1 || :
	printf '%s\n' '--- processes ---'
	ps -eo pid,ppid,stat,rss,comm,args 2>&1 || :
	printf '%s\n' '--- input devices ---'
	cat /proc/bus/input/devices 2>&1 || :
	for INPUT in /dev/input/event*; do
		[ -e "$INPUT" ] || continue
		printf '[%s]\n' "$INPUT"
		udevadm info --query=property "$INPUT" 2>&1 || :
	done
	printf '%s\n' '--- loaded modules ---'
	cat /proc/modules 2>&1 || :
	printf '%s\n' '--- CPU and GPU policy ---'
	for POLICY in /sys/devices/system/cpu/cpufreq/policy*; do
		[ -e "$POLICY" ] || continue
		printf '[%s]\n' "${POLICY##*/}"
		for PROPERTY in scaling_governor scaling_available_governors \
			scaling_cur_freq scaling_min_freq scaling_max_freq \
			cpuinfo_min_freq cpuinfo_max_freq; do
			[ -r "$POLICY/$PROPERTY" ] || continue
			printf '%s=' "$PROPERTY"
			cat "$POLICY/$PROPERTY"
		done
	done
	for DEVFREQ in /sys/class/devfreq/*; do
		[ -e "$DEVFREQ" ] || continue
		printf '[%s]\n' "${DEVFREQ##*/}"
		for PROPERTY in governor available_governors cur_freq min_freq max_freq \
			available_frequencies; do
			[ -r "$DEVFREQ/$PROPERTY" ] || continue
			printf '%s=' "$PROPERTY"
			cat "$DEVFREQ/$PROPERTY"
		done
	done
	printf '%s\n' '--- memory ---'
	cat /proc/meminfo
	printf '%s\n' '--- mounts ---'
	cat /proc/mounts
	printf '%s\n' '--- power supplies ---'
	for SUPPLY in /sys/class/power_supply/*; do
		[ -e "$SUPPLY" ] || continue
		printf '[%s]\n' "${SUPPLY##*/}"
		for PROPERTY in type status capacity health present online \
			voltage_now voltage_min_design voltage_max_design \
			current_now constant_charge_current \
			constant_charge_current_max input_current_limit; do
			[ -r "$SUPPLY/$PROPERTY" ] || continue
			printf '%s=' "$PROPERTY"
			cat "$SUPPLY/$PROPERTY"
		done
		[ -r "$SUPPLY/uevent" ] && cat "$SUPPLY/uevent"
	done
	printf '%s\n' '--- LEDs ---'
	for LED in /sys/class/leds/*; do
		[ -e "$LED" ] || continue
		printf '[%s]\n' "${LED##*/}"
		for PROPERTY in brightness max_brightness trigger; do
			[ -r "$LED/$PROPERTY" ] || continue
			printf '%s=' "$PROPERTY"
			cat "$LED/$PROPERTY"
		done
	done
	printf '%s\n' '--- AXP717 kernel messages ---'
	dmesg | grep -Ei 'axp717|battery|charger|power supply' | tail -n 80 || :
} >"$LOG" 2>&1
