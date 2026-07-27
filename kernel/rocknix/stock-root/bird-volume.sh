#!/bin/sh
# ROCKNIX stores the numeric volume and the WirePlumber route mute separately.
# Keep its canonical volume helper, then make every explicit Bird volume action
# audible by clearing a stale mute on the selected internal sink.

set -eu

/usr/bin/volume "${1:-restore}"
pactl -- set-sink-mute @DEFAULT_SINK@ 0
