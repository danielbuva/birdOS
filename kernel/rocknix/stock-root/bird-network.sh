#!/bin/bash
# Network exists only around direct PortMaster or the temporary scoped stock
# ROCKNIX diagnostic session.

set -u

FLAG=${BIRD_NETWORK_FLAG:-/run/bird/network-request}
LOG=${BIRD_NETWORK_LOG:-/storage/bird-data/Bird/log/network-latest.log}
SYS_CLASS_NET=${BIRD_SYS_CLASS_NET:-/sys/class/net}
SYSTEMCTL_PROGRAM=${BIRD_SYSTEMCTL_PROGRAM:-/usr/bin/systemctl}
TIMEOUT_PROGRAM=${BIRD_TIMEOUT_PROGRAM:-/usr/bin/timeout}
NMCLI_PROGRAM=${BIRD_NMCLI_PROGRAM:-/usr/bin/nmcli}
NM_ONLINE_PROGRAM=${BIRD_NM_ONLINE_PROGRAM:-/usr/bin/nm-online}
IWCTL_PROGRAM=${BIRD_IWCTL_PROGRAM:-/usr/bin/iwctl}
RFKILL_PROGRAM=${BIRD_RFKILL_PROGRAM:-/usr/sbin/rfkill}
IP_PROGRAM=${BIRD_IP_PROGRAM:-/usr/sbin/ip}
JOURNALCTL_PROGRAM=${BIRD_JOURNALCTL_PROGRAM:-/usr/bin/journalctl}
LS_PROGRAM=${BIRD_LS_PROGRAM:-/bin/ls}
HEAD_PROGRAM=${BIRD_HEAD_PROGRAM:-/usr/bin/head}
USLEEP_PROGRAM=${BIRD_USLEEP_PROGRAM:-/usr/bin/usleep}
UPTIME_PATH=${BIRD_UPTIME_PATH:-/proc/uptime}

# Fixed production audit anchors; host fixtures override only the executable:
# /usr/bin/nmcli -w 30 connection up
# /usr/bin/nm-online -q --timeout=10

mkdir -p "${FLAG%/*}" "${LOG%/*}"
exec >>"$LOG" 2>&1
printf 'Bird network log shareability=private-raw path=%s\n' "$LOG"

bounded_command() {
	BOUND=$1
	shift
	"$TIMEOUT_PROGRAM" --signal=TERM --kill-after=1s "$BOUND" "$@"
}

find_wifi_device() {
	WIFI_DEV=
	NET_LIST_STATUS=0
	NET_LIST=$(bounded_command 0.5s "$LS_PROGRAM" "$SYS_CLASS_NET" 2>/dev/null) || \
		NET_LIST_STATUS=$?
	while IFS= read -r NET_DEVICE; do
		case "$NET_DEVICE" in
			wlan*)
				NET_DEVICE_SUFFIX=${NET_DEVICE#wlan}
				case "$NET_DEVICE_SUFFIX" in
					''|*[!0-9]*) ;;
					*) WIFI_DEV=$NET_DEVICE; break ;;
				esac
				;;
		esac
	done <<<"$NET_LIST"
}

network_unit_summary() {
	NETWORK_MANAGER_STATE=unknown
	IWD_STATE=unknown
	RESOLVED_STATE=unknown
	TIMESYNC_STATE=unknown
	RFKILL_SERVICE_STATE=unknown
	UNIT_QUERY_STATUS=0
	UNIT_OUTPUT=$(bounded_command 0.5s "$SYSTEMCTL_PROGRAM" is-active \
		NetworkManager.service iwd.service systemd-resolved.service \
		systemd-timesyncd.service systemd-rfkill.service 2>/dev/null) || \
		UNIT_QUERY_STATUS=$?
	UNIT_INDEX=0
	while IFS= read -r UNIT_LINE; do
		UNIT_INDEX=$((UNIT_INDEX + 1))
		case "$UNIT_INDEX" in
			1) NETWORK_MANAGER_STATE=$UNIT_LINE ;;
			2) IWD_STATE=$UNIT_LINE ;;
			3) RESOLVED_STATE=$UNIT_LINE ;;
			4) TIMESYNC_STATE=$UNIT_LINE ;;
			5) RFKILL_SERVICE_STATE=$UNIT_LINE ;;
		esac
	done <<<"$UNIT_OUTPUT"
	printf 'Bird network services active=%s/%s/%s/%s/%s query_status=%s flag=%s\n' \
		"$NETWORK_MANAGER_STATE" "$IWD_STATE" "$RESOLVED_STATE" \
		"$TIMESYNC_STATE" "$RFKILL_SERVICE_STATE" "$UNIT_QUERY_STATUS" \
		"$([ -e "$FLAG" ] && printf present || printf absent)"
}

