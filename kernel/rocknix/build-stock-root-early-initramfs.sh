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
INIT_BUSYBOX_SHA=5ee3d20d8ea5fd9b3ba5109da80599eaf46a5a337d9e40d4c67d28eef44d5dc8

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

case "${BIRD_KERNEL_AUTHORITY:-stock}" in
	stock) JOYPAD_SHA=a8ac6cacfa89672fa08dec7fa02179bb108a4a2303fd5c1eb5834f916089b79b; EMBED_JOYPAD=1 ;;
	source-parity) JOYPAD_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05; EMBED_JOYPAD=1 ;;
	source-builtin-input) JOYPAD_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05; EMBED_JOYPAD=0 ;;
	source-single-gpio-read) JOYPAD_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05; EMBED_JOYPAD=0 ;;
	source-single-input-sync) JOYPAD_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05; EMBED_JOYPAD=0 ;;
	source-changed-input-sync) JOYPAD_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05; EMBED_JOYPAD=0 ;;
	source-fixed-gpio-fastpath) JOYPAD_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05; EMBED_JOYPAD=0 ;;
	source-irq-buttons|source-irq-buttons-lz4) JOYPAD_SHA=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05; EMBED_JOYPAD=0 ;;
	*) fail "unknown kernel authority: ${BIRD_KERNEL_AUTHORITY}" ;;
esac

validate_early_launcher_static_assets() {
	EARLY_BASE=$PAYLOAD/opt/bird/launcher-base.xrgb
	if [ "$EARLY_STATIC_ASSET_BYTES" -eq 1382400 ]; then
		[ -f "$EARLY_BASE" ] && [ ! -L "$EARLY_BASE" ] || \
			fail 'early launcher fallback base is missing or unsafe'
		[ "$(stat -f %z "$EARLY_BASE" 2>/dev/null || stat -c %s "$EARLY_BASE")" \
			-eq 1382400 ] || fail 'early launcher fallback base size changed'
		[ "$(sha256 "$EARLY_BASE")" = \
			6f9daae758675bd8bb805a851b30f1d64b06ec6e8367a17749707ac61824843a ] || \
			fail 'early launcher fallback base digest changed'
	elif [ -e "$EARLY_BASE" ] || [ -L "$EARLY_BASE" ]; then
		fail 'verified U-Boot reuse retained a duplicate early wallpaper'
	fi
	if find "$PAYLOAD" -type f ! -path "$EARLY_BASE" \
		\( -iname '*.bmp' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
			-o -iname '*.rgb' -o -iname '*.rgba' -o -iname '*.xrgb' -o -iname '*.raw' \) \
		-print -quit | grep -q .; then
		fail 'early launcher payload contains an unbudgeted static image'
	fi
}

case "$RELEASE_ID" in
	''|[![:alnum:]]*|*[![:alnum:]._-]*) fail "unsafe Bird release ID: $RELEASE_ID" ;;
esac
[ "${#RELEASE_ID}" -le 64 ] || fail 'Bird release ID is longer than 64 bytes'

# Ignore ambient off-tree source overrides in canonical builds. Only the
# mutable dev-current workflow may explicitly pass its generated source tree.
case "${BIRD_DEV_LOCAL_BUILD:-0}" in
	0|'') unset BIRD_LOCAL_LAUNCHER_DIR ;;
	1)
		[ "$RELEASE_ID" = dev-current ] || \
			fail 'local launcher override is restricted to dev-current'
		[ -n "${BIRD_LOCAL_LAUNCHER_DIR:-}" ] || \
			fail 'dev local build requires its private launcher directory'
		;;
	*) fail 'invalid Bird dev local-build mode' ;;
esac

BIRD_INITRAMFS_GZIP_LEVEL=${BIRD_INITRAMFS_GZIP_LEVEL:-9}
case "$BIRD_INITRAMFS_GZIP_LEVEL" in
	1|9) ;;
	*) fail 'Bird initramfs gzip level must be 1 or 9' ;;
esac

