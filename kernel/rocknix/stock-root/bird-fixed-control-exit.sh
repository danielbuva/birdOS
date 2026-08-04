#!/bin/sh
# End only birdOS's current foreground content scope. Every destructive action
# requires the exact boot, session token, unit and systemd InvocationID. Query
# failures are unknown—not evidence that a cgroup is empty.

SESSION_PID=${BIRD_SESSION_PID:-/run/bird/content-session.pid}
EXPECTED_SESSION_TOKEN=${BIRD_EXPECTED_SESSION_TOKEN:-}
REQUIRE_SESSION_RECORD=${BIRD_REQUIRE_SESSION_RECORD:-0}
STABLE_NOT_FOUND_COUNT=${BIRD_STABLE_NOT_FOUND_COUNT:-1}
LOG=${BIRD_EXIT_LOG:-/storage/bird-data/Bird/log/content-exit-latest.log}
BOOT_ID_PATH=${BIRD_BOOT_ID_PATH:-/proc/sys/kernel/random/boot_id}
UPTIME_PATH=${BIRD_UPTIME_PATH:-/proc/uptime}
SESSION_LOCK=${BIRD_SESSION_LOCK:-/run/bird/content-session.lock}
SCOPE_QUERY_RESULT=unknown
SCOPE_QUERY_VALUE=

case "$STABLE_NOT_FOUND_COUNT" in
	''|*[!0-9]*) STABLE_NOT_FOUND_COUNT=1 ;;
	*)
		[ "$STABLE_NOT_FOUND_COUNT" -ge 1 ] 2>/dev/null || \
			STABLE_NOT_FOUND_COUNT=1
		[ "$STABLE_NOT_FOUND_COUNT" -le 100 ] 2>/dev/null || \
			STABLE_NOT_FOUND_COUNT=100
		;;
esac

mkdir -p "${LOG%/*}"
: >"$LOG"

printf 'Bird foreground exit request uptime=' >>"$LOG"
cut -d ' ' -f 1 "$UPTIME_PATH" >>"$LOG"

metadata_value() {
	KEY=$1
	sed -n "s/^$KEY=//p" "$SESSION_PID" 2>/dev/null | head -n 1
}

session_lock() {
	exec 8>"$SESSION_LOCK" || return 1
	flock -x 8 || { exec 8>&-; return 1; }
}

session_unlock() {
	flock -u 8 2>/dev/null || :
	exec 8>&-
}

scope_query_property() {
	PROPERTY=$1
	UNIT_NAME=$2
	SCOPE_QUERY_RESULT=unknown
	SCOPE_QUERY_VALUE=
	PROPERTY_QUERY_OK=0
	if SCOPE_QUERY_VALUE=$(systemctl show --property="$PROPERTY" --value \
		"$UNIT_NAME" 8>&- 9>&- 2>/dev/null); then
		PROPERTY_QUERY_OK=1
		if [ -n "$SCOPE_QUERY_VALUE" ]; then
			SCOPE_QUERY_RESULT=present
			return 0
		fi
	fi
	if LOAD_STATE=$(systemctl show --property=LoadState --value "$UNIT_NAME" \
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
		"$UNIT_NAME" 8>&- 9>&- 2>/dev/null); then
		UNIT_FOUND=0
		while IFS=' ' read -r LISTED_UNIT _; do
			[ "$LISTED_UNIT" = "$UNIT_NAME" ] && UNIT_FOUND=1
		done <<EOF
$UNIT_LIST
EOF
		[ "$UNIT_FOUND" -eq 1 ] || SCOPE_QUERY_RESULT=not-found
	fi
}

