#!/bin/sh
set -eu

DEFAULT_SOURCE="/Users/dani/Downloads/MustardOS_RG34XX-SP_2601.1_FUNKY_JACARANDA-bc38efa0.img.gz"
DEFAULT_OUTPUT="/Volumes/dani-sp/.firmware-work"
SOURCE=${1:-$DEFAULT_SOURCE}
OUTPUT=${2:-$DEFAULT_OUTPUT}
SOURCE_SHA256="18c6e1e20421be2bf604cbaf920c3fc69b0ab49c758a0a42e04626499f1444ee"
GDD=${GDD:-/opt/homebrew/bin/gdd}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] || fail "source image not found: $SOURCE"
[ -x "$GDD" ] || fail "GNU dd is required; install it with: brew install coreutils"
command -v gzip >/dev/null 2>&1 || fail "gzip is required"
command -v shasum >/dev/null 2>&1 || fail "shasum is required"

printf 'Verifying source archive...\n'
ACTUAL_SOURCE_SHA=$(shasum -a 256 "$SOURCE" | awk '{print $1}')
[ "$ACTUAL_SOURCE_SHA" = "$SOURCE_SHA256" ] || fail "source checksum does not match muOS 2601.1 RG34XX-SP"

mkdir -p "$OUTPUT"
for NAME in stock-spare.img stock-boot-resource.img stock-env.img stock-boot.img stock-rootfs.ext4; do
	[ ! -e "$OUTPUT/$NAME" ] || fail "$OUTPUT/$NAME already exists; use a new empty output directory"
done

extract() {
	NAME=$1
	SKIP_MIB=$2
	COUNT_MIB=$3
	printf 'Extracting %-24s %5s MiB...\n' "$NAME" "$COUNT_MIB"
	gzip -dc "$SOURCE" | "$GDD" \
		of="$OUTPUT/$NAME" \
		bs=1M skip="$SKIP_MIB" count="$COUNT_MIB" \
		iflag=fullblock status=progress
}

extract stock-spare.img 36 8
extract stock-boot-resource.img 44 32
extract stock-env.img 76 16
extract stock-boot.img 92 64
extract stock-rootfs.ext4 156 8192

printf '\nExtraction complete: %s\n' "$OUTPUT"
printf 'Run firmware/inspect-stock.sh "%s" --checksums next.\n' "$OUTPUT"
