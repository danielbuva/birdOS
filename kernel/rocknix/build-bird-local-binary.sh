#!/bin/sh
# Compile the fixed Bird launchers and tiny native workers with the exact
# production command contract.  The complete builder, early-overlay builder,
# and development workflow intentionally share this one narrow recipe.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}
LAUNCHER_DIR=$ROOT/launcher

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
usage:
  build-bird-local-binary.sh --contract final|early
  build-bird-local-binary.sh --build COMPONENT --object PATH --output PATH

COMPONENT is one of:
  final-launcher early-launcher bird-pidwait bird-powerstate
  bird-fixed-controls bird-mpv-controls bird-input-tester
EOF
}

file_bytes() {
	stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"
}

if [ -n "${BIRD_LOCAL_LAUNCHER_DIR:-}" ]; then
	case "$BIRD_LOCAL_LAUNCHER_DIR" in
		/*) ;;
		*) fail 'Bird local launcher directory must be absolute' ;;
	esac
	case "$BIRD_LOCAL_LAUNCHER_DIR" in
		*'/../'*|*/..|*'/./'*|*/.|*'//'* )
			fail 'Bird local launcher directory contains an unsafe path component'
			;;
	esac
	[ -d "$BIRD_LOCAL_LAUNCHER_DIR" ] && [ ! -L "$BIRD_LOCAL_LAUNCHER_DIR" ] || \
		fail 'Bird local launcher directory is missing, unsafe, or symlinked'
	LAUNCHER_DIR=$(CDPATH= cd -- "$BIRD_LOCAL_LAUNCHER_DIR" && pwd -P) || \
		fail 'could not resolve Bird local launcher directory'
fi

LAUNCHER_PROFILE_FLAGS=
case "${BIRD_LAUNCHER_PROFILE:-none}" in
	none|0|'') ;;
	profile|1) LAUNCHER_PROFILE_FLAGS=-DBIRD_PROFILE ;;
	deep) fail 'BIRD_PROFILE_DEEP is host-test-only' ;;
	*) fail "unknown BIRD_LAUNCHER_PROFILE mode: $BIRD_LAUNCHER_PROFILE" ;;
esac
LAUNCHER_PROFILE_MODE=${BIRD_LAUNCHER_PROFILE:-release}

BOOT_FRAME_REUSE_FLAGS=
EARLY_STATIC_BASE_FLAGS=
case "${BIRD_REUSE_UBOOT_FRAME:-0}" in
	0|'')
		EARLY_STATIC_BASE_FLAGS='-DBIRD_STATIC_BASE_PATH="/opt/bird/launcher-base.xrgb"'
		;;
	1)
		BOOT_FRAME_REUSE_FLAGS='-DBIRD_REUSE_UBOOT_FRAME -DBIRD_BOOT_FRAME_MANIFEST_VERIFIED -DBIRD_BOOT_FRAME_VISIBLE_HASH_A=0x849df1c7262d2e3eUL -DBIRD_BOOT_FRAME_VISIBLE_HASH_B=0x754469f5749caa71UL -DBIRD_BOOT_FRAME_ASSET_ID=0xfca1176e4247c5b3UL'
		;;
	*) fail 'invalid BIRD_REUSE_UBOOT_FRAME mode' ;;
esac

