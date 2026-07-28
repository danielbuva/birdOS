#!/bin/sh
# Build a small external initramfs overlay. Linux unpacks it over the exact
# embedded ROCKNIX archive, so only /init and Bird's fixed early payloads differ.

set -eu

configure_reproducible_build_environment() {
	# Directory modes and timestamp parsing must not depend on the caller.
	umask 022
	LC_ALL=C
	TZ=UTC
	export LC_ALL TZ
}
configure_reproducible_build_environment

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
RELEASE_ID=${BIRD_RELEASE_ID:-v6.23}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-rocknix-stock-root-$RELEASE_ID}
OFFICIAL_INIT=${OFFICIAL_INIT:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/init}
JOYPAD=${JOYPAD:-$ROOT/kernel/work/rocknix-system-exact-20260701/usr/lib/kernel-overlays/base/lib/modules/7.0.11/rocknix-joypad/rocknix-singleadc-joypad.ko}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}
INIT_BUSYBOX=${INIT_BUSYBOX:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/usr/bin/busybox}

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

case "$RELEASE_ID" in
	''|[![:alnum:]]*|*[![:alnum:]._-]*) fail "unsafe Bird release ID: $RELEASE_ID" ;;
esac
[ "${#RELEASE_ID}" -le 64 ] || fail 'Bird release ID is longer than 64 bytes'

LAUNCHER_PROFILE_FLAGS=
case "${BIRD_LAUNCHER_PROFILE:-none}" in
	none|0|'') ;;
	profile|1) LAUNCHER_PROFILE_FLAGS=-DBIRD_PROFILE ;;
	deep) fail 'BIRD_PROFILE_DEEP is host-test-only' ;;
	*) fail "unknown BIRD_LAUNCHER_PROFILE mode: $BIRD_LAUNCHER_PROFILE" ;;
esac