EARLY_STATIC_ASSET_BYTES=1382400
EARLY_INITRAMFS_GZIP_MAX_BYTES=786432
case "${BIRD_REUSE_UBOOT_FRAME:-0}" in
	0|'') ;;
	1)
		EARLY_STATIC_ASSET_BYTES=0
		EARLY_INITRAMFS_GZIP_MAX_BYTES=262144
		;;
	*) fail 'invalid BIRD_REUSE_UBOOT_FRAME mode' ;;
esac
case "${BIRD_LAUNCHER_PROFILE:-none}" in
	none|0|'') ;;
	profile|1) ;;
	deep) fail 'BIRD_PROFILE_DEEP is host-test-only' ;;
	*) fail "unknown BIRD_LAUNCHER_PROFILE mode: $BIRD_LAUNCHER_PROFILE" ;;
esac

sha256() {
	BIRD_SHA256_LINE=$(shasum -a 256 "$1") || return 1
	printf '%s\n' "$BIRD_SHA256_LINE" | awk '{print $1}'
}

# The BMP remains a build-only verification artifact. The contract always
# enters the early overlay. Until verified U-Boot reuse is enabled, the overlay
# also carries the exact native XRGB fallback; final-root recovery owns its own
# copy in either mode.
BOOT_FRAME_WORK=$OUTPUT/build/boot-frame
BOOT_FRAME_BMP=$BOOT_FRAME_WORK/bird-frame-zero.bmp
BOOT_FRAME_XRGB=$BOOT_FRAME_WORK/launcher-base.xrgb
BOOT_FRAME_CONTRACT=$OUTPUT/card/bird/boot-frame.contract
mkdir -p "$BOOT_FRAME_WORK" "$OUTPUT/card/bird"
python3 "$ROOT/firmware/generate-launcher-bootlogo.py" "$BOOT_FRAME_BMP" \
	--contract "$BOOT_FRAME_CONTRACT" \
	--xrgb-output "$BOOT_FRAME_XRGB" \
	--early-static-asset-bytes "$EARLY_STATIC_ASSET_BYTES"
[ "$(sha256 "$BOOT_FRAME_BMP")" = \
	fca1176e4247c5b358df495cf062e88ff53c3aa781c54325545a02b26a9fcb15 ] || \
	fail 'generated boot-frame asset digest changed'
chmod 0644 "$BOOT_FRAME_CONTRACT"
[ -f "$BOOT_FRAME_CONTRACT" ] && [ ! -L "$BOOT_FRAME_CONTRACT" ] || \
	fail 'generated boot-frame contract missing or unsafe'
BOOT_FRAME_ASSET_SHA=$(awk -F '\t' '$1 == "asset-sha256" {print $2}' \
	"$BOOT_FRAME_CONTRACT")
BOOT_FRAME_VISIBLE_HASH_A=$(awk -F '\t' '$1 == "visible-hash-a" {print $2}' \
	"$BOOT_FRAME_CONTRACT")
BOOT_FRAME_VISIBLE_HASH_B=$(awk -F '\t' '$1 == "visible-hash-b" {print $2}' \
	"$BOOT_FRAME_CONTRACT")
case "$BOOT_FRAME_ASSET_SHA:$BOOT_FRAME_VISIBLE_HASH_A:$BOOT_FRAME_VISIBLE_HASH_B" in
	fca1176e4247c5b358df495cf062e88ff53c3aa781c54325545a02b26a9fcb15:849df1c7262d2e3e:754469f5749caa71) ;;
	*) fail 'generated boot-frame contract identity changed' ;;
esac
case "${BIRD_REUSE_UBOOT_FRAME:-0}" in
	0|'') ;;
	1)
		VERIFIED_CONTRACT=${BIRD_BOOT_FRAME_VERIFIED_CONTRACT:-}
		[ -n "$VERIFIED_CONTRACT" ] && [ -f "$VERIFIED_CONTRACT" ] && \
			[ ! -L "$VERIFIED_CONTRACT" ] || \
			fail 'U-Boot frame reuse requires a hardware-verified contract'
		cmp "$BOOT_FRAME_CONTRACT" "$VERIFIED_CONTRACT" >/dev/null || \
			fail 'hardware-verified boot frame does not match this build contract'
		;;
	*) fail 'invalid BIRD_REUSE_UBOOT_FRAME mode' ;;
