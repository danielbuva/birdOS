#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-input-tester.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

SOURCE=$ROOT/launcher/bird-input-tester.c
grep -Fq '#define BIRD_BUTTON_A BTN_EAST' "$SOURCE"
grep -Fq '#define BIRD_BUTTON_B BTN_SOUTH' "$SOURCE"
grep -Fq '#define BIRD_BUTTON_X BTN_WEST' "$SOURCE"
grep -Fq '#define BIRD_BUTTON_Y BTN_NORTH' "$SOURCE"
grep -Fq '#define RUMBLE_LENGTH_MS 300U' "$SOURCE"
grep -Fq 'BIRD_DEVICE_RUMBLE_ENABLE_PATH' "$SOURCE"
grep -Fq 'EVIOCGKEY_768' "$SOURCE"
grep -Fq 'SYN_DROPPED' "$SOURCE"
grep -Fq 'EXIT_HOLD_NS 1000000000UL' "$SOURCE"
grep -Fq 'sys_ppoll' "$SOURCE"
grep -Fq 'truncate ? O_TRUNC | O_DSYNC : O_APPEND' "$SOURCE"
if grep -Fq 'EVIOCGRAB' "$SOURCE"; then
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
