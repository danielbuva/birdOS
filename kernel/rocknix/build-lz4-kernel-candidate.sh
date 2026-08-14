#!/bin/sh
# Build and independently verify the exact host-only IRQ-kernel LZ4 candidate.
# Why before: the first frame authority was prepared while direct-extlinux was
# the accepted U-Boot consumer. Why change: in-place handoff is now the exact
# physical boundary, so keep the compressed-kernel proof rooted there without
# changing the frame bytes. This script cannot deploy, edit a release, or open
# a block device.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-kernel-lz4-irq-candidate-20260813}
KERNEL=${KERNEL:-$ROOT/kernel/work/rocknix-source-irq-buttons/build/Image}
LZ4=${LZ4:-/opt/homebrew/Cellar/lz4/1.10.0/bin/lz4}
UBOOT_SOURCE=${UBOOT_SOURCE:-$HOME/rocknix-distribution-20260701/sources/u-boot-DDR4/u-boot-DDR4-v2026.01.tar.gz}
UBOOT_CONFIG=${UBOOT_CONFIG:-$ROOT/kernel/work/bird-uboot-inplace-handoff-20260701/inplace-handoff.config}
UBOOT_BINARY=${UBOOT_BINARY:-$ROOT/kernel/work/bird-uboot-inplace-handoff-20260701/inplace-handoff-uboot.bin}
VERIFIER=$ROOT/kernel/rocknix/verify-lz4-kernel-candidate.py
PYTHON=${PYTHON:-python3}

KERNEL_SHA=cad7ad8437d0a7de0d819846b12fdf83078f5878313704d0de79274431ec9d64
KERNEL_BYTES=30926856
LZ4_SHA=4fef8dd687478d1a8dcf4e2db25defd2daf76f7e0bb3478f023b738f9501f48c
CANDIDATE_SHA=a7321d2a79b18e81f114aefd9bb7509ba70d5e56b562a345ea5ca66dbf11262a
CANDIDATE_BYTES=17565707
UBOOT_SOURCE_SHA=03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654
UBOOT_CONFIG_SHA=77f2bee66adc542e3475594c4727933607f76c2adf72e6428e0e57cadb6de762
UBOOT_BINARY_SHA=cff9a9ca1bd7db20a3a136fec655d7120481afa8a837930266a9962ab2dec578

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

sha256_file() {
	shasum -a 256 "$1" | awk '{print $1}'
}

file_bytes() {
	stat -f %z "$1"
}

require_regular() {
	[ -f "$1" ] && [ ! -L "$1" ] || fail "unsafe or missing input: $1"
}

require_hash() {
	ACTUAL=$(sha256_file "$1")
	[ "$ACTUAL" = "$2" ] || fail "checksum mismatch for $1: $ACTUAL"
}

[ "$#" -eq 0 ] || fail 'this host-only builder takes no positional arguments; use environment overrides'
command -v "$PYTHON" >/dev/null 2>&1 || fail 'Python 3 is required'
command -v shasum >/dev/null 2>&1 || fail 'shasum is required'
require_regular "$KERNEL"
require_hash "$KERNEL" "$KERNEL_SHA"
[ "$(file_bytes "$KERNEL")" -eq "$KERNEL_BYTES" ] || fail 'accepted IRQ Image byte count changed'
require_regular "$LZ4"
[ -x "$LZ4" ] || fail "LZ4 authority is not executable: $LZ4"
require_hash "$LZ4" "$LZ4_SHA"
[ "$($LZ4 --version 2>&1)" = '*** lz4 v1.10.0 64-bit multithread, by Yann Collet ***' ] || \
	fail 'LZ4 version authority changed'
