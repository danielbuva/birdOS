#!/bin/sh
# Read-only raw verification after writing the guarded ROCKNIX reference.

set -eu

DEVICE=${1:-}
ACTION=${2:-}
GDD=${GDD:-/opt/homebrew/bin/gdd}
IMAGE_BYTES=2432696320
IMAGE_SHA=4d5c16452c7e45970f60bb4897c45a4e10f0e4fb10957927fb02405810b45dc7
DISK_BYTES=512074186752

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -n "$DEVICE" ] && [ "$ACTION" = '--verify' ] || \
	fail "usage: $0 /dev/diskN --verify"
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v diskutil >/dev/null 2>&1 || fail 'diskutil is required'
command -v plutil >/dev/null 2>&1 || fail 'plutil is required'

WHOLE=${DEVICE#/dev/}
case "$WHOLE" in
disk[0-9]*) ;;
*) fail 'device must be a whole disk such as /dev/disk4' ;;
esac

INFO=$(mktemp -t dani-card-info)
MOUNTED=1
cleanup() {
	if [ "$MOUNTED" -eq 0 ]; then
		diskutil mountDisk "/dev/$WHOLE" >/dev/null 2>&1 || true
	fi
	find "$INFO" -delete
}
trap cleanup EXIT HUP INT TERM

diskutil info -plist "/dev/$WHOLE" >"$INFO"
INTERNAL=$(plutil -extract Internal raw -o - "$INFO")
REMOVABLE=$(plutil -extract Removable raw -o - "$INFO")
DISK_SIZE=$(plutil -extract Size raw -o - "$INFO")
[ "$INTERNAL" = false ] || fail 'refusing an internal disk'
[ "$REMOVABLE" = true ] || fail 'refusing non-removable media'
[ "$DISK_SIZE" = "$DISK_BYTES" ] || fail "unexpected card size: $DISK_SIZE"

RAW_DISK="/dev/r$WHOLE"
printf 'Rereading and hashing %s bytes from %s...\n' "$IMAGE_BYTES" "$RAW_DISK"
diskutil unmountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=0
RAW_SHA=$(sudo "$GDD" if="$RAW_DISK" bs=4M count="$IMAGE_BYTES" \
	iflag=count_bytes,fullblock status=progress | shasum -a 256 | awk '{print $1}')
[ "$RAW_SHA" = "$IMAGE_SHA" ] || fail "raw reference verification failed: $RAW_SHA"

diskutil mountDisk "/dev/$WHOLE" >/dev/null
MOUNTED=1
printf 'Raw reference verification passed: %s\n' "$RAW_SHA"
