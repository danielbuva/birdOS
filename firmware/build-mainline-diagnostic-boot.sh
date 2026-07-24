#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE=${1:-$ROOT/firmware/work/fixed-device-dtb-v1/bird-boot-fixed-device-dtb-v1.img}
KERNEL=${2:-$ROOT/kernel/work/mainline-compat/Image}
DTB=${3:-$ROOT/kernel/work/mainline-diagnostic/diagnostic.dtb}
WORK=${4:-$ROOT/firmware/work/mainline-diagnostic-boot}
case "$WORK" in
	/*) ;;
	*) WORK="$PWD/$WORK" ;;
esac
OUTPUT="$WORK/bird-boot-mainline-diagnostic.img"
BASE_SHA=872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f
KERNEL_SHA=2294fca4c88834d379d063eb08c606224fea2d4eb6a77edd50b6e1b320ab3150
BOOT_BYTES=67108864
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -f "$BASE" ] || fail 'accepted base boot image missing'
[ "$(shasum -a 256 "$BASE" | awk '{print $1}')" = "$BASE_SHA" ] || \
	fail 'base is not the accepted fixed-device boot image'
[ -f "$KERNEL" ] || fail 'mainline Image missing'
[ "$(shasum -a 256 "$KERNEL" | awk '{print $1}')" = "$KERNEL_SHA" ] || \
	fail 'mainline Image identity changed'
[ -f "$DTB" ] || fail 'diagnostic DTB missing'
[ -x "$CLANG" ] && [ -x "$LLD" ] && [ -x "$READELF" ] || \
	fail 'LLVM static AArch64 toolchain missing'
[ ! -e "$WORK" ] || fail "work directory already exists: $WORK"

BASE_UNPACK="$WORK/base"
VERIFY="$WORK/verify"
RAMDISK="$BASE_UNPACK/ramdisk"
FIRST_INIT="$RAMDISK/init"
FIRST_OBJECT="$WORK/bird-fixed-init-diagnostic.o"
RAMDISK_CPIO="$WORK/bird-mainline-diagnostic.cpio"
RAMDISK_GZ="$WORK/bird-mainline-diagnostic.gz"
RAMDISK_BOOT="$WORK/ramdisk-diagnostic.img"

mkdir -p "$WORK"
"$ROOT/firmware/unpack-boot.sh" "$BASE" "$BASE_UNPACK"

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
	-DBIRD_STATIC_ROOT_INIT=1 \
	-DBIRD_BOOT_DIAGNOSTICS=1 \
	-c "$ROOT/firmware/bird-fixed-init.c" \
	-o "$FIRST_OBJECT"
"$LLD" -static --build-id=none -z noexecstack -s -e _start \
	-o "$FIRST_INIT" "$FIRST_OBJECT"
chmod 755 "$FIRST_INIT"
touch -t 202601010000 "$RAMDISK" "$FIRST_INIT"

file "$FIRST_INIT" | grep -q 'ARM aarch64.*statically linked' || \
	fail 'diagnostic /init is not static AArch64'
if "$READELF" -l "$FIRST_INIT" | grep -q ' INTERP '; then
	fail 'diagnostic /init has a program interpreter'
fi
strings "$FIRST_INIT" | grep -q '/sys/class/leds/red:status' || \
	fail 'diagnostic LED path missing from /init'

(
	cd "$RAMDISK"
	find . -print | LC_ALL=C sort | cpio -o --format newc --owner 0:0 \
		>"$RAMDISK_CPIO" 2>"$WORK/cpio.log"
)
"$ROOT/firmware/normalize-newc.py" "$RAMDISK_CPIO"
gzip -n -9 -c "$RAMDISK_CPIO" >"$RAMDISK_GZ"

"$ROOT/firmware/repack-boot-ramdisk.sh" "$BASE" "$RAMDISK_GZ" "$RAMDISK_BOOT"
"$ROOT/firmware/repack-boot-kernel-dtb.sh" \
	"$RAMDISK_BOOT" "$KERNEL" "$DTB" "$OUTPUT"
"$ROOT/firmware/unpack-boot.sh" "$OUTPUT" "$VERIFY"

cmp "$KERNEL" "$VERIFY/kernel.img" || fail 'kernel changed during repack'
cmp "$DTB" "$VERIFY/device-tree.dtb" || fail 'diagnostic DTB changed during repack'
cmp "$FIRST_INIT" "$VERIFY/ramdisk/init" || fail 'diagnostic /init changed during repack'
cmp "$BASE_UNPACK/ramdisk/init.stock" "$VERIFY/ramdisk/init.stock" || \
	fail 'stock init fallback changed'
cmp "$BASE_UNPACK/ramdisk/opt/bird-launcher" \
	"$VERIFY/ramdisk/opt/bird-launcher" || fail 'launcher changed'
cmp "$BASE_UNPACK/ramdisk/opt/bird-root-init" \
	"$VERIFY/ramdisk/opt/bird-root-init" || fail 'root PID 1 changed'
[ "$(stat -f %z "$OUTPUT")" -eq "$BOOT_BYTES" ] || \
	fail 'candidate is not exactly 64 MiB'

shasum -a 256 "$OUTPUT" >"$WORK/candidate.sha256"
shasum -a 256 "$FIRST_INIT" "$DTB" >"$WORK/diagnostic-payloads.sha256"
printf 'Built boot-boundary diagnostic candidate: %s\n' "$OUTPUT"
cat "$WORK/candidate.sha256" "$WORK/diagnostic-payloads.sha256"
