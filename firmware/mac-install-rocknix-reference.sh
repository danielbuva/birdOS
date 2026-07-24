#!/bin/sh
# Install only the checksum-pinned ROCKNIX reference chain after proving that
# the complete current-card checkpoint exists.  This is a compatibility proof,
# not a kernel promotion.

set -eu

CARD=${1:-/Volumes/BIRD-DATA}
ACTION=${2:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}
IMAGE=${IMAGE:-$HOME/ROCKNIX-H700.aarch64-20260701-DDR4-rg34xxsp-safe.img}
LOCAL_PREFIX=${LOCAL_PREFIX:-$HOME/Downloads/bird-sp-before-rocknix-prefix.img}
IMAGE_BYTES=2432696320
IMAGE_SHA=4d5c16452c7e45970f60bb4897c45a4e10f0e4fb10957927fb02405810b45dc7
PREFIX_BYTES=163577856
ROOTFS_BYTES=8589934592
DISK_BYTES=512074186752
ACCEPTED_BOOT_SHA=872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ "$ACTION" = '--install-reference' ] || \
	fail "usage: $0 /Volumes/BIRD-DATA --install-reference"
[ -d "$CARD" ] || fail "card volume not mounted: $CARD"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v diskutil >/dev/null 2>&1 || fail 'diskutil is required'
command -v plutil >/dev/null 2>&1 || fail 'plutil is required'

[ -f "$IMAGE" ] || fail "reference image missing: $IMAGE"
[ "$(stat -f %z "$IMAGE")" -eq "$IMAGE_BYTES" ] || fail 'reference image size mismatch'
[ "$(shasum -a 256 "$IMAGE" | awk '{print $1}')" = "$IMAGE_SHA" ] || \
	fail 'reference image checksum mismatch'
[ -f "$LOCAL_PREFIX" ] || fail "local checkpoint prefix missing: $LOCAL_PREFIX"
[ "$(stat -f %z "$LOCAL_PREFIX")" -eq "$PREFIX_BYTES" ] || \
	fail 'local checkpoint prefix size mismatch'

CHECKPOINT_DIR="$CARD/.firmware-work/source-kernel-checkpoint"
ROOTFS_IMAGE="$CHECKPOINT_DIR/current-rootfs.ext4"
MANIFEST="$CHECKPOINT_DIR/manifest.sha256"
[ -f "$ROOTFS_IMAGE" ] || fail "rootfs checkpoint missing: $ROOTFS_IMAGE"
[ "$(stat -f %z "$ROOTFS_IMAGE")" -eq "$ROOTFS_BYTES" ] || \
	fail 'rootfs checkpoint size mismatch'
[ -f "$MANIFEST" ] || fail "checkpoint manifest missing: $MANIFEST"
(
	cd "$CHECKPOINT_DIR"
	shasum -a 256 -c manifest.sha256
)
PREFIX_BOOT_SHA=$("$GDD" if="$LOCAL_PREFIX" bs=1M skip=92 count=64 \
	iflag=fullblock status=none | shasum -a 256 | awk '{print $1}')
[ "$PREFIX_BOOT_SHA" = "$ACCEPTED_BOOT_SHA" ] || \
	fail "checkpoint does not contain the accepted Bird boot image: $PREFIX_BOOT_SHA"

INFO=$(mktemp -t bird-card-info)
MOUNTED=1
cleanup() {
	if [ "$MOUNTED" -eq 0 ]; then
		diskutil mountDisk "/dev/$WHOLE" >/dev/null 2>&1 || true
	fi
	find "$INFO" -delete
}
trap cleanup EXIT HUP INT TERM

diskutil info -plist "$CARD" >"$INFO"
WHOLE=$(plutil -extract ParentWholeDisk raw -o - "$INFO")
VOLUME_ID=$(plutil -extract DeviceIdentifier raw -o - "$INFO")
INTERNAL=$(plutil -extract Internal raw -o - "$INFO")
REMOVABLE=$(plutil -extract Removable raw -o - "$INFO")
DISK_SIZE=$(diskutil info -plist "/dev/$WHOLE" |
	plutil -extract Size raw -o - -)
[ "$INTERNAL" = false ] || fail 'refusing an internal disk'
[ "$REMOVABLE" = true ] || fail 'refusing non-removable media'
[ "$DISK_SIZE" = "$DISK_BYTES" ] || fail "unexpected card size: $DISK_SIZE"
[ "$VOLUME_ID" = "${WHOLE}s6" ] || \
	fail "ROM volume is not partition 6 of $WHOLE"

RAW_DISK="/dev/r$WHOLE"
printf 'Installing verified ROCKNIX reference chain on %s...\n' "$RAW_DISK"
diskutil unmountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=0
sudo "$GDD" if="$IMAGE" of="$RAW_DISK" bs=4M conv=fsync,notrunc \
	status=progress
RAW_SHA=$(sudo "$GDD" if="$RAW_DISK" bs=4M count="$IMAGE_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')
[ "$RAW_SHA" = "$IMAGE_SHA" ] || fail "raw reference verification failed: $RAW_SHA"

diskutil mountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=1
printf 'Exact DDR4 reference chain installed and raw-verified.\n'
printf 'This first boot proves hardware compatibility; it is not a speed result.\n'
printf 'Eject the card before removal.\n'
