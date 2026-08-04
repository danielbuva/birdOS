#!/bin/sh
# Shared macOS host lock for every operation that mutates one Bird card. The
# caller must set WHOLE and provide fail(). The canonical lock is an atomic
# symlink whose complete target binds PID to process start identity. A short
# BSD advisory mutex serializes owner inspection, while a second advisory lock
# is held for the complete transaction and inherited by every mutator child.

bird_card_process_start() {
	# lstart is localized by ps. Force the portable English rendering, then
	# retain only C-locale alphanumerics so the symlink token grammar is stable.
	LC_ALL=C ps -p "$1" -o lstart= 2>/dev/null |
		LC_ALL=C tr -cd '[:alnum:]'
}

bird_card_lock_serial_enter() {
	BIRD_CARD_LOCK_SERIAL=$BIRD_CARD_LOCK_ROOT/$WHOLE.serial
	if [ ! -e "$BIRD_CARD_LOCK_SERIAL" ] && [ ! -L "$BIRD_CARD_LOCK_SERIAL" ]; then
		(umask 077; set -C; : >"$BIRD_CARD_LOCK_SERIAL") 2>/dev/null || :
	fi
	[ -f "$BIRD_CARD_LOCK_SERIAL" ] && [ ! -L "$BIRD_CARD_LOCK_SERIAL" ] ||
		fail 'Bird card lock mutex is unsafe'
	[ "$(stat -f '%u' "$BIRD_CARD_LOCK_SERIAL" 2>/dev/null || :)" = \
		"$BIRD_CARD_LOCK_UID" ] || fail 'Bird card lock mutex owner is unsafe'
	[ "$(stat -f '%Lp' "$BIRD_CARD_LOCK_SERIAL" 2>/dev/null || :)" = 600 ] ||
		fail 'Bird card lock mutex mode is unsafe'
	[ "$(stat -f '%l' "$BIRD_CARD_LOCK_SERIAL" 2>/dev/null || :)" = 1 ] ||
		fail 'Bird card lock mutex link count is unsafe'
	exec 9<>"$BIRD_CARD_LOCK_SERIAL" || fail 'could not open Bird card lock mutex'
	/usr/bin/lockf -s -t 15 9 || fail 'Bird card lock recovery is busy'
}

bird_card_lock_serial_leave() {
	exec 9>&-
}

bird_card_lock_transaction_enter() {
	BIRD_CARD_TRANSACTION=$BIRD_CARD_LOCK_ROOT/$WHOLE.transaction
	if [ ! -e "$BIRD_CARD_TRANSACTION" ] && [ ! -L "$BIRD_CARD_TRANSACTION" ]; then
		(umask 077; set -C; : >"$BIRD_CARD_TRANSACTION") 2>/dev/null || :
	fi
	[ -f "$BIRD_CARD_TRANSACTION" ] && [ ! -L "$BIRD_CARD_TRANSACTION" ] ||
		fail 'Bird card transaction mutex is unsafe'
	[ "$(stat -f '%u' "$BIRD_CARD_TRANSACTION" 2>/dev/null || :)" = \
		"$BIRD_CARD_LOCK_UID" ] || fail 'Bird card transaction mutex owner is unsafe'
	[ "$(stat -f '%Lp' "$BIRD_CARD_TRANSACTION" 2>/dev/null || :)" = 600 ] ||
		fail 'Bird card transaction mutex mode is unsafe'
	[ "$(stat -f '%l' "$BIRD_CARD_TRANSACTION" 2>/dev/null || :)" = 1 ] ||
		fail 'Bird card transaction mutex link count is unsafe'
	exec 8<>"$BIRD_CARD_TRANSACTION" || fail 'could not open Bird card transaction mutex'
	BIRD_CARD_TRANSACTION_OPEN=1
	# flock(2) is tied to the inherited open-file description. If this shell is
	# SIGKILLed, an in-flight cp/mv/find child keeps fd 8 and therefore the lock
	# until that child really exits.
	if ! /usr/bin/lockf -s -t 15 8; then
		exec 8>&-
		BIRD_CARD_TRANSACTION_OPEN=0
		fail 'another Bird card transaction is active (owner or inherited mutator child)'
	fi
}