parse_metadata_snapshot() {
	VERSION=
	BOUNDARY=
	RECORDED_STATE=
	RECORDED_SESSION_TOKEN=
	RECORDED_BOOT_ID=
	UNIT=
	INVOCATION=
	CONTROL_GROUP=
	SEEN_VERSION=0
	SEEN_BOUNDARY=0
	SEEN_STATE=0
	SEEN_SESSION_TOKEN=0
	SEEN_BOOT_ID=0
	SEEN_UNIT=0
	SEEN_INVOCATION=0
	SEEN_CONTROL_GROUP=0
	METADATA_FIELDS=0
	while IFS= read -r METADATA_LINE; do
		METADATA_FIELDS=$((METADATA_FIELDS + 1))
		case "$METADATA_LINE" in
			version=*)
				[ "$SEEN_VERSION" -eq 0 ] || return 1
				SEEN_VERSION=1
				VERSION=${METADATA_LINE#version=}
				;;
			boundary=*)
				[ "$SEEN_BOUNDARY" -eq 0 ] || return 1
				SEEN_BOUNDARY=1
				BOUNDARY=${METADATA_LINE#boundary=}
				;;
			state=*)
				[ "$SEEN_STATE" -eq 0 ] || return 1
				SEEN_STATE=1
				RECORDED_STATE=${METADATA_LINE#state=}
				;;
			session_token=*)
				[ "$SEEN_SESSION_TOKEN" -eq 0 ] || return 1
				SEEN_SESSION_TOKEN=1
				RECORDED_SESSION_TOKEN=${METADATA_LINE#session_token=}
				;;
			boot_id=*)
				[ "$SEEN_BOOT_ID" -eq 0 ] || return 1
				SEEN_BOOT_ID=1
				RECORDED_BOOT_ID=${METADATA_LINE#boot_id=}
				;;
			unit=*)
				[ "$SEEN_UNIT" -eq 0 ] || return 1
				SEEN_UNIT=1
				UNIT=${METADATA_LINE#unit=}
				;;
			invocation_id=*)
				[ "$SEEN_INVOCATION" -eq 0 ] || return 1
				SEEN_INVOCATION=1
				INVOCATION=${METADATA_LINE#invocation_id=}
				;;
			control_group=*)
				[ "$SEEN_CONTROL_GROUP" -eq 0 ] || return 1
				SEEN_CONTROL_GROUP=1
				CONTROL_GROUP=${METADATA_LINE#control_group=}
				;;
			*) return 1 ;;
		esac
	done <<EOF
