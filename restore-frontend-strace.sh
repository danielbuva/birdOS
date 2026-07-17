#!/bin/sh

ROOT="/mnt/mmc/MUOS/boot-timing/frontend-strace"
TARGET="/opt/muos/frontend/muxfrontend"
REAL="/opt/muos/frontend/muxfrontend.boottrace-real"
BACKUP="$ROOT/backup/muxfrontend.pre-strace"

if [ -f "$REAL" ]; then
	mv -f "$REAL" "$TARGET"
elif [ -f "$BACKUP" ]; then
	cp -p "$BACKUP" "$TARGET"
else
	printf '%s\n' "No frontend binary available to restore" >&2
	exit 1
fi

chmod 755 "$TARGET"
printf '%s\n' "complete" >"$ROOT/state"
printf '%s frontend strace wrapper manually restored\n' \
	"$(date -Iseconds 2>/dev/null || date)" >>"$ROOT/restore.log"
exit 0
