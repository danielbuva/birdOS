#!/bin/sh
# Preserve Bird's exact fixed-panel level around ROCKNIX's retained fake
# suspend transaction. The provider owns audio, input, governors and LEDs;
# this wrapper narrows the display contract to one RG34XX-SP backlight.

BACKLIGHT=${BIRD_BACKLIGHT:-/sys/class/backlight/backlight}
BRIGHTNESS=$BACKLIGHT/brightness
BL_POWER=$BACKLIGHT/bl_power
MAX_BRIGHTNESS=$BACKLIGHT/max_brightness
STATE=${BIRD_SUSPEND_STATE:-/run/muos/bird-pre-suspend-brightness}
STOCK=${BIRD_SUSPEND_PROVIDER:-/usr/bin/rocknix-fake-suspend}
LOG=${BIRD_SUSPEND_LOG:-/storage/bird-data/MUOS/Bird/log/suspend-latest.log}
SETTLE=${BIRD_SUSPEND_SETTLE:-/usr/bin/usleep}
TRANSITION=${BIRD_SUSPEND_TRANSITION:-/run/muos/bird-suspend-resuming}
PENDING=${BIRD_SUSPEND_PENDING:-/run/muos/bird-suspend-pending}
TRANSITION_LOCK=${BIRD_SUSPEND_TRANSITION_LOCK:-/run/muos/bird-suspend-transition.lock}
FLOCK=${BIRD_SUSPEND_FLOCK:-flock}

lock_transition() {
	mkdir -p "${TRANSITION_LOCK%/*}"
	exec 9>"$TRANSITION_LOCK"
	"$FLOCK" -x 9
}

unlock_transition() {
	"$FLOCK" -u 9 2>/dev/null || :
	exec 9>&-
}

pending_value() {
	case "${1:-}:${2:-}" in
		power:) printf '%s\n' power ;;
		lid:close) printf '%s\n' lid-close ;;
		*) printf '%s\n' none ;;
	esac
}

queue_while_resuming() {
	REQUEST=$(pending_value "${1:-}" "${2:-}")
	lock_transition
	if [ ! -e "$TRANSITION" ]; then
		unlock_transition
		return 1
	fi
	OWNER=
	IFS= read -r OWNER <"$TRANSITION" || :
	case "$OWNER" in
		''|*[!0-9]*) OWNER=0 ;;
	esac
	if [ "$OWNER" -le 0 ] || ! kill -0 "$OWNER" 2>/dev/null; then
		rm -f "$TRANSITION" "$PENDING"
		unlock_transition
		return 1
	fi
	if [ "$REQUEST" = none ]; then
		rm -f "$PENDING"
	else
		printf '%s\n' "$REQUEST" >"$PENDING"
	fi
	unlock_transition
	printf 'bird-suspend stage=queued request=%s\n' "$REQUEST" >>"$LOG"
	return 0
}

begin_resume() {
	lock_transition
	if [ -e "$TRANSITION" ]; then
		unlock_transition
		return 1
	fi
	printf '%s\n' "$$" >"$TRANSITION"
	rm -f "$PENDING"
	unlock_transition
}

finish_resume() {
	QUEUED=none
	lock_transition
	if [ -r "$PENDING" ]; then
		IFS= read -r QUEUED <"$PENDING" || QUEUED=none
	fi
	if [ "$QUEUED" = none ]; then
		rm -f "$PENDING" "$TRANSITION"
	fi
	unlock_transition
	[ "$QUEUED" != none ] || return 0
	BIRD_SUSPEND_HANDOFF=1
	export BIRD_SUSPEND_HANDOFF
	exec "$0"
}

accept_handoff() {
	[ "${BIRD_SUSPEND_HANDOFF:-0}" = 1 ] || return 1
	QUEUED=none
	lock_transition
	if [ -r "$PENDING" ]; then
		IFS= read -r QUEUED <"$PENDING" || QUEUED=none
	fi
	rm -f "$PENDING" "$TRANSITION"
	unlock_transition
	case "$QUEUED" in
		power) set -- power ;;
		lid-close) set -- lid close ;;
		*) exit 0 ;;
	esac
	BIRD_SUSPEND_HANDOFF=0
	export BIRD_SUSPEND_HANDOFF
	HANDOFF_SOURCE=$1
	HANDOFF_ACTION=${2:-}
}

