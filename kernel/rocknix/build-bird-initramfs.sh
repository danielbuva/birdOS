#!/bin/sh
# Rebuild Bird's accepted fixed initramfs as a standalone archive suitable for
# direct embedding in the source kernel. The normal path is unchanged except
# for a 20-second first-frame watchdog and the pinned H700 input module needed
# before the launcher can become interactive.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BASE=${BASE:-$ROOT/firmware/work/direct-handoff-from-power/dani-trimmed-initramfs.cpio}
JOYPAD_MODULE=${JOYPAD_MODULE:-$ROOT/kernel/work/rocknix-bird-kernel-v2-joypad/build/rocknix-singleadc-joypad.ko}
DRM_SHMEM_MODULE=${DRM_SHMEM_MODULE:-}
GPU_SCHED_MODULE=${GPU_SCHED_MODULE:-}
PANFROST_MODULE=${PANFROST_MODULE:-}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/rocknix-bird-initramfs}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}

BASE_SHA=6db265a4adc75093799f3b2211b4298d001546854c3faa5015e9c0459be60cba
LAUNCHER_SHA=840ab4cfd967f18687e624a3dd916ea6cb852a23db84f554d81e1b7c2bcecf2c
JOYPAD_MODULE_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05
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

compile_mali_stub() {
	SOURCE=$1
	OBJECT=$2
	TARGET=$3
	"$CLANG" \
		--target=aarch64-linux-gnu \
		-mcpu=cortex-a53 \
		-O2 \
		-ffreestanding \
		-fno-stack-protector \
		-fno-ident \
		-fPIC \
		-nostdlib \
		-Wall -Wextra -Werror \
		-c "$SOURCE" \
		-o "$OBJECT"
	"$LLD" -shared --build-id=none -z noexecstack \
		-soname libmali.so.0 -o "$TARGET" "$OBJECT"
	chmod 644 "$TARGET"
	file "$TARGET" | grep -q 'ARM aarch64' ||
		fail "not an AArch64 shared object: $TARGET"
	file "$TARGET" | grep -q 'shared object' ||
		fail "not an AArch64 shared object: $TARGET"
	"$READELF" -d "$TARGET" | grep -q 'Library soname: \[libmali.so.0\]' ||
		fail 'Mali compatibility stub SONAME is missing'
}

[ -f "$BASE" ] || fail "accepted Bird initramfs missing: $BASE"
[ "$(shasum -a 256 "$BASE" | awk '{print $1}')" = "$BASE_SHA" ] ||
	fail 'accepted Bird initramfs checksum mismatch'
[ -f "$JOYPAD_MODULE" ] || fail "H700 joypad module missing: $JOYPAD_MODULE"
[ "$(shasum -a 256 "$JOYPAD_MODULE" | awk '{print $1}')" = \
	"$JOYPAD_MODULE_SHA" ] || fail 'H700 joypad module checksum mismatch'
for MODULE_VARIABLE in DRM_SHMEM_MODULE GPU_SCHED_MODULE PANFROST_MODULE; do
	eval "MODULE_PATH=\${$MODULE_VARIABLE-}"
	[ -n "$MODULE_PATH" ] || fail "$MODULE_VARIABLE is required"
	[ -f "$MODULE_PATH" ] || fail "GPU module missing: $MODULE_PATH"
	strings "$MODULE_PATH" | grep -Fqx \
		'vermagic=7.0.11 SMP preempt mod_unload modversions aarch64' || \
		fail "GPU module vermagic mismatch: $MODULE_PATH"
done
strings "$PANFROST_MODULE" | grep -Fqx \
	'depends=gpu-sched,drm_shmem_helper' || \
	fail 'Panfrost dependency set changed'
[ -x "$CLANG" ] || fail 'LLVM clang is required'
[ -x "$LLD" ] || fail 'LLVM lld is required'
[ -x "$READELF" ] || fail 'llvm-readelf is required'
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"

RAMDISK="$OUTPUT/ramdisk"
CPIO="$OUTPUT/bird-initramfs.cpio"
GZIP="$OUTPUT/bird-initramfs.cpio.gz"
FIRST_OBJECT="$OUTPUT/bird-fixed-init.o"
ROOT_OBJECT="$OUTPUT/bird-root-init.o"
MALI_STUB_OBJECT="$OUTPUT/bird-mali-stub.o"
CONTROLS_OBJECT="$OUTPUT/bird-controls.o"
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
	-DDANI_MAINLINE_INPUT_MODULE=1 \
	-DDANI_BOOT_TIMEOUT_SECONDS="$WATCHDOG_SECONDS"
