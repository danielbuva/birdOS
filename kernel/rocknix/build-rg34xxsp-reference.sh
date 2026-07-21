#!/bin/sh
# Provision the verified generic ROCKNIX release for this physical RG34XX-SP.
# The boot chain and SYSTEM remain byte-identical.  The documented v1 DTB is
# copied to /dtb.img.  Storage is fixed at 256 MiB with its auto-grow marker
# removed so a one-boot proof cannot overwrite the checkpoint beyond p2.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SOURCE=${SOURCE:-/Users/dani/Downloads/ROCKNIX-H700.aarch64-20260701-DDR4.img}
# Keep the generated raw image outside Downloads. macOS provenance scanning can
# block raw-image opens there for minutes even after its checksum was proven.
OUTPUT=${OUTPUT:-/Users/dani/ROCKNIX-H700.aarch64-20260701-DDR4-rg34xxsp-safe.img}
SOURCE_BYTES=2198863872
SOURCE_SHA=fce3fe81be706be795311b361db7b98eb1316befc5d543a1ad6ca184aedcc3d6
FIXED_STORAGE_BYTES=268435456
FINAL_BYTES=2432696320
E2FS=/opt/homebrew/opt/e2fsprogs/sbin

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] || fail "official raw image missing: $SOURCE"
[ "$(stat -f %z "$SOURCE")" -eq "$SOURCE_BYTES" ] || fail 'official image size mismatch'
[ "$(shasum -a 256 "$SOURCE" | awk '{print $1}')" = "$SOURCE_SHA" ] || \
	fail 'official image checksum mismatch'
[ ! -e "$OUTPUT" ] || fail "refusing to overwrite: $OUTPUT"
command -v 7zz >/dev/null 2>&1 || fail '7zz is required'
[ -x "$E2FS/debugfs" ] || fail 'Homebrew e2fsprogs is required'
[ -x "$E2FS/e2fsck" ] || fail 'Homebrew e2fsprogs is required'
[ -x "$E2FS/resize2fs" ] || fail 'Homebrew e2fsprogs is required'

WORK=$(mktemp -d -t dani-rocknix-reference)
ATTACHED=
cleanup() {
	if [ -n "$ATTACHED" ]; then
		diskutil unmount "${ATTACHED}s1" >/dev/null 2>&1 || true
		hdiutil detach "$ATTACHED" >/dev/null 2>&1 || true
	fi
	find "$WORK" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

cp -c "$SOURCE" "$OUTPUT"
ATTACHED=$(hdiutil attach -nomount -readwrite "$OUTPUT" | awk 'NR == 1 {print $1}')
[ -n "$ATTACHED" ] || fail 'candidate image did not attach'
diskutil mount "${ATTACHED}s1" >/dev/null
MOUNT=$(diskutil info -plist "${ATTACHED}s1" |
	plutil -extract MountPoint raw -o - -)
COPYFILE_DISABLE=1 cp -fp \
	"$MOUNT/device_trees/sun50i-h700-anbernic-rg34xx-sp.dtb" \
	"$MOUNT/dtb.img"
cmp "$MOUNT/device_trees/sun50i-h700-anbernic-rg34xx-sp.dtb" "$MOUNT/dtb.img"
find "$MOUNT" -maxdepth 1 -name '._*' -delete
sync
diskutil unmount "${ATTACHED}s1" >/dev/null
hdiutil detach "$ATTACHED" >/dev/null
ATTACHED=

7zz x -aoa -bso0 -bsp0 -o"$WORK" "$SOURCE" 1.img
STORAGE="$WORK/1.img"
[ "$(stat -f %z "$STORAGE")" -eq 33554432 ] || fail 'release storage size mismatch'
"$E2FS/debugfs" -w -R 'rm .please_resize_me' "$STORAGE" >/dev/null 2>&1
/opt/homebrew/bin/gtruncate -s "$FIXED_STORAGE_BYTES" "$STORAGE"
FSCK_STATUS=0
"$E2FS/e2fsck" -fy "$STORAGE" >/dev/null 2>&1 || FSCK_STATUS=$?
[ "$FSCK_STATUS" -le 1 ] || fail "pre-resize e2fsck failed: $FSCK_STATUS"
"$E2FS/resize2fs" "$STORAGE" >/dev/null
FSCK_STATUS=0
"$E2FS/e2fsck" -fy "$STORAGE" >/dev/null 2>&1 || FSCK_STATUS=$?
[ "$FSCK_STATUS" -le 1 ] || fail "post-resize e2fsck failed: $FSCK_STATUS"
[ "$(stat -f %z "$STORAGE")" -eq "$FIXED_STORAGE_BYTES" ] || \
	fail 'fixed storage size mismatch'

python3 "$ROOT/kernel/rocknix/install-storage-partition.py" "$OUTPUT" "$STORAGE"
[ "$(stat -f %z "$OUTPUT")" -eq "$FINAL_BYTES" ] || fail 'candidate final size mismatch'

printf 'RG34XX-SP reference candidate complete:\n  %s\n' "$OUTPUT"
shasum -a 256 "$OUTPUT"
