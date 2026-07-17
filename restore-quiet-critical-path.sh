#!/bin/sh

ROOT="/mnt/mmc/MUOS/boot-timing/quiet-critical-path"
STARTUP_BACKUP="$ROOT/backup/startup.sh.pre-quiet"
DEVICE_BACKUP="$ROOT/backup/device-start.sh.pre-quiet"
STARTUP_TARGET="/opt/muos/script/system/startup.sh"
DEVICE_TARGET="/opt/muos/script/device/start.sh"

if [ ! -f "$STARTUP_BACKUP" ] || [ ! -f "$DEVICE_BACKUP" ]; then
	printf '%s\n' "Quiet-critical-path backups are incomplete" >&2
	exit 1
fi

cp -p "$STARTUP_BACKUP" "$STARTUP_TARGET"
cp -p "$DEVICE_BACKUP" "$DEVICE_TARGET"
chmod 755 "$STARTUP_TARGET" "$DEVICE_TARGET"
printf '%s quiet critical-path scripts restored\n' \
	"$(date -Iseconds 2>/dev/null || date)" >>"$ROOT/restore.log"
exit 0