compile_static "$ROOT/firmware/dani-root-init.c" "$ROOT_OBJECT" \
	"$RAMDISK/opt/dani-root-init"
mkdir -p "$MAINLINE_OVERRIDE_DIR"
compile_mali_stub \
	"$ROOT/kernel/rocknix/root-overrides/libmali-stub.c" \
	"$MALI_STUB_OBJECT" \
	"$MAINLINE_OVERRIDE_DIR/libmali-bird-stub.so"
compile_static \
	"$ROOT/kernel/rocknix/root-overrides/bird-controls.c" \
	"$CONTROLS_OBJECT" \
	"$MAINLINE_OVERRIDE_DIR/bird-controls"
"$LLD" -static --build-id=none -z noexecstack -s -e _start \
	-o "$RAMDISK/opt/dani-launcher" "$ROOT/launcher/dani-launcher.o"
chmod 755 "$RAMDISK/opt/dani-launcher"

cp -fp "$JOYPAD_MODULE" \
	"$MAINLINE_OVERRIDE_DIR/rocknix-singleadc-joypad.ko"
cp -fp "$DRM_SHMEM_MODULE" "$MAINLINE_OVERRIDE_DIR/drm_shmem_helper.ko"
cp -fp "$GPU_SCHED_MODULE" "$MAINLINE_OVERRIDE_DIR/gpu-sched.ko"
cp -fp "$PANFROST_MODULE" "$MAINLINE_OVERRIDE_DIR/panfrost.ko"
cp -fp "$ROOT/kernel/rocknix/root-overrides/S10udev" \
	"$MAINLINE_OVERRIDE_DIR/S10udev"
cp -fp "$ROOT/kernel/rocknix/root-overrides/module.sh" \
	"$MAINLINE_OVERRIDE_DIR/module.sh"
cp -fp "$ROOT/launcher/S03danilauncher" \
	"$MAINLINE_OVERRIDE_DIR/S03danilauncher"
cp -fp "$ROOT/kernel/rocknix/root-overrides/bird-mainline-env.sh" \
	"$MAINLINE_OVERRIDE_DIR/bird-mainline-env.sh"
cp -fp "$ROOT/kernel/rocknix/root-overrides/func-mainline.sh" \
	"$MAINLINE_OVERRIDE_DIR/func-mainline.sh"
cp -fp "$ROOT/kernel/rocknix/root-overrides/bright-mainline.sh" \
	"$MAINLINE_OVERRIDE_DIR/bright-mainline.sh"
chmod 755 "$MAINLINE_OVERRIDE_DIR/S10udev" \
	"$MAINLINE_OVERRIDE_DIR/module.sh" \
	"$MAINLINE_OVERRIDE_DIR/S03danilauncher" \
	"$MAINLINE_OVERRIDE_DIR/bird-mainline-env.sh" \
	"$MAINLINE_OVERRIDE_DIR/func-mainline.sh" \
	"$MAINLINE_OVERRIDE_DIR/bright-mainline.sh"

[ "$(shasum -a 256 "$RAMDISK/opt/dani-launcher" | awk '{print $1}')" = \
	"$LAUNCHER_SHA" ] || fail 'launcher no longer reproduces pinned executable'
strings "$RAMDISK/init" | grep -q 'watchdog-reboot' || \
	fail 'first-frame watchdog is missing'
strings "$RAMDISK/init" | grep -q 'direct-handoff-static-pid1' || \
	fail 'direct static PID 1 handoff is missing'
strings "$RAMDISK/init" | grep -q 'mainline-input-ready' || \
	fail 'early H700 input load is missing'
grep -q '^[[:space:]]*export SDL_KMSDRM_DEVICE_INDEX=0$' \
	"$MAINLINE_OVERRIDE_DIR/bird-mainline-env.sh" || \
	fail 'fixed sun4i display-card selection is missing'
grep -q '/run/muos/panfrost\.ko' "$MAINLINE_OVERRIDE_DIR/S10udev" || \
	fail 'asynchronous Panfrost warm-up is missing'
grep -q 'BIRD_MAINLINE_WAIT_GPU' \
	"$MAINLINE_OVERRIDE_DIR/bird-mainline-env.sh" || \
	fail 'Panfrost readiness wait is missing'
grep -q '^[[:space:]]*export SDL_LOGGING=video=debug$' \
	"$MAINLINE_OVERRIDE_DIR/bird-mainline-env.sh" || \
	fail 'SDL graphics diagnostics are missing'
strings "$MAINLINE_OVERRIDE_DIR/bird-controls" | \
	grep -q 'bird-controls: brightness-write-failed' || \
	fail 'persistent mainline controls diagnostics are missing'