esac

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
if [ "$EARLY_STATIC_ASSET_BYTES" -eq 1382400 ]; then
	cp -fp "$BOOT_FRAME_XRGB" "$PAYLOAD/opt/bird/launcher-base.xrgb"
chmod 0644 "$PAYLOAD/opt/bird/launcher-base.xrgb"
fi

sh "$ROOT/kernel/rocknix/build-bird-local-binary.sh" --contract early \
	>>"$OUTPUT/build/build-flags.tsv"
printf 'early-initramfs-compress\trelease\t%s\n' \
	"gzip -n -$BIRD_INITRAMFS_GZIP_LEVEL -c" \
	>>"$OUTPUT/build/build-flags.tsv"

CLANG="$CLANG" LLD="$LLD" READELF="$READELF" \
	sh "$ROOT/kernel/rocknix/build-bird-local-binary.sh" \
	--build early-launcher --object "$OBJECT" --output "$LAUNCHER"

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
		print "  if [ \"${BOOT_STEP}\" = \"mount_storage\" ]; then"
		print "    if ! mount_storage; then"
		print "      printf \"bird mount_storage failed closed\\n\" >/dev/kmsg"
		print "      for BIRD_STORAGE_LOG_ROOT in /run/bird-data /birddata; do"
		print "        if [ -d \"${BIRD_STORAGE_LOG_ROOT}/Bird/log\" ]; then"
		print "          printf \"status=failed step=mount_storage\\n\" >\"${BIRD_STORAGE_LOG_ROOT}/Bird/log/mount-storage-latest.log\""
		print "          break"
		print "        fi"
		print "      done"
		print "      /bird-early.sh storage-failed"
		print "      while :; do sleep 3600; done"
		print "    fi"
		print "  else"
		print "    ${BOOT_STEP}"
		print "  fi"
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
[ "$(grep -c '^  if \[ "${BOOT_STEP}" = "mount_storage" \]; then$' "$PAYLOAD/init")" = 1 ] || \
	fail 'storage integration failure boundary missing'
[ "$(grep -c '^      while :; do sleep 3600; done$' "$PAYLOAD/init")" = 2 ] || \
	fail 'fatal initramfs boundary count changed'
[ "$(grep -c 'mount-storage-latest.log' "$PAYLOAD/init")" = 1 ] || \
	fail 'storage integration failure log missing'
[ "$(grep -c '^/bird-early.sh handoff$' "$PAYLOAD/init")" = 1 ] || \
	fail 'handoff injection count changed'
[ "$(grep -c '^/bird-early.sh resume$' "$PAYLOAD/init")" = 0 ] || \
	fail 'obsolete root bridge injection remained'
[ "$(grep -c '^load_splash() { :; }$' "$PAYLOAD/init")" = 1 ] || \
	fail 'splash suppression injection count changed'
[ "$(grep -c '^    if ! \. /bird-release-loader.sh; then$' "$PAYLOAD/init")" = 1 ] || \
	fail 'versioned release-loader injection count changed'
[ "$(grep -c '^    if ! mount_storage; then$' "$PAYLOAD/init")" = 1 ] || \
	fail 'storage integration status is not checked'
[ "$(grep -c '/flash/post-flash.sh' "$PAYLOAD/init")" = 0 ] || \
	fail 'mutable top-level boot hook remained in versioned init'

cp -fp "$ROOT/kernel/rocknix/stock-root/bird-early.sh" \
	"$PAYLOAD/bird-early.sh"
cp -fp "$ROOT/kernel/rocknix/stock-root/bird-release-loader.sh" \
	"$PAYLOAD/bird-release-loader.sh"
