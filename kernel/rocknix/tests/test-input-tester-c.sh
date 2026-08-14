#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-input-tester.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

SOURCE=$ROOT/launcher/bird-input-tester.c
grep -Fq '#define BIRD_BUTTON_A BTN_EAST' "$SOURCE"
grep -Fq '#define BIRD_BUTTON_B BTN_SOUTH' "$SOURCE"
grep -Fq '#define BIRD_BUTTON_X BTN_NORTH' "$SOURCE"
grep -Fq '#define BIRD_BUTTON_Y BTN_WEST' "$SOURCE"
grep -Fq '"gpio-keys-volume"' "$SOURCE"
grep -Fq '"axp20x-pek"' "$SOURCE"
grep -Fq 'KEY_VOLUMEDOWN' "$SOURCE"
grep -Fq 'KEY_VOLUMEUP' "$SOURCE"
grep -Fq 'KEY_POWER' "$SOURCE"
grep -Fq 'set_auxiliary_exclusive(fd, 1)' "$SOURCE"
grep -Fq 'draw_text(20, 12, "INPUT TEST", 2' "$SOURCE"
grep -Fq 'draw_text(20, 42, "EVENT", 2' "$SOURCE"
if grep -Eq 'RG34XX-SP INPUT TEST|PRESS EVERY CONTROL|MOVE STICKS TO EDGES' "$SOURCE"; then
	printf '%s\n' 'removed tester UI copy must stay absent' >&2
	exit 1
fi
grep -Fq '#define RUMBLE_LENGTH_MS 300U' "$SOURCE"
grep -Fq 'BIRD_DEVICE_RUMBLE_ENABLE_PATH' "$SOURCE"
grep -Fq 'EVIOCGKEY_768' "$SOURCE"
grep -Fq 'SYN_DROPPED' "$SOURCE"
grep -Fq 'EXIT_HOLD_NS 1000000000UL' "$SOURCE"
grep -Fq 'sys_ppoll' "$SOURCE"
grep -Fq 'truncate ? O_TRUNC | O_DSYNC : O_APPEND' "$SOURCE"
if sed -n '/^static int connect_input(/,/^}/p' "$SOURCE" | grep -Fq 'EVIOCGRAB'; then
	printf '%s\n' 'input tester must not grab the shared H700 gamepad' >&2
	exit 1
fi

CC=${CC:-cc}
"$CC" -std=c11 -O1 -Wall -Wextra -Werror \
	-Wno-unused-function -Wno-unused-variable -Wno-macro-redefined \
	-I "$ROOT/launcher" \
	"$ROOT/kernel/rocknix/tests/input-tester-host.c" \
	-o "$TMP/input-tester-host"
"$TMP/input-tester-host"
