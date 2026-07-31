#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-launcher-runtime.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

CC=${CC:-cc}

python3 "$ROOT/firmware/generate-launcher-bootlogo.py" \
	"$TMP/boot-frame.bmp" --xrgb-output "$TMP/boot-frame.xrgb" >/dev/null

build_and_run() {
	NAME=$1
	shift
	"$CC" -std=c11 -O1 -Wall -Wextra -Werror \
		-Wno-unused-function -Wno-unused-variable "$@" \
		"$ROOT/kernel/rocknix/tests/launcher-runtime-host.c" \
		-o "$TMP/launcher-runtime-host-$NAME"
	"$TMP/launcher-runtime-host-$NAME"
}

build_and_run release
build_and_run profile -DBIRD_PROFILE
build_and_run deep -DBIRD_PROFILE_DEEP
build_and_run boot-frame -DBIRD_PROFILE \
	-DBIRD_REUSE_UBOOT_FRAME -DBIRD_BOOT_FRAME_MANIFEST_VERIFIED \
	-DBIRD_STATIC_BASE_PATH=\"/flash/bird/launcher-base.xrgb\" \
	-DBIRD_BOOT_FRAME_VISIBLE_HASH_A=0x849df1c7262d2e3eUL \
	-DBIRD_BOOT_FRAME_VISIBLE_HASH_B=0x754469f5749caa71UL \
	-DBIRD_BOOT_FRAME_ASSET_ID=0xfca1176e4247c5b3UL \
	-DBIRD_TEST_BOOT_FRAME_XRGB=\"$TMP/boot-frame.xrgb\"

if "$CC" -E -DBIRD_PROFILE_DEEP "$ROOT/launcher/bird-launcher.c" \
		-o "$TMP/production-deep.i" 2>"$TMP/production-deep.err"; then
	printf '%s\n' 'production launcher accepted BIRD_PROFILE_DEEP' >&2
	exit 1
fi
grep -Fq 'BIRD_PROFILE_DEEP is host-test-only' "$TMP/production-deep.err" || {
	printf '%s\n' 'production deep-profile rejection was not explicit' >&2
	exit 1
}

if "$CC" -E -DBIRD_REUSE_UBOOT_FRAME \
	"$ROOT/launcher/bird-launcher.c" >"$TMP/unverified-boot-frame.out" \
	2>"$TMP/unverified-boot-frame.err"; then
	printf '%s\n' 'launcher accepted unverified U-Boot frame reuse' >&2
	exit 1
fi
grep -Fq 'U-Boot frame reuse requires an active manifest-verified boot asset' \
	"$TMP/unverified-boot-frame.err" || {
	printf '%s\n' 'launcher U-Boot frame gate failed for the wrong reason' >&2
	exit 1
}

for BUILDER in build-stock-root-compat.sh build-stock-root-early-initramfs.sh; do
	if BIRD_LAUNCHER_PROFILE=deep \
		"$ROOT/kernel/rocknix/$BUILDER" >"$TMP/$BUILDER.out" \
		2>"$TMP/$BUILDER.err"; then
		printf 'production builder accepted deep profiling: %s\n' "$BUILDER" >&2
		exit 1
	fi
	grep -Fq 'BIRD_PROFILE_DEEP is host-test-only' "$TMP/$BUILDER.err" || {
		printf 'production builder deep-profile rejection was not explicit: %s\n' \
			"$BUILDER" >&2
		exit 1
	}
done
