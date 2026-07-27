#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-launcher-runtime.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

CC=${CC:-cc}

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

if "$CC" -E -DBIRD_PROFILE_DEEP "$ROOT/launcher/bird-launcher.c" \
		-o "$TMP/production-deep.i" 2>"$TMP/production-deep.err"; then
	printf '%s\n' 'production launcher accepted BIRD_PROFILE_DEEP' >&2
	exit 1
fi
grep -Fq 'BIRD_PROFILE_DEEP is host-test-only' "$TMP/production-deep.err" || {
	printf '%s\n' 'production deep-profile rejection was not explicit' >&2
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
