#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
. "$ROOT/firmware/mac-removable-device.sh"

grep -Fq 'rocknix-bird-prefix-compat-v3/bird-rocknix-prefix.img' \
	"$ROOT/firmware/mac-install-rocknix-bird-prefix.sh" || {
	printf 'prefix installer does not select the v3 builder output\n' >&2
	exit 1
}
grep -Fq 'PREFIX_SHA=6f5f6cec067c9e03c088d629c9a31f9f382d6302e1095fbacd66fde1476761cb' \
	"$ROOT/firmware/mac-install-rocknix-bird-prefix.sh" || {
	printf 'prefix installer digest differs from the reproduced v3 prefix\n' >&2
	exit 1
}
grep -Fq 'RECOVERY_SHA=0bcacc83bf7345306ef7615be1012b5c7dd0a92630cf764f34b049f88e9b9f78' \
	"$ROOT/firmware/mac-reimage-bird-prefix.sh" || {
	printf 'combined reimage recovery digest changed\n' >&2
	exit 1
}
grep -Fq 'BIRD_PREFIX_SHA=6f5f6cec067c9e03c088d629c9a31f9f382d6302e1095fbacd66fde1476761cb' \
	"$ROOT/firmware/mac-reimage-bird-prefix.sh" || {
	printf 'combined reimage Bird prefix digest changed\n' >&2
	exit 1
}

fail() {
	printf '%s\n' "$*" >&2
	exit 1
}

plist_value() {
	case $2 in
	Internal) printf '%s\n' "$TEST_INTERNAL" ;;
	Removable) printf '%s\n' "$TEST_REMOVABLE" ;;
	OSInternalMedia) printf '%s\n' "$TEST_OS_INTERNAL" ;;
	BusProtocol) printf '%s\n' "$TEST_PROTOCOL" ;;
	MediaName) printf '%s\n' "$TEST_MEDIA_NAME" ;;
	VirtualOrPhysical) printf '%s\n' "$TEST_PHYSICAL" ;;
	WholeDisk) printf '%s\n' "$TEST_WHOLE" ;;
	*) exit 1 ;;
	esac
}

set_case() {
	TEST_INTERNAL=$1
	TEST_REMOVABLE=$2
	TEST_OS_INTERNAL=$3
	TEST_PROTOCOL=$4
	TEST_MEDIA_NAME=$5
	TEST_PHYSICAL=$6
	TEST_WHOLE=$7
}

expect_accept() {
	( bird_require_safe_removable_device /dev/test ) ||
		fail "safe-device case was rejected: $*"
}

expect_reject() {
	if ( bird_require_safe_removable_device /dev/test ) >/dev/null 2>&1; then
		fail "unsafe-device case was accepted: $*"
	fi
}

set_case false true false USB External Physical true
expect_accept external-removable

set_case true true false 'Secure Digital' 'Built In SDXC Reader' Physical true
expect_accept built-in-sdxc

set_case true false false 'Secure Digital' 'Built In SDXC Reader' Physical true
expect_reject non-removable

set_case true true true 'Secure Digital' 'Built In SDXC Reader' Physical true
expect_reject os-internal

set_case true true false USB 'Built In SDXC Reader' Physical true
expect_reject wrong-protocol

set_case true true false 'Secure Digital' 'Other Reader' Physical true
expect_reject wrong-media-name

set_case true true false 'Secure Digital' 'Built In SDXC Reader' Virtual true
expect_reject virtual-device

set_case true true false 'Secure Digital' 'Built In SDXC Reader' Physical false
expect_reject partition-device

printf 'mac removable-device guard tests: PASS\n'