find "$RAMDISK" -type d -exec touch -t 202601010000 {} +
touch -t 202601010000 \
	"$RAMDISK/init" \
	"$RAMDISK/opt/dani-root-init" \
	"$RAMDISK/opt/dani-launcher" \
	"$MAINLINE_OVERRIDE_DIR/rocknix-singleadc-joypad.ko" \
	"$MAINLINE_OVERRIDE_DIR/drm_shmem_helper.ko" \
	"$MAINLINE_OVERRIDE_DIR/gpu-sched.ko" \
	"$MAINLINE_OVERRIDE_DIR/panfrost.ko" \
	"$MAINLINE_OVERRIDE_DIR/S10udev" \
	"$MAINLINE_OVERRIDE_DIR/module.sh" \
	"$MAINLINE_OVERRIDE_DIR/S03danilauncher" \
	"$MAINLINE_OVERRIDE_DIR/bird-mainline-env.sh" \
	"$MAINLINE_OVERRIDE_DIR/func-mainline.sh" \
	"$MAINLINE_OVERRIDE_DIR/bright-mainline.sh" \
	"$MAINLINE_OVERRIDE_DIR/bird-controls" \
	"$MAINLINE_OVERRIDE_DIR/libmali-bird-stub.so"
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
for PAYLOAD in \
	S03danilauncher \
	bird-mainline-env.sh \
	func-mainline.sh \
	bright-mainline.sh \
	bird-controls \
	libmali-bird-stub.so; do
	grep -qx "./opt/bird-mainline/$PAYLOAD" "$OUTPUT/payload.txt" || \
		fail "mainline compatibility payload missing: $PAYLOAD"
done
grep -qx './opt/bird-mainline/rocknix-singleadc-joypad.ko' \
	"$OUTPUT/payload.txt" || fail 'H700 joypad module missing from archive'
grep -qx './opt/bird-mainline/drm_shmem_helper.ko' \
	"$OUTPUT/payload.txt" || fail 'DRM shmem helper missing from archive'
grep -qx './opt/bird-mainline/gpu-sched.ko' \
	"$OUTPUT/payload.txt" || fail 'GPU scheduler missing from archive'
grep -qx './opt/bird-mainline/panfrost.ko' \
	"$OUTPUT/payload.txt" || fail 'Panfrost module missing from archive'

(
	cd "$OUTPUT"
	wc -c bird-initramfs.cpio bird-initramfs.cpio.gz ramdisk/init \
		ramdisk/opt/dani-root-init ramdisk/opt/dani-launcher \
		ramdisk/opt/bird-mainline/rocknix-singleadc-joypad.ko \
		ramdisk/opt/bird-mainline/drm_shmem_helper.ko \
		ramdisk/opt/bird-mainline/gpu-sched.ko \
		ramdisk/opt/bird-mainline/panfrost.ko \
		ramdisk/opt/bird-mainline/S10udev \
		ramdisk/opt/bird-mainline/module.sh \
		ramdisk/opt/bird-mainline/S03danilauncher \
		ramdisk/opt/bird-mainline/bird-mainline-env.sh \
		ramdisk/opt/bird-mainline/func-mainline.sh \
		ramdisk/opt/bird-mainline/bright-mainline.sh \
		ramdisk/opt/bird-mainline/bird-controls \
		ramdisk/opt/bird-mainline/libmali-bird-stub.so >sizes.txt
)
(
	cd "$OUTPUT"
	shasum -a 256 \
		bird-initramfs.cpio \
		bird-initramfs.cpio.gz \
		ramdisk/init \
		ramdisk/opt/dani-root-init \
		ramdisk/opt/dani-launcher \
		ramdisk/opt/bird-mainline/rocknix-singleadc-joypad.ko \
		ramdisk/opt/bird-mainline/S10udev \
		ramdisk/opt/bird-mainline/module.sh \
		ramdisk/opt/bird-mainline/S03danilauncher \
		ramdisk/opt/bird-mainline/bird-mainline-env.sh \
		ramdisk/opt/bird-mainline/func-mainline.sh \
		ramdisk/opt/bird-mainline/bright-mainline.sh \
		ramdisk/opt/bird-mainline/bird-controls \
		ramdisk/opt/bird-mainline/libmali-bird-stub.so \
		payload.txt \
		sizes.txt >sha256sums.txt
)

printf 'Standalone Bird initramfs built with a %s-second watchdog:\n  %s\n' \
	"$WATCHDOG_SECONDS" "$CPIO"
cat "$OUTPUT/sizes.txt"