log_brightness() {
	RAW=unavailable
	POWER=unavailable
	if [ -r "$BRIGHTNESS" ]; then
		IFS= read -r RAW <"$BRIGHTNESS"
	fi
	if [ -r "$BL_POWER" ]; then
		IFS= read -r POWER <"$BL_POWER"
	fi
	printf 'bird-suspend stage=%s raw=%s bl_power=%s\n' "$1" "$RAW" "$POWER"
	printf 'bird-suspend stage=%s raw=%s bl_power=%s\n' \
		"$1" "$RAW" "$POWER" >>"$LOG"
}

normalize_saved_lit_level() {
	CANDIDATE=${1:-}
	MAXIMUM=
	[ -r "$MAX_BRIGHTNESS" ] && IFS= read -r MAXIMUM <"$MAX_BRIGHTNESS"
	case "$CANDIDATE:$MAXIMUM" in
		*[!0-9:]*) SAVED=; return ;;
	esac
	[ -n "$CANDIDATE" ] && [ -n "$MAXIMUM" ] && [ "$MAXIMUM" -gt 0 ] || {
		SAVED=
		return
	}
	if [ "$CANDIDATE" -lt 1 ]; then
		# Raw zero is display-off, never a restorable lit level. Recover to
		# the stable one-percent floor if close raced panel blanking.
		CANDIDATE=$(((MAXIMUM + 50) / 100))
		[ "$CANDIDATE" -gt 0 ] || CANDIDATE=1
	elif [ "$CANDIDATE" -gt "$MAXIMUM" ]; then
		CANDIDATE=$MAXIMUM
	fi
	SAVED=$CANDIDATE
}

is_resume() {
	[ "${1:-}" = lid ] && [ "${2:-}" = open ] && return 0
	[ "${1:-}" = power ] && \
		[ -e /var/run/power-fake-suspend-active.flag ] && return 0
	return 1
}

mkdir -p "${LOG%/*}"
HANDOFF_SOURCE=
HANDOFF_ACTION=
if accept_handoff; then
	:
elif queue_while_resuming "${1:-}" "${2:-}"; then
	exit 0
fi
[ -z "$HANDOFF_SOURCE" ] || set -- "$HANDOFF_SOURCE" "$HANDOFF_ACTION"
if is_resume "${1:-}" "${2:-}"; then
	while ! begin_resume; do
		if queue_while_resuming "${1:-}" "${2:-}"; then
			exit 0
		fi
	done
	SAVED=
	[ -r "$STATE" ] && IFS= read -r SAVED <"$STATE"
	normalize_saved_lit_level "$SAVED"
	log_brightness resume-request
	# The retained provider kills every rocknix-fake-suspend process as the final
	# resume action, including this child. The wrapper survives that expected
	# signal and restores the exact pre-suspend raw level afterward.
	"$STOCK" "$@" || :
	case "$SAVED" in
		''|*[!0-9]*) ;;
		*)
			# The physical gate proves that dim PWM levels remain visible once
			# running but cannot start this panel after DPMS. Raw 250 at max 2499
			# (10 percent) is the first reliable wake level. Strike there for a
			# bounded 50 ms, then restore the exact saved dim value.
			STRIKE=$(((MAXIMUM * 10 + 50) / 100))
			[ "$STRIKE" -gt 0 ] || STRIKE=1
			[ -w "$BL_POWER" ] && printf '0\n' >"$BL_POWER"
			if [ "$SAVED" -lt "$STRIKE" ]; then
				[ -w "$BRIGHTNESS" ] && printf '%s\n' "$STRIKE" >"$BRIGHTNESS"
				log_brightness wake-strike
				"$SETTLE" 50000 2>/dev/null || :
			fi
			[ -w "$BRIGHTNESS" ] && printf '%s\n' "$SAVED" >"$BRIGHTNESS"
			;;
	esac
	rm -f "$STATE"
	log_brightness restored
	finish_resume
	exit 0
fi

: >"$LOG"
if [ -r "$BRIGHTNESS" ]; then
	IFS= read -r SAVED <"$BRIGHTNESS"
	normalize_saved_lit_level "$SAVED"
	case "$SAVED" in
		''|*[!0-9]*) ;;
		*)
			mkdir -p "${STATE%/*}"
			printf '%s\n' "$SAVED" >"$STATE"
			;;
	esac
fi
log_brightness saved
exec "$STOCK" "$@"