sed "s#BIRD_LOADER_RELEASE=v6\.23\$#BIRD_LOADER_RELEASE=$RELEASE_ID#" \
	"$ROOT/kernel/rocknix/stock-root/bird-release-loader.sh" \
	>"$PAYLOAD/bird-release-loader.sh"
if [ "$EMBED_JOYPAD" -eq 1 ]; then
	cp -fp "$JOYPAD" "$PAYLOAD/opt/bird/rocknix-singleadc-joypad.ko"
fi
chmod 0755 "$PAYLOAD/init" "$PAYLOAD/bird-early.sh" \
	"$PAYLOAD/bird-release-loader.sh"
if [ "$EMBED_JOYPAD" -eq 1 ]; then
	chmod 0644 "$PAYLOAD/opt/bird/rocknix-singleadc-joypad.ko"
fi
[ "$(grep -c '^[[:space:]]*/bird-early.sh watchdog >/dev/null 2>&1 &$' \
	"$PAYLOAD/bird-early.sh")" = 1 ] || \
	fail 'pre-launch storage watchdog count changed'
[ "$(grep -c 'storage-anchor-ready >"$WATCHDOG_DISARM"' \
	"$PAYLOAD/bird-early.sh")" = 1 ] || \
	fail 'storage watchdog disarm authority changed'
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
gzip -n "-$BIRD_INITRAMFS_GZIP_LEVEL" -c "$CPIO" >"$GZIP"
[ "$(stat -f %z "$GZIP" 2>/dev/null || stat -c %s "$GZIP")" -le \
	"$EARLY_INITRAMFS_GZIP_MAX_BYTES" ] || \
	fail 'early overlay exceeded its compressed-initramfs budget'
# Before the physical U-Boot asset is verified, the early overlay carries one
# native fallback base so the requested UI is complete without runtime decode.
# A verified Phase 5B build must drop it and return to the smaller budget.
validate_early_launcher_static_assets

gzip -dc "$GZIP" | (cd "$VERIFY" && cpio -idm 2>"$WORK/verify.log")
cmp "$PAYLOAD/init" "$VERIFY/init" || fail 'verified init changed'
cmp "$PAYLOAD/bird-early.sh" "$VERIFY/bird-early.sh" || \
	fail 'verified early hook changed'
cmp "$PAYLOAD/bird-release-loader.sh" "$VERIFY/bird-release-loader.sh" || \
	fail 'verified release loader changed'
cmp "$LAUNCHER" "$VERIFY/opt/bird/bird-launcher" || \
	fail 'verified early launcher changed'
if [ "$EARLY_STATIC_ASSET_BYTES" -eq 1382400 ]; then
	cmp "$PAYLOAD/opt/bird/launcher-base.xrgb" \
		"$VERIFY/opt/bird/launcher-base.xrgb" || \
		fail 'verified early launcher fallback base changed'
elif [ -e "$VERIFY/opt/bird/launcher-base.xrgb" ]; then
	fail 'verified U-Boot reuse unpacked a duplicate early wallpaper'
fi
if [ "$EMBED_JOYPAD" -eq 1 ]; then
	cmp "$JOYPAD" "$VERIFY/opt/bird/rocknix-singleadc-joypad.ko" || \
		fail 'verified H700 input module changed'
elif [ -e "$VERIFY/opt/bird/rocknix-singleadc-joypad.ko" ]; then
	fail 'built-in H700 input build retained a duplicate early module'
fi

{
	printf '%s  bird-initramfs.cpio\n' "$(sha256 "$CPIO")"
	printf '%s  bird-initramfs.cpio.gz\n' "$(sha256 "$GZIP")"
	printf '%s  early-bird-launcher\n' "$(sha256 "$LAUNCHER")"
} >"$WORK/manifest.sha256"

printf 'Built external Bird early-initramfs overlay: %s\n' "$GZIP"
wc -c "$CPIO" "$GZIP" "$LAUNCHER" "$PAYLOAD/init"
