#!/bin/bash
# One requested diagnostic snapshot ordered after normal ROCKNIX autostart.
# It publishes the boot-scoped record immediately, so ordinary later boots do
# not have to rename or accidentally reattribute a stale latest snapshot.

set -u

LOG_DIR=/storage/bird-data/MUOS/Bird/log
IFS= read -r BOOT_ID_FULL </proc/sys/kernel/random/boot_id || BOOT_ID_FULL=
BOOT_ID=${BOOT_ID_FULL:0:8}
[ -n "$BOOT_ID" ] || BOOT_ID=unknown
LOG=$LOG_DIR/stock-root-boot-state-$BOOT_ID.log
LOG_TMP=$LOG.tmp.$$
LATEST=$LOG_DIR/stock-root-boot-state-latest.log
STAGE5_WINDOW_REQUEST=/storage/.config/bird/stage5-idle-window.request
STAGE5_WINDOW_ARMED=0
[ ! -e "$STAGE5_WINDOW_REQUEST" ] || STAGE5_WINDOW_ARMED=1

cleanup() {
	rm -f "$LOG_TMP" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

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
	printf '%s\n' '--- retained manager audit ---'
	for UNIT in systemd-udevd.service systemd-logind.service seatd.service \
		systemd-journald.service pipewire.service wireplumber.service \
		sway.service; do
		systemctl show "$UNIT" --no-pager -p Id -p ActiveState -p SubState \
			-p MainPID -p MemoryCurrent -p TasksCurrent -p NRestarts 2>&1 || :
	done
	printf '%s\n' '--- udev settled state ---'
	if udevadm settle --timeout=1; then
		printf '%s\n' 'udev_queue=settled'
	else
		printf '%s\n' 'udev_queue=busy'
	fi
	printf 'udev_database_records='
	find /run/udev/data -type f 2>/dev/null | wc -l
	for CLASS in input sound drm power_supply backlight net block; do
		printf 'sys_class_%s=' "$CLASS"
		find "/sys/class/$CLASS" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l
	done
	printf '%s\n' '--- journal policy ---'
	systemctl show systemd-journald.service --no-pager \
		-p MainPID -p MemoryCurrent -p TasksCurrent 2>&1 || :
	journalctl --disk-usage 2>&1 || :
	printf '%s\n' '--- audio graph ---'
	timeout 2s pactl info 2>&1 || :
	timeout 2s pactl list short sinks 2>&1 || :
	timeout 2s pactl get-sink-volume @DEFAULT_SINK@ 2>&1 || :
	timeout 2s pactl get-sink-mute @DEFAULT_SINK@ 2>&1 || :
	timeout 2s pactl list short modules 2>&1 || :
	timeout 2s amixer -c 0 contents 2>&1 || :
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
	printf '%s\n' '--- Stage 5 structural counters ---'
	BIRD_STAGE5_LABEL=post-autostart \
		/flash/bird/capture-stage5-state.sh 2>&1 || :
	printf '%s\n' '--- fixed memory policy ---'
	if [ -r /storage/.config/swap.conf ]; then
		cat /storage/.config/swap.conf
	else
		printf '%s\n' 'swap.conf=missing'
	fi
	for PROPERTY in run pages_to_scan sleep_millisecs pages_shared \
		pages_sharing pages_unshared; do
		FILE=/sys/kernel/mm/ksm/$PROPERTY
		[ -r "$FILE" ] || continue
		printf 'ksm_%s=' "$PROPERTY"
		cat "$FILE"
	done
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
	if [ "$STAGE5_WINDOW_ARMED" -eq 1 ]; then
		printf '%s\n' '--- Stage 5 controlled menu-idle window ---'
		printf '%s\n' 'settle_seconds=5 window_seconds=15'
		sleep 5
		BIRD_STAGE5_LABEL=menu-idle-start \
			/flash/bird/capture-stage5-state.sh 2>&1 || :
		sleep 15
		BIRD_STAGE5_LABEL=menu-idle-end \
			/flash/bird/capture-stage5-state.sh 2>&1 || :
	fi
} >"$LOG_TMP" 2>&1
mv -f "$LOG_TMP" "$LOG" || exit 1
cp -f "$LOG" "$LATEST" || exit 1
[ "$STAGE5_WINDOW_ARMED" -eq 0 ] || rm -f "$STAGE5_WINDOW_REQUEST" || exit 1
trap - EXIT HUP INT TERM
