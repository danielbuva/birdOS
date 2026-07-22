#!/bin/sh
# One Bird-owned exit contract for every application. The controls service
# invokes this only while Select+Start are held and a content marker exists.

NAMES="retroarch retroarch32 mpv ppsspp"
/usr/bin/killall -TERM $NAMES 2>/dev/null || :

# Let applications flush saves and tear down DRM/ALSA, but never let a broken
# client strand Bird. Most exits complete on the first few 10 ms checks.
COUNT=0
while [ "$COUNT" -lt 100 ]; do
	RUNNING=
	for NAME in $NAMES; do
		/bin/pidof "$NAME" >/dev/null 2>&1 && RUNNING=1
	done
	[ -n "$RUNNING" ] || exit 0
	COUNT=$((COUNT + 1))
	/bin/usleep 10000
done

/usr/bin/killall -KILL $NAMES 2>/dev/null || :
exit 0
