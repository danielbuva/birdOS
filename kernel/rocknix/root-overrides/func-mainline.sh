#!/bin/sh
# Load the existing muOS helpers, then replace only the generic vendor hotkey
# watcher with Bird's fixed-device event service. The service remains separate
# from the launcher and startup still dispatches it after the first menu frame.

. /run/muos/bird-func-vendor

HOTKEY() {
	case "$1" in
		stop)
			killall -TERM bird-controls 2>/dev/null || :
			WAIT_COUNT=0
			while pgrep -x bird-controls >/dev/null; do
				WAIT_COUNT=$((WAIT_COUNT + 1))
				[ "$WAIT_COUNT" -lt 100 ] || {
					killall -KILL bird-controls 2>/dev/null || :
					break
				}
				sleep 0.01
			done
			;;
		start)
			[ -x /run/muos/bird-controls ] || return 1
			pgrep -x bird-controls >/dev/null && return 0
			setsid -f /run/muos/bird-controls </dev/null \
				>>/tmp/bird-controls.log 2>&1
			;;
		restart)
			HOTKEY stop
			HOTKEY start
			;;
		*)
			printf 'Usage: HOTKEY start | stop | restart\n'
			return 1
			;;
	esac
}

# During an explicitly selected content session, keep Bird's mainline graphics
# ABI ahead of GL4ES and the vendor frontend libraries.
if [ "${BIRD_MAINLINE_CONTENT-}" = 1 ] && \
	[ -r /run/muos/bird-mainline-env ]; then
	. /run/muos/bird-mainline-env
	BIRD_MAINLINE_REASSERT

	SETUP_GL4ES() {
		BIRD_MAINLINE_REASSERT
	}

	# The preserved muOS RetroArch process still rejects its SDL graphics
	# context after the same modern SDL library independently completes KMSDRM
	# initialization. Run libretro sessions in ROCKNIX's native mainline
	# RetroArch process instead. The stable libretro ABI keeps Bird's existing
	# cores, configs, content paths and launch policy unchanged.
	retroarch() {
		NATIVE_RETROARCH="$BIRD_RUNTIME_ROOT/usr/bin/retroarch"
		NATIVE_LOADER="$BIRD_RUNTIME_ROOT/usr/lib/ld-linux-aarch64.so.1"
		NATIVE_LIBRARY_PATH="$BIRD_RUNTIME_ROOT/usr/lib"
		[ -x "$NATIVE_RETROARCH" ] && [ -x "$NATIVE_LOADER" ] || {
			printf 'Bird native RetroArch runtime incomplete: %s %s\n' \
				"$NATIVE_LOADER" "$NATIVE_RETROARCH" >&2
			return 127
		}
		printf 'Bird native RetroArch exec: %s\n' "$NATIVE_RETROARCH" >&2
		LD_LIBRARY_PATH="$NATIVE_LIBRARY_PATH" \
			"$NATIVE_LOADER" --library-path "$NATIVE_LIBRARY_PATH" \
			"$NATIVE_RETROARCH" "$@"
	}
fi
