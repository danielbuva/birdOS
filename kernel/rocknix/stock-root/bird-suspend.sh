#!/bin/sh
# Preserve Bird's exact fixed-panel level around ROCKNIX's retained fake
# suspend transaction. The provider owns audio, input, governors and LEDs;
# this wrapper narrows the display contract to one RG34XX-SP backlight.

BACKLIGHT=${BIRD_BACKLIGHT:-/sys/class/backlight/backlight}
BRIGHTNESS=$BACKLIGHT/brightness
BL_POWER=$BACKLIGHT/bl_power
MAX_BRIGHTNESS=$BACKLIGHT/max_brightness
STATE=${BIRD_SUSPEND_STATE:-/run/bird/bird-pre-suspend-brightness}
STOCK=${BIRD_SUSPEND_PROVIDER:-/usr/bin/rocknix-fake-suspend}
LOG=${BIRD_SUSPEND_LOG:-/storage/bird-data/Bird/log/suspend-latest.log}
SETTLE=${BIRD_SUSPEND_SETTLE:-/usr/bin/usleep}
RESUME_READY=${BIRD_SUSPEND_RESUME_READY:-/run/bird/bird-suspend-resume-ready}
UPTIME=${BIRD_SUSPEND_UPTIME:-/proc/uptime}

log_brightness() {
	snapshot_brightness
	emit_brightness "$1" "$RAW" "$POWER" "$BOOTTIME"
}

snapshot_brightness() {
	RAW=unavailable
	POWER=unavailable
	BOOTTIME=unavailable
	if [ -r "$BRIGHTNESS" ]; then
		IFS= read -r RAW <"$BRIGHTNESS"
	fi
	if [ -r "$BL_POWER" ]; then
		IFS= read -r POWER <"$BL_POWER"
	fi
	if [ -r "$UPTIME" ]; then
		IFS=' ' read -r BOOTTIME _ <"$UPTIME" || BOOTTIME=unavailable
		case "$BOOTTIME" in
			''|*[!0-9.]*) BOOTTIME=unavailable ;;
		esac
	fi
	# The original brightness log was deliberately limited to proving the
	# panel wake/restore sequence.  Append CLOCK_BOOTTIME-like /proc/uptime
	# evidence now so a delayed provider return can be separated from a late
	# panel restore without adding a timer or an idle wakeup.
	:
}

emit_brightness() {
	printf 'bird-suspend stage=%s raw=%s bl_power=%s boottime_s=%s\n' \
		"$1" "$2" "$3" "$4"
	printf 'bird-suspend stage=%s raw=%s bl_power=%s boottime_s=%s\n' \
		"$1" "$2" "$3" "$4" >>"$LOG"
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

mkdir -p "${LOG%/*}" "${RESUME_READY%/*}"
if is_resume "${1:-}" "${2:-}"; then
	rm -f "$RESUME_READY"
	SAVED=
	[ -r "$STATE" ] && IFS= read -r SAVED <"$STATE"
	normalize_saved_lit_level "$SAVED"
	log_brightness resume-request
	# The retained provider kills every rocknix-fake-suspend process as the final
	# resume action, including this child. The wrapper survives that expected
	# signal and restores the exact pre-suspend raw level afterward.
	"$STOCK" "$@" || :
	# Snapshot provider return immediately, but do not put persistent logging
	# ahead of the panel restore or resume-ready handoff.  Emit the preserved
	# observation only after the display is restored and the coordinator can
	# proceed.
	snapshot_brightness
	PROVIDER_RAW=$RAW
	PROVIDER_POWER=$POWER
	PROVIDER_BOOTTIME=$BOOTTIME
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
	: >"$RESUME_READY"
	emit_brightness provider-return "$PROVIDER_RAW" "$PROVIDER_POWER" \
		"$PROVIDER_BOOTTIME"
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
