#!/bin/bash
# Route Bird selections through the exact ROCKNIX 20260701 application
# contract. No chroot, copied library set, hand-written device metadata or
# substitute audio stack exists in this path.

set -u

CATALOG_PATH_MAX_BYTES=4085
APPLICATION_CONTRACT_REVISION=bird-application-v1
APPLICATION_READY=${BIRD_APPLICATION_READY:-/run/bird/application-contract-ready}

application_contract_valid() {
	[ -f "$APPLICATION_READY" ] || return 1
	CONTRACT_EXTRA_LINE=0
	CONTRACT_TRAILING_LINE=
	{
		IFS= read -r CONTRACT_REVISION_LINE || return 1
		IFS= read -r CONTRACT_UPTIME_LINE || return 1
		# read(1) still assigns bytes when EOF arrives without a trailing newline,
		# but returns nonzero. Treat either result or assigned data as a third line.
		if IFS= read -r CONTRACT_TRAILING_LINE ||
			[ -n "$CONTRACT_TRAILING_LINE" ]; then
			CONTRACT_EXTRA_LINE=1
		fi
	} <"$APPLICATION_READY"
	[ "$CONTRACT_EXTRA_LINE" -eq 0 ] && \
		[ "$CONTRACT_REVISION_LINE" = \
			"contract_revision=$APPLICATION_CONTRACT_REVISION" ] || return 1
	case "$CONTRACT_UPTIME_LINE" in
		published_uptime=*) CONTRACT_UPTIME=${CONTRACT_UPTIME_LINE#published_uptime=} ;;
		*) return 1 ;;
	esac
	case "$CONTRACT_UPTIME" in
		*.*)
			CONTRACT_UPTIME_WHOLE=${CONTRACT_UPTIME%%.*}
			CONTRACT_UPTIME_FRACTION=${CONTRACT_UPTIME#*.}
			;;
		*) return 1 ;;
	esac
	case "$CONTRACT_UPTIME_WHOLE" in ''|*[!0-9]*) return 1 ;; esac
	case "$CONTRACT_UPTIME_FRACTION" in ''|*[!0-9]*) return 1 ;; esac
	return 0
}

wait_application_contract() {
	application_contract_valid && return 0
	# A selection may arrive from initramfs before ROCKNIX has generated the
	# exact Sway/application configuration. Request that existing job and join
	# only its first usable milestone; the launcher remains independent.
	systemctl start --no-block rocknix-autostart.service 8>&- 9>&- || return 1
	for _ in $(seq 1 1200); do
		application_contract_valid && return 0
		usleep 25000
	done
	return 1
}

if [ "${BIRD_TEST_WAIT_APPLICATION_CONTRACT:-0}" = 1 ]; then
	wait_application_contract
	exit $?
fi

scope_poll_delay() {
	if [ "$1" -le 10 ]; then
		SCOPE_POLL_DELAY_US=10000
	elif [ "$1" -le 30 ]; then
		SCOPE_POLL_DELAY_US=50000
	else
		SCOPE_POLL_DELAY_US=250000
	fi
}

if [ -n "${BIRD_TEST_SCOPE_POLL_STEPS:-}" ]; then
	BIRD_TEST_POLL_INDEX=1
	while [ "$BIRD_TEST_POLL_INDEX" -le "$BIRD_TEST_SCOPE_POLL_STEPS" ]; do
		scope_poll_delay "$BIRD_TEST_POLL_INDEX"
		printf '%s\n' "$SCOPE_POLL_DELAY_US"
		BIRD_TEST_POLL_INDEX=$((BIRD_TEST_POLL_INDEX + 1))
	done
	exit 0
fi

