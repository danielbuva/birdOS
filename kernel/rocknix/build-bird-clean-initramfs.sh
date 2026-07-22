#!/bin/sh
# Build Bird clean-root v5.0. Unlike the earlier compatibility archives this
# one never mounts or switches into p5: the initramfs is Bird's permanent root.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BASE=${BASE:-$ROOT/firmware/work/direct-handoff-from-power/dani-trimmed-initramfs.cpio}
MODULE_DIR=${MODULE_DIR:-$ROOT/kernel/work/rocknix-bird-kernel-compat-v4-5-native-ra-deploy/build}
JOYPAD=${JOYPAD:-$ROOT/kernel/work/rocknix-bird-kernel-v2-joypad/build/rocknix-singleadc-joypad.ko}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-clean-root-v5-initramfs}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}

BASE_SHA=6db265a4adc75093799f3b2211b4298d001546854c3faa5015e9c0459be60cba
JOYPAD_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05
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
	"$CLANG" --target=aarch64-linux-gnu -mcpu=cortex-a53 -O2 \
		-ffreestanding -ffunction-sections -fdata-sections \
		-fno-builtin -fno-stack-protector -fno-unwind-tables \
		-fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden \
		-nostdlib -Wall -Wextra -Werror -Wno-unused-function \
		"$@" -c "$SOURCE" -o "$OBJECT"
	"$LLD" -static --gc-sections --build-id=none -z noexecstack -s \
		-e _start -o "$TARGET" "$OBJECT"
	chmod 755 "$TARGET"
	file "$TARGET" | grep -q 'ARM aarch64.*statically linked' || \
		fail "not a static AArch64 executable: $TARGET"
	if "$READELF" -l "$TARGET" | grep -q ' INTERP '; then
		fail "unexpected interpreter: $TARGET"
	fi
}

[ -f "$BASE" ] || fail "base initramfs missing: $BASE"
[ "$(shasum -a 256 "$BASE" | awk '{print $1}')" = "$BASE_SHA" ] || \
	fail 'base initramfs checksum mismatch'
[ -f "$JOYPAD" ] || fail "joypad module missing: $JOYPAD"
[ "$(shasum -a 256 "$JOYPAD" | awk '{print $1}')" = "$JOYPAD_SHA" ] || \
	fail 'joypad module checksum mismatch'
for MODULE in drm_shmem_helper.ko gpu-sched.ko panfrost.ko; do
	[ -f "$MODULE_DIR/$MODULE" ] || fail "GPU module missing: $MODULE"
	strings "$MODULE_DIR/$MODULE" | grep -Fqx \
		'vermagic=7.0.11 SMP preempt mod_unload modversions aarch64' || \
		fail "GPU module ABI mismatch: $MODULE"
done
[ -x "$CLANG" ] || fail 'LLVM clang missing'
[ -x "$LLD" ] || fail 'LLVM lld missing'
[ -x "$READELF" ] || fail 'LLVM readelf missing'
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"

RAMDISK=$OUTPUT/ramdisk
BIRD=$RAMDISK/opt/bird
CPIO=$OUTPUT/bird-clean-root-v5.cpio
mkdir -p "$RAMDISK"
(
	cd "$RAMDISK"
	cpio -idm <"$BASE" 2>"$OUTPUT/extract.log"
)
mkdir -p "$BIRD"

compile_static "$ROOT/firmware/dani-fixed-init.c" \
	"$OUTPUT/fixed-init.o" "$RAMDISK/init" \
	-DDANI_CLEAN_ROOT=1 \
	-DDANI_MAINLINE_INPUT_MODULE=1 \
	-DDANI_BOOT_TIMEOUT_SECONDS="$WATCHDOG_SECONDS"
compile_static "$ROOT/firmware/dani-root-init.c" \
	"$OUTPUT/root-init.o" "$RAMDISK/opt/dani-root-init" \
	-DDANI_CLEAN_ROOT=1