bird_card_lock_transaction_leave() {
	[ "${BIRD_CARD_TRANSACTION_OPEN:-0}" -eq 1 ] || return 0
	exec 8>&-
	BIRD_CARD_TRANSACTION_OPEN=0
}

bird_card_lock_acquire() {
	[ -n "${WHOLE:-}" ] || fail 'card lock requires a whole-disk identity'
	case "$WHOLE" in *[!A-Za-z0-9._-]*|'') fail 'unsafe whole-disk identity for card lock' ;; esac
	[ -x /usr/bin/lockf ] || fail 'macOS lock helper is missing: /usr/bin/lockf'
	BIRD_CARD_LOCK_UID=$(id -u)
	case "$BIRD_CARD_LOCK_UID" in ''|*[!0-9]*) fail 'invalid host UID for card lock' ;; esac
	# TMPDIR and effective UID can differ across shells, launch agents and sudo.
	# Keep every card in one fixed namespace: the first verified 0700 owner is
	# authoritative, and any other UID fails closed instead of acquiring a
	# parallel lock for the same physical card.
	BIRD_CARD_LOCK_ROOT=/tmp/bird-card-locks
	if [ ! -e "$BIRD_CARD_LOCK_ROOT" ] && [ ! -L "$BIRD_CARD_LOCK_ROOT" ]; then
		(umask 077; mkdir -m 700 "$BIRD_CARD_LOCK_ROOT") 2>/dev/null || :
	fi
	[ -d "$BIRD_CARD_LOCK_ROOT" ] && [ ! -L "$BIRD_CARD_LOCK_ROOT" ] ||
		fail 'Bird card lock directory is unsafe'
	[ "$(stat -f '%u' "$BIRD_CARD_LOCK_ROOT" 2>/dev/null || :)" = \
		"$BIRD_CARD_LOCK_UID" ] || fail 'Bird card lock directory owner is unsafe'
	[ "$(stat -f '%Lp' "$BIRD_CARD_LOCK_ROOT" 2>/dev/null || :)" = 700 ] ||
		fail 'Bird card lock directory mode is unsafe'
	BIRD_CARD_LOCK=$BIRD_CARD_LOCK_ROOT/$WHOLE.lock
	BIRD_CARD_LOCK_OWNED=0
	BIRD_CARD_TRANSACTION_OPEN=0
	BIRD_CARD_LOCK_START=$(bird_card_process_start "$$")
	[ -n "$BIRD_CARD_LOCK_START" ] || fail 'could not read Bird card lock process identity'
	BIRD_CARD_LOCK_TOKEN=$$:$BIRD_CARD_LOCK_START:$(date +%s)

	# Acquire the full-lifetime kernel lock before trusting or recovering the
	# diagnostic owner symlink. A dead parent is not stale while any inherited
	# mutator descriptor remains open. It must be acquired before the short
	# serial mutex: the current owner needs that serial mutex while releasing
	# its transaction, so waiting in the opposite order would deadlock it.
	bird_card_lock_transaction_enter
	bird_card_lock_serial_enter
	if [ -e "$BIRD_CARD_LOCK" ] && [ ! -L "$BIRD_CARD_LOCK" ]; then
		bird_card_lock_serial_leave
		bird_card_lock_transaction_leave
		fail 'Bird card lock is not an atomic owner symlink'
	fi
	if [ -L "$BIRD_CARD_LOCK" ]; then
		BIRD_CARD_LOCK_OBSERVED=$(readlink "$BIRD_CARD_LOCK" 2>/dev/null || printf '')
		BIRD_CARD_LOCK_OWNER_PID=${BIRD_CARD_LOCK_OBSERVED%%:*}
		BIRD_CARD_LOCK_OWNER_REST=${BIRD_CARD_LOCK_OBSERVED#*:}
		BIRD_CARD_LOCK_OWNER_START=${BIRD_CARD_LOCK_OWNER_REST%%:*}
		BIRD_CARD_LOCK_OWNER_VALID=1
		case "$BIRD_CARD_LOCK_OWNER_PID" in
			''|*[!0-9]*) BIRD_CARD_LOCK_OWNER_VALID=0 ;;
		esac
		case "$BIRD_CARD_LOCK_OWNER_START" in
			''|*[!0-9A-Za-z]*) BIRD_CARD_LOCK_OWNER_VALID=0 ;;
		esac
		BIRD_CARD_LOCK_OWNER_LIVE=0
		if [ "$BIRD_CARD_LOCK_OWNER_VALID" -eq 1 ] &&
			kill -0 "$BIRD_CARD_LOCK_OWNER_PID" 2>/dev/null &&
			[ "$(bird_card_process_start "$BIRD_CARD_LOCK_OWNER_PID")" = \
			"$BIRD_CARD_LOCK_OWNER_START" ]; then
			BIRD_CARD_LOCK_OWNER_STATE=$(LC_ALL=C ps \
				-p "$BIRD_CARD_LOCK_OWNER_PID" -o state= 2>/dev/null |
				LC_ALL=C tr -d '[:space:]')
			case "$BIRD_CARD_LOCK_OWNER_STATE" in
				Z*|'') ;;
				*) BIRD_CARD_LOCK_OWNER_LIVE=1 ;;
			esac
		fi
		if [ "$BIRD_CARD_LOCK_OWNER_LIVE" -eq 1 ]; then
			bird_card_lock_serial_leave
			bird_card_lock_transaction_leave
			fail "another Bird card transaction is active (owner $BIRD_CARD_LOCK_OWNER_PID)"
		fi
		rm -f "$BIRD_CARD_LOCK" || {
			bird_card_lock_serial_leave
			bird_card_lock_transaction_leave
			fail 'could not remove stale Bird card lock'
		}
	fi
	ln -s "$BIRD_CARD_LOCK_TOKEN" "$BIRD_CARD_LOCK" || {
		bird_card_lock_serial_leave
		bird_card_lock_transaction_leave
		fail 'could not publish atomic Bird card lock'
	}
	[ "$(readlink "$BIRD_CARD_LOCK" 2>/dev/null || :)" = \
		"$BIRD_CARD_LOCK_TOKEN" ] || {
		bird_card_lock_serial_leave
		bird_card_lock_transaction_leave
		fail 'atomic Bird card lock verification failed'
	}
	BIRD_CARD_LOCK_OWNED=1
	bird_card_lock_serial_leave
}

bird_card_lock_release() {
	if [ "${BIRD_CARD_LOCK_OWNED:-0}" -eq 1 ]; then
		bird_card_lock_serial_enter
		if [ "$(readlink "$BIRD_CARD_LOCK" 2>/dev/null || :)" = \
			"$BIRD_CARD_LOCK_TOKEN" ]; then
			BIRD_CARD_LOCK_RELEASED=$BIRD_CARD_LOCK.released.$$
			if mv "$BIRD_CARD_LOCK" "$BIRD_CARD_LOCK_RELEASED" 2>/dev/null; then
				[ "$(readlink "$BIRD_CARD_LOCK_RELEASED" 2>/dev/null || :)" = \
					"$BIRD_CARD_LOCK_TOKEN" ] && rm -f "$BIRD_CARD_LOCK_RELEASED"
			fi
		fi
		BIRD_CARD_LOCK_OWNED=0
		bird_card_lock_serial_leave
	fi
	# Remove the diagnostic owner first, then release the authoritative kernel
	# lock. A contender that arrives between those steps still cannot proceed.
	bird_card_lock_transaction_leave
}