FINAL_LAUNCHER_COMPILE="--target=aarch64-linux-gnu -mcpu=cortex-a53 -O2 -ffreestanding -ffunction-sections -fdata-sections -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden -nostdlib -Wall -Wextra -Werror -Wno-unused-function -DROM_ROOT=\"/storage/roms\" -DLIVE_STORAGE_ROOT=\"/storage\" -DFAVORITES_PATH=\"/storage/bird-data/Bird/state/favorites.txt\" -DFAVORITES_TEMP=\"/storage/bird-data/Bird/state/favorites.tmp\" -DRECENT_PATH=\"/storage/bird-data/Bird/state/recent.txt\" -DRECENT_TEMP=\"/storage/bird-data/Bird/state/recent.tmp\" -DBIRD_STATIC_BASE_PATH=\"/flash/bird/launcher-base.xrgb\" -DPERSIST_UI_STATE ${LAUNCHER_PROFILE_FLAGS:-} -c launcher/bird-launcher.c"
EARLY_LAUNCHER_COMPILE="--target=aarch64-linux-gnu -mcpu=cortex-a53 -O2 -ffreestanding -ffunction-sections -fdata-sections -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden -nostdlib -Wall -Wextra -Werror -Wno-unused-function -DROM_ROOT=\"/storage/roms\" -DLIVE_STORAGE_ROOT=\"/storage\" -DFAVORITES_PATH=\"/storage/bird-data/Bird/state/favorites.txt\" -DFAVORITES_TEMP=\"/storage/bird-data/Bird/state/favorites.tmp\" -DRECENT_PATH=\"/storage/bird-data/Bird/state/recent.txt\" -DRECENT_TEMP=\"/storage/bird-data/Bird/state/recent.tmp\" -DHANDOFF_ACTION_PATH=\"/run/bird/bird-launch-action\" -DSTORAGE_ANCHOR_MARKER=\"/run/bird/bird-storage-anchor-ready\" -DSTORAGE_READY_SIGNAL=\"/run/bird/bird-storage-ready\" -DPERSIST_UI_STATE -DDEVICE_WAIT_MS=20000UL ${LAUNCHER_PROFILE_FLAGS:-} ${BOOT_FRAME_REUSE_FLAGS:-} ${EARLY_STATIC_BASE_FLAGS:-} -c launcher/bird-launcher.c"
LAUNCHER_LINK='-static --gc-sections --build-id=none -z noexecstack -s -e _start'
SMALL_COMPILE='--target=aarch64-linux-gnu -mcpu=cortex-a53 -Os -ffreestanding -ffunction-sections -fdata-sections -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden -nostdlib -Wall -Wextra -Werror'
SMALL_LINK='-static --gc-sections --build-id=none -z noexecstack -s -e _start'

print_contract() {
	case "$1" in
		final)
			printf 'final-launcher-compile\t%s\t%s\n' \
				"$LAUNCHER_PROFILE_MODE" "$FINAL_LAUNCHER_COMPILE"
			printf 'final-launcher-link\t%s\t%s\n' \
				"$LAUNCHER_PROFILE_MODE" "$LAUNCHER_LINK"
			printf 'bird-pidwait-compile\trelease\t%s -c launcher/bird-pidwait.c\n' \
				"$SMALL_COMPILE"
			printf 'bird-fixed-controls-compile\trelease\t%s -I launcher -c kernel/rocknix/stock-root/bird-fixed-controls.c\n' \
				"$SMALL_COMPILE"
			printf 'bird-mpv-controls-compile\trelease\t%s -I launcher -c kernel/rocknix/stock-root/bird-mpv-controls.c\n' \
				"$SMALL_COMPILE"
			printf 'bird-input-tester-compile\trelease\t%s -I launcher -c launcher/bird-input-tester.c\n' \
				"$SMALL_COMPILE"
			printf 'bird-powerstate-compile\trelease\t%s -c launcher/bird-powerstate.c\n' \
				"$SMALL_COMPILE"
			printf 'small-worker-link\trelease\t%s\n' "$SMALL_LINK"
			;;
		early)
			printf 'early-launcher-compile\t%s\t%s\n' \
				"$LAUNCHER_PROFILE_MODE" "$EARLY_LAUNCHER_COMPILE"
			printf 'early-launcher-link\t%s\t%s\n' \
				"$LAUNCHER_PROFILE_MODE" "$LAUNCHER_LINK"
			;;
		*) fail "unknown Bird local binary contract: $1" ;;
	esac
}

