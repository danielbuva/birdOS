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
		# The fixed radio was deliberately blocked when the previous maintenance
		# session ended. Unblock it before starting its two retained owners.
		/usr/sbin/rfkill unblock wifi || :
		systemctl start iwd.service || :
		systemctl start NetworkManager.service || :
		for _ in $(seq 1 100); do
			[ "$(systemctl is-active NetworkManager.service 2>/dev/null)" = active ] && break
			usleep 50000
		done
		WIFI_DEV=$(ls /sys/class/net 2>/dev/null | awk '/^wlan/ { print; exit }')
		if [ -n "$WIFI_DEV" ]; then
			/usr/bin/nmcli radio wifi on || :
			/usr/bin/nmcli device set "$WIFI_DEV" managed yes || :
			# Starting the managers does not mean iwd has registered the radio.
			# ROCKNIX's own connector waits for that device and scans before it
			# activates a saved keyfile; reproduce those necessary operations.
			for _ in $(seq 1 100); do
				/usr/bin/iwctl device list 2>/dev/null | \
					grep -q "$WIFI_DEV" && break
				usleep 50000
			done
			for _ in 1 2 3; do
				/usr/bin/nmcli -w 5 device wifi rescan \
					ifname "$WIFI_DEV" 2>/dev/null && break
				usleep 500000
			done
		fi
		/usr/bin/nmcli connection reload || :
		PROFILE=$(/usr/bin/nmcli -t -f NAME,TYPE connection show 2>/dev/null | \
			awk -F: '$2 == "wifi" || $2 == "802-11-wireless" { print $1; exit }')
		if [ -n "$PROFILE" ] && [ -n "$WIFI_DEV" ] && \
			/usr/bin/nmcli -w 30 connection up id "$PROFILE" \
				ifname "$WIFI_DEV"; then
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
		printf '%s\n' '--- Wi-Fi radio and scan ---'
		/usr/sbin/rfkill list wifi || :
		if [ -n "$WIFI_DEV" ]; then
			/usr/bin/nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY \
				device wifi list ifname "$WIFI_DEV" || :
		fi
		printf '%s\n' '--- routes ---'
		ip route || :
		if [ "$ACTIVATION" != ready ]; then
			printf '%s\n' '--- failed activation journal ---'
			journalctl -b -u iwd.service -u NetworkManager.service \
				--no-pager -n 120 || :
		fi
		;;
	stop)
		printf 'Bird network release start uptime='
		cut -d ' ' -f 1 /proc/uptime
		WIFI_DEV=$(ls /sys/class/net 2>/dev/null | awk '/^wlan/ { print; exit }')
		[ -z "$WIFI_DEV" ] || /usr/bin/nmcli device disconnect "$WIFI_DEV" || :
		/usr/sbin/rfkill block wifi || :
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
