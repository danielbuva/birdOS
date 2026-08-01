#!/bin/sh
# Install the untrimmed, source-built ROCKNIX kernel with Bird embedded as its
# initramfs.  Only the prefix before the existing p5 root is replaced.

set -eu

CARD=${1:-/Volumes/BIRD-DATA}
ACTION=${2:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}
PREFIX=${PREFIX:-$HOME/birdOS/kernel/work/rocknix-bird-prefix-compat-v2/bird-rocknix-prefix.img}
RECOVERY_PREFIX=${RECOVERY_PREFIX:-$HOME/muos-kernel-source/checkpoints/20260721-bird-current-prefix.img}

PREFIX_BYTES=163577856
PREFIX_SHA=b9828838e6197efa9108365493275a4ebc246c2e24725b7c852d650d42bbfb38
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

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/mac-removable-device.sh"

[ "$ACTION" = '--install-bird-prefix' ] ||
	fail "usage: $0 /Volumes/BIRD-DATA --install-bird-prefix"
[ -d "$CARD" ] || fail "card volume not mounted: $CARD"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v diskutil >/dev/null 2>&1 || fail 'diskutil is required'
command -v plutil >/dev/null 2>&1 || fail 'plutil is required'

[ -f "$PREFIX" ] || fail "Bird prefix missing: $PREFIX"
[ "$(stat -f %z "$PREFIX")" -eq "$PREFIX_BYTES" ] ||
	fail 'Bird prefix size mismatch'
[ "$(shasum -a 256 "$PREFIX" | awk '{print $1}')" = "$PREFIX_SHA" ] ||
	fail 'Bird prefix checksum mismatch'
[ -f "$RECOVERY_PREFIX" ] ||
	fail "local recovery prefix missing: $RECOVERY_PREFIX"
[ "$(stat -f %z "$RECOVERY_PREFIX")" -eq "$PREFIX_BYTES" ] ||
	fail 'local recovery prefix size mismatch'
[ "$(shasum -a 256 "$RECOVERY_PREFIX" | awk '{print $1}')" = "$RECOVERY_SHA" ] ||
	fail 'local recovery prefix checksum mismatch'

WHOLE=$(plist_value "$CARD" ParentWholeDisk)
VOLUME_ID=$(plist_value "$CARD" DeviceIdentifier)
DISK_SIZE=$(plist_value "/dev/$WHOLE" Size)
bird_require_safe_removable_device "/dev/$WHOLE"
[ "$DISK_SIZE" = "$DISK_BYTES" ] || fail "unexpected card size: $DISK_SIZE"
[ "$VOLUME_ID" = "${WHOLE}s6" ] ||
	fail "data volume is not partition 6 of $WHOLE"
[ "$(plist_value "/dev/${WHOLE}s5" PartitionMapPartitionOffset)" = "$ROOT_OFFSET" ] ||
	fail 'current root partition offset differs from the recovery contract'
[ "$(plist_value "/dev/${WHOLE}s5" Size)" = "$ROOT_BYTES" ] ||
	fail 'current root partition size differs from the recovery contract'
[ "$(plist_value "/dev/${WHOLE}s6" PartitionMapPartitionOffset)" = "$DATA_OFFSET" ] ||
	fail 'current data partition offset differs from the recovery contract'
[ "$(plist_value "/dev/${WHOLE}s6" Size)" = "$DATA_BYTES" ] ||
	fail 'current data partition size differs from the recovery contract'

RAW_DISK="/dev/r$WHOLE"
CURRENT_SHA=$(sudo "$GDD" if="$RAW_DISK" bs=4M count="$PREFIX_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')
[ "$CURRENT_SHA" = "$RECOVERY_SHA" ] ||
	fail "card prefix no longer matches the local recovery oracle: $CURRENT_SHA"

MOUNTED=1
cleanup() {
	if [ "$MOUNTED" -eq 0 ]; then
		diskutil mountDisk "/dev/$WHOLE" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT HUP INT TERM

printf 'Installing the verified Bird/source-kernel prefix on %s...\n' "$RAW_DISK"
diskutil unmountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=0
sudo "$GDD" if="$PREFIX" of="$RAW_DISK" bs=4M conv=fsync,notrunc \
	status=progress
DEVICE_SHA=$(sudo "$GDD" if="$RAW_DISK" bs=4M count="$PREFIX_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')
[ "$DEVICE_SHA" = "$PREFIX_SHA" ] ||
	fail "raw Bird prefix verification failed: $DEVICE_SHA"

diskutil mountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=1
[ "$(plist_value "/dev/${WHOLE}s5" PartitionMapPartitionOffset)" = "$ROOT_OFFSET" ] ||
	fail 'candidate root partition offset is wrong'
[ "$(plist_value "/dev/${WHOLE}s5" Size)" = "$ROOT_BYTES" ] ||
	fail 'candidate root partition size is wrong'
[ "$(plist_value "/dev/${WHOLE}s6" PartitionMapPartitionOffset)" = "$DATA_OFFSET" ] ||
	fail 'candidate data partition offset is wrong'
[ "$(plist_value "/dev/${WHOLE}s6" Size)" = "$DATA_BYTES" ] ||
	fail 'candidate data partition size is wrong'

printf 'Bird/source-kernel prefix installed and raw-verified.\n'
printf 'The existing p5 root and p6 data bytes were not written.\n'
printf 'Eject the card before removal.\n'
