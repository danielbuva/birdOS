#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
HELPER=$ROOT/kernel/rocknix/build-bird-local-binary.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-local-binary.XXXXXX")
TMP=$(CDPATH= cd -- "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

# The recorded command contract is part of release provenance. Keep the exact
# pre-extraction spelling, ordering, modes and deliberate empty-flag spacing.
sh "$HELPER" --contract final >"$TMP/final.actual"
{
	printf '%s\n' 'final-launcher-compile\trelease\t--target=aarch64-linux-gnu -mcpu=cortex-a53 -O2 -ffreestanding -ffunction-sections -fdata-sections -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden -nostdlib -Wall -Wextra -Werror -Wno-unused-function -DROM_ROOT="/storage/roms" -DLIVE_STORAGE_ROOT="/storage" -DFAVORITES_PATH="/storage/bird-data/Bird/state/favorites.txt" -DFAVORITES_TEMP="/storage/bird-data/Bird/state/favorites.tmp" -DRECENT_PATH="/storage/bird-data/Bird/state/recent.txt" -DRECENT_TEMP="/storage/bird-data/Bird/state/recent.tmp" -DBIRD_STATIC_BASE_PATH="/flash/bird/launcher-base.xrgb" -DPERSIST_UI_STATE  -c launcher/bird-launcher.c'
	printf '%s\n' 'final-launcher-link\trelease\t-static --gc-sections --build-id=none -z noexecstack -s -e _start'
	printf '%s\n' 'bird-pidwait-compile\trelease\t--target=aarch64-linux-gnu -mcpu=cortex-a53 -Os -ffreestanding -ffunction-sections -fdata-sections -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden -nostdlib -Wall -Wextra -Werror -c launcher/bird-pidwait.c'
	printf '%s\n' 'bird-fixed-controls-compile\trelease\t--target=aarch64-linux-gnu -mcpu=cortex-a53 -Os -ffreestanding -ffunction-sections -fdata-sections -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden -nostdlib -Wall -Wextra -Werror -I launcher -c kernel/rocknix/stock-root/bird-fixed-controls.c'
	printf '%s\n' 'bird-mpv-controls-compile\trelease\t--target=aarch64-linux-gnu -mcpu=cortex-a53 -Os -ffreestanding -ffunction-sections -fdata-sections -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden -nostdlib -Wall -Wextra -Werror -I launcher -c kernel/rocknix/stock-root/bird-mpv-controls.c'
	printf '%s\n' 'bird-powerstate-compile\trelease\t--target=aarch64-linux-gnu -mcpu=cortex-a53 -Os -ffreestanding -ffunction-sections -fdata-sections -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden -nostdlib -Wall -Wextra -Werror -c launcher/bird-powerstate.c'
	printf '%s\n' 'small-worker-link\trelease\t-static --gc-sections --build-id=none -z noexecstack -s -e _start'
} | sed 's/\\t/'"$(printf '\t')"'/g' >"$TMP/final.expected"
cmp "$TMP/final.expected" "$TMP/final.actual" || \
	fail 'final command contract changed during extraction'

sh "$HELPER" --contract early >"$TMP/early.actual"
{
	printf '%s\n' 'early-launcher-compile\trelease\t--target=aarch64-linux-gnu -mcpu=cortex-a53 -O2 -ffreestanding -ffunction-sections -fdata-sections -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden -nostdlib -Wall -Wextra -Werror -Wno-unused-function -DROM_ROOT="/storage/roms" -DLIVE_STORAGE_ROOT="/storage" -DFAVORITES_PATH="/storage/bird-data/Bird/state/favorites.txt" -DFAVORITES_TEMP="/storage/bird-data/Bird/state/favorites.tmp" -DRECENT_PATH="/storage/bird-data/Bird/state/recent.txt" -DRECENT_TEMP="/storage/bird-data/Bird/state/recent.tmp" -DHANDOFF_ACTION_PATH="/run/bird/bird-launch-action" -DSTORAGE_ANCHOR_MARKER="/run/bird/bird-storage-anchor-ready" -DSTORAGE_READY_SIGNAL="/run/bird/bird-storage-ready" -DPERSIST_UI_STATE -DDEVICE_WAIT_MS=20000UL   -DBIRD_STATIC_BASE_PATH="/opt/bird/launcher-base.xrgb" -c launcher/bird-launcher.c'
	printf '%s\n' 'early-launcher-link\trelease\t-static --gc-sections --build-id=none -z noexecstack -s -e _start'
} | sed 's/\\t/'"$(printf '\t')"'/g' >"$TMP/early.expected"
cmp "$TMP/early.expected" "$TMP/early.actual" || \
	fail 'early command contract changed during extraction'

# A private launcher tree lets the dev workflow compile generated headers and
# launcher bytes without modifying the checkout. It must never change the
# canonical provenance spelling, and unsafe override paths fail before compile.
OVERRIDE=$TMP/launcher-override
mkdir -p "$OVERRIDE"
OVERRIDE=$(CDPATH= cd -- "$OVERRIDE" && pwd -P)
cp "$ROOT/launcher/bird-launcher.c" "$ROOT/launcher/catalog.generated.h" \
	"$ROOT/launcher/bird-device-contract.h" "$OVERRIDE/"
BIRD_LOCAL_LAUNCHER_DIR=$OVERRIDE sh "$HELPER" --contract final \
	>"$TMP/final.override-contract"
BIRD_LOCAL_LAUNCHER_DIR=$OVERRIDE sh "$HELPER" --contract early \
	>"$TMP/early.override-contract"
cmp "$TMP/final.actual" "$TMP/final.override-contract" || \
	fail 'launcher source override changed the final recorded command contract'
cmp "$TMP/early.actual" "$TMP/early.override-contract" || \
	fail 'launcher source override changed the early recorded command contract'
if BIRD_LOCAL_LAUNCHER_DIR=relative/path sh "$HELPER" --contract final \
	>"$TMP/relative.out" 2>"$TMP/relative.err"; then
	fail 'relative launcher source override was accepted'
fi
grep -Fq 'launcher directory must be absolute' "$TMP/relative.err" || \
	fail 'relative launcher source rejection was not diagnostic'
ln -s "$OVERRIDE" "$TMP/launcher-override-link"
if BIRD_LOCAL_LAUNCHER_DIR=$TMP/launcher-override-link \
	sh "$HELPER" --contract final >"$TMP/symlink.out" 2>"$TMP/symlink.err"; then
	fail 'symlinked launcher source override was accepted'
fi
grep -Fq 'missing, unsafe, or symlinked' "$TMP/symlink.err" || \
	fail 'symlinked launcher source rejection was not diagnostic'

BIRD_LAUNCHER_PROFILE=profile sh "$HELPER" --contract final \
	>"$TMP/profile.contract"
grep -Fq 'final-launcher-compile' "$TMP/profile.contract" &&
	grep -Fq -- '-DPERSIST_UI_STATE -DBIRD_PROFILE -c launcher/bird-launcher.c' \
		"$TMP/profile.contract" || fail 'profile launcher contract changed'
BIRD_REUSE_UBOOT_FRAME=1 sh "$HELPER" --contract early \
	>"$TMP/reuse.contract"
grep -Fq -- '-DBIRD_BOOT_FRAME_ASSET_ID=0xfca1176e4247c5b3UL' \
	"$TMP/reuse.contract" || fail 'verified frame-reuse contract changed'
if grep -Fq 'BIRD_STATIC_BASE_PATH' "$TMP/reuse.contract"; then
	fail 'verified frame-reuse contract retained the early static base'
fi
if BIRD_LAUNCHER_PROFILE=deep sh "$HELPER" --contract final \
	>"$TMP/deep.out" 2>"$TMP/deep.err"; then
	fail 'host-only deep profiling was accepted by the production helper'
fi
grep -Fq 'BIRD_PROFILE_DEEP is host-test-only' "$TMP/deep.err" ||
	fail 'deep-profile rejection was not diagnostic'

# When the pinned LLVM tools are present, compare every resulting ELF with the
# previous in-builder command recipe. No source or asset fixture is substituted.
for TOOL in "$CLANG" "$LLD" "$READELF"; do
	if [ ! -x "$TOOL" ]; then
		printf 'bird local binary tests: PASS (byte identity skipped; missing %s)\n' \
			"$TOOL"
		exit 0
	fi
done
mkdir -p "$TMP/legacy" "$TMP/shared"

legacy_link() {
	"$LLD" -static --gc-sections --build-id=none -z noexecstack -s \
		-e _start -o "$2" "$1"
}

legacy_launcher() {
	VARIANT=$1
	OBJECT=$2
	OUTPUT=$3
	set -- --target=aarch64-linux-gnu -mcpu=cortex-a53 -O2 \
		-ffreestanding -ffunction-sections -fdata-sections \
		-fno-builtin -fno-stack-protector -fno-unwind-tables \
		-fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden \
		-nostdlib -Wall -Wextra -Werror -Wno-unused-function \
		'-DROM_ROOT="/storage/roms"' \
		'-DLIVE_STORAGE_ROOT="/storage"' \
		'-DFAVORITES_PATH="/storage/bird-data/Bird/state/favorites.txt"' \
		'-DFAVORITES_TEMP="/storage/bird-data/Bird/state/favorites.tmp"' \
		'-DRECENT_PATH="/storage/bird-data/Bird/state/recent.txt"' \
		'-DRECENT_TEMP="/storage/bird-data/Bird/state/recent.tmp"'
	case "$VARIANT" in
		final-launcher)
			set -- "$@" '-DBIRD_STATIC_BASE_PATH="/flash/bird/launcher-base.xrgb"' \
				-DPERSIST_UI_STATE
			;;
		early-launcher)
			set -- "$@" '-DHANDOFF_ACTION_PATH="/run/bird/bird-launch-action"' \
				'-DSTORAGE_ANCHOR_MARKER="/run/bird/bird-storage-anchor-ready"' \
				'-DSTORAGE_READY_SIGNAL="/run/bird/bird-storage-ready"' \
				-DPERSIST_UI_STATE -DDEVICE_WAIT_MS=20000UL \
				'-DBIRD_STATIC_BASE_PATH="/opt/bird/launcher-base.xrgb"'
			;;
	esac
	"$CLANG" "$@" -c "$ROOT/launcher/bird-launcher.c" -o "$OBJECT"
	legacy_link "$OBJECT" "$OUTPUT"
}

