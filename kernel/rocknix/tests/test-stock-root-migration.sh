#!/bin/sh
# Host-only identity, filesystem and idempotency checks for the explicit Ports
# migration. All paths and metadata are private temporary fixtures.

set -eu

if [ "$(uname -s)" != Darwin ]; then
	printf '%s\n' 'stock-root migration test skipped: macOS host required'
	exit 0
fi

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
MIGRATION=$ROOT/firmware/mac-migrate-rocknix-ports.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-migration.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
BIRD=$TMP/BIRD
DATA=$TMP/BIRD-DATA
INFO=$TMP/device-info.tsv
mkdir -p "$BIRD" "$DATA/ports/GameA"

write_info() {
	DATA_WHOLE=$1
	DATA_PARTITION=$2
	printf '%s\t%s\t%s\n' \
		"$BIRD" 'Part of Whole' testdisk \
		"$DATA" 'Part of Whole' "$DATA_WHOLE" \
		'/dev/testdisk' 'Device Location' External \
		'/dev/testdisk' 'Protocol' 'Secure Digital' \
		'/dev/testdisk' 'Removable Media' Removable \
		"$BIRD" 'Device Identifier' testdisks1 \
		"$DATA" 'Device Identifier' "$DATA_PARTITION" \
		"$BIRD" 'Volume Read-Only' No \
		"$DATA" 'Volume Read-Only' No >"$INFO"
}

run_migration() {
	TMPDIR=$TMP BIRD_HOST_TEST_MODE=1 BIRD=$BIRD DATA=$DATA \
	BIRD_DEVICE_INFO=$INFO "$MIGRATION"
}

write_info otherdisk testdisks6
if run_migration >"$TMP/different-disk.out" 2>"$TMP/different-disk.err"; then
	printf '%s\n' 'migration accepted volumes on different disks' >&2
	exit 1
fi
grep -q 'volumes are on different disks' "$TMP/different-disk.err"
[ -d "$DATA/ports/GameA" ]

write_info testdisk testdisks5
if run_migration >"$TMP/not-p6.out" 2>"$TMP/not-p6.err"; then
	printf '%s\n' 'migration accepted a data volume that was not p6' >&2
	exit 1
fi
grep -q 'data is not p6' "$TMP/not-p6.err"
[ -d "$DATA/ports/GameA" ]

write_info testdisk testdisks6
mv "$DATA/ports" "$DATA/ports-real"
ln -s "$DATA/ports-real" "$DATA/ports"
if run_migration >"$TMP/symlink.out" 2>"$TMP/symlink.err"; then
	printf '%s\n' 'migration accepted a symlinked legacy tree' >&2
	exit 1
fi
grep -q 'legacy /ports must not be a symlink' "$TMP/symlink.err"
rm "$DATA/ports"
mv "$DATA/ports-real" "$DATA/ports"

run_migration >"$TMP/success.out"
[ -d "$DATA/ROMS/Ports/GameA" ]
[ ! -e "$DATA/ports" ]
grep -q 'Migrated 1 Port data directories' "$TMP/success.out"
run_migration >"$TMP/idempotent.out"
grep -qx 'No legacy /ports tree remains.' "$TMP/idempotent.out"

printf '%s\n' 'stock-root migration tests passed'
