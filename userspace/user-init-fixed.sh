#!/bin/sh
# BIRD_FIXED_USER_INIT_V1

SCRIPT_DIR="/run/muos/storage/init"
LOG="/mnt/mmc/MUOS/log/user_init.log"

mkdir -p "${LOG%/*}"
: >"$LOG"

for SCRIPT in "$SCRIPT_DIR"/*.sh; do
	[ -f "$SCRIPT" ] || continue
	printf '%s\n' "$SCRIPT" >>"$LOG"
	sh "$SCRIPT" &
done
