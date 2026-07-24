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
STORAGE_MARKER=$RUN/dani-storage-anchor-ready
STORAGE_SIGNAL=$RUN/dani-storage-ready

log_leds() {
	STAGE=$1
	for NAME in green:power red:status; do
		LED=/sys/class/leds/$NAME
		printf 'early_led stage=%s name=%s brightness=' "$STAGE" "$NAME"
		if [ -r "$LED/brightness" ]; then
			$BUSYBOX cat "$LED/brightness"
		else
			printf '%s\n' missing
		fi
	done
}

case "${1:-}" in
	start)
		$BUSYBOX mkdir -p "$RUN"
		$BUSYBOX rm -f "$STORAGE_MARKER" "$STORAGE_SIGNAL"
		if $BUSYBOX mknod -m 0600 "$STORAGE_SIGNAL" p; then
			STORAGE_FIFO=ready
		else
			STORAGE_FIFO=failed
		fi
		{
			printf 'Bird early-init start uptime='
			$BUSYBOX cut -d ' ' -f 1 /proc/uptime
			printf 'early_storage_fifo=%s\n' "$STORAGE_FIFO"
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
			log_leds start
		} >"$LOG" 2>&1
		"$LAUNCHER" >>"$LOG" 2>&1 &
		printf '%s\n' "$!" >"$PID_FILE"
		;;
	root-ready)
		# prepare_sysroot has moved the completed storage tree beneath /sysroot,
		# while /run and Bird's original root are still intact. This is the one
		# deterministic point where the persistent process can retain both.
		if [ -p "$STORAGE_SIGNAL" ]; then
			# Keep the read/write endpoint open through the acknowledgement
			# wait, so the byte remains queued even if Bird opens a moment later.
			exec 4<>"$STORAGE_SIGNAL"
			printf '%s\n' ready >&4
			printf 'Bird final-root storage signalled uptime=' >>"$LOG"
			$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$LOG"
		else
			printf '%s\n' 'Bird final-root storage FIFO missing' >>"$LOG"
		fi
		COUNT=0
		while [ "$COUNT" -lt 500 ]; do
			if [ -s "$STORAGE_MARKER" ]; then
				printf 'Bird storage anchor acknowledged wait_ms=%s uptime=' \
					"$COUNT" >>"$LOG"
				$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$LOG"
				log_leds root-ready >>"$LOG" 2>&1
				exit 0
			fi
			$BUSYBOX usleep 1000
			COUNT=$((COUNT + 1))
		done
		printf 'Bird final-root storage timeout wait_ms=%s uptime=' "$COUNT" >>"$LOG"
		$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$LOG"
		# Never preserve a launcher that cannot reach content. Its framebuffer
		# remains visible while the normal final-root supervisor takes over.
		if [ -s "$PID_FILE" ]; then
			PID=$($BUSYBOX cat "$PID_FILE")
			case "$PID" in *[!0-9]*|'') PID= ;; esac
			if [ -n "$PID" ]; then
				$BUSYBOX kill -TERM "$PID" 2>/dev/null || :
				printf 'Bird final-root timeout retired pid=%s uptime=' "$PID" >>"$LOG"
				$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$LOG"
			fi
			$BUSYBOX rm -f "$PID_FILE"
		fi
		exit 0
		;;
	handoff)
		log_leds handoff >>"$LOG" 2>&1
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
		printf 'usage: %s {start|root-ready|handoff}\n' "$0" >&2
		exit 2
		;;
esac
