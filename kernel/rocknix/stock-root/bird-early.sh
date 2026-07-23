#!/bin/sh
# Run Bird beside the unchanged ROCKNIX initramfs, then bridge the same static
# binary into the prepared final root. UI/action state moves with /run and the
# systemd supervisor adopts the bridge as its one input owner.

BUSYBOX=/usr/bin/busybox
RUN=/run/muos
PID_FILE=$RUN/initramfs-launcher.pid
LOG=$RUN/initramfs-launcher.log
LAUNCHER=/opt/bird/dani-launcher
JOYPAD=/opt/bird/rocknix-singleadc-joypad.ko
BACKLIGHT=/sys/class/backlight/backlight
BRIDGE=$RUN/dani-launcher-bridge
BRIDGE_PID=$RUN/initramfs-bridge.pid

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
				printf 'Bird early-init handoff uptime=' >>"$LOG"
				$BUSYBOX cut -d ' ' -f 1 /proc/uptime >>"$LOG"
				$BUSYBOX kill "$PID" 2>/dev/null || :
				COUNT=0
				while [ "$COUNT" -lt 50 ]; do
					$BUSYBOX kill -0 "$PID" 2>/dev/null || break
					$BUSYBOX usleep 1000
					COUNT=$((COUNT + 1))
				done
			fi
		fi
		$BUSYBOX rm -f "$PID_FILE"
		# /run moves into the final root a few instructions from here. Carry the
		# same static binary with it so pixels and evdev can resume before PID 1
		# begins parsing the systemd graph.
		$BUSYBOX cp "$LAUNCHER" "$BRIDGE" || exit 1
		$BUSYBOX chmod 0755 "$BRIDGE" || exit 1
		;;
	resume)
		ROOT_RUN=/sysroot/run/muos
		[ -x "$ROOT_RUN/dani-launcher-bridge" ] || exit 1
		if [ -s "$ROOT_RUN/dani-launch-action" ]; then
			printf '%s\n' 'Bird root bridge skipped for queued action' \
				>"$ROOT_RUN/initramfs-bridge.log"
			exit 0
		fi
		# /proc has already moved below /sysroot here. Do not touch an old-root
		# path before dispatching the bridge: v6.7 stopped at that exact read.
		printf '%s\n' 'Bird root bridge dispatch' \
			>"$ROOT_RUN/initramfs-bridge.log"
		# Give the final-root launcher its own session before this short hook
		# exits and PID 1 becomes systemd; no shell-exit SIGHUP can end it.
		$BUSYBOX setsid $BUSYBOX chroot /sysroot /run/muos/dani-launcher-bridge \
			>>"$ROOT_RUN/initramfs-bridge.log" 2>&1 &
		PID=$!
		printf '%s\n' "$PID" >"/sysroot$BRIDGE_PID"
		printf 'Bird root bridge pid=%s\n' "$PID" \
			>>"$ROOT_RUN/initramfs-bridge.log"
		$BUSYBOX usleep 5000
		if ! $BUSYBOX kill -0 "$PID" 2>/dev/null; then
			STATUS=0
			wait "$PID" || STATUS=$?
			printf 'Bird root bridge launch failed status=%s\n' "$STATUS" \
				>>"$ROOT_RUN/initramfs-bridge.log"
			$BUSYBOX rm -f "/sysroot$BRIDGE_PID"
		fi
		;;
	*)
		printf 'usage: %s {start|handoff|resume}\n' "$0" >&2
		exit 2
		;;
esac