require_regular "$UBOOT_SOURCE"
require_hash "$UBOOT_SOURCE" "$UBOOT_SOURCE_SHA"
require_regular "$UBOOT_CONFIG"
require_hash "$UBOOT_CONFIG" "$UBOOT_CONFIG_SHA"
require_regular "$UBOOT_BINARY"
require_hash "$UBOOT_BINARY" "$UBOOT_BINARY_SHA"
require_regular "$VERIFIER"
[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || fail "output already exists: $OUTPUT"

OUTPUT_PARENT=$(dirname "$OUTPUT")
[ -d "$OUTPUT_PARENT" ] && [ ! -L "$OUTPUT_PARENT" ] || fail "unsafe or missing output parent: $OUTPUT_PARENT"
WORK=$(mktemp -d "$OUTPUT_PARENT/.bird-lz4-kernel-candidate.XXXXXX") || fail 'could not create staging directory'
cleanup() {
	case "$WORK" in
		"$OUTPUT_PARENT"/.bird-lz4-kernel-candidate.*) rm -rf -- "$WORK" ;;
		*) fail 'refusing unsafe temporary cleanup' ;;
	esac
}
trap cleanup EXIT HUP INT TERM
STAGE=$WORK/output
mkdir "$STAGE"

"$LZ4" -9 -T1 -f -q "$KERNEL" "$WORK/candidate-a.lz4"
"$LZ4" -9 -T1 -f -q "$KERNEL" "$WORK/candidate-b.lz4"
cmp "$WORK/candidate-a.lz4" "$WORK/candidate-b.lz4" || fail 'repeated LZ4 outputs differ'
require_hash "$WORK/candidate-a.lz4" "$CANDIDATE_SHA"
[ "$(file_bytes "$WORK/candidate-a.lz4")" -eq "$CANDIDATE_BYTES" ] || \
	fail 'LZ4 candidate byte count changed'
"$LZ4" -t -q "$WORK/candidate-a.lz4"
"$LZ4" -d -f -q "$WORK/candidate-a.lz4" "$WORK/roundtrip.Image"
cmp "$KERNEL" "$WORK/roundtrip.Image" || fail 'LZ4 producer round trip differs from accepted Image'

"$PYTHON" "$VERIFIER" \
	"$KERNEL" "$WORK/candidate-a.lz4" "$UBOOT_SOURCE" \
	"$UBOOT_CONFIG" "$UBOOT_BINARY" >"$STAGE/validation.tsv"
cp -p "$WORK/candidate-a.lz4" "$STAGE/KERNEL.lz4"
{
	printf 'schema\t%s\n' bird-lz4-kernel-candidate-authority-v1
	printf 'candidate\t%s\n' accepted-irq-image-lz4-level9
	printf 'kernel-bytes\t%s\n' "$KERNEL_BYTES"
	printf 'kernel-sha256\t%s\n' "$KERNEL_SHA"
	printf 'compressor\t%s\n' lz4-v1.10.0-arm64-tahoe-bottle
	printf 'compressor-sha256\t%s\n' "$LZ4_SHA"
	printf 'compressor-arguments\t%s\n' '-9 -T1'
	printf 'candidate-bytes\t%s\n' "$CANDIDATE_BYTES"
	printf 'candidate-sha256\t%s\n' "$CANDIDATE_SHA"
	printf 'repeat-byte-identical\t%s\n' yes
	printf 'producer-roundtrip\t%s\n' exact
	printf 'independent-frame-decode\t%s\n' exact
	printf 'accepted-uboot-config-sha256\t%s\n' "$UBOOT_CONFIG_SHA"
	printf 'accepted-uboot-binary-sha256\t%s\n' "$UBOOT_BINARY_SHA"
	printf 'uboot-source-tar-sha256\t%s\n' "$UBOOT_SOURCE_SHA"
	printf 'deployment-requires-exact-kernel-comp-size\t%s\n' 0x10c080b
	printf 'deployment-authority\t%s\n' none-host-candidate-only
	printf 'card-write\t%s\n' none
} >"$STAGE/authority.tsv"
(
	cd "$STAGE"
	shasum -a 256 KERNEL.lz4 authority.tsv validation.tsv >sha256sums.txt
)
require_hash "$STAGE/KERNEL.lz4" "$CANDIDATE_SHA"
mv "$STAGE" "$OUTPUT"
trap - EXIT HUP INT TERM
cleanup
printf 'Verified host-only LZ4 KERNEL candidate: %s\n' "$OUTPUT"
printf 'Bytes: %s -> %s (saved %s)\n' \
	"$KERNEL_BYTES" "$CANDIDATE_BYTES" "$((KERNEL_BYTES - CANDIDATE_BYTES))"
printf 'SHA-256: %s\n' "$CANDIDATE_SHA"
printf 'No release or card was changed. Deployment remains disabled.\n'