validate_host_path() {
	EXTRA_LINE=$1
	HOST_PATH_BYTES=$(LC_ALL=C printf '%s' "$HOST_PATH" | wc -c | tr -d ' ')
	case "$HOST_PATH_BYTES" in
		''|*[!0-9]*) HOST_PATH_BYTES=$((CATALOG_PATH_MAX_BYTES + 1)) ;;
	esac
	if [ "$EXTRA_LINE" -ne 0 ] || \
		[ "$HOST_PATH_BYTES" -gt "$CATALOG_PATH_MAX_BYTES" ] || \
		LC_ALL=C printf '%s' "$HOST_PATH" | grep -q '[[:cntrl:]]'; then
		PATH_REJECTION="malformed ($HOST_PATH_BYTES bytes)"
		return 1
	fi
	case "$HOST_PATH" in
		*/../*|*/..|../*|..) PATH_REJECTION=traversal; return 1 ;;
		/mnt/mmc/*) return 0 ;;
		*) PATH_REJECTION=prefix; return 1 ;;
	esac
}

if [ "${BIRD_TEST_VALIDATE_HOST_PATH:-0}" = 1 ]; then
	HOST_PATH=${BIRD_TEST_HOST_PATH:-}
	if validate_host_path "${BIRD_TEST_EXTRA_LINE:-0}"; then exit 0; fi
	exit 1
fi

REQUEST=${1:-/run/muos/bird-launch-request}
LOG_DIR=/storage/bird-data/MUOS/Bird/log
LOG=$LOG_DIR/stock-root-content-latest.log
SWAY_SOCKET=/var/run/0-runtime-dir/sway-ipc.0.sock
PORTMASTER_ONLY=0
PORT_PREP=/storage/.config/bird/prepare-ports.sh
NETWORK=/storage/.config/bird/bird-network.sh
SESSION_PID=/run/bird/content-session.pid
SESSION_DIR=/run/bird/content-sessions
SCOPE_UNIT=
SCOPE_INVOCATION=
SCOPE_CONTROL_GROUP=
SCOPE_RUNNER_PID=
SCOPE_RUNNER_START_TICKS=
SCOPE_START_GATE=
SCOPE_START_READY=
SCOPE_START_CANCEL=
SCOPE_EXPECTED=0
SWAY_OWNED=0
PORTMASTER_NETWORK=0
CLEANUP_STATE=not-started
RUNNER_STATE=
RUNNER_START_TICKS=
GUARD_UNIT=
GUARD_STARTED=0
SESSION_TOKEN=
SESSION_RECORD=
RESOURCE_LOCK=/run/bird/content-resources.lock
RESOURCE_LOCK_HELD=0
SESSION_LOCK=/run/bird/content-session.lock
SESSION_LOCK_HELD=0
SWAY_OWNER=/run/bird/sway-owner
NETWORK_OWNER=/run/bird/network-owner
SCOPE_QUERY_RESULT=unknown
SCOPE_QUERY_VALUE=
PROCESS_PROC_ROOT=${BIRD_PROCESS_PROC_ROOT:-/proc}

initial_process_start_ticks() {
	[ -r "$1" ] || return 1
	PROCESS_STAT_RECORD=$(cat "$1" 2>/dev/null) || \
		return 1
	case "$PROCESS_STAT_RECORD" in
		*") "*)
			printf '%s\n' "${PROCESS_STAT_RECORD##*) }" | awk '{print $20}'
			;;
		*) return 1 ;;
	esac
}

load_launch_request() {
	[ -s "$REQUEST" ] || { PATH_REJECTION=missing; return 1; }
	EXTRA_REQUEST_LINE=0
	TRAILING_REQUEST_LINE=
	KIND=
	REQUESTED_CORE=
	NAME=
	HOST_PATH=
	REQUEST_KIND_OK=0
	REQUEST_CORE_OK=0
	REQUEST_NAME_OK=0
	REQUEST_HOST_OK=0
	{
		if IFS= read -r KIND; then REQUEST_KIND_OK=1; fi
		if IFS= read -r REQUESTED_CORE; then REQUEST_CORE_OK=1; fi
		if IFS= read -r NAME; then REQUEST_NAME_OK=1; fi
		if IFS= read -r HOST_PATH; then REQUEST_HOST_OK=1; fi
		if IFS= read -r TRAILING_REQUEST_LINE ||
			[ -n "$TRAILING_REQUEST_LINE" ]; then
			EXTRA_REQUEST_LINE=1
		fi
	} <"$REQUEST"
	if [ "$REQUEST_KIND_OK$REQUEST_CORE_OK$REQUEST_NAME_OK$REQUEST_HOST_OK" \
		!= 1111 ]; then
		PATH_REJECTION='malformed request record'
		return 1
	fi
	validate_host_path "$EXTRA_REQUEST_LINE" || return 1
	CONTENT=/storage/bird-data/${HOST_PATH#/mnt/mmc/}
	return 0
}

if [ "${BIRD_TEST_PARSE_LAUNCH_REQUEST:-0}" = 1 ]; then
	REQUEST=${BIRD_TEST_REQUEST_PATH:-}
	load_launch_request
	exit $?
fi

mkdir -p "$LOG_DIR" /run/bird "$SESSION_DIR"

if [ "$REQUEST" = --portmaster ]; then
	PORTMASTER_ONLY=1
else
	if ! load_launch_request; then
		printf 'Rejected Bird content path (%s): %s\n' \
			"$PATH_REJECTION" "$HOST_PATH" >"$LOG"
		exit 1
	fi
fi

BOOT_ID_FULL=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)
BOOT_ID=$(printf '%s' "$BOOT_ID_FULL" | cut -c 1-8)
[ -n "$BOOT_ID" ] || BOOT_ID=boot
RUNNER_START_TICKS=$(initial_process_start_ticks \
	"$PROCESS_PROC_ROOT/$$/stat")
[ -n "$RUNNER_START_TICKS" ] || RUNNER_START_TICKS=unknown
SESSION_TOKEN=${BOOT_ID}-$$-${RUNNER_START_TICKS}
SESSION_RECORD=$SESSION_DIR/$SESSION_TOKEN.session
RUNNER_STATE=/run/bird/content-runner-$SESSION_TOKEN.state
SCOPE_START_GATE=/run/bird/content-scope-$SESSION_TOKEN.start
SCOPE_START_READY=/run/bird/content-scope-$SESSION_TOKEN.ready
SCOPE_START_CANCEL=/run/bird/content-scope-$SESSION_TOKEN.cancel
SESSION_TICK=$(cut -d ' ' -f 1 /proc/uptime | tr -d .)
if [ "$PORTMASTER_ONLY" -eq 1 ]; then
	SESSION_KIND=portmaster
else
	SESSION_KIND=kind$KIND
fi
SESSION_LOG=$LOG_DIR/stock-root-content-$BOOT_ID-$SESSION_TICK-$SESSION_KIND.log

session_lock() {
	[ "$SESSION_LOCK_HELD" -eq 0 ] || return 0
	exec 8>"$SESSION_LOCK" || return 1
	flock -x 8 || { exec 8>&-; return 1; }
	SESSION_LOCK_HELD=1
}

session_unlock() {
	[ "$SESSION_LOCK_HELD" -eq 1 ] || return 0
	flock -u 8 2>/dev/null || :
	exec 8>&-
	SESSION_LOCK_HELD=0
}

resource_lock() {
	[ "$RESOURCE_LOCK_HELD" -eq 0 ] || return 0
	exec 9>"$RESOURCE_LOCK" || return 1
	flock -x 9 || { exec 9>&-; return 1; }
	RESOURCE_LOCK_HELD=1
}

resource_unlock() {
	[ "$RESOURCE_LOCK_HELD" -eq 1 ] || return 0
	flock -u 9 2>/dev/null || :
	exec 9>&-
	RESOURCE_LOCK_HELD=0
}

owner_matches() {
	OWNER_FILE=$1
	[ -s "$OWNER_FILE" ] || return 1
	IFS= read -r OWNER_TOKEN <"$OWNER_FILE" || return 1
	[ "$OWNER_TOKEN" = "$SESSION_TOKEN" ]
}

owner_relation() {
	OWNER_RELATION=unknown
	OWNER_FILE=$1
	[ -s "$OWNER_FILE" ] || return 0
	IFS= read -r OWNER_TOKEN <"$OWNER_FILE" || return 0
	[ -n "$OWNER_TOKEN" ] || return 0
	if [ "$OWNER_TOKEN" = "$SESSION_TOKEN" ]; then
		OWNER_RELATION=ours
	else
		OWNER_RELATION=transferred
	fi
}

claim_owner() {
	OWNER_FILE=$1
	TMP=$OWNER_FILE.tmp.$$
	if printf '%s\n' "$SESSION_TOKEN" >"$TMP" && \
		mv -f "$TMP" "$OWNER_FILE"; then
		return 0
	fi
	rm -f "$TMP" 2>/dev/null || :
	return 1
}

remove_owned_token() {
	OWNER_FILE=$1
	owner_matches "$OWNER_FILE" || return 1
	rm -f "$OWNER_FILE"
}

start_sway() {
	resource_lock || return 1
	if ! claim_owner "$SWAY_OWNER"; then
		resource_unlock
		return 1
	fi
	# Ownership is published while holding the cross-session lock. An older
	# crash guard must either finish first or observe this newer token and leave
	# the compositor alone.
	SWAY_OWNED=1
	if ! publish_runner_state 1; then
		SWAY_OWNED=0
		remove_owned_token "$SWAY_OWNER" || :
		resource_unlock
		return 1
	fi
	if ! systemctl start sway.service 8>&- 9>&-; then
		resource_unlock
		return 1
	fi
	resource_unlock
	for _ in $(seq 1 200); do
		[ -S "$SWAY_SOCKET" ] && return 0
		usleep 25000
	done
	return 1
}

ensure_content_services() {
	# Bird can be selected before the background compatibility graph completes.
	# Join only the services every proven application session actually needs.
	systemctl start dbus.service 8>&- 9>&- || return 1
	systemctl start pipewire.service wireplumber.service \
		pipewire-pulse.service 8>&- 9>&- || return 1
	# The writable ROCKNIX image can persist a muted internal route even while
	# every audio service, app stream and ALSA control looks healthy. Reapply the
	# saved Bird volume and explicitly clear that route mute before every app.
	/storage/.config/bird/bird-volume.sh restore 8>&- 9>&- || return 1
}

stop_sway() {
	[ "$SWAY_OWNED" -eq 1 ] || return 0
	resource_lock || return 1
	owner_relation "$SWAY_OWNER"
	if [ "$OWNER_RELATION" = transferred ]; then
		# Ownership was deliberately transferred to a newer session.
		SWAY_OWNED=0
		if ! publish_runner_state 1; then
			SWAY_OWNED=1
			resource_unlock
			return 1
		fi
		resource_unlock
		return 0
	fi
	if [ "$OWNER_RELATION" != ours ]; then
		resource_unlock
		return 1
	fi
	systemctl stop sway.service 8>&- 9>&- || :
	for _ in $(seq 1 100); do
		if sway_stopped_confirmed; then
			SWAY_OWNED=0
			if ! publish_runner_state 1; then
				SWAY_OWNED=1
				resource_unlock
				return 1
			fi
			if ! remove_owned_token "$SWAY_OWNER"; then
				SWAY_OWNED=1
				publish_runner_state 1 || :
				resource_unlock
				return 1
			fi
			resource_unlock
			return 0
		fi
		usleep 20000
	done
	systemctl kill --kill-whom=all --signal=KILL sway.service \
		8>&- 9>&- 2>/dev/null || :
	systemctl stop sway.service 8>&- 9>&- 2>/dev/null || :
	for _ in $(seq 1 50); do
		if sway_stopped_confirmed; then
			SWAY_OWNED=0
			if ! publish_runner_state 1; then
				SWAY_OWNED=1
				resource_unlock
				return 1
			fi
			if ! remove_owned_token "$SWAY_OWNER"; then
				SWAY_OWNED=1
				publish_runner_state 1 || :
				resource_unlock
				return 1
			fi
			resource_unlock
			return 0
		fi
		usleep 20000
	done
	publish_runner_state 1 || :
	resource_unlock
	return 1
}

install_mpv_input_policy() {
	SOURCE=/flash/bird/mpv-input.conf
	TARGET=/storage/.config/mpv/input.conf
	CONFIG=/storage/.config/mpv/mpv.conf
	RESUME='save-position-on-quit=yes'
	[ -f "$SOURCE" ] || return 1
	mkdir -p /storage/.config/mpv || return 1
	if ! cmp -s "$SOURCE" "$TARGET"; then
		cp -f "$SOURCE" "$TARGET" || return 1
		printf 'Bird MPV system-volume-only policy installed\n'
	fi
	# ROCKNIX's player wrapper does not promise watch-later persistence. Keep
	# the user's config intact and add the one Bird-owned playback contract only
	# when it is not already expressed.
	if [ ! -f "$CONFIG" ] || ! grep -Eq \
		'^[[:space:]]*save-position-on-quit[[:space:]]*=[[:space:]]*(yes|true)[[:space:]]*$' \
		"$CONFIG"; then
		printf '\n# birdOS: resume media after a clean player exit\n%s\n' \
			"$RESUME" >>"$CONFIG" || return 1
		printf 'Bird MPV resume policy installed\n'
	fi
}

prepare_fmsx_bios() {
	SOURCE='/storage/roms/bios/Machines/Shared Roms'
	for BIOS in MSX MSX2 MSX2EXT MSX2P MSX2PEXT KANJI; do
		[ -f "/storage/roms/bios/$BIOS.ROM" ] ||
			cp "$SOURCE/$BIOS.rom" "/storage/roms/bios/$BIOS.ROM" || return 1
	done
}

scope_query_property() {
	PROPERTY=$1
	UNIT=$2
	SCOPE_QUERY_RESULT=unknown
	SCOPE_QUERY_VALUE=
	PROPERTY_QUERY_OK=0
	if SCOPE_QUERY_VALUE=$(systemctl show --property="$PROPERTY" --value \
		"$UNIT" 8>&- 9>&- 2>/dev/null); then
		PROPERTY_QUERY_OK=1
		if [ -n "$SCOPE_QUERY_VALUE" ]; then
			SCOPE_QUERY_RESULT=present
			return 0
		fi
	fi

	# systemctl may successfully print an empty property for an unloaded unit.
	# LoadState=not-found or a successful exact list with no unit are the only
	# confirmations; every bus/query error remains unknown.
	if LOAD_STATE=$(systemctl show --property=LoadState --value "$UNIT" \
		8>&- 9>&- 2>/dev/null); then
		case "$LOAD_STATE" in
			not-found) SCOPE_QUERY_RESULT=not-found; return 0 ;;
			'') ;;
			*)
				[ "$PROPERTY_QUERY_OK" -eq 0 ] || SCOPE_QUERY_RESULT=present
				return 0
				;;
		esac
	fi
	if UNIT_LIST=$(systemctl list-units --all --full --plain --no-legend \
		"$UNIT" 8>&- 9>&- 2>/dev/null); then
		UNIT_FOUND=0
		while IFS=' ' read -r LISTED_UNIT _; do
			[ "$LISTED_UNIT" = "$UNIT" ] && UNIT_FOUND=1
		done <<EOF
$UNIT_LIST
EOF
		[ "$UNIT_FOUND" -eq 1 ] || SCOPE_QUERY_RESULT=not-found
	fi
	return 0
}

sway_stopped_confirmed() {
	[ ! -S "$SWAY_SOCKET" ] || return 1
	scope_query_property ActiveState sway.service
	case "$SCOPE_QUERY_RESULT:$SCOPE_QUERY_VALUE" in
		not-found:*|present:inactive) return 0 ;;
		*) return 1 ;;
	esac
}

# Return 0 only for this exact invocation, 1 for confirmed gone/replaced, and
# 2 when systemd cannot currently prove either state.
scope_identity_status() {
	[ -n "$SCOPE_UNIT" ] || return 2
	scope_query_property InvocationID "$SCOPE_UNIT"
	case "$SCOPE_QUERY_RESULT" in
		not-found) return 1 ;;
		unknown) return 2 ;;
	esac
	CURRENT_INVOCATION=$SCOPE_QUERY_VALUE
	case "$CURRENT_INVOCATION" in
		00000000000000000000000000000000|*[!0-9a-fA-F]*|'') return 2 ;;
	esac
	[ "${#CURRENT_INVOCATION}" -eq 32 ] || return 2
	if [ -z "$SCOPE_INVOCATION" ]; then
		SCOPE_INVOCATION=$CURRENT_INVOCATION
		write_scope_metadata active || return 2
	fi
	[ "$CURRENT_INVOCATION" = "$SCOPE_INVOCATION" ] && return 0
	return 1
}

# Return 0 active, 1 confirmed inactive/gone/replaced, 2 query unknown.
scope_activity_status() {
	scope_identity_status
	IDENTITY_STATUS=$?
	[ "$IDENTITY_STATUS" -eq 0 ] || return "$IDENTITY_STATUS"
	scope_query_property ActiveState "$SCOPE_UNIT"
	case "$SCOPE_QUERY_RESULT" in
		not-found) return 1 ;;
		unknown) return 2 ;;
	esac
	case "$SCOPE_QUERY_VALUE" in
		active|activating|deactivating|reloading) return 0 ;;
		inactive) return 1 ;;
		*) return 2 ;;
	esac
}

write_scope_metadata() {
	STATE=$1
	if [ "$STATE" = active ]; then
		scope_query_property ControlGroup "$SCOPE_UNIT"
		[ "$SCOPE_QUERY_RESULT" = present ] || return 1
		SCOPE_CONTROL_GROUP=$SCOPE_QUERY_VALUE
		case "$SCOPE_CONTROL_GROUP" in
			/*) ;;
			*) return 1 ;;
		esac
	fi
	TMP=$SESSION_RECORD.tmp.$$
	if ! (
		umask 077
		{
			printf '%s\n' 'version=2' 'boundary=systemd-scope'
			printf 'state=%s\n' "$STATE"
			printf 'session_token=%s\n' "$SESSION_TOKEN"
			printf 'boot_id=%s\n' "$BOOT_ID_FULL"
			printf 'unit=%s\n' "$SCOPE_UNIT"
			printf 'invocation_id=%s\n' "${SCOPE_INVOCATION:-pending}"
			printf 'control_group=%s\n' "$SCOPE_CONTROL_GROUP"
		} >"$TMP" && mv -f "$TMP" "$SESSION_RECORD"
	); then
		rm -f "$TMP" "$SESSION_PID.tmp.$$"
		return 1
	fi
	METADATA_LOCK_LOCAL=0
	if [ "$SESSION_LOCK_HELD" -eq 0 ]; then
		session_lock || return 1
		METADATA_LOCK_LOCAL=1
	fi
	if ! cp -f "$SESSION_RECORD" "$SESSION_PID.tmp.$$" || \
		! mv -f "$SESSION_PID.tmp.$$" "$SESSION_PID"; then
		rm -f "$SESSION_PID.tmp.$$" 2>/dev/null || :
		[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
		return 1
	fi
	[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
	return 0
}

scope_metadata_matches() {
	METADATA_FILE=$1
	[ -f "$METADATA_FILE" ] || return 1
	RECORDED_TOKEN=$(sed -n 's/^session_token=//p' "$METADATA_FILE" | head -n 1)
	RECORDED_UNIT=$(sed -n 's/^unit=//p' "$METADATA_FILE" | head -n 1)
	RECORDED_INVOCATION=$(sed -n 's/^invocation_id=//p' "$METADATA_FILE" | head -n 1)
	[ "$RECORDED_TOKEN" = "$SESSION_TOKEN" ] && \
		[ "$RECORDED_UNIT" = "$SCOPE_UNIT" ] && \
		{ [ "$RECORDED_INVOCATION" = "$SCOPE_INVOCATION" ] || \
			{ [ "$RECORDED_INVOCATION" = pending ] && \
				[ -z "$SCOPE_INVOCATION" ]; }; }
}

discard_unlaunched_metadata() {
	DISCARD_LOCK_LOCAL=0
	if [ "$SESSION_LOCK_HELD" -eq 0 ]; then
		session_lock || return 1
		DISCARD_LOCK_LOCAL=1
	fi
	DISCARD_STATUS=0
	if scope_metadata_matches "$SESSION_PID"; then
		rm -f "$SESSION_PID" || DISCARD_STATUS=1
	fi
	if [ -e "$SESSION_RECORD" ]; then
		if scope_metadata_matches "$SESSION_RECORD"; then
			rm -f "$SESSION_RECORD" || DISCARD_STATUS=1
		else
			DISCARD_STATUS=1
		fi
	fi
	[ "$DISCARD_LOCK_LOCAL" -eq 0 ] || session_unlock
	[ "$DISCARD_STATUS" -eq 0 ]
}

remove_scope_metadata() {
	METADATA_LOCK_LOCAL=0
	if [ "$SESSION_LOCK_HELD" -eq 0 ]; then
		session_lock || return 1
		METADATA_LOCK_LOCAL=1
	fi
	# Revalidate immediately before either unlink. Unknown manager state keeps
	# both records for the runner guard or a later explicit exit attempt.
	if [ -n "$SCOPE_INVOCATION" ]; then
		scope_activity_status
		ACTIVITY_STATUS=$?
		if [ "$ACTIVITY_STATUS" -ne 1 ]; then
			[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
			return 1
		fi
	else
		scope_query_property InvocationID "$SCOPE_UNIT"
		if [ "$SCOPE_QUERY_RESULT" != not-found ]; then
			[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
			return 1
		fi
	fi
	# This path is token-specific. An existing mismatch means corrupt or partial
	# recovery data and must never be silently abandoned. The global pointer may
	# legitimately belong to a newer session and is handled separately below.
	if [ -e "$SESSION_RECORD" ] && \
		! scope_metadata_matches "$SESSION_RECORD"; then
		[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
		return 1
	fi
	EXACT_RECORD_PRESENT=0
	[ ! -e "$SESSION_RECORD" ] || EXACT_RECORD_PRESENT=1

	# Publish that no live scope can remain before deleting its recovery data.
	# If publication fails, the external guard must continue to expect and
	# revalidate the exact scope rather than assuming cleanup succeeded.
	if ! rm -f "$SCOPE_START_GATE" "$SCOPE_START_READY" \
		"$SCOPE_START_CANCEL" "$SCOPE_START_READY".tmp.*; then
		[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
		return 1
	fi
	SCOPE_EXPECTED=0
	if ! publish_runner_state 1; then
		SCOPE_EXPECTED=1
		[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
		return 1
	fi
	# The shared pointer is removed under the same lock used by every publisher,
	# so an old cleanup cannot unlink a newer session after checking its token.
	if scope_metadata_matches "$SESSION_PID"; then
		if ! rm -f "$SESSION_PID"; then
			if [ "$EXACT_RECORD_PRESENT" -eq 1 ]; then
				SCOPE_EXPECTED=1
				publish_runner_state 1 || :
			fi
			[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
			return 1
		fi
	fi
	# Delete the required token-specific record last. No subsequent operation can
	# restore scope_expected=1 and strand the strict crash guard without it.
	if [ "$EXACT_RECORD_PRESENT" -eq 1 ] && ! rm -f "$SESSION_RECORD"; then
		SCOPE_EXPECTED=1
		publish_runner_state 1 || :
		[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
		return 1
	fi
	[ "$METADATA_LOCK_LOCAL" -eq 0 ] || session_unlock
	return 0
}

runner_process_alive() {
	process_identity_alive "$SCOPE_RUNNER_PID" \
		"$SCOPE_RUNNER_START_TICKS"
}

signal_scope() {
	SIGNAL=$1
	scope_identity_status
	IDENTITY_STATUS=$?
	[ "$IDENTITY_STATUS" -eq 0 ] || return "$IDENTITY_STATUS"
	systemctl kill --kill-whom=all --signal="$SIGNAL" "$SCOPE_UNIT" \
		8>&- 9>&- 2>/dev/null || return 2
	return 0
}

wait_scope_inactive_bounded() {
	LIMIT=$1
	COUNT=0
	while [ "$COUNT" -lt "$LIMIT" ]; do
		scope_activity_status
		ACTIVITY_STATUS=$?
		case "$ACTIVITY_STATUS" in
			1) return 0 ;;
			2) return 2 ;;
		esac
		COUNT=$((COUNT + 1))
		usleep 10000
	done
	return 1
}

terminate_scope() {
	[ -n "$SCOPE_UNIT" ] || return 0
	TERMINATE_STATUS=0
	scope_activity_status
	ACTIVITY_STATUS=$?
	case "$ACTIVITY_STATUS" in
		0)
			printf 'Bird content scope=%s action=term\n' "$SCOPE_UNIT"
			signal_scope TERM
			SIGNAL_STATUS=$?
			if [ "$SIGNAL_STATUS" -eq 2 ]; then
				TERMINATE_STATUS=1
			elif [ "$SIGNAL_STATUS" -eq 0 ]; then
				wait_scope_inactive_bounded 100
				WAIT_STATUS=$?
				if [ "$WAIT_STATUS" -eq 1 ]; then
					printf 'Bird content scope=%s action=kill\n' "$SCOPE_UNIT"
					signal_scope KILL
					SIGNAL_STATUS=$?
					[ "$SIGNAL_STATUS" -eq 1 ] || \
						wait_scope_inactive_bounded 100
					WAIT_STATUS=$?
				fi
				[ "$WAIT_STATUS" -eq 0 ] || TERMINATE_STATUS=1
			fi
			;;
		1) ;;
		2) TERMINATE_STATUS=1 ;;
	esac
	if [ "$TERMINATE_STATUS" -eq 0 ]; then
		if remove_scope_metadata; then
			SCOPE_UNIT=
			SCOPE_INVOCATION=
			SCOPE_CONTROL_GROUP=
			SCOPE_RUNNER_PID=
		else
			TERMINATE_STATUS=1
		fi
	else
		printf 'Bird content scope=%s state=query-unknown-or-not-empty\n' \
			"$SCOPE_UNIT"
	fi
	return "$TERMINATE_STATUS"
}

wait_for_scope_registration() {
	COUNT=0
	while [ "$COUNT" -lt 100 ]; do
		scope_query_property InvocationID "$SCOPE_UNIT"
		case "$SCOPE_QUERY_RESULT:$SCOPE_QUERY_VALUE" in
			present:00000000000000000000000000000000|present:|unknown:*) ;;
			not-found:*)
				runner_process_alive || return 1
				;;
			present:*)
				SCOPE_INVOCATION=$SCOPE_QUERY_VALUE
				case "$SCOPE_INVOCATION" in
					*[!0-9a-fA-F]*|'') SCOPE_INVOCATION= ;;
					*) [ "${#SCOPE_INVOCATION}" -eq 32 ] && \
						write_scope_metadata active && return 0 ;;
				esac
				;;
		esac
		if ! runner_process_alive; then
			[ "$SCOPE_QUERY_RESULT" = not-found ] && return 1
			# The provider has exited but the manager cannot prove whether its
			# transient cgroup registered. Hand recovery to cleanup/the exact guard
			# instead of spinning forever in the foreground registration path.
			return 3
		fi
		COUNT=$((COUNT + 1))
		usleep 10000
	done
	return 2
}

process_stat_tail() {
	[ -r "$PROCESS_PROC_ROOT/$1/stat" ] || return 1
	PROCESS_STAT_RECORD=$(cat "$PROCESS_PROC_ROOT/$1/stat" 2>/dev/null) || \
		return 1
	case "$PROCESS_STAT_RECORD" in
		*") "*) printf '%s\n' "${PROCESS_STAT_RECORD##*) }" ;;
		*) return 1 ;;
	esac
}

process_start_ticks() {
	process_stat_tail "$1" | awk '{print $20}'
}

process_pid_running() {
	PROCESS_PID_STAT=$(process_stat_tail "$1") || return 1
	PROCESS_PID_STATE=${PROCESS_PID_STAT%% *}
	[ -n "$PROCESS_PID_STATE" ] && [ "$PROCESS_PID_STATE" != Z ]
}

process_identity_alive() {
	IDENTITY_PID=$1
	IDENTITY_START_TICKS=$2
	case "$IDENTITY_PID:$IDENTITY_START_TICKS" in
		*[!0-9:]*|:*) return 1 ;;
	esac
	IDENTITY_STAT=$(process_stat_tail "$IDENTITY_PID") || return 1
	IDENTITY_STATE=${IDENTITY_STAT%% *}
	IDENTITY_CURRENT_START=$(printf '%s\n' "$IDENTITY_STAT" | awk '{print $20}')
	[ "$IDENTITY_CURRENT_START" = "$IDENTITY_START_TICKS" ] && \
		[ -n "$IDENTITY_STATE" ] && [ "$IDENTITY_STATE" != Z ]
}

stop_and_reap_scope_runner() {
	SCOPE_RUNNER_STOP_PID=$1
	SCOPE_RUNNER_STOP_START=$2
	[ -n "$SCOPE_RUNNER_STOP_PID" ] || return 0
	if process_identity_alive "$SCOPE_RUNNER_STOP_PID" \
		"$SCOPE_RUNNER_STOP_START"; then
		kill -TERM "$SCOPE_RUNNER_STOP_PID" 2>/dev/null || :
	fi
	SCOPE_RUNNER_STOP_COUNT=0
	while process_identity_alive "$SCOPE_RUNNER_STOP_PID" \
		"$SCOPE_RUNNER_STOP_START" && \
		[ "$SCOPE_RUNNER_STOP_COUNT" -lt 100 ]; do
		SCOPE_RUNNER_STOP_COUNT=$((SCOPE_RUNNER_STOP_COUNT + 1))
		usleep 10000
	done
	if process_identity_alive "$SCOPE_RUNNER_STOP_PID" \
		"$SCOPE_RUNNER_STOP_START"; then
		kill -KILL "$SCOPE_RUNNER_STOP_PID" 2>/dev/null || :
	fi
	wait "$SCOPE_RUNNER_STOP_PID" 2>/dev/null || :
	rm -f "$SCOPE_START_GATE" "$SCOPE_START_READY" \
		"$SCOPE_START_CANCEL" "$SCOPE_START_READY".tmp.* 2>/dev/null || :
	return 0
}

stop_and_reap_direct_child() {
	# Before the child's immutable start time has been captured, $1 is still an
	# unreaped direct child of this shell. The kernel cannot recycle that PID
	# until wait(2), so a numeric signal in this narrow pre-identity path cannot
	# hit an unrelated process.
	SCOPE_DIRECT_CHILD_PID=$1
	[ -n "$SCOPE_DIRECT_CHILD_PID" ] || return 0
	if process_pid_running "$SCOPE_DIRECT_CHILD_PID"; then
		kill -TERM "$SCOPE_DIRECT_CHILD_PID" 2>/dev/null || :
	fi
	SCOPE_DIRECT_CHILD_WAIT=0
	while process_pid_running "$SCOPE_DIRECT_CHILD_PID" && \
		[ "$SCOPE_DIRECT_CHILD_WAIT" -lt 100 ]; do
		SCOPE_DIRECT_CHILD_WAIT=$((SCOPE_DIRECT_CHILD_WAIT + 1))
		usleep 10000
	done
	if process_pid_running "$SCOPE_DIRECT_CHILD_PID"; then
		kill -KILL "$SCOPE_DIRECT_CHILD_PID" 2>/dev/null || :
	fi
	wait "$SCOPE_DIRECT_CHILD_PID" 2>/dev/null || :
	rm -f "$SCOPE_START_GATE" "$SCOPE_START_READY" \
		"$SCOPE_START_CANCEL" "$SCOPE_START_READY".tmp.* 2>/dev/null || :
	return 0
}

scope_start_ready_valid() {
	SCOPE_READY_LINE=
	SCOPE_READY_TRAILING=
	SCOPE_READY_FIRST_OK=0
	SCOPE_READY_EXTRA=0
	[ -s "$SCOPE_START_READY" ] || return 1
	{
		if IFS= read -r SCOPE_READY_LINE; then SCOPE_READY_FIRST_OK=1; fi
		if IFS= read -r SCOPE_READY_TRAILING || \
			[ -n "$SCOPE_READY_TRAILING" ]; then
			SCOPE_READY_EXTRA=1
		fi
	} <"$SCOPE_START_READY"
	[ "$SCOPE_READY_FIRST_OK" -eq 1 ] && \
		[ "$SCOPE_READY_LINE" = ready ] && \
		[ "$SCOPE_READY_EXTRA" -eq 0 ]
}

terminate_scope_until_gone() {
	RECONCILE_CONTEXT=$1
	RECONCILE_WARNING=0
	while ! terminate_scope; do
		if [ "$RECONCILE_WARNING" -eq 0 ]; then
			printf 'Bird content foreground unresolved context=%s; waiting\n' \
				"$RECONCILE_CONTEXT"
			RECONCILE_WARNING=1
		fi
		usleep 250000
	done
	return 0
}

reconcile_registration_failure() {
	REGISTRATION_FAILURE_STATUS=$1
	UNRESOLVED_RUNNER_PID=$SCOPE_RUNNER_PID
	UNRESOLVED_RUNNER_START=$SCOPE_RUNNER_START_TICKS
	session_unlock
	case "$REGISTRATION_FAILURE_STATUS" in
		2) stop_and_reap_scope_runner "$UNRESOLVED_RUNNER_PID" \
			"$UNRESOLVED_RUNNER_START" ;;
		3) wait "$UNRESOLVED_RUNNER_PID" 2>/dev/null || : ;;
		*) return 1 ;;
	esac
	# Foreground ownership remains here until systemd proves this exact scope is
	# inactive/gone and its recovery metadata has been durably removed. The guard
	# exists only for an abrupt runner death, never as an asynchronous handoff.
	terminate_scope_until_gone "registration-$REGISTRATION_FAILURE_STATUS"
	return 1
}

release_owned_resources_until_done() {
	SWAY_RELEASE_WARNING=0
	while [ "$SWAY_OWNED" -eq 1 ]; do
		if ! stop_sway; then
			if [ "$SWAY_RELEASE_WARNING" -eq 0 ]; then
				printf '%s\n' 'Bird Sway ownership unresolved; waiting'
				SWAY_RELEASE_WARNING=1
			fi
			usleep 250000
		fi
	done
	NETWORK_RELEASE_WARNING=0
	while [ "$PORTMASTER_NETWORK" -eq 1 ]; do
		if ! stop_portmaster_network; then
			if [ "$NETWORK_RELEASE_WARNING" -eq 0 ]; then
				printf '%s\n' 'Bird network ownership unresolved; waiting'
				NETWORK_RELEASE_WARNING=1
			fi
			usleep 250000
		fi
	done
	return 0
}

start_scope_runner() {
	# These paths are initialized once with the session token. Keeping them as
	# injected state also lets host fault tests exercise this exact function
	# without touching the device-only /run/bird namespace.
	[ -n "$SCOPE_START_GATE" ] && [ -n "$SCOPE_START_READY" ] && \
		[ -n "$SCOPE_START_CANCEL" ] || return 1
	rm -f "$SCOPE_START_GATE" "$SCOPE_START_READY" \
		"$SCOPE_START_CANCEL" "$SCOPE_START_READY".tmp.* || return 1

	# The bootstrap may not contact systemd until its exact PID/starttime has
	# been committed to the armed crash-recovery lease. If this runner dies in
	# the pre-publication window, the still-gated child observes the exact parent
	# death and exits without ever creating a scope.
	(
		SCOPE_READY_TMP=$SCOPE_START_READY.tmp.$$
		trap 'rm -f "$SCOPE_READY_TMP" 2>/dev/null || :; exit 125' \
			INT TERM HUP
		printf '%s\n' ready >"$SCOPE_READY_TMP" && \
			mv -f "$SCOPE_READY_TMP" "$SCOPE_START_READY" || exit 125
		SCOPE_GATE_WAIT=0
		while [ ! -e "$SCOPE_START_GATE" ] && \
			[ "$SCOPE_GATE_WAIT" -lt 500 ]; do
			[ ! -e "$SCOPE_START_CANCEL" ] || exit 125
			process_identity_alive "$$" "$RUNNER_START_TICKS" || exit 125
			SCOPE_GATE_WAIT=$((SCOPE_GATE_WAIT + 1))
			usleep 10000
		done
		[ -e "$SCOPE_START_GATE" ] || exit 125
		exec /usr/bin/systemd-run --quiet --scope --collect \
			--unit="$SCOPE_UNIT" \
			--description='birdOS foreground content' -- "$@" 8>&- 9>&-
	) &
	SCOPE_RUNNER_PID=$!
	SCOPE_RUNNER_START_TICKS=
	# The READY sentinel proves the child installed its cancellation trap and is
	# blocked behind the gate. Because it remains our unreaped direct child, its
	# $! cannot be recycled while the parent reads and validates starttime.
	SCOPE_START_WAIT=0
	while [ ! -s "$SCOPE_START_READY" ] && \
		process_pid_running "$SCOPE_RUNNER_PID" && \
		[ "$SCOPE_START_WAIT" -lt 100 ]; do
		SCOPE_START_WAIT=$((SCOPE_START_WAIT + 1))
		usleep 10000
	done
	if ! scope_start_ready_valid; then
			: >"$SCOPE_START_CANCEL" 2>/dev/null || :
			stop_and_reap_direct_child "$SCOPE_RUNNER_PID"
			SCOPE_RUNNER_PID=
			SCOPE_RUNNER_START_TICKS=
			return 1
	fi
	SCOPE_RUNNER_START_TICKS=$(process_start_ticks "$SCOPE_RUNNER_PID")
	case "$SCOPE_RUNNER_START_TICKS" in
		''|*[!0-9]*)
			: >"$SCOPE_START_CANCEL" 2>/dev/null || :
			stop_and_reap_direct_child "$SCOPE_RUNNER_PID"
			SCOPE_RUNNER_PID=
			SCOPE_RUNNER_START_TICKS=
			return 1
			;;
	esac
	if ! process_identity_alive "$SCOPE_RUNNER_PID" \
		"$SCOPE_RUNNER_START_TICKS" || ! publish_runner_state 1; then
		stop_and_reap_scope_runner "$SCOPE_RUNNER_PID" \
			"$SCOPE_RUNNER_START_TICKS"
		SCOPE_RUNNER_PID=
		SCOPE_RUNNER_START_TICKS=
		return 1
	fi
	# This is the one-way release edge. Before it exists, a surviving bootstrap
	# can only wait or die; afterward the armed lease identifies it exactly.
	if ! : >"$SCOPE_START_GATE"; then
		stop_and_reap_scope_runner "$SCOPE_RUNNER_PID" \
			"$SCOPE_RUNNER_START_TICKS"
		SCOPE_RUNNER_PID=
		SCOPE_RUNNER_START_TICKS=
		publish_runner_state 1 || :
		return 1
	fi
	return 0
}

run_managed() {
	command -v systemd-run >/dev/null 2>&1 || {
		printf '%s\n' 'Bird content boundary unavailable: systemd-run missing'
		return 1
	}

	rm -f "$SESSION_RECORD" || return 1
	SCOPE_TICK=$(cut -d ' ' -f 1 /proc/uptime | tr -cd '0-9')
	[ -n "$SCOPE_TICK" ] || SCOPE_TICK=0
	SCOPE_UNIT=bird-content-${BOOT_ID}-$$-${SCOPE_TICK}.scope
	SCOPE_INVOCATION=
	SCOPE_CONTROL_GROUP=
	if ! write_scope_metadata starting; then
		discard_unlaunched_metadata || :
		return 1
	fi
	SCOPE_EXPECTED=1
	if ! publish_runner_state 1; then
		SCOPE_EXPECTED=0
		if ! discard_unlaunched_metadata; then
			SCOPE_EXPECTED=1
			publish_runner_state 1 || :
		fi
		return 1
	fi
	# Serialize the pending-to-active handshake with the global control helper.
	# A pending exit removes this session pointer under the same lock; holding it
	# through registration means the helper either cancels before exec or sees the
	# published real InvocationID and terminates that exact scope afterward.
	if ! session_lock; then
		# Keep the strict guard contract intact: the exact pending record lets it
		# confirm that no unit registered and clean up once locking recovers.
		return 1
	fi
	if ! scope_metadata_matches "$SESSION_RECORD" || \
		! scope_metadata_matches "$SESSION_PID"; then
		SCOPE_EXPECTED=0
		if publish_runner_state 1; then
			discard_unlaunched_metadata || :
		else
			SCOPE_EXPECTED=1
		fi
		session_unlock
		return 1
	fi

	# A transient scope is a kernel-enforced cgroup boundary while retaining
	# the provider command's normal parent, environment and terminal contract.
	# Descendants remain in it across forks, reparenting and setsid(2).
	if ! start_scope_runner "$@"; then
		session_unlock
		while ! remove_scope_metadata; do usleep 250000; done
		SCOPE_UNIT=
		SCOPE_INVOCATION=
		SCOPE_CONTROL_GROUP=
		SCOPE_RUNNER_PID=
		SCOPE_RUNNER_START_TICKS=
		return 1
	fi
	while :; do
		wait_for_scope_registration
		REGISTRATION_STATUS=$?
		case "$REGISTRATION_STATUS" in
			0)
				# InvocationID publication proves the bootstrap crossed its gate;
				# these one-shot handshake files no longer carry recovery state.
				rm -f "$SCOPE_START_GATE" "$SCOPE_START_READY" \
					"$SCOPE_START_CANCEL" "$SCOPE_START_READY".tmp.* \
					2>/dev/null || :
				session_unlock
				break
				;;
			1)
				session_unlock
				wait "$SCOPE_RUNNER_PID"
				STATUS=$?
				while ! remove_scope_metadata; do usleep 250000; done
				SCOPE_UNIT=
				SCOPE_INVOCATION=
				SCOPE_CONTROL_GROUP=
				SCOPE_RUNNER_PID=
				return "$STATUS"
				;;
			2)
				printf 'Bird content scope registration query unresolved unit=%s\n' \
					"$SCOPE_UNIT"
				reconcile_registration_failure 2 || :
				return 1
				;;
			3)
				printf 'Bird content scope registration unresolved after provider exit unit=%s\n' \
					"$SCOPE_UNIT"
				reconcile_registration_failure 3 || :
				return 1
				;;
		esac
	done

	printf 'Bird managed application scope=%s invocation=%s\n' \
		"$SCOPE_UNIT" "$SCOPE_INVOCATION"
	wait "$SCOPE_RUNNER_PID"
	STATUS=$?

	# systemd-run follows the provider root. A surviving child keeps the scope
	# active. Joining the already-completed start job is not an inactivity wait,
	# so use exact-state observations and back off to four wakeups per
	# second while retaining exact-identity checks on every observation.
	SCOPE_QUERY_WARNING=0
	SCOPE_POLL_COUNT=0
	while :; do
		scope_activity_status
		ACTIVITY_STATUS=$?
		case "$ACTIVITY_STATUS" in
			0)
				SCOPE_POLL_COUNT=$((SCOPE_POLL_COUNT + 1))
				scope_poll_delay "$SCOPE_POLL_COUNT"
				usleep "$SCOPE_POLL_DELAY_US"
			;;
			1) break ;;
			2)
				if [ "$SCOPE_QUERY_WARNING" -eq 0 ]; then
					printf 'Bird content scope state query unknown unit=%s; retrying\n' \
						"$SCOPE_UNIT"
					SCOPE_QUERY_WARNING=1
				fi
				usleep 250000
				;;
		esac
	done
	while ! remove_scope_metadata; do usleep 250000; done
	SCOPE_UNIT=
	SCOPE_INVOCATION=
	SCOPE_CONTROL_GROUP=
	SCOPE_RUNNER_PID=
	return "$STATUS"
}

rocknix_tuple() {
	case "$HOST_PATH" in
		*/ROMS/A2600/*)      printf '%s %s %s\n' atari2600 retroarch stella ;;
		*/ROMS/ATOMISWAVE/*) printf '%s %s %s\n' atomiswave retroarch flycast2021 ;;
		*/ROMS/CPS1/*)       printf '%s %s %s\n' cps1 retroarch fbneo ;;
		*/ROMS/CPS2/*)       printf '%s %s %s\n' cps2 retroarch fbneo ;;
		*/ROMS/CPS3/*)       printf '%s %s %s\n' cps3 retroarch fbneo ;;
		*/ROMS/DOS/*)        printf '%s %s %s\n' pc retroarch dosbox_pure ;;
		*/ROMS/DREAMCAST/*)  printf '%s %s %s\n' dreamcast retroarch flycast2021 ;;
		*/ROMS/FBNEO/*)      printf '%s %s %s\n' fbneo retroarch fbneo ;;
		*/ROMS/FC/*)         printf '%s %s %s\n' famicom retroarch nestopia ;;
		*/ROMS/GB/*)         printf '%s %s %s\n' gb retroarch gambatte ;;
		*/ROMS/GBA/*)        printf '%s %s %s\n' gba retroarch mgba ;;
		*/ROMS/GBC/*)        printf '%s %s %s\n' gbc retroarch gambatte ;;
		*/ROMS/GG/*)         printf '%s %s %s\n' gamegear retroarch gearsystem ;;
		*/ROMS/GW/*)         printf '%s %s %s\n' gameandwatch retroarch gw ;;
		*/ROMS/HBMAME/*)     printf '%s %s %s\n' arcade retroarch fbneo ;;
		*/ROMS/MAME/*)       printf '%s %s %s\n' mame retroarch mame2003_plus ;;
		*/ROMS/MD/*)         printf '%s %s %s\n' megadrive retroarch genesis_plus_gx ;;
		*/ROMS/MSX/*)        printf '%s %s %s\n' msx retroarch fmsx ;;
		*/ROMS/N64/*)        printf '%s %s %s\n' n64 retroarch mupen64plus_next ;;
		*/ROMS/NAOMI/*)      printf '%s %s %s\n' naomi retroarch flycast2021 ;;
		*/ROMS/NDS/*)        printf '%s %s %s\n' nds drastic drastic-sa ;;
		*/ROMS/OPENBOR/*)    printf '%s %s %s\n' openbor OpenBOR OpenBOR ;;
		*/ROMS/PCE/*)        printf '%s %s %s\n' pcengine retroarch beetle_pce_fast ;;
		*/ROMS/PICO/*)       printf '%s %s %s\n' pico-8 retroarch fake08 ;;
		*/ROMS/PSP/*)        printf '%s %s %s\n' psp ppsspp ppsspp-sa ;;
		*/ROMS/Ports/*)      printf '%s %s %s\n' ports portmaster portmaster ;;
		*/ROMS/SNES/*)       printf '%s %s %s\n' snes retroarch snes9x ;;
		*) return 1 ;;
	esac
}

start_portmaster_network() {
	resource_lock || return 1
	if ! claim_owner "$NETWORK_OWNER"; then
		resource_unlock
		return 1
	fi
	PORTMASTER_NETWORK=1
	if ! publish_runner_state 1; then
		PORTMASTER_NETWORK=0
		remove_owned_token "$NETWORK_OWNER" || :
		resource_unlock
		return 1
	fi
	"$NETWORK" start 8>&- 9>&-
	NETWORK_STATUS=$?
	resource_unlock
	return "$NETWORK_STATUS"
}

stop_portmaster_network() {
	[ "$PORTMASTER_NETWORK" -eq 1 ] || return 0
	resource_lock || return 1
	owner_relation "$NETWORK_OWNER"
	if [ "$OWNER_RELATION" = transferred ]; then
		PORTMASTER_NETWORK=0
		if ! publish_runner_state 1; then
			PORTMASTER_NETWORK=1
			resource_unlock
			return 1
		fi
		resource_unlock
		return 0
	fi
	if [ "$OWNER_RELATION" != ours ]; then
		resource_unlock
		return 1
	fi
	if "$NETWORK" stop 8>&- 9>&-; then
		PORTMASTER_NETWORK=0
		if ! publish_runner_state 1; then
			PORTMASTER_NETWORK=1
			resource_unlock
			return 1
		fi
		if ! remove_owned_token "$NETWORK_OWNER"; then
			PORTMASTER_NETWORK=1
			publish_runner_state 1 || :
			resource_unlock
			return 1
		fi
		resource_unlock
		return 0
	fi
	resource_unlock
	return 1
}

run_selected() {
	if [ "$PORTMASTER_ONLY" -eq 1 ]; then
		"$PORT_PREP" || return 1
		# The start helper can partially configure an interface before returning
		# failure, so cleanup owns a stop attempt from this point onward.
		start_portmaster_network || :
		# PortMaster is English-only on this fixed profile. Disable X11 compose
		# parsing so xkbcommon does not load unrelated legacy encodings.
		run_managed env XCOMPOSEFILE=/dev/null /usr/bin/start_portmaster.sh
		return $?
	fi
	case "$KIND" in
		1|2|4|5)
			read -r PLATFORM EMULATOR CORE < <(rocknix_tuple) || return 1
			[ "$CORE" != fmsx ] || prepare_fmsx_bios || return 1
			run_managed /usr/bin/runemu.sh "$CONTENT" "-P$PLATFORM" \
				"--core=$CORE" "--emulator=$EMULATOR" --controllers=""
			;;
		3)
			"$PORT_PREP" || return 1
			PORT_SCRIPT=/storage/roms/ports/${CONTENT##*/}
			# This one retained Stardew launcher predates the native ROCKNIX
			# PortMaster tree. Translate a volatile copy onto the pinned provider;
			# never rewrite the user's only launcher or its game data.
			if [ "${CONTENT##*/}" = StardewValley.sh ]; then
				mkdir -p /run/bird/ports
				PORT_SCRIPT=/run/bird/ports/StardewValley.sh
				sed \
					-e 's#/mnt/mmc/MUOS/PortMaster#/storage/roms/ports/PortMaster#g' \
					-e 's#/mnt/mmc/ports#/storage/roms/ports#g' \
					-e '/source "$controlfolder\/tasksetter"/d' \
					-e 's#mod_muOS\.txt#mod_ROCKNIX.txt#g' \
					-e 's#libgl_muOS\.txt#libgl_ROCKNIX.txt#g' \
					-e 's#\$TASKSET mono#mono#' \
					"$CONTENT" >"$PORT_SCRIPT" || return 1
				chmod 0755 "$PORT_SCRIPT" || return 1
			fi
			run_managed /usr/bin/runemu.sh "$PORT_SCRIPT" -Pports \
				--core=portmaster --emulator=portmaster --controllers=""
			;;
		6)
			install_mpv_input_policy || return 1
			run_managed /usr/bin/start_mplayer.sh "$CONTENT"
			;;
		*) return 1 ;;
	esac
}

