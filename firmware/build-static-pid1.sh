#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE_BOOT=${1:-$ROOT/firmware/work/fixed-initramfs/bird-boot-fixed-initramfs.img}
OUTPUT_DIR=${2:-$ROOT/firmware/work/static-pid1}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}
BASE_SHA="3f6e8b07826ba307ff22665b9ca4d6cd2a485ce3b5162be95c7eacfa8301578c"
BOOT_BYTES=67108864

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

compile_static() {
	SOURCE="$1"
	OBJECT="$2"
	OUTPUT="$3"
	shift 3
	"$CLANG" \
		--target=aarch64-linux-gnu \
		-mcpu=cortex-a53 \
		-O2 \
		-ffreestanding \
		-fno-builtin \
		-fno-stack-protector \
		-fno-unwind-tables \
		-fno-asynchronous-unwind-tables \
		-fno-ident \
		-fvisibility=hidden \
		-nostdlib \
		-Wall -Wextra -Werror \
		"$@" \
		-c "$SOURCE" \
		-o "$OBJECT"
	"$LLD" -static --build-id=none -z noexecstack -s -e _start \
		-o "$OUTPUT" "$OBJECT"
	chmod 755 "$OUTPUT"
	file "$OUTPUT" | grep -q 'ARM aarch64.*statically linked' ||
		fail "not a static AArch64 executable: $OUTPUT"
	if "$READELF" -l "$OUTPUT" | grep -q ' INTERP '; then
		fail "program interpreter found in static executable: $OUTPUT"
	fi
}

[ -f "$BASE_BOOT" ] || fail "hardware-verified fixed-init base missing: $BASE_BOOT"
[ -x "$CLANG" ] || fail "LLVM clang is required; install llvm"
[ -x "$LLD" ] || fail "LLVM lld is required; install lld"
[ -x "$READELF" ] || fail "llvm-readelf is required: $READELF"
[ ! -e "$OUTPUT_DIR" ] || fail "output already exists: $OUTPUT_DIR"
[ "$(shasum -a 256 "$BASE_BOOT" | awk '{print $1}')" = "$BASE_SHA" ] ||
	fail "base is not the hardware-verified static first-stage image"
[ "$(stat -f %z "$BASE_BOOT")" -eq "$BOOT_BYTES" ] ||
	fail "base boot image is not exactly 64 MiB"

UNPACKED="$OUTPUT_DIR/base"
VERIFY="$OUTPUT_DIR/verify"
RAMDISK="$UNPACKED/ramdisk"
FIRST_INIT="$RAMDISK/init"
ROOT_INIT="$RAMDISK/opt/bird-root-init"
FIRST_OBJECT="$OUTPUT_DIR/bird-fixed-init-stage2.o"
ROOT_OBJECT="$OUTPUT_DIR/bird-root-init.o"
RAMDISK_CPIO="$OUTPUT_DIR/bird-static-pid1.cpio"
RAMDISK_GZ="$OUTPUT_DIR/bird-static-pid1.gz"
CANDIDATE="$OUTPUT_DIR/bird-boot-static-pid1.img"

mkdir -p "$OUTPUT_DIR"
"$ROOT/firmware/unpack-boot.sh" "$BASE_BOOT" "$UNPACKED"

compile_static "$ROOT/firmware/bird-fixed-init.c" "$FIRST_OBJECT" "$FIRST_INIT" \
	-DBIRD_STATIC_ROOT_INIT=1
compile_static "$ROOT/firmware/bird-root-init.c" "$ROOT_OBJECT" "$ROOT_INIT"
touch -t 202601010000 "$RAMDISK" "$RAMDISK/opt" "$FIRST_INIT" "$ROOT_INIT"

(
	cd "$RAMDISK"
	find . -print | LC_ALL=C sort | cpio -o --format newc --owner 0:0 \
		>"$RAMDISK_CPIO" 2>"$OUTPUT_DIR/cpio.log"
)
"$ROOT/firmware/normalize-newc.py" "$RAMDISK_CPIO"
gzip -n -9 -c "$RAMDISK_CPIO" >"$RAMDISK_GZ"

"$ROOT/firmware/repack-boot-ramdisk.sh" "$BASE_BOOT" "$RAMDISK_GZ" "$CANDIDATE"
"$ROOT/firmware/unpack-boot.sh" "$CANDIDATE" "$VERIFY"

cmp "$UNPACKED/kernel.img" "$VERIFY/kernel.img" || fail "kernel changed"
cmp "$UNPACKED/device-tree.dtb" "$VERIFY/device-tree.dtb" || fail "DTB changed"
cmp "$UNPACKED/ramdisk/opt/bird-launcher" \
	"$VERIFY/ramdisk/opt/bird-launcher" || fail "launcher changed"
cmp "$UNPACKED/ramdisk/init.stock" \
	"$VERIFY/ramdisk/init.stock" || fail "shell recovery changed"
cmp "$FIRST_INIT" "$VERIFY/ramdisk/init" || fail "first-stage init changed"
cmp "$ROOT_INIT" "$VERIFY/ramdisk/opt/bird-root-init" || fail "root init changed"
[ "$(stat -f %z "$CANDIDATE")" -eq "$BOOT_BYTES" ] ||
	fail "candidate is not exactly 64 MiB"

strings "$VERIFY/ramdisk/init" | grep -q 'switch-root-static-pid1' ||
	fail "static PID 1 handoff is missing from first-stage init"
strings "$VERIFY/ramdisk/opt/bird-root-init" | grep -q 'bird-root-init-active' ||
	fail "static PID 1 marker is missing"

CANDIDATE_SHA=$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')
FIRST_SHA=$(shasum -a 256 "$FIRST_INIT" | awk '{print $1}')
ROOT_SHA=$(shasum -a 256 "$ROOT_INIT" | awk '{print $1}')
printf '%s  %s\n' "$CANDIDATE_SHA" "${CANDIDATE##*/}" >"$OUTPUT_DIR/candidate.sha256"

printf '\nStatic root PID 1 candidate verified offline.\n'
printf 'First-stage /init: %10s bytes  %s\n' "$(stat -f %z "$FIRST_INIT")" "$FIRST_SHA"
printf 'Root PID 1:        %10s bytes  %s\n' "$(stat -f %z "$ROOT_INIT")" "$ROOT_SHA"
printf 'Previous ramdisk:  %10s bytes\n' "$(stat -f %z "$UNPACKED/ramdisk.gz")"
printf 'New ramdisk:       %10s bytes\n' "$(stat -f %z "$RAMDISK_GZ")"
printf 'Candidate SHA-256: %s\n' "$CANDIDATE_SHA"
printf 'Candidate: %s\n' "$CANDIDATE"
