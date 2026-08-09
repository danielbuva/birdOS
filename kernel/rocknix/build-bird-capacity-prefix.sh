#!/bin/sh
# Build payload-equivalent legacy and expanded BIRD prefix images without
# touching the mounted card. The output remains the explicit rollback oracle
# until the expanded layout passes its physical gate.

set -eu
umask 077

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BIRD_SOURCE=${BIRD_SOURCE:-/Volumes/BIRD}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-capacity-prefix}
BOOT_PREFIX=${BOOT_PREFIX:-$HOME/rocknix-reference-result/boot-prefix-16m.bin}
GDD=${GDD:-/opt/homebrew/bin/gdd}
GTRUNCATE=${GTRUNCATE:-/opt/homebrew/bin/gtruncate}
HOST_TEST_MODE=${BIRD_CAPACITY_HOST_TEST_MODE:-0}
BOOT_PREFIX_SHA=3d06e243e26bd1a06d585fa35e53912b5742f62ca180135308740719883d65d2
PREFIX_BYTES=163577856
FAT_OFFSET=16777216
ATTACHED=
FINAL_OUTPUT=$OUTPUT
OUTPUT_STAGE=
OUTPUT_PUBLISHED=0

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

cleanup() {
	if [ -n "$ATTACHED" ]; then
		hdiutil detach "$ATTACHED" >/dev/null 2>&1 || :
	fi
	if [ "$OUTPUT_PUBLISHED" -eq 0 ] && [ -n "$OUTPUT_STAGE" ] &&
		[ -d "$OUTPUT_STAGE" ] && [ ! -L "$OUTPUT_STAGE" ]; then
		/bin/rm -rf "$OUTPUT_STAGE"
	fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ "${1:-}" = --build ] && [ "$#" -eq 1 ] ||
	fail "usage: BIRD_SOURCE=/Volumes/BIRD OUTPUT=/path $0 --build"
