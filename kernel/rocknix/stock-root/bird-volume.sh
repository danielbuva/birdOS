#!/bin/sh
# ROCKNIX stores the numeric volume and the WirePlumber route mute separately.
# Keep its canonical volume helper, then make every explicit Bird volume action
# audible by clearing a stale mute on the selected internal sink.

set -eu

ACTION=${1:-restore}
if [ "$ACTION" != restore ]; then
	/usr/bin/volume "$ACTION"
	pactl -- set-sink-mute @DEFAULT_SINK@ 0
	exit 0
fi

# A boot with the jack already asserted can miss WirePlumber's UCM transition.
# Inspect both fixed controls and never rewrite an already-correct amplifier
# switch: even a same-value cset can produce an audible codec transient.
JACK_CONTROL=$(/usr/bin/amixer -c 0 cget "name='Headphone Jack'" 2>/dev/null)
SPEAKER_CONTROL=$(/usr/bin/amixer -c 0 cget "name='Speaker Switch'" 2>/dev/null)
case "$JACK_CONTROL" in
	*'values=on'*) REQUIRED_SPEAKER=off ;;
	*'values=off'*) REQUIRED_SPEAKER=on ;;
	*) exit 1 ;;
esac
case "$SPEAKER_CONTROL" in
	*"values=$REQUIRED_SPEAKER"*) ROUTE_CHANGE=0 ;;
	*'values=on'*|*'values=off'*) ROUTE_CHANGE=1 ;;
	*) exit 1 ;;
esac

if [ "$ROUTE_CHANGE" -eq 1 ]; then
	pactl -- set-sink-mute @DEFAULT_SINK@ 1 || exit 1
	if ! /usr/bin/amixer -q -c 0 cset "name='Speaker Switch'" \
		"$REQUIRED_SPEAKER"; then
		pactl -- set-sink-mute @DEFAULT_SINK@ 0 || :
		exit 1
	fi
fi

if ! /usr/bin/volume restore; then
	[ "$ROUTE_CHANGE" -eq 0 ] || \
		pactl -- set-sink-mute @DEFAULT_SINK@ 0 || :
	exit 1
fi
pactl -- set-sink-mute @DEFAULT_SINK@ 0