publish_runner_state() {
	ARMED=$1
	[ -n "$RUNNER_STATE" ] || return 0
	TMP=$RUNNER_STATE.tmp.$$
	(
		umask 077
		{
			printf '%s\n' 'version=1'
			printf 'armed=%s\n' "$ARMED"
			printf 'session_token=%s\n' "$SESSION_TOKEN"
			printf 'boot_id=%s\n' "$BOOT_ID_FULL"
			printf 'runner_pid=%s\n' "$$"
			printf 'runner_start_ticks=%s\n' "$RUNNER_START_TICKS"
			printf 'scope_expected=%s\n' "$SCOPE_EXPECTED"
			printf 'scope_unit=%s\n' "$SCOPE_UNIT"
			printf 'scope_invocation=%s\n' "${SCOPE_INVOCATION:-pending}"
			printf 'scope_runner_pid=%s\n' "$SCOPE_RUNNER_PID"
			printf 'scope_runner_start_ticks=%s\n' \
				"$SCOPE_RUNNER_START_TICKS"
			printf 'sway_owned=%s\n' "$SWAY_OWNED"
			printf 'network_owned=%s\n' "$PORTMASTER_NETWORK"
		} >"$TMP" && mv -f "$TMP" "$RUNNER_STATE"
	) || {
		rm -f "$TMP"
		return 1
	}
}

