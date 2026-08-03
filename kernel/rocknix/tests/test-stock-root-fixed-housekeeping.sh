#!/bin/bash
# Host coverage for idempotent post-frame logging and Pico-8 compatibility.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
LOGGING=$ROOT/kernel/rocknix/stock-root/bird-fixed-logging.sh
PICO=$ROOT/kernel/rocknix/stock-root/bird-fixed-pico8.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-housekeeping.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

LOG_DIR=$TMP/var/log/retroarch
LOG_LINK=$TMP/storage/retroarch/logs
mkdir -p "${LOG_LINK%/*}"
BIRD_RETROARCH_LOG_DIR=$LOG_DIR BIRD_RETROARCH_LOG_LINK=$LOG_LINK "$LOGGING"
[ -d "$LOG_DIR" ]
[ -L "$LOG_LINK" ]
[ "$LOG_LINK" -ef "$LOG_DIR" ]
FIRST_LINK_MTIME=$(stat -f '%m' "$LOG_LINK" 2>/dev/null || stat -c '%Y' "$LOG_LINK")
sleep 1
BIRD_RETROARCH_LOG_DIR=$LOG_DIR BIRD_RETROARCH_LOG_LINK=$LOG_LINK "$LOGGING"
SECOND_LINK_MTIME=$(stat -f '%m' "$LOG_LINK" 2>/dev/null || stat -c '%Y' "$LOG_LINK")
[ "$FIRST_LINK_MTIME" = "$SECOND_LINK_MTIME" ]

rm -f "$LOG_LINK"
mkdir -p "$LOG_LINK"
printf '%s\n' stale >"$LOG_LINK/stale"
BIRD_RETROARCH_LOG_DIR=$LOG_DIR BIRD_RETROARCH_LOG_LINK=$LOG_LINK "$LOGGING"
[ -L "$LOG_LINK" ]
[ "$LOG_LINK" -ef "$LOG_DIR" ]

PICO_DIR=$TMP/storage/roms/pico-8
mkdir -p "$PICO_DIR"
BIRD_PICO_DIR=$PICO_DIR "$PICO"
[ -f "$PICO_DIR/Splore.png" ]
FIRST_PICO_MTIME=$(stat -f '%m' "$PICO_DIR/Splore.png" 2>/dev/null || \
	stat -c '%Y' "$PICO_DIR/Splore.png")
sleep 1
BIRD_PICO_DIR=$PICO_DIR "$PICO"
SECOND_PICO_MTIME=$(stat -f '%m' "$PICO_DIR/Splore.png" 2>/dev/null || \
	stat -c '%Y' "$PICO_DIR/Splore.png")
[ "$FIRST_PICO_MTIME" = "$SECOND_PICO_MTIME" ]

rm -f "$PICO_DIR/Splore.png"
touch "$PICO_DIR/.disable_splore"
BIRD_PICO_DIR=$PICO_DIR "$PICO"
[ ! -e "$PICO_DIR/Splore.png" ]

printf '%s\n' 'stock-root fixed housekeeping tests: PASS'