case "$HOST_TEST_MODE" in
	0)
		[ -z "${BIRD_TEST_BOOT_PREFIX_SHA:-}" ] ||
			fail 'test boot-prefix override requires host-test mode'
		ARTIFACT_MODE=production
		;;
	1)
		: "${BIRD_TEST_BOOT_PREFIX_SHA:?test boot-prefix digest is required}"
		case "$BIRD_SOURCE:$FINAL_OUTPUT:$BOOT_PREFIX" in
			/var/folders/*:/var/folders/*:/var/folders/*|\
			/private/tmp/*:/private/tmp/*:/private/tmp/*|\
			/tmp/*:/tmp/*:/tmp/*) ;;
			*) fail 'host-test paths must stay in one temporary namespace' ;;
		esac
		BOOT_PREFIX_SHA=$BIRD_TEST_BOOT_PREFIX_SHA
		ARTIFACT_MODE=host-test
		;;
	*) fail 'invalid capacity builder host-test mode' ;;
esac
[ -d "$BIRD_SOURCE" ] && [ ! -L "$BIRD_SOURCE" ] ||
	fail "BIRD source is missing or unsafe: $BIRD_SOURCE"
case "$FINAL_OUTPUT" in
	/*) ;;
	*) fail 'output must be an absolute path' ;;
esac
[ ! -e "$FINAL_OUTPUT" ] && [ ! -L "$FINAL_OUTPUT" ] ||
	fail "output already exists: $FINAL_OUTPUT"
OUTPUT_PARENT=$(dirname "$FINAL_OUTPUT")
[ -d "$OUTPUT_PARENT" ] && [ ! -L "$OUTPUT_PARENT" ] ||
	fail "output parent is missing or unsafe: $OUTPUT_PARENT"
OUTPUT_STAGE=$FINAL_OUTPUT.new.$$
[ ! -e "$OUTPUT_STAGE" ] && [ ! -L "$OUTPUT_STAGE" ] ||
	fail "private output stage already exists: $OUTPUT_STAGE"
[ -x "$GDD" ] || fail 'GNU dd is required'
[ -x "$GTRUNCATE" ] || fail 'GNU truncate is required'
for COMMAND in hdiutil newfs_msdos fsck_msdos 7zz python3 rsync shasum; do
	command -v "$COMMAND" >/dev/null 2>&1 || fail "required command missing: $COMMAND"
done
[ -f "$BOOT_PREFIX" ] && [ ! -L "$BOOT_PREFIX" ] ||
	fail "boot prefix is missing or unsafe: $BOOT_PREFIX"
[ "$(stat -f '%z' "$BOOT_PREFIX")" -eq "$FAT_OFFSET" ] ||
	fail 'boot prefix size changed'
[ "$(shasum -a 256 "$BOOT_PREFIX" | awk '{print $1}')" = "$BOOT_PREFIX_SHA" ] ||
	fail 'boot prefix checksum changed'

mkdir -m 700 "$OUTPUT_STAGE"
OUTPUT=$OUTPUT_STAGE
MIRROR=$OUTPUT/source-mirror
mkdir -m 700 "$MIRROR"
INVENTORY_TOOL=$ROOT/kernel/rocknix/inventory-bird-fat-source.py
LAYOUT_TOOL=$ROOT/kernel/rocknix/build-bird-layout.py
python3 "$INVENTORY_TOOL" "$BIRD_SOURCE" >"$OUTPUT/source-inventory.tsv"
COPYFILE_DISABLE=1 /usr/bin/rsync -rt \
	--exclude='._*' --exclude='.DS_Store' --exclude='.Spotlight-V100' \
	--exclude='.Trashes' --exclude='.fseventsd' \
	"$BIRD_SOURCE/" "$MIRROR/"
python3 "$INVENTORY_TOOL" "$MIRROR" >"$OUTPUT/mirror-inventory.tsv"
cmp "$OUTPUT/source-inventory.tsv" "$OUTPUT/mirror-inventory.tsv" >/dev/null ||
	fail 'host mirror differs from the mounted BIRD payload'

purge_host_metadata() {
	PURGE_ROOT=$1
	for PURGE_NAME in '._*' .DS_Store .Spotlight-V100 .Trashes .fseventsd; do
		find "$PURGE_ROOT" -depth -name "$PURGE_NAME" \
			-exec /bin/rm -rf -- {} \;
	done
}

build_variant() {
	VARIANT=$1
	FAT_BYTES=$2
	FAT=$OUTPUT/$VARIANT.fat
	PREFIX=$OUTPUT/$VARIANT-prefix.img
	MOUNT=$OUTPUT/.mount-$VARIANT
	TARGET_INVENTORY=$OUTPUT/$VARIANT-inventory.tsv

	"$GTRUNCATE" -s "$FAT_BYTES" "$FAT"
	ATTACHED=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage \
		-nomount -readwrite "$FAT" | awk 'NR == 1 {print $1}')
	[ -n "$ATTACHED" ] || fail "could not attach $VARIANT FAT"
	newfs_msdos -F 32 -I 42495244 -v BIRD "$ATTACHED" >/dev/null
	hdiutil detach "$ATTACHED" >/dev/null
	ATTACHED=
	mkdir -m 700 "$MOUNT"
	ATTACHED=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage \
		-readwrite -nobrowse -mountpoint "$MOUNT" "$FAT" |
		awk 'NR == 1 {print $1}')
	[ -n "$ATTACHED" ] || fail "could not mount $VARIANT FAT"
	COPYFILE_DISABLE=1 /usr/bin/rsync -rt "$MIRROR/" "$MOUNT/"
	purge_host_metadata "$MOUNT"
	sync
	python3 "$INVENTORY_TOOL" "$MOUNT" >"$TARGET_INVENTORY"
	cmp "$OUTPUT/source-inventory.tsv" "$TARGET_INVENTORY" >/dev/null ||
		fail "$VARIANT FAT payload differs before detach"
	hdiutil detach "$ATTACHED" >/dev/null
	ATTACHED=
	rmdir "$MOUNT"
	fsck_msdos -n "$FAT" >/dev/null
	7zz t "$FAT" >/dev/null

	"$GTRUNCATE" -s "$PREFIX_BYTES" "$PREFIX"
	"$GDD" if="$BOOT_PREFIX" of="$PREFIX" bs=4M conv=notrunc status=none
	"$GDD" if="$FAT" of="$PREFIX" bs=4M seek="$FAT_OFFSET" \
		oflag=seek_bytes conv=notrunc status=none
	python3 "$LAYOUT_TOOL" --layout "$VARIANT" "$PREFIX" >/dev/null
	[ "$(stat -f '%z' "$PREFIX")" -eq "$PREFIX_BYTES" ] ||
		fail "$VARIANT prefix size changed"
}

build_variant legacy-128 134217728
build_variant expanded-138 144703488

SOURCE_INVENTORY_BYTES=$(stat -f '%z' "$OUTPUT/source-inventory.tsv")
SOURCE_INVENTORY_SHA=$(shasum -a 256 "$OUTPUT/source-inventory.tsv" | awk '{print $1}')
LEGACY_SHA=$(shasum -a 256 "$OUTPUT/legacy-128-prefix.img" | awk '{print $1}')
EXPANDED_SHA=$(shasum -a 256 "$OUTPUT/expanded-138-prefix.img" | awk '{print $1}')
cat >"$OUTPUT/artifacts.tsv" <<EOF
schema	bird-prefix-capacity-v1
build-mode	$ARTIFACT_MODE
input	boot-prefix-16m.bin	16777216	$BOOT_PREFIX_SHA
source-inventory	source-inventory.tsv	$SOURCE_INVENTORY_BYTES	$SOURCE_INVENTORY_SHA
prefix	legacy-128	legacy-128-prefix.img	$PREFIX_BYTES	$LEGACY_SHA
prefix	expanded-138	expanded-138-prefix.img	$PREFIX_BYTES	$EXPANDED_SHA
EOF
MANIFEST_SHA=$(shasum -a 256 "$OUTPUT/artifacts.tsv" | awk '{print $1}')
printf '%s\n' "$MANIFEST_SHA" >"$OUTPUT/.complete"

# Only the two complete prefix oracles and their verification records survive.
/bin/rm -rf "$MIRROR"
/bin/rm -f "$OUTPUT/mirror-inventory.tsv" \
	"$OUTPUT/legacy-128-inventory.tsv" "$OUTPUT/expanded-138-inventory.tsv" \
	"$OUTPUT/legacy-128.fat" "$OUTPUT/expanded-138.fat"

[ ! -e "$FINAL_OUTPUT" ] && [ ! -L "$FINAL_OUTPUT" ] ||
	fail "output appeared during build: $FINAL_OUTPUT"
mv "$OUTPUT" "$FINAL_OUTPUT"
OUTPUT=$FINAL_OUTPUT
OUTPUT_PUBLISHED=1

printf 'BIRD capacity prefix artifacts built without card mutation:\n  %s\n' "$OUTPUT"
printf 'Legacy rollback SHA-256: %s\nExpanded candidate SHA-256: %s\n' \
	"$LEGACY_SHA" "$EXPANDED_SHA"
