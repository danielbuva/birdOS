#!/bin/sh
# Rebuild Bird's accepted fixed initramfs as a standalone archive suitable for
# direct embedding in the source kernel. The normal path is unchanged except
# for a 20-second first-frame watchdog, which reboots a failed experiment.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BASE=${BASE:-$ROOT/firmware/work/direct-handoff-from-power/dani-trimmed-initramfs.cpio}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/rocknix-bird-initramfs}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}

BASE_SHA=6db265a4adc75093799f3b2211b4298d001546854c3faa5015e9c0459be60cba
LAUNCHER_SHA=ab82e90a822c2baa4402829be3dba8cb9db71761b970e7dbab689bf4d7f0c85e
WATCHDOG_SECONDS=20

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

compile_static() {
	SOURCE=$1
	OBJECT=$2
	TARGET=$3
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
		-o "$TARGET" "$OBJECT"
	chmod 755 "$TARGET"
	file "$TARGET" | grep -q 'ARM aarch64.*statically linked' ||
		fail "not a static AArch64 executable: $TARGET"
	if "$READELF" -l "$TARGET" | grep -q ' INTERP '; then
		fail "program interpreter found: $TARGET"
	fi
}

[ -f "$BASE" ] || fail "accepted Bird initramfs missing: $BASE"
[ "$(shasum -a 256 "$BASE" | awk '{print $1}')" = "$BASE_SHA" ] ||
	fail 'accepted Bird initramfs checksum mismatch'
[ -x "$CLANG" ] || fail 'LLVM clang is required'
[ -x "$LLD" ] || fail 'LLVM lld is required'
[ -x "$READELF" ] || fail 'llvm-readelf is required'
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"

RAMDISK="$OUTPUT/ramdisk"
CPIO="$OUTPUT/bird-initramfs.cpio"
GZIP="$OUTPUT/bird-initramfs.cpio.gz"
FIRST_OBJECT="$OUTPUT/bird-fixed-init.o"
ROOT_OBJECT="$OUTPUT/bird-root-init.o"
MAINLINE_OVERRIDE_DIR="$RAMDISK/opt/bird-mainline"

mkdir -p "$RAMDISK"
(
	cd "$RAMDISK"
	cpio -idm <"$BASE" 2>"$OUTPUT/extract.log"
)

compile_static "$ROOT/firmware/dani-fixed-init.c" "$FIRST_OBJECT" \
	"$RAMDISK/init" \
	-DDANI_STATIC_ROOT_INIT=1 \
	-DDANI_MAINLINE_ROOT_OVERRIDES=1 \
	-DDANI_BOOT_TIMEOUT_SECONDS="$WATCHDOG_SECONDS"
compile_static "$ROOT/firmware/dani-root-init.c" "$ROOT_OBJECT" \
	"$RAMDISK/opt/dani-root-init"
"$LLD" -static --build-id=none -z noexecstack -s -e _start \
	-o "$RAMDISK/opt/dani-launcher" "$ROOT/launcher/dani-launcher.o"
chmod 755 "$RAMDISK/opt/dani-launcher"

mkdir -p "$MAINLINE_OVERRIDE_DIR"
cp -fp "$ROOT/kernel/rocknix/root-overrides/S10udev" \
	"$MAINLINE_OVERRIDE_DIR/S10udev"
cp -fp "$ROOT/kernel/rocknix/root-overrides/module.sh" \
	"$MAINLINE_OVERRIDE_DIR/module.sh"
chmod 755 "$MAINLINE_OVERRIDE_DIR/S10udev" \
	"$MAINLINE_OVERRIDE_DIR/module.sh"

[ "$(shasum -a 256 "$RAMDISK/opt/dani-launcher" | awk '{print $1}')" = \
	"$LAUNCHER_SHA" ] || fail 'launcher no longer reproduces accepted executable'
strings "$RAMDISK/init" | grep -q 'watchdog-reboot' || \
	fail 'first-frame watchdog is missing'
strings "$RAMDISK/init" | grep -q 'direct-handoff-static-pid1' || \
	fail 'direct static PID 1 handoff is missing'

find "$RAMDISK" -type d -exec touch -t 202601010000 {} +
touch -t 202601010000 \
	"$RAMDISK/init" \
	"$RAMDISK/opt/dani-root-init" \
	"$RAMDISK/opt/dani-launcher" \
	"$MAINLINE_OVERRIDE_DIR/S10udev" \
	"$MAINLINE_OVERRIDE_DIR/module.sh"
(
	cd "$RAMDISK"
	find . -print | LC_ALL=C sort | cpio -o --format newc --owner 0:0 \
		>"$CPIO" 2>"$OUTPUT/cpio.log"
)
"$ROOT/firmware/normalize-newc.py" "$CPIO"
gzip -n -9 -c "$CPIO" >"$GZIP"

cpio -it <"$CPIO" >"$OUTPUT/payload.txt" 2>"$OUTPUT/verify.log"
grep -qx './init' "$OUTPUT/payload.txt" || fail '/init missing from archive'
grep -qx './opt/dani-launcher' "$OUTPUT/payload.txt" || \
	fail 'launcher missing from archive'
grep -qx './opt/dani-root-init' "$OUTPUT/payload.txt" || \
	fail 'root PID 1 missing from archive'
grep -qx './opt/bird-mainline/S10udev' "$OUTPUT/payload.txt" || \
	fail 'mainline udev override missing from archive'
grep -qx './opt/bird-mainline/module.sh' "$OUTPUT/payload.txt" || \
	fail 'mainline module override missing from archive'

wc -c "$CPIO" "$GZIP" "$RAMDISK/init" \
	"$RAMDISK/opt/dani-root-init" "$RAMDISK/opt/dani-launcher" \
	"$MAINLINE_OVERRIDE_DIR/S10udev" "$MAINLINE_OVERRIDE_DIR/module.sh" \
	>"$OUTPUT/sizes.txt"
(
	cd "$OUTPUT"
	shasum -a 256 \
		bird-initramfs.cpio \
		bird-initramfs.cpio.gz \
		ramdisk/init \
		ramdisk/opt/dani-root-init \
		ramdisk/opt/dani-launcher \
		ramdisk/opt/bird-mainline/S10udev \
		ramdisk/opt/bird-mainline/module.sh \
		payload.txt \
		sizes.txt >sha256sums.txt
)

printf 'Standalone Bird initramfs built with a %s-second watchdog:\n  %s\n' \
	"$WATCHDOG_SECONDS" "$CPIO"
cat "$OUTPUT/sizes.txt"
