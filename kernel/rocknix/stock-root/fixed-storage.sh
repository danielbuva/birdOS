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

log_uptime() {
	local LABEL=$1 NOW UNUSED
	NOW=unknown
	IFS=' ' read -r NOW UNUSED </proc/uptime || NOW=unknown
	printf '%s%s\n' "$LABEL" "$NOW"
}

rom_mount_options() {
	local SOURCE TARGET TYPE OPTIONS DUMP PASS
	ROM_MOUNT_OPTIONS=
	while IFS=' ' read -r SOURCE TARGET TYPE OPTIONS DUMP PASS; do
		[ "$TARGET" = "$ROM_TARGET" ] || continue
		# A later record at the same target is the visible stacked mount.
		ROM_MOUNT_OPTIONS=$OPTIONS
	done </proc/mounts
	[ -n "$ROM_MOUNT_OPTIONS" ]
}

mount_option_present() {
	case ",$1," in
		*,$2,*) return 0 ;;
	esac
	return 1
}

rom_mount_is_rw_exec() {
	rom_mount_options || return 1
	mount_option_present "$ROM_MOUNT_OPTIONS" rw || return 1
	# Linux records exec as the absence of the per-mount noexec flag.
	! mount_option_present "$ROM_MOUNT_OPTIONS" noexec
}

log_fixed_mounts() {
	local SOURCE TARGET TYPE OPTIONS DUMP PASS
	while IFS=' ' read -r SOURCE TARGET TYPE OPTIONS DUMP PASS; do
		case "$TARGET" in
			/storage/bird-data|/storage/roms|/storage/media)
				printf '%s %s %s %s %s %s\n' \
					"$SOURCE" "$TARGET" "$TYPE" "$OPTIONS" \
					"$DUMP" "$PASS"
				;;
		esac
	done </proc/mounts
}

for REQUIRED_DIR in "$LOG_DIR" /run/bird; do
	[ -d "$REQUIRED_DIR" ] || mkdir -p "$REQUIRED_DIR" || exit 1
done
exec >"$LOG" 2>&1

log_uptime 'Bird fixed storage start uptime='
STORAGE_REPAIRED=0

[ -d "$ROM_SOURCE" ] || {
	printf 'Missing fixed ROM source: %s\n' "$ROM_SOURCE"
	exit 1
}
[ -d "$MEDIA_SOURCE" ] || {
	printf 'Missing fixed media source: %s\n' "$MEDIA_SOURCE"
	exit 1
}

for REQUIRED_DIR in "$ROM_TARGET" "$MEDIA_TARGET"; do
	[ -d "$REQUIRED_DIR" ] || mkdir -p "$REQUIRED_DIR" || exit 1
done

# The initramfs normally installed this view already. If any compatibility
# service stacked another mount over it, peel every wrong layer and restore the
# one fixed source.
while [ ! "$ROM_TARGET" -ef "$ROM_SOURCE" ]; do
	STORAGE_REPAIRED=1
	if umount "$ROM_TARGET" 2>/dev/null; then
		continue
	fi
	mount --bind "$ROM_SOURCE" "$ROM_TARGET" || exit 1
done

# Bind views can carry per-mount read-only or noexec state independently. The
# initramfs publishes this one as rw+exec, so preserve the ordinary accepted
# state without another mount syscall or namespace change. Repair only an
# incorrect view so native PortMaster scripts remain executable.
if ! rom_mount_is_rw_exec; then
	STORAGE_REPAIRED=1
	mount -o remount,bind,rw,exec "$ROM_TARGET" || exit 1
	rom_mount_is_rw_exec || exit 1
fi

while [ ! "$MEDIA_TARGET" -ef "$MEDIA_SOURCE" ]; do
	STORAGE_REPAIRED=1
	if umount "$MEDIA_TARGET" 2>/dev/null; then
		continue
	fi
	mount --bind "$MEDIA_SOURCE" "$MEDIA_TARGET" || exit 1
done

[ "$ROM_TARGET" -ef "$ROM_SOURCE" ] || exit 1
[ "$MEDIA_TARGET" -ef "$MEDIA_SOURCE" ] || exit 1

if [ "$STORAGE_REPAIRED" -eq 1 ]; then
	printf '%s\n' 'Bird fixed storage state=repaired'
	log_fixed_mounts
else
	printf '%s\n' 'Bird fixed storage state=accepted'
fi
log_uptime 'Bird fixed storage ready uptime='
