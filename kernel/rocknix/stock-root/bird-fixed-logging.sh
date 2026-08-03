#!/bin/sh
# Preserve RetroArch's expected volatile log target without deleting and
# recreating the same writable-storage link on every boot.

set -eu

LOG_DIR=${BIRD_RETROARCH_LOG_DIR:-/var/log/retroarch}
LINK=${BIRD_RETROARCH_LOG_LINK:-/storage/.config/retroarch/logs}

[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
if [ -L "$LINK" ] && [ "$LINK" -ef "$LOG_DIR" ]; then
	exit 0
fi

rm -rf "$LINK"
ln -s "$LOG_DIR" "$LINK"
