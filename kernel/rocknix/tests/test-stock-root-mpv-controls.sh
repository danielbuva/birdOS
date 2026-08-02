#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
POLICY=$ROOT/kernel/rocknix/stock-root/mpv-input.conf
CLEAN_POLICY=$ROOT/kernel/rocknix/clean-root/mpv-input.conf

EXPECTED_KEYS='GAMEPAD_ACTION_DOWN
GAMEPAD_ACTION_RIGHT
GAMEPAD_ACTION_LEFT
GAMEPAD_ACTION_UP
GAMEPAD_DPAD_LEFT
GAMEPAD_DPAD_RIGHT
GAMEPAD_DPAD_DOWN
GAMEPAD_DPAD_UP
GAMEPAD_LEFT_SHOULDER
GAMEPAD_RIGHT_SHOULDER
VOLUME_DOWN
VOLUME_UP'

ACTUAL_KEYS=$(awk 'NF && $1 !~ /^#/ { print $1 }' "$POLICY")
[ "$ACTUAL_KEYS" = "$EXPECTED_KEYS" ] || {
	printf '%s\n' 'active MPV control policy has missing, duplicate, or reordered keys' >&2
	exit 1
}

for BINDING in \
	'GAMEPAD_ACTION_DOWN cycle pause' \
	'GAMEPAD_ACTION_RIGHT ignore' \
	'GAMEPAD_ACTION_LEFT cycle sub' \
	'GAMEPAD_ACTION_UP show-progress' \
	'GAMEPAD_DPAD_LEFT seek -5' \
	'GAMEPAD_DPAD_RIGHT seek 5' \
	'GAMEPAD_DPAD_DOWN seek -60' \
	'GAMEPAD_DPAD_UP seek 60' \
	'GAMEPAD_LEFT_SHOULDER add volume -2' \
	'GAMEPAD_RIGHT_SHOULDER add volume 2' \
	'VOLUME_DOWN ignore' \
	'VOLUME_UP ignore'; do
	grep -Fxq "$BINDING" "$POLICY" || {
		printf 'missing exact active MPV binding: %s\n' "$BINDING" >&2
		exit 1
	}
done

# Physical face-button presses can produce overlapping MPV/SDL actions. The
# secondary action must therefore be harmless and no face action may cycle
# audio tracks.
[ "$(grep -Ec '^[^#]+[[:space:]]cycle[[:space:]]+pause([[:space:]]|$)' "$POLICY")" = 1 ]
! grep -Eq '^[^#]+[[:space:]]cycle[[:space:]]+audio([[:space:]]|$)' "$POLICY"
! grep -Eq '^[^#]+[[:space:]]cycle[[:space:]]+audio([[:space:]]|$)' "$CLEAN_POLICY"

# MPV 0.38 on the retained ROCKNIX image can repeat a trigger command after
# release. Keep both triggers absent rather than assigning a hazardous action.
if grep -Eq '^GAMEPAD_(LEFT|RIGHT)_TRIGGER[[:space:]]' "$POLICY"; then
	printf '%s\n' 'unsafe MPV trigger binding reintroduced' >&2
	exit 1
fi
if grep -Eq '^GAMEPAD_(LEFT|RIGHT)_TRIGGER[[:space:]]' "$CLEAN_POLICY"; then
	printf '%s\n' 'unsafe clean-root MPV trigger binding reintroduced' >&2
	exit 1
fi

printf '%s\n' 'stock-root MPV controls tests: PASS'