validate_binary() {
	OUTPUT_PATH=$1
	STATIC_ERROR=$2
	INTERP_ERROR=$3
	file "$OUTPUT_PATH" | grep -q 'ARM aarch64.*statically linked' || \
		fail "$STATIC_ERROR"
	if "$READELF" -l "$OUTPUT_PATH" | grep -q ' INTERP '; then
		fail "$INTERP_ERROR"
	fi
}

compile_launcher() {
	VARIANT=$1
	OBJECT_PATH=$2
	OUTPUT_PATH=$3
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
				-DPERSIST_UI_STATE -DDEVICE_WAIT_MS=20000UL
			;;
	esac
	[ -z "$LAUNCHER_PROFILE_FLAGS" ] || set -- "$@" "$LAUNCHER_PROFILE_FLAGS"
	if [ "$VARIANT" = early-launcher ]; then
		case "${BIRD_REUSE_UBOOT_FRAME:-0}" in
			0|'') set -- "$@" '-DBIRD_STATIC_BASE_PATH="/opt/bird/launcher-base.xrgb"' ;;
			1)
				set -- "$@" -DBIRD_REUSE_UBOOT_FRAME \
					-DBIRD_BOOT_FRAME_MANIFEST_VERIFIED \
					-DBIRD_BOOT_FRAME_VISIBLE_HASH_A=0x849df1c7262d2e3eUL \
					-DBIRD_BOOT_FRAME_VISIBLE_HASH_B=0x754469f5749caa71UL \
					-DBIRD_BOOT_FRAME_ASSET_ID=0xfca1176e4247c5b3UL
				;;
		esac
	fi
	[ -f "$LAUNCHER_DIR/bird-launcher.c" ] && \
		[ ! -L "$LAUNCHER_DIR/bird-launcher.c" ] || \
		fail 'Bird local launcher source is missing, unsafe, or symlinked'
	"$CLANG" "$@" -c "$LAUNCHER_DIR/bird-launcher.c" -o "$OBJECT_PATH"
	"$LLD" -static --gc-sections --build-id=none -z noexecstack -s \
		-e _start -o "$OUTPUT_PATH" "$OBJECT_PATH"
	chmod 0755 "$OUTPUT_PATH"
	case "$VARIANT" in
		final-launcher)
			validate_binary "$OUTPUT_PATH" 'launcher is not static AArch64' \
				'launcher unexpectedly has an interpreter'
			MAX_BYTES=600000
			[ -z "$LAUNCHER_PROFILE_FLAGS" ] || MAX_BYTES=660000
			[ "$(file_bytes "$OUTPUT_PATH")" -le "$MAX_BYTES" ] || \
				fail 'final-root launcher exceeded its binary budget'
			;;
		early-launcher)
			validate_binary "$OUTPUT_PATH" 'early launcher is not static AArch64' \
				'early launcher unexpectedly has an interpreter'
			MAX_BYTES=610000
			[ -z "$LAUNCHER_PROFILE_FLAGS" ] || MAX_BYTES=670000
			[ "$(file_bytes "$OUTPUT_PATH")" -le "$MAX_BYTES" ] || \
				fail 'early launcher exceeded its binary budget'
			;;
	esac
}