$METADATA_SNAPSHOT
EOF
	[ "$METADATA_FIELDS" -eq 8 ] || return 1
	[ "$SEEN_VERSION$SEEN_BOUNDARY$SEEN_STATE$SEEN_SESSION_TOKEN" = 1111 ] ||
		return 1
	[ "$SEEN_BOOT_ID$SEEN_UNIT$SEEN_INVOCATION$SEEN_CONTROL_GROUP" = 1111 ] ||
		return 1

	[ "$VERSION" = 2 ] && [ "$BOUNDARY" = systemd-scope ] || return 1
	[ -n "$RECORDED_SESSION_TOKEN" ] || return 1
	if [ -n "$EXPECTED_SESSION_TOKEN" ] && \
		[ "$RECORDED_SESSION_TOKEN" != "$EXPECTED_SESSION_TOKEN" ]; then
		return 3
	fi
	case "$UNIT" in
		bird-content-*.scope) ;;
		*) return 1 ;;
	esac
	case "$UNIT" in
		*[!A-Za-z0-9_.-]*) return 1 ;;
	esac
	case "$RECORDED_STATE" in
		starting)
			[ "$INVOCATION" = pending ] || return 1
			;;
		active)
			case "$INVOCATION" in
				00000000000000000000000000000000|''|*[!0-9a-fA-F]*) return 1 ;;
			esac
			[ "${#INVOCATION}" -eq 32 ] || return 1
			case "$CONTROL_GROUP" in /*) ;; *) return 1 ;; esac
			;;
		*) return 1 ;;
	esac
	CURRENT_BOOT_ID=$(cat "$BOOT_ID_PATH" 2>/dev/null || :)
	[ -n "$CURRENT_BOOT_ID" ] && \
		[ "$RECORDED_BOOT_ID" = "$CURRENT_BOOT_ID" ]
}

load_metadata() {
	# The publisher swaps starting and active records while holding this same
	# lock. Read the global pointer exactly once under that lock, then release it
	# before any manager query or later remove_our_metadata lock acquisition.
	session_lock || return 2
	LOAD_METADATA_STATUS=0
	if [ ! -s "$SESSION_PID" ]; then
		LOAD_METADATA_STATUS=1
	elif ! METADATA_CAPTURE=$(cat "$SESSION_PID" 2>/dev/null && \
		printf '%s' __BIRD_METADATA_EOF__); then
		LOAD_METADATA_STATUS=2
	else
		# Keeping a non-newline sentinel in the command substitution preserves
		# whether the source really ended in a newline. Remove exactly that final
		# newline before the here-document parser adds its own line terminator.
		case "$METADATA_CAPTURE" in
			*"
__BIRD_METADATA_EOF__")
				METADATA_SNAPSHOT=${METADATA_CAPTURE%__BIRD_METADATA_EOF__}
				METADATA_SNAPSHOT=${METADATA_SNAPSHOT%?}
				parse_metadata_snapshot
				LOAD_METADATA_STATUS=$?
				;;
			*) LOAD_METADATA_STATUS=1 ;;
		esac
	fi
	session_unlock
	return "$LOAD_METADATA_STATUS"
}

# Return 0 exact match, 1 confirmed gone/replaced, 2 query unknown.
scope_identity_status() {
	scope_query_property InvocationID "$UNIT"
	case "$SCOPE_QUERY_RESULT" in
		not-found) return 1 ;;
		unknown) return 2 ;;
	esac
	CURRENT_INVOCATION=$SCOPE_QUERY_VALUE
	case "$CURRENT_INVOCATION" in
		00000000000000000000000000000000|''|*[!0-9a-fA-F]*) return 2 ;;
	esac
	[ "${#CURRENT_INVOCATION}" -eq 32 ] || return 2
	if [ "$INVOCATION" = pending ]; then
		# The unit name contains the exact boot/session identity. Adoption is only
		# for the short atomic publication race and is rechecked before signaling.
		INVOCATION=$CURRENT_INVOCATION
	fi
	[ "$INVOCATION" = "$CURRENT_INVOCATION" ] && return 0
	return 1
}

# Return 0 active, 1 confirmed inactive/gone/replaced, 2 query unknown.
scope_activity_status() {
	scope_identity_status
	IDENTITY_STATUS=$?
	[ "$IDENTITY_STATUS" -eq 0 ] || return "$IDENTITY_STATUS"
	scope_query_property ActiveState "$UNIT"
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

remove_our_metadata() {
	session_lock || return 2
	# Revalidate immediately before unlink. A manager query failure preserves
	# the record so a later control request or crash guard can retry safely.
	scope_activity_status
	REMOVE_ACTIVITY=$?
	case "$REMOVE_ACTIVITY" in
		0) session_unlock; return 3 ;;
		1) ;;
		*) session_unlock; return 2 ;;
	esac
	if [ ! -f "$SESSION_PID" ]; then
		session_unlock
		return 0
	fi
	FILE_TOKEN=$(metadata_value session_token)
	FILE_UNIT=$(metadata_value unit)
	FILE_INVOCATION=$(metadata_value invocation_id)
	if [ "$FILE_TOKEN" != "$RECORDED_SESSION_TOKEN" ] || \
		[ "$FILE_UNIT" != "$UNIT" ]; then
		session_unlock
		return 0
	fi
	case "$FILE_INVOCATION" in
		pending|"$INVOCATION")
			if ! rm -f "$SESSION_PID"; then
				session_unlock
				return 2
			fi
			;;
	esac
	session_unlock
	return 0
}

load_metadata
LOAD_STATUS=$?
case "$LOAD_STATUS" in
	0) ;;
	2)
		printf '%s\n' 'content_scope=metadata-query-unknown action=retry' >>"$LOG"
		exit 2
		;;
	3)
		printf '%s\n' 'content_scope=newer-session action=none' >>"$LOG"
		[ "$REQUIRE_SESSION_RECORD" = 1 ] && exit 2
		exit 0
		;;
	*)
		printf '%s\n' 'content_scope=none-or-invalid action=none' >>"$LOG"
		[ "$REQUIRE_SESSION_RECORD" = 1 ] && exit 2
		exit 0
		;;
esac

# Cover the exact launch/exit registration race. Unknown after the bounded
# foreground wait is retryable status 2 and never removes the record.
COUNT=0
while [ "$COUNT" -lt 50 ]; do
	scope_identity_status
	IDENTITY_STATUS=$?
	[ "$IDENTITY_STATUS" -ne 2 ] && break
	COUNT=$((COUNT + 1))
	usleep 10000
done

# A killed scope-bootstrap client may already have queued its manager request.
# Crash recovery therefore requires consecutive confirmed-absent observations
# after that exact client is gone; a late InvocationID wins and is terminated.
if [ "$IDENTITY_STATUS" -eq 1 ] && [ "$STABLE_NOT_FOUND_COUNT" -gt 1 ]; then
	ABSENT_COUNT=1
	while [ "$ABSENT_COUNT" -lt "$STABLE_NOT_FOUND_COUNT" ]; do
		usleep 25000
		scope_identity_status
		IDENTITY_STATUS=$?
		[ "$IDENTITY_STATUS" -eq 1 ] || break
		ABSENT_COUNT=$((ABSENT_COUNT + 1))
	done
fi

case "$IDENTITY_STATUS" in
	1)
		remove_our_metadata
		REMOVE_STATUS=$?
		if [ "$REMOVE_STATUS" -eq 0 ]; then
			printf 'content_scope=%s state=gone-or-replaced\n' "$UNIT" >>"$LOG"
			exit 0
		fi
		if [ "$REMOVE_STATUS" -ne 3 ]; then
			printf 'content_scope=%s state=query-unknown metadata=preserved\n' \
				"$UNIT" >>"$LOG"
			exit 2
		fi
		;;
	2)
		printf 'content_scope=%s state=query-unknown metadata=preserved\n' \
			"$UNIT" >>"$LOG"
		exit 2
		;;
esac

printf 'content_scope=%s invocation=%s action=term\n' \
	"$UNIT" "$INVOCATION" >>"$LOG"
scope_identity_status
IDENTITY_STATUS=$?
case "$IDENTITY_STATUS" in
	0)
		systemctl kill --kill-whom=all --signal=TERM "$UNIT" \
			8>&- 9>&- 2>/dev/null || {
			scope_activity_status
			[ "$?" -eq 1 ] || exit 2
		}
		;;
	1) ;;
	2) exit 2 ;;
esac

COUNT=0
while [ "$COUNT" -lt 100 ]; do
	scope_activity_status
	ACTIVITY_STATUS=$?
	[ "$ACTIVITY_STATUS" -ne 0 ] && break
	COUNT=$((COUNT + 1))
	usleep 10000
done

if [ "$ACTIVITY_STATUS" -eq 2 ]; then
	printf 'content_scope=%s state=query-unknown metadata=preserved\n' \
		"$UNIT" >>"$LOG"
	exit 2
fi

if [ "$ACTIVITY_STATUS" -eq 0 ]; then
	printf 'content_scope=%s invocation=%s action=kill\n' \
		"$UNIT" "$INVOCATION" >>"$LOG"
	scope_identity_status
	IDENTITY_STATUS=$?
	case "$IDENTITY_STATUS" in
		0)
			systemctl kill --kill-whom=all --signal=KILL "$UNIT" \
				8>&- 9>&- 2>/dev/null || {
				scope_activity_status
				[ "$?" -eq 1 ] || exit 2
			}
			;;
		1) ;;
		2) exit 2 ;;
	esac
	COUNT=0
	while [ "$COUNT" -lt 100 ]; do
		scope_activity_status
		ACTIVITY_STATUS=$?
		[ "$ACTIVITY_STATUS" -ne 0 ] && break
		COUNT=$((COUNT + 1))
		usleep 10000
	done
fi

case "$ACTIVITY_STATUS" in
	0)
		printf 'content_scope=%s invocation=%s state=not-empty\n' \
			"$UNIT" "$INVOCATION" >>"$LOG"
		exit 1
		;;
	2)
		printf 'content_scope=%s state=query-unknown metadata=preserved\n' \
			"$UNIT" >>"$LOG"
		exit 2
		;;
esac

if ! remove_our_metadata; then
	printf 'content_scope=%s state=query-unknown metadata=preserved\n' \
		"$UNIT" >>"$LOG"
	exit 2
fi
printf 'content_scope=%s invocation=%s state=empty\n' \
	"$UNIT" "$INVOCATION" >>"$LOG"
exit 0
