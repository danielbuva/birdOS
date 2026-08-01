#!/bin/sh
# Reconcile the fixed RG34XX-SP audio state without waking a suspended codec
# merely to rewrite values it already has.

set -u

ACTION=${1:-restore}
if [ "$ACTION" != restore ]; then
	/usr/bin/volume "$ACTION" || exit 1
	pactl -- set-sink-mute @DEFAULT_SINK@ 0 || exit 1
	exit 0
fi

CONFIG=/storage/.config/system/configs/system.cfg

saved_volume() {
	[ -r "$CONFIG" ] || {
		printf '%s\n' 50
		return
	}
	awk -F= '
		$1 == "system.audio.volume" { system = $2 }
		$1 == "audio.volume" { local = $2 }
		$1 == "global.audio.volume" { global = $2 }
		END {
			if (system != "") print system
			else if (local != "") print local
			else if (global != "") print global
			else print 50
		}
	' "$CONFIG"
}

DESIRED_VOLUME=$(saved_volume 2>/dev/null || printf '%s\n' 50)
case "$DESIRED_VOLUME" in
	''|*[!0-9]*) DESIRED_VOLUME=50 ;;
	*)
		[ "$DESIRED_VOLUME" -le 100 ] 2>/dev/null || DESIRED_VOLUME=50
		;;
esac

JACK_CONTROL=$(/usr/bin/amixer -c 0 cget "name='Headphone Jack'" 2>/dev/null || :)
SPEAKER_CONTROL=$(/usr/bin/amixer -c 0 cget "name='Speaker Switch'" 2>/dev/null || :)
JACK_STATE=unknown
SPEAKER_STATE=unknown
ROUTE_ACTION=unchanged
case "$JACK_CONTROL" in
	*'values=on'*) JACK_STATE=on; REQUIRED_SPEAKER=off ;;
	*'values=off'*) JACK_STATE=off; REQUIRED_SPEAKER=on ;;
	*) REQUIRED_SPEAKER=unknown; ROUTE_ACTION=inspect-failed ;;
esac
case "$SPEAKER_CONTROL" in
	*'values=on'*) SPEAKER_STATE=on ;;
	*'values=off'*) SPEAKER_STATE=off ;;
esac
if [ "$REQUIRED_SPEAKER" != unknown ]; then
	if [ "$SPEAKER_STATE" = unknown ]; then
		ROUTE_ACTION=inspect-failed
	elif [ "$SPEAKER_STATE" != "$REQUIRED_SPEAKER" ]; then
		# The sink is normally suspended here. Do not wake it with a PulseAudio
		# mute write before changing the independent fixed speaker amplifier.
		if /usr/bin/amixer -q -c 0 cset "name='Speaker Switch'" \
			"$REQUIRED_SPEAKER"; then
			ROUTE_ACTION=changed
		else
			ROUTE_ACTION=change-failed
		fi
	fi
fi

VOLUME_OUTPUT=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null || :)
CURRENT_VOLUME=$(printf '%s\n' "$VOLUME_OUTPUT" | sed -n \
	'1s#.* /[[:space:]]*\([0-9][0-9]*\)%.*#\1#p')
MUTE_OUTPUT=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null || :)
case "$MUTE_OUTPUT" in
	*': yes') CURRENT_MUTE=yes ;;
	*': no') CURRENT_MUTE=no ;;
	*) CURRENT_MUTE=unknown ;;
esac

VOLUME_ACTION=unchanged
if [ -z "$CURRENT_VOLUME" ]; then
	VOLUME_ACTION=inspect-failed
elif [ "$CURRENT_VOLUME" != "$DESIRED_VOLUME" ]; then
	if /usr/bin/volume restore; then
		VOLUME_ACTION=changed
	else
		VOLUME_ACTION=change-failed
	fi
fi

MUTE_ACTION=unchanged
case "$CURRENT_MUTE" in
	yes)
		if pactl -- set-sink-mute @DEFAULT_SINK@ 0; then
			MUTE_ACTION=changed
		else
			MUTE_ACTION=change-failed
		fi
		;;
	unknown) MUTE_ACTION=inspect-failed ;;
esac

printf 'Bird audio restore jack=%s speaker=%s route=%s desired_volume=%s current_volume=%s volume=%s mute=%s mute_action=%s\n' \
	"$JACK_STATE" "$SPEAKER_STATE" "$ROUTE_ACTION" "$DESIRED_VOLUME" \
	"${CURRENT_VOLUME:-unknown}" "$VOLUME_ACTION" "$CURRENT_MUTE" "$MUTE_ACTION"

# Audio policy failures are recorded above. They must never prevent a game,
# reader, or other non-audio provider from launching.
exit 0
