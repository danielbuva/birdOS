#!/bin/sh
# Publish the one H700 controller profile without running control-gen,
# xmlstarlet, uuidgen and per-input awk processes on every boot.

set -eu

SOURCE=${BIRD_CONTROLLER_SOURCE:-/flash/bird/bird-controller-profile}
TARGET=${BIRD_CONTROLLER_TARGET:-/storage/.config/profile.d/098-controller}
SYSTEM_BUSYBOX=${BIRD_SYSTEM_BUSYBOX:-/usr/bin/busybox}
TEMP=$TARGET.bird-new

if "$SYSTEM_BUSYBOX" cmp -s "$SOURCE" "$TARGET"; then
	exit 0
fi

mkdir -p "${TARGET%/*}"
"$SYSTEM_BUSYBOX" rm -f "$TEMP"
"$SYSTEM_BUSYBOX" cp -f "$SOURCE" "$TEMP"
"$SYSTEM_BUSYBOX" chmod 0644 "$TEMP"
"$SYSTEM_BUSYBOX" mv -f "$TEMP" "$TARGET"
