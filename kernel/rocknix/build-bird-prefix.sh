#!/bin/sh
# Build the only bytes needed for the first Bird-on-ROCKNIX hardware gate.
# The prefix ends exactly where the existing p5 root begins, so the current
# root and p6 data library are neither copied nor modified.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BOOT_PREFIX=${BOOT_PREFIX:-$HOME/rocknix-reference-result/boot-prefix-16m.bin}
KERNEL_BUILD=${KERNEL_BUILD:-$ROOT/kernel/work/rocknix-bird-kernel-compat-v3/build}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/rocknix-bird-prefix-compat-v3}
GDD=${GDD:-/opt/homebrew/bin/gdd}
GTRUNCATE=${GTRUNCATE:-/opt/homebrew/bin/gtruncate}

BOOT_PREFIX_SHA=3d06e243e26bd1a06d585fa35e53912b5742f62ca180135308740719883d65d2
KERNEL_SHA=82f1a2ed941b55f5bb3a79421962f78029fa0559379c0651a4d4c82bd46d8653
DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
FAT_BYTES=134217728
FAT_OFFSET=16777216
PREFIX_BYTES=163577856

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -x "$GDD" ] || fail 'GNU dd is required'
[ -x "$GTRUNCATE" ] || fail 'GNU truncate is required'
[ -f "$BOOT_PREFIX" ] || fail "ROCKNIX boot prefix missing: $BOOT_PREFIX"
[ "$(shasum -a 256 "$BOOT_PREFIX" | awk '{print $1}')" = \
	"$BOOT_PREFIX_SHA" ] || fail 'ROCKNIX boot prefix checksum mismatch'
[ -f "$KERNEL_BUILD/Image" ] || fail 'Bird source kernel missing'
[ "$(shasum -a 256 "$KERNEL_BUILD/Image" | awk '{print $1}')" = \
	"$KERNEL_SHA" ] || fail 'Bird source kernel checksum mismatch'
[ "$(shasum -a 256 "$KERNEL_BUILD/sun50i-h700-anbernic-rg34xx-sp.dtb" | awk '{print $1}')" = \
	"$DTB_SHA" ] || fail 'RG34XX-SP DTB checksum mismatch'
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"

FAT="$OUTPUT/bird-boot.fat"
PREFIX="$OUTPUT/bird-rocknix-prefix.img"
PAYLOAD="$OUTPUT/payload"

mkdir -p "$PAYLOAD/extlinux"
cp -fp "$KERNEL_BUILD/Image" "$PAYLOAD/KERNEL"
cp -fp "$KERNEL_BUILD/sun50i-h700-anbernic-rg34xx-sp.dtb" \
	"$PAYLOAD/dtb.img"
cp -fp "$ROOT/kernel/rocknix/extlinux-bird.conf" \
	"$PAYLOAD/extlinux/extlinux.conf"
touch -t 202607010453 \
	"$PAYLOAD/KERNEL" "$PAYLOAD/dtb.img" \
	"$PAYLOAD/extlinux" "$PAYLOAD/extlinux/extlinux.conf"

"$GTRUNCATE" -s "$FAT_BYTES" "$FAT"
ATTACHED=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage \
	-nomount -readwrite "$FAT" | awk 'NR == 1 {print $1}')
[ -n "$ATTACHED" ] || fail 'FAT image did not attach'
newfs_msdos -F 32 -I 42495244 -v BIRD "$ATTACHED" >/dev/null
hdiutil detach "$ATTACHED" >/dev/null
python3 "$ROOT/kernel/rocknix/populate-bird-fat32.py" \
	"$FAT" \
	"$PAYLOAD/KERNEL" \
	"$PAYLOAD/dtb.img" \
	"$PAYLOAD/extlinux/extlinux.conf"
fsck_msdos -n "$FAT" >/dev/null
7zz t "$FAT" >/dev/null
[ "$(7zz l -ba "$FAT" | awk '{print $NF}' | LC_ALL=C sort | tr '\n' ' ')" = \
	'KERNEL dtb.img extlinux extlinux/extlinux.conf ' ] ||
	fail 'FAT image contains unexpected paths'

"$GTRUNCATE" -s "$PREFIX_BYTES" "$PREFIX"
"$GDD" if="$BOOT_PREFIX" of="$PREFIX" bs=4M conv=notrunc status=none
"$GDD" if="$FAT" of="$PREFIX" bs=4M seek="$FAT_OFFSET" \
	oflag=seek_bytes conv=notrunc status=none
python3 "$ROOT/kernel/rocknix/build-bird-layout.py" "$PREFIX" \
	>"$OUTPUT/layout.txt"

[ "$(stat -f %z "$PREFIX")" -eq "$PREFIX_BYTES" ] || \
	fail 'candidate prefix changed size'
"$GDD" if="$PREFIX" of="$OUTPUT/verified-fat.img" bs=4M \
	skip="$FAT_OFFSET" count="$FAT_BYTES" \
	iflag=skip_bytes,count_bytes status=none
cmp "$FAT" "$OUTPUT/verified-fat.img" || fail 'embedded FAT differs'

(
	cd "$OUTPUT"
	wc -c bird-rocknix-prefix.img bird-boot.fat payload/KERNEL \
		payload/dtb.img >sizes.txt
)
(
	cd "$OUTPUT"
	shasum -a 256 \
		bird-rocknix-prefix.img \
		bird-boot.fat \
		payload/KERNEL \
		payload/dtb.img \
		payload/extlinux/extlinux.conf \
		layout.txt \
		sizes.txt >sha256sums.txt
)

printf 'Non-deploying Bird/ROCKNIX prefix built:\n  %s\n' "$PREFIX"
cat "$OUTPUT/layout.txt"
cat "$OUTPUT/sha256sums.txt"
