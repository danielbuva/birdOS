#!/bin/sh
# Run Bird beside the unchanged ROCKNIX initramfs and leave that exact process
# alive across switch_root. Its retained mount descriptors follow /dev, /sys,
# /run and storage; the systemd supervisor adopts its existing PID.

BUSYBOX=/usr/bin/busybox
RUN=/run/bird
PID_FILE=$RUN/initramfs-launcher.pid
LOG=$RUN/initramfs-launcher.log
LAUNCHER=/opt/bird/bird-launcher
JOYPAD=/opt/bird/rocknix-singleadc-joypad.ko
BACKLIGHT=/sys/class/backlight/backlight
STORAGE_MARKER=$RUN/bird-storage-anchor-ready
STORAGE_SIGNAL=$RUN/bird-storage-ready

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

set_early_brightness() {
	IFS= read -r MAX <"$BACKLIGHT/max_brightness"
	RAW=$((5 * MAX / 100))
	[ "$RAW" -lt 1 ] && RAW=1
	# This panel cannot reliably leave a powered-off state at the retained
	# five-percent level. Use the same measured ten-percent, 50 ms wake strike
	# as resume, then restore the exact low boot level before the launcher draws.
	STRIKE=$(((MAX * 10 + 50) / 100))
	[ "$STRIKE" -lt 1 ] && STRIKE=1
	if [ -w "$BACKLIGHT/bl_power" ]; then
		printf '%s\n' 0 >"$BACKLIGHT/bl_power"
	fi
	if [ "$RAW" -lt "$STRIKE" ]; then
		printf '%s\n' "$STRIKE" >"$BACKLIGHT/brightness"
		$BUSYBOX usleep 50000
	fi
	printf '%s\n' "$RAW" >"$BACKLIGHT/brightness"
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
			if [ "$STORAGE_FIFO" != ready ]; then
				printf '%s\n' 'early_storage_fifo=failed'
			fi
			if [ -d /sys/bus/platform/drivers/rocknix-singleadc-joypad ]; then
				:
			elif [ -f "$JOYPAD" ] && $BUSYBOX insmod "$JOYPAD" 2>&1; then
				:
			else
				printf '%s\n' 'early_input_module=failed'
				$BUSYBOX dmesg | $BUSYBOX tail -n 30
			fi
			COUNT=0
			while [ "$COUNT" -lt 500 ]; do
				if [ -r "$BACKLIGHT/max_brightness" ] && \
					[ -w "$BACKLIGHT/brightness" ]; then
					set_early_brightness
					break
				fi
				$BUSYBOX usleep 1000
				COUNT=$((COUNT + 1))
			done
			# LED state is diagnostic-only. Inspect it only on later storage or
			# ownership failure, never between display preparation and launcher
			# dispatch.
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
		else
			printf '%s\n' 'Bird final-root storage FIFO missing' >>"$LOG"
		fi
		COUNT=0
		while [ "$COUNT" -lt 500 ]; do
			if [ -s "$STORAGE_MARKER" ]; then
				exit 0
			fi
			$BUSYBOX usleep 1000
			COUNT=$((COUNT + 1))
		done
		printf 'Bird final-root storage timeout wait_ms=%s uptime=' "$COUNT" >>"$LOG"
		$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$LOG"
		log_leds root-timeout >>"$LOG" 2>&1
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
		if [ -s "$PID_FILE" ]; then
			PID=$($BUSYBOX cat "$PID_FILE")
			case "$PID" in *[!0-9]*|'') PID= ;; esac
			if [ -n "$PID" ] && $BUSYBOX kill -0 "$PID" 2>/dev/null; then
				exit 0
			fi
		fi
		log_leds handoff-missing >>"$LOG" 2>&1
		printf '%s\n' 'Bird early-init owner missing before mount move' >>"$LOG"
		;;
	storage-failed)
		# The normal persistent tree is unavailable, but p6 is still mounted at
		# /birddata. Keep the working early menu alive. When the launcher exits
		# for any requested action, seal the failure evidence and force a bounded
		# poweroff instead of leaving an unlogged frozen framebuffer.
		FAILURE_LOG=/birddata/Bird/log/mount-storage-latest.log
		[ -d /birddata/Bird/log ] || FAILURE_LOG=$LOG
		printf 'status=fatal launcher_watch=ready uptime=' >>"$FAILURE_LOG"
		$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$FAILURE_LOG"
		PID=
		if [ -s "$PID_FILE" ]; then
			PID=$($BUSYBOX cat "$PID_FILE")
			case "$PID" in *[!0-9]*|'') PID= ;; esac
		fi
		while [ -n "$PID" ] && $BUSYBOX kill -0 "$PID" 2>/dev/null; do
			$BUSYBOX sleep 1
		done
		printf 'launcher_exit=detected shutdown_countdown_s=3 uptime=' \
			>>"$FAILURE_LOG"
		$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$FAILURE_LOG"
		COUNT=3
		while [ "$COUNT" -gt 0 ]; do
			printf 'shutdown_countdown remaining_s=%s\n' "$COUNT" \
				>>"$FAILURE_LOG"
			LED=/sys/class/leds/red:status/brightness
			[ ! -w "$LED" ] || printf '%s\n' $((COUNT % 2)) >"$LED"
			$BUSYBOX sync
			$BUSYBOX sleep 1
			COUNT=$((COUNT - 1))
		done
		printf '%s\n' 'shutdown_countdown dispatch=poweroff-force' \
			>>"$FAILURE_LOG"
		$BUSYBOX sync
		$BUSYBOX poweroff -f
		;;
	*)
		printf 'usage: %s {start|root-ready|handoff|storage-failed}\n' "$0" >&2
		exit 2
		;;
esac
