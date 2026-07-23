#!/bin/sh
# Build a small external initramfs overlay. Linux unpacks it over the exact
# embedded ROCKNIX archive, so only /init and Bird's two early payloads differ.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-rocknix-stock-root-v6.5}
OFFICIAL_INIT=${OFFICIAL_INIT:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/init}
JOYPAD=${JOYPAD:-$ROOT/kernel/work/rocknix-bird-kernel-v2-joypad/build/rocknix-singleadc-joypad.ko}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}

case "$OUTPUT" in
	/*) ;;
	*) OUTPUT=$PWD/$OUTPUT ;;
esac

OFFICIAL_INIT_SHA=3473415af0cf5df44e70259c3392817b1df421a12a617ec083ec018ff51dbc48
JOYPAD_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

[ -f "$OFFICIAL_INIT" ] || fail 'exact ROCKNIX init missing'
[ "$(sha256 "$OFFICIAL_INIT")" = "$OFFICIAL_INIT_SHA" ] || \
	fail 'exact ROCKNIX init changed'
[ -f "$JOYPAD" ] || fail 'exact H700 input module missing'
[ "$(sha256 "$JOYPAD")" = "$JOYPAD_SHA" ] || \
	fail 'exact H700 input module changed'
[ -x "$CLANG" ] || fail 'LLVM clang missing'
[ -x "$LLD" ] || fail 'LLVM lld missing'
[ -x "$READELF" ] || fail 'LLVM readelf missing'
[ -d "$OUTPUT/build" ] || fail "candidate build directory missing: $OUTPUT/build"

WORK=$OUTPUT/build/early-initramfs
PAYLOAD=$WORK/payload
VERIFY=$WORK/verify
CPIO=$WORK/bird-initramfs.cpio
GZIP=$OUTPUT/card/bird-initramfs.cpio.gz
OBJECT=$WORK/dani-launcher.o
LAUNCHER=$PAYLOAD/opt/bird/dani-launcher

[ ! -e "$WORK" ] || fail "early initramfs work already exists: $WORK"
mkdir -p "$PAYLOAD/opt/bird" "$VERIFY"

"$CLANG" --target=aarch64-linux-gnu -mcpu=cortex-a53 -O2 \
	-ffreestanding -ffunction-sections -fdata-sections \
	-fno-builtin -fno-stack-protector -fno-unwind-tables \
	-fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden \
	-nostdlib -Wall -Wextra -Werror -Wno-unused-function \
	'-DROM_ROOT="/storage/bird-data/ROMS"' \
	'-DLIVE_STORAGE_ROOT="/storage/bird-data"' \
	'-DFAVORITES_PATH="/storage/.config/bird/favorites.txt"' \
	'-DFAVORITES_TEMP="/storage/.config/bird/favorites.tmp"' \
	'-DRECENT_PATH="/storage/.config/bird/recent.txt"' \
	'-DRECENT_TEMP="/storage/.config/bird/recent.tmp"' \
	'-DHANDOFF_ACTION_PATH="/run/muos/dani-launch-action"' \
	-DEARLY_HANDOFF_STATE=1 -DDEVICE_WAIT_MS=20000UL \
	-c "$ROOT/launcher/dani-launcher.c" -o "$OBJECT"
"$LLD" -static --gc-sections --build-id=none -z noexecstack -s \
	-e _start -o "$LAUNCHER" "$OBJECT"
chmod 0755 "$LAUNCHER"
file "$LAUNCHER" | grep -q 'ARM aarch64.*statically linked' || \
	fail 'early launcher is not static AArch64'
if "$READELF" -l "$LAUNCHER" | grep -q ' INTERP '; then
	fail 'early launcher unexpectedly has an interpreter'
fi

# Inject exactly two calls into the pinned upstream init. Bird starts after the
# special filesystems exist and stops before those mounts move into sysroot.
awk '
	$0 == "hidecursor" {
		print
		print ""
		print "/bird-early.sh start"
		print "load_splash() { :; }"
		next
	}
	$0 == "# move some special filesystems" {
		print "/bird-early.sh handoff"
		print ""
	}
	{ print }
' "$OFFICIAL_INIT" >"$PAYLOAD/init"
[ "$(grep -c '^/bird-early.sh start$' "$PAYLOAD/init")" = 1 ] || \
	fail 'early start injection count changed'
[ "$(grep -c '^/bird-early.sh handoff$' "$PAYLOAD/init")" = 1 ] || \
	fail 'handoff injection count changed'
[ "$(grep -c '^load_splash() { :; }$' "$PAYLOAD/init")" = 1 ] || \
	fail 'splash suppression injection count changed'

cp -fp "$ROOT/kernel/rocknix/stock-root/bird-early.sh" \
	"$PAYLOAD/bird-early.sh"
cp -fp "$JOYPAD" "$PAYLOAD/opt/bird/rocknix-singleadc-joypad.ko"
chmod 0755 "$PAYLOAD/init" "$PAYLOAD/bird-early.sh"
chmod 0644 "$PAYLOAD/opt/bird/rocknix-singleadc-joypad.ko"
bash -n "$PAYLOAD/init" || fail 'overlaid ROCKNIX init syntax failed'
bash -n "$PAYLOAD/bird-early.sh" || fail 'Bird early hook syntax failed'

find "$PAYLOAD" -exec touch -t 202601010000 {} +
(
	cd "$PAYLOAD"
	find . -print | LC_ALL=C sort | \
		cpio -o --format newc --owner 0:0 >"$CPIO" 2>"$WORK/cpio.log"
)
"$ROOT/firmware/normalize-newc.py" "$CPIO"
gzip -n -9 -c "$CPIO" >"$GZIP"

gzip -dc "$GZIP" | (cd "$VERIFY" && cpio -idm 2>"$WORK/verify.log")
cmp "$PAYLOAD/init" "$VERIFY/init" || fail 'verified init changed'
cmp "$PAYLOAD/bird-early.sh" "$VERIFY/bird-early.sh" || \
	fail 'verified early hook changed'
cmp "$LAUNCHER" "$VERIFY/opt/bird/dani-launcher" || \
	fail 'verified early launcher changed'
cmp "$JOYPAD" "$VERIFY/opt/bird/rocknix-singleadc-joypad.ko" || \
	fail 'verified H700 input module changed'

{
	printf '%s  bird-initramfs.cpio\n' "$(sha256 "$CPIO")"
	printf '%s  bird-initramfs.cpio.gz\n' "$(sha256 "$GZIP")"
	printf '%s  early-dani-launcher\n' "$(sha256 "$LAUNCHER")"
} >"$WORK/manifest.sha256"

printf 'Built external Bird early-initramfs overlay: %s\n' "$GZIP"
wc -c "$CPIO" "$GZIP" "$LAUNCHER" "$PAYLOAD/init"
