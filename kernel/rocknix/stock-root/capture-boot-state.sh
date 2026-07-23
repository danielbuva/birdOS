#!/bin/bash
# One diagnostic snapshot ordered after normal ROCKNIX autostart. This is
# deliberately post-frame and never blocks Bird interaction.

set -u

LOG=/storage/bird-data/MUOS/Bird/log/stock-root-boot-state-latest.log

{
	printf 'Bird post-frame boot snapshot uptime='
	cut -d ' ' -f 1 /proc/uptime
	printf '%s\n' '--- selected unit timestamps ---'
	for UNIT in rocknix-automount.service essway.service \
		rocknix-autostart.service input.service pipewire.service \
		wireplumber.service powerstate.service; do
		systemctl show "$UNIT" --no-pager \
			-p Id -p LoadState -p ActiveState -p SubState \
			-p InactiveExitTimestampMonotonic \
			-p ActiveEnterTimestampMonotonic 2>&1 || :
	done
	printf '%s\n' '--- running services ---'
	systemctl list-units --type=service --state=running --no-pager 2>&1 || :
	printf '%s\n' '--- failed units ---'
	systemctl --failed --no-pager 2>&1 || :
	printf '%s\n' '--- remaining jobs ---'
	systemctl list-jobs --no-pager 2>&1 || :
	printf '%s\n' '--- processes ---'
	ps -eo pid,ppid,stat,rss,comm,args 2>&1 || :
	printf '%s\n' '--- memory ---'
	cat /proc/meminfo
	printf '%s\n' '--- mounts ---'
	cat /proc/mounts
} >"$LOG" 2>&1