compile_static "$ROOT/kernel/rocknix/root-overrides/bird-controls.c" \
	"$OUTPUT/controls.o" "$BIRD/controls" \
	-DDANI_CLEAN_ROOT=1

"$LLD" -static --gc-sections --build-id=none -z noexecstack -s -e _start \
	-o "$RAMDISK/opt/dani-launcher" "$ROOT/launcher/dani-launcher.o"
chmod 755 "$RAMDISK/opt/dani-launcher"

cp -fp "$JOYPAD" "$BIRD/rocknix-singleadc-joypad.ko"
cp -fp "$MODULE_DIR/drm_shmem_helper.ko" "$BIRD/drm_shmem_helper.ko"
cp -fp "$MODULE_DIR/gpu-sched.ko" "$BIRD/gpu-sched.ko"
cp -fp "$MODULE_DIR/panfrost.ko" "$BIRD/panfrost.ko"
for FILE in supervisor.sh post-frame.sh run-content.sh shutdown.sh \
	volume.sh suspend.sh retroarch-append.cfg; do
	cp -fp "$ROOT/kernel/rocknix/clean-root/$FILE" "$BIRD/$FILE"
done
chmod 755 "$BIRD"/*.sh

for SCRIPT in "$BIRD"/*.sh; do
	sh -n "$SCRIPT" || fail "shell syntax failed: $SCRIPT"
done
strings "$RAMDISK/init" | grep -q 'clean-root-pid1' || \
	fail 'clean-root handoff missing from first init'
strings "$RAMDISK/init" | grep -q 'watchdog-reboot' || \
	fail 'clean-root watchdog missing'
strings "$RAMDISK/init" | grep -q '/opt/bird/rocknix-singleadc-joypad.ko' || \
	fail 'clean-root input path missing'
strings "$RAMDISK/opt/dani-root-init" | grep -q '/opt/bird/post-frame.sh' || \
	fail 'clean post-frame dispatch missing'
grep -q 'complete interface between UI and application policy' \
	"$BIRD/supervisor.sh" || \
	fail 'clean supervisor identity missing'
grep -q 'same mounted ROCKNIX runtime' "$BIRD/run-content.sh" || \
	fail 'native application boundary missing'

find "$RAMDISK" -type d -exec touch -t 202601010000 {} +
find "$RAMDISK" -type f -exec touch -t 202601010000 {} +
(
	cd "$RAMDISK"
	find . -print | LC_ALL=C sort | cpio -o --format newc --owner 0:0 \
		>"$CPIO" 2>"$OUTPUT/cpio.log"
)
"$ROOT/firmware/normalize-newc.py" "$CPIO"
cpio -it <"$CPIO" >"$OUTPUT/payload.txt" 2>"$OUTPUT/verify.log"

for FILE in \
	./init \
	./init.stock \
	./opt/dani-launcher \
	./opt/dani-root-init \
	./opt/bird/supervisor.sh \
	./opt/bird/post-frame.sh \
	./opt/bird/run-content.sh \
	./opt/bird/controls \
	./opt/bird/rocknix-singleadc-joypad.ko \
	./opt/bird/panfrost.ko; do
	grep -qx "$FILE" "$OUTPUT/payload.txt" || fail "payload missing: $FILE"
done

(
	cd "$OUTPUT"
	wc -c bird-clean-root-v5.cpio ramdisk/init ramdisk/opt/dani-root-init \
		ramdisk/opt/dani-launcher ramdisk/opt/bird/controls >sizes.txt
	shasum -a 256 bird-clean-root-v5.cpio ramdisk/init \
		ramdisk/opt/dani-root-init ramdisk/opt/dani-launcher \
		ramdisk/opt/bird/* >sha256sums.txt
)

printf 'Bird clean-root v5.0 initramfs built: %s\n' "$CPIO"
cat "$OUTPUT/sizes.txt"