legacy_worker() {
	COMPONENT=$1
	OBJECT=$2
	OUTPUT=$3
	case "$COMPONENT" in
		bird-pidwait) SOURCE=$ROOT/launcher/bird-pidwait.c; INCLUDE=0 ;;
		bird-powerstate) SOURCE=$ROOT/launcher/bird-powerstate.c; INCLUDE=0 ;;
		bird-fixed-controls)
			SOURCE=$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c
			INCLUDE=1
			;;
		bird-mpv-controls)
			SOURCE=$ROOT/kernel/rocknix/stock-root/bird-mpv-controls.c
			INCLUDE=1
			;;
	esac
	set -- --target=aarch64-linux-gnu -mcpu=cortex-a53 -Os \
		-ffreestanding -ffunction-sections -fdata-sections \
		-fno-builtin -fno-stack-protector -fno-unwind-tables \
		-fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden \
		-nostdlib -Wall -Wextra -Werror
	[ "$INCLUDE" -eq 0 ] || set -- "$@" -I "$ROOT/launcher"
	"$CLANG" "$@" -c "$SOURCE" -o "$OBJECT"
	legacy_link "$OBJECT" "$OUTPUT"
}

for COMPONENT in final-launcher early-launcher; do
	legacy_launcher "$COMPONENT" "$TMP/legacy/$COMPONENT.o" \
		"$TMP/legacy/$COMPONENT"
	CLANG="$CLANG" LLD="$LLD" READELF="$READELF" sh "$HELPER" \
		--build "$COMPONENT" --object "$TMP/shared/$COMPONENT.o" \
		--output "$TMP/shared/$COMPONENT"
	cmp "$TMP/legacy/$COMPONENT" "$TMP/shared/$COMPONENT" ||
		fail "$COMPONENT output is not byte-identical to the previous recipe"
	BIRD_LAUNCHER_PROFILE=profile CLANG="$CLANG" LLD="$LLD" \
		READELF="$READELF" sh "$HELPER" --build "$COMPONENT" \
		--object "$TMP/shared/$COMPONENT-profile.o" \
		--output "$TMP/shared/$COMPONENT-profile"
