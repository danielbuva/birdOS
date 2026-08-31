#!/bin/bash
# Route Bird selections through the exact ROCKNIX 20260701 application
# contract. No chroot, copied library set, hand-written device metadata or
# substitute audio stack exists in this path.

set -u

CATALOG_PATH_MAX_BYTES=4095
APPLICATION_CONTRACT_REVISION=bird-application-v1
APPLICATION_READY=${BIRD_APPLICATION_READY:-/run/bird/application-contract-ready}
SYSTEMCTL_PROGRAM=${BIRD_SYSTEMCTL_PROGRAM:-$(command -v systemctl)}
TIMEOUT_PROGRAM=${BIRD_TIMEOUT_PROGRAM:-$(command -v timeout)}
NETWORK_DIRECT_BOUND=90s
NETWORK_DIRECT_HARD_BOUND=91s
NETWORK_STOP_BOUND=12s
NETWORK_STOP_HARD_BOUND=13s

read_uptime() {
	BIRD_UPTIME_PATH=${BIRD_UPTIME_PATH:-/proc/uptime}
	if [ ! -r "$BIRD_UPTIME_PATH" ] || \
		! IFS=' ' read -r BIRD_UPTIME_VALUE _ <"$BIRD_UPTIME_PATH"; then
		BIRD_UPTIME_VALUE=unknown
	fi
}

uptime_now() {
	read_uptime
	printf '%s\n' "$BIRD_UPTIME_VALUE"
}

classify_exit_status() {
	case "$1" in
		0) BIRD_EXIT_CLASS=success ;;
		129|1[3-8][0-9]|19[0-2])
			BIRD_EXIT_SIGNAL=$(($1 - 128))
			case "$BIRD_EXIT_SIGNAL" in
				9) BIRD_EXIT_CLASS=sigkill ;;
				15) BIRD_EXIT_CLASS=sigterm ;;
				*) BIRD_EXIT_CLASS=signal-$BIRD_EXIT_SIGNAL ;;
			esac
			;;
		*) BIRD_EXIT_CLASS=exit-$1 ;;
	esac
}

# A wedged systemd client must never strand the launcher off-screen. Callers
# retain their existing exact state checks; a timeout is an unknown/failure,
# never proof that a resource stopped.
systemctl() {
	"$TIMEOUT_PROGRAM" --signal=TERM --kill-after=1s 3s \
		"$SYSTEMCTL_PROGRAM" "$@"
}