sha256() {
	BIRD_SHA256_LINE=$(shasum -a 256 "$1") || return 1
	printf '%s\n' "$BIRD_SHA256_LINE" | awk '{print $1}'
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
strings "$INIT_BUSYBOX" | grep -qx sha256sum || \
	fail 'initramfs BusyBox lacks release-verification sha256sum'
strings "$INIT_BUSYBOX" | grep -qx stat || \
	fail 'initramfs BusyBox lacks release-verification stat'
strings "$INIT_BUSYBOX" | grep -Fqx mknod || \
	fail 'initramfs BusyBox lacks the required mknod applet'
if strings "$INIT_BUSYBOX" | grep -Fqx mkfifo; then
	fail 'unexpected mkfifo applet appeared; reassess the fixed FIFO creation path'
fi
[ -x "$CLANG" ] || fail 'LLVM clang missing'
[ -x "$LLD" ] || fail 'LLVM lld missing'
[ -x "$READELF" ] || fail 'LLVM readelf missing'
[ -d "$OUTPUT/build" ] || fail "candidate build directory missing: $OUTPUT/build"
[ -d "$OUTPUT/card" ] || fail "candidate card directory missing: $OUTPUT/card"
chmod 0755 "$OUTPUT" "$OUTPUT/build" "$OUTPUT/card"

WORK=$OUTPUT/build/early-initramfs
PAYLOAD=$WORK/payload
VERIFY=$WORK/verify
CPIO=$WORK/bird-initramfs.cpio
GZIP=$OUTPUT/card/bird-initramfs.cpio.gz
OBJECT=$WORK/bird-launcher.o
LAUNCHER=$PAYLOAD/opt/bird/bird-launcher

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
	'-DHANDOFF_ACTION_PATH="/run/muos/bird-launch-action"' \
	'-DSTORAGE_ANCHOR_MARKER="/run/muos/bird-storage-anchor-ready"' \
	'-DSTORAGE_READY_SIGNAL="/run/muos/bird-storage-ready"' \
	-DPERSIST_UI_STATE \
	-DDEVICE_WAIT_MS=20000UL \
	$LAUNCHER_PROFILE_FLAGS \
	-c "$ROOT/launcher/bird-launcher.c" -o "$OBJECT"
"$LLD" -static --gc-sections --build-id=none -z noexecstack -s \
	-e _start -o "$LAUNCHER" "$OBJECT"
chmod 0755 "$LAUNCHER"
file "$LAUNCHER" | grep -q 'ARM aarch64.*statically linked' || \
	fail 'early launcher is not static AArch64'
if "$READELF" -l "$LAUNCHER" | grep -q ' INTERP '; then
	fail 'early launcher unexpectedly has an interpreter'
fi

# Inject three fixed calls into the pinned upstream init. Bird starts after the
# special filesystems exist. After prepare_sysroot moves the complete storage
# tree below /sysroot, init gives Bird a bounded opportunity to retain it. The
# same Bird process remains alive while the exact special filesystems move.
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
		print "  [ \"${BOOT_STEP}\" != \"prepare_sysroot\" ] || /bird-early.sh root-ready"
		next
	}
	$0 == "  if [ -f /flash/post-flash.sh ]; then" {
		print "  if [ -f /bird-release-loader.sh ]; then"
		next
	}
	$0 == "    . /flash/post-flash.sh" {
		print "    if ! . /bird-release-loader.sh; then"
		print "      error bird-release-loader \"versioned boot hook failed closed\""
		print "      while :; do sleep 3600; done"
		print "    fi"
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
[ "$(grep -c '^  \[ "${BOOT_STEP}" != "prepare_sysroot" \] || /bird-early.sh root-ready$' "$PAYLOAD/init")" = 1 ] || \
	fail 'storage anchor injection count changed'
[ "$(grep -c '^/bird-early.sh handoff$' "$PAYLOAD/init")" = 1 ] || \
	fail 'handoff injection count changed'
[ "$(grep -c '^/bird-early.sh resume$' "$PAYLOAD/init")" = 0 ] || \
	fail 'obsolete root bridge injection remained'
[ "$(grep -c '^load_splash() { :; }$' "$PAYLOAD/init")" = 1 ] || \
	fail 'splash suppression injection count changed'
[ "$(grep -c '^    if ! \. /bird-release-loader.sh; then$' "$PAYLOAD/init")" = 1 ] || \
	fail 'versioned release-loader injection count changed'
[ "$(grep -c '^      while :; do sleep 3600; done$' "$PAYLOAD/init")" = 1 ] || \
	fail 'versioned release-loader fatal boundary changed'
[ "$(grep -c '/flash/post-flash.sh' "$PAYLOAD/init")" = 0 ] || \
	fail 'mutable top-level boot hook remained in versioned init'

cp -fp "$ROOT/kernel/rocknix/stock-root/bird-early.sh" \
	"$PAYLOAD/bird-early.sh"
cp -fp "$ROOT/kernel/rocknix/stock-root/bird-release-loader.sh" \
	"$PAYLOAD/bird-release-loader.sh"
sed "s#BIRD_LOADER_RELEASE=v6\.23\$#BIRD_LOADER_RELEASE=$RELEASE_ID#" \
	"$ROOT/kernel/rocknix/stock-root/bird-release-loader.sh" \
	>"$PAYLOAD/bird-release-loader.sh"
cp -fp "$JOYPAD" "$PAYLOAD/opt/bird/rocknix-singleadc-joypad.ko"
chmod 0755 "$PAYLOAD/init" "$PAYLOAD/bird-early.sh" \
	"$PAYLOAD/bird-release-loader.sh"
chmod 0644 "$PAYLOAD/opt/bird/rocknix-singleadc-joypad.ko"
bash -n "$PAYLOAD/init" || fail 'overlaid ROCKNIX init syntax failed'
bash -n "$PAYLOAD/bird-early.sh" || fail 'Bird early hook syntax failed'
bash -n "$PAYLOAD/bird-release-loader.sh" || fail 'release loader syntax failed'
grep -Fq "BIRD_LOADER_RELEASE=$RELEASE_ID" \
	"$PAYLOAD/bird-release-loader.sh" || fail 'release loader identity generation failed'

find "$PAYLOAD" -type d -exec chmod 0755 {} +
find "$PAYLOAD" -exec touch -t 202601010000.00 {} +
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
cmp "$PAYLOAD/bird-release-loader.sh" "$VERIFY/bird-release-loader.sh" || \
	fail 'verified release loader changed'
cmp "$LAUNCHER" "$VERIFY/opt/bird/bird-launcher" || \
	fail 'verified early launcher changed'
cmp "$JOYPAD" "$VERIFY/opt/bird/rocknix-singleadc-joypad.ko" || \
	fail 'verified H700 input module changed'

{
	printf '%s  bird-initramfs.cpio\n' "$(sha256 "$CPIO")"
	printf '%s  bird-initramfs.cpio.gz\n' "$(sha256 "$GZIP")"
	printf '%s  early-bird-launcher\n' "$(sha256 "$LAUNCHER")"
} >"$WORK/manifest.sha256"

printf 'Built external Bird early-initramfs overlay: %s\n' "$GZIP"
wc -c "$CPIO" "$GZIP" "$LAUNCHER" "$PAYLOAD/init"
