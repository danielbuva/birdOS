#!/bin/sh

[ -x /opt/bird/supervisor.sh ] && /opt/bird/supervisor.sh stop || :
killall -TERM retroarch mpv bird-controls 2>/dev/null || :
sync

for POINT in \
	/run/bird-runtime/storage \
	/run/bird-runtime/run \
	/run/bird-runtime/sys \
	/run/bird-runtime/proc \
	/run/bird-runtime/dev \
	/run/bird-runtime \
	/mnt/mmc; do
	umount "$POINT" 2>/dev/null || :
done
sync
exit 0
