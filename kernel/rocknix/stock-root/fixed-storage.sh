#!/bin/bash
# Publish this RG34XX-SP's one known content volume at ROCKNIX's compatibility
# path. This replaces generic partition discovery without coupling storage work
# to the launcher.

set -u

ROM_SOURCE=/storage/bird-data/ROMS
MEDIA_SOURCE=/storage/bird-data/MEDIA
ROM_TARGET=/storage/roms
MEDIA_TARGET=/storage/media
LOG_DIR=/storage/bird-data/Bird/log
LOG=$LOG_DIR/fixed-storage-latest.log

mkdir -p "$LOG_DIR" /run/bird "$ROM_TARGET" "$MEDIA_TARGET" || exit 1
exec >"$LOG" 2>&1

printf 'Bird fixed storage start uptime='
cut -d ' ' -f 1 /proc/uptime

[ -d "$ROM_SOURCE" ] || {
	printf 'Missing fixed ROM source: %s\n' "$ROM_SOURCE"
	exit 1
}
[ -d "$MEDIA_SOURCE" ] || {
	printf 'Missing fixed media source: %s\n' "$MEDIA_SOURCE"
	exit 1
}

# The initramfs normally installed this view already. If any compatibility
# service stacked another mount over it, peel every wrong layer and restore the
# one fixed source.
while [ ! "$ROM_TARGET" -ef "$ROM_SOURCE" ]; do
	if umount "$ROM_TARGET" 2>/dev/null; then
		continue
	fi
	mount --bind "$ROM_SOURCE" "$ROM_TARGET" || exit 1
done

# Bind views can carry per-mount noexec state independently. Make the native
# PortMaster contract explicit even when this service is restarted later.
mount -o remount,bind,rw,exec "$ROM_TARGET" || exit 1

while [ ! "$MEDIA_TARGET" -ef "$MEDIA_SOURCE" ]; do
	if umount "$MEDIA_TARGET" 2>/dev/null; then
		continue
	fi
	mount --bind "$MEDIA_SOURCE" "$MEDIA_TARGET" || exit 1
done

[ "$ROM_TARGET" -ef "$ROM_SOURCE" ] || exit 1
[ "$MEDIA_TARGET" -ef "$MEDIA_SOURCE" ] || exit 1

printf '%s\n' 'Bird fixed storage mount state:'
grep -E ' /storage/(bird-data|roms|media) ' /proc/mounts || :
printf 'Bird fixed storage ready uptime='
cut -d ' ' -f 1 /proc/uptime