content_stage() {
	printf 'Bird content stage=%s uptime=' "$1"
	uptime_now
}

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
	# C-locale shell length is the exact byte count. Keep validation in this
	# process instead of forking wc, tr and grep before every provider handoff.
	local LC_ALL=C
	HOST_PATH_BYTES=${#HOST_PATH}
	case "$HOST_PATH" in
		*[[:cntrl:]]*) HOST_PATH_CONTROL=1 ;;
		*) HOST_PATH_CONTROL=0 ;;
	esac
	if [ "$EXTRA_LINE" -ne 0 ] || \
		[ "$HOST_PATH_BYTES" -gt "$CATALOG_PATH_MAX_BYTES" ] || \
		[ "$HOST_PATH_CONTROL" -ne 0 ]; then
		PATH_REJECTION="malformed ($HOST_PATH_BYTES bytes)"
		return 1
	fi
	case "$HOST_PATH" in
		*/../*|*/..|../*|..) PATH_REJECTION=traversal; return 1 ;;
		/storage/roms/*|/storage/media/*) return 0 ;;
		*) PATH_REJECTION=prefix; return 1 ;;
	esac
}

if [ "${BIRD_TEST_VALIDATE_HOST_PATH:-0}" = 1 ]; then
	HOST_PATH=${BIRD_TEST_HOST_PATH:-}
	if validate_host_path "${BIRD_TEST_EXTRA_LINE:-0}"; then exit 0; fi
	exit 1
fi

REQUEST=${1:-/run/bird/bird-launch-request}
LOG_DIR=/storage/bird-data/Bird/log
LOG=$LOG_DIR/stock-root-content-latest.log
SWAY_SOCKET=/var/run/0-runtime-dir/sway-ipc.0.sock
SESSION_MODE=content
PORT_PREP=/flash/bird/prepare-ports.sh
NETWORK=/flash/bird/bird-network.sh
MPV_PLAYER=${BIRD_MPV_PLAYER:-/flash/bird/bird-mpv-player.sh}
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
CLEANUP_MODE=foreground
RUNNER_STATE=
RUNNER_START_TICKS=
GUARD_UNIT=
GUARD_STARTED=0
SESSION_TOKEN=
SESSION_RECORD=
SWAY_LOCK=/run/bird/sway-resource.lock
NETWORK_LOCK=/run/bird/network-resource.lock
RESOURCE_LOCK_HELD=0
RESOURCE_LOCK_PATH=
SESSION_LOCK=/run/bird/content-session.lock
SESSION_LOCK_HELD=0
SWAY_OWNER=/run/bird/sway-owner
NETWORK_OWNER=/run/bird/network-owner
SCOPE_QUERY_RESULT=unknown
SCOPE_QUERY_VALUE=
PROCESS_PROC_ROOT=${BIRD_PROCESS_PROC_ROOT:-/proc}
KOREADER_PORT_SOURCE=${BIRD_KOREADER_PORT_SOURCE:-/storage/roms/ports/KOReader.sh}
KOREADER_PORT_SOURCE_SHA=af3f0850da81d5c3777588e597803195384d82eb3b298bab611d19aa0fb423b5
KOREADER_ARCHIVE_SHA=be706d106d80063ec7471249011da6ee483ac18b77adb8d61571f272c88d3a57
KOREADER_ARCHIVE_BYTES=43069001
KOREADER_EXPANDED_BYTES=108544222
KOREADER_ARCHIVE_ENTRIES=1139
KOREADER_SHA256_PROGRAM=${BIRD_KOREADER_SHA256_PROGRAM:-/usr/bin/sha256sum}
KOREADER_EXTRACTION_STATE_DIR=/storage/bird-data/Bird/state/koreader-extraction
KOREADER_PORT_SCRIPT=
KOREADER_PORT_TEMP=

initial_process_start_ticks() {
	[ -r "$1" ] || return 1
	IFS= read -r PROCESS_STAT_RECORD <"$1" || return 1
	case "$PROCESS_STAT_RECORD" in
		*") "*) PROCESS_STAT_TAIL=${PROCESS_STAT_RECORD##*) } ;;
		*) return 1 ;;
	esac
	set -- $PROCESS_STAT_TAIL
	[ "$#" -ge 20 ] || return 1
	printf '%s\n' "${20}"
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
	CONTENT=$HOST_PATH
	return 0
}

select_session_mode() {
	case "$REQUEST" in
		--portmaster) SESSION_MODE=portmaster ;;
		*) SESSION_MODE=content ;;
	esac
}

if [ "${BIRD_TEST_SESSION_MODE:-0}" = 1 ]; then
	REQUEST=${BIRD_TEST_SESSION_REQUEST:-}
	select_session_mode
	printf '%s\n' "$SESSION_MODE"
	exit 0
fi

if [ "${BIRD_TEST_PARSE_LAUNCH_REQUEST:-0}" = 1 ]; then
	REQUEST=${BIRD_TEST_REQUEST_PATH:-}
	load_launch_request
	exit $?
fi

mkdir -p "$LOG_DIR" /run/bird "$SESSION_DIR"

select_session_mode
if [ "$SESSION_MODE" = content ]; then
	if ! load_launch_request; then
		printf 'Rejected Bird content path (%s): %s\n' \
			"$PATH_REJECTION" "$HOST_PATH" >"$LOG"
		exit 1
	fi
fi

IFS= read -r BOOT_ID_FULL </proc/sys/kernel/random/boot_id || BOOT_ID_FULL=unknown
BOOT_ID=${BOOT_ID_FULL:0:8}
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
KOREADER_PORT_SCRIPT=/run/bird/ports/KOReader-$SESSION_TOKEN.sh
KOREADER_PORT_TEMP=$KOREADER_PORT_SCRIPT.tmp
read_uptime
SESSION_TICK=${BIRD_UPTIME_VALUE/./}
case "$SESSION_MODE" in
	content) SESSION_KIND=kind$KIND ;;
	portmaster) SESSION_KIND=portmaster ;;
esac
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
	RESOURCE_LOCK_REQUEST=$1
	if [ "$RESOURCE_LOCK_HELD" -eq 1 ]; then
		[ "$RESOURCE_LOCK_PATH" = "$RESOURCE_LOCK_REQUEST" ]
		return $?
	fi
	RESOURCE_LOCK_PATH=$RESOURCE_LOCK_REQUEST
	exec 9>"$RESOURCE_LOCK_PATH" || return 1
	flock -x 9 || { exec 9>&-; return 1; }
	RESOURCE_LOCK_HELD=1
}

sway_lock() {
	resource_lock "$SWAY_LOCK"
}

network_lock() {
	resource_lock "$NETWORK_LOCK"
}

resource_unlock() {
	[ "$RESOURCE_LOCK_HELD" -eq 1 ] || return 0
	flock -u 9 2>/dev/null || :
	exec 9>&-
	RESOURCE_LOCK_HELD=0
	RESOURCE_LOCK_PATH=
}

owner_matches() {
	OWNER_FILE=$1
	[ -s "$OWNER_FILE" ] || return 1
	IFS= read -r OWNER_TOKEN <"$OWNER_FILE" || return 1
	[ "$OWNER_TOKEN" = "$SESSION_TOKEN" ]
}

owner_relation() {
	OWNER_RELATION=unknown
	OWNER_TOKEN=
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

rollback_sway_start() {
	if ! stop_sway; then
		printf '%s\n' 'Bird Sway startup rollback unresolved; cleanup retained'
	fi
	return 1
}

start_sway() {
	# graphical.target normally owns seatd, but an early queued selection can
	# reach this path while that target is still starting. Join the fixed seat
	# provider before publishing compositor ownership.
	if ! systemctl start seatd.service 8>&- 9>&-; then
		printf '%s\n' 'Bird Sway start failed stage=seatd'
		return 1
	fi
	content_stage sway-owner-claim
	sway_lock || return 1
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
	if ! systemctl start --no-block sway.service 8>&- 9>&-; then
		resource_unlock
		printf '%s\n' 'Bird Sway start failed stage=service'
		rollback_sway_start
		return 1
	fi
	resource_unlock
	for _ in $(seq 1 200); do
		if [ -S "$SWAY_SOCKET" ]; then
			content_stage sway-ready
			return 0
		fi
		usleep 25000
	done
	printf '%s\n' 'Bird Sway start failed stage=socket-timeout'
	rollback_sway_start
	return 1
}

ensure_content_services() {
	# Bird can be selected before the background compatibility graph completes.
	# Join only the services every proven application session actually needs.
	# D-Bus is a completed barrier: the pinned audio units do not express that
	# ordering themselves, so merging these transactions is not equivalent.
	systemctl start dbus.service 8>&- 9>&- || return 1
	systemctl start pipewire.service wireplumber.service \
		pipewire-pulse.service 8>&- 9>&- || return 1
	# The writable ROCKNIX image can persist a muted internal route even while
	# every audio service, app stream and ALSA control looks healthy. Reapply the
	# saved Bird volume and explicitly clear that route mute before every app.
	"$TIMEOUT_PROGRAM" --signal=TERM --kill-after=1s 3s \
		/flash/bird/bird-volume.sh restore \
		8>&- 9>&- || return 1
	content_stage services-ready
}

stop_sway() {
	[ "$SWAY_OWNED" -eq 1 ] || return 0
	sway_lock || return 1
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
	content_stage sway-stop-request
	systemctl stop --no-block sway.service 8>&- 9>&- || :
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
	systemctl stop --no-block sway.service 8>&- 9>&- 2>/dev/null || :
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
	RESUME_OPTIONS='watch-later-options=start'
	RESUME_MIGRATION=/storage/.config/mpv/.bird-watch-later-start-only-v1
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
	# MPV's default watch-later set includes changed track selections.  A saved
	# aid=no makes a later audio-only launch exit with "No video or audio streams
	# selected".  Preserve resume position, but never persist player-local track,
	# volume, mute, or speed choices as part of Bird's system media contract.
	if ! grep -Eq \
		'^[[:space:]]*watch-later-options[[:space:]]*=[[:space:]]*start[[:space:]]*$' \
		"$CONFIG"; then
		printf '\n# birdOS: resume position only; system controls own audio policy\n%s\n' \
			"$RESUME_OPTIONS" >>"$CONFIG" || return 1
		printf 'Bird MPV position-only resume policy installed\n'
	fi
	if [ ! -e "$RESUME_MIGRATION" ]; then
		for WATCH_DIR in /storage/.config/mpv/watch_later \
			/storage/.local/state/mpv/watch_later; do
			[ -d "$WATCH_DIR" ] || continue
			for WATCH_STATE in "$WATCH_DIR"/*; do
				[ -f "$WATCH_STATE" ] || continue
				WATCH_TMP=$WATCH_STATE.bird.$$
				if ! awk '/^#/ || /^start=/' "$WATCH_STATE" >"$WATCH_TMP" ||
					! chmod 0600 "$WATCH_TMP" ||
					! mv -f "$WATCH_TMP" "$WATCH_STATE"; then
					rm -f "$WATCH_TMP"
					return 1
				fi
			done
		done
		: >"$RESUME_MIGRATION" || return 1
		printf 'Bird MPV legacy resume state sanitized\n'
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
		not-found:*|present:inactive|present:failed) return 0 ;;
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
	RECORDED_TOKEN=
	RECORDED_UNIT=
	RECORDED_INVOCATION=
	METADATA_TOKEN_FOUND=0
	METADATA_UNIT_FOUND=0
	METADATA_INVOCATION_FOUND=0
	while IFS= read -r METADATA_LINE || [ -n "$METADATA_LINE" ]; do
		case "$METADATA_LINE" in
			session_token=*)
				if [ "$METADATA_TOKEN_FOUND" -eq 0 ]; then
					RECORDED_TOKEN=${METADATA_LINE#session_token=}
					METADATA_TOKEN_FOUND=1
				fi
				;;
			unit=*)
				if [ "$METADATA_UNIT_FOUND" -eq 0 ]; then
					RECORDED_UNIT=${METADATA_LINE#unit=}
					METADATA_UNIT_FOUND=1
				fi
				;;
			invocation_id=*)
				if [ "$METADATA_INVOCATION_FOUND" -eq 0 ]; then
					RECORDED_INVOCATION=${METADATA_LINE#invocation_id=}
					METADATA_INVOCATION_FOUND=1
				fi
				;;
		esac
	done <"$METADATA_FILE"
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
			SCOPE_RUNNER_START_TICKS=
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
	IFS= read -r PROCESS_STAT_RECORD \
		<"$PROCESS_PROC_ROOT/$1/stat" || return 1
	case "$PROCESS_STAT_RECORD" in
		*") "*) PROCESS_STAT_TAIL=${PROCESS_STAT_RECORD##*) } ;;
		*) return 1 ;;
	esac
	[ -n "$PROCESS_STAT_TAIL" ]
}

process_start_ticks() {
	process_stat_tail "$1" || return 1
	set -- $PROCESS_STAT_TAIL
	[ "$#" -ge 20 ] || return 1
	printf '%s\n' "${20}"
}

process_pid_running() {
	process_stat_tail "$1" || return 1
	PROCESS_PID_STATE=${PROCESS_STAT_TAIL%% *}
	[ -n "$PROCESS_PID_STATE" ] && [ "$PROCESS_PID_STATE" != Z ]
}

process_identity_alive() {
	IDENTITY_PID=$1
	IDENTITY_START_TICKS=$2
	case "$IDENTITY_PID:$IDENTITY_START_TICKS" in
		*[!0-9:]*|:*) return 1 ;;
	esac
	process_stat_tail "$IDENTITY_PID" || return 1
	IDENTITY_STATE=${PROCESS_STAT_TAIL%% *}
	set -- $PROCESS_STAT_TAIL
	[ "$#" -ge 20 ] || return 1
	IDENTITY_CURRENT_START=${20}
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

release_network_until_done() {
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
}

release_sway_until_done() {
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
}

release_owned_resources_until_done() {
	# The synchronous fallback keeps Sway scanout present until variable network
	# teardown has converged. Normal PortMaster return uses the explicit
	# background-network handoff after releasing Sway below.
	release_network_until_done
	release_sway_until_done
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
			--expand-environment=no \
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
	read_uptime
	SCOPE_TICK=${BIRD_UPTIME_VALUE/./}
	case "$SCOPE_TICK" in *[!0-9]*) SCOPE_TICK=0 ;; esac
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
				SCOPE_RUNNER_START_TICKS=
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
	classify_exit_status "$STATUS"
	printf 'Bird managed scope return status=%s class=%s uptime=' \
		"$STATUS" "$BIRD_EXIT_CLASS"
	uptime_now

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
	SCOPE_RUNNER_START_TICKS=
	return "$STATUS"
}

rocknix_tuple() {
	case "$HOST_PATH" in
		/storage/roms/A2600/*)      printf '%s %s %s\n' atari2600 retroarch stella ;;
		/storage/roms/ATOMISWAVE/*) printf '%s %s %s\n' atomiswave retroarch flycast2021 ;;
		/storage/roms/CPS1/*)       printf '%s %s %s\n' cps1 retroarch fbneo ;;
		/storage/roms/CPS2/*)       printf '%s %s %s\n' cps2 retroarch fbneo ;;
		/storage/roms/CPS3/*)       printf '%s %s %s\n' cps3 retroarch fbneo ;;
		/storage/roms/DOS/*)        printf '%s %s %s\n' pc retroarch dosbox_pure ;;
		/storage/roms/DREAMCAST/*)  printf '%s %s %s\n' dreamcast retroarch flycast2021 ;;
		/storage/roms/FBNEO/*)      printf '%s %s %s\n' fbneo retroarch fbneo ;;
		/storage/roms/FC/*)         printf '%s %s %s\n' famicom retroarch nestopia ;;
		/storage/roms/GB/*)         printf '%s %s %s\n' gb retroarch gambatte ;;
		/storage/roms/GBA/*)        printf '%s %s %s\n' gba retroarch mgba ;;
		/storage/roms/GBC/*)        printf '%s %s %s\n' gbc retroarch gambatte ;;
		/storage/roms/GG/*)         printf '%s %s %s\n' gamegear retroarch gearsystem ;;
		/storage/roms/GW/*)         printf '%s %s %s\n' gameandwatch retroarch gw ;;
		/storage/roms/HBMAME/*)     printf '%s %s %s\n' arcade retroarch fbneo ;;
		/storage/roms/MAME/*)       printf '%s %s %s\n' mame retroarch mame2003_plus ;;
		/storage/roms/MD/*)         printf '%s %s %s\n' megadrive retroarch genesis_plus_gx ;;
		/storage/roms/MSX/*)        printf '%s %s %s\n' msx retroarch fmsx ;;
		/storage/roms/N64/*)        printf '%s %s %s\n' n64 retroarch mupen64plus_next ;;
		/storage/roms/NAOMI/*)      printf '%s %s %s\n' naomi retroarch flycast2021 ;;
		/storage/roms/NDS/*)        printf '%s %s %s\n' nds drastic drastic-sa ;;
		/storage/roms/OPENBOR/*)    printf '%s %s %s\n' openbor OpenBOR OpenBOR ;;
		/storage/roms/PCE/*)        printf '%s %s %s\n' pcengine retroarch beetle_pce_fast ;;
		/storage/roms/PICO/*)       printf '%s %s %s\n' pico-8 retroarch fake08 ;;
		/storage/roms/PSP/*)        printf '%s %s %s\n' psp ppsspp ppsspp-sa ;;
		/storage/roms/Ports/*)      printf '%s %s %s\n' ports portmaster portmaster ;;
		/storage/roms/SNES/*)       printf '%s %s %s\n' snes retroarch snes9x ;;
		*) return 1 ;;
	esac
}

run_network_helper() {
	NETWORK_HELPER_MODE=$1
	case "$NETWORK_HELPER_MODE" in
		start)
			NETWORK_HELPER_BOUND=$NETWORK_DIRECT_BOUND
			NETWORK_HELPER_HARD_BOUND=$NETWORK_DIRECT_HARD_BOUND
			;;
		stop)
			NETWORK_HELPER_BOUND=$NETWORK_STOP_BOUND
			NETWORK_HELPER_HARD_BOUND=$NETWORK_STOP_HARD_BOUND
			;;
		*) return 2 ;;
	esac
	# The helper subtree inherits fd9 so a killed owner cannot release the
	# network lock while its bounded destructive transaction is still running.
	"$TIMEOUT_PROGRAM" --signal=TERM --kill-after=1s \
		"$NETWORK_HELPER_BOUND" "$NETWORK" "$NETWORK_HELPER_MODE" 8>&-
}

start_portmaster_network() {
	NETWORK_START_MODE=${1:-start}
	printf 'Bird portmaster network start begin uptime='
	uptime_now
	if [ -e /run/bird/network-request ]; then
		printf '%s\n' 'Bird network request flag present before start'
	else
		printf '%s\n' 'Bird network request flag absent before start'
	fi
	if [ -s "$NETWORK_OWNER" ]; then
		owner_relation "$NETWORK_OWNER" || :
		printf 'Bird portmaster network owner relation=%s token=%s\n' \
			"$OWNER_RELATION" "$OWNER_TOKEN"
	else
		printf '%s\n' 'Bird portmaster network owner relation=none token=none'
	fi
	NETWORK_OWNER_WAIT=0
	while :; do
		network_lock || return 1
		if [ -e "$NETWORK_OWNER" ] || [ -L "$NETWORK_OWNER" ]; then
			owner_relation "$NETWORK_OWNER"
			case "$OWNER_RELATION" in
				ours) break ;;
				transferred)
					resource_unlock
					NETWORK_OWNER_WAIT=$((NETWORK_OWNER_WAIT + 1))
					if [ "$NETWORK_OWNER_WAIT" -ge 60 ]; then
						printf '%s\n' \
							'Bird portmaster network start aborted: prior cleanup unresolved'
						return 1
					fi
					usleep 250000
					continue
					;;
				*)
					printf '%s\n' \
						'Bird portmaster network start aborted: malformed owner'
					resource_unlock
					return 1
					;;
			esac
		fi
		break
	done
	if ! claim_owner "$NETWORK_OWNER"; then
		printf '%s\n' 'Bird portmaster network start aborted: no owner token'
		resource_unlock
		return 1
	fi
	PORTMASTER_NETWORK=1
	if ! publish_runner_state 1; then
		printf '%s\n' 'Bird portmaster network start aborted: publish runner state failed'
		PORTMASTER_NETWORK=0
		remove_owned_token "$NETWORK_OWNER" || :
		resource_unlock
		return 1
	fi
	NETWORK_STATUS=0
	run_network_helper "$NETWORK_START_MODE" || NETWORK_STATUS=$?
	resource_unlock
	if [ -e /run/bird/network-request ]; then
		printf '%s\n' 'Bird network request flag present after start'
	else
		printf '%s\n' 'Bird network request flag absent after start'
	fi
	if [ -s "$NETWORK_OWNER" ]; then
		owner_relation "$NETWORK_OWNER" || :
		printf 'Bird portmaster network owner relation=%s token=%s\n' \
			"$OWNER_RELATION" "$OWNER_TOKEN"
	else
		printf '%s\n' 'Bird portmaster network owner relation=none token=none'
	fi
	printf 'Bird portmaster network start mode=%s helper_status=%s hard_bound=%s uptime=' \
		"$NETWORK_START_MODE" "$NETWORK_STATUS" "$NETWORK_HELPER_HARD_BOUND"
	uptime_now
	return "$NETWORK_STATUS"
}

stop_portmaster_network() {
	printf 'Bird portmaster network stop begin uptime='
	uptime_now
	if [ -e /run/bird/network-request ]; then
		printf '%s\n' 'Bird network request flag present before stop'
	else
		printf '%s\n' 'Bird network request flag absent before stop'
	fi
	if [ -s "$NETWORK_OWNER" ]; then
		owner_relation "$NETWORK_OWNER" || :
		printf 'Bird portmaster network owner relation=%s token=%s\n' \
			"$OWNER_RELATION" "$OWNER_TOKEN"
	else
		printf '%s\n' 'Bird portmaster network owner relation=none token=none'
	fi
	[ "$PORTMASTER_NETWORK" -eq 1 ] || return 0
	network_lock || return 1
	owner_relation "$NETWORK_OWNER"
	if [ "$OWNER_RELATION" = transferred ]; then
		printf '%s\n' 'Bird portmaster network stop transfer: already owned by replacement'
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
		printf '%s\n' 'Bird portmaster network stop aborted: stale ownership'
		resource_unlock
		return 1
	fi
	NETWORK_STOP_STATUS=0
	run_network_helper stop || NETWORK_STOP_STATUS=$?
	if [ "$NETWORK_STOP_STATUS" -eq 0 ]; then
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
		if [ -e /run/bird/network-request ]; then
			printf '%s\n' 'Bird network request flag present after stop'
		else
			printf '%s\n' 'Bird network request flag absent after stop'
		fi
		if [ -s "$NETWORK_OWNER" ]; then
			owner_relation "$NETWORK_OWNER" || :
			printf 'Bird portmaster network owner token=%s\n' \
				"$OWNER_TOKEN"
		else
			printf '%s\n' 'Bird portmaster network owner relation=none token=none'
		fi
		resource_unlock
		printf '%s\n' 'Bird portmaster network stop status=ok'
		return 0
	fi
	resource_unlock
	printf 'Bird portmaster network stop status=%s\n' "$NETWORK_STOP_STATUS"
	return "$NETWORK_STOP_STATUS"
}

remove_koreader_port_script() {
	KOREADER_REMOVE_STATUS=0
	if [ -n "$KOREADER_PORT_TEMP" ] &&
		! rm -f "$KOREADER_PORT_TEMP"; then
		KOREADER_REMOVE_STATUS=1
	fi
	if [ -n "$KOREADER_PORT_SCRIPT" ] &&
		! rm -f "$KOREADER_PORT_SCRIPT"; then
		KOREADER_REMOVE_STATUS=1
	fi
	return "$KOREADER_REMOVE_STATUS"
}

prepare_koreader_port_script() {
	[ -n "$KOREADER_PORT_SCRIPT" ] && [ -n "$KOREADER_PORT_TEMP" ] ||
		return 1
	[ -f "$KOREADER_PORT_SOURCE" ] && [ ! -L "$KOREADER_PORT_SOURCE" ] ||
		return 1
	[ -x "$KOREADER_SHA256_PROGRAM" ] || return 1
	[ -n "$KOREADER_ARCHIVE_SHA" ] &&
		[ -n "$KOREADER_EXTRACTION_STATE_DIR" ] || return 1
	KOREADER_SOURCE_DIGEST_LINE=$(
		"$KOREADER_SHA256_PROGRAM" "$KOREADER_PORT_SOURCE" 2>/dev/null
	) || return 1
	KOREADER_SOURCE_DIGEST=${KOREADER_SOURCE_DIGEST_LINE%% *}
	[ "$KOREADER_SOURCE_DIGEST" = "$KOREADER_PORT_SOURCE_SHA" ] || return 1
	mkdir -p "${KOREADER_PORT_SCRIPT%/*}" || return 1
	remove_koreader_port_script || return 1

	# Keep the downloaded PortMaster launcher and archive immutable. The
	# session-local copy changes exactly two audited regions: interrupted first
	# extraction becomes restartable, and reader.lua receives the selected
	# catalog path instead of opening the generic books directory. Any upstream
	# structural change fails closed before the temporary script is published.
	if ! awk -v archive_sha="$KOREADER_ARCHIVE_SHA" \
		-v complete_dir="$KOREADER_EXTRACTION_STATE_DIR" \
		-v sha_program="$KOREADER_SHA256_PROGRAM" '
		BEGIN { block = 0; launch = 0; state = 0 }
		state == 0 && $0 == "if [ -f \"$ZIPFILE\" ]; then" {
			block += 1
			state = 1
			next
		}
		state == 1 {
			if ($0 != "    echo \"Unzipping $ZIPFILE to $TARGET_DIR...\"") exit 71
			state = 2
			next
		}
		state == 2 {
			if ($0 != "    unzip \"$ZIPFILE\" -d \"$TARGET_DIR\"") exit 71
			state = 3
			next
		}
		state == 3 {
			if ($0 != "elif [ -f \"$GAMEDIR/koreader/luajit\" ]; then") exit 71
			state = 4
			next
		}
		state == 4 {
			if ($0 != "    echo \"ZIP IS ALREADY EXTRACTED\"") exit 71
			state = 5
			next
		}
		state == 5 {
			if ($0 != "    rm $ZIPFILE") exit 71
			state = 6
			next
		}
		state == 6 {
			if ($0 != "else") exit 71
			state = 7
			next
		}
		state == 7 {
			if ($0 != "    echo \"File $ZIPFILE does not exist 😢\"") exit 71
			state = 8
			next
		}
		state == 8 {
			if ($0 != "fi") exit 71
			print "BIRD_KOREADER_ARCHIVE_SHA=\"" archive_sha "\""
			print "BIRD_KOREADER_SHA256_PROGRAM=\"" sha_program "\""
			print "BIRD_KOREADER_COMPLETE_DIR=\"" complete_dir "\""
			print "BIRD_KOREADER_COMPLETE=\"$BIRD_KOREADER_COMPLETE_DIR/$BIRD_KOREADER_ARCHIVE_SHA.complete\""
			print "BIRD_KOREADER_COMPLETE_TEMP=\"$BIRD_KOREADER_COMPLETE.tmp\""
			print "BIRD_KOREADER_RECORD_SHA="
			print "if [ -f \"$BIRD_KOREADER_COMPLETE\" ]; then"
			print "    BIRD_KOREADER_RECORD_SHA=$(cat \"$BIRD_KOREADER_COMPLETE\" 2>/dev/null) || BIRD_KOREADER_RECORD_SHA="
			print "fi"
			print "if [ \"$BIRD_KOREADER_RECORD_SHA\" = \"$BIRD_KOREADER_ARCHIVE_SHA\" ] && [ -f \"$GAMEDIR/koreader/luajit\" ] && [ -f \"$GAMEDIR/koreader/reader.lua\" ] && [ -f \"$GAMEDIR/koreader/frontend/apps/reader/readerui.lua\" ] && [ -f \"$GAMEDIR/koreader/libs/libkoreader-cre.so\" ] && [ -f \"$GAMEDIR/koreader/libs/libwrap-mupdf.so\" ] && [ -f \"$GAMEDIR/koreader/defaults.custom.lua\" ]; then"
			print "    echo \"ZIP IS ALREADY EXTRACTED\""
			print "elif [ -f \"$ZIPFILE\" ]; then"
			print "    [ -x \"$BIRD_KOREADER_SHA256_PROGRAM\" ] || exit 1"
			print "    mkdir -p \"$BIRD_KOREADER_COMPLETE_DIR\" || exit 1"
			print "    chmod 0700 \"$BIRD_KOREADER_COMPLETE_DIR\" || exit 1"
			print "    rm -f \"$BIRD_KOREADER_COMPLETE\" \"$BIRD_KOREADER_COMPLETE_TEMP\" || exit 1"
			print "    BIRD_KOREADER_ARCHIVE_DIGEST_LINE=$(\"$BIRD_KOREADER_SHA256_PROGRAM\" \"$ZIPFILE\" 2>/dev/null) || exit 1"
			print "    BIRD_KOREADER_ARCHIVE_DIGEST=${BIRD_KOREADER_ARCHIVE_DIGEST_LINE%% *}"
			print "    [ \"$BIRD_KOREADER_ARCHIVE_DIGEST\" = \"$BIRD_KOREADER_ARCHIVE_SHA\" ] || exit 1"
			print "    echo \"Unzipping $ZIPFILE to $TARGET_DIR...\""
			print "    unzip -o \"$ZIPFILE\" -d \"$TARGET_DIR\" || exit 1"
			print "    for BIRD_KOREADER_REQUIRED in luajit reader.lua frontend/apps/reader/readerui.lua libs/libkoreader-cre.so libs/libwrap-mupdf.so defaults.custom.lua; do"
			print "        [ -f \"$GAMEDIR/koreader/$BIRD_KOREADER_REQUIRED\" ] || exit 1"
			print "    done"
			print "    printf \"%s\\n\" \"$BIRD_KOREADER_ARCHIVE_SHA\" >\"$BIRD_KOREADER_COMPLETE_TEMP\" || exit 1"
			print "    chmod 0600 \"$BIRD_KOREADER_COMPLETE_TEMP\" || { rm -f \"$BIRD_KOREADER_COMPLETE_TEMP\"; exit 1; }"
			print "    mv -f \"$BIRD_KOREADER_COMPLETE_TEMP\" \"$BIRD_KOREADER_COMPLETE\" || { rm -f \"$BIRD_KOREADER_COMPLETE_TEMP\"; exit 1; }"
			print "else"
			print "    echo \"File $ZIPFILE does not exist\""
			print "    exit 1"
			print "fi"
			print "for BIRD_KOREADER_REQUIRED in luajit reader.lua frontend/apps/reader/readerui.lua libs/libkoreader-cre.so libs/libwrap-mupdf.so defaults.custom.lua; do"
			print "    [ -f \"$GAMEDIR/koreader/$BIRD_KOREADER_REQUIRED\" ] || exit 1"
			print "done"
			state = 0
			next
		}
		$0 == "LD_PRELOAD=$GAMEDIR/libcrusty.so CRUSTY_BLOCK_INPUT=1 ./luajit reader.lua ../books" {
			launch += 1
			print "[ -n \"${BIRD_EBOOK_PATH:-}\" ] || exit 1"
			print "LD_PRELOAD=$GAMEDIR/libcrusty.so CRUSTY_BLOCK_INPUT=1 ./luajit reader.lua \"$BIRD_EBOOK_PATH\""
			next
		}
		{ print }
		END {
			if (state != 0 || block != 1 || launch != 1) exit 72
		}
	' "$KOREADER_PORT_SOURCE" >"$KOREADER_PORT_TEMP"; then
		remove_koreader_port_script || :
		return 1
	fi
	KOREADER_SOURCE_DIGEST_LINE=$(
		"$KOREADER_SHA256_PROGRAM" "$KOREADER_PORT_SOURCE" 2>/dev/null
	) || {
		remove_koreader_port_script || :
		return 1
	}
	KOREADER_SOURCE_DIGEST=${KOREADER_SOURCE_DIGEST_LINE%% *}
	[ "$KOREADER_SOURCE_DIGEST" = "$KOREADER_PORT_SOURCE_SHA" ] || {
		remove_koreader_port_script || :
		return 1
	}
	/bin/bash -n "$KOREADER_PORT_TEMP" || {
		remove_koreader_port_script || :
		return 1
	}
	chmod 0755 "$KOREADER_PORT_TEMP" || {
		remove_koreader_port_script || :
		return 1
	}
	mv -f "$KOREADER_PORT_TEMP" "$KOREADER_PORT_SCRIPT" || {
		remove_koreader_port_script || :
		return 1
	}
	return 0
}

prepare_portmaster_python_cache() {
	PORTMASTER_PYCACHE=/run/bird/portmaster-pycache
	if [ -e "$PORTMASTER_PYCACHE" ] || [ -L "$PORTMASTER_PYCACHE" ]; then
		[ -d "$PORTMASTER_PYCACHE" ] && [ ! -L "$PORTMASTER_PYCACHE" ] || \
			return 1
		rm -rf "$PORTMASTER_PYCACHE" || return 1
	fi
	(umask 077; mkdir -p "$PORTMASTER_PYCACHE") || return 1
	export PYTHONPYCACHEPREFIX="$PORTMASTER_PYCACHE"
	export PYTHONDONTWRITEBYTECODE=1
}

# PortMaster's fixed upstream frontend reads /tmp/battery.percent before it
# falls back to the AXP717 sysfs attribute.  The kernel attribute can
# transiently return ETIMEDOUT; publish the last value already acquired by
# Bird's long-lived power owner so a provider launch never performs that read.
prepare_portmaster_battery_cache() {
	PORTMASTER_POWER_LOG=${BIRD_PORTMASTER_POWER_LOG:-/storage/bird-data/Bird/log/powerstate-latest.log}
	PORTMASTER_BATTERY_CACHE=${BIRD_PORTMASTER_BATTERY_CACHE:-/tmp/battery.percent}
	PORTMASTER_BATTERY_PERCENT=
	PORTMASTER_BATTERY_LINE=

	if [ -r "$PORTMASTER_POWER_LOG" ]; then
		while IFS= read -r PORTMASTER_BATTERY_LINE ||
			[ -n "$PORTMASTER_BATTERY_LINE" ]; do
			if [[ $PORTMASTER_BATTERY_LINE =~ (^|[[:space:]])capacity=([0-9]{1,3})([[:space:]]|$) ]] &&
				[ "${BASH_REMATCH[2]}" -le 100 ]; then
				PORTMASTER_BATTERY_PERCENT=${BASH_REMATCH[2]}
			fi
		done <"$PORTMASTER_POWER_LOG"
	fi

	# A prior verified tmpfs value remains better than touching wedged sysfs.
	if [ -z "$PORTMASTER_BATTERY_PERCENT" ] &&
		[ -f "$PORTMASTER_BATTERY_CACHE" ] &&
		[ ! -L "$PORTMASTER_BATTERY_CACHE" ]; then
		IFS= read -r PORTMASTER_BATTERY_PERCENT <"$PORTMASTER_BATTERY_CACHE" || :
		case "$PORTMASTER_BATTERY_PERCENT" in
			''|*[!0-9]*) PORTMASTER_BATTERY_PERCENT= ;;
			*) [ "$PORTMASTER_BATTERY_PERCENT" -le 100 ] ||
				PORTMASTER_BATTERY_PERCENT= ;;
		esac
	fi
	[ -n "$PORTMASTER_BATTERY_PERCENT" ] || return 1

	if [ -e "$PORTMASTER_BATTERY_CACHE" ] ||
		[ -L "$PORTMASTER_BATTERY_CACHE" ]; then
		[ -f "$PORTMASTER_BATTERY_CACHE" ] &&
			[ ! -L "$PORTMASTER_BATTERY_CACHE" ] || return 1
	fi
	PORTMASTER_BATTERY_TEMP=${PORTMASTER_BATTERY_CACHE}.bird-new.$$
	[ ! -e "$PORTMASTER_BATTERY_TEMP" ] &&
		[ ! -L "$PORTMASTER_BATTERY_TEMP" ] || return 1
	(umask 077; printf '%s\n' "$PORTMASTER_BATTERY_PERCENT" \
		>"$PORTMASTER_BATTERY_TEMP") || return 1
	chmod 0644 "$PORTMASTER_BATTERY_TEMP" || {
		rm -f "$PORTMASTER_BATTERY_TEMP"
		return 1
	}
	mv -f "$PORTMASTER_BATTERY_TEMP" "$PORTMASTER_BATTERY_CACHE" || {
		rm -f "$PORTMASTER_BATTERY_TEMP"
		return 1
	}
	printf 'Bird portmaster battery-cache percent=%s\n' \
		"$PORTMASTER_BATTERY_PERCENT"
}

run_selected() {
	if [ "$SESSION_MODE" = portmaster ]; then
		prepare_portmaster_python_cache || return 1
		printf '%s\n' 'Bird portmaster prepare start'
		PORT_PREP_STATUS=0
		"$PORT_PREP" || PORT_PREP_STATUS=$?
		printf 'Bird portmaster prepare status=%s uptime=' "$PORT_PREP_STATUS"
		uptime_now
		[ "$PORT_PREP_STATUS" -eq 0 ] || return "$PORT_PREP_STATUS"
		prepare_portmaster_battery_cache || {
			printf '%s\n' 'Bird portmaster battery-cache unavailable'
			return 1
		}
		# The start helper can partially configure an interface before returning
		# failure, so cleanup owns a stop attempt from this point onward.
		PORTMASTER_NETWORK_STATUS=0
		start_portmaster_network start || PORTMASTER_NETWORK_STATUS=$?
		printf 'Bird portmaster network-start status=%s\n' "$PORTMASTER_NETWORK_STATUS"
		[ "$PORTMASTER_NETWORK_STATUS" -eq 0 ] || \
			return "$PORTMASTER_NETWORK_STATUS"
		# PortMaster is English-only on this fixed profile. Disable X11 compose
		# parsing so xkbcommon does not load unrelated legacy encodings. Redirect
		# Python's cache lookup is already redirected to fresh tmpfs by the shared
		# PortMaster execution boundary, making provider-local cache bytes inert.
		printf '%s\n' 'Bird portmaster launch start'
		run_managed env XCOMPOSEFILE=/dev/null /usr/bin/start_portmaster.sh
		PORTMASTER_RUN_STATUS=$?
		printf 'Bird portmaster launch status=%s\n' "$PORTMASTER_RUN_STATUS"
		return "$PORTMASTER_RUN_STATUS"
	fi
	case "$KIND" in
		1|2|4|5)
			read -r PLATFORM EMULATOR CORE < <(rocknix_tuple) || return 1
			[ "$CORE" != fmsx ] || prepare_fmsx_bios || return 1
			run_managed /usr/bin/runemu.sh "$CONTENT" "-P$PLATFORM" \
				"--core=$CORE" "--emulator=$EMULATOR" --controllers=""
			;;
		3)
			prepare_portmaster_python_cache || return 1
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
			run_managed "$MPV_PLAYER" "$CONTENT"
			;;
		7)
			case "$HOST_PATH" in
				/storage/media/READ/*.[eE][pP][uU][bB]|\
				/storage/media/READ/*.[pP][dD][fF]) ;;
				*) return 1 ;;
			esac
			[ -f "$CONTENT" ] || return 1
			prepare_portmaster_python_cache || return 1
			"$PORT_PREP" || return 1
			prepare_koreader_port_script || return 1
			run_managed env BIRD_EBOOK_PATH="$CONTENT" \
				/usr/bin/runemu.sh "$KOREADER_PORT_SCRIPT" -Pports \
				--core=portmaster --emulator=portmaster --controllers=""
			KOREADER_RUN_STATUS=$?
			remove_koreader_port_script || return 1
			return "$KOREADER_RUN_STATUS"
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
		RUNNER_SCOPE_INVOCATION=${SCOPE_INVOCATION:-pending}
		[ "$SCOPE_EXPECTED" -eq 1 ] || RUNNER_SCOPE_INVOCATION=none
		{
			printf '%s\n' 'version=2'
			printf 'armed=%s\n' "$ARMED"
			printf 'session_token=%s\n' "$SESSION_TOKEN"
			printf 'boot_id=%s\n' "$BOOT_ID_FULL"
			printf 'runner_pid=%s\n' "$$"
			printf 'runner_start_ticks=%s\n' "$RUNNER_START_TICKS"
			printf 'scope_expected=%s\n' "$SCOPE_EXPECTED"
			printf 'scope_unit=%s\n' "$SCOPE_UNIT"
			printf 'scope_invocation=%s\n' "$RUNNER_SCOPE_INVOCATION"
			printf 'scope_runner_pid=%s\n' "$SCOPE_RUNNER_PID"
			printf 'scope_runner_start_ticks=%s\n' \
				"$SCOPE_RUNNER_START_TICKS"
			printf 'sway_owned=%s\n' "$SWAY_OWNED"
			printf 'network_owned=%s\n' "$PORTMASTER_NETWORK"
			printf 'cleanup_mode=%s\n' "$CLEANUP_MODE"
			printf 'guard_unit=%s\n' "$GUARD_UNIT"
			printf 'session_log=%s\n' "$SESSION_LOG"
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
	# needs no lease; after publication, the live guard owns recovery. Ordinary
	# EXIT disarms it; the typed PortMaster network handoff deliberately does not.
	case "$RUNNER_START_TICKS" in
		*[!0-9]*|'') return 1 ;;
	esac
	GUARD_UNIT=bird-content-guard-${BOOT_ID}-$$-${RUNNER_START_TICKS}.service
	if ! /usr/bin/timeout --signal=TERM --kill-after=1s 3s \
		/usr/bin/systemd-run --quiet --collect --service-type=exec \
		--expand-environment=no \
		--unit="$GUARD_UNIT" --description='birdOS content cleanup guard' \
		--property=StartLimitIntervalSec=0 \
		--property=Restart=on-failure --property=RestartSec=250ms \
		-- /bin/sh -c '
		trap "" HUP
		umask 077
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
		SWAY_LOCK=${12}
		NETWORK_LOCK=${13}
		SWAY_OWNER=${14}
		NETWORK_OWNER=${15}
		SWAY_SOCKET=${16}
		SCOPE_START_GATE=${17}
		SCOPE_START_READY=${18}
		SCOPE_START_CANCEL=${19}
		PROC_ROOT=${20}
		KOREADER_PORT_SCRIPT=${21:-}
		"$PIDWAIT" --wait-exact "$PARENT" "$PARENT_START"
		PIDWAIT_STATUS=$?
		case "$PIDWAIT_STATUS" in
			0|5) ;;
			*) exit 1 ;;
		esac
		[ -s "$STATE_FILE" ] || exit 0
		value() { sed -n "s/^$1=//p" "$STATE_FILE" | head -n 1; }
		[ "$(value version)" = 2 ] || exit 0
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
		CLEANUP_MODE_GUARD=$(value cleanup_mode)
		case "$SCOPE_EXPECTED_GUARD:$SWAY_OWNED_GUARD:$NETWORK_OWNED_GUARD" in
			[01]:[01]:[01]) ;;
			*) exit 0 ;;
		esac
		case "$CLEANUP_MODE_GUARD" in
			foreground|background-network-pending|background-network-active) ;;
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
		if [ -n "$KOREADER_PORT_SCRIPT" ]; then
			while ! rm -f "$KOREADER_PORT_SCRIPT" \
				"$KOREADER_PORT_SCRIPT.tmp"; do
				usleep 250000
			done
		fi
		{
			printf "Bird runner guard reconciled pid=%s uptime=" "$PARENT"
			if IFS=" " read -r GUARD_UPTIME _ </proc/uptime; then
				printf "%s\n" "$GUARD_UPTIME"
			else
				printf "%s\n" unknown
			fi
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
				if [ ! -e "$1" ] && [ ! -L "$1" ]; then
					OWNER_RELATION=none
					return 0
				fi
				[ -s "$1" ] || return 0
				IFS= read -r OWNER_TOKEN <"$1" || return 0
				[ -n "$OWNER_TOKEN" ] || return 0
				if [ "$OWNER_TOKEN" = "$SESSION_TOKEN" ]; then
					OWNER_RELATION=ours
				else
					OWNER_RELATION=transferred
				fi
			}
			activate_background_network() {
				[ "$CLEANUP_MODE_GUARD" = background-network-pending ] || return 0
				[ "$SCOPE_EXPECTED_GUARD" = 0 ] && \
					[ "$SWAY_OWNED_GUARD" = 0 ] && \
					[ "$NETWORK_OWNED_GUARD" = 1 ] && \
					[ "$OWNER_RELATION" = ours ] || return 1
				ACTIVE_TMP=$STATE_FILE.active.$$
				[ "$(grep -c "^cleanup_mode=background-network-pending$" \
					"$STATE_FILE")" = 1 ] || return 1
				if ! sed \
					"s/^cleanup_mode=background-network-pending$/cleanup_mode=background-network-active/" \
					"$STATE_FILE" >"$ACTIVE_TMP" || \
					[ "$(grep -c "^cleanup_mode=background-network-active$" \
						"$ACTIVE_TMP")" != 1 ] || \
					! mv -f "$ACTIVE_TMP" "$STATE_FILE"; then
					rm -f "$ACTIVE_TMP" 2>/dev/null || :
					return 1
				fi
				CLEANUP_MODE_GUARD=background-network-active
				printf "Bird runner guard network cleanup active token=%s state=%s\n" \
					"$SESSION_TOKEN" "$STATE_FILE"
				return 0
			}
			sway_stopped() {
				[ ! -S "$SWAY_SOCKET" ] || return 1
				ACTIVE=$(timeout 3s systemctl show --property=ActiveState --value sway.service \
					8>&- 9>&- 2>/dev/null) || return 1
				case "$ACTIVE" in inactive|failed) return 0 ;; esac
				[ -z "$ACTIVE" ] || return 1
				LOAD=$(timeout 3s systemctl show --property=LoadState --value sway.service \
					8>&- 9>&- 2>/dev/null) || return 1
				[ "$LOAD" = not-found ]
			}
			while [ "$NETWORK_OWNED_GUARD" = 1 ]; do
				RESOURCE_STATUS=0
				if ! exec 9>"$NETWORK_LOCK" || ! flock -x 9; then
					RESOURCE_STATUS=1
				else
					owner_relation "$NETWORK_OWNER"
					if ! activate_background_network; then
						RESOURCE_STATUS=1
					fi
					case "$RESOURCE_STATUS:$OWNER_RELATION" in
						0:transferred) NETWORK_OWNED_GUARD=0 ;;
						0:ours|0:none)
							while ! timeout --signal=TERM --kill-after=1s 12s \
								"$NETWORK_HELPER" stop 8>&-; do
								usleep 250000
							done
							if [ "$OWNER_RELATION" = ours ] && \
								! rm -f "$NETWORK_OWNER"; then
								RESOURCE_STATUS=1
							else
								NETWORK_OWNED_GUARD=0
							fi
							;;
						*) RESOURCE_STATUS=1 ;;
					esac
					flock -u 9 || RESOURCE_STATUS=1
				fi
				exec 9>&-
				[ "$RESOURCE_STATUS" -eq 0 ] || usleep 250000
			done
			while [ "$SWAY_OWNED_GUARD" = 1 ]; do
				RESOURCE_STATUS=0
				if ! exec 9>"$SWAY_LOCK" || ! flock -x 9; then
					RESOURCE_STATUS=1
				else
					owner_relation "$SWAY_OWNER"
					case "$OWNER_RELATION" in
						transferred) SWAY_OWNED_GUARD=0 ;;
						ours|none)
							timeout 3s systemctl stop --no-block sway.service 8>&- 9>&- || :
							COUNT=0
							while ! sway_stopped && [ "$COUNT" -lt 100 ]; do
								COUNT=$((COUNT + 1))
								usleep 20000
							done
							if ! sway_stopped; then
								timeout 3s systemctl kill --kill-whom=all --signal=KILL \
									sway.service 8>&- 9>&- 2>/dev/null || :
								timeout 3s systemctl stop --no-block sway.service 8>&- 9>&- 2>/dev/null || :
							fi
							if ! sway_stopped || { \
								[ "$OWNER_RELATION" = ours ] && \
									! rm -f "$SWAY_OWNER"; }; then
								RESOURCE_STATUS=1
							else
								SWAY_OWNED_GUARD=0
							fi
							;;
						*) RESOURCE_STATUS=1 ;;
					esac
					flock -u 9 || RESOURCE_STATUS=1
				fi
				exec 9>&-
				[ "$RESOURCE_STATUS" -eq 0 ] || usleep 250000
			done
		} >>"$GUARD_LOG" 2>&1
		rm -f "$STATE_FILE".active.* 2>/dev/null || :
		while ! rm -f "$STATE_FILE"; do usleep 250000; done
	' bird-content-guard /flash/bird/bird-pidwait "$$" \
		"$RUNNER_STATE" "$RUNNER_START_TICKS" "$BOOT_ID_FULL" \
		/flash/bird/bird-fixed-control-exit.sh "$NETWORK" \
		"$SESSION_LOG" "$SESSION_RECORD" "$SESSION_PID" "$SESSION_TOKEN" \
		"$SWAY_LOCK" "$NETWORK_LOCK" "$SWAY_OWNER" "$NETWORK_OWNER" \
		"$SWAY_SOCKET" \
		"$SCOPE_START_GATE" "$SCOPE_START_READY" "$SCOPE_START_CANCEL" /proc \
		"$KOREADER_PORT_SCRIPT" \
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

handoff_portmaster_network_cleanup() {
	[ "$SESSION_MODE" = portmaster ] && [ "$GUARD_STARTED" -eq 1 ] &&
		[ "$SCOPE_EXPECTED" -eq 0 ] && [ "$SWAY_OWNED" -eq 0 ] &&
		[ "$PORTMASTER_NETWORK" -eq 1 ] && [ -n "$GUARD_UNIT" ] || return 1
	case "$$:$RUNNER_START_TICKS" in
		*[!0-9:]*|*:|:*) return 1 ;;
	esac
	[ "$SESSION_TOKEN" = "$BOOT_ID-$$-$RUNNER_START_TICKS" ] &&
		[ "$GUARD_UNIT" = \
		"bird-content-guard-$BOOT_ID-$$-$RUNNER_START_TICKS.service" ] || return 1
	# The guard is already an independently managed service waiting on this
	# exact runner pidfd. Publish the only state the supervisor may treat as
	# non-foreground: no scope, no Sway, and this token's network still owned.
	network_lock || return 1
	owner_relation "$NETWORK_OWNER"
	if [ "$OWNER_RELATION" != ours ]; then
		resource_unlock
		return 1
	fi
	CLEANUP_MODE=background-network-pending
	if ! publish_runner_state 1; then
		CLEANUP_MODE=foreground
		resource_unlock
		return 1
	fi
	resource_unlock
	CLEANUP_STATE=background-network
	printf 'Bird content stage=network-cleanup-background token=%s state=%s log=%s uptime=' \
		"$SESSION_TOKEN" "$RUNNER_STATE" "$SESSION_LOG"
	uptime_now
	return 0
}

cleanup_runtime() {
	case "$CLEANUP_STATE" in
		succeeded|background-network) return 0 ;;
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
	if [ "$SESSION_MODE" = portmaster ] && [ "$GUARD_STARTED" -eq 1 ] &&
		[ "$PORTMASTER_NETWORK" -eq 1 ]; then
		# Display and input ownership remain a foreground boundary. Once Sway is
		# proven gone, only token-checked network teardown may outlive this runner.
		release_sway_until_done
		if handoff_portmaster_network_cleanup; then
			return 0
		fi
	fi
	release_owned_resources_until_done
	if ! remove_koreader_port_script; then
		CLEANUP_STATE=failed
		return 1
	fi
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
	elif [ "$CLEANUP_STATE" = background-network ]; then
		# The still-armed guard wakes on this exact exit and owns the remaining
		# network teardown. Its state is a non-foreground supervisor lease.
		:
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

{
	STATUS=0
	START_FAILURE_REASON=
	printf 'Bird session log shareability=private-raw path=%s\n' "$SESSION_LOG"
	content_stage session-start
	if ! start_cleanup_guard; then
		START_FAILURE_REASON='runner cleanup guard unavailable'
		STATUS=1
		content_stage guard-failed
	else
		content_stage guard-ready
	fi
	[ -z "$START_FAILURE_REASON" ] || \
		printf 'Bird content refused: %s\n' "$START_FAILURE_REASON"
	printf 'session_mode=%s\n' "$SESSION_MODE"
	if [ "$SESSION_MODE" = content ]; then
		printf 'kind=%s core=%s name=%s host=%s content=%s\n' \
			"$KIND" "$REQUESTED_CORE" "$NAME" "$HOST_PATH" "$CONTENT"
	fi
	# An initramfs selection can start this runner before the persistent profile
	# writers finish. Reload only after the revisioned marker has validated their
	# exact outputs; otherwise this shell retains stale DEVICE_*/Sway values.
	if [ "$STATUS" -eq 0 ] && wait_application_contract && . /etc/profile; then
		printf 'Bird application contract ready revision=%s uptime=' \
			"$APPLICATION_CONTRACT_REVISION"
		uptime_now
		content_stage contract-ready
		if [ "$SESSION_MODE" = content ] && ! rm -f "$REQUEST"; then
			STATUS=1
		fi
		if [ "$STATUS" -eq 0 ]; then
			content_stage sway-start-request
		fi
		if [ "$STATUS" -eq 0 ] && start_sway; then
			content_stage services-start
			ensure_content_services || STATUS=1
			: >/var/log/exec.log
			if [ "${STATUS:-0}" -eq 0 ]; then
				content_stage provider-start
				run_selected
				STATUS=$?
				content_stage provider-returned
			fi
			if [ -s /var/log/exec.log ]; then
				printf '%s\n' '--- ROCKNIX application log (private raw, last 256 KiB) ---'
				tail -c 262144 /var/log/exec.log
				printf '%s\n' '--- end ROCKNIX application log ---'
			fi
		else
			STATUS=1
		fi
	else
		STATUS=1
	fi
	content_stage cleanup-start
	cleanup_runtime || STATUS=1
	content_stage cleanup-complete
	printf 'Bird ROCKNIX session result=%s uptime=' "$STATUS"
	uptime_now
} >"$SESSION_LOG" 2>&1

cp -f "$SESSION_LOG" "$LOG" || :
exit "$STATUS"
