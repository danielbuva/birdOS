#!/bin/sh
# Build the compatibility-first Bird milestone from one exact ROCKNIX release.
# KERNEL, dtb.img, SYSTEM and the initial STORAGE filesystem are checksummed as
# a set. Only Bird's normal userspace executable and tiny integration hooks are
# built here.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SOURCE=${SOURCE:-/Volumes/ROCKNIX}
STORAGE=${STORAGE:-/Users/dani/rocknix-reference-result/storage.ext4}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-rocknix-stock-root-v6}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}

KERNEL_SHA=af4e75cb30b097ee5764764eb056d686bc00c6bd03fefece26b0ebbaa7fbb673
DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
SYSTEM_SHA=6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac
STORAGE_SHA=12affdad7bc2042cb590fea60fc015a7ee8d4374ebcc3b1c11098a64b9ffa3be

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

[ -d "$SOURCE" ] || fail "mounted exact ROCKNIX release missing: $SOURCE"
[ -f "$SOURCE/KERNEL" ] || fail 'release KERNEL missing'
[ -f "$SOURCE/dtb.img" ] || fail 'release DTB missing'
[ -f "$SOURCE/SYSTEM" ] || fail 'release SYSTEM missing'
[ -f "$STORAGE" ] || fail 'captured ROCKNIX STORAGE image missing'
[ "$(sha256 "$SOURCE/KERNEL")" = "$KERNEL_SHA" ] || fail 'release KERNEL changed'
[ "$(sha256 "$SOURCE/dtb.img")" = "$DTB_SHA" ] || fail 'release DTB changed'
[ "$(sha256 "$SOURCE/SYSTEM")" = "$SYSTEM_SHA" ] || fail 'release SYSTEM changed'
[ "$(sha256 "$STORAGE")" = "$STORAGE_SHA" ] || fail 'reference STORAGE changed'
[ -x "$CLANG" ] || fail 'LLVM clang missing'
[ -x "$LLD" ] || fail 'LLVM lld missing'
[ -x "$READELF" ] || fail 'LLVM readelf missing'
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"

mkdir -p "$OUTPUT/card/bird" "$OUTPUT/card/extlinux" "$OUTPUT/build"

"$CLANG" --target=aarch64-linux-gnu -mcpu=cortex-a53 -O2 \
	-ffreestanding -ffunction-sections -fdata-sections \
	-fno-builtin -fno-stack-protector -fno-unwind-tables \
	-fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden \
	-nostdlib -Wall -Wextra -Werror -Wno-unused-function \
	'-DROM_ROOT="/storage/bird-data/ROMS"' \
	'-DFAVORITES_PATH="/storage/.config/bird/favorites.txt"' \
	'-DFAVORITES_TEMP="/storage/.config/bird/favorites.tmp"' \
	'-DRECENT_PATH="/storage/.config/bird/recent.txt"' \
	'-DRECENT_TEMP="/storage/.config/bird/recent.tmp"' \
	-c "$ROOT/launcher/dani-launcher.c" \
	-o "$OUTPUT/build/dani-launcher.o"
"$LLD" -static --gc-sections --build-id=none -z noexecstack -s \
	-e _start -o "$OUTPUT/card/bird/dani-launcher" \
	"$OUTPUT/build/dani-launcher.o"
chmod 0755 "$OUTPUT/card/bird/dani-launcher"
file "$OUTPUT/card/bird/dani-launcher" | \
	grep -q 'ARM aarch64.*statically linked' || fail 'launcher is not static AArch64'
if "$READELF" -l "$OUTPUT/card/bird/dani-launcher" | grep -q ' INTERP '; then
	fail 'launcher unexpectedly has an interpreter'
fi

cp -fp "$SOURCE/KERNEL" "$OUTPUT/card/KERNEL"
cp -fp "$SOURCE/dtb.img" "$OUTPUT/card/dtb.img"
cp -fp "$ROOT/kernel/rocknix/stock-root/post-flash.sh" \
	"$OUTPUT/card/post-flash.sh"
cp -fp "$ROOT/kernel/rocknix/stock-root/mount-storage.sh" \
	"$OUTPUT/card/mount-storage.sh"
for FILE in 090-ui_service essway.service rocknix.target supervisor.sh run-content.sh; do
	cp -fp "$ROOT/kernel/rocknix/stock-root/$FILE" "$OUTPUT/card/bird/$FILE"
done
cp -fp "$ROOT/kernel/rocknix/stock-root/extlinux.conf" \
	"$OUTPUT/card/extlinux/extlinux.conf"
cp -fp "$ROOT/kernel/rocknix/stock-root/extlinux.fallback.conf" \
	"$OUTPUT/card/extlinux/extlinux.fallback.conf"
touch "$OUTPUT/card/SYSTEM"
chmod 0755 "$OUTPUT/card/post-flash.sh" "$OUTPUT/card/mount-storage.sh" \
	"$OUTPUT/card/bird/090-ui_service" \
	"$OUTPUT/card/bird/supervisor.sh" "$OUTPUT/card/bird/run-content.sh"

for SCRIPT in "$OUTPUT/card/post-flash.sh" \
	"$OUTPUT/card/mount-storage.sh" \
	"$OUTPUT/card/bird/090-ui_service" \
	"$OUTPUT/card/bird/supervisor.sh" \
	"$OUTPUT/card/bird/run-content.sh"; do
	bash -n "$SCRIPT" || fail "shell syntax failed: $SCRIPT"
done

[ "$(sha256 "$OUTPUT/card/KERNEL")" = "$KERNEL_SHA" ] || fail 'copied KERNEL changed'
[ "$(sha256 "$OUTPUT/card/dtb.img")" = "$DTB_SHA" ] || fail 'copied DTB changed'
grep -q 'runemu.sh' "$OUTPUT/card/bird/run-content.sh" || fail 'ROCKNIX dispatcher missing'
grep -q 'ExecStart=/storage/.config/bird/supervisor.sh' \
	"$OUTPUT/card/bird/essway.service" || fail 'Bird UI unit missing'
grep -q '^UI_SERVICE="essway.service"$' \
	"$OUTPUT/card/bird/090-ui_service" || fail 'boot compositor deferral missing'
grep -q '^JobTimeoutAction=reboot-force$' \
	"$OUTPUT/card/bird/rocknix.target" || fail 'target watchdog missing'

{
	printf '%s  KERNEL\n' "$KERNEL_SHA"
	printf '%s  dtb.img\n' "$DTB_SHA"
	printf '%s  ROCKNIX-SYSTEM\n' "$SYSTEM_SHA"
	printf '%s  ROCKNIX-STORAGE\n' "$STORAGE_SHA"
	printf '%s  bird/dani-launcher\n' \
		"$(sha256 "$OUTPUT/card/bird/dani-launcher")"
} >"$OUTPUT/manifest.sha256"

printf 'Built exact ROCKNIX compatibility baseline: %s\n' "$OUTPUT"
printf 'KERNEL remains byte-identical to release 20260701: %s\n' "$KERNEL_SHA"
printf 'Bird launcher: %s\n' "$(sha256 "$OUTPUT/card/bird/dani-launcher")"
