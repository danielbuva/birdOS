#!/bin/bash
# Host-only proof that boot verification failures persist evidence and stop
# without changing the selected release or invoking an alternate boot path.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
LOADER=$ROOT/kernel/rocknix/stock-root/bird-release-loader.sh
POST_FLASH=$ROOT/kernel/rocknix/stock-root/post-flash.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-boot-failure.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

FLASH=$TMP/flash
CMDLINE=$TMP/cmdline
mkdir -p "$FLASH/extlinux" "$FLASH/bird-releases"
printf '%s\n' 'production-selector' >"$FLASH/extlinux/extlinux.conf"
SELECTOR_BEFORE=$(shasum -a 256 "$FLASH/extlinux/extlinux.conf" | awk '{print $1}')

run_loader_failure() (
	BIRD_HOST_TEST_MODE=1
	BIRD_LOADER_FLASH=$FLASH
	BIRD_LOADER_CMDLINE=$CMDLINE
	BIRD_LOADER_RELEASE=dev-current
	BIRD_LOADER_BUSYBOX=
	export BIRD_HOST_TEST_MODE BIRD_LOADER_FLASH BIRD_LOADER_CMDLINE \
		BIRD_LOADER_RELEASE BIRD_LOADER_BUSYBOX
	mount() { return 0; }
	error() { printf 'error-called\t%s\t%s\n' "$1" "$2" >>"$TMP/error.log"; return 1; }
	export -f mount error
	# shellcheck source=/dev/null
	. "$LOADER"
)

printf '%s\n' 'quiet bird_release=wrong' >"$CMDLINE"
if run_loader_failure; then
	printf '%s\n' 'malformed selector unexpectedly passed release loader' >&2
	exit 1
fi
[ "$(shasum -a 256 "$FLASH/extlinux/extlinux.conf" | awk '{print $1}')" = \
	"$SELECTOR_BEFORE" ]
grep -Fqx 'release=wrong' "$FLASH/bird-loader-failure.txt"
grep -Fqx 'reason=unexpected release selector: wrong' \
	"$FLASH/bird-loader-failure.txt"
grep -Fq 'error-called' "$TMP/error.log"

rm -f "$FLASH/bird-loader-failure.txt" "$TMP/error.log"
printf '%s\n' 'quiet bird_release=dev-current' >"$CMDLINE"
if run_loader_failure; then
	printf '%s\n' 'incomplete release unexpectedly passed release loader' >&2
	exit 1
fi
[ "$(shasum -a 256 "$FLASH/extlinux/extlinux.conf" | awk '{print $1}')" = \
	"$SELECTOR_BEFORE" ]
grep -Fqx 'release=dev-current' "$FLASH/bird-loader-failure.txt"
grep -Fqx 'reason=selected release is incomplete' \
	"$FLASH/bird-loader-failure.txt"

if grep -Eq 'KERNEL\.fallback|extlinux\.fallback|reboot -f|write_attempts|fallback_boot' \
		"$LOADER" "$POST_FLASH"; then
	printf '%s\n' 'alternate-boot or retry machinery remains in active hooks' >&2
	exit 1
fi
grep -Fq 'bird_loader_record_failure "$1"' "$LOADER"
grep -Fq 'stop_boot bird-release "Release verification failed: $BIRD_RELEASE"' \
	"$POST_FLASH"
grep -Fq 'BIRD_SYSTEM_REL=Bird/runtime/$BIRD_RELEASE/ROCKNIX-SYSTEM' \
	"$POST_FLASH"
grep -Fq 'inputs != 14' "$POST_FLASH"

printf '%s\n' 'boot failure persistence tests passed'
