#!/bin/sh
# One Bird-owned exit contract for every application. The controls service
# invokes this only while Select+Start are held and a content marker exists.

/usr/bin/killall -TERM retroarch retroarch32 mpv ppsspp 2>/dev/null || :
/bin/usleep 150000
/usr/bin/killall -KILL retroarch retroarch32 mpv ppsspp 2>/dev/null || :
exit 0
