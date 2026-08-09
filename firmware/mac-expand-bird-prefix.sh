#!/bin/sh
# Install or explicitly roll back the one-time 138 MiB BIRD capacity layout.
# Every write remains bounded to the existing 156 MiB prefix before p5.

set -eu
umask 077

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DEVICE=${1:-}
ACTION=${2:-}
ARTIFACTS=${3:-}
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/BIRD-DATA}
GDD=${GDD:-/opt/homebrew/bin/gdd}
HOST_TEST_MODE=${BIRD_PREFIX_HOST_TEST_MODE:-0}
PREFIX_BYTES=163577856
FAT_OFFSET=16777216
LEGACY_BYTES=134217728
EXPANDED_BYTES=144703488
PINNED_BOOT_PREFIX_SHA=3d06e243e26bd1a06d585fa35e53912b5742f62ca180135308740719883d65d2
PINNED_MASKED_BOOT_SHA=9f1f056e544b12c28d253478b3bacd4ad1635fee65cb6715bacae2a4a308e114
VERIFY_WORK=
ATTACHED=
MOUNTED=1
BIRD_CARD_LOCK_OWNED=0
DEVICE_PHASE=source

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

usage() {
	printf 'usage: %s /dev/diskN --install-expanded ARTIFACT_DIR\n' "$0" >&2
	printf '       %s /dev/diskN --restore-legacy ARTIFACT_DIR\n' "$0" >&2
	exit 2
}

