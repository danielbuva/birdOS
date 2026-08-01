#!/bin/sh
# ROCKNIX stores the numeric volume and the WirePlumber route mute separately.
# Keep its canonical volume helper, then make every explicit Bird volume action
# audible by clearing a stale mute on the selected internal sink.

set -eu

ACTION=${1:-restore}
/usr/bin/volume "$ACTION"
pactl -- set-sink-mute @DEFAULT_SINK@ 0

# WirePlumber can start after a headphone jack is already asserted and select
# the correct headphone sink without running the UCM transition that disables
# the fixed internal speaker. Reconcile once at each existing restore boundary;
# volume-button actions remain on their accepted path and hotplug stays owned
# by WirePlumber.
[ "$ACTION" = restore ] || exit 0
JACK_STATE=$(/usr/bin/amixer -c 0 cget "name='Headphone Jack'" 2>/dev/null)
case "$JACK_STATE" in
	*'values=on'*) SPEAKER_STATE=off ;;
	*'values=off'*) SPEAKER_STATE=on ;;
	*) exit 1 ;;
esac
/usr/bin/amixer -q -c 0 cset "name='Speaker Switch'" "$SPEAKER_STATE"
