#!/bin/bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
VALIDATOR=$ROOT/kernel/rocknix/validate-canonical-namespace.py
MIGRATOR=$ROOT/firmware/migrate-bird-namespace.py
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-namespace.XXXXXX")
TMP=$(CDPATH= cd -- "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
BIRD=$TMP/BIRD
DATA=$TMP/BIRD-DATA
INFO=$TMP/device-info.tsv
mkdir -p "$BIRD" "$DATA/MUOS/Bird/log" "$DATA/MUOS/bios/sub" "$DATA/ROMS/bios" "$DATA/.config/bird"
printf 'bios-a\n' >"$DATA/MUOS/bios/a.bin"
printf 'bios-b\n' >"$DATA/MUOS/bios/sub/b.bin"
printf 'host metadata must not become a device file\n' \
	>"$DATA/MUOS/bios/._host-only"
printf 'fav\n' >"$DATA/.config/bird/favorites.txt"
printf 'recent\n' >"$DATA/.config/bird/recent.txt"
printf 'legacy-log\n' >"$DATA/MUOS/Bird/log/keep.log"
printf '%s\t%s\t%s\n' \
	"$BIRD" 'Part of Whole' testdisk \
	"$DATA" 'Part of Whole' testdisk \
	'/dev/testdisk' 'Device Location' External \
	'/dev/testdisk' 'Protocol' 'Secure Digital' \
	'/dev/testdisk' 'Removable Media' Removable \
	"$BIRD" 'Device Identifier' testdisks1 \
	"$DATA" 'Device Identifier' testdisks6 \
	"$BIRD" 'Volume Read-Only' No \
	"$DATA" 'Volume Read-Only' No >"$INFO"

run() {
	python3 "$MIGRATOR" "$1" --bird "$BIRD" --data "$DATA" --device-info "$INFO"
}

python3 "$VALIDATOR"
run status | grep -Fxq $'state\tnone'
run prepare | grep -q 'Prepared and verified 2 BIOS files'
[ ! -e "$DATA/.bird-namespace-v1/prepare/bios/._host-only" ]
[ ! -e "$DATA/Bird" ]
[ "$(cat "$DATA/MUOS/Bird/log/keep.log")" = legacy-log ]
run prepare | grep -q 'already prepared and verified'
mv "$DATA/.bird-namespace-v1/prepare/Bird" "$DATA/Bird"
run status | grep -Fxq $'partial-commit\t1'
run commit | grep -q 'committed'
cmp "$DATA/MUOS/bios/a.bin" "$DATA/ROMS/bios/a.bin"
cmp "$DATA/.config/bird/favorites.txt" "$DATA/Bird/state/favorites.txt"
[ "$(cat "$DATA/MUOS/Bird/log/keep.log")" = legacy-log ]
run commit | grep -q 'already committed'
run rollback | grep -q 'legacy fallback is unchanged'
[ ! -e "$DATA/Bird" ]
[ ! -e "$DATA/ROMS/bios" ]
[ "$(cat "$DATA/MUOS/Bird/log/keep.log")" = legacy-log ]
rm -rf "$DATA/.bird-namespace-v1"
mkdir -p "$DATA/Bird"
if run prepare >"$TMP/mixed.out" 2>"$TMP/mixed.err"; then
	echo 'mixed canonical state was accepted' >&2
	exit 1
fi
grep -q 'mixed state' "$TMP/mixed.err"

printf '%s\n' 'canonical namespace tests passed'
