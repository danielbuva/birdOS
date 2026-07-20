#!/bin/sh

# Exact RG34XX-SP storage policy: the only content device is the OS card's
# sixth partition, it is always exFAT, and it always mounts at /mnt/mmc.
DEVICE="/dev/mmcblk0p6"
DISK="mmcblk0"
MOUNT_POINT="/mnt/mmc"
LOCK_DIR="/tmp/muos/rom-mount.lock"
STAGES="/tmp/muos/fixed-mount.tsv"
BOOT_TIMING="/tmp/muos/boot-timing.tsv"

mkdir -p /tmp/muos

mark() {
	IFS=' ' read -r NOW _ </proc/uptime
	printf '%s\t%s\n' "$NOW" "$1" >>"$STAGES"
}

timing_event() {
	[ -f "$BOOT_TIMING" ] || return 0
	IFS= read -r BOOT_ID </proc/sys/kernel/random/boot_id
	IFS=' ' read -r NOW _ </proc/uptime
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$BOOT_ID" "$NOW" "$1" "mount" "$2" "${3:-0}" >>"$BOOT_TIMING"
}

is_mounted() {
	grep -qs " $MOUNT_POINT " /proc/mounts
}

post_mount_policy() {
	# Compatibility state and tunables are not prerequisites for exposing ROMS.
	# Apply them after the mount is visible to the launcher.
	. /opt/muos/script/var/func.sh
	SET_VAR "device" "storage/rom/active" "1"
	SET_VAR "device" "storage/rom/label" "dani-sp"

	CARD_MODE=$(GET_VAR "config" "danger/cardmode")
	if [ -e "/sys/block/$DISK/queue/scheduler" ]; then
		if [ "$CARD_MODE" = "noop" ]; then
			echo noop >"/sys/block/$DISK/queue/scheduler" 2>/dev/null || :
			echo 'write back' >"/sys/block/$DISK/queue/write_cache" 2>/dev/null || :
		else
			echo deadline >"/sys/block/$DISK/queue/scheduler" 2>/dev/null || :
			echo 'write through' >"/sys/block/$DISK/queue/write_cache" 2>/dev/null || :
		fi
	fi
	KERNEL_TUNING "$DISK"
	mark fixed-mount-policy-complete
}

mount_rom() {
	ROLE=stock
	[ "${MUOS_EARLY_ROM_MOUNT:-0}" -eq 1 ] && ROLE=early
	timing_event request "rom_mount_fixed_$ROLE" 0
	mark "fixed-mount-$ROLE-request"

	if is_mounted; then
		timing_event ready "rom_mount_fixed_${ROLE}_already_mounted" 0
		mark "fixed-mount-$ROLE-already-ready"
		return 0
	fi

	COUNT=0
	while [ ! -b "$DEVICE" ] && [ "$COUNT" -lt 100 ]; do
		COUNT=$((COUNT + 1))
		sleep 0.05
	done
	[ -b "$DEVICE" ] || {
		mark fixed-mount-device-timeout
		return 1
	}

	WAIT_COUNT=0
	while ! mkdir "$LOCK_DIR" 2>/dev/null; do
		if is_mounted; then
			timing_event ready "rom_mount_fixed_${ROLE}_after_wait" 0
			mark "fixed-mount-$ROLE-ready-after-wait"
			return 0
		fi
		WAIT_COUNT=$((WAIT_COUNT + 1))
		[ "$WAIT_COUNT" -lt 200 ] || {
			mark fixed-mount-lock-timeout
			return 1
		}
		sleep 0.05
	done

	release_lock() {
		rmdir "$LOCK_DIR" 2>/dev/null || :
	}
	trap release_lock 0 1 2 15

	if is_mounted; then
		mark "fixed-mount-$ROLE-ready-after-lock"
		return 0
	fi

	mkdir -p "$MOUNT_POINT"
	timing_event start "rom_mount_fixed_$ROLE" 0
	mark "fixed-mount-$ROLE-start"
	if ! mount -t exfat -o rw,utf8,noatime,nofail "$DEVICE" "$MOUNT_POINT"; then
		timing_event end "rom_mount_fixed_$ROLE" 1
		mark fixed-mount-failed
		return 1
	fi
	timing_event end "rom_mount_fixed_$ROLE" 0
	mark "fixed-mount-$ROLE-visible"

	mkdir -p "$MOUNT_POINT/ROMS" "$MOUNT_POINT/BACKUP" \
		"$MOUNT_POINT/ARCHIVE" "$MOUNT_POINT/ports"
	post_mount_policy &
	return 0
}

unmount_rom() {
	is_mounted || return 0
	sync
	umount "$MOUNT_POINT" 2>/dev/null || umount -l "$MOUNT_POINT" 2>/dev/null
}

TYPE="${1:-}"
ACTION="${2:-}"

case "$TYPE:$ACTION" in
	rom:mount) mount_rom ;;
	rom:status) is_mounted ;;
	rom:eject | rom:down) unmount_rom ;;
	sdcard:mount | usb:mount)
		# These storage classes do not exist in the fixed device experience.
		exit 0
		;;
	sdcard:down | sdcard:eject | usb:down | usb:eject) exit 0 ;;
	sdcard:status | usb:status) exit 1 ;;
	*)
		printf 'Usage: %s <rom|sdcard|usb> <mount|eject|down|status>\n' "$0" >&2
		exit 2
		;;
esac