cleanup() {
	if [ -n "$ATTACHED" ]; then
		hdiutil detach "$ATTACHED" >/dev/null 2>&1 || :
	fi
	if [ "$MOUNTED" -eq 0 ]; then
		if [ "$HOST_TEST_MODE" -eq 0 ]; then
			diskutil mountDisk "/dev/$WHOLE" >/dev/null 2>&1 || :
		else
			MOUNTED=1
		fi
	fi
	if command -v bird_card_lock_release >/dev/null 2>&1; then
		bird_card_lock_release
	fi
	if [ -n "$VERIFY_WORK" ]; then
		case "$VERIFY_WORK" in
			/var/folders/*|/private/tmp/*|/tmp/*) /bin/rm -rf "$VERIFY_WORK" ;;
		esac
	fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ "$#" -eq 3 ] || usage
case "$DEVICE" in /dev/disk[0-9]*) ;; *) usage ;; esac
WHOLE=${DEVICE#/dev/}
case "$ACTION" in
	--install-expanded)
		SOURCE_BIRD_BYTES=$LEGACY_BYTES
		TARGET_BIRD_BYTES=$EXPANDED_BYTES
		SOURCE_LAYOUT=legacy-128
		TARGET_LAYOUT=expanded-138
		;;
	--restore-legacy)
		SOURCE_BIRD_BYTES=$EXPANDED_BYTES
		TARGET_BIRD_BYTES=$LEGACY_BYTES
		SOURCE_LAYOUT=expanded-138
		TARGET_LAYOUT=legacy-128
		;;
	*) usage ;;
esac
[ -d "$ARTIFACTS" ] && [ ! -L "$ARTIFACTS" ] ||
	fail "artifact directory is missing or unsafe: $ARTIFACTS"

case "$HOST_TEST_MODE" in
	0)
		[ -z "${BIRD_DEVICE_INFO:-}${BIRD_TEST_SOURCE_DEVICE_INFO:-}${BIRD_TEST_TARGET_DEVICE_INFO:-}${BIRD_TEST_RAW_DISK:-}" ] ||
			fail 'test overrides require host-test mode'
		RAW_DISK=/dev/r$WHOLE
		;;
	1)
		: "${BIRD_TEST_SOURCE_DEVICE_INFO:?source device fixture is required}"
		: "${BIRD_TEST_TARGET_DEVICE_INFO:?target device fixture is required}"
		: "${BIRD_TEST_RAW_DISK:?raw disk fixture is required}"
		case "$BIRD:$DATA:$BIRD_TEST_SOURCE_DEVICE_INFO:$BIRD_TEST_TARGET_DEVICE_INFO:$BIRD_TEST_RAW_DISK" in
			/var/folders/*:/var/folders/*:/var/folders/*:/var/folders/*:/var/folders/*|\
			/private/tmp/*:/private/tmp/*:/private/tmp/*:/private/tmp/*:/private/tmp/*|\
			/tmp/*:/tmp/*:/tmp/*:/tmp/*:/tmp/*) ;;
			*) fail 'host-test paths must stay in temporary storage' ;;
		esac
		RAW_DISK=$BIRD_TEST_RAW_DISK
		;;
	*) fail 'invalid prefix host-test mode' ;;
esac

for COMMAND in python3 shasum awk cmp stat hdiutil fsck_msdos plutil diskutil; do
	command -v "$COMMAND" >/dev/null 2>&1 || fail "required command missing: $COMMAND"
done
[ -x "$GDD" ] || fail 'GNU dd is required'

plist_value() {
	if [ "$HOST_TEST_MODE" -eq 1 ]; then
		if [ "$DEVICE_PHASE" = source ]; then
			DEVICE_INFO=$BIRD_TEST_SOURCE_DEVICE_INFO
		else
			DEVICE_INFO=$BIRD_TEST_TARGET_DEVICE_INFO
		fi
		awk -F '\t' -v device="$1" -v key="$2" \
			'$1 == device && $2 == key {print $3; exit}' "$DEVICE_INFO"
		return
	fi
	diskutil info -plist "$1" | plutil -extract "$2" raw -o - -
}

# shellcheck source=mac-removable-device.sh
. "$ROOT/firmware/mac-removable-device.sh"
# shellcheck source=mac-stock-root-card-identity.sh
. "$ROOT/firmware/mac-stock-root-card-identity.sh"
# shellcheck source=mac-bird-card-lock.sh
. "$ROOT/firmware/mac-bird-card-lock.sh"

validate_phase_identity() {
	EXPECTED_BIRD_BYTES=$1
	if [ "$HOST_TEST_MODE" -eq 1 ]; then
		if [ "$DEVICE_PHASE" = source ]; then
			BIRD_DEVICE_INFO=$BIRD_TEST_SOURCE_DEVICE_INFO
		else
			BIRD_DEVICE_INFO=$BIRD_TEST_TARGET_DEVICE_INFO
		fi
	else
		BIRD_DEVICE_INFO=
	fi
	# The shared contract is already promoted to 138 MiB. Override only its p1
	# size while validating the one legacy source or explicit rollback phase.
	BIRD_BYTES=$EXPECTED_BIRD_BYTES
	validate_stock_root_card_identity
	[ "$WHOLE" = "${DEVICE#/dev/}" ] || fail 'requested whole disk differs from mounted volumes'
	bird_require_safe_removable_device "/dev/$WHOLE"
	case "$(field "$BIRD" 'File System Personality')" in
		*FAT*) ;;
		*) fail 'BIRD is not a FAT volume' ;;
	esac
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

is_regular_file() {
	[ -f "$1" ] && [ ! -L "$1" ]
}

MANIFEST=$ARTIFACTS/artifacts.tsv
COMPLETE=$ARTIFACTS/.complete
INVENTORY=$ARTIFACTS/source-inventory.tsv
is_regular_file "$MANIFEST" || fail 'capacity artifact manifest is missing or unsafe'
is_regular_file "$COMPLETE" || fail 'capacity artifact completion marker is missing or unsafe'
is_regular_file "$INVENTORY" || fail 'capacity source inventory is missing or unsafe'
[ "$(cat "$COMPLETE")" = "$(sha256 "$MANIFEST")" ] ||
	fail 'capacity artifact completion marker changed'

awk -F '\t' '
	$1 == "schema" {if (NF != 2 || $2 != "bird-prefix-capacity-v1" || schema) {bad=1; next}; schema=1; next}
	$1 == "build-mode" {if (NF != 2 || ($2 != "production" && $2 != "host-test") || mode) {bad=1; next}; mode=1; next}
	$1 == "input" {if (NF != 4 || $2 != "boot-prefix-16m.bin" || $3 != 16777216 || length($4) != 64 || input) {bad=1; next}; input=1; next}
	$1 == "source-inventory" {if (NF != 4 || $2 != "source-inventory.tsv" || $3 !~ /^[0-9]+$/ || length($4) != 64 || inventory) {bad=1; next}; inventory=1; next}
	$1 == "prefix" {if (NF != 5 || ($2 != "legacy-128" && $2 != "expanded-138") || $3 !~ /^[A-Za-z0-9._-]+$/ || $4 != 163577856 || length($5) != 64 || seen[$2]) {bad=1; next}; seen[$2]=1; prefixes++; next}
	{bad=1}
	END {exit bad || schema != 1 || mode != 1 || input != 1 || inventory != 1 || prefixes != 2 || seen["legacy-128"] != 1 || seen["expanded-138"] != 1}
' "$MANIFEST" || fail 'capacity artifact manifest is malformed'
ARTIFACT_MODE=$(awk -F '\t' '$1 == "build-mode" {print $2}' "$MANIFEST")
BOOT_INPUT_SHA=$(awk -F '\t' '$1 == "input" && $2 == "boot-prefix-16m.bin" {print $4}' "$MANIFEST")
if [ "$HOST_TEST_MODE" -eq 0 ]; then
	[ "$ARTIFACT_MODE" = production ] ||
		fail 'host-test capacity artifacts cannot be installed on a real card'
	[ "$BOOT_INPUT_SHA" = "$PINNED_BOOT_PREFIX_SHA" ] ||
		fail 'capacity artifact boot-prefix authority changed'
fi
INVENTORY_BYTES=$(awk -F '\t' '$1 == "source-inventory" {print $3}' "$MANIFEST")
INVENTORY_SHA=$(awk -F '\t' '$1 == "source-inventory" {print $4}' "$MANIFEST")
[ "$(stat -f '%z' "$INVENTORY")" = "$INVENTORY_BYTES" ] &&
	[ "$(sha256 "$INVENTORY")" = "$INVENTORY_SHA" ] ||
	fail 'capacity source inventory verification failed'

VERIFY_WORK=$(mktemp -d "${TMPDIR:-/tmp}/bird-prefix-verify.XXXXXX") ||
	fail 'could not create private prefix verification directory'
INVENTORY_TOOL=$ROOT/kernel/rocknix/inventory-bird-fat-source.py
LAYOUT_TOOL=$ROOT/kernel/rocknix/build-bird-layout.py

verify_prefix() {
	VERIFY_LAYOUT=$1
	VERIFY_FAT_BYTES=$2
	PREFIX_NAME=$(awk -F '\t' -v layout="$VERIFY_LAYOUT" \
		'$1 == "prefix" && $2 == layout {print $3}' "$MANIFEST")
	PREFIX_SHA=$(awk -F '\t' -v layout="$VERIFY_LAYOUT" \
		'$1 == "prefix" && $2 == layout {print $5}' "$MANIFEST")
	PREFIX=$ARTIFACTS/$PREFIX_NAME
	is_regular_file "$PREFIX" || fail "$VERIFY_LAYOUT prefix is missing or unsafe"
	[ "$(stat -f '%z' "$PREFIX")" -eq "$PREFIX_BYTES" ] ||
		fail "$VERIFY_LAYOUT prefix size changed"
	[ "$(sha256 "$PREFIX")" = "$PREFIX_SHA" ] ||
		fail "$VERIFY_LAYOUT prefix checksum changed"
	VERIFY_BOOT=$VERIFY_WORK/$VERIFY_LAYOUT.boot
	"$GDD" if="$PREFIX" of="$VERIFY_BOOT" bs=4M count="$FAT_OFFSET" \
		iflag=count_bytes status=none
	if [ "$HOST_TEST_MODE" -eq 0 ]; then
		MASKED_BOOT_SHA=$(
			{
				"$GDD" if="$VERIFY_BOOT" bs=1 count=446 status=none
				"$GDD" if=/dev/zero bs=1 count=64 status=none
				"$GDD" if="$VERIFY_BOOT" bs=4M skip=510 \
					count=$((FAT_OFFSET - 510)) \
					iflag=skip_bytes,count_bytes status=none
			} | shasum -a 256 | awk '{print $1}'
		)
		[ "$MASKED_BOOT_SHA" = "$PINNED_MASKED_BOOT_SHA" ] ||
			fail "$VERIFY_LAYOUT boot/SPL/U-Boot bytes changed"
	fi
	VERIFY_COPY=$VERIFY_WORK/$VERIFY_LAYOUT.verify.img
	cp "$PREFIX" "$VERIFY_COPY"
	python3 "$LAYOUT_TOOL" --layout "$VERIFY_LAYOUT" "$VERIFY_COPY" >/dev/null
	cmp "$PREFIX" "$VERIFY_COPY" >/dev/null || fail "$VERIFY_LAYOUT partition records changed"
	FAT=$VERIFY_WORK/$VERIFY_LAYOUT.fat
	"$GDD" if="$PREFIX" of="$FAT" bs=4M skip="$FAT_OFFSET" \
		count="$VERIFY_FAT_BYTES" iflag=skip_bytes,count_bytes status=none
	fsck_msdos -n "$FAT" >/dev/null
	MOUNT=$VERIFY_WORK/$VERIFY_LAYOUT.mount
	mkdir "$MOUNT"
	ATTACHED=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage \
		-readonly -nobrowse -mountpoint "$MOUNT" "$FAT" | awk 'NR == 1 {print $1}')
	[ -n "$ATTACHED" ] || fail "could not mount $VERIFY_LAYOUT FAT for verification"
	python3 "$INVENTORY_TOOL" "$MOUNT" >"$VERIFY_WORK/$VERIFY_LAYOUT.inventory"
	cmp "$INVENTORY" "$VERIFY_WORK/$VERIFY_LAYOUT.inventory" >/dev/null ||
		fail "$VERIFY_LAYOUT prefix payload differs from its source inventory"
	hdiutil detach "$ATTACHED" >/dev/null
	ATTACHED=
}

verify_prefix legacy-128 "$LEGACY_BYTES"
verify_prefix expanded-138 "$EXPANDED_BYTES"
python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/current-before-lock.tsv"
cmp "$INVENTORY" "$VERIFY_WORK/current-before-lock.tsv" >/dev/null ||
	fail 'mounted BIRD payload changed since capacity artifacts were built'
validate_phase_identity "$SOURCE_BIRD_BYTES"
LOCKED_WHOLE=$WHOLE
bird_card_lock_acquire
validate_phase_identity "$SOURCE_BIRD_BYTES"
OBSERVED_WHOLE=$WHOLE
WHOLE=$LOCKED_WHOLE
[ "$OBSERVED_WHOLE" = "$LOCKED_WHOLE" ] ||
	fail 'card identity changed after acquiring its lock'
python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/current-under-lock.tsv"
cmp "$INVENTORY" "$VERIFY_WORK/current-under-lock.tsv" >/dev/null ||
	fail 'mounted BIRD payload changed before capacity write'

TARGET_NAME=$(awk -F '\t' -v layout="$TARGET_LAYOUT" \
	'$1 == "prefix" && $2 == layout {print $3}' "$MANIFEST")
TARGET_SHA=$(awk -F '\t' -v layout="$TARGET_LAYOUT" \
	'$1 == "prefix" && $2 == layout {print $5}' "$MANIFEST")
TARGET_PREFIX=$ARTIFACTS/$TARGET_NAME
SOURCE_BOOT=$VERIFY_WORK/$SOURCE_LAYOUT.boot
TARGET_BOOT=$VERIFY_WORK/$TARGET_LAYOUT.boot

printf 'Writing the verified %s layout to %s...\n' "$TARGET_LAYOUT" "$RAW_DISK"
if [ "$HOST_TEST_MODE" -eq 0 ]; then
	# Authenticate while every filesystem is still mounted and recoverable.
	sudo -v
	sudo "$GDD" if="$RAW_DISK" of="$VERIFY_WORK/current-boot.bin" bs=4M \
		count="$FAT_OFFSET" iflag=count_bytes,fullblock status=none
	cmp "$VERIFY_WORK/current-boot.bin" "$SOURCE_BOOT" >/dev/null ||
		fail 'current boot/SPL/U-Boot bytes differ from the source-layout oracle'
	diskutil unmountDisk "/dev/$WHOLE" >/dev/null
	MOUNTED=0
	sudo "$GDD" if="$TARGET_PREFIX" of="$RAW_DISK" bs=4M \
		conv=fsync,notrunc status=progress
	RAW_VERIFIED=0
	if diskutil unmountDisk force "/dev/$WHOLE" >/dev/null 2>&1; then
		DEVICE_SHA=$(sudo "$GDD" if="$RAW_DISK" bs=4M count="$PREFIX_BYTES" \
			iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')
		if [ "$DEVICE_SHA" = "$TARGET_SHA" ]; then
			RAW_VERIFIED=1
		fi
	fi
else
	"$GDD" if="$RAW_DISK" of="$VERIFY_WORK/current-boot.bin" bs=4M \
		count="$FAT_OFFSET" iflag=count_bytes,fullblock status=none
	cmp "$VERIFY_WORK/current-boot.bin" "$SOURCE_BOOT" >/dev/null ||
		fail 'current boot/SPL/U-Boot bytes differ from the source-layout oracle'
	"$GDD" if="$TARGET_PREFIX" of="$RAW_DISK" bs=4M \
		conv=fsync,notrunc status=none
	DEVICE_SHA=$("$GDD" if="$RAW_DISK" bs=4M count="$PREFIX_BYTES" \
		iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')
	[ "$DEVICE_SHA" = "$TARGET_SHA" ] || fail "raw prefix verification failed: $DEVICE_SHA"
	RAW_VERIFIED=1
fi

if [ "$HOST_TEST_MODE" -eq 0 ]; then
	diskutil mountDisk "/dev/$WHOLE" >/dev/null
fi
MOUNTED=1
DEVICE_PHASE=target
validate_phase_identity "$TARGET_BIRD_BYTES"
OBSERVED_WHOLE=$WHOLE
WHOLE=$LOCKED_WHOLE
[ "$OBSERVED_WHOLE" = "$LOCKED_WHOLE" ] ||
	fail 'card identity changed after remounting the capacity layout'
if [ "$HOST_TEST_MODE" -eq 0 ]; then
	sudo "$GDD" if="$RAW_DISK" of="$VERIFY_WORK/installed-boot.bin" bs=4M \
		count="$FAT_OFFSET" iflag=count_bytes,fullblock status=none
	cmp "$VERIFY_WORK/installed-boot.bin" "$TARGET_BOOT" >/dev/null ||
		fail 'installed boot/SPL/U-Boot bytes differ from the target-layout oracle'
	diskutil verifyVolume "$BIRD" >/dev/null ||
		fail 'installed BIRD FAT filesystem verification failed'
fi
python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/current-after.tsv"
cmp "$INVENTORY" "$VERIFY_WORK/current-after.tsv" >/dev/null ||
	fail 'mounted BIRD payload differs after capacity migration'
sync

if [ "$RAW_VERIFIED" -eq 1 ]; then
	printf 'BIRD prefix now uses %s and exact raw verification passed.\n' "$TARGET_LAYOUT"
else
	printf 'BIRD prefix now uses %s; macOS changed FAT metadata, while boot bytes, geometry, filesystem and payload verified.\n' "$TARGET_LAYOUT"
fi
printf 'p5 root and p6 data byte ranges were not written.\n'
printf 'Keep both prefix artifacts until the RG34XX-SP physical gate passes.\n'
printf 'Safe eject: diskutil eject /dev/%s\n' "$WHOLE"
