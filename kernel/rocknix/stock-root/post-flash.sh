#!/bin/sh
# Keep ROCKNIX's initramfs and SYSTEM unchanged. The small BIRD partition only
# supplies this hook so the exact release SYSTEM and writable storage image can
# live on the existing large data partition.

BIRD_DATA_DEVICE=/dev/mmcblk0p6
BIRD_DATA_MOUNT=/birddata
BIRD_SYSTEM_REL=MUOS/runtime/ROCKNIX-SYSTEM
BIRD_STORAGE_REL=MUOS/runtime/ROCKNIX-STORAGE
BIRD_STATE_REL=MUOS/Bird/boot-state
BIRD_ATTEMPTS_REL=$BIRD_STATE_REL/stock-root-attempts

mkdir -p "$BIRD_DATA_MOUNT"
mount -t exfat -o rw,noatime "$BIRD_DATA_DEVICE" "$BIRD_DATA_MOUNT" || {
	error bird-data "Could not mount $BIRD_DATA_DEVICE"
	return 1
}

SYSTEM_SOURCE=$BIRD_DATA_MOUNT/$BIRD_SYSTEM_REL
STORAGE_SOURCE=$BIRD_DATA_MOUNT/$BIRD_STORAGE_REL
STATE_DIR=$BIRD_DATA_MOUNT/$BIRD_STATE_REL
ATTEMPTS_FILE=$BIRD_DATA_MOUNT/$BIRD_ATTEMPTS_REL

[ -f "$SYSTEM_SOURCE" ] || {
	error bird-system "Missing $SYSTEM_SOURCE"
	return 1
}
[ -f "$STORAGE_SOURCE" ] || {
	error bird-storage "Missing $STORAGE_SOURCE"
	return 1
}

mkdir -p "$STATE_DIR"
ATTEMPTS=0
[ -s "$ATTEMPTS_FILE" ] && ATTEMPTS=$(cat "$ATTEMPTS_FILE")
case "$ATTEMPTS" in *[!0-9]*|'') ATTEMPTS=0 ;; esac
ATTEMPTS=$((ATTEMPTS + 1))
printf '%s\n' "$ATTEMPTS" >"$ATTEMPTS_FILE"
sync

# Two failed full-stack starts are enough evidence to return to the preserved
# clean-root kernel. The fallback is selected before the third candidate boot.
if [ "$ATTEMPTS" -ge 3 ]; then
	mount -o remount,rw /flash
	cp -f /flash/extlinux/extlinux.fallback.conf /flash/extlinux/extlinux.conf
	sync
	reboot -f
	return 1
fi

# /flash/SYSTEM is an empty mount target on the small FAT partition. Bind the
# exact immutable image over it so the unmodified ROCKNIX mount_sysroot path is
# used without copying or repacking SYSTEM.
mount --bind "$SYSTEM_SOURCE" /flash/SYSTEM || {
	error bird-system-bind "Could not bind exact ROCKNIX SYSTEM"
	return 1
}

export BIRD_DATA_MOUNT BIRD_STORAGE_REL BIRD_ATTEMPTS_REL