raw_diagnostic_probe() {
	PROBE_NAME=$1
	shift
	PROBE_STATUS=0
	bounded_command 2s "$@" 2>&1 | "$HEAD_PROGRAM" -c 131072
	PROBE_PIPE_STATUS=("${PIPESTATUS[@]}")
	PROBE_STATUS=${PROBE_PIPE_STATUS[0]}
	printf '\nBird network diagnostic probe=%s status=%s bound=2s bytes=131072\n' \
		"$PROBE_NAME" "$PROBE_STATUS"
}

units_stopped_confirmed() {
	NETWORK_MANAGER_STATE=unknown
	IWD_STATE=unknown
	RESOLVED_STATE=unknown
	TIMESYNC_STATE=unknown
	RFKILL_SERVICE_STATE=unknown
	STOP_UNIT_QUERY_STATUS=0
	STOP_UNIT_OUTPUT=$(bounded_command 0.5s "$SYSTEMCTL_PROGRAM" is-active \
		NetworkManager.service iwd.service systemd-resolved.service \
		systemd-timesyncd.service systemd-rfkill.service 2>/dev/null) || \
		STOP_UNIT_QUERY_STATUS=$?
	STOP_UNIT_INDEX=0
	while IFS= read -r STOP_UNIT_LINE; do
		STOP_UNIT_INDEX=$((STOP_UNIT_INDEX + 1))
		case "$STOP_UNIT_INDEX" in
			1) NETWORK_MANAGER_STATE=$STOP_UNIT_LINE ;;
			2) IWD_STATE=$STOP_UNIT_LINE ;;
			3) RESOLVED_STATE=$STOP_UNIT_LINE ;;
			4) TIMESYNC_STATE=$STOP_UNIT_LINE ;;
			5) RFKILL_SERVICE_STATE=$STOP_UNIT_LINE ;;
		esac
	done <<<"$STOP_UNIT_OUTPUT"
	for UNIT_STATE in "$NETWORK_MANAGER_STATE" "$IWD_STATE" \
		"$RESOLVED_STATE" "$TIMESYNC_STATE" "$RFKILL_SERVICE_STATE"; do
		case "$UNIT_STATE" in
			inactive|failed) ;;
			*) return 1 ;;
		esac
	done
	return 0
}

radio_stopped_confirmed() {
	RADIO_QUERY_STATUS=0
	RADIO_OUTPUT=$(bounded_command 0.5s "$RFKILL_PROGRAM" list wifi 2>/dev/null) || \
		RADIO_QUERY_STATUS=$?
	[ "$RADIO_QUERY_STATUS" -eq 0 ] || return 1
	RADIO_SOFT_BLOCK_SEEN=0
	RADIO_ALL_SOFT_BLOCKED=1
	while IFS= read -r RADIO_LINE; do
		case "$RADIO_LINE" in
			*"Soft blocked: yes"*) RADIO_SOFT_BLOCK_SEEN=1 ;;
			*"Soft blocked:"*)
				RADIO_SOFT_BLOCK_SEEN=1
				RADIO_ALL_SOFT_BLOCKED=0
				;;
		esac
	done <<<"$RADIO_OUTPUT"
	[ "$RADIO_SOFT_BLOCK_SEEN" -eq 1 ] && \
		[ "$RADIO_ALL_SOFT_BLOCKED" -eq 1 ]
}

network_stopped_confirmed() {
	UNITS_STOPPED=0
	RADIO_STOPPED=0
	units_stopped_confirmed && UNITS_STOPPED=1
	radio_stopped_confirmed && RADIO_STOPPED=1
	[ "$UNITS_STOPPED" -eq 1 ] && [ "$RADIO_STOPPED" -eq 1 ]
}

