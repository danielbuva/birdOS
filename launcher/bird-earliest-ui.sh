#!/bin/sh

# BusyBox inittab invokes this immediately after its essential mount pass and
# before the generic rcS tree. Failure is deliberately non-fatal: normal rcS
# still invokes S03birdlauncher as the stock-compatible fallback.
FIRST_FRAME_MARKER="/run/muos/bird-first-frame-ready"
COUNT=0

/opt/muos/script/init/S03birdlauncher start || exit 0

while [ ! -e "$FIRST_FRAME_MARKER" ]; do
	COUNT=$((COUNT + 1))
	[ "$COUNT" -ge 500 ] && exit 0
	sleep 0.001
done

exit 0
