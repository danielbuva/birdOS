#!/bin/sh

TRACE_ROOT="/mnt/mmc/MUOS/boot-timing/frontend-native"
BACKUP="$TRACE_ROOT/backup/frontend.sh.pre-native-log"
TARGET="/opt/muos/script/mux/frontend.sh"

if [ ! -f "$BACKUP" ]; then
	printf '%s\n' "No frontend native-log backup found" >&2
	exit 1
fi

cp -p "$BACKUP" "$TARGET"
chmod 755 "$TARGET"
printf '%s native frontend log capture restored\n' \
	"$(date -Iseconds 2>/dev/null || date)" >>"$TRACE_ROOT/restore.log"
exit 0
