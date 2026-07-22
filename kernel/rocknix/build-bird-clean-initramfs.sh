#!/bin/sh
# Build Bird clean-root v5.2. Unlike the earlier compatibility archives this
# one never mounts or switches into p5: the initramfs is Bird's permanent root.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BASE=${BASE:-$ROOT/firmware/work/direct-handoff-from-power/dani-trimmed-initramfs.cpio}
MODULE_DIR=${MODULE_DIR:-$ROOT/kernel/work/rocknix-bird-kernel-compat-v4-5-native-ra-deploy/build}
JOYPAD=${JOYPAD:-$ROOT/kernel/work/rocknix-bird-kernel-v2-joypad/build/rocknix-singleadc-joypad.ko}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-clean-root-v5-2-initramfs}
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
CPIO=$OUTPUT/bird-clean-root-v5-2.cpio
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
	volume.sh suspend.sh input-metadata.sh audio-init.sh exit-content.sh \
	retroarch-append.cfg h700-gamepad.cfg h700-sdl-gamecontrollerdb.txt \
	mpv-input.conf; do
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
grep -q 'ID_INPUT_JOYSTICK=1' "$BIRD/input-metadata.sh" || \
	fail 'fixed native input metadata missing'
grep -q 'input_device = "H700 Gamepad"' "$BIRD/h700-gamepad.cfg" || \
	fail 'fixed H700 native controller policy missing'
grep -q '^input_y_btn = "2"$' "$BIRD/h700-gamepad.cfg" || \
	fail 'fixed H700 Y mapping missing'
grep -q '^input_x_btn = "3"$' "$BIRD/h700-gamepad.cfg" || \
	fail 'fixed H700 X mapping missing'
grep -q 'H700 Gamepad' "$BIRD/h700-sdl-gamecontrollerdb.txt" || \
	fail 'fixed H700 SDL controller policy missing'
grep -q '^VOLUME_UP ignore$' "$BIRD/mpv-input.conf" || \
	fail 'Bird MPV system-volume ownership missing'
if grep -q '^GAMEPAD_.*_TRIGGER ' "$BIRD/mpv-input.conf"; then
	fail 'unreliable MPV trigger binding present'
fi
grep -q -- '--vo=drm --drm-device=/dev/dri/card0' \
	"$BIRD/run-content.sh" || fail 'direct DRM movie policy missing'
grep -q -- '--input-gamepad=yes' "$BIRD/run-content.sh" || \
	fail 'native MPV gamepad input missing'
if grep -q -- '--drm-mode=preferred' "$BIRD/run-content.sh"; then
	fail 'unsupported MPV DRM mode policy present'
fi
if grep -q 'systemd-udevd' "$BIRD/input-metadata.sh"; then
	fail 'generic udev daemon reintroduced into fixed metadata path'
fi
grep -q '^while \[ "$COUNT" -lt 100 \]; do$' "$BIRD/exit-content.sh" || \
	fail 'bounded content-exit readiness polling missing'
grep -q 'cset "name=DAC Playback Switch" on' "$BIRD/audio-init.sh" || \
	fail 'fixed H616 DAC route missing'
grep -q 'cset "name=DAC Reversed Playback Switch" off' \
	"$BIRD/audio-init.sh" || fail 'fixed H616 reversed DAC route missing'
grep -q 'cset "name=Line Out Source Playback Route" Stereo' \
	"$BIRD/audio-init.sh" || fail 'fixed stereo Line Out route missing'
grep -q 'cset "name=DAC Playback Volume" 63' "$BIRD/audio-init.sh" || \
	fail 'fixed H616 DAC level missing'
grep -q 'cset "name=Speaker Switch" on' "$BIRD/audio-init.sh" || \
	fail 'fixed RG34XX-SP speaker route missing'
grep -q 'sset "Line Out" 60% unmute' "$BIRD/audio-init.sh" || \
	fail 'fixed default Line Out level missing'
grep -q 'sset "Line Out" "$CHANGE"' "$BIRD/volume.sh" || \
	fail 'Bird Line Out volume ownership missing'
if grep -q 'MESA_LOADER_DRIVER_OVERRIDE' "$BIRD/run-content.sh"; then
	fail 'Mesa split-DRM auto-selection overridden'
fi
grep -q 'LIBGL_DEBUG=verbose' "$BIRD/run-content.sh" || \
	fail 'one-cycle Mesa loader diagnostic missing'
grep -q -- '--audio-device=alsa/hw:0,0' "$BIRD/run-content.sh" || \
	fail 'MPV direct hardware ALSA endpoint missing'
grep -q '^video_fullscreen_x = "720"$' "$BIRD/retroarch-append.cfg" || \
	fail 'fixed 720-pixel panel width missing'
grep -q '^video_fullscreen_y = "480"$' "$BIRD/retroarch-append.cfg" || \
	fail 'fixed 480-pixel panel height missing'
if grep -q '^video_threaded = ' "$BIRD/retroarch-append.cfg"; then
	fail 'native H700 frame-pacing policy overridden'
fi
grep -q '^gamemode_enable = "false"$' "$BIRD/retroarch-append.cfg" || \
	fail 'unused GameMode client path not disabled'
grep -q '^audio_device = "hw:0,0"$' "$BIRD/retroarch-append.cfg" || \
	fail 'RetroArch direct hardware ALSA endpoint missing'
grep -q '^audio_latency = "64"$' "$BIRD/retroarch-append.cfg" || \
	fail 'fixed H700 audio latency missing'
grep -q '^core_options_path = "/run/bird/retroarch-core-options.cfg"$' \
	"$BIRD/retroarch-append.cfg" || \
	fail 'native fixed-device core options path missing'

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
	./opt/bird/input-metadata.sh \
	./opt/bird/audio-init.sh \
	./opt/bird/exit-content.sh \
	./opt/bird/h700-gamepad.cfg \
	./opt/bird/h700-sdl-gamecontrollerdb.txt \
	./opt/bird/mpv-input.conf \
	./opt/bird/controls \
	./opt/bird/rocknix-singleadc-joypad.ko \
	./opt/bird/panfrost.ko; do
	grep -qx "$FILE" "$OUTPUT/payload.txt" || fail "payload missing: $FILE"
done

(
	cd "$OUTPUT"
	wc -c bird-clean-root-v5-2.cpio ramdisk/init ramdisk/opt/dani-root-init \
		ramdisk/opt/dani-launcher ramdisk/opt/bird/controls >sizes.txt
	shasum -a 256 bird-clean-root-v5-2.cpio ramdisk/init \
		ramdisk/opt/dani-root-init ramdisk/opt/dani-launcher \
		ramdisk/opt/bird/* >sha256sums.txt
)

printf 'Bird clean-root v5.2 initramfs built: %s\n' "$CPIO"
cat "$OUTPUT/sizes.txt"
