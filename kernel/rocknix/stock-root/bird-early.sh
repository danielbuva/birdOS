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
WATCHDOG_DISARM=$RUN/boot-watchdog-disarmed
WATCHDOG_PID_FILE=$RUN/boot-watchdog.pid
WATCHDOG_SECONDS=30
WATCHDOG_PERSIST_DELAY=5

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
	RAW=$(((10 * MAX + 50) / 100))
	[ "$RAW" -lt 1 ] && RAW=1
	# Linux takes ownership of the inherited U-Boot PWM. Store the proven
	# cold-start level before unblanking so power-on cannot expose the driver's
	# unrelated default. Unlike resume, cold boot stays at this level and needs
	# no timed strike or second brightness write.
	printf '%s\n' "$RAW" >"$BACKLIGHT/brightness"
	if [ -w "$BACKLIGHT/bl_power" ]; then
		printf '%s\n' 0 >"$BACKLIGHT/bl_power"
	fi
}

case "${1:-}" in
	start)
		$BUSYBOX mkdir -p "$RUN"
		$BUSYBOX rm -f "$STORAGE_MARKER" "$STORAGE_SIGNAL" \
			"$WATCHDOG_DISARM" "$WATCHDOG_PID_FILE"
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
		# Why before: storage-failed waited for the launcher to exit, but a
		# pre-storage action can remain pending inside that launcher forever.
		# Why change: arm one initramfs-owned deadline before Bird. It is outside
		# launcher and systemd ownership and is disarmed only by the verified
		# post-prepare_sysroot storage-anchor acknowledgement below.
		/bird-early.sh watchdog >/dev/null 2>&1 &
		printf '%s\n' "$!" >"$WATCHDOG_PID_FILE"
		"$LAUNCHER" >>"$LOG" 2>&1 &
		printf '%s\n' "$!" >"$PID_FILE"
		;;
	watchdog)
		WATCHDOG_BOOT_ID=$($BUSYBOX cat /proc/sys/kernel/random/boot_id \
			2>/dev/null || printf unknown)
		case "$WATCHDOG_BOOT_ID" in
			*[!0-9a-f-]*|'') WATCHDOG_BOOT_ID=unknown ;;
		esac
		WATCHDOG_NAME=boot-watchdog-$WATCHDOG_BOOT_ID.log
		WATCHDOG_TMP=$RUN/$WATCHDOG_NAME
		WATCHDOG_PERSISTENT=0
		WATCHDOG_PATH=
		: >"$WATCHDOG_TMP"

		watchdog_line() {
			if [ "$WATCHDOG_PERSISTENT" -eq 1 ]; then
				if printf '%s\n' "$*" >&5 2>/dev/null; then
					return 0
				fi
				exec 5>&- || :
				WATCHDOG_PERSISTENT=0
			fi
			printf '%s\n' "$*" >>"$WATCHDOG_TMP"
		}

		watchdog_open_persistent() {
			[ "$WATCHDOG_PERSISTENT" -eq 0 ] || return 0
			for WATCHDOG_ROOT in /birddata /run/bird-data \
				/sysroot/storage/bird-data /storage/bird-data; do
				[ -d "$WATCHDOG_ROOT/Bird/log" ] || continue
				WATCHDOG_PATH=$WATCHDOG_ROOT/Bird/log/$WATCHDOG_NAME
				if exec 5>"$WATCHDOG_PATH"; then
					if $BUSYBOX cat "$WATCHDOG_TMP" >&5 2>/dev/null; then
						WATCHDOG_PERSISTENT=1
						watchdog_line "persistent_log=retained path=$WATCHDOG_PATH"
						return 0
					fi
					exec 5>&- || :
					$BUSYBOX rm -f "$WATCHDOG_PATH" 2>/dev/null || :
				fi
			done
			WATCHDOG_PATH=
			return 1
		}

		watchdog_remove_success_record() {
			[ "$WATCHDOG_PERSISTENT" -eq 0 ] || exec 5>&-
			for WATCHDOG_ROOT in /birddata /run/bird-data \
				/sysroot/storage/bird-data /storage/bird-data; do
				$BUSYBOX rm -f "$WATCHDOG_ROOT/Bird/log/$WATCHDOG_NAME" \
					2>/dev/null || :
			done
			$BUSYBOX rm -f "$WATCHDOG_TMP" "$WATCHDOG_PID_FILE"
		}

		watchdog_capture() {
			printf '%s\n' 'section=uptime'
			$BUSYBOX cat /proc/uptime || :
			printf '%s\n' 'section=cmdline'
			$BUSYBOX cat /proc/cmdline || :
			printf '%s\n' 'section=mounts'
			$BUSYBOX cat /proc/mounts || :
			printf '%s\n' 'section=partitions'
			$BUSYBOX cat /proc/partitions || :
			printf '%s\n' 'section=modules'
			$BUSYBOX cat /proc/modules || :
			printf '%s\n' 'section=storage-paths'
			$BUSYBOX ls -ld /birddata /run/bird-data \
				/sysroot/storage /storage /storage/bird-data 2>&1 || :
			printf '%s\n' 'section=readiness'
			for WATCHDOG_ITEM in "$RUN"/*; do
				[ -e "$WATCHDOG_ITEM" ] || continue
				[ "$WATCHDOG_ITEM" != "$WATCHDOG_TMP" ] || continue
				[ "$WATCHDOG_ITEM" != "$WATCHDOG_CAPTURE_TMP" ] || continue
				if [ -f "$WATCHDOG_ITEM" ] && [ -r "$WATCHDOG_ITEM" ]; then
					printf 'file=%s value=' "$WATCHDOG_ITEM"
					$BUSYBOX dd if="$WATCHDOG_ITEM" bs=256 count=1 2>/dev/null || :
					printf '\n'
				elif [ -p "$WATCHDOG_ITEM" ]; then
					printf 'fifo=%s\n' "$WATCHDOG_ITEM"
				else
					printf 'node=%s\n' "$WATCHDOG_ITEM"
				fi
			done
			printf '%s\n' 'section=processes'
			for WATCHDOG_COMM in /proc/[0-9]*/comm; do
				[ -r "$WATCHDOG_COMM" ] || continue
				WATCHDOG_PROCESS=${WATCHDOG_COMM#/proc/}
				printf 'pid=%s comm=' "${WATCHDOG_PROCESS%/comm}"
				$BUSYBOX cat "$WATCHDOG_COMM" || :
			done
			printf '%s\n' 'section=mount-storage'
			for WATCHDOG_ROOT in /birddata /run/bird-data \
				/sysroot/storage/bird-data /storage/bird-data; do
				WATCHDOG_MOUNT_LOG=$WATCHDOG_ROOT/Bird/log/mount-storage-latest.log
				[ -r "$WATCHDOG_MOUNT_LOG" ] || continue
				printf 'path=%s\n' "$WATCHDOG_MOUNT_LOG"
				$BUSYBOX cat "$WATCHDOG_MOUNT_LOG" || :
				break
			done
			printf '%s\n' 'section=early-launcher'
			[ ! -r "$LOG" ] || $BUSYBOX cat "$LOG" || :
			printf '%s\n' 'section=kernel'
			$BUSYBOX dmesg || :
		}

		watchdog_publish_p1() {
			if $BUSYBOX mount -o remount,rw /flash 2>/dev/null; then
				$BUSYBOX cat "$WATCHDOG_TMP" \
					>/flash/bird-watchdog-failure.txt 2>/dev/null || :
				$BUSYBOX sync || :
				$BUSYBOX mount -o remount,ro /flash 2>/dev/null || :
			fi
		}

		watchdog_line 'schema=bird-early-storage-watchdog-v1'
		watchdog_line "boot_id=$WATCHDOG_BOOT_ID"
		watchdog_line "deadline_s=$WATCHDOG_SECONDS"
		WATCHDOG_COUNT=$WATCHDOG_SECONDS
		WATCHDOG_ELAPSED=0
		while [ "$WATCHDOG_COUNT" -gt 0 ]; do
			if [ -s "$WATCHDOG_DISARM" ]; then
				watchdog_remove_success_record
				exit 0
			fi
			if [ "$WATCHDOG_ELAPSED" -ge "$WATCHDOG_PERSIST_DELAY" ]; then
				watchdog_open_persistent || :
			fi
			$BUSYBOX sleep 1
			WATCHDOG_COUNT=$((WATCHDOG_COUNT - 1))
			WATCHDOG_ELAPSED=$((WATCHDOG_ELAPSED + 1))
		done
		if [ -s "$WATCHDOG_DISARM" ]; then
			watchdog_remove_success_record
			exit 0
		fi
		watchdog_open_persistent || :
		watchdog_line 'status=fatal reason=storage-readiness-timeout'
		watchdog_line 'capture=begin'
		WATCHDOG_CAPTURE_TMP=$RUN/$WATCHDOG_NAME.capture
		watchdog_capture >"$WATCHDOG_CAPTURE_TMP" 2>&1 || :
		if [ "$WATCHDOG_PERSISTENT" -eq 1 ]; then
			if ! $BUSYBOX cat "$WATCHDOG_CAPTURE_TMP" >&5 2>/dev/null; then
				exec 5>&- || :
				WATCHDOG_PERSISTENT=0
				$BUSYBOX cat "$WATCHDOG_CAPTURE_TMP" >>"$WATCHDOG_TMP" || :
			fi
		else
			$BUSYBOX cat "$WATCHDOG_CAPTURE_TMP" >>"$WATCHDOG_TMP" || :
		fi
		$BUSYBOX rm -f "$WATCHDOG_CAPTURE_TMP" || :
		# p6 may be the failed boundary. Persist one bounded fallback outside
		# the immutable release tree on the already verified BIRD volume.
		[ "$WATCHDOG_PERSISTENT" -eq 1 ] || watchdog_publish_p1
		watchdog_line 'capture=complete shutdown_countdown_s=3'
		WATCHDOG_COUNT=3
		while [ "$WATCHDOG_COUNT" -gt 0 ]; do
			watchdog_line "shutdown_countdown remaining_s=$WATCHDOG_COUNT"
			WATCHDOG_LED=/sys/class/leds/red:status/brightness
			[ ! -w "$WATCHDOG_LED" ] || \
				printf '%s\n' $((WATCHDOG_COUNT % 2)) >"$WATCHDOG_LED"
			$BUSYBOX sync || :
			$BUSYBOX sleep 1
			WATCHDOG_COUNT=$((WATCHDOG_COUNT - 1))
		done
		watchdog_line 'shutdown_countdown dispatch=poweroff-force'
		[ "$WATCHDOG_PERSISTENT" -eq 1 ] || watchdog_publish_p1
		$BUSYBOX sync || :
		$BUSYBOX poweroff -f
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
				printf '%s\n' storage-anchor-ready >"$WATCHDOG_DISARM"
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
		# The independent pre-launch watchdog already owns the deadline and full
		# capture. Record this exact branch without waiting on launcher behavior;
		# upstream init then parks while that watchdog seals evidence and powers off.
		FAILURE_LOG=$LOG
		for FAILURE_ROOT in /run/bird-data /birddata; do
			if [ -d "$FAILURE_ROOT/Bird/log" ]; then
				FAILURE_LOG=$FAILURE_ROOT/Bird/log/mount-storage-latest.log
				break
			fi
		done
		printf 'status=fatal boot_watchdog=armed deadline_s=%s uptime=' \
			"$WATCHDOG_SECONDS" >>"$FAILURE_LOG"
		$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$FAILURE_LOG"
		;;
	*)
		printf 'usage: %s {start|watchdog|root-ready|handoff|storage-failed}\n' "$0" >&2
		exit 2
		;;
esac
