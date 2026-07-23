#!/bin/sh
# Run Bird beside the unchanged ROCKNIX initramfs and leave that exact process
# alive across switch_root. Its retained mount descriptors follow /dev, /sys,
# /run and storage; the systemd supervisor adopts its existing PID.

BUSYBOX=/usr/bin/busybox
RUN=/run/muos
PID_FILE=$RUN/initramfs-launcher.pid
LOG=$RUN/initramfs-launcher.log
LAUNCHER=/opt/bird/dani-launcher
JOYPAD=/opt/bird/rocknix-singleadc-joypad.ko
BACKLIGHT=/sys/class/backlight/backlight

case "${1:-}" in
	start)
		$BUSYBOX mkdir -p "$RUN"
		{
			printf 'Bird early-init start uptime='
			$BUSYBOX cut -d ' ' -f 1 /proc/uptime
			if $BUSYBOX insmod "$JOYPAD" 2>&1; then
				printf '%s\n' 'early_input_module=loaded'
			else
				printf '%s\n' 'early_input_module=failed'
				$BUSYBOX dmesg | $BUSYBOX tail -n 30
			fi
			COUNT=0
			while [ "$COUNT" -lt 500 ]; do
				if [ -r "$BACKLIGHT/max_brightness" ] && \
					[ -w "$BACKLIGHT/brightness" ]; then
					MAX=$($BUSYBOX cat "$BACKLIGHT/max_brightness")
					RAW=$((5 * MAX / 100))
					[ "$RAW" -lt 1 ] && RAW=1
					printf '%s\n' "$RAW" >"$BACKLIGHT/brightness"
					printf 'early_brightness raw=%s max=%s\n' "$RAW" "$MAX"
					break
				fi
				$BUSYBOX usleep 1000
				COUNT=$((COUNT + 1))
			done
		} >"$LOG" 2>&1
		"$LAUNCHER" >>"$LOG" 2>&1 &
		printf '%s\n' "$!" >"$PID_FILE"
		;;
	handoff)
		if [ -s "$PID_FILE" ]; then
			PID=$($BUSYBOX cat "$PID_FILE")
			case "$PID" in *[!0-9]*|'') PID= ;; esac
			if [ -n "$PID" ] && $BUSYBOX kill -0 "$PID" 2>/dev/null; then
				printf 'Bird early-init persistent-owner uptime=' >>"$LOG"
				$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$LOG"
				exit 0
			fi
		fi
		printf '%s\n' 'Bird early-init owner missing before mount move' >>"$LOG"
		;;
	*)
		printf 'usage: %s {start|handoff}\n' "$0" >&2
		exit 2
		;;
esac
