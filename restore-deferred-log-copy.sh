#!/bin/sh

ROOT="/mnt/mmc/MUOS/boot-timing/deferred-log-copy"
BACKUP="$ROOT/backup/frontend.sh.pre-deferred-log-copy"
TARGET="/opt/muos/script/mux/frontend.sh"

if [ ! -f "$BACKUP" ]; then
	printf '%s\n' "No deferred-log-copy backup found" >&2
	exit 1
fi

cp -p "$BACKUP" "$TARGET"
chmod 755 "$TARGET"
printf '%s deferred boot-log copy restored\n' \
	"$(date -Iseconds 2>/dev/null || date)" >>"$ROOT/restore.log"
exit 0