compile_worker() {
	COMPONENT=$1
	OBJECT_PATH=$2
	OUTPUT_PATH=$3
	INCLUDE_LAUNCHER=0
	case "$COMPONENT" in
		bird-pidwait)
			SOURCE_PATH=$ROOT/launcher/bird-pidwait.c
			STATIC_ERROR='pid waiter is not static AArch64'
			INTERP_ERROR='pid waiter unexpectedly has an interpreter'
			;;
		bird-powerstate)
			SOURCE_PATH=$ROOT/launcher/bird-powerstate.c
			STATIC_ERROR='fixed powerstate is not static AArch64'
			INTERP_ERROR='fixed powerstate unexpectedly has an interpreter'
			;;
		bird-fixed-controls)
			SOURCE_PATH=$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c
			INCLUDE_LAUNCHER=1
			STATIC_ERROR='fixed controls are not static AArch64'
			INTERP_ERROR='fixed controls unexpectedly have an interpreter'
			;;
		bird-mpv-controls)
			SOURCE_PATH=$ROOT/kernel/rocknix/stock-root/bird-mpv-controls.c
			INCLUDE_LAUNCHER=1
			STATIC_ERROR='MPV controls are not static AArch64'
			INTERP_ERROR='MPV controls unexpectedly have an interpreter'
			;;
		bird-input-tester)
			SOURCE_PATH=$ROOT/launcher/bird-input-tester.c
			INCLUDE_LAUNCHER=1
			STATIC_ERROR='input tester is not static AArch64'
			INTERP_ERROR='input tester unexpectedly has an interpreter'
			;;
	esac
	set -- --target=aarch64-linux-gnu -mcpu=cortex-a53 -Os \
		-ffreestanding -ffunction-sections -fdata-sections \
		-fno-builtin -fno-stack-protector -fno-unwind-tables \
		-fno-asynchronous-unwind-tables -fno-ident -fvisibility=hidden \
		-nostdlib -Wall -Wextra -Werror
	if [ "$INCLUDE_LAUNCHER" -ne 0 ]; then
		[ -f "$LAUNCHER_DIR/bird-device-contract.h" ] && \
			[ ! -L "$LAUNCHER_DIR/bird-device-contract.h" ] || \
			fail 'Bird local device-contract header is missing, unsafe, or symlinked'
		set -- "$@" -I "$LAUNCHER_DIR"
	fi
	"$CLANG" "$@" -c "$SOURCE_PATH" -o "$OBJECT_PATH"
	"$LLD" -static --gc-sections --build-id=none -z noexecstack -s \
		-e _start -o "$OUTPUT_PATH" "$OBJECT_PATH"
	chmod 0755 "$OUTPUT_PATH"
	validate_binary "$OUTPUT_PATH" "$STATIC_ERROR" "$INTERP_ERROR"
	if [ "$COMPONENT" = bird-input-tester ]; then
		[ "$(file_bytes "$OUTPUT_PATH")" -le 32768 ] || \
			fail 'input tester exceeded its binary budget'
	fi
}

[ "$#" -gt 0 ] || { usage >&2; exit 2; }
case "$1" in
	--contract)
		[ "$#" -eq 2 ] || fail '--contract requires exactly final or early'
		print_contract "$2"
		exit 0
		;;
	--build)
		[ "$#" -eq 6 ] && [ "$3" = --object ] && [ "$5" = --output ] || \
			fail '--build requires COMPONENT --object PATH --output PATH'
		COMPONENT=$2
		OBJECT=$4
		OUTPUT=$6
		;;
	--help|-h)
		[ "$#" -eq 1 ] || fail '--help takes no arguments'
		usage
		exit 0
		;;
	*) fail "unknown Bird local binary action: $1" ;;
esac

case "$COMPONENT" in
	final-launcher|early-launcher|bird-pidwait|bird-powerstate|bird-fixed-controls|bird-mpv-controls|bird-input-tester) ;;
	*) fail "unknown Bird local binary component: $COMPONENT" ;;
esac
[ -n "$OBJECT" ] && [ -n "$OUTPUT" ] || fail 'empty object or output path'
[ -d "$(dirname "$OBJECT")" ] || fail "object directory missing: $(dirname "$OBJECT")"
[ -d "$(dirname "$OUTPUT")" ] || fail "output directory missing: $(dirname "$OUTPUT")"
[ -x "$CLANG" ] || fail 'LLVM clang missing'
[ -x "$LLD" ] || fail 'LLVM lld missing'
[ -x "$READELF" ] || fail 'LLVM readelf missing'

case "$COMPONENT" in
	final-launcher|early-launcher) compile_launcher "$COMPONENT" "$OBJECT" "$OUTPUT" ;;
	*) compile_worker "$COMPONENT" "$OBJECT" "$OUTPUT" ;;
esac
