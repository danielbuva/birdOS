#!/bin/bash
# Network exists only around the explicit PortMaster maintenance session.

set -u

FLAG=/run/bird/network-request
LOG=/storage/bird-data/MUOS/Bird/log/network-latest.log

mkdir -p /run/bird "${LOG%/*}"
exec >>"$LOG" 2>&1

case "${1:-}" in
	start)
		printf 'Bird network request start uptime='
		cut -d ' ' -f 1 /proc/uptime
		touch "$FLAG"
		systemctl start systemd-rfkill.service || :
		systemctl start dbus.service systemd-resolved.service \
			systemd-timesyncd.service || :
		systemctl start iwd.service NetworkManager.service || :
		/usr/bin/wifictl enable || :
		for _ in $(seq 1 100); do
			[ "$(systemctl is-active NetworkManager.service 2>/dev/null)" = active ] && break
			usleep 50000
		done
		/usr/bin/nmcli connection reload || :
		PROFILE=$(/usr/bin/nmcli -t -f NAME,TYPE connection show 2>/dev/null | \
			awk -F: '$2 == "wifi" || $2 == "802-11-wireless" { print $1; exit }')
		if [ -n "$PROFILE" ] && \
			/usr/bin/nmcli -w 20 connection up id "$PROFILE"; then
			ACTIVATION=ready
		else
			ACTIVATION=failed
		fi
		# PortMaster should not mistake a running manager for a usable link.
		# This wait is inside the explicit maintenance session only; it never
		# delays Bird's offline boot or menu.
		if /usr/bin/nm-online -q --timeout=10; then
			LINK=ready
		else
			LINK=timeout
		fi
		printf 'Bird network request ready profile=%s activation=%s link=%s nm=%s iwd=%s resolved=%s timesync=%s rfkill=%s uptime=' \
			"${PROFILE:-missing}" "$ACTIVATION" "$LINK" \
			"$(systemctl is-active NetworkManager.service 2>/dev/null || :)" \
			"$(systemctl is-active iwd.service 2>/dev/null || :)" \
			"$(systemctl is-active systemd-resolved.service 2>/dev/null || :)" \
			"$(systemctl is-active systemd-timesyncd.service 2>/dev/null || :)" \
			"$(systemctl is-active systemd-rfkill.service 2>/dev/null || :)"
		cut -d ' ' -f 1 /proc/uptime
		printf '%s\n' '--- NetworkManager connections ---'
		/usr/bin/nmcli -t -f NAME,TYPE,AUTOCONNECT connection show || :
		printf '%s\n' '--- Wi-Fi device ---'
		/usr/bin/nmcli -t -f GENERAL.DEVICE,GENERAL.STATE,GENERAL.REASON,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY device show || :
		printf '%s\n' '--- routes ---'
		ip route || :
		;;
	stop)
		printf 'Bird network release start uptime='
		cut -d ' ' -f 1 /proc/uptime
		/usr/bin/wifictl disable || :
		systemctl stop --no-block NetworkManager.service iwd.service \
			systemd-resolved.service systemd-timesyncd.service \
			systemd-rfkill.service || :
		rm -f "$FLAG"
		printf 'Bird network release ready uptime='
		cut -d ' ' -f 1 /proc/uptime
		;;
	*)
		printf 'usage: %s {start|stop}\n' "$0" >&2
		exit 2
		;;
esac
