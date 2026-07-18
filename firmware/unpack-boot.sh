#!/bin/sh
set -eu

BOOT=${1:-/Volumes/dani-sp/.firmware-work/stock-boot.img}
OUTPUT=${2:-$(pwd)/firmware/work/boot-unpacked}
GDD=${GDD:-/opt/homebrew/bin/gdd}
GTRUNCATE=${GTRUNCATE:-/opt/homebrew/bin/gtruncate}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

u32() {
	od -An -j "$2" -N 4 -tu4 "$1" | tr -d ' '
}

[ -f "$BOOT" ] || fail "boot image not found: $BOOT"
[ -x "$GDD" ] || fail "GNU dd is required; install it with: brew install coreutils"
[ -x "$GTRUNCATE" ] || fail "GNU truncate is required; install it with: brew install coreutils"
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"

MAGIC=$(dd if="$BOOT" bs=8 count=1 2>/dev/null)
[ "$MAGIC" = "ANDROID!" ] || fail "not an Android boot image"

KERNEL_SIZE=$(u32 "$BOOT" 8)
RAMDISK_SIZE=$(u32 "$BOOT" 16)
SECOND_SIZE=$(u32 "$BOOT" 24)
PAGE_SIZE=$(u32 "$BOOT" 36)
HEADER_VERSION=$(u32 "$BOOT" 40)
RECOVERY_DTBO_SIZE=$(u32 "$BOOT" 1632)
HEADER_SIZE=$(u32 "$BOOT" 1644)
DTB_SIZE=$(u32 "$BOOT" 1648)

[ "$HEADER_VERSION" -eq 2 ] || fail "expected Android boot header v2; found v$HEADER_VERSION"
[ "$PAGE_SIZE" -eq 2048 ] || fail "expected a 2048-byte page; found $PAGE_SIZE"
[ "$SECOND_SIZE" -eq 0 ] || fail "second-stage payload is not supported by this exact-image unpacker"
[ "$RECOVERY_DTBO_SIZE" -eq 0 ] || fail "recovery DTBO payload is not supported by this exact-image unpacker"

KERNEL_PAGES=$(((KERNEL_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
RAMDISK_PAGES=$(((RAMDISK_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
DTB_PAGES=$(((DTB_SIZE + PAGE_SIZE - 1) / PAGE_SIZE))
RAMDISK_SKIP=$((1 + KERNEL_PAGES))
DTB_SKIP=$((RAMDISK_SKIP + RAMDISK_PAGES))

mkdir -p "$OUTPUT/ramdisk"

"$GDD" if="$BOOT" of="$OUTPUT/kernel.img" bs="$PAGE_SIZE" skip=1 count="$KERNEL_PAGES" status=none
"$GTRUNCATE" -s "$KERNEL_SIZE" "$OUTPUT/kernel.img"

"$GDD" if="$BOOT" of="$OUTPUT/ramdisk.gz" bs="$PAGE_SIZE" skip="$RAMDISK_SKIP" count="$RAMDISK_PAGES" status=none
"$GTRUNCATE" -s "$RAMDISK_SIZE" "$OUTPUT/ramdisk.gz"

"$GDD" if="$BOOT" of="$OUTPUT/device-tree.dtb" bs="$PAGE_SIZE" skip="$DTB_SKIP" count="$DTB_PAGES" status=none
"$GTRUNCATE" -s "$DTB_SIZE" "$OUTPUT/device-tree.dtb"

(
	cd "$OUTPUT/ramdisk"
	gzip -dc ../ramdisk.gz | cpio -idmu
)

if command -v dtc >/dev/null 2>&1; then
	dtc -I dtb -O dts -o "$OUTPUT/device-tree.dts" "$OUTPUT/device-tree.dtb" 2>"$OUTPUT/dtc-warnings.txt"
fi

cat >"$OUTPUT/layout.txt" <<EOF
header_version=$HEADER_VERSION
header_size=$HEADER_SIZE
page_size=$PAGE_SIZE
kernel_size=$KERNEL_SIZE
ramdisk_size=$RAMDISK_SIZE
dtb_size=$DTB_SIZE
kernel_offset=$PAGE_SIZE
ramdisk_offset=$((RAMDISK_SKIP * PAGE_SIZE))
dtb_offset=$((DTB_SKIP * PAGE_SIZE))
EOF

printf 'Unpacked Android boot image into %s\n' "$OUTPUT"