case "${1:-}" in
	start|start-interactive)
		START_MODE=$1
		if [ "$START_MODE" = start-interactive ]; then
			COMMAND_BOUND=0.5s
			SYSTEMD_START_OPTION=--no-block
		else
			COMMAND_BOUND=4s
			SYSTEMD_START_OPTION=
		fi
		printf 'Bird network request start mode=%s uptime=' "$START_MODE"
		cut -d ' ' -f 1 "$UPTIME_PATH"
		if ! touch "$FLAG"; then
			printf '%s\n' 'Bird network request failed stage=request-flag'
			exit 1
		fi
		network_unit_summary

		RFKILL_SERVICE_STATUS=0
		bounded_command "$COMMAND_BOUND" "$SYSTEMCTL_PROGRAM" start \
			${SYSTEMD_START_OPTION:+"$SYSTEMD_START_OPTION"} \
			systemd-rfkill.service || RFKILL_SERVICE_STATUS=$?
		printf 'Bird network step=systemctl-start-systemd-rfkill status=%s\n' \
			"$RFKILL_SERVICE_STATUS"
		SYSTEM_SERVICES_STATUS=0
		bounded_command "$COMMAND_BOUND" "$SYSTEMCTL_PROGRAM" start \
			${SYSTEMD_START_OPTION:+"$SYSTEMD_START_OPTION"} dbus.service \
			systemd-resolved.service systemd-timesyncd.service || \
			SYSTEM_SERVICES_STATUS=$?
		printf 'Bird network step=systemctl-start-system-services status=%s\n' \
			"$SYSTEM_SERVICES_STATUS"
		RFKILL_UNBLOCK_STATUS=0
		bounded_command "$COMMAND_BOUND" "$RFKILL_PROGRAM" unblock wifi || \
			RFKILL_UNBLOCK_STATUS=$?
		printf 'Bird network step=rfkill-unblock status=%s\n' \
			"$RFKILL_UNBLOCK_STATUS"
		IWD_SERVICE_STATUS=0
		bounded_command "$COMMAND_BOUND" "$SYSTEMCTL_PROGRAM" start \
			${SYSTEMD_START_OPTION:+"$SYSTEMD_START_OPTION"} iwd.service || \
			IWD_SERVICE_STATUS=$?
		printf 'Bird network step=systemctl-start-iwd status=%s\n' \
			"$IWD_SERVICE_STATUS"
		NM_SERVICE_STATUS=0
		bounded_command "$COMMAND_BOUND" "$SYSTEMCTL_PROGRAM" start \
			${SYSTEMD_START_OPTION:+"$SYSTEMD_START_OPTION"} \
			NetworkManager.service || NM_SERVICE_STATUS=$?
		printf 'Bird network step=systemctl-start-networkmanager status=%s\n' \
			"$NM_SERVICE_STATUS"

		if [ "$START_MODE" = start ]; then
			for _ in $(seq 1 100); do
				NM_ACTIVE_STATUS=0
				NM_ACTIVE=$(bounded_command 0.5s "$SYSTEMCTL_PROGRAM" is-active \
					NetworkManager.service 2>/dev/null) || NM_ACTIVE_STATUS=$?
				[ "$NM_ACTIVE_STATUS" -eq 0 ] && [ "$NM_ACTIVE" = active ] && break
				"$USLEEP_PROGRAM" 50000
			done
		fi

		find_wifi_device
		NM_RADIO_STATUS=not-requested
		NM_MANAGED_STATUS=not-requested
		if [ -n "$WIFI_DEV" ]; then
			NM_RADIO_STATUS=0
			bounded_command "$COMMAND_BOUND" "$NMCLI_PROGRAM" radio wifi on || \
				NM_RADIO_STATUS=$?
			printf 'Bird network step=nmcli-radio-wifi-on status=%s\n' \
				"$NM_RADIO_STATUS"
			NM_MANAGED_STATUS=0
			bounded_command "$COMMAND_BOUND" "$NMCLI_PROGRAM" device set \
				"$WIFI_DEV" managed yes || NM_MANAGED_STATUS=$?
			printf 'Bird network step=nmcli-device-managed status=%s\n' \
				"$NM_MANAGED_STATUS"
		fi

		PROFILE=not-probed
		NM_RESCAN_STATUS=not-requested
		NM_RELOAD_STATUS=not-requested
		NM_CONNECT_STATUS=not-requested
		NM_ONLINE_STATUS=not-requested
		if [ "$START_MODE" = start ]; then
			IWCTL_FOUND=0
			if [ -n "$WIFI_DEV" ]; then
				for _ in $(seq 1 20); do
					IWCTL_STATUS=0
					IWCTL_OUTPUT=$(bounded_command 0.5s "$IWCTL_PROGRAM" \
						device list 2>/dev/null) || IWCTL_STATUS=$?
					case "$IWCTL_OUTPUT" in
						*"$WIFI_DEV"*) IWCTL_FOUND=1; break ;;
					esac
					"$USLEEP_PROGRAM" 50000
				done
			fi
			printf 'Bird network step=iwctl-device-list found=%s\n' "$IWCTL_FOUND"
			NM_RESCAN_STATUS=1
			if [ -n "$WIFI_DEV" ]; then
				for _ in 1 2 3; do
					if bounded_command 6s "$NMCLI_PROGRAM" -w 5 \
						device wifi rescan ifname "$WIFI_DEV" 2>/dev/null; then
						NM_RESCAN_STATUS=0
						break
					fi
					"$USLEEP_PROGRAM" 500000
				done
			fi
			printf 'Bird network step=nmcli-wifi-rescan status=%s\n' \
				"$NM_RESCAN_STATUS"
			NM_RELOAD_STATUS=0
			bounded_command 2s "$NMCLI_PROGRAM" connection reload || \
				NM_RELOAD_STATUS=$?
			printf 'Bird network step=nmcli-connection-reload status=%s\n' \
				"$NM_RELOAD_STATUS"
			PROFILE_STATUS=0
			PROFILE_OUTPUT=$(bounded_command 2s "$NMCLI_PROGRAM" -t -f \
				NAME,TYPE connection show 2>/dev/null) || PROFILE_STATUS=$?
			PROFILE=
			while IFS=: read -r PROFILE_NAME PROFILE_TYPE _; do
				case "$PROFILE_TYPE" in
					wifi|802-11-wireless) PROFILE=$PROFILE_NAME; break ;;
				esac
			done <<<"$PROFILE_OUTPUT"
			NM_CONNECT_STATUS=1
			ACTIVATION=failed
			if [ "$PROFILE_STATUS" -eq 0 ] && [ -n "$PROFILE" ] && \
				[ -n "$WIFI_DEV" ] && bounded_command 31s "$NMCLI_PROGRAM" \
				-w 30 connection up id "$PROFILE" ifname "$WIFI_DEV"; then
				NM_CONNECT_STATUS=0
				ACTIVATION=ready
			fi
			printf 'Bird network step=nmcli-connection-up status=%s profile=%s\n' \
				"$NM_CONNECT_STATUS" "${PROFILE:-missing}"
			NM_ONLINE_STATUS=0
			if bounded_command 11s "$NM_ONLINE_PROGRAM" -q --timeout=10; then
				LINK=ready
			else
				NM_ONLINE_STATUS=$?
				LINK=timeout
			fi
			printf 'Bird network step=nm-online status=%s\n' "$NM_ONLINE_STATUS"
		else
			ACTIVATION=interactive
			LINK=awaiting-user
			printf 'Bird network step=interactive-connection profile=%s link=%s\n' \
				"$PROFILE" "$LINK"
		fi

		network_unit_summary
		START_STATUS=0
		READINESS=ready
		for STEP_STATUS in "$RFKILL_SERVICE_STATUS" "$SYSTEM_SERVICES_STATUS" \
			"$RFKILL_UNBLOCK_STATUS" "$IWD_SERVICE_STATUS" "$NM_SERVICE_STATUS"; do
			[ "$STEP_STATUS" = 0 ] || START_STATUS=1
		done
		case "$NETWORK_MANAGER_STATE:$IWD_STATE" in
			active:active) ;;
			*) START_STATUS=1 ;;
		esac
		if [ -z "$WIFI_DEV" ] || [ "$NM_RADIO_STATUS" != 0 ] || \
			[ "$NM_MANAGED_STATUS" != 0 ]; then
			START_STATUS=1
		fi
		if [ "$START_MODE" = start ] && { [ "$ACTIVATION" != ready ] || \
			[ "$LINK" != ready ]; }; then
			START_STATUS=1
		fi
		[ "$START_STATUS" -eq 0 ] || READINESS=degraded
		printf 'Bird network request readiness=%s mode=%s profile=%s activation=%s link=%s status=%s uptime=' \
			"$READINESS" "$START_MODE" "${PROFILE:-missing}" "$ACTIVATION" \
			"$LINK" "$START_STATUS"
		cut -d ' ' -f 1 "$UPTIME_PATH"

		if [ "$START_MODE" = start ]; then
			printf '%s\n' '--- NetworkManager connections (private raw, bounded) ---'
			raw_diagnostic_probe nmcli-connections "$NMCLI_PROGRAM" -t -f \
				NAME,TYPE,AUTOCONNECT connection show || :
			printf '%s\n' '--- Wi-Fi device (private raw, bounded) ---'
			raw_diagnostic_probe nmcli-device "$NMCLI_PROGRAM" -t -f \
				GENERAL.DEVICE,GENERAL.STATE,GENERAL.REASON,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY \
				device show || :
			printf '%s\n' '--- Wi-Fi radio and scan (private raw, bounded) ---'
			raw_diagnostic_probe rfkill "$RFKILL_PROGRAM" list wifi || :
			if [ -n "$WIFI_DEV" ]; then
				raw_diagnostic_probe nmcli-wifi-list "$NMCLI_PROGRAM" -t -f \
					IN-USE,SSID,SIGNAL,SECURITY device wifi list \
					ifname "$WIFI_DEV" || :
			fi
			printf '%s\n' '--- routes (private raw, bounded) ---'
			raw_diagnostic_probe ip-route "$IP_PROGRAM" route || :
			if [ "$ACTIVATION" != ready ]; then
				printf '%s\n' '--- failed activation journal (private raw, bounded) ---'
				raw_diagnostic_probe journal "$JOURNALCTL_PROGRAM" -b \
					-u iwd.service -u NetworkManager.service --no-pager -n 120 || :
			fi
		fi
		exit "$START_STATUS"
		;;
	stop)
		printf 'Bird network release start uptime='
		cut -d ' ' -f 1 "$UPTIME_PATH"
		network_unit_summary
		find_wifi_device
		NM_DISCONNECT_STATUS=0
		if [ -n "$WIFI_DEV" ]; then
			bounded_command 3s "$NMCLI_PROGRAM" device disconnect "$WIFI_DEV" || \
				NM_DISCONNECT_STATUS=$?
		fi
		printf 'Bird network step=nmcli-device-disconnect status=%s\n' \
			"$NM_DISCONNECT_STATUS"
		RFKILL_BLOCK_STATUS=0
		bounded_command 3s "$RFKILL_PROGRAM" block wifi || \
			RFKILL_BLOCK_STATUS=$?
		printf 'Bird network step=rfkill-block status=%s\n' "$RFKILL_BLOCK_STATUS"
		NM_STOP_STATUS=0
		bounded_command 3s "$SYSTEMCTL_PROGRAM" stop --no-block \
			NetworkManager.service iwd.service systemd-resolved.service \
			systemd-timesyncd.service systemd-rfkill.service || \
			NM_STOP_STATUS=$?
		printf 'Bird network step=systemctl-stop-network-stack status=%s\n' \
			"$NM_STOP_STATUS"
		STOP_CONFIRMED=0
		for _ in $(seq 1 10); do
			if network_stopped_confirmed; then
				STOP_CONFIRMED=1
				break
			fi
			"$USLEEP_PROGRAM" 50000
		done
		printf 'Bird network stop confirmation units=%s radio=%s nm=%s iwd=%s resolved=%s timesync=%s rfkill=%s unit_query=%s radio_query=%s\n' \
			"$UNITS_STOPPED" "$RADIO_STOPPED" "$NETWORK_MANAGER_STATE" \
			"$IWD_STATE" "$RESOLVED_STATE" "$TIMESYNC_STATE" \
			"$RFKILL_SERVICE_STATE" "${STOP_UNIT_QUERY_STATUS:-unknown}" \
			"${RADIO_QUERY_STATUS:-unknown}"
		if [ "$STOP_CONFIRMED" -ne 1 ]; then
			printf '%s\n' 'Bird network release unresolved request=retained'
			exit 1
		fi
		if ! rm -f "$FLAG"; then
			printf '%s\n' 'Bird network release unresolved request=retained reason=flag-remove'
			exit 1
		fi
		network_unit_summary
		printf 'Bird network release ready request=removed uptime='
		cut -d ' ' -f 1 "$UPTIME_PATH"
		;;
	*)
		printf 'usage: %s {start|start-interactive|stop}\n' "$0" >&2
		exit 2
		;;
esac
