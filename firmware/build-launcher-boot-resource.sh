#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STOCK=${1:-/Volumes/dani-sp/.firmware-work/stock-boot-resource.img}
OUTPUT_DIR=${2:-$SCRIPT_DIR/work/boot-resource}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -f "$STOCK" ] || fail "stock 32 MiB boot-resource image not found: $STOCK"
[ "$(stat -f %z "$STOCK")" -eq 33554432 ] || fail "stock image must be exactly 32 MiB"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

mkdir -p "$OUTPUT_DIR"
STOCK_LOGO="$OUTPUT_DIR/stock-bootlogo.bmp"
UNCHANGED="$OUTPUT_DIR/no-change-boot-resource.img"
DANI_LOGO="$OUTPUT_DIR/dani-frame-zero.bmp"
CANDIDATE="$OUTPUT_DIR/dani-boot-resource.img"

python3 "$SCRIPT_DIR/fat16-file.py" extract "$STOCK" bootlogo.bmp "$STOCK_LOGO"
python3 "$SCRIPT_DIR/fat16-file.py" replace "$STOCK" bootlogo.bmp "$STOCK_LOGO" "$UNCHANGED"
cmp -s "$STOCK" "$UNCHANGED" || fail "no-change FAT16 replacement was not byte-identical"
printf '%s\n' 'No-change FAT16 round trip: byte-identical'

python3 "$SCRIPT_DIR/generate-launcher-bootlogo.py" "$DANI_LOGO"
[ "$(stat -f %z "$DANI_LOGO")" -eq "$(stat -f %z "$STOCK_LOGO")" ] || \
	fail "generated bootlogo does not preserve the stock file size"
python3 "$SCRIPT_DIR/fat16-file.py" replace "$STOCK" bootlogo.bmp "$DANI_LOGO" "$CANDIDATE"

printf '\nSHA-256:\n'
shasum -a 256 "$STOCK" "$STOCK_LOGO" "$DANI_LOGO" "$CANDIDATE"
printf '\nBuilt candidate: %s\n' "$CANDIDATE"
