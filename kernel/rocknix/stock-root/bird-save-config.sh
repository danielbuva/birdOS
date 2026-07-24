#!/bin/sh
# Preserve the one useful ROCKNIX shutdown action without sourcing its complete
# interactive profile or copying an unchanged file on every shutdown.

set -u

SOURCE=/storage/.config/system/configs/system.cfg
BACKUP=/storage/.config/system/configs/system.cfg.backup
LOG=/storage/bird-data/MUOS/Bird/log/shutdown-latest.log

mkdir -p "${LOG%/*}"
{
	printf 'Bird fixed shutdown save start uptime='
	cut -d ' ' -f 1 /proc/uptime
	if [ ! -s "$SOURCE" ]; then
		printf 'config=result-missing\n'
		exit 0
	fi
	if cmp -s "$SOURCE" "$BACKUP" 2>/dev/null; then
		printf 'config=result-unchanged\n'
	else
		cp -f "$SOURCE" "$BACKUP"
		printf 'config=result-updated bytes=%s\n' "$(wc -c <"$BACKUP")"
	fi
	printf 'Bird fixed shutdown save ready uptime='
	cut -d ' ' -f 1 /proc/uptime
} >>"$LOG" 2>&1
