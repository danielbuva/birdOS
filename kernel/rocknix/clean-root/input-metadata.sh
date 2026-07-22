#!/bin/sh
# RetroArch's udev input driver filters for ID_INPUT_JOYSTICK=1. The kernel
# already created Bird's one immutable gamepad, so publish exactly that record
# instead of starting udevd, parsing rules, or replaying hardware events.

set -u

LOG=/tmp/bird-input-metadata.log
DB_ROOT=/run/udev/data

: >"$LOG"
mkdir -p "$DB_ROOT"

for EVENT in /sys/class/input/event*; do
	[ -r "$EVENT/device/name" ] || continue
	[ "$(cat "$EVENT/device/name")" = "H700 Gamepad" ] || continue
	[ -r "$EVENT/dev" ] || continue
	IFS=: read -r MAJOR MINOR <"$EVENT/dev"
	case "$MAJOR:$MINOR" in
		*[!0-9:]*|:|*:) continue ;;
	esac
	RECORD=$DB_ROOT/c$MAJOR:$MINOR
	{
		printf 'E:ID_INPUT=1\n'
		printf 'E:ID_INPUT_KEY=1\n'
		printf 'E:ID_INPUT_JOYSTICK=1\n'
	} >"$RECORD"
	printf 'device=%s database=%s\n' "${EVENT##*/}" "$RECORD" >>"$LOG"
	grep -q '^E:ID_INPUT_JOYSTICK=1$' "$RECORD" || exit 1
	exit 0
done

printf 'H700 Gamepad not found\n' >>"$LOG"
exit 1
