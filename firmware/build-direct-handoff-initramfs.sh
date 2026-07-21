#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE=${1:-$ROOT/firmware/work/trimmed-initramfs/dani-boot-trimmed-initramfs.img}
OUTPUT=${2:-$ROOT/firmware/work/direct-handoff-initramfs}

"$ROOT/firmware/build-trimmed-initramfs.sh" "$BASE" "$OUTPUT"

CANDIDATE="$OUTPUT/dani-boot-trimmed-initramfs.img"
strings "$OUTPUT/verify/ramdisk/init" | grep -q 'direct-handoff-static-pid1'
strings "$OUTPUT/verify/ramdisk/init" | grep -q 'dani-fsck-clean-skip'

printf 'Direct fixed-init handoff verified: %s\n' "$CANDIDATE"