done

for COMPONENT in bird-pidwait bird-powerstate bird-fixed-controls \
	bird-mpv-controls; do
	legacy_worker "$COMPONENT" "$TMP/legacy/$COMPONENT.o" \
		"$TMP/legacy/$COMPONENT"
	CLANG="$CLANG" LLD="$LLD" READELF="$READELF" sh "$HELPER" \
		--build "$COMPONENT" --object "$TMP/shared/$COMPONENT.o" \
		--output "$TMP/shared/$COMPONENT"
	cmp "$TMP/legacy/$COMPONENT" "$TMP/shared/$COMPONENT" ||
		fail "$COMPONENT output is not byte-identical to the previous recipe"
done

# Prove the override controls launcher source/header lookup and worker includes,
# while pidwait and powerstate remain sourced from the canonical launcher tree.
printf '%s\n' '#error "override header selected"' \
	>"$OVERRIDE/bird-device-contract.h"
if BIRD_LOCAL_LAUNCHER_DIR=$OVERRIDE CLANG="$CLANG" LLD="$LLD" \
	READELF="$READELF" sh "$HELPER" --build final-launcher \
	--object "$TMP/shared/override-fail-launcher.o" \
	--output "$TMP/shared/override-fail-launcher" \
	>"$TMP/override-launcher.out" 2>"$TMP/override-launcher.err"; then
	fail 'launcher build ignored its private generated header'