start_cleanup_guard() {
	# A transient service keeps the guard outside the supervisor/runner cgroup;
	# it sleeps in pidfd/ppoll with no periodic wakeups. Direct or service-level
	# runner death wakes the exact pidfd (not a reused numeric PID) to reconcile
	# the validated scope, network and compositor. Start it before publishing the
	# foreground lease: a crash before the service exec owns no resources and
	# needs no lease; after publication, the live guard owns recovery. Normal EXIT
	# disarms first.
	GUARD_UNIT=bird-content-guard-${BOOT_ID}-$$-${RUNNER_START_TICKS}.service
	if ! /usr/bin/systemd-run --quiet --collect --service-type=exec \
		--unit="$GUARD_UNIT" --description='birdOS content cleanup guard' \
		-- /bin/sh -c '
		trap "" HUP
		PIDWAIT=$1
		PARENT=$2
		STATE_FILE=$3
		PARENT_START=$4
		EXPECTED_BOOT=$5
		EXIT_HELPER=$6
		NETWORK_HELPER=$7
		GUARD_LOG=$8
		SESSION_RECORD=$9
		GLOBAL_SESSION=${10}
		SESSION_TOKEN=${11}
		RESOURCE_LOCK=${12}
		SWAY_OWNER=${13}
		NETWORK_OWNER=${14}
		SWAY_SOCKET=${15}
		SCOPE_START_GATE=${16}
		SCOPE_START_READY=${17}
		SCOPE_START_CANCEL=${18}
		PROC_ROOT=${19}
		if ! "$PIDWAIT" "$PARENT"; then
			while [ -r "$PROC_ROOT/$PARENT/stat" ]; do
				PARENT_STAT_RECORD=$(cat "$PROC_ROOT/$PARENT/stat" 2>/dev/null || :)
				case "$PARENT_STAT_RECORD" in
					*") "*) PARENT_STAT_TAIL=${PARENT_STAT_RECORD##*) } ;;
					*) break ;;
				esac
				NOW_START=$(printf "%s\n" "$PARENT_STAT_TAIL" | awk "{print \$20}")
				[ "$NOW_START" = "$PARENT_START" ] || break
				usleep 50000
			done
		fi
		[ -s "$STATE_FILE" ] || exit 0
		value() { sed -n "s/^$1=//p" "$STATE_FILE" | head -n 1; }
		if [ "$(value armed)" != 1 ]; then
			while ! rm -f "$STATE_FILE"; do usleep 250000; done
			exit 0
		fi
		[ "$(value boot_id)" = "$EXPECTED_BOOT" ] || exit 0
		[ "$(value session_token)" = "$SESSION_TOKEN" ] || exit 0
		[ "$(cat "$PROC_ROOT/sys/kernel/random/boot_id" 2>/dev/null || :)" = "$EXPECTED_BOOT" ] || exit 0
		[ "$(value runner_pid)" = "$PARENT" ] || exit 0
		[ "$(value runner_start_ticks)" = "$PARENT_START" ] || exit 0
		SCOPE_EXPECTED_GUARD=$(value scope_expected)
		SCOPE_RUNNER_PID_GUARD=$(value scope_runner_pid)
		SCOPE_RUNNER_START_GUARD=$(value scope_runner_start_ticks)
		SWAY_OWNED_GUARD=$(value sway_owned)
		NETWORK_OWNED_GUARD=$(value network_owned)
		case "$SCOPE_EXPECTED_GUARD:$SWAY_OWNED_GUARD:$NETWORK_OWNED_GUARD" in
			[01]:[01]:[01]) ;;
			*) exit 0 ;;
		esac
		case "$SCOPE_RUNNER_PID_GUARD:$SCOPE_RUNNER_START_GUARD" in
			:) ;;
			*[!0-9:]*) exit 0 ;;
			[0-9]*:[0-9]*) ;;
			*) exit 0 ;;
		esac

		# A gated bootstrap is published before its release edge. Stop that exact
		# process first so it cannot create the pending scope after a not-found
		# observation. pidfd_open pins the task, the helper validates start ticks
		# around that open, and pidfd_send_signal can never hit a reused numeric PID.
		if [ -n "$SCOPE_RUNNER_PID_GUARD" ]; then
			while :; do
				"$PIDWAIT" --terminate "$SCOPE_RUNNER_PID_GUARD" \
					"$SCOPE_RUNNER_START_GUARD"
				SCOPE_RUNNER_STOP_STATUS=$?
				case "$SCOPE_RUNNER_STOP_STATUS" in
					0|5) break ;;
					*) usleep 250000 ;;
				esac
			done
		fi
		rm -f "$SCOPE_START_GATE" "$SCOPE_START_READY" \
			"$SCOPE_START_CANCEL" "$SCOPE_START_READY".tmp.* \
			2>/dev/null || :
		{
			printf "Bird runner guard reconciled pid=%s uptime=" "$PARENT"
			cut -d " " -f 1 /proc/uptime
			if [ "$SCOPE_EXPECTED_GUARD" = 1 ]; then
				for TARGET in "$SESSION_RECORD" "$GLOBAL_SESSION"; do
					EXIT_STATUS=2
					while [ "$EXIT_STATUS" -ne 0 ]; do
					BIRD_SESSION_PID="$TARGET" \
						BIRD_EXPECTED_SESSION_TOKEN="$SESSION_TOKEN" \
						BIRD_REQUIRE_SESSION_RECORD=$([ "$TARGET" = "$SESSION_RECORD" ] && printf 1 || printf 0) \
						BIRD_STABLE_NOT_FOUND_COUNT=$([ "$TARGET" = "$SESSION_RECORD" ] && printf 20 || printf 1) \
							"$EXIT_HELPER" 8>&- 9>&-
						EXIT_STATUS=$?
						[ "$EXIT_STATUS" -eq 0 ] || usleep 250000
					done
				done
			fi

			owner_relation() {
				OWNER_RELATION=unknown
				[ -s "$1" ] || return 0
				IFS= read -r OWNER_TOKEN <"$1" || return 0
				[ -n "$OWNER_TOKEN" ] || return 0
				if [ "$OWNER_TOKEN" = "$SESSION_TOKEN" ]; then
					OWNER_RELATION=ours
				else
					OWNER_RELATION=transferred
				fi
			}
			sway_stopped() {
				[ ! -S "$SWAY_SOCKET" ] || return 1
				ACTIVE=$(systemctl show --property=ActiveState --value sway.service \
					8>&- 9>&- 2>/dev/null) || return 1
				[ "$ACTIVE" = inactive ] && return 0
				[ -z "$ACTIVE" ] || return 1
				LOAD=$(systemctl show --property=LoadState --value sway.service \
					8>&- 9>&- 2>/dev/null) || return 1
				[ "$LOAD" = not-found ]
			}
			while :; do
				RESOURCE_STATUS=0
				if ! exec 9>"$RESOURCE_LOCK" || ! flock -x 9; then
					RESOURCE_STATUS=1
				else
					if [ "$NETWORK_OWNED_GUARD" = 1 ]; then
						owner_relation "$NETWORK_OWNER"
						case "$OWNER_RELATION" in
							transferred) NETWORK_OWNED_GUARD=0 ;;
							ours)
								if ! "$NETWORK_HELPER" stop 8>&- 9>&- || \
									! rm -f "$NETWORK_OWNER"; then
									RESOURCE_STATUS=1
								else
									NETWORK_OWNED_GUARD=0
								fi
								;;
							*) RESOURCE_STATUS=1 ;;
						esac
					fi
					if [ "$SWAY_OWNED_GUARD" = 1 ]; then
						owner_relation "$SWAY_OWNER"
						case "$OWNER_RELATION" in
							transferred) SWAY_OWNED_GUARD=0 ;;
							ours)
								systemctl stop sway.service 8>&- 9>&- || :
								COUNT=0
								while ! sway_stopped && [ "$COUNT" -lt 100 ]; do
									COUNT=$((COUNT + 1))
									usleep 20000
								done
								if ! sway_stopped; then
									systemctl kill --kill-whom=all --signal=KILL \
										sway.service 8>&- 9>&- 2>/dev/null || :
									systemctl stop sway.service 8>&- 9>&- 2>/dev/null || :
								fi
								if ! sway_stopped || ! rm -f "$SWAY_OWNER"; then
									RESOURCE_STATUS=1
								else
									SWAY_OWNED_GUARD=0
								fi
								;;
							*) RESOURCE_STATUS=1 ;;
						esac
					fi
					flock -u 9 || RESOURCE_STATUS=1
				fi
				exec 9>&-
				[ "$RESOURCE_STATUS" -eq 0 ] && break
				usleep 250000
			done
		} >>"$GUARD_LOG" 2>&1
		while ! rm -f "$STATE_FILE"; do usleep 250000; done
	' bird-content-guard /storage/.config/bird/bird-pidwait "$$" \
		"$RUNNER_STATE" "$RUNNER_START_TICKS" "$BOOT_ID_FULL" \
		/storage/.config/bird/bird-fixed-control-exit.sh "$NETWORK" \
		"$SESSION_LOG" "$SESSION_RECORD" "$SESSION_PID" "$SESSION_TOKEN" \
		"$RESOURCE_LOCK" "$SWAY_OWNER" "$NETWORK_OWNER" "$SWAY_SOCKET" \
		"$SCOPE_START_GATE" "$SCOPE_START_READY" "$SCOPE_START_CANCEL" /proc \
		8>&- 9>&- </dev/null >/dev/null 2>&1; then
		rm -f "$RUNNER_STATE" 2>/dev/null || :
		return 1
	fi
	GUARD_STARTED=1
	# service-type=exec returns only after the guard has execed. No Sway, network
	# or content scope is allowed to start until this atomic armed state exists.
	publish_runner_state 1 || return 1
	return 0
}

