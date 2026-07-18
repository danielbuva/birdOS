#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORKSPACE=${1:-/Volumes/dani-sp/.firmware-work}
MODE=${2:-}
DEBUGFS=${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}
E2FSCK=${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -d "$WORKSPACE" ] || fail "workspace not found: $WORKSPACE"
[ -x "$DEBUGFS" ] || fail "debugfs is required; install it with: brew install e2fsprogs"
[ -x "$E2FSCK" ] || fail "e2fsck is required; install it with: brew install e2fsprogs"

check_size() {
	NAME=$1
	EXPECTED=$2
	PATHNAME="$WORKSPACE/$NAME"
	[ -f "$PATHNAME" ] || fail "missing $PATHNAME"
	ACTUAL=$(stat -f %z "$PATHNAME")
	[ "$ACTUAL" -eq "$EXPECTED" ] || fail "$NAME is $ACTUAL bytes; expected $EXPECTED"
	printf '%-24s %12s bytes\n' "$NAME" "$ACTUAL"
}

check_size stock-spare.img 8388608
check_size stock-boot-resource.img 33554432
check_size stock-env.img 16777216
check_size stock-boot.img 67108864
check_size stock-rootfs.ext4 8589934592

printf '\nRoot filesystem type and allocation:\n'
file "$WORKSPACE/stock-rootfs.ext4"
"$DEBUGFS" -R stats "$WORKSPACE/stock-rootfs.ext4" 2>/dev/null | \
	awk '/Filesystem volume name:|Filesystem state:|Block count:|Free blocks:|Block size:|Inode count:|Free inodes:/'

printf '\nRead-only ext4 consistency check:\n'
"$E2FSCK" -fn "$WORKSPACE/stock-rootfs.ext4"

if [ "$MODE" = "--checksums" ]; then
	printf '\nFull partition checksums (the 8 GiB rootfs takes a while):\n'
	(
		cd "$WORKSPACE"
		shasum -a 256 -c "$SCRIPT_DIR/checksums.sha256"
	)
fi
