#!/bin/sh
# Host-only end-to-end gate for the bounded 128 MiB -> 138 MiB BIRD migration.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
BUILDER=$ROOT/kernel/rocknix/build-bird-capacity-prefix.sh
INSTALLER=$ROOT/firmware/mac-expand-bird-prefix.sh
INVENTORY=$ROOT/kernel/rocknix/inventory-bird-fat-source.py
GDD=${GDD:-/opt/homebrew/bin/gdd}
GTRUNCATE=${GTRUNCATE:-/opt/homebrew/bin/gtruncate}
PREFIX_BYTES=163577856
TAIL_BYTES=4096

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

[ "$(uname -s)" = Darwin ] || {
	printf 'SKIP: BIRD capacity prefix host gate requires macOS\n'
	exit 0
}
[ -x "$GDD" ] && [ -x "$GTRUNCATE" ] ||
	fail 'GNU coreutils are required'

CASE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bird-capacity-migration-test.XXXXXX") ||
	fail 'could not create temporary fixture'
cleanup() {
	case "$CASE_ROOT" in
		/var/folders/*|/private/tmp/*|/tmp/*) /bin/rm -rf "$CASE_ROOT" ;;
	esac
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

BIRD=$CASE_ROOT/BIRD
DATA=$CASE_ROOT/BIRD-DATA
BOOT=$CASE_ROOT/boot-prefix-16m.bin
ARTIFACTS=$CASE_ROOT/artifacts
RAW=$CASE_ROOT/raw-card.img
mkdir -p "$BIRD/bird-releases/current/empty" "$BIRD/extlinux" "$DATA"
printf 'kernel bytes\n' >"$BIRD/bird-releases/current/KERNEL"
printf 'complete\n' >"$BIRD/bird-releases/current/.complete"
printf 'default bird\n' >"$BIRD/extlinux/extlinux.conf"
printf 'fallback\n' >"$BIRD/KERNEL.fallback"
printf 'ignored\n' >"$BIRD/._KERNEL.fallback"
mkdir "$BIRD/.Spotlight-V100"
printf 'ignored\n' >"$BIRD/.Spotlight-V100/index"

"$GTRUNCATE" -s 16777216 "$BOOT"
printf '\125\252' | "$GDD" of="$BOOT" bs=1 seek=510 conv=notrunc status=none
BOOT_SHA=$(shasum -a 256 "$BOOT" | awk '{print $1}')
BIRD_CAPACITY_HOST_TEST_MODE=1 \
	BIRD_TEST_BOOT_PREFIX_SHA=$BOOT_SHA \
	BIRD_SOURCE=$BIRD OUTPUT=$ARTIFACTS BOOT_PREFIX=$BOOT \
	GDD=$GDD GTRUNCATE=$GTRUNCATE \
	sh "$BUILDER" --build >"$CASE_ROOT/build.out"
[ -f "$ARTIFACTS/.complete" ] || fail 'builder did not publish completion'
[ ! -e "$ARTIFACTS/source-mirror" ] || fail 'builder retained its source mirror'
[ -f "$ARTIFACTS/legacy-128-prefix.img" ] &&
	[ -f "$ARTIFACTS/expanded-138-prefix.img" ] ||
	fail 'builder did not publish both prefix oracles'
awk -F '\t' '$1 == "build-mode" && $2 == "host-test" {found=1} END {exit !found}' \
	"$ARTIFACTS/artifacts.tsv" ||
	fail 'builder did not label host-test artifacts'

WHOLE=disk$$
SOURCE_INFO=$CASE_ROOT/source-device.tsv
TARGET_INFO=$CASE_ROOT/target-device.tsv

write_device_info() {
	INFO_PATH=$1
	BIRD_SIZE=$2
	cat >"$INFO_PATH" <<EOF
$BIRD	Part of Whole	$WHOLE
$DATA	Part of Whole	$WHOLE
/dev/$WHOLE	Device Location	External
/dev/$WHOLE	Removable Media	Removable
/dev/$WHOLE	Internal	false
/dev/$WHOLE	Removable	true
/dev/$WHOLE	Disk Size	512074186752 Bytes (512074186752 Bytes)
$BIRD	Device Identifier	${WHOLE}s1
$DATA	Device Identifier	${WHOLE}s6
$BIRD	Partition Offset	16777216 Bytes
$BIRD	Disk Size	$BIRD_SIZE Bytes ($BIRD_SIZE Bytes)
/dev/${WHOLE}s5	Partition Offset	163577856 Bytes
/dev/${WHOLE}s5	Disk Size	8589934592 Bytes (8589934592 Bytes)
$DATA	Partition Offset	8753512448 Bytes
$DATA	Disk Size	503320672768 Bytes (503320672768 Bytes)
$BIRD	Volume Read-Only	No
$DATA	Volume Read-Only	No
$BIRD	File System Personality	MS-DOS FAT32
EOF
}

write_device_info "$SOURCE_INFO" 134217728
write_device_info "$TARGET_INFO" 144703488
"$GTRUNCATE" -s $((PREFIX_BYTES + TAIL_BYTES)) "$RAW"
"$GDD" if="$ARTIFACTS/legacy-128-prefix.img" of="$RAW" bs=4M \
	conv=notrunc status=none
printf 'p5 sentinel remains outside the prefix\n' >"$CASE_ROOT/sentinel"
"$GDD" if="$CASE_ROOT/sentinel" of="$RAW" bs=1 seek="$PREFIX_BYTES" \
	conv=notrunc status=none
"$GDD" if="$RAW" of="$CASE_ROOT/tail.before" bs=1 skip="$PREFIX_BYTES" \
	count="$TAIL_BYTES" status=none

run_installer() {
	SOURCE_FIXTURE=$1
	TARGET_FIXTURE=$2
	MODE=$3
	BIRD_PREFIX_HOST_TEST_MODE=1 BIRD=$BIRD DATA=$DATA \
		BIRD_TEST_SOURCE_DEVICE_INFO=$SOURCE_FIXTURE \
		BIRD_TEST_TARGET_DEVICE_INFO=$TARGET_FIXTURE \
		BIRD_TEST_RAW_DISK=$RAW GDD=$GDD \
		sh "$INSTALLER" "/dev/$WHOLE" "$MODE" "$ARTIFACTS"
}

# Unknown manifest records and a recomputed-but-false artifact digest are both
# rejected before the raw fixture changes.
cp "$ARTIFACTS/artifacts.tsv" "$CASE_ROOT/artifacts.original.tsv"
printf 'unknown\trecord\n' >>"$ARTIFACTS/artifacts.tsv"
shasum -a 256 "$ARTIFACTS/artifacts.tsv" | awk '{print $1}' \
	>"$ARTIFACTS/.complete"
RAW_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_installer "$SOURCE_INFO" "$TARGET_INFO" --install-expanded \
		>"$CASE_ROOT/unknown.out" 2>"$CASE_ROOT/unknown.err"; then
	fail 'unknown capacity manifest record was accepted'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RAW_SHA" ] ||
	fail 'unknown manifest record changed the raw fixture'
cp "$CASE_ROOT/artifacts.original.tsv" "$ARTIFACTS/artifacts.tsv"
printf 'prefix\texpanded-138\tmalformed\n' >>"$ARTIFACTS/artifacts.tsv"
shasum -a 256 "$ARTIFACTS/artifacts.tsv" | awk '{print $1}' \
	>"$ARTIFACTS/.complete"
if run_installer "$SOURCE_INFO" "$TARGET_INFO" --install-expanded \
		>"$CASE_ROOT/malformed.out" 2>"$CASE_ROOT/malformed.err"; then
	fail 'malformed recognized capacity manifest record was accepted'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RAW_SHA" ] ||
	fail 'malformed manifest record changed the raw fixture'
cp "$CASE_ROOT/artifacts.original.tsv" "$ARTIFACTS/artifacts.tsv"
sed -i '' '/^prefix[[:space:]]expanded-138[[:space:]]/s/[0-9a-f][0-9a-f]*$/0000000000000000000000000000000000000000000000000000000000000000/' \
	"$ARTIFACTS/artifacts.tsv"
shasum -a 256 "$ARTIFACTS/artifacts.tsv" | awk '{print $1}' \
	>"$ARTIFACTS/.complete"
if run_installer "$SOURCE_INFO" "$TARGET_INFO" --install-expanded \
		>"$CASE_ROOT/digest.out" 2>"$CASE_ROOT/digest.err"; then
	fail 'false capacity artifact digest was accepted'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RAW_SHA" ] ||
	fail 'false artifact digest changed the raw fixture'
cp "$CASE_ROOT/artifacts.original.tsv" "$ARTIFACTS/artifacts.tsv"
shasum -a 256 "$ARTIFACTS/artifacts.tsv" | awk '{print $1}' \
	>"$ARTIFACTS/.complete"

run_installer "$SOURCE_INFO" "$TARGET_INFO" --install-expanded \
	>"$CASE_ROOT/install.out"
"$GDD" if="$RAW" of="$CASE_ROOT/prefix.actual" bs=4M \
	count="$PREFIX_BYTES" iflag=count_bytes status=none
cmp "$CASE_ROOT/prefix.actual" "$ARTIFACTS/expanded-138-prefix.img" >/dev/null ||
	fail 'expanded prefix was not written exactly'
"$GDD" if="$RAW" of="$CASE_ROOT/tail.after" bs=1 skip="$PREFIX_BYTES" \
	count="$TAIL_BYTES" status=none
cmp "$CASE_ROOT/tail.before" "$CASE_ROOT/tail.after" >/dev/null ||
	fail 'expanded write changed bytes at or after p5'
grep -Fq 'p5 root and p6 data byte ranges were not written' \
	"$CASE_ROOT/install.out" || fail 'expanded report omitted its write boundary'

run_installer "$TARGET_INFO" "$SOURCE_INFO" --restore-legacy \
	>"$CASE_ROOT/restore.out"
"$GDD" if="$RAW" of="$CASE_ROOT/prefix.actual" bs=4M \
	count="$PREFIX_BYTES" iflag=count_bytes status=none
cmp "$CASE_ROOT/prefix.actual" "$ARTIFACTS/legacy-128-prefix.img" >/dev/null ||
	fail 'legacy rollback prefix was not restored exactly'
"$GDD" if="$RAW" of="$CASE_ROOT/tail.after" bs=1 skip="$PREFIX_BYTES" \
	count="$TAIL_BYTES" status=none
cmp "$CASE_ROOT/tail.before" "$CASE_ROOT/tail.after" >/dev/null ||
	fail 'legacy restore changed bytes at or after p5'

# Wrong geometry, payload drift and an unsafe source node all fail before the
# first raw byte changes.
cp "$SOURCE_INFO" "$CASE_ROOT/wrong-source.tsv"
sed -i '' 's/134217728 Bytes (134217728 Bytes)/134217729 Bytes (134217729 Bytes)/' \
	"$CASE_ROOT/wrong-source.tsv"
RAW_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_installer "$CASE_ROOT/wrong-source.tsv" "$TARGET_INFO" \
		--install-expanded >"$CASE_ROOT/wrong.out" 2>"$CASE_ROOT/wrong.err"; then
	fail 'wrong source geometry was accepted'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RAW_SHA" ] ||
	fail 'wrong source geometry changed the raw fixture'

printf 'drift\n' >>"$BIRD/extlinux/extlinux.conf"
if run_installer "$SOURCE_INFO" "$TARGET_INFO" --install-expanded \
		>"$CASE_ROOT/drift.out" 2>"$CASE_ROOT/drift.err"; then
	fail 'payload drift was accepted'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RAW_SHA" ] ||
	fail 'payload drift changed the raw fixture'
printf 'default bird\n' >"$BIRD/extlinux/extlinux.conf"

ln -s KERNEL.fallback "$BIRD/unsafe-link"
if run_installer "$SOURCE_INFO" "$TARGET_INFO" --install-expanded \
		>"$CASE_ROOT/link.out" 2>"$CASE_ROOT/link.err"; then
	fail 'source symlink was accepted'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RAW_SHA" ] ||
	fail 'source symlink changed the raw fixture'
rm "$BIRD/unsafe-link"

python3 "$INVENTORY" "$BIRD" >"$CASE_ROOT/final-inventory.tsv"
cmp "$CASE_ROOT/final-inventory.tsv" "$ARTIFACTS/source-inventory.tsv" >/dev/null ||
	fail 'host gate changed the source payload'

printf 'PASS: bounded BIRD capacity migration host gate\n'
