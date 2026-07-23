#!/bin/bash
# Publish this RG34XX-SP's one known content volume at ROCKNIX's compatibility
# path. This replaces generic partition discovery without coupling storage work
# to the launcher.

set -u

ROM_SOURCE=/storage/bird-data/ROMS
BIOS_SOURCE=/storage/bird-data/MUOS/bios
ROM_TARGET=/storage/roms
BIOS_TARGET=$ROM_TARGET/bios
LOG_DIR=/storage/bird-data/MUOS/Bird/log
LOG=$LOG_DIR/fixed-storage-latest.log

mkdir -p "$LOG_DIR" /run/bird "$ROM_TARGET" || exit 1
exec >"$LOG" 2>&1

printf 'Bird fixed storage start uptime='
cut -d ' ' -f 1 /proc/uptime

[ -d "$ROM_SOURCE" ] || {
	printf 'Missing fixed ROM source: %s\n' "$ROM_SOURCE"
	exit 1
}
[ -d "$BIOS_SOURCE" ] || {
	printf 'Missing fixed BIOS source: %s\n' "$BIOS_SOURCE"
	exit 1
}

# The initramfs normally installed this view already. If any compatibility
# service stacked another mount over it, peel every wrong layer and restore the
# one fixed source.
while [ ! "$ROM_TARGET" -ef "$ROM_SOURCE" ]; do
	# A wrong parent layer can hide the correct parent and its nested BIOS
	# mount. Peel one visible layer at a time and stop as soon as the original
	# fixed view is revealed.
	if mountpoint -q "$BIOS_TARGET"; then
		# The mount table may still name a BIOS child hidden below a stacked
		# parent; that hidden child cannot be addressed until the parent peels.
		umount "$BIOS_TARGET" 2>/dev/null || :
	fi
	if mountpoint -q "$ROM_TARGET"; then
		umount "$ROM_TARGET" || exit 1
	else
		mount --bind "$ROM_SOURCE" "$ROM_TARGET" || exit 1
	fi
done

# Bind views can carry per-mount noexec state independently. Make the native
# PortMaster contract explicit even when this service is restarted later.
mount -o remount,bind,rw,exec "$ROM_TARGET" || exit 1

mkdir -p "$BIOS_TARGET" || exit 1
while [ ! "$BIOS_TARGET" -ef "$BIOS_SOURCE" ]; do
	if mountpoint -q "$BIOS_TARGET"; then
		umount "$BIOS_TARGET" || exit 1
	else
		mount --bind "$BIOS_SOURCE" "$BIOS_TARGET" || exit 1
	fi
done

[ "$ROM_TARGET" -ef "$ROM_SOURCE" ] || exit 1
[ "$BIOS_TARGET" -ef "$BIOS_SOURCE" ] || exit 1

printf '%s\n' 'Bird fixed storage mount state:'
grep -E ' /storage/(bird-data|roms) ' /proc/mounts || :
printf 'Bird fixed storage ready uptime='
cut -d ' ' -f 1 /proc/uptime