cleanup_runtime() {
	case "$CLEANUP_STATE" in
		succeeded) return 0 ;;
		running|failed) return 1 ;;
	esac
	CLEANUP_STATE=running
	# Once foreground reconciliation begins, ordinary signals cannot turn it
	# into an asynchronous handoff. SIGKILL still activates the external guard.
	trap '' INT TERM HUP
	if [ -n "$SCOPE_RUNNER_PID" ]; then
		stop_and_reap_scope_runner "$SCOPE_RUNNER_PID" \
			"$SCOPE_RUNNER_START_TICKS"
	fi
	terminate_scope_until_gone cleanup
	release_owned_resources_until_done
	CLEANUP_STATE=succeeded
	return 0
}

cleanup_on_exit() {
	EXIT_STATUS=$?
	trap - EXIT
	trap '' INT TERM HUP
	if [ "$GUARD_STARTED" -eq 0 ]; then
		cleanup_runtime || :
		rm -f "$RUNNER_STATE" 2>/dev/null || :
	elif cleanup_runtime; then
		# Publish disarm before removing the foreground lease. If either operation
		# fails, leave the state for the guard; if SIGKILL lands between them, the
		# guard observes armed=0 and removes the already-clean lease itself.
		if publish_runner_state 0; then
			rm -f "$RUNNER_STATE" 2>/dev/null || :
		fi
	else
		# Keep the external guard armed after the exact runner pidfd reports death.
		publish_runner_state 1 || :
	fi
	[ -f "$SESSION_LOG" ] && cp -f "$SESSION_LOG" "$LOG" 2>/dev/null || :
	exit "$EXIT_STATUS"
}

