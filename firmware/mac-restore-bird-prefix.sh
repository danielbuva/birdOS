#!/bin/sh
# Restore the exact accepted Bird GPT/boot prefix after the source-kernel gate.
# Root and data partitions are deliberately not rewritten.

set -eu

DEVICE=${1:-}
ACTION=${2:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}
RECOVERY_PREFIX=${RECOVERY_PREFIX:-/Users/dani/muos-kernel-source/checkpoints/20260721-bird-current-prefix.img}

PREFIX_BYTES=163577856
RECOVERY_SHA=0bcacc83bf7345306ef7615be1012b5c7dd0a92630cf764f34b049f88e9b9f78
DISK_BYTES=512074186752
ROOT_OFFSET=163577856
ROOT_BYTES=8589934592
DATA_OFFSET=8753512448
DATA_BYTES=503320672768

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

plist_value() {
	diskutil info -plist "$1" | plutil -extract "$2" raw -o - -
}

[ -n "$DEVICE" ] && [ "$ACTION" = '--restore-bird-prefix' ] ||
	fail "usage: $0 /dev/diskN --restore-bird-prefix"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v diskutil >/dev/null 2>&1 || fail 'diskutil is required'
command -v plutil >/dev/null 2>&1 || fail 'plutil is required'
[ -f "$RECOVERY_PREFIX" ] ||
	fail "local recovery prefix missing: $RECOVERY_PREFIX"
[ "$(stat -f %z "$RECOVERY_PREFIX")" -eq "$PREFIX_BYTES" ] ||
	fail 'local recovery prefix size mismatch'
[ "$(shasum -a 256 "$RECOVERY_PREFIX" | awk '{print $1}')" = "$RECOVERY_SHA" ] ||
	fail 'local recovery prefix checksum mismatch'

WHOLE=${DEVICE#/dev/}
case "$WHOLE" in
disk[0-9]*) ;;
*) fail 'device must be a whole disk such as /dev/disk4' ;;
esac
[ "$(plist_value "/dev/$WHOLE" Internal)" = false ] ||
	fail 'refusing an internal disk'
[ "$(plist_value "/dev/$WHOLE" Removable)" = true ] ||
	fail 'refusing non-removable media'
[ "$(plist_value "/dev/$WHOLE" Size)" = "$DISK_BYTES" ] ||
	fail 'unexpected card size'

RAW_DISK="/dev/r$WHOLE"
MOUNTED=1
cleanup() {
	if [ "$MOUNTED" -eq 0 ]; then
		diskutil mountDisk "/dev/$WHOLE" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT HUP INT TERM

printf 'Restoring the exact accepted Bird prefix to %s...\n' "$RAW_DISK"
diskutil unmountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=0
sudo "$GDD" if="$RECOVERY_PREFIX" of="$RAW_DISK" bs=4M \
	conv=fsync,notrunc status=progress
DEVICE_SHA=$(sudo "$GDD" if="$RAW_DISK" bs=4M count="$PREFIX_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')
[ "$DEVICE_SHA" = "$RECOVERY_SHA" ] ||
	fail "raw recovery verification failed: $DEVICE_SHA"

diskutil mountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=1
[ "$(plist_value "/dev/${WHOLE}s5" PartitionMapPartitionOffset)" = "$ROOT_OFFSET" ] ||
	fail 'restored root partition offset is wrong'
[ "$(plist_value "/dev/${WHOLE}s5" Size)" = "$ROOT_BYTES" ] ||
	fail 'restored root partition size is wrong'
[ "$(plist_value "/dev/${WHOLE}s6" PartitionMapPartitionOffset)" = "$DATA_OFFSET" ] ||
	fail 'restored data partition offset is wrong'
[ "$(plist_value "/dev/${WHOLE}s6" Size)" = "$DATA_BYTES" ] ||
	fail 'restored data partition size is wrong'

printf 'Accepted Bird prefix restored and raw-verified.\n'
printf 'The existing p5 root and p6 data bytes were not written.\n'