fi
grep -Fq 'override header selected' "$TMP/override-launcher.err" || \
	fail 'launcher override failure did not come from the private header'
if BIRD_LOCAL_LAUNCHER_DIR=$OVERRIDE CLANG="$CLANG" LLD="$LLD" \
	READELF="$READELF" sh "$HELPER" --build bird-fixed-controls \
	--object "$TMP/shared/override-fail-controls.o" \
	--output "$TMP/shared/override-fail-controls" \
	>"$TMP/override-controls.out" 2>"$TMP/override-controls.err"; then
	fail 'fixed controls ignored the private generated-header include root'
fi
grep -Fq 'override header selected' "$TMP/override-controls.err" || \
	fail 'controls override failure did not come from the private header'
cp "$ROOT/launcher/bird-device-contract.h" \
	"$OVERRIDE/bird-device-contract.h"
for COMPONENT in final-launcher early-launcher bird-fixed-controls \
	bird-mpv-controls bird-pidwait bird-powerstate; do
	BIRD_LOCAL_LAUNCHER_DIR=$OVERRIDE CLANG="$CLANG" LLD="$LLD" \
		READELF="$READELF" sh "$HELPER" --build "$COMPONENT" \
		--object "$TMP/shared/override-$COMPONENT.o" \
		--output "$TMP/shared/override-$COMPONENT"
done

printf 'bird local binary tests: PASS\n'
