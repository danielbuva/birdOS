#!/bin/sh
# Build a small external initramfs overlay. Linux unpacks it over the exact
# embedded ROCKNIX archive, so only /init and Bird's two early payloads differ.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-rocknix-stock-root-v6.17}
OFFICIAL_INIT=${OFFICIAL_INIT:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/init}
JOYPAD=${JOYPAD:-$ROOT/kernel/work/rocknix-system-exact-20260701/usr/lib/kernel-overlays/base/lib/modules/7.0.11/rocknix-joypad/rocknix-singleadc-joypad.ko}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}
INIT_BUSYBOX=$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/usr/bin/busybox

case "$OUTPUT" in
	/*) ;;
	*) OUTPUT=$PWD/$OUTPUT ;;
esac

OFFICIAL_INIT_SHA=3473415af0cf5df44e70259c3392817b1df421a12a617ec083ec018ff51dbc48
JOYPAD_SHA=a8ac6cacfa89672fa08dec7fa02179bb108a4a2303fd5c1eb5834f916089b79b
INIT_BUSYBOX_SHA=5ee3d20d8ea5fd9b3ba5109da80599eaf46a5a337d9e40d4c67d28eef44d5dc8

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
strings "$JOYPAD" | grep -Fqx \
	'vermagic=7.0.11 SMP preempt mod_unload modversions aarch64' || \
	fail 'exact H700 input module ABI changed'
[ -f "$INIT_BUSYBOX" ] || fail 'exact initramfs BusyBox missing'
[ "$(sha256 "$INIT_BUSYBOX")" = "$INIT_BUSYBOX_SHA" ] || \
	fail 'exact initramfs BusyBox changed'
strings "$INIT_BUSYBOX" | grep -Fqx mknod || \
	fail 'initramfs BusyBox lacks the required mknod applet'
if strings "$INIT_BUSYBOX" | grep -Fqx mkfifo; then
	fail 'unexpected mkfifo applet appeared; reassess the fixed FIFO creation path'
fi
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
	'-DSTORAGE_ANCHOR_MARKER="/run/muos/dani-storage-anchor-ready"' \
	'-DSTORAGE_READY_SIGNAL="/run/muos/dani-storage-ready"' \
	-DDEVICE_WAIT_MS=20000UL \
	-c "$ROOT/launcher/dani-launcher.c" -o "$OBJECT"
"$LLD" -static --gc-sections --build-id=none -z noexecstack -s \
	-e _start -o "$LAUNCHER" "$OBJECT"
chmod 0755 "$LAUNCHER"
file "$LAUNCHER" | grep -q 'ARM aarch64.*statically linked' || \
	fail 'early launcher is not static AArch64'
if "$READELF" -l "$LAUNCHER" | grep -q ' INTERP '; then
	fail 'early launcher unexpectedly has an interpreter'
fi

# Inject three fixed calls into the pinned upstream init. Bird starts after the
# special filesystems exist. Once storage is mounted, init gives Bird a bounded
# opportunity to retain it before prepare_sysroot moves that mount. The same
# Bird process remains alive while the exact special filesystems move.
awk '
	$0 == "hidecursor" {
		print
		print ""
		print "/bird-early.sh start"
		print "load_splash() { :; }"
		next
	}
	$0 == "  ${BOOT_STEP}" {
		print
		print "  [ \"${BOOT_STEP}\" != \"mount_storage\" ] || /bird-early.sh storage"
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
[ "$(grep -c '^  \[ "${BOOT_STEP}" != "mount_storage" \] || /bird-early.sh storage$' "$PAYLOAD/init")" = 1 ] || \
	fail 'storage anchor injection count changed'
[ "$(grep -c '^/bird-early.sh handoff$' "$PAYLOAD/init")" = 1 ] || \
	fail 'handoff injection count changed'
[ "$(grep -c '^/bird-early.sh resume$' "$PAYLOAD/init")" = 0 ] || \
	fail 'obsolete root bridge injection remained'
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