signal_exit() {
	SIGNAL_STATUS=$1
	exit "$SIGNAL_STATUS"
}

trap cleanup_on_exit EXIT
trap 'signal_exit 130' INT
trap 'signal_exit 143' TERM
trap 'signal_exit 129' HUP

STATUS=0
START_FAILURE_REASON=
if ! start_cleanup_guard; then
	START_FAILURE_REASON='runner cleanup guard unavailable'
	STATUS=1
fi

{
	printf 'Bird ROCKNIX session start uptime='
	cut -d ' ' -f 1 /proc/uptime
	[ -z "$START_FAILURE_REASON" ] || \
		printf 'Bird content refused: %s\n' "$START_FAILURE_REASON"
	if [ "$PORTMASTER_ONLY" -eq 0 ]; then
		printf 'kind=%s core=%s name=%s host=%s content=%s\n' \
			"$KIND" "$REQUESTED_CORE" "$NAME" "$HOST_PATH" "$CONTENT"
	fi
	# An initramfs selection can start this runner before the persistent profile
	# writers finish. Reload only after the revisioned marker has validated their
	# exact outputs; otherwise this shell retains stale DEVICE_*/Sway values.
	if [ "$STATUS" -eq 0 ] && wait_application_contract && . /etc/profile; then
		printf 'Bird application contract ready revision=%s uptime=' \
			"$APPLICATION_CONTRACT_REVISION"
		cut -d ' ' -f 1 /proc/uptime
		if [ "$PORTMASTER_ONLY" -eq 0 ] && ! rm -f "$REQUEST"; then
			STATUS=1
		fi
		if [ "$STATUS" -eq 0 ] && start_sway; then
			ensure_content_services || STATUS=1
			: >/var/log/exec.log
			if [ "${STATUS:-0}" -eq 0 ]; then
				run_selected
				STATUS=$?
			fi
			if [ -s /var/log/exec.log ]; then
				printf '%s\n' '--- ROCKNIX application log (last 256 KiB) ---'
				tail -c 262144 /var/log/exec.log
				printf '%s\n' '--- end ROCKNIX application log ---'
			fi
		else
			STATUS=1
		fi
	else
		STATUS=1
	fi
	cleanup_runtime || STATUS=1
	printf 'Bird ROCKNIX session result=%s uptime=' "$STATUS"
	cut -d ' ' -f 1 /proc/uptime
} >"$SESSION_LOG" 2>&1

cp -f "$SESSION_LOG" "$LOG" || :
exit "$STATUS"
