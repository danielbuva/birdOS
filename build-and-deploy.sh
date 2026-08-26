#!/bin/sh
# One guarded macOS entry point for the canonical birdOS build and deployment.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
BASE_RELEASE_ID=v6.23
MODE=
KERNEL_AUTHORITY=stock
REQUESTED_RELEASE_ID=
DRY_RUN=0
HOST_TEST_MODE=${BIRD_BUILD_DEPLOY_HOST_TEST_MODE:-0}
ARCHIVE_REPOSITORY=${BIRD_RELEASE_ARCHIVE_REPOSITORY:-danielbuva/birdOS-release-archive}
RUN_TEMP=
BIRD_WRITE_PROBE=
DATA_WRITE_PROBE=
BIRD_CARD_LOCK_SCRIPT_LOADED=0
BIRD_CARD_LOCK_OWNED=0
LEGACY_KERNEL_RETIRE=0
LEGACY_KERNEL_RECLAIM_BYTES=0
PINNED_SOURCE_KERNEL_SHA=
PINNED_SOURCE_DTB_SHA=
PINNED_IMMUTABLE_SOURCE_ID=
KOREADER_CATEGORY_COUNT=0
KOREADER_EXTRACTION_RESERVE=0
KOREADER_EXTRACTION_STATE=not-required
PORTMASTER_PROVIDER_MARKER_VALUE=
PORTMASTER_PROVIDER_MARKER_STATE=
ROTATION_SELECTOR_TEMP=

usage() {
	cat <<'EOF'
Usage:
  ./build-and-deploy.sh --release [--source-kernel-parity|--builtin-input-kernel|--single-gpio-read-kernel|--single-input-sync-kernel|--changed-input-sync-kernel|--fixed-gpio-fastpath-kernel|--irq-buttons-kernel|--irq-buttons-lz4-kernel] [--release-id ID] [--dry-run]
  ./build-and-deploy.sh --profile [--release-id ID] [--dry-run]
  ./build-and-deploy.sh --help

Modes:
  --release       Build the ordinary launcher with profiling disabled.
  --profile       Build with BIRD_LAUNCHER_PROFILE=profile.

Options:
  --release-id ID Use ID as the preferred immutable release ID. If that ID is
                  already present on the card or in the GitHub archive, a
                  timestamped unused ID is selected.
  --source-kernel-parity
                  Build the pinned Stage 8 source kernel, source modules,
                  shipping-identical DTB and accepted current userspace.
                  Valid only with --release.
  --builtin-input-kernel
                  Build the pinned Stage 9 kernel with the exact RG34XX-SP
                  joypad driver linked into the Image. Valid only with --release.
  --single-gpio-read-kernel
                  Build the Stage 9 built-in-input kernel with one GPIO read
                  per button per polling cycle. Valid only with --release.
  --single-input-sync-kernel
                  Build the Stage 9 kernel with one combined axes-and-buttons
                  input frame per polling cycle. Valid only with --release.
  --changed-input-sync-kernel
                  Build the Stage 9 kernel that publishes the combined input
                  frame only when a control changed. Valid only with --release.
  --fixed-gpio-fastpath-kernel
                  Build the Stage 9 fixed-H700 GPIO access and single-open-frame
                  kernel. Valid only with --release.
  --irq-buttons-kernel
                  Build the Stage 9 kernel with IRQ-backed digital controls and
                  analog-only 10 ms polling. Valid only with --release.
  --irq-buttons-lz4-kernel
                  Build the same accepted IRQ kernel as the exact reviewed LZ4
                  frame for the Stage 10 production successor. Valid only with
                  --release.
  --dry-run       Perform read-only preflight and print the selected commands.
  --help          Show this help text.

The command requires the exact BIRD and BIRD-DATA volumes on the supported
RG34XX-SP card. It never scans or modifies ROMs, BIOS, media, saves, or other
card data. When BIRD lacks staging space, it may retire the minimum ordered set
of inactive completed releases needed only after archiving and verifying each
one in the configured private, immutable GitHub release repository. After a
successful activation it archives and verifies the superseded immutable
release, makes the exact current selector authoritative as previous, and only
then removes the old card copy. No alternate boot release is retained. When the
active selector already uses a verified
immutable release, the command may also retire the byte-identical, unreferenced
pre-versioned top-level KERNEL.
EOF
}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

cleanup() {
	if [ -n "$ROTATION_SELECTOR_TEMP" ]; then
		case "$ROTATION_SELECTOR_TEMP" in
			/Volumes/BIRD/extlinux/.extlinux.previous.conf.rotate-new.*|/private/tmp/*/Volumes/BIRD/extlinux/.extlinux.previous.conf.rotate-new.*|/var/folders/*/Volumes/BIRD/extlinux/.extlinux.previous.conf.rotate-new.*|/tmp/*/Volumes/BIRD/extlinux/.extlinux.previous.conf.rotate-new.*)
				rm -f "$ROTATION_SELECTOR_TEMP"
				;;
		esac
	fi
	if [ "$BIRD_CARD_LOCK_SCRIPT_LOADED" -eq 1 ]; then
		bird_card_lock_release
	fi
	[ -z "$BIRD_WRITE_PROBE" ] || rm -f "$BIRD_WRITE_PROBE"
	[ -z "$DATA_WRITE_PROBE" ] || rm -f "$DATA_WRITE_PROBE"
	if [ -n "$RUN_TEMP" ]; then
		case "$RUN_TEMP" in
			/var/folders/*|/private/tmp/*|/tmp/*) rm -rf "$RUN_TEMP" ;;
		esac
	fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

set_mode() {
	[ -z "$MODE" ] || fail 'choose exactly one of --profile or --release'
	MODE=$1
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--profile) set_mode profile ;;
		--release) set_mode release ;;
		--source-kernel-parity)
			[ "$KERNEL_AUTHORITY" = stock ] || \
				fail '--source-kernel-parity was supplied more than once'
			KERNEL_AUTHORITY=source-parity
			;;
		--builtin-input-kernel)
			[ "$KERNEL_AUTHORITY" = stock ] || \
				fail 'choose only one source-kernel authority'
			KERNEL_AUTHORITY=source-builtin-input
			;;
		--single-gpio-read-kernel)
			[ "$KERNEL_AUTHORITY" = stock ] || \
				fail 'choose only one source-kernel authority'
			KERNEL_AUTHORITY=source-single-gpio-read
			;;
		--single-input-sync-kernel)
			[ "$KERNEL_AUTHORITY" = stock ] || \
				fail 'choose only one source-kernel authority'
			KERNEL_AUTHORITY=source-single-input-sync
			;;
		--changed-input-sync-kernel)
			[ "$KERNEL_AUTHORITY" = stock ] || \
				fail 'choose only one source-kernel authority'
			KERNEL_AUTHORITY=source-changed-input-sync
			;;
		--fixed-gpio-fastpath-kernel)
			[ "$KERNEL_AUTHORITY" = stock ] || \
				fail 'choose only one source-kernel authority'
			KERNEL_AUTHORITY=source-fixed-gpio-fastpath
			;;
		--irq-buttons-kernel)
			[ "$KERNEL_AUTHORITY" = stock ] || \
				fail 'choose only one source-kernel authority'
			KERNEL_AUTHORITY=source-irq-buttons
			;;
		--irq-buttons-lz4-kernel)
			[ "$KERNEL_AUTHORITY" = stock ] || \
				fail 'choose only one source-kernel authority'
			KERNEL_AUTHORITY=source-irq-buttons-lz4
			;;
		--release-id)
			[ "$#" -ge 2 ] || fail '--release-id requires a value'
			[ -z "$REQUESTED_RELEASE_ID" ] || fail '--release-id was supplied more than once'
			REQUESTED_RELEASE_ID=$2
			shift
			;;
		--release-id=*)
			[ -z "$REQUESTED_RELEASE_ID" ] || fail '--release-id was supplied more than once'
			REQUESTED_RELEASE_ID=${1#--release-id=}
			;;
		--dry-run) [ "$DRY_RUN" -eq 0 ] || fail '--dry-run was supplied more than once'; DRY_RUN=1 ;;
		--help|-h) usage; exit 0 ;;
		--) shift; [ "$#" -eq 0 ] || fail 'positional arguments are not supported'; break ;;
		-*) fail "unknown option: $1" ;;
		*) fail "unexpected positional argument: $1" ;;
	esac
	shift
done

[ -n "$MODE" ] || fail 'choose exactly one of --profile or --release'
[ "$KERNEL_AUTHORITY" = stock ] || [ "$MODE" = release ] || \
	fail 'source-kernel authorities require --release'
[ -n "$REQUESTED_RELEASE_ID" ] || REQUESTED_RELEASE_ID=$BASE_RELEASE_ID
case "$REQUESTED_RELEASE_ID" in
	''|[![:alnum:]]*|*[![:alnum:]._-]*) fail "unsafe Bird release ID: $REQUESTED_RELEASE_ID" ;;
esac
[ "${#REQUESTED_RELEASE_ID}" -le 64 ] || fail 'Bird release ID is longer than 64 bytes'
[ "$(printf '%s' "$REQUESTED_RELEASE_ID" | LC_ALL=C tr '[:upper:]' '[:lower:]')" != dev-current ] || \
	fail 'production release ID dev-current is reserved; run ./dev-build-and-deploy.sh --clean before production deployment'
BIRD_INITRAMFS_GZIP_LEVEL=${BIRD_INITRAMFS_GZIP_LEVEL:-9}
case "$BIRD_INITRAMFS_GZIP_LEVEL" in
	1|9) ;;
	*) fail 'Bird initramfs gzip level must be 1 or 9' ;;
esac
export BIRD_INITRAMFS_GZIP_LEVEL
printf '%s\n' "$ARCHIVE_REPOSITORY" | \
	awk '/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/ {found++} END {exit found != 1}' || \
	fail "unsafe GitHub archive repository: $ARCHIVE_REPOSITORY"

[ "$(uname -s)" = Darwin ] || fail 'build-and-deploy is supported only on macOS'
[ -e "$ROOT/.git" ] && [ ! -L "$ROOT/.git" ] || \
	fail "repository metadata missing or unsafe at expected root: $ROOT"
GIT_ROOT=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) || \
	fail 'could not identify the Git repository root'
ROOT_REAL=$(CDPATH= cd -- "$ROOT" && pwd -P)
GIT_ROOT_REAL=$(CDPATH= cd -- "$GIT_ROOT" && pwd -P)
[ "$ROOT_REAL" = "$GIT_ROOT_REAL" ] || fail 'script is not running from the birdOS repository root'
for REQUIRED_SOURCE in ACTIVE_PATH.md \
	kernel/rocknix/build-stock-root-compat.sh \
	kernel/rocknix/build-stock-root-early-initramfs.sh \
	firmware/generate-launcher-bootlogo.py \
	firmware/assets/bird-launcher-backdrop.png \
	firmware/mac-update-rocknix-stock-root-v6.sh \
	firmware/mac-bird-card-lock.sh \
	firmware/mac-stock-root-card-identity.sh \
	launcher/catalog.generated.h \
	kernel/rocknix/stock-root/run-content.sh \
	kernel/rocknix/stock-root/portmaster-provider.manifest.tsv \
	kernel/rocknix/stock-root/verify-portmaster-provider.sh; do
	[ -f "$ROOT/$REQUIRED_SOURCE" ] && [ ! -L "$ROOT/$REQUIRED_SOURCE" ] || \
		fail "required repository source missing or unsafe: $REQUIRED_SOURCE"
done

# shellcheck source=firmware/mac-bird-card-lock.sh
. "$ROOT/firmware/mac-bird-card-lock.sh"
BIRD_CARD_LOCK_SCRIPT_LOADED=1

case "$HOST_TEST_MODE" in
	0)
		BIRD=/Volumes/BIRD
		DATA=/Volumes/BIRD-DATA
		VOLUMES_ROOT=/Volumes
		WORK_ROOT=$ROOT/kernel/work
		BUILDER=$ROOT/kernel/rocknix/build-stock-root-compat.sh
		UPDATER=$ROOT/firmware/mac-update-rocknix-stock-root-v6.sh
		BIRD_DEVICE_INFO=
		CLANG=/opt/homebrew/opt/llvm/bin/clang
		LLD=/opt/homebrew/opt/lld/bin/ld.lld
		READELF=/opt/homebrew/opt/llvm/bin/llvm-readelf
		GH=$(command -v gh || :)
		;;
	1)
		: "${BIRD:?host-test BIRD is required}"
		: "${DATA:?host-test DATA is required}"
		: "${VOLUMES_ROOT:?host-test VOLUMES_ROOT is required}"
		: "${WORK_ROOT:?host-test WORK_ROOT is required}"
		: "${BUILDER:?host-test BUILDER is required}"
		: "${UPDATER:?host-test UPDATER is required}"
		: "${BIRD_DEVICE_INFO:?host-test BIRD_DEVICE_INFO is required}"
		: "${CLANG:?host-test CLANG is required}"
		: "${LLD:?host-test LLD is required}"
		: "${READELF:?host-test READELF is required}"
		[ -n "${GH:-}" ] || fail 'host-test GH is required'
		for TEST_PATH in "$BIRD" "$DATA" "$VOLUMES_ROOT" "$WORK_ROOT" \
			"$BUILDER" "$UPDATER" "$BIRD_DEVICE_INFO" "$CLANG" "$LLD" "$READELF" "$GH"; do
			case "$TEST_PATH" in
				/var/folders/*|/private/tmp/*|/tmp/*) ;;
				*) fail "host-test path is not a temporary fixture: $TEST_PATH" ;;
			esac
			case "$TEST_PATH" in
				*/../*|*/..|*/./*) fail "host-test path contains traversal: $TEST_PATH" ;;
			esac
		if [ -d "$TEST_PATH" ]; then
			TEST_PATH_REAL=$(CDPATH= cd -- "$TEST_PATH" && pwd -P)
		else
			TEST_PATH_PARENT=$(CDPATH= cd -- "$(dirname "$TEST_PATH")" && pwd -P)
			TEST_PATH_REAL=$TEST_PATH_PARENT/$(basename "$TEST_PATH")
		fi
		case "$TEST_PATH_REAL" in
			/private/var/folders/*|/private/tmp/*) ;;
			*) fail "host-test path resolves outside temporary storage: $TEST_PATH" ;;
		esac
		done
		;;
	*) fail 'invalid build-and-deploy host-test mode' ;;
esac

SOURCE=$BIRD
SYSTEM_SOURCE=${SYSTEM_SOURCE:-}
STORAGE_SOURCE=${STORAGE_SOURCE:-$HOME/rocknix-reference-result/storage.ext4}
SYSTEM_TREE=${SYSTEM_TREE:-$ROOT/kernel/work/rocknix-system-exact-20260701}
OFFICIAL_INIT=${OFFICIAL_INIT:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/init}
JOYPAD=${JOYPAD:-$ROOT/kernel/work/rocknix-system-exact-20260701/usr/lib/kernel-overlays/base/lib/modules/7.0.11/rocknix-joypad/rocknix-singleadc-joypad.ko}
SOURCE_KERNEL_BUILD=$ROOT/kernel/work/rocknix-source-reference/build
SOURCE_KERNEL_SYSTEM=$ROOT/kernel/work/rocknix-source-kernel-system/SYSTEM
SOURCE_KERNEL_AUTHORITY_RECORD=$ROOT/kernel/rocknix/source-kernel-parity.tsv
if [ "$KERNEL_AUTHORITY" = source-builtin-input ]; then
	SOURCE_KERNEL_BUILD=$ROOT/kernel/work/rocknix-source-builtin-joypad/build
	SOURCE_KERNEL_SYSTEM=$ROOT/kernel/work/rocknix-source-builtin-joypad-system/SYSTEM
	SOURCE_KERNEL_AUTHORITY_RECORD=$ROOT/kernel/rocknix/source-kernel-builtin-input.tsv
fi
if [ "$KERNEL_AUTHORITY" = source-single-gpio-read ]; then
	SOURCE_KERNEL_BUILD=$ROOT/kernel/work/rocknix-source-single-gpio-read/build
	SOURCE_KERNEL_SYSTEM=$ROOT/kernel/work/rocknix-source-builtin-joypad-system/SYSTEM
	SOURCE_KERNEL_AUTHORITY_RECORD=$ROOT/kernel/rocknix/source-kernel-single-gpio-read.tsv
fi
if [ "$KERNEL_AUTHORITY" = source-single-input-sync ]; then
	SOURCE_KERNEL_BUILD=$ROOT/kernel/work/rocknix-source-single-input-sync/build
	SOURCE_KERNEL_SYSTEM=$ROOT/kernel/work/rocknix-source-builtin-joypad-system/SYSTEM
	SOURCE_KERNEL_AUTHORITY_RECORD=$ROOT/kernel/rocknix/source-kernel-single-input-sync.tsv
fi
if [ "$KERNEL_AUTHORITY" = source-changed-input-sync ]; then
	SOURCE_KERNEL_BUILD=$ROOT/kernel/work/rocknix-source-changed-input-sync/build
	SOURCE_KERNEL_SYSTEM=$ROOT/kernel/work/rocknix-source-builtin-joypad-system/SYSTEM
	SOURCE_KERNEL_AUTHORITY_RECORD=$ROOT/kernel/rocknix/source-kernel-changed-input-sync.tsv
fi
if [ "$KERNEL_AUTHORITY" = source-fixed-gpio-fastpath ]; then
	SOURCE_KERNEL_BUILD=$ROOT/kernel/work/rocknix-source-fixed-gpio-fastpath/build
	SOURCE_KERNEL_SYSTEM=$ROOT/kernel/work/rocknix-source-builtin-joypad-system/SYSTEM
	SOURCE_KERNEL_AUTHORITY_RECORD=$ROOT/kernel/rocknix/source-kernel-fixed-gpio-fastpath.tsv
fi
if [ "$KERNEL_AUTHORITY" = source-irq-buttons ]; then
	SOURCE_KERNEL_BUILD=$ROOT/kernel/work/rocknix-source-irq-buttons/build
	SOURCE_KERNEL_SYSTEM=$ROOT/kernel/work/rocknix-source-builtin-joypad-system/SYSTEM
	SOURCE_KERNEL_AUTHORITY_RECORD=$ROOT/kernel/rocknix/source-kernel-irq-buttons.tsv
fi
if [ "$KERNEL_AUTHORITY" = source-irq-buttons-lz4 ]; then
	SOURCE_KERNEL_BUILD=$ROOT/kernel/work/rocknix-source-irq-buttons/build
	SOURCE_KERNEL_SYSTEM=$ROOT/kernel/work/rocknix-source-builtin-joypad-system/SYSTEM
	SOURCE_KERNEL_AUTHORITY_RECORD=$ROOT/kernel/rocknix/source-kernel-irq-buttons-lz4.tsv
fi
SOURCE_KERNEL_PAYLOAD=$SOURCE_KERNEL_BUILD/Image
if [ "$KERNEL_AUTHORITY" = source-irq-buttons-lz4 ]; then
	SOURCE_KERNEL_PAYLOAD=$ROOT/kernel/work/bird-kernel-lz4-irq-candidate-20260813/KERNEL.lz4
fi
INIT_BUSYBOX=${INIT_BUSYBOX:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/usr/bin/busybox}
PORTMASTER_ARCHIVE=${PORTMASTER_ARCHIVE:-$SYSTEM_TREE/usr/config/PortMaster/release/PortMaster.zip}
KOREADER_CATALOG_HEADER=$ROOT/launcher/catalog.generated.h
KOREADER_CONTRACT=$ROOT/kernel/rocknix/stock-root/run-content.sh
PORTMASTER_PROVIDER_MANIFEST=$ROOT/kernel/rocknix/stock-root/portmaster-provider.manifest.tsv
PORTMASTER_PROVIDER_VERIFIER=$ROOT/kernel/rocknix/stock-root/verify-portmaster-provider.sh
if [ "$HOST_TEST_MODE" -eq 0 ]; then
	[ -z "${BIRD_TEST_KOREADER_CATALOG_HEADER:-}${BIRD_TEST_KOREADER_SOURCE_SHA:-}${BIRD_TEST_KOREADER_ARCHIVE_SHA:-}${BIRD_TEST_KOREADER_ARCHIVE_BYTES:-}${BIRD_TEST_KOREADER_EXPANDED_BYTES:-}${BIRD_TEST_KOREADER_ARCHIVE_ENTRIES:-}${BIRD_TEST_PORTMASTER_PROVIDER_MANIFEST:-}" ] || \
		fail 'KOReader preflight overrides require host-test mode'
elif [ -n "${BIRD_TEST_KOREADER_CATALOG_HEADER:-}" ]; then
	KOREADER_CATALOG_HEADER=$BIRD_TEST_KOREADER_CATALOG_HEADER
	case "$KOREADER_CATALOG_HEADER" in
		/var/folders/*|/private/tmp/*|/tmp/*) ;;
		*) fail 'host-test KOReader catalog header must be a temporary fixture' ;;
	esac
fi
if [ "$HOST_TEST_MODE" -eq 1 ] && \
	[ -n "${BIRD_TEST_PORTMASTER_PROVIDER_MANIFEST:-}" ]; then
	PORTMASTER_PROVIDER_MANIFEST=$BIRD_TEST_PORTMASTER_PROVIDER_MANIFEST
	case "$PORTMASTER_PROVIDER_MANIFEST" in
		/var/folders/*|/private/tmp/*|/tmp/*) ;;
		*) fail 'host-test PortMaster provider manifest must be a temporary fixture' ;;
	esac
fi

RUN_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-build-deploy.XXXXXX") || \
	fail 'could not create private host workspace'

if [ "$HOST_TEST_MODE" -eq 0 ]; then
	command -v brew >/dev/null 2>&1 || fail 'Homebrew is required: https://brew.sh/'
	for TOOL in "$CLANG" "$LLD" "$READELF"; do
		[ -x "$TOOL" ] || fail "required Homebrew tool missing: $TOOL"
	done
	for COMMAND in diskutil git shasum awk sed sort find stat file strings \
		unzip python3 cpio gzip xattr tar; do
		command -v "$COMMAND" >/dev/null 2>&1 || fail "required host command missing: $COMMAND"
	done
	[ -x /usr/bin/lockf ] || fail 'required macOS lock helper missing: /usr/bin/lockf'
else
	for TOOL in "$CLANG" "$LLD" "$READELF" "$BUILDER" "$UPDATER"; do
		[ -x "$TOOL" ] || fail "required host-test executable missing: $TOOL"
	done
fi

VOLUME_MATCHES=$RUN_TEMP/volume-matches
find "$VOLUMES_ROOT" -mindepth 1 -maxdepth 1 -type d -print | \
	awk -F/ '$NF == "BIRD" || $NF ~ /^BIRD [0-9]+$/ {print}' >"$VOLUME_MATCHES"
[ "$(wc -l <"$VOLUME_MATCHES" | tr -d ' ')" -eq 1 ] || \
	fail 'BIRD volume is missing or ambiguous'
[ "$(cat "$VOLUME_MATCHES")" = "$BIRD" ] || fail "expected BIRD mount is missing: $BIRD"
find "$VOLUMES_ROOT" -mindepth 1 -maxdepth 1 -type d -print | \
	awk -F/ '$NF == "BIRD-DATA" || $NF ~ /^BIRD-DATA [0-9]+$/ {print}' >"$VOLUME_MATCHES"
[ "$(wc -l <"$VOLUME_MATCHES" | tr -d ' ')" -eq 1 ] || \
	fail 'BIRD-DATA volume is missing or ambiguous'
[ "$(cat "$VOLUME_MATCHES")" = "$DATA" ] || fail "expected BIRD-DATA mount is missing: $DATA"

# shellcheck source=firmware/mac-stock-root-card-identity.sh
. "$ROOT/firmware/mac-stock-root-card-identity.sh"
validate_stock_root_card_identity

NAMESPACE_MARKER=$DATA/Bird/namespace-v1.tsv
[ -f "$NAMESPACE_MARKER" ] && [ ! -L "$NAMESPACE_MARKER" ] &&
	[ "$(wc -l <"$NAMESPACE_MARKER" | tr -d ' ')" -eq 2 ] &&
	grep -Fqx 'revision	bird-canonical-namespace-v1' "$NAMESPACE_MARKER" &&
	grep -Fqx 'state	committed' "$NAMESPACE_MARKER" ||
	fail 'canonical namespace v1 is not committed; run the migration transaction first'

BIRD_FS=$(field "$BIRD" 'File System Personality')
case "$BIRD_FS" in
	*FAT*|*ExFAT*) BIRD_SYNTHETIC_MODES=1 ;;
	*) BIRD_SYNTHETIC_MODES=0 ;;
esac

is_regular_file() {
	[ -f "$1" ] && [ ! -L "$1" ]
}

selector_names_dev_current() {
	awk '
		$1 == "APPEND" {
			for (field = 2; field <= NF; field++)
				if (tolower($field) == "bird_release=dev-current") found++
		}
		END {exit found == 0}
	' "$1"
}

reject_dev_current_production_state() {
	DEV_ACTIVE_SELECTOR=$BIRD/extlinux/extlinux.conf
	if is_regular_file "$DEV_ACTIVE_SELECTOR" && \
		selector_names_dev_current "$DEV_ACTIVE_SELECTOR"; then
		fail 'active selector names mutable dev-current; run ./dev-build-and-deploy.sh --clean before production deployment'
	fi
	for DEV_ENTRY in "$BIRD"/*; do
		[ -e "$DEV_ENTRY" ] || [ -L "$DEV_ENTRY" ] || continue
		DEV_ENTRY_NAME=${DEV_ENTRY##*/}
		case "$(printf '%s' "$DEV_ENTRY_NAME" | LC_ALL=C tr '[:upper:]' '[:lower:]')" in
			bird-dev)
				fail 'development metadata exists at BIRD/bird-dev; run ./dev-build-and-deploy.sh --clean before production deployment'
				;;
			bird-dev-cleanup.tsv)
				fail 'development cleanup authority exists at BIRD/bird-dev-cleanup.tsv; run ./dev-build-and-deploy.sh --recover-production then --clean-recovered'
				;;
		esac
	done
	for DEV_ENTRY in "$BIRD"/.*; do
		[ -e "$DEV_ENTRY" ] || [ -L "$DEV_ENTRY" ] || continue
		DEV_ENTRY_NAME=${DEV_ENTRY##*/}
		DEV_ENTRY_NORMALIZED=$(printf '%s' "$DEV_ENTRY_NAME" | \
			LC_ALL=C tr '[:upper:]' '[:lower:]')
		case "$DEV_ENTRY_NORMALIZED" in
			.bird-dev-cleanup.tsv.dev-new.*)
				fail 'interrupted development cleanup-authority publication exists at BIRD/.bird-dev-cleanup.tsv.dev-new.*; run ./dev-build-and-deploy.sh --clean or --clean-recovered'
				;;
			._bird-dev-cleanup.tsv|._.bird-dev-cleanup.tsv.dev-new.*)
				fail 'interrupted development cleanup-authority metadata exists on BIRD; run ./dev-build-and-deploy.sh --clean or --clean-recovered'
				;;
		esac
	done
	for DEV_ENTRY in "$BIRD/bird-releases"/*; do
		[ -e "$DEV_ENTRY" ] || [ -L "$DEV_ENTRY" ] || continue
		DEV_ENTRY_NAME=${DEV_ENTRY##*/}
		if [ "$(printf '%s' "$DEV_ENTRY_NAME" | LC_ALL=C tr '[:upper:]' '[:lower:]')" = dev-current ]; then
			fail 'mutable release exists at BIRD/bird-releases/dev-current; run ./dev-build-and-deploy.sh --clean before production deployment'
		fi
	done
	# A hard interruption during the first development copy can leave the
	# same-filesystem staging sibling behind. Hidden stages are excluded from
	# ordinary production release enumeration, so reserve this exact normalized
	# prefix explicitly instead of allowing the stale copy to consume space.
	for DEV_ENTRY in "$BIRD/bird-releases"/.*; do
		[ -e "$DEV_ENTRY" ] || [ -L "$DEV_ENTRY" ] || continue
		DEV_ENTRY_NAME=${DEV_ENTRY##*/}
		DEV_ENTRY_NORMALIZED=$(printf '%s' "$DEV_ENTRY_NAME" | \
			LC_ALL=C tr '[:upper:]' '[:lower:]')
		case "$DEV_ENTRY_NORMALIZED" in
			.dev-current.new.*)
				fail 'stale mutable release stage exists at BIRD/bird-releases/.dev-current.new.*; run ./dev-build-and-deploy.sh --clean before production deployment'
				;;
		esac
	done
}

# dev-current is intentionally mutable and must never become a production
# previous selector or a generic inactive release-retirement candidate. This
# read-only boundary runs before pinned-input preparation, builder preflight,
# release retirement, or any card write.
reject_dev_current_production_state

file_bytes() {
	stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"
}

file_mode() {
	stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

verify_installed_mode() {
	TARGET_PATH=$1
	EXPECTED_MODE=$2
	if [ "$BIRD_SYNTHETIC_MODES" -eq 0 ]; then
		[ "$(file_mode "$TARGET_PATH")" = "$EXPECTED_MODE" ]
		return
	fi

	# FAT does not retain Unix mode bits. Match the canonical updater's
	# fat-capability policy and verify the effective owner capabilities that the
	# manifest requires instead of comparing macOS's synthetic stat value.
	OWNER_MODE=$(printf '%s' "$EXPECTED_MODE" | cut -c1)
	[ -r "$TARGET_PATH" ] || return 1
	case "$OWNER_MODE" in 2|3|6|7) [ -w "$TARGET_PATH" ] || return 1 ;; esac
	case "$OWNER_MODE" in 1|3|5|7) [ -x "$TARGET_PATH" ] || return 1 ;; esac
	return 0
}

validate_completed_release() {
	VALIDATED_DIR=$1
	VALIDATED_ID=$2
	VALIDATED_PURPOSE=$3
	VALIDATED_ROOT=${4:-$BIRD/bird-releases}
	case "$VALIDATED_ID" in
		''|[![:alnum:]]*|*[![:alnum:]._-]*) fail "$VALIDATED_PURPOSE has an unsafe release ID" ;;
	esac
	[ -d "$VALIDATED_DIR" ] && [ ! -L "$VALIDATED_DIR" ] || \
		fail "$VALIDATED_PURPOSE is not a safe directory: $VALIDATED_DIR"
	[ "$VALIDATED_DIR" = "$VALIDATED_ROOT/$VALIDATED_ID" ] || \
		fail "$VALIDATED_PURPOSE path does not match its release ID"
	is_regular_file "$VALIDATED_DIR/deploy-manifest.tsv" || \
		fail "$VALIDATED_PURPOSE manifest is missing or unsafe: $VALIDATED_ID"
	is_regular_file "$VALIDATED_DIR/.complete" || \
		fail "$VALIDATED_PURPOSE completion marker is missing or unsafe: $VALIDATED_ID"
	VALIDATED_MANIFEST_SHA=$(sha256 "$VALIDATED_DIR/deploy-manifest.tsv")
	[ "$(cat "$VALIDATED_DIR/.complete")" = "$VALIDATED_MANIFEST_SHA" ] || \
		fail "$VALIDATED_PURPOSE completion marker changed: $VALIDATED_ID"

	VALIDATED_RECORDS=$RUN_TEMP/validated-release-records
	VALIDATED_EXPECTED_FILES=$RUN_TEMP/validated-release-expected-files
	VALIDATED_ACTUAL_FILES=$RUN_TEMP/validated-release-actual-files
	VALIDATED_EXPECTED_DIRS=$RUN_TEMP/validated-release-expected-dirs
	VALIDATED_ACTUAL_DIRS=$RUN_TEMP/validated-release-actual-dirs
	VALIDATED_DUPLICATES=$RUN_TEMP/validated-release-duplicates
	awk -F '\t' -v expected_release="$VALIDATED_ID" '
		function safe_path(path) {
			return path ~ /^[A-Za-z0-9._\/-]+$/ && path !~ /(^|\/)\.\.?($|\/)/
		}
		$1 == "schema" {if (NF != 2 || $2 != "bird-deploy-v1" || schema++) exit 1; next}
		$1 == "release" {if (NF != 2 || $2 != expected_release || release++) exit 1; next}
		$1 == "target-mode-policy" {if (NF != 2 || $2 != "fat-capability" || policy++) exit 1; next}
		$1 == "source-commit" {if (NF != 3 || source++) exit 1; next}
		$1 == "artifact" {
			if (NF != 4 || ($2 != "device-contract" && $2 != "catalog") ||
			    !safe_path($3) || length($4) != 64 || $4 ~ /[^0-9a-f]/) exit 1
			if ($2 == "device-contract") device_contract++
			if ($2 == "catalog") catalog++
			print "artifact\t" $2 "\t" $3 "\t" $4
			artifacts++; next
		}
		$1 == "input" {
			if (NF != 6 || !safe_path($2) || $3 !~ /^[0-7][0-7][0-7]$/ ||
			    $4 !~ /^[0-9]+$/ || length($5) != 64 || $5 ~ /[^0-9a-f]/ || $6 == "") exit 1
			inputs++; next
		}
		$1 == "dir" {
			if (NF != 3 || !safe_path($2) || $3 !~ /^[0-7][0-7][0-7]$/) exit 1
			print "dir\t" $2; next
		}
		$1 == "file" {
			if (NF != 5 || !safe_path($2) || $3 !~ /^[0-7][0-7][0-7]$/ ||
			    $4 !~ /^[0-9]+$/ || length($5) != 64 || $5 ~ /[^0-9a-f]/) exit 1
			print "file\t" $2 "\t" $3 "\t" $4 "\t" $5; files++; next
		}
		{exit 1}
		END {
			if (schema != 1 || release != 1 || policy != 1 || source != 1 ||
			    (inputs != 14 && inputs != 15) || files < 1 ||
			    (artifacts != 0 && artifacts != 2) ||
			    (artifacts == 2 && (device_contract != 1 || catalog != 1))) exit 1
		}
	' "$VALIDATED_DIR/deploy-manifest.tsv" >"$VALIDATED_RECORDS" || \
		fail "$VALIDATED_PURPOSE manifest is malformed: $VALIDATED_ID"
	if [ "$(awk -F '\t' '$1 == "artifact" {count++} END {print count + 0}' \
		"$VALIDATED_RECORDS")" -eq 2 ]; then
		VALIDATED_DEVICE_PATH=$(awk -F '\t' '$1 == "artifact" && $2 == "device-contract" {print $3}' \
			"$VALIDATED_RECORDS")
		VALIDATED_DEVICE_SHA=$(awk -F '\t' '$1 == "artifact" && $2 == "device-contract" {print $4}' \
			"$VALIDATED_RECORDS")
		VALIDATED_CATALOG_PATH=$(awk -F '\t' '$1 == "artifact" && $2 == "catalog" {print $3}' \
			"$VALIDATED_RECORDS")
		[ "$VALIDATED_DEVICE_PATH" = bird/bird-device-contract.tsv ] && \
			[ "$VALIDATED_CATALOG_PATH" = launcher/catalog.generated.h ] || \
			fail "$VALIDATED_PURPOSE artifact paths changed: $VALIDATED_ID"
		awk -F '\t' -v path="$VALIDATED_DEVICE_PATH" -v digest="$VALIDATED_DEVICE_SHA" \
			'$1 == "file" && $2 == path && $5 == digest {found++} END {exit found != 1}' \
			"$VALIDATED_RECORDS" || \
			fail "$VALIDATED_PURPOSE device-contract artifact changed: $VALIDATED_ID"
	fi
	awk -F '\t' '$1 == "file" || $1 == "dir" {print $2}' "$VALIDATED_RECORDS" | \
		LC_ALL=C sort | uniq -d >"$VALIDATED_DUPLICATES"
	[ ! -s "$VALIDATED_DUPLICATES" ] || \
		fail "$VALIDATED_PURPOSE manifest has duplicate paths: $VALIDATED_ID"
	find "$VALIDATED_DIR" -mindepth 1 ! -type f ! -type d -print | grep -q . && \
		fail "$VALIDATED_PURPOSE contains a symlink or special node: $VALIDATED_ID"
	{
		printf '%s\n' .complete deploy-manifest.tsv
		awk -F '\t' '$1 == "file" {print $2}' "$VALIDATED_RECORDS"
	} | LC_ALL=C sort >"$VALIDATED_EXPECTED_FILES"
	find "$VALIDATED_DIR" -type f -print | while IFS= read -r VALIDATED_FILE; do
		printf '%s\n' "${VALIDATED_FILE#"$VALIDATED_DIR"/}"
	done | LC_ALL=C sort >"$VALIDATED_ACTUAL_FILES"
	cmp "$VALIDATED_EXPECTED_FILES" "$VALIDATED_ACTUAL_FILES" >/dev/null || \
		fail "$VALIDATED_PURPOSE file set differs from its manifest: $VALIDATED_ID"
	awk -F '\t' '$1 == "dir" {print $2}' "$VALIDATED_RECORDS" | \
		LC_ALL=C sort >"$VALIDATED_EXPECTED_DIRS"
	find "$VALIDATED_DIR" -mindepth 1 -type d -empty -print | while IFS= read -r VALIDATED_DIRECTORY; do
		printf '%s\n' "${VALIDATED_DIRECTORY#"$VALIDATED_DIR"/}"
	done | LC_ALL=C sort >"$VALIDATED_ACTUAL_DIRS"
	cmp "$VALIDATED_EXPECTED_DIRS" "$VALIDATED_ACTUAL_DIRS" >/dev/null || \
		fail "$VALIDATED_PURPOSE empty-directory set differs from its manifest: $VALIDATED_ID"
	VALIDATED_TAB=$(printf '\t')
	while IFS="$VALIDATED_TAB" read -r KIND RELATIVE MODE_VALUE BYTES_VALUE HASH_VALUE; do
		case "$KIND" in
			dir)
				[ -d "$VALIDATED_DIR/$RELATIVE" ] && [ ! -L "$VALIDATED_DIR/$RELATIVE" ] || \
					fail "$VALIDATED_PURPOSE directory is missing or unsafe: $VALIDATED_ID/$RELATIVE"
				verify_installed_mode "$VALIDATED_DIR/$RELATIVE" "$MODE_VALUE" || \
					fail "$VALIDATED_PURPOSE directory capabilities changed: $VALIDATED_ID/$RELATIVE"
				;;
			file)
				is_regular_file "$VALIDATED_DIR/$RELATIVE" || \
					fail "$VALIDATED_PURPOSE file is missing or unsafe: $VALIDATED_ID/$RELATIVE"
				verify_installed_mode "$VALIDATED_DIR/$RELATIVE" "$MODE_VALUE" || \
					fail "$VALIDATED_PURPOSE capabilities changed: $VALIDATED_ID/$RELATIVE"
				[ "$(file_bytes "$VALIDATED_DIR/$RELATIVE")" = "$BYTES_VALUE" ] || \
					fail "$VALIDATED_PURPOSE size changed: $VALIDATED_ID/$RELATIVE"
				[ "$(sha256 "$VALIDATED_DIR/$RELATIVE")" = "$HASH_VALUE" ] || \
					fail "$VALIDATED_PURPOSE digest changed: $VALIDATED_ID/$RELATIVE"
				;;
		esac
	done <"$VALIDATED_RECORDS"
}

selector_release_id() {
	awk '
		$1 == "APPEND" {
			for (field = 2; field <= NF; field++)
				if ($field ~ /^bird_release=/) {
					value = $field
					sub(/^bird_release=/, "", value)
					print value
					found++
				}
		}
		END {if (found != 1) exit 1}
	' "$1"
}

read_active_selector() {
	ACTIVE_SELECTOR=$BIRD/extlinux/extlinux.conf
	is_regular_file "$ACTIVE_SELECTOR" || fail 'active extlinux selector is missing or unsafe'
	ACTIVE_SELECTOR_SHA=$(sha256 "$ACTIVE_SELECTOR")
	ACTIVE_SELECTOR_KIND=release
	ACTIVE_RELEASE_ID=
	ACTIVE_RELEASE_ID=$(selector_release_id "$ACTIVE_SELECTOR") || \
		fail 'active selector does not contain exactly one Bird release ID'
	case "$ACTIVE_RELEASE_ID" in
		''|[![:alnum:]]*|*[![:alnum:]._-]*) fail 'active selector contains an unsafe release ID' ;;
	esac
}

prepare_versioned_build_source() {
	if [ -e "$BIRD/KERNEL" ] || [ -L "$BIRD/KERNEL" ]; then
		is_regular_file "$BIRD/KERNEL" || \
			fail 'legacy top-level KERNEL is a symlink or special node'
		return 0
	fi
	read_active_selector
	IMMUTABLE_SOURCE_SELECTOR=$ACTIVE_SELECTOR
	IMMUTABLE_SOURCE_ID=$ACTIVE_RELEASE_ID
	IMMUTABLE_SOURCE_PURPOSE='active immutable build source'
	IMMUTABLE_SOURCE_SELECTOR_PURPOSE='active selector'
	ACTIVE_SOURCE=$BIRD/bird-releases/$IMMUTABLE_SOURCE_ID
	validate_completed_release "$ACTIVE_SOURCE" "$IMMUTABLE_SOURCE_ID" \
		"$IMMUTABLE_SOURCE_PURPOSE"
	PINNED_IMMUTABLE_SOURCE_ID=$IMMUTABLE_SOURCE_ID
	ACTIVE_KERNEL_RECORD=$RUN_TEMP/active-kernel-record
	awk -F '\t' '
		$1 == "file" && $2 == "KERNEL" {
			print $4 "\t" $5
			found++
		}
		END {if (found != 1) exit 1}
	' "$VALIDATED_RECORDS" >"$ACTIVE_KERNEL_RECORD" || \
		fail "$IMMUTABLE_SOURCE_PURPOSE manifest has no unique valid KERNEL record"
	ACTIVE_KERNEL_BYTES=$(awk -F '\t' '{print $1}' "$ACTIVE_KERNEL_RECORD")
	ACTIVE_KERNEL_SHA=$(awk -F '\t' '{print $2}' "$ACTIVE_KERNEL_RECORD")
	is_regular_file "$ACTIVE_SOURCE/extlinux/extlinux.conf" || \
		fail "$IMMUTABLE_SOURCE_PURPOSE selector is missing or unsafe"
	IMMUTABLE_SELECTOR_RELEASE_ID=$(selector_release_id \
		"$ACTIVE_SOURCE/extlinux/extlinux.conf") || \
		fail "$IMMUTABLE_SOURCE_PURPOSE selector does not contain exactly one Bird release ID"
	[ "$IMMUTABLE_SELECTOR_RELEASE_ID" = "$IMMUTABLE_SOURCE_ID" ] || \
		fail "$IMMUTABLE_SOURCE_PURPOSE selector release ID does not match its immutable directory"
	[ "$(sha256 "$IMMUTABLE_SOURCE_SELECTOR")" = \
		"$(sha256 "$ACTIVE_SOURCE/extlinux/extlinux.conf")" ] || \
		fail "$IMMUTABLE_SOURCE_SELECTOR_PURPOSE differs from its verified immutable release selector"
	[ "$(grep -Fxc "  LINUX /bird-releases/$IMMUTABLE_SOURCE_ID/KERNEL" \
		"$IMMUTABLE_SOURCE_SELECTOR")" -eq 1 ] || \
		fail "$IMMUTABLE_SOURCE_SELECTOR_PURPOSE does not reference its immutable KERNEL exactly once"
	is_regular_file "$ACTIVE_SOURCE/dtb.img" || \
		fail 'versioned build source requires its manifest-verified DTB'

	SOURCE=$RUN_TEMP/pinned-card-source
	mkdir -p "$SOURCE"
	COPYFILE_DISABLE=1 cp -p "$ACTIVE_SOURCE/KERNEL" "$SOURCE/KERNEL"
	COPYFILE_DISABLE=1 cp -p "$ACTIVE_SOURCE/dtb.img" "$SOURCE/dtb.img"
	[ "$(sha256 "$SOURCE/KERNEL")" = "$ACTIVE_KERNEL_SHA" ] && \
	[ "$(sha256 "$SOURCE/dtb.img")" = "$(sha256 "$ACTIVE_SOURCE/dtb.img")" ] || \
		fail 'versioned host build-source snapshot verification failed'
}

prepare_versioned_build_source

if [ "$KERNEL_AUTHORITY" != stock ]; then
	for SOURCE_PARITY_INPUT in \
		"$SOURCE_KERNEL_BUILD/Image" \
		"$SOURCE_KERNEL_PAYLOAD" \
		"$SOURCE_KERNEL_BUILD/sun50i-h700-anbernic-rg34xx-sp.dtb" \
		"$SOURCE_KERNEL_BUILD/modules.tar.xz" \
		"$SOURCE_KERNEL_BUILD/rocknix-singleadc-joypad.ko" \
		"$SOURCE_KERNEL_BUILD/parity.tsv" \
		"$SOURCE_KERNEL_SYSTEM" "$SOURCE_KERNEL_AUTHORITY_RECORD"; do
		is_regular_file "$SOURCE_PARITY_INPUT" || \
			fail "source-kernel input missing or unsafe: $SOURCE_PARITY_INPUT"
	done
	case "$KERNEL_AUTHORITY" in
	source-parity)
		EXPECTED_SOURCE_KERNEL_SHA=1d1e950eac7af564dfb3d439d3029989ea0e1ff5bd036cc19bda820f4d1cc9cd
		EXPECTED_SOURCE_MODULES_SHA=7267770aecb39069bbd5275b4538a9bb666e906cdabc844b275652603e1ad52e
		EXPECTED_SOURCE_PARITY_SHA=897fffdba2f20fd62cd55175884132a7e47fe662f6d59964622989f3c71a19ed
		EXPECTED_SOURCE_SYSTEM_SHA=bf8cb00a57f749483a986183e5aca396bf1f3f196996b20e703b43f26214ad11
		EXPECTED_SOURCE_AUTHORITY_SHA=74ea672573dd80f368314bdef6a9481b2af9cf54b321cfd6e165179cc3185ffc
		;;
	source-builtin-input)
		EXPECTED_SOURCE_KERNEL_SHA=2c5c2a69b4ce4d16ec9a77e7fca4c14e2b8f537d7877cc8d52315277a0b69404
		EXPECTED_SOURCE_MODULES_SHA=56bd291210ef47a020c3c6dfcac6f6987135ef4bf20f22435138acafb6107211
		EXPECTED_SOURCE_PARITY_SHA=015a0ab31cf82079972d276275034f8a7953cb306ed961511ac5b7daad4ac179
		EXPECTED_SOURCE_SYSTEM_SHA=57210b5cb6072bf1e2b81dea31df76f9b5d4aab5534d7d3b668fdfdc51a1c527
		EXPECTED_SOURCE_AUTHORITY_SHA=53116bb1df39e4520699dc481f4155a2a93bcedb81695fa1c15b2bd562bd94cd
		;;
	source-single-gpio-read)
		EXPECTED_SOURCE_KERNEL_SHA=1dfa7e4a740a79ee9814c2da54080a0d843e874f5ec92fbd1fb91e58a9c8c2b5
		EXPECTED_SOURCE_MODULES_SHA=56bd291210ef47a020c3c6dfcac6f6987135ef4bf20f22435138acafb6107211
		EXPECTED_SOURCE_PARITY_SHA=9c8c899d1561ab12b423c34fe3dccdb2173964113188b3158425c5ca2a6d9932
		EXPECTED_SOURCE_SYSTEM_SHA=57210b5cb6072bf1e2b81dea31df76f9b5d4aab5534d7d3b668fdfdc51a1c527
		EXPECTED_SOURCE_AUTHORITY_SHA=d4d3977294603f15085e38972370795d7932cb503110f7eddec104dfecab0194
		;;
	source-single-input-sync)
		EXPECTED_SOURCE_KERNEL_SHA=7c37f4faad42326926740286f1b9d8d2beb461d31751d81103c25d9baa44bde3
		EXPECTED_SOURCE_MODULES_SHA=56bd291210ef47a020c3c6dfcac6f6987135ef4bf20f22435138acafb6107211
		EXPECTED_SOURCE_PARITY_SHA=9465c8ff031d14effae2a1cbc6ed72dddd24f95d7a48d17c4b1db6fe59b0b2aa
		EXPECTED_SOURCE_SYSTEM_SHA=57210b5cb6072bf1e2b81dea31df76f9b5d4aab5534d7d3b668fdfdc51a1c527
		EXPECTED_SOURCE_AUTHORITY_SHA=afe2693b5a632170b638eda70f27a77198ca89e2b792dfa5628f5057a8f49fa8
		;;
	source-changed-input-sync)
		EXPECTED_SOURCE_KERNEL_SHA=856fb5b4ac23b28cd7fdaebb39278d47824d087e40450f8af5014c8d1249eb6a
		EXPECTED_SOURCE_MODULES_SHA=56bd291210ef47a020c3c6dfcac6f6987135ef4bf20f22435138acafb6107211
		EXPECTED_SOURCE_PARITY_SHA=8c434778fe4a81e0268800230759ddcbe134217404a35a6f68ff101ebdaff536
		EXPECTED_SOURCE_SYSTEM_SHA=57210b5cb6072bf1e2b81dea31df76f9b5d4aab5534d7d3b668fdfdc51a1c527
		EXPECTED_SOURCE_AUTHORITY_SHA=8ae897ae79536313d1501c72ccb2c6dd9472963e7c2d0bfd6c1dbf54a51831c6
		;;
	source-fixed-gpio-fastpath)
		EXPECTED_SOURCE_KERNEL_SHA=e112527fac5790b4dfee8a5381224ff15dffc84a16e64202c46c981335b3b549
		EXPECTED_SOURCE_MODULES_SHA=56bd291210ef47a020c3c6dfcac6f6987135ef4bf20f22435138acafb6107211
		EXPECTED_SOURCE_PARITY_SHA=be2ab8c1f0e12d8f3350e6e8d08528ee675d45652f8bfcfc3499d30579fa77ad
		EXPECTED_SOURCE_SYSTEM_SHA=57210b5cb6072bf1e2b81dea31df76f9b5d4aab5534d7d3b668fdfdc51a1c527
		EXPECTED_SOURCE_AUTHORITY_SHA=c727c365941c0957d9d56994d1cc9a5c0d16dccf315ff1d664944bac732b4820
		;;
	source-irq-buttons)
		EXPECTED_SOURCE_KERNEL_SHA=cad7ad8437d0a7de0d819846b12fdf83078f5878313704d0de79274431ec9d64
		EXPECTED_SOURCE_MODULES_SHA=56bd291210ef47a020c3c6dfcac6f6987135ef4bf20f22435138acafb6107211
		EXPECTED_SOURCE_PARITY_SHA=c32fcf16af9149c1cdbcbaed0181ce196c23444d5eda6e13fae767802da5a0aa
		EXPECTED_SOURCE_SYSTEM_SHA=57210b5cb6072bf1e2b81dea31df76f9b5d4aab5534d7d3b668fdfdc51a1c527
		EXPECTED_SOURCE_AUTHORITY_SHA=0020d161b5a2be0d8393267c3eb96794a0c2d9f82e8df5e097932216fad9e45d
		;;
	source-irq-buttons-lz4)
		EXPECTED_SOURCE_KERNEL_SHA=cad7ad8437d0a7de0d819846b12fdf83078f5878313704d0de79274431ec9d64
		EXPECTED_SOURCE_MODULES_SHA=56bd291210ef47a020c3c6dfcac6f6987135ef4bf20f22435138acafb6107211
		EXPECTED_SOURCE_PARITY_SHA=c32fcf16af9149c1cdbcbaed0181ce196c23444d5eda6e13fae767802da5a0aa
		EXPECTED_SOURCE_SYSTEM_SHA=57210b5cb6072bf1e2b81dea31df76f9b5d4aab5534d7d3b668fdfdc51a1c527
		EXPECTED_SOURCE_AUTHORITY_SHA=250be0f922339e423cc7e100d785747b16686873a5bea357b69825dc29434b3c
		;;
	esac
	EXPECTED_SOURCE_PAYLOAD_SHA=$EXPECTED_SOURCE_KERNEL_SHA
	if [ "$KERNEL_AUTHORITY" = source-irq-buttons-lz4 ]; then
		EXPECTED_SOURCE_PAYLOAD_SHA=a7321d2a79b18e81f114aefd9bb7509ba70d5e56b562a345ea5ca66dbf11262a
	fi
	[ "$(sha256 "$SOURCE_KERNEL_BUILD/Image")" = "$EXPECTED_SOURCE_KERNEL_SHA" ] && \
	[ "$(sha256 "$SOURCE_KERNEL_PAYLOAD")" = "$EXPECTED_SOURCE_PAYLOAD_SHA" ] && \
	[ "$(sha256 "$SOURCE_KERNEL_BUILD/sun50i-h700-anbernic-rg34xx-sp.dtb")" = \
		f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31 ] && \
	[ "$(sha256 "$SOURCE_KERNEL_BUILD/modules.tar.xz")" = "$EXPECTED_SOURCE_MODULES_SHA" ] && \
	[ "$(sha256 "$SOURCE_KERNEL_BUILD/rocknix-singleadc-joypad.ko")" = \
		fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05 ] && \
	[ "$(sha256 "$SOURCE_KERNEL_BUILD/parity.tsv")" = "$EXPECTED_SOURCE_PARITY_SHA" ] && \
	[ "$(sha256 "$SOURCE_KERNEL_SYSTEM")" = "$EXPECTED_SOURCE_SYSTEM_SHA" ] && \
	[ "$(sha256 "$SOURCE_KERNEL_AUTHORITY_RECORD")" = "$EXPECTED_SOURCE_AUTHORITY_SHA" ] || \
		fail 'source-kernel input digest changed'
	SOURCE=$RUN_TEMP/source-kernel-input
	mkdir "$SOURCE"
	COPYFILE_DISABLE=1 cp -p "$SOURCE_KERNEL_PAYLOAD" "$SOURCE/KERNEL"
	COPYFILE_DISABLE=1 cp -p \
		"$SOURCE_KERNEL_BUILD/sun50i-h700-anbernic-rg34xx-sp.dtb" \
		"$SOURCE/dtb.img"
	JOYPAD=$SOURCE_KERNEL_BUILD/rocknix-singleadc-joypad.ko
	SYSTEM_SOURCE=$SOURCE_KERNEL_SYSTEM
	BUILD_SOURCE=$SOURCE
fi

# A caller may supply a newly generated hermetic SYSTEM. Ordinary later builds
# reuse the selected release's version-scoped canonical SYSTEM. The legacy muOS
# path exists only for the one-time Stage 6 transition.
if [ -z "$SYSTEM_SOURCE" ]; then
	read_active_selector
	ACTIVE_SYSTEM_SOURCE=$DATA/Bird/runtime/$ACTIVE_RELEASE_ID/ROCKNIX-SYSTEM
	LEGACY_SYSTEM_SOURCE=$DATA/MUOS/runtime/ROCKNIX-SYSTEM
	if is_regular_file "$ACTIVE_SYSTEM_SOURCE"; then
		SYSTEM_SOURCE=$ACTIVE_SYSTEM_SOURCE
	elif is_regular_file "$LEGACY_SYSTEM_SOURCE"; then
		SYSTEM_SOURCE=$LEGACY_SYSTEM_SOURCE
	else
		fail 'selected release has no canonical or legacy SYSTEM build input'
	fi
fi

for PINNED_FILE in "$SOURCE/KERNEL" "$SOURCE/dtb.img" "$SYSTEM_SOURCE" \
	"$STORAGE_SOURCE" "$SYSTEM_TREE/usr/bin/autostart" "$OFFICIAL_INIT" \
	"$JOYPAD" "$INIT_BUSYBOX" "$PORTMASTER_ARCHIVE"; do
	is_regular_file "$PINNED_FILE" || fail "pinned build input missing or unsafe: $PINNED_FILE"
done
BUILD_SOURCE=$SOURCE
PINNED_SOURCE_KERNEL_SHA=$(sha256 "$SOURCE/KERNEL")
PINNED_SOURCE_DTB_SHA=$(sha256 "$SOURCE/dtb.img")

catalog_koreader_category_count() {
	awk '
		$0 == "#define CATALOG_LAUNCH_KOREADER 7" {defines++; next}
		$0 == "static const u8 catalog_media_category_launch_kinds[CATALOG_MEDIA_CATEGORY_COUNT] = {" {
			if (inside) exit 1
			arrays++
			inside=1
			next
		}
		inside && $0 == "};" {inside=0; closed++; next}
		inside && $0 == "    CATALOG_LAUNCH_KOREADER," {count++}
		END {
			if (defines != 1 || arrays != 1 || closed != 1 || inside) exit 1
			print count + 0
		}
	' "$1"
}

contract_literal() {
	CONTRACT_NAME=$1
	awk -v name="$CONTRACT_NAME" '
		index($0, name "=") == 1 {
			print substr($0, length(name) + 2)
			found++
		}
		END {if (found != 1) exit 1}
	' "$KOREADER_CONTRACT"
}

require_plain_directory() {
	[ -d "$1" ] && [ ! -L "$1" ] || \
		fail "KOReader directory is missing or unsafe: $1"
}

preflight_koreader() {
	is_regular_file "$KOREADER_CATALOG_HEADER" || \
		fail 'generated launcher catalog is missing or unsafe for KOReader preflight'
	is_regular_file "$KOREADER_CONTRACT" || \
		fail 'content runner is missing or unsafe for KOReader preflight'
	KOREADER_CATEGORY_COUNT=$(catalog_koreader_category_count \
		"$KOREADER_CATALOG_HEADER") || \
		fail 'generated catalog has a malformed KOReader launch-kind contract'
	case "$KOREADER_CATEGORY_COUNT" in
		''|*[!0-9]*) fail 'generated catalog returned an invalid KOReader category count' ;;
	esac
	[ "$KOREADER_CATEGORY_COUNT" -gt 0 ] || return 0

	[ "$(grep -Fxc 'KOREADER_PORT_SOURCE=${BIRD_KOREADER_PORT_SOURCE:-/storage/roms/ports/KOReader.sh}' \
		"$KOREADER_CONTRACT")" -eq 1 ] || \
		fail 'KOReader runtime source path contract changed'
	KOREADER_SOURCE_SHA=$(contract_literal KOREADER_PORT_SOURCE_SHA) || \
		fail 'KOReader source digest contract is missing or duplicated'
	KOREADER_ARCHIVE_SHA=$(contract_literal KOREADER_ARCHIVE_SHA) || \
		fail 'KOReader archive digest contract is missing or duplicated'
	KOREADER_ARCHIVE_BYTES=$(contract_literal KOREADER_ARCHIVE_BYTES) || \
		fail 'KOReader archive-size contract is missing or duplicated'
	KOREADER_EXPANDED_BYTES=$(contract_literal KOREADER_EXPANDED_BYTES) || \
		fail 'KOReader extraction-size contract is missing or duplicated'
	KOREADER_ARCHIVE_ENTRIES=$(contract_literal KOREADER_ARCHIVE_ENTRIES) || \
		fail 'KOReader archive-entry contract is missing or duplicated'
	if [ "$HOST_TEST_MODE" -eq 1 ]; then
		[ -z "${BIRD_TEST_KOREADER_SOURCE_SHA:-}" ] || \
			KOREADER_SOURCE_SHA=$BIRD_TEST_KOREADER_SOURCE_SHA
		[ -z "${BIRD_TEST_KOREADER_ARCHIVE_SHA:-}" ] || \
			KOREADER_ARCHIVE_SHA=$BIRD_TEST_KOREADER_ARCHIVE_SHA
		[ -z "${BIRD_TEST_KOREADER_ARCHIVE_BYTES:-}" ] || \
			KOREADER_ARCHIVE_BYTES=$BIRD_TEST_KOREADER_ARCHIVE_BYTES
		[ -z "${BIRD_TEST_KOREADER_EXPANDED_BYTES:-}" ] || \
			KOREADER_EXPANDED_BYTES=$BIRD_TEST_KOREADER_EXPANDED_BYTES
		[ -z "${BIRD_TEST_KOREADER_ARCHIVE_ENTRIES:-}" ] || \
			KOREADER_ARCHIVE_ENTRIES=$BIRD_TEST_KOREADER_ARCHIVE_ENTRIES
	fi
	case "$KOREADER_SOURCE_SHA" in
		''|*[!0-9a-f]*) fail 'KOReader source digest contract is malformed' ;;
	esac
	case "$KOREADER_ARCHIVE_SHA" in
		''|*[!0-9a-f]*) fail 'KOReader archive digest contract is malformed' ;;
	esac
	[ "${#KOREADER_SOURCE_SHA}" -eq 64 ] && \
	[ "${#KOREADER_ARCHIVE_SHA}" -eq 64 ] || \
		fail 'KOReader digest contract has the wrong length'
	for KOREADER_NUMBER in "$KOREADER_ARCHIVE_BYTES" "$KOREADER_EXPANDED_BYTES" \
		"$KOREADER_ARCHIVE_ENTRIES"; do
		case "$KOREADER_NUMBER" in
			''|*[!0-9]*) fail 'KOReader archive budget contract is malformed' ;;
		esac
	done

	KOREADER_PORTS=$DATA/ROMS/Ports
	KOREADER_SOURCE=$KOREADER_PORTS/KOReader.sh
	KOREADER_ARCHIVE_ROOT=$KOREADER_PORTS/koreader
	KOREADER_ARCHIVE=$KOREADER_ARCHIVE_ROOT/koreader.zip
	for KOREADER_DIR in "$DATA/ROMS" "$KOREADER_PORTS" "$KOREADER_ARCHIVE_ROOT"; do
		require_plain_directory "$KOREADER_DIR"
	done
	is_regular_file "$KOREADER_SOURCE" || \
		fail 'cataloged KOReader source launcher is missing or unsafe on BIRD-DATA'
	is_regular_file "$KOREADER_ARCHIVE" || \
		fail 'cataloged KOReader archive is missing or unsafe on BIRD-DATA'
	[ "$(file_bytes "$KOREADER_SOURCE")" -gt 0 ] || \
		fail 'cataloged KOReader source launcher is empty'
	[ "$(sha256 "$KOREADER_SOURCE")" = "$KOREADER_SOURCE_SHA" ] || \
		fail 'cataloged KOReader source launcher digest changed'
	[ "$(file_bytes "$KOREADER_ARCHIVE")" = "$KOREADER_ARCHIVE_BYTES" ] || \
		fail 'cataloged KOReader archive size changed'
	[ "$(sha256 "$KOREADER_ARCHIVE")" = "$KOREADER_ARCHIVE_SHA" ] || \
		fail 'cataloged KOReader archive digest changed'
	unzip -tq "$KOREADER_ARCHIVE" >/dev/null || \
		fail 'cataloged KOReader archive failed integrity verification'
	KOREADER_ARCHIVE_PATHS=$RUN_TEMP/koreader-archive-paths
	unzip -Z -1 "$KOREADER_ARCHIVE" >"$KOREADER_ARCHIVE_PATHS" || \
		fail 'cataloged KOReader archive inventory failed'
	awk '
		$0 == "" || substr($0, 1, 1) == "/" || index($0, "\\") {exit 1}
		{
			parts=split($0, component, "/")
			for (i=1; i<=parts; i++)
				if (component[i] == "." || component[i] == "..") exit 1
		}
	' "$KOREADER_ARCHIVE_PATHS" || \
		fail 'cataloged KOReader archive contains an unsafe path'
	KOREADER_LIST_SUMMARY=$RUN_TEMP/koreader-list-summary
	unzip -l "$KOREADER_ARCHIVE" | awk 'END {print $1 "\t" $2 "\t" $3}' \
		>"$KOREADER_LIST_SUMMARY" || \
		fail 'cataloged KOReader archive size inventory failed'
	KOREADER_LIST_BYTES=$(awk -F '\t' '{print $1}' "$KOREADER_LIST_SUMMARY")
	KOREADER_LIST_ENTRIES=$(awk -F '\t' '{print $2}' "$KOREADER_LIST_SUMMARY")
	KOREADER_LIST_LABEL=$(awk -F '\t' '{print $3}' "$KOREADER_LIST_SUMMARY")
	case "$KOREADER_LIST_LABEL" in file|files) ;; *) KOREADER_LIST_LABEL=invalid ;; esac
	[ "$KOREADER_LIST_LABEL" != invalid ] && \
	[ "$KOREADER_LIST_BYTES" = "$KOREADER_EXPANDED_BYTES" ] && \
	[ "$KOREADER_LIST_ENTRIES" = "$KOREADER_ARCHIVE_ENTRIES" ] || \
		fail 'cataloged KOReader archive differs from its expanded-size budget'

	KOREADER_COMPLETE=1
	KOREADER_STATE_ROOT=$DATA/.config/bird/koreader-extraction
	for KOREADER_DIR in "$DATA/.config" "$DATA/.config/bird" \
		"$KOREADER_STATE_ROOT" "$KOREADER_ARCHIVE_ROOT/koreader" \
		"$KOREADER_ARCHIVE_ROOT/koreader/frontend" \
		"$KOREADER_ARCHIVE_ROOT/koreader/frontend/apps" \
		"$KOREADER_ARCHIVE_ROOT/koreader/frontend/apps/reader" \
		"$KOREADER_ARCHIVE_ROOT/koreader/libs"; do
		if [ -e "$KOREADER_DIR" ] || [ -L "$KOREADER_DIR" ]; then
			[ -d "$KOREADER_DIR" ] && [ ! -L "$KOREADER_DIR" ] || \
				fail "KOReader extraction directory is unsafe: $KOREADER_DIR"
		else
			KOREADER_COMPLETE=0
		fi
	done
	KOREADER_MARKER=$KOREADER_STATE_ROOT/$KOREADER_ARCHIVE_SHA.complete
	if [ -e "$KOREADER_MARKER" ] || [ -L "$KOREADER_MARKER" ]; then
		is_regular_file "$KOREADER_MARKER" || \
			fail 'KOReader extraction completion marker is unsafe'
		[ "$(file_bytes "$KOREADER_MARKER")" = 65 ] && \
		[ "$(cat "$KOREADER_MARKER")" = "$KOREADER_ARCHIVE_SHA" ] || \
			KOREADER_COMPLETE=0
	else
		KOREADER_COMPLETE=0
	fi
	for KOREADER_SENTINEL in luajit reader.lua \
		frontend/apps/reader/readerui.lua libs/libkoreader-cre.so \
		libs/libwrap-mupdf.so defaults.custom.lua; do
		KOREADER_SENTINEL_PATH=$KOREADER_ARCHIVE_ROOT/koreader/$KOREADER_SENTINEL
		if [ -e "$KOREADER_SENTINEL_PATH" ] || [ -L "$KOREADER_SENTINEL_PATH" ]; then
			is_regular_file "$KOREADER_SENTINEL_PATH" || \
				fail "KOReader extraction sentinel is unsafe: $KOREADER_SENTINEL"
		else
			KOREADER_COMPLETE=0
		fi
	done
	if [ "$KOREADER_COMPLETE" -eq 1 ]; then
		KOREADER_EXTRACTION_STATE=complete
		KOREADER_EXTRACTION_RESERVE=0
	else
		KOREADER_EXTRACTION_STATE=pending
		KOREADER_EXTRACTION_RESERVE=$KOREADER_EXPANDED_BYTES
	fi
}

preflight_koreader

preflight_portmaster_provider() {
	PORTMASTER_PROVIDER=$DATA/ROMS/Ports/PortMaster
	for PORTMASTER_DIR in "$DATA/ROMS" "$DATA/ROMS/Ports" \
		"$PORTMASTER_PROVIDER"; do
		require_plain_directory "$PORTMASTER_DIR"
	done
	is_regular_file "$PORTMASTER_PROVIDER_MANIFEST" || \
		fail 'pinned PortMaster provider manifest is missing or unsafe'
	is_regular_file "$PORTMASTER_PROVIDER_VERIFIER" || \
		fail 'PortMaster provider verifier is missing or unsafe'
	for PORTMASTER_ADAPTER in control.txt oga_controls; do
		PORTMASTER_PATH=$PORTMASTER_PROVIDER/$PORTMASTER_ADAPTER
		is_regular_file "$PORTMASTER_PATH" && [ -s "$PORTMASTER_PATH" ] || \
			fail "PortMaster runtime adapter is incomplete or unsafe: $PORTMASTER_ADAPTER"
	done
	PORTMASTER_PROVIDER_MARKER_VALUE=$(
		# Provider-local cache bytes are inert under run-content.sh's required
		# fresh /run PYTHONPYCACHEPREFIX boundary.
		"$PORTMASTER_PROVIDER_VERIFIER" --allow-isolated-python-cache \
			"$PORTMASTER_PROVIDER_MANIFEST" "$PORTMASTER_PROVIDER"
	) || fail 'installed PortMaster provider is not a pinned complete revision'
	PORTMASTER_PROVIDER_MARKER_STATE=$(portmaster_provider_marker_state)
}

portmaster_provider_marker_state() {
	PORTMASTER_MARKER=$PORTMASTER_PROVIDER/.bird-release-complete
	if [ ! -e "$PORTMASTER_MARKER" ] && [ ! -L "$PORTMASTER_MARKER" ]; then
		printf 'absent:0:-\n'
		return 0
	fi
	is_regular_file "$PORTMASTER_MARKER" || \
		fail 'PortMaster completion marker is a symlink or special node'
	PORTMASTER_MARKER_BYTES=$(file_bytes "$PORTMASTER_MARKER")
	case "$PORTMASTER_MARKER_BYTES" in
		''|*[!0-9]*) fail 'PortMaster completion marker size is malformed' ;;
	esac
	[ "$PORTMASTER_MARKER_BYTES" -le 1024 ] || \
		fail 'PortMaster completion marker is unexpectedly large'
	PORTMASTER_MARKER_SHA=$(sha256 "$PORTMASTER_MARKER")
	if [ "$PORTMASTER_MARKER_BYTES" -eq 0 ]; then
		printf 'legacy:0:%s\n' "$PORTMASTER_MARKER_SHA"
		return 0
	fi
	[ "$(wc -l <"$PORTMASTER_MARKER" | tr -d '[:space:]')" = 1 ] || \
		fail 'PortMaster completion marker must contain one newline-terminated record'
	if grep -Fqx "$PORTMASTER_PROVIDER_MARKER_VALUE" "$PORTMASTER_MARKER"; then
		printf 'exact:%s:%s\n' "$PORTMASTER_MARKER_BYTES" \
			"$PORTMASTER_MARKER_SHA"
	elif grep -Eq '^bird-portmaster-v(1|2):[A-Za-z0-9:._/-]+$' \
		"$PORTMASTER_MARKER"; then
		printf 'legacy:%s:%s\n' "$PORTMASTER_MARKER_BYTES" \
			"$PORTMASTER_MARKER_SHA"
	elif grep -Eq '^bird-portmaster-v3:' "$PORTMASTER_MARKER"; then
		fail 'PortMaster v3 completion marker does not match the pinned revision'
	else
		fail 'PortMaster completion marker has an unrecognized format'
	fi
}

verify_portmaster_provider_unchanged() {
	[ -n "$PORTMASTER_PROVIDER_MARKER_VALUE" ] || \
		fail 'PortMaster provider preflight checkpoint is missing'
	[ "$("$PORTMASTER_PROVIDER_VERIFIER" --allow-isolated-python-cache \
		"$PORTMASTER_PROVIDER_MANIFEST" "$PORTMASTER_PROVIDER")" = \
		"$PORTMASTER_PROVIDER_MARKER_VALUE" ] || \
		fail 'PortMaster provider changed after deployment preflight'
	[ "$(portmaster_provider_marker_state)" = \
		"$PORTMASTER_PROVIDER_MARKER_STATE" ] || \
		fail 'PortMaster completion marker changed after deployment preflight'
}

preflight_portmaster_provider

[ -d "$WORK_ROOT" ] && [ ! -L "$WORK_ROOT" ] || \
	fail "kernel work directory missing or unsafe: $WORK_ROOT"
WORK_ROOT_REAL=$(CDPATH= cd -- "$WORK_ROOT" && pwd -P)
if [ "$HOST_TEST_MODE" -eq 0 ]; then
	[ "$WORK_ROOT_REAL" = "$ROOT_REAL/kernel/work" ] || \
		fail 'generated output root is not the repository kernel/work directory'
fi

card_release_path_occupied() {
	[ -e "$BIRD/bird-releases/$1" ] || [ -L "$BIRD/bird-releases/$1" ]
}

archive_release_id_occupied() {
	[ -n "$GH" ] && [ -x "$GH" ] || return 1
	"$GH" release view "card-$1" --repo "$ARCHIVE_REPOSITORY" \
		--json tagName --jq .tagName >/dev/null 2>&1
}

release_id_occupied() {
	card_release_path_occupied "$1" || archive_release_id_occupied "$1"
}

if [ -e "$BIRD/bird-releases" ] || [ -L "$BIRD/bird-releases" ]; then
	[ -d "$BIRD/bird-releases" ] && [ ! -L "$BIRD/bird-releases" ] || \
		fail 'card release root is a symlink or special node'
fi

RELEASE_ID=$REQUESTED_RELEASE_ID
if release_id_occupied "$RELEASE_ID"; then
	STAMP=$(date -u '+%Y%m%d-%H%M%S')
	if [ "$HOST_TEST_MODE" -eq 1 ] && [ -n "${BIRD_TEST_RELEASE_STAMP:-}" ]; then
		STAMP=$BIRD_TEST_RELEASE_STAMP
	fi
	case "$STAMP" in ''|*[!0-9-]*) fail 'automatic release timestamp is unsafe' ;; esac
	INDEX=0
	while :; do
		if [ "$INDEX" -eq 0 ]; then
			CANDIDATE_ID=$REQUESTED_RELEASE_ID-$STAMP
		else
			CANDIDATE_ID=$REQUESTED_RELEASE_ID-$STAMP-$(printf '%02d' "$INDEX")
		fi
		[ "${#CANDIDATE_ID}" -le 64 ] || \
			fail 'automatic release ID would be longer than 64 bytes; choose a shorter --release-id'
		if ! release_id_occupied "$CANDIDATE_ID"; then
			RELEASE_ID=$CANDIDATE_ID
			break
		fi
		INDEX=$((INDEX + 1))
		[ "$INDEX" -le 99 ] || fail 'could not find an unused automatic release ID'
	done
	printf 'Preferred release ID %s is already occupied on the card or in the archive; selected %s.\n' \
		"$REQUESTED_RELEASE_ID" "$RELEASE_ID"
fi

OUTPUT=$WORK_ROOT_REAL/bird-rocknix-stock-root-$RELEASE_ID
EXPECTED_OUTPUT=$WORK_ROOT_REAL/bird-rocknix-stock-root-$RELEASE_ID
[ "$OUTPUT" = "$EXPECTED_OUTPUT" ] || fail 'generated output path does not match the selected release'
case "$OUTPUT" in
	"$WORK_ROOT_REAL"/bird-rocknix-stock-root-*) ;;
	*) fail "unsafe generated output path: $OUTPUT" ;;
esac

validate_retired_release() {
	RETIRED_DIR=$1
	RETIRED_ID=$2
	ALLOW_ACTIVE_RELEASE=${3:-0}
	if [ "$ACTIVE_SELECTOR_KIND" = release ] && \
		[ "$RETIRED_ID" = "$ACTIVE_RELEASE_ID" ] && \
		[ "$ALLOW_ACTIVE_RELEASE" -ne 1 ]; then
		fail 'refusing to archive or remove the active release'
	fi
	validate_completed_release "$RETIRED_DIR" "$RETIRED_ID" \
		'retirement candidate'
	RETIRED_MANIFEST_SHA=$VALIDATED_MANIFEST_SHA
}

plan_legacy_kernel_retirement() {
	LEGACY_KERNEL_RETIRE=0
	LEGACY_KERNEL_RECLAIM_BYTES=0
	[ "$ACTIVE_SELECTOR_KIND" = release ] || return 0
	if [ ! -e "$BIRD/KERNEL" ] && [ ! -L "$BIRD/KERNEL" ]; then
		return 0
	fi
	is_regular_file "$BIRD/KERNEL" || \
		fail 'legacy top-level KERNEL is a symlink or special node'
	ACTIVE_RELEASE_DIR=$BIRD/bird-releases/$ACTIVE_RELEASE_ID
	validate_retired_release "$ACTIVE_RELEASE_DIR" "$ACTIVE_RELEASE_ID" 1
	[ "$(grep -Fxc "  LINUX /bird-releases/$ACTIVE_RELEASE_ID/KERNEL" \
		"$BIRD/extlinux/extlinux.conf")" -eq 1 ] || \
		fail 'active selector does not reference its immutable release KERNEL exactly once'
	is_regular_file "$ACTIVE_RELEASE_DIR/extlinux/extlinux.conf" || \
		fail 'active immutable release selector is missing or unsafe'
	[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = \
		"$(sha256 "$ACTIVE_RELEASE_DIR/extlinux/extlinux.conf")" ] || \
		fail 'active selector differs from the verified immutable release selector'
	is_regular_file "$ACTIVE_RELEASE_DIR/KERNEL" || \
		fail 'active immutable release KERNEL is missing or unsafe'
	[ "$(file_bytes "$BIRD/KERNEL")" = \
		"$(file_bytes "$ACTIVE_RELEASE_DIR/KERNEL")" ] && \
	[ "$(sha256 "$BIRD/KERNEL")" = \
		"$(sha256 "$ACTIVE_RELEASE_DIR/KERNEL")" ] || \
		fail 'legacy top-level KERNEL is not byte-identical to the active release'
	[ "$(sha256 "$BIRD/KERNEL")" = "$PINNED_SOURCE_KERNEL_SHA" ] || \
		fail 'legacy top-level KERNEL changed after pinned-input preflight'
	LEGACY_KERNEL_RECLAIM_BYTES=$(file_bytes "$BIRD/KERNEL")
	case "$LEGACY_KERNEL_RECLAIM_BYTES" in
		''|*[!0-9]*) fail 'could not size redundant top-level KERNEL' ;;
	esac
	LEGACY_KERNEL_RETIRE=1
}

snapshot_legacy_kernel_build_inputs() {
	[ "$LEGACY_KERNEL_RETIRE" -eq 1 ] || return 0
	plan_legacy_kernel_retirement
	[ "$LEGACY_KERNEL_RETIRE" -eq 1 ] || \
		fail 'planned legacy top-level KERNEL retirement is no longer valid'
	BUILD_SOURCE=$RUN_TEMP/pinned-card-source
	mkdir -p "$BUILD_SOURCE"
	COPYFILE_DISABLE=1 cp -p "$SOURCE/KERNEL" "$BUILD_SOURCE/KERNEL"
	COPYFILE_DISABLE=1 cp -p "$SOURCE/dtb.img" "$BUILD_SOURCE/dtb.img"
	for SNAPSHOT_NAME in KERNEL dtb.img; do
		is_regular_file "$BUILD_SOURCE/$SNAPSHOT_NAME" || \
			fail "host input snapshot is missing or unsafe: $SNAPSHOT_NAME"
	done
	[ "$(sha256 "$BUILD_SOURCE/KERNEL")" = "$PINNED_SOURCE_KERNEL_SHA" ] && \
	[ "$(sha256 "$BUILD_SOURCE/dtb.img")" = "$PINNED_SOURCE_DTB_SHA" ] || \
		fail 'host input snapshot verification failed'
}

retire_legacy_root_kernel() {
	[ "$LEGACY_KERNEL_RETIRE" -eq 1 ] || return 0
	verify_archive_selector_unchanged
	plan_legacy_kernel_retirement
	[ "$LEGACY_KERNEL_RETIRE" -eq 1 ] || \
		fail 'planned legacy top-level KERNEL retirement is no longer valid'
	[ "$BIRD/KERNEL" = /Volumes/BIRD/KERNEL ] || \
		[ "$HOST_TEST_MODE" -eq 1 ] || \
		fail 'refusing unsafe legacy top-level KERNEL path'
	rm -f "$BIRD/KERNEL"
	[ ! -e "$BIRD/KERNEL" ] && [ ! -L "$BIRD/KERNEL" ] || \
		fail 'redundant top-level KERNEL could not be retired'
	sync
	printf 'Reclaimed redundant top-level KERNEL: %s bytes.\n' \
		"$LEGACY_KERNEL_RECLAIM_BYTES"
}

available_bytes() {
	if [ "$HOST_TEST_MODE" -eq 1 ]; then
		case "$1" in
			"$BIRD") [ -z "${BIRD_TEST_BIRD_FREE_BYTES:-}" ] || { printf '%s\n' "$BIRD_TEST_BIRD_FREE_BYTES"; return; } ;;
			"$DATA") [ -z "${BIRD_TEST_DATA_FREE_BYTES:-}" ] || { printf '%s\n' "$BIRD_TEST_DATA_FREE_BYTES"; return; } ;;
			"$WORK_ROOT_REAL") [ -z "${BIRD_TEST_HOST_FREE_BYTES:-}" ] || { printf '%s\n' "$BIRD_TEST_HOST_FREE_BYTES"; return; } ;;
		esac
	fi
	df -Pk "$1" | awk 'END {printf "%.0f\n", $(NF - 2) * 1024}'
}

require_free_space() {
	FREE_PATH=$1
	REQUIRED_BYTES=$2
	DESCRIPTION=$3
	AVAILABLE_BYTES=$(available_bytes "$FREE_PATH")
	case "$AVAILABLE_BYTES" in ''|*[!0-9]*) fail "could not read free space for $DESCRIPTION" ;; esac
	[ "$AVAILABLE_BYTES" -ge "$REQUIRED_BYTES" ] || \
		fail "$DESCRIPTION has insufficient free space: need $REQUIRED_BYTES bytes, have $AVAILABLE_BYTES"
}

HOST_REQUIRED_BYTES=134217728
BIRD_STAGING_REQUIRED_BYTES=$(( $(file_bytes "$SOURCE/KERNEL") + $(file_bytes "$SOURCE/dtb.img") + 4194304 ))
# Production preflight needs only enough space to stage the candidate.  After
# activation the superseded immutable release is archived, verified and
# removed, which makes room for the mutable development copy without retaining
# two production releases on the card.
BIRD_REQUIRED_BYTES=$BIRD_STAGING_REQUIRED_BYTES
DATA_REQUIRED_BYTES=$((16777216 + KOREADER_EXTRACTION_RESERVE + $(file_bytes "$SYSTEM_SOURCE") ))
if ! is_regular_file "$DATA/MUOS/runtime/ROCKNIX-STORAGE"; then
	DATA_REQUIRED_BYTES=$(( $(file_bytes "$STORAGE_SOURCE") + DATA_REQUIRED_BYTES ))
fi

check_archive_repository() {
	[ -n "$GH" ] && [ -x "$GH" ] || \
		fail 'GitHub CLI is required to archive an inactive release: brew install gh'
	"$GH" auth status --hostname github.com >/dev/null 2>&1 || \
		fail 'GitHub CLI is not authenticated for release archival: gh auth login'
	ARCHIVE_VISIBILITY=$("$GH" repo view "$ARCHIVE_REPOSITORY" \
		--json visibility --jq .visibility 2>/dev/null) || \
		fail "private GitHub archive repository is unavailable: $ARCHIVE_REPOSITORY"
	[ "$ARCHIVE_VISIBILITY" = PRIVATE ] || \
		fail "GitHub release archive is not private: $ARCHIVE_REPOSITORY"
	ARCHIVE_IMMUTABLE=$("$GH" api "repos/$ARCHIVE_REPOSITORY/immutable-releases" \
		--jq .enabled 2>/dev/null) || \
		fail "GitHub release immutability is not enabled: $ARCHIVE_REPOSITORY"
	[ "$ARCHIVE_IMMUTABLE" = true ] || \
		fail "GitHub release immutability is not enabled: $ARCHIVE_REPOSITORY"
}

plan_post_activation_rotation() {
	ROTATION_PREVIOUS_SELECTOR=$BIRD/extlinux/extlinux.conf
	is_regular_file "$ROTATION_PREVIOUS_SELECTOR" || \
		fail 'active selector is missing or unsafe before release rotation'
	ROTATION_PREVIOUS_SELECTOR_SHA=$(sha256 "$ROTATION_PREVIOUS_SELECTOR")
	ROTATION_SUPERSEDED_ID=
	ROTATION_SUPERSEDED_DIR=

	# A versioned build source is the immutable runtime superseded by the new
	# canonical release. Legacy top-level layouts have no immutable release to
	# rotate.
	if [ -n "$PINNED_IMMUTABLE_SOURCE_ID" ]; then
		ROTATION_SUPERSEDED_ID=$PINNED_IMMUTABLE_SOURCE_ID
	elif ROTATION_PARSED_ID=$(selector_release_id \
		"$ROTATION_PREVIOUS_SELECTOR" 2>/dev/null); then
		ROTATION_SUPERSEDED_ID=$ROTATION_PARSED_ID
	elif grep -Eq '(^|[[:space:]])bird_release=' \
		"$ROTATION_PREVIOUS_SELECTOR"; then
		fail 'active selector has a malformed release identity before rotation'
	fi

	if [ -n "$ROTATION_SUPERSEDED_ID" ]; then
		case "$ROTATION_SUPERSEDED_ID" in
			''|[![:alnum:]]*|*[![:alnum:]._-]*) \
				fail 'superseded release has an unsafe release ID' ;;
		esac
		[ "$ROTATION_SUPERSEDED_ID" != "$RELEASE_ID" ] || \
			fail 'new release ID unexpectedly matches the superseded release'
		ROTATION_SUPERSEDED_DIR=$BIRD/bird-releases/$ROTATION_SUPERSEDED_ID
		validate_completed_release "$ROTATION_SUPERSEDED_DIR" \
			"$ROTATION_SUPERSEDED_ID" 'superseded release'
		is_regular_file "$ROTATION_SUPERSEDED_DIR/extlinux/extlinux.conf" || \
			fail 'superseded release selector is missing or unsafe'
		[ "$(selector_release_id \
			"$ROTATION_SUPERSEDED_DIR/extlinux/extlinux.conf")" = \
			"$ROTATION_SUPERSEDED_ID" ] || \
			fail 'superseded release selector identity changed'
		check_archive_repository
	fi

}

publish_current_selector_as_previous() {
	EXPECTED_PREVIOUS_SELECTOR_SHA=${1:-}
	CURRENT_SELECTOR=$BIRD/extlinux/extlinux.conf
	PREVIOUS_SELECTOR=$BIRD/extlinux/extlinux.previous.conf
	is_regular_file "$CURRENT_SELECTOR" || \
		fail 'current selector is missing before previous-selector rotation'
	CURRENT_SELECTOR_SHA=$(sha256 "$CURRENT_SELECTOR")
	[ "$CURRENT_SELECTOR_SHA" = "$ARCHIVE_ACTIVE_SELECTOR_SHA" ] || \
		fail 'current selector changed before previous-selector rotation'
	if [ -n "$EXPECTED_PREVIOUS_SELECTOR_SHA" ]; then
		is_regular_file "$PREVIOUS_SELECTOR" && \
			[ "$(sha256 "$PREVIOUS_SELECTOR")" = \
			"$EXPECTED_PREVIOUS_SELECTOR_SHA" ] || \
			fail 'previous selector changed before release rotation'
	fi

	ROTATION_SELECTOR_TEMP=$BIRD/extlinux/.extlinux.previous.conf.rotate-new.$$
	[ ! -e "$ROTATION_SELECTOR_TEMP" ] && \
		[ ! -L "$ROTATION_SELECTOR_TEMP" ] || \
		fail 'previous-selector rotation stage is already occupied'
	COPYFILE_DISABLE=1 cp -f "$CURRENT_SELECTOR" "$ROTATION_SELECTOR_TEMP"
	chmod 0644 "$ROTATION_SELECTOR_TEMP"
	[ "$(sha256 "$ROTATION_SELECTOR_TEMP")" = "$CURRENT_SELECTOR_SHA" ] || \
		fail 'previous-selector rotation copy failed'
	sync
	mv -f "$ROTATION_SELECTOR_TEMP" "$PREVIOUS_SELECTOR"
	ROTATION_SELECTOR_TEMP=
	sync
	is_regular_file "$PREVIOUS_SELECTOR" && \
		[ "$(sha256 "$PREVIOUS_SELECTOR")" = "$CURRENT_SELECTOR_SHA" ] || \
		fail 'previous-selector rotation commit failed'
}

select_retirement_candidates() {
	read_active_selector
	ARCHIVE_ACTIVE_SELECTOR_KIND=$ACTIVE_SELECTOR_KIND
	ARCHIVE_ACTIVE_SELECTOR_SHA=$ACTIVE_SELECTOR_SHA
	if [ "$ACTIVE_SELECTOR_KIND" = release ]; then
		ACTIVE_RELEASE_DIR=$BIRD/bird-releases/$ACTIVE_RELEASE_ID
		[ -d "$ACTIVE_RELEASE_DIR" ] && [ ! -L "$ACTIVE_RELEASE_DIR" ] || \
			fail 'active selector does not name a safe installed release directory'
	fi
	RETIREMENT_CANDIDATES=$RUN_TEMP/retirement-candidates
	RETIREMENT_SELECTED=$RUN_TEMP/retirement-selected
	RETIREMENT_TAB=$(printf '\t')
	find "$BIRD/bird-releases" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print | \
		LC_ALL=C sort >"$RETIREMENT_CANDIDATES"
	: >"$RETIREMENT_SELECTED"
	RETIRED_BYTES=0
	RETIREMENT_EFFECTIVE_BYTES=$BIRD_EFFECTIVE_BYTES
	while IFS= read -r POSSIBLE_DIR; do
		POSSIBLE_ID=${POSSIBLE_DIR##*/}
		if [ "$ACTIVE_SELECTOR_KIND" = release ] && \
			[ "$POSSIBLE_ID" = "$ACTIVE_RELEASE_ID" ]; then
			continue
		fi
		if [ -n "$PINNED_IMMUTABLE_SOURCE_ID" ] && \
			[ "$POSSIBLE_ID" = "$PINNED_IMMUTABLE_SOURCE_ID" ]; then
			continue
		fi
		[ "$POSSIBLE_ID" != "$RELEASE_ID" ] || continue
		validate_retired_release "$POSSIBLE_DIR" "$POSSIBLE_ID"
		POSSIBLE_KIB=$(du -sk "$POSSIBLE_DIR" | awk '{print $1}')
		case "$POSSIBLE_KIB" in
			''|*[!0-9]*) fail 'could not size inactive release candidate' ;;
		esac
		POSSIBLE_BYTES=$((POSSIBLE_KIB * 1024))
		printf '%s\t%s\t%s\n' "$POSSIBLE_ID" "$POSSIBLE_DIR" \
			"$POSSIBLE_BYTES" >>"$RETIREMENT_SELECTED"
		RETIRED_BYTES=$((RETIRED_BYTES + POSSIBLE_BYTES))
		RETIREMENT_EFFECTIVE_BYTES=$((RETIREMENT_EFFECTIVE_BYTES + POSSIBLE_BYTES))
		if [ "$RETIREMENT_EFFECTIVE_BYTES" -ge "$BIRD_REQUIRED_BYTES" ]; then
			break
		fi
	done <"$RETIREMENT_CANDIDATES"
	if [ "$RETIREMENT_EFFECTIVE_BYTES" -lt "$BIRD_REQUIRED_BYTES" ]; then
		plan_legacy_kernel_retirement
		if [ "$LEGACY_KERNEL_RETIRE" -eq 1 ]; then
			RETIREMENT_EFFECTIVE_BYTES=$((RETIREMENT_EFFECTIVE_BYTES + LEGACY_KERNEL_RECLAIM_BYTES))
		fi
	fi
	[ "$RETIREMENT_EFFECTIVE_BYTES" -ge "$BIRD_REQUIRED_BYTES" ] || \
		fail "BIRD has insufficient staging space and verified retirement cannot safely provide it: need $BIRD_REQUIRED_BYTES bytes, have $BIRD_AVAILABLE_BYTES plus $((STALE_RECLAIM_KIB * 1024)) stale bytes, $RETIRED_BYTES inactive release bytes, and $LEGACY_KERNEL_RECLAIM_BYTES redundant root-kernel bytes"
	[ "$RETIRED_BYTES" -eq 0 ] || check_archive_repository
}

verify_archive_selector_unchanged() {
	read_active_selector
	[ "$ACTIVE_SELECTOR_KIND" = "$ARCHIVE_ACTIVE_SELECTOR_KIND" ] && \
		[ "$ACTIVE_SELECTOR_SHA" = "$ARCHIVE_ACTIVE_SELECTOR_SHA" ] || \
		fail 'active selector changed during GitHub archival; inactive release retained'
}

verify_published_archive() {
	VERIFY_TAG=$1
	VERIFY_ARCHIVE_ASSET=$2
	VERIFY_MANIFEST_ASSET=$3
	VERIFY_CHECKSUM_ASSET=$4
	VERIFY_LOCAL_MANIFEST=$5
	VERIFY_LOCAL_ARCHIVE=$6
	VERIFY_ASSETS=$RUN_TEMP/archive-assets
	"$GH" release verify "$VERIFY_TAG" --repo "$ARCHIVE_REPOSITORY" >/dev/null || \
		fail "GitHub release attestation verification failed: $VERIFY_TAG"
	"$GH" release view "$VERIFY_TAG" --repo "$ARCHIVE_REPOSITORY" \
		--json assets --jq '.assets[].name' >"$VERIFY_ASSETS" || \
		fail "could not inspect archived release assets: $VERIFY_TAG"
	for REQUIRED_ASSET in "$VERIFY_ARCHIVE_ASSET" "$VERIFY_MANIFEST_ASSET" \
		"$VERIFY_CHECKSUM_ASSET"; do
		grep -Fqx "$REQUIRED_ASSET" "$VERIFY_ASSETS" || \
			fail "archived release is missing required asset: $REQUIRED_ASSET"
	done
	VERIFY_DOWNLOAD=$RUN_TEMP/archive-download
	mkdir -p "$VERIFY_DOWNLOAD"
	"$GH" release download "$VERIFY_TAG" --repo "$ARCHIVE_REPOSITORY" \
		--pattern "$VERIFY_ARCHIVE_ASSET" --dir "$VERIFY_DOWNLOAD" >/dev/null || \
		fail "could not download archived release for verification: $VERIFY_TAG"
	"$GH" release download "$VERIFY_TAG" --repo "$ARCHIVE_REPOSITORY" \
		--pattern "$VERIFY_MANIFEST_ASSET" --dir "$VERIFY_DOWNLOAD" >/dev/null || \
		fail "could not download archived manifest for verification: $VERIFY_TAG"
	VERIFY_DOWNLOADED_ARCHIVE=$VERIFY_DOWNLOAD/$VERIFY_ARCHIVE_ASSET
	"$GH" release verify-asset "$VERIFY_TAG" "$VERIFY_DOWNLOADED_ARCHIVE" \
		--repo "$ARCHIVE_REPOSITORY" >/dev/null || \
		fail "published archive failed attestation verification: $VERIFY_TAG"
	cmp "$VERIFY_LOCAL_MANIFEST" "$VERIFY_DOWNLOAD/$VERIFY_MANIFEST_ASSET" >/dev/null || \
		fail "published archive manifest differs from the card release: $VERIFY_TAG"
	VERIFY_ARCHIVE_PATHS=$RUN_TEMP/archive-paths
	VERIFY_ARCHIVE_LIST=$RUN_TEMP/archive-list
	tar -tf "$VERIFY_DOWNLOADED_ARCHIVE" >"$VERIFY_ARCHIVE_PATHS" 2>/dev/null || \
		fail "published archive differs from the verified card release: $VERIFY_TAG"
	awk -v release="$RETIRED_ID" '
		$0 == "" || substr($0, 1, 1) == "/" || index($0, "\\") {exit 1}
		{
			path=$0
			sub(/\/$/, "", path)
			parts=split(path, component, "/")
			if (component[1] != release) exit 1
			for (i=1; i<=parts; i++)
				if (component[i] == "" || component[i] == "." || component[i] == "..") exit 1
		}
	' "$VERIFY_ARCHIVE_PATHS" || \
		fail "published archive contains an unsafe path: $VERIFY_TAG"
	tar -tvf "$VERIFY_DOWNLOADED_ARCHIVE" >"$VERIFY_ARCHIVE_LIST" 2>/dev/null || \
		fail "published archive inventory is unreadable: $VERIFY_TAG"
	awk 'substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" {exit 1}' \
		"$VERIFY_ARCHIVE_LIST" || \
		fail "published archive contains a special node: $VERIFY_TAG"
	VERIFY_EXTRACT_ROOT=$RUN_TEMP/archive-extract
	mkdir -p "$VERIFY_EXTRACT_ROOT"
	COPYFILE_DISABLE=1 tar -xf "$VERIFY_DOWNLOADED_ARCHIVE" \
		-C "$VERIFY_EXTRACT_ROOT" || \
		fail "published archive could not be extracted safely: $VERIFY_TAG"
	validate_completed_release "$VERIFY_EXTRACT_ROOT/$RETIRED_ID" "$RETIRED_ID" \
		'published archive' "$VERIFY_EXTRACT_ROOT"
	[ "$VALIDATED_MANIFEST_SHA" = "$RETIRED_MANIFEST_SHA" ] || \
		fail "published archive differs from the verified card release: $VERIFY_TAG"
}

archive_and_remove_retired_release() {
	RETIRED_ID=$1
	RETIRED_DIR=$2
	ROTATE_PREVIOUS_AFTER_ARCHIVE=${3:-0}
	case "$ROTATE_PREVIOUS_AFTER_ARCHIVE" in
		0|1) ;;
		*) fail 'internal previous-selector rotation mode is invalid' ;;
	esac
	verify_archive_selector_unchanged
	validate_retired_release "$RETIRED_DIR" "$RETIRED_ID"
	RETIRED_SYSTEM_ROOT=$DATA/Bird/runtime/$RETIRED_ID
	RETIRED_SYSTEM=$RETIRED_SYSTEM_ROOT/ROCKNIX-SYSTEM
	RETIRED_SYSTEM_SIDECAR=$RETIRED_SYSTEM_ROOT/._ROCKNIX-SYSTEM
	RETIRED_SYSTEM_PRESENT=0
	if [ -e "$RETIRED_SYSTEM_ROOT" ] || [ -L "$RETIRED_SYSTEM_ROOT" ]; then
		[ -d "$RETIRED_SYSTEM_ROOT" ] && [ ! -L "$RETIRED_SYSTEM_ROOT" ] || \
			fail "retired release SYSTEM directory is unsafe: $RETIRED_ID"
		if find "$RETIRED_SYSTEM_ROOT" -mindepth 1 -maxdepth 1 \
			! -path "$RETIRED_SYSTEM" ! -path "$RETIRED_SYSTEM_SIDECAR" \
			-print -quit | grep -q .; then
			fail "retired release SYSTEM directory has an unexpected inventory: $RETIRED_ID"
		fi
		is_regular_file "$RETIRED_SYSTEM" || \
			fail "retired release SYSTEM is missing or unsafe: $RETIRED_ID"
		if [ -e "$RETIRED_SYSTEM_SIDECAR" ] || [ -L "$RETIRED_SYSTEM_SIDECAR" ]; then
			is_regular_file "$RETIRED_SYSTEM_SIDECAR" || \
				fail "retired release SYSTEM AppleDouble is unsafe: $RETIRED_ID"
		fi
		RETIRED_SYSTEM_BYTES=$(awk -F '\t' '
			$1 == "input" && $2 == "ROCKNIX-SYSTEM" {print $4; found++}
			END {if (found != 1) exit 1}
		' "$RETIRED_DIR/deploy-manifest.tsv") || \
			fail "retired release SYSTEM size authority is missing: $RETIRED_ID"
		RETIRED_SYSTEM_SHA=$(awk -F '\t' '
			$1 == "input" && $2 == "ROCKNIX-SYSTEM" {print $5; found++}
			END {if (found != 1) exit 1}
		' "$RETIRED_DIR/deploy-manifest.tsv") || \
			fail "retired release SYSTEM digest authority is missing: $RETIRED_ID"
		[ "$(file_bytes "$RETIRED_SYSTEM")" = "$RETIRED_SYSTEM_BYTES" ] && \
		[ "$(sha256 "$RETIRED_SYSTEM")" = "$RETIRED_SYSTEM_SHA" ] || \
			fail "retired release SYSTEM differs from its manifest: $RETIRED_ID"
		RETIRED_SYSTEM_PRESENT=1
	fi
	ARCHIVE_TAG=card-$RETIRED_ID
	ARCHIVE_ASSET=birdOS-RG34XX-SP-$RETIRED_ID.tar
	ARCHIVE_MANIFEST_ASSET=$RETIRED_ID.deploy-manifest.tsv
	ARCHIVE_CHECKSUM_ASSET=$RETIRED_ID.SHA256SUMS
	ARCHIVE_FILE=$RUN_TEMP/$ARCHIVE_ASSET
	ARCHIVE_MANIFEST=$RUN_TEMP/$ARCHIVE_MANIFEST_ASSET
	ARCHIVE_CHECKSUM=$RUN_TEMP/$ARCHIVE_CHECKSUM_ASSET
	ARCHIVE_NOTES=$RUN_TEMP/archive-notes
	cp "$RETIRED_DIR/deploy-manifest.tsv" "$ARCHIVE_MANIFEST"
	COPYFILE_DISABLE=1 tar -cf "$ARCHIVE_FILE" \
		-C "$BIRD/bird-releases" "$RETIRED_ID" || \
		fail "could not package inactive release for archival: $RETIRED_ID"
	tar -tf "$ARCHIVE_FILE" >/dev/null || \
		fail "retired release archive is unreadable: $RETIRED_ID"
	{
		printf '%s  %s\n' "$(sha256 "$ARCHIVE_FILE")" "$ARCHIVE_ASSET"
		printf '%s  %s\n' "$(sha256 "$ARCHIVE_MANIFEST")" "$ARCHIVE_MANIFEST_ASSET"
	} >"$ARCHIVE_CHECKSUM"
	{
		printf 'Exact retired RG34XX-SP card release `%s`.\n\n' "$RETIRED_ID"
		printf 'Canonical manifest SHA-256: `%s`\n' "$RETIRED_MANIFEST_SHA"
		printf 'Archived only after the installed manifest and every deployed file were verified.\n'
	} >"$ARCHIVE_NOTES"

	ARCHIVE_RELEASE_STATE=
	if ARCHIVE_RELEASE_STATE=$("$GH" release view "$ARCHIVE_TAG" \
		--repo "$ARCHIVE_REPOSITORY" --json isDraft --jq .isDraft 2>/dev/null); then
		case "$ARCHIVE_RELEASE_STATE" in
			false)
				verify_published_archive "$ARCHIVE_TAG" "$ARCHIVE_ASSET" \
					"$ARCHIVE_MANIFEST_ASSET" "$ARCHIVE_CHECKSUM_ASSET" \
					"$ARCHIVE_MANIFEST" "$ARCHIVE_FILE"
				;;
			true)
				"$GH" release upload "$ARCHIVE_TAG" "$ARCHIVE_FILE" \
					"$ARCHIVE_MANIFEST" "$ARCHIVE_CHECKSUM" --clobber \
					--repo "$ARCHIVE_REPOSITORY" >/dev/null || \
					fail "could not resume draft archive upload: $ARCHIVE_TAG"
				"$GH" release edit "$ARCHIVE_TAG" --draft=false \
					--notes-file "$ARCHIVE_NOTES" --repo "$ARCHIVE_REPOSITORY" >/dev/null || \
					fail "could not publish immutable archive release: $ARCHIVE_TAG"
				;;
			*) fail "GitHub archive release returned an unknown state: $ARCHIVE_TAG" ;;
		esac
	else
		"$GH" release create "$ARCHIVE_TAG" --draft --target main \
			--title "birdOS retired card release $RETIRED_ID" \
			--notes-file "$ARCHIVE_NOTES" --repo "$ARCHIVE_REPOSITORY" >/dev/null || \
			fail "could not create draft archive release: $ARCHIVE_TAG"
		"$GH" release upload "$ARCHIVE_TAG" "$ARCHIVE_FILE" \
			"$ARCHIVE_MANIFEST" "$ARCHIVE_CHECKSUM" \
			--repo "$ARCHIVE_REPOSITORY" >/dev/null || \
			fail "could not upload inactive release archive: $ARCHIVE_TAG"
		"$GH" release edit "$ARCHIVE_TAG" --draft=false \
			--repo "$ARCHIVE_REPOSITORY" >/dev/null || \
			fail "could not publish immutable archive release: $ARCHIVE_TAG"
	fi

	if [ "$ARCHIVE_RELEASE_STATE" != false ]; then
		ARCHIVE_VERIFY_ATTEMPT=0
		while ! "$GH" release verify "$ARCHIVE_TAG" \
				--repo "$ARCHIVE_REPOSITORY" >/dev/null 2>&1; do
			ARCHIVE_VERIFY_ATTEMPT=$((ARCHIVE_VERIFY_ATTEMPT + 1))
			[ "$ARCHIVE_VERIFY_ATTEMPT" -lt 10 ] || \
				fail "published GitHub archive did not produce a valid attestation: $ARCHIVE_TAG"
			sleep 1
		done
		verify_published_archive "$ARCHIVE_TAG" "$ARCHIVE_ASSET" \
			"$ARCHIVE_MANIFEST_ASSET" "$ARCHIVE_CHECKSUM_ASSET" \
			"$ARCHIVE_MANIFEST" "$ARCHIVE_FILE"
	fi

	verify_archive_selector_unchanged
	validate_retired_release "$RETIRED_DIR" "$RETIRED_ID"
	case "$RETIRED_DIR" in
		"$BIRD"/bird-releases/"$RETIRED_ID") ;;
		*) fail "refusing to remove unsafe archived release path: $RETIRED_DIR" ;;
	esac
	printf 'Archived inactive release %s to private GitHub release %s/%s.\n' \
		"$RETIRED_ID" "$ARCHIVE_REPOSITORY" "$ARCHIVE_TAG"
	# Once the archive is proven, stop pointing the manual previous selector at
	# bytes that are about to leave the card.  Publication happens before
	# removal, so a selector-write failure retains the complete old release.
	if [ "$ROTATE_PREVIOUS_AFTER_ARCHIVE" -eq 1 ]; then
		publish_current_selector_as_previous \
			"$ROTATION_PREVIOUS_SELECTOR_SHA"
	else
		# Space reclamation can retire an older release still named by the
		# manual previous selector.  Close that reference before deletion, so
		# a later host-build failure leaves previous self-referencing the exact
		# still-active release instead of pointing at absent bytes.
		PRESTAGE_PREVIOUS=$BIRD/extlinux/extlinux.previous.conf
		if is_regular_file "$PRESTAGE_PREVIOUS" && \
			PRESTAGE_PREVIOUS_ID=$(selector_release_id \
				"$PRESTAGE_PREVIOUS" 2>/dev/null) && \
			[ "$PRESTAGE_PREVIOUS_ID" = "$RETIRED_ID" ]; then
			PRESTAGE_PREVIOUS_SHA=$(sha256 "$PRESTAGE_PREVIOUS")
			publish_current_selector_as_previous \
				"$PRESTAGE_PREVIOUS_SHA"
		fi
	fi
	rm -rf "$RETIRED_DIR"
	[ ! -e "$RETIRED_DIR" ] && [ ! -L "$RETIRED_DIR" ] || \
		fail "verified archive was published but inactive card release could not be removed: $RETIRED_ID"
	if [ "$RETIRED_SYSTEM_PRESENT" -eq 1 ]; then
		rm -f "$RETIRED_SYSTEM" "$RETIRED_SYSTEM_SIDECAR"
		rmdir "$RETIRED_SYSTEM_ROOT" || \
			fail "retired release SYSTEM directory could not be removed: $RETIRED_ID"
	fi
	sync
	printf 'Reclaimed inactive card release: %s\n' "$RETIRED_ID"
}

plan_post_activation_rotation

# The canonical updater removes only hidden stages for this exact release ID.
# Count that reclaimable space so an interrupted prior attempt cannot prevent
# the read-only preflight from reaching the updater's guarded cleanup.
STALE_RECLAIM_KIB=0
for STALE_STAGE in "$BIRD/bird-releases/.$RELEASE_ID.new."*; do
	[ -d "$STALE_STAGE" ] && [ ! -L "$STALE_STAGE" ] || continue
	STAGE_KIB=$(du -sk "$STALE_STAGE" | awk '{print $1}')
	case "$STAGE_KIB" in ''|*[!0-9]*) fail 'could not size stale release staging directory' ;; esac
	STALE_RECLAIM_KIB=$((STALE_RECLAIM_KIB + STAGE_KIB))
done
BIRD_AVAILABLE_BYTES=$(available_bytes "$BIRD")
case "$BIRD_AVAILABLE_BYTES" in ''|*[!0-9]*) fail 'could not read free space for BIRD' ;; esac
BIRD_EFFECTIVE_BYTES=$((BIRD_AVAILABLE_BYTES + STALE_RECLAIM_KIB * 1024))
ARCHIVE_NEEDED=0
if [ "$BIRD_EFFECTIVE_BYTES" -lt "$BIRD_REQUIRED_BYTES" ]; then
	ARCHIVE_NEEDED=1
	select_retirement_candidates
fi
require_free_space "$WORK_ROOT_REAL" "$HOST_REQUIRED_BYTES" 'kernel/work'
require_free_space "$DATA" "$DATA_REQUIRED_BYTES" 'BIRD-DATA'

printf 'Selected release ID: %s\n' "$RELEASE_ID"
printf 'Build mode: %s\n' "$MODE"
printf 'Initramfs compression: gzip -n -%s\n' "$BIRD_INITRAMFS_GZIP_LEVEL"
printf 'BIRD production staging requirement: %s bytes\n' "$BIRD_REQUIRED_BYTES"
printf 'Output directory: %s\n' "$OUTPUT"
printf 'Card identity: /dev/%s (p1 BIRD, p6 BIRD-DATA)\n' "$WHOLE"
printf 'PortMaster preflight: pinned installed provider %s; checkpoint state %s.\n' \
	"$PORTMASTER_PROVIDER_MARKER_VALUE" \
	"${PORTMASTER_PROVIDER_MARKER_STATE%%:*}"
if [ -n "$ROTATION_SUPERSEDED_ID" ]; then
	printf 'Post-activation rotation: archive verified release %s to %s, remove it from BIRD, and point previous at %s.\n' \
		"$ROTATION_SUPERSEDED_ID" "$ARCHIVE_REPOSITORY" "$RELEASE_ID"
else
	printf 'Post-activation rotation: no superseded immutable release; point previous at %s.\n' \
		"$RELEASE_ID"
fi
if [ "$KOREADER_CATEGORY_COUNT" -gt 0 ]; then
	printf 'KOReader preflight: %s catalog category, archive %s (%s bytes), extraction %s (%s-byte reserve).\n' \
		"$KOREADER_CATEGORY_COUNT" "$KOREADER_ARCHIVE_SHA" \
		"$KOREADER_ARCHIVE_BYTES" "$KOREADER_EXTRACTION_STATE" \
		"$KOREADER_EXTRACTION_RESERVE"
fi
if [ "$ARCHIVE_NEEDED" -eq 1 ]; then
	if [ "$RETIRED_BYTES" -gt 0 ]; then
		printf 'Retirement plan: archive the following inactive releases to %s and reclaim %s bytes:\n' \
			"$ARCHIVE_REPOSITORY" "$RETIRED_BYTES"
		while IFS="$RETIREMENT_TAB" read -r PLANNED_ID PLANNED_DIR PLANNED_BYTES; do
			printf '  %s (%s bytes)\n' "$PLANNED_ID" "$PLANNED_BYTES"
		done <"$RETIREMENT_SELECTED"
	fi
	if [ "$LEGACY_KERNEL_RETIRE" -eq 1 ]; then
		printf 'Retirement plan: remove verified redundant top-level KERNEL (%s bytes).\n' \
			"$LEGACY_KERNEL_RECLAIM_BYTES"
	fi
fi

run_builder_preflight() {
	if [ "$MODE" = profile ]; then
		BIRD_BUILD_PREFLIGHT_ONLY=1 BIRD_LAUNCHER_PROFILE=profile \
		BIRD_RELEASE_ID="$RELEASE_ID" SOURCE="$SOURCE" SYSTEM_SOURCE="$SYSTEM_SOURCE" \
		STORAGE="$STORAGE_SOURCE" SYSTEM_TREE="$SYSTEM_TREE" OUTPUT="$OUTPUT" \
		CLANG="$CLANG" LLD="$LLD" READELF="$READELF" \
		OFFICIAL_INIT="$OFFICIAL_INIT" \
		JOYPAD="$JOYPAD" INIT_BUSYBOX="$INIT_BUSYBOX" \
		BIRD_KERNEL_AUTHORITY="$KERNEL_AUTHORITY" \
		SOURCE_KERNEL_AUTHORITY_RECORD="$SOURCE_KERNEL_AUTHORITY_RECORD" \
		PORTMASTER_ARCHIVE="$PORTMASTER_ARCHIVE" "$BUILDER"
		return
	fi
	(
		unset BIRD_LAUNCHER_PROFILE
		BIRD_BUILD_PREFLIGHT_ONLY=1 BIRD_RELEASE_ID="$RELEASE_ID" \
		SOURCE="$SOURCE" SYSTEM_SOURCE="$SYSTEM_SOURCE" STORAGE="$STORAGE_SOURCE" \
		SYSTEM_TREE="$SYSTEM_TREE" OUTPUT="$OUTPUT" CLANG="$CLANG" LLD="$LLD" \
		READELF="$READELF" \
		OFFICIAL_INIT="$OFFICIAL_INIT" JOYPAD="$JOYPAD" INIT_BUSYBOX="$INIT_BUSYBOX" \
		BIRD_KERNEL_AUTHORITY="$KERNEL_AUTHORITY" \
		SOURCE_KERNEL_AUTHORITY_RECORD="$SOURCE_KERNEL_AUTHORITY_RECORD" \
		PORTMASTER_ARCHIVE="$PORTMASTER_ARCHIVE" "$BUILDER"
	)
}
run_builder_preflight || fail 'canonical pinned-input preflight failed; no build or deployment was attempted'

if [ "$DRY_RUN" -eq 1 ]; then
	if [ "$ARCHIVE_NEEDED" -eq 1 ]; then
		while IFS="$RETIREMENT_TAB" read -r PLANNED_ID PLANNED_DIR PLANNED_BYTES; do
			printf 'Dry run: would archive and verify inactive release %s before reclaiming it.\n' \
				"$PLANNED_ID"
		done <"$RETIREMENT_SELECTED"
		if [ "$LEGACY_KERNEL_RETIRE" -eq 1 ]; then
			printf 'Dry run: would remove the verified redundant top-level KERNEL after snapshotting its build inputs.\n'
		fi
	fi
	if [ -e "$OUTPUT" ] || [ -L "$OUTPUT" ]; then
		printf 'Dry run: would validate and remove matching stale output: %s\n' "$OUTPUT"
	fi
	printf 'Dry run: would run canonical builder: %s\n' "$BUILDER"
	printf 'Dry run: would validate deploy-manifest.tsv, then run updater: %s\n' "$UPDATER"
	if [ -n "$ROTATION_SUPERSEDED_ID" ]; then
		printf 'Dry run: after activation would archive, verify and remove superseded release %s, then retain only %s on-card.\n' \
			"$ROTATION_SUPERSEDED_ID" "$RELEASE_ID"
	else
		printf 'Dry run: after activation would make the exact current selector authoritative as previous.\n'
	fi
	printf 'Launcher SHA-256: not built (dry run)\n'
	printf 'Manifest SHA-256: not built (dry run)\n'
	printf 'Deployment result: not run (dry run)\n'
	exit 0
fi

# Serialize the write probes and any release retirement with development,
# updater and migration transactions. Planning remains read-only; card identity
# and the mutable-release boundary are re-read only after the shared lock is
# held and before the first card write.
BIRD_PRODUCTION_LOCKED_WHOLE=$WHOLE
bird_card_lock_acquire
validate_stock_root_card_identity
[ "$WHOLE" = "$BIRD_PRODUCTION_LOCKED_WHOLE" ] || \
	fail 'card identity changed after acquiring its production transaction lock'
reject_dev_current_production_state
if [ "$ARCHIVE_NEEDED" -eq 1 ]; then
	verify_archive_selector_unchanged
	verify_portmaster_provider_unchanged
	snapshot_legacy_kernel_build_inputs
fi

probe_writable_volume() {
	PROBE_ROOT=$1
	PROBE=$PROBE_ROOT/.bird-build-deploy-write-test.$$
	case "$PROBE_ROOT" in
		"$BIRD") BIRD_WRITE_PROBE=$PROBE ;;
		"$DATA") DATA_WRITE_PROBE=$PROBE ;;
		*) fail 'internal write-test target mismatch' ;;
	esac
	[ ! -e "$PROBE" ] && [ ! -L "$PROBE" ] || fail "write-test path is already occupied: $PROBE"
	(umask 077; set -C; printf 'bird-write-test\n' >"$PROBE") 2>/dev/null || \
		fail "volume is not writable: $PROBE_ROOT"
	[ "$(cat "$PROBE")" = bird-write-test ] || fail "volume write verification failed: $PROBE_ROOT"
}
probe_writable_volume "$BIRD"
probe_writable_volume "$DATA"
rm -f "$BIRD_WRITE_PROBE" "$DATA_WRITE_PROBE"
BIRD_WRITE_PROBE=
DATA_WRITE_PROBE=

if [ "$ARCHIVE_NEEDED" -eq 1 ]; then
	while IFS="$RETIREMENT_TAB" read -r PLANNED_ID PLANNED_DIR PLANNED_BYTES; do
		archive_and_remove_retired_release "$PLANNED_ID" "$PLANNED_DIR"
	done <"$RETIREMENT_SELECTED"
	retire_legacy_root_kernel
	# The canonical updater later acquires this same transaction lock itself.
	# This planning/probe/retirement transaction ends before the host build.
fi
bird_card_lock_release

if [ "$ARCHIVE_NEEDED" -eq 1 ]; then
	if [ "$HOST_TEST_MODE" -eq 1 ]; then
		BIRD_POST_ARCHIVE_BYTES=$((BIRD_EFFECTIVE_BYTES + RETIRED_BYTES + LEGACY_KERNEL_RECLAIM_BYTES))
	else
		BIRD_POST_ARCHIVE_BYTES=$(( $(available_bytes "$BIRD") + STALE_RECLAIM_KIB * 1024 ))
	fi
	[ "$BIRD_POST_ARCHIVE_BYTES" -ge "$BIRD_REQUIRED_BYTES" ] || \
		fail "verified inactive release was archived but BIRD still lacks staging space: need $BIRD_REQUIRED_BYTES bytes, have $BIRD_POST_ARCHIVE_BYTES"
fi

if [ -e "$OUTPUT" ] || [ -L "$OUTPUT" ]; then
	[ -d "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || \
		fail "matching generated output is not a safe directory: $OUTPUT"
	case "$OUTPUT" in
		"$WORK_ROOT_REAL"/bird-rocknix-stock-root-$RELEASE_ID) ;;
		*) fail "refusing to remove unsafe generated output: $OUTPUT" ;;
	esac
	printf 'Removing matching stale generated output: %s\n' "$OUTPUT"
	rm -rf "$OUTPUT"
	[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || \
		fail "could not remove stale generated output: $OUTPUT"
fi

run_builder() {
	if [ "$MODE" = profile ]; then
		BIRD_LAUNCHER_PROFILE=profile BIRD_RELEASE_ID="$RELEASE_ID" \
		SOURCE="$BUILD_SOURCE" SYSTEM_SOURCE="$SYSTEM_SOURCE" STORAGE="$STORAGE_SOURCE" \
		SYSTEM_TREE="$SYSTEM_TREE" OUTPUT="$OUTPUT" CLANG="$CLANG" LLD="$LLD" \
		READELF="$READELF" \
		OFFICIAL_INIT="$OFFICIAL_INIT" JOYPAD="$JOYPAD" INIT_BUSYBOX="$INIT_BUSYBOX" \
		BIRD_KERNEL_AUTHORITY="$KERNEL_AUTHORITY" \
		SOURCE_KERNEL_AUTHORITY_RECORD="$SOURCE_KERNEL_AUTHORITY_RECORD" \
		PORTMASTER_ARCHIVE="$PORTMASTER_ARCHIVE" "$BUILDER"
		return
	fi
	(
		unset BIRD_LAUNCHER_PROFILE
		BIRD_RELEASE_ID="$RELEASE_ID" SOURCE="$BUILD_SOURCE" SYSTEM_SOURCE="$SYSTEM_SOURCE" \
		STORAGE="$STORAGE_SOURCE" SYSTEM_TREE="$SYSTEM_TREE" OUTPUT="$OUTPUT" \
		CLANG="$CLANG" LLD="$LLD" READELF="$READELF" \
		OFFICIAL_INIT="$OFFICIAL_INIT" \
		JOYPAD="$JOYPAD" INIT_BUSYBOX="$INIT_BUSYBOX" \
		BIRD_KERNEL_AUTHORITY="$KERNEL_AUTHORITY" \
		SOURCE_KERNEL_AUTHORITY_RECORD="$SOURCE_KERNEL_AUTHORITY_RECORD" \
		PORTMASTER_ARCHIVE="$PORTMASTER_ARCHIVE" "$BUILDER"
	)
}

run_builder || fail "canonical build failed; stale output retained for diagnosis: $OUTPUT"

CANDIDATE=$OUTPUT/card
MANIFEST=$OUTPUT/deploy-manifest.tsv
is_regular_file "$MANIFEST" || fail "canonical deploy manifest missing or unsafe: $MANIFEST"
[ -d "$CANDIDATE" ] && [ ! -L "$CANDIDATE" ] || fail 'canonical candidate card tree is missing or unsafe'

validate_manifest() {
	RECORDS=$RUN_TEMP/manifest-records
	MANIFEST_PATHS=$RUN_TEMP/manifest-paths
	MANIFEST_DIRS=$RUN_TEMP/manifest-dirs
	CANDIDATE_PATHS=$RUN_TEMP/candidate-paths
	CANDIDATE_DIRS=$RUN_TEMP/candidate-dirs
	DUPLICATES=$RUN_TEMP/manifest-duplicates
	TAB=$(printf '\t')
	EXPECTED_MANIFEST_INPUT_COUNT=14
	[ "$KERNEL_AUTHORITY" = stock ] || EXPECTED_MANIFEST_INPUT_COUNT=15
	awk -F '\t' -v expected_release="$RELEASE_ID" \
		-v expected_inputs="$EXPECTED_MANIFEST_INPUT_COUNT" '
		function safe_path(path) {
			return path ~ /^[A-Za-z0-9._\/-]+$/ && path !~ /(^|\/)\.\.?($|\/)/
		}
		$1 == "schema" {if (NF != 2 || $2 != "bird-deploy-v1" || schema++) exit 1; next}
		$1 == "release" {if (NF != 2 || $2 != expected_release || release++) exit 1; next}
		$1 == "target-mode-policy" {if (NF != 2 || $2 != "fat-capability" || policy++) exit 1; next}
		$1 == "source-commit" {if (NF != 3 || source++) exit 1; next}
		$1 == "artifact" {
			if (NF != 4 || ($2 != "device-contract" && $2 != "catalog") ||
			    !safe_path($3) || length($4) != 64 || $4 ~ /[^0-9a-f]/) exit 1
			if ($2 == "device-contract") device_contract++
			if ($2 == "catalog") catalog++
			print "artifact\t" $2 "\t" $3 "\t" $4
			artifacts++; next
		}
		$1 == "input" {
			if (NF != 6 || !safe_path($2) || $3 !~ /^[0-7][0-7][0-7]$/ ||
			    $4 !~ /^[0-9]+$/ || length($5) != 64 || $5 ~ /[^0-9a-f]/ || $6 == "") exit 1
			print "input\t" $2; inputs++; next
		}
		$1 == "dir" {
			if (NF != 3 || !safe_path($2) || $3 !~ /^[0-7][0-7][0-7]$/) exit 1
			print "dir\t" $2; next
		}
		$1 == "file" {
			if (NF != 5 || !safe_path($2) || $3 !~ /^[0-7][0-7][0-7]$/ ||
			    $4 !~ /^[0-9]+$/ || length($5) != 64 || $5 ~ /[^0-9a-f]/) exit 1
			print "file\t" $2 "\t" $3 "\t" $4 "\t" $5; files++; next
		}
		{exit 1}
		END {
			if (schema != 1 || release != 1 || policy != 1 || source != 1 ||
			    inputs != expected_inputs || files < 1 || artifacts != 2 ||
			    device_contract != 1 || catalog != 1) exit 1
		}
	' "$MANIFEST" >"$RECORDS" || fail 'canonical deploy manifest is malformed or has the wrong release ID'
	DEVICE_CONTRACT_PATH=$(awk -F '\t' '$1 == "artifact" && $2 == "device-contract" {print $3}' \
		"$RECORDS")
	DEVICE_CONTRACT_SHA=$(awk -F '\t' '$1 == "artifact" && $2 == "device-contract" {print $4}' \
		"$RECORDS")
	CATALOG_ARTIFACT_PATH=$(awk -F '\t' '$1 == "artifact" && $2 == "catalog" {print $3}' \
		"$RECORDS")
	CATALOG_ARTIFACT_SHA=$(awk -F '\t' '$1 == "artifact" && $2 == "catalog" {print $4}' \
		"$RECORDS")
	[ "$DEVICE_CONTRACT_PATH" = bird/bird-device-contract.tsv ] || \
		fail 'canonical device-contract artifact path changed'
	[ "$CATALOG_ARTIFACT_PATH" = launcher/catalog.generated.h ] || \
		fail 'canonical catalog artifact path changed'
	[ "$CATALOG_ARTIFACT_SHA" = "$(sha256 "$KOREADER_CATALOG_HEADER")" ] || \
		fail 'canonical catalog artifact does not match the generated catalog source'
	awk -F '\t' -v path="$DEVICE_CONTRACT_PATH" -v digest="$DEVICE_CONTRACT_SHA" \
		'$1 == "file" && $2 == path && $5 == digest {found++} END {exit found != 1}' \
		"$RECORDS" || fail 'device-contract artifact does not match its deployed file record'
	awk -F '\t' '$1 == "file" || $1 == "dir" {print $2}' "$RECORDS" | \
		LC_ALL=C sort | uniq -d >"$DUPLICATES"
	[ ! -s "$DUPLICATES" ] || fail 'canonical deploy manifest has duplicate paths'
	awk -F '\t' '$1 == "input" {print $2}' "$RECORDS" | LC_ALL=C sort \
		>"$RUN_TEMP/manifest-inputs"
	printf '%s\n' KERNEL PortMaster.zip \
		PortMaster/PortMaster.sh PortMaster/funcs.txt PortMaster/harbourmaster \
		PortMaster/mod_ROCKNIX.txt PortMaster/pugwash ROCKNIX-STORAGE \
		ROCKNIX-SYSTEM dtb.img initramfs/busybox initramfs/init \
		rocknix-singleadc-joypad.ko usr/bin/autostart | LC_ALL=C sort \
		>"$RUN_TEMP/expected-inputs"
	if [ "$KERNEL_AUTHORITY" != stock ]; then
		basename "$SOURCE_KERNEL_AUTHORITY_RECORD" >>"$RUN_TEMP/expected-inputs"
		LC_ALL=C sort -o "$RUN_TEMP/expected-inputs" "$RUN_TEMP/expected-inputs"
	fi
	cmp "$RUN_TEMP/expected-inputs" "$RUN_TEMP/manifest-inputs" >/dev/null || \
		fail 'canonical deploy manifest input set is incomplete or duplicated'
	awk -F '\t' '$1 == "file" {print $2}' "$RECORDS" | LC_ALL=C sort >"$MANIFEST_PATHS"
	awk -F '\t' '$1 == "dir" {print $2}' "$RECORDS" | LC_ALL=C sort >"$MANIFEST_DIRS"
	find "$CANDIDATE" -mindepth 1 ! -type f ! -type d -print | grep -q . && \
		fail 'candidate contains a symlink or special node'
	find "$CANDIDATE" -type f -print | while IFS= read -r FILE; do
		printf '%s\n' "${FILE#"$CANDIDATE"/}"
	done | LC_ALL=C sort >"$CANDIDATE_PATHS"
	cmp "$MANIFEST_PATHS" "$CANDIDATE_PATHS" >/dev/null || \
		fail 'candidate regular-file set differs from canonical manifest'
	find "$CANDIDATE" -mindepth 1 -type d -empty -print | while IFS= read -r DIRECTORY; do
		printf '%s\n' "${DIRECTORY#"$CANDIDATE"/}"
	done | LC_ALL=C sort >"$CANDIDATE_DIRS"
	cmp "$MANIFEST_DIRS" "$CANDIDATE_DIRS" >/dev/null || \
		fail 'candidate empty-directory set differs from canonical manifest'
	while IFS="$TAB" read -r KIND RELATIVE MODE_VALUE BYTES_VALUE HASH_VALUE REST; do
		case "$KIND" in
			dir)
				[ -d "$CANDIDATE/$RELATIVE" ] && [ ! -L "$CANDIDATE/$RELATIVE" ] || \
					fail "candidate directory missing or unsafe: $RELATIVE"
				[ "$(file_mode "$CANDIDATE/$RELATIVE")" = "$MODE_VALUE" ] || \
					fail "candidate directory mode changed: $RELATIVE"
				;;
			file)
				is_regular_file "$CANDIDATE/$RELATIVE" || fail "candidate file missing or unsafe: $RELATIVE"
				[ "$(file_mode "$CANDIDATE/$RELATIVE")" = "$MODE_VALUE" ] || \
					fail "candidate mode changed: $RELATIVE"
				[ "$(file_bytes "$CANDIDATE/$RELATIVE")" = "$BYTES_VALUE" ] || \
					fail "candidate size changed: $RELATIVE"
				[ "$(sha256 "$CANDIDATE/$RELATIVE")" = "$HASH_VALUE" ] || \
					fail "candidate digest changed: $RELATIVE"
				;;
		esac
	done <"$MANIFEST"
	LAUNCHER_RECORD=$(awk -F '\t' '$1 == "file" && $2 == "bird/bird-launcher" {print $5}' "$MANIFEST")
	case "$LAUNCHER_RECORD" in
		[0-9a-f][0-9a-f]*) ;;
		*) fail 'canonical manifest has no launcher digest' ;;
	esac
	[ "${#LAUNCHER_RECORD}" -eq 64 ] || fail 'canonical launcher digest has the wrong length'
	LAUNCHER_SHA=$(sha256 "$CANDIDATE/bird/bird-launcher")
	[ "$LAUNCHER_SHA" = "$LAUNCHER_RECORD" ] || fail 'launcher does not match canonical manifest'
	MANIFEST_SHA=$(sha256 "$MANIFEST")
}
validate_manifest

printf 'Launcher SHA-256: %s\n' "$LAUNCHER_SHA"
printf 'Manifest SHA-256: %s\n' "$MANIFEST_SHA"

DEPLOY_RESULT='activated new immutable release'
INSTALLED_RELEASE=$BIRD/bird-releases/$RELEASE_ID
if [ -e "$INSTALLED_RELEASE" ] || [ -L "$INSTALLED_RELEASE" ]; then
	[ -d "$INSTALLED_RELEASE" ] && [ ! -L "$INSTALLED_RELEASE" ] || \
		fail 'selected release destination became unsafe after the build; rerun to select another ID'
	is_regular_file "$INSTALLED_RELEASE/.complete" && \
		[ "$(cat "$INSTALLED_RELEASE/.complete")" = "$MANIFEST_SHA" ] && \
		is_regular_file "$INSTALLED_RELEASE/deploy-manifest.tsv" && \
		[ "$(sha256 "$INSTALLED_RELEASE/deploy-manifest.tsv")" = "$MANIFEST_SHA" ] || \
		fail 'selected release ID became occupied by a different or incomplete release; rerun to select another ID'
	DEPLOY_RESULT='verified and activated already-installed identical release'
fi

if ! BIRD_HOST_TEST_MODE="$HOST_TEST_MODE" BIRD_DEVICE_INFO="$BIRD_DEVICE_INFO" \
	BIRD_RELEASE_ID="$RELEASE_ID" BIRD="$BIRD" DATA="$DATA" \
	CANDIDATE="$CANDIDATE" MANIFEST="$MANIFEST" STORAGE_SOURCE="$STORAGE_SOURCE" \
	SYSTEM_INSTALL_SOURCE="$SYSTEM_SOURCE" \
	"$UPDATER"; then
	fail "deployment failed; the previous selector remains authoritative unless the updater reported a verified post-selector commit. Build output retained at: $OUTPUT"
fi

is_regular_file "$INSTALLED_RELEASE/.complete" || fail 'deployed completion marker is missing or unsafe'
[ "$(cat "$INSTALLED_RELEASE/.complete")" = "$MANIFEST_SHA" ] || fail 'deployed completion marker does not match the build manifest'
is_regular_file "$INSTALLED_RELEASE/deploy-manifest.tsv" || fail 'deployed canonical manifest is missing or unsafe'
[ "$(sha256 "$INSTALLED_RELEASE/deploy-manifest.tsv")" = "$MANIFEST_SHA" ] || fail 'deployed canonical manifest hash changed'
grep -Fq "bird_release=$RELEASE_ID" "$BIRD/extlinux/extlinux.conf" || \
	fail 'active selector does not name the deployed release'

# A successful canonical activation rotates the superseded immutable release
# off-card.  The GitHub copy is published and fully re-read before the exact
# current selector replaces the previous selector and the old bytes are
# removed. No alternate boot release is retained.
ROTATION_LOCKED_WHOLE=$WHOLE
bird_card_lock_acquire
validate_stock_root_card_identity
[ "$WHOLE" = "$ROTATION_LOCKED_WHOLE" ] || \
	fail 'card identity changed before post-activation release rotation'
reject_dev_current_production_state
read_active_selector
[ "$ACTIVE_SELECTOR_KIND" = release ] && \
	[ "$ACTIVE_RELEASE_ID" = "$RELEASE_ID" ] || \
	fail 'active selector changed before post-activation release rotation'
ARCHIVE_ACTIVE_SELECTOR_KIND=$ACTIVE_SELECTOR_KIND
ARCHIVE_ACTIVE_SELECTOR_SHA=$ACTIVE_SELECTOR_SHA
validate_completed_release "$INSTALLED_RELEASE" "$RELEASE_ID" \
	'newly activated release'
is_regular_file "$INSTALLED_RELEASE/extlinux/extlinux.conf" && \
	[ "$(sha256 "$INSTALLED_RELEASE/extlinux/extlinux.conf")" = \
	"$ARCHIVE_ACTIVE_SELECTOR_SHA" ] || \
	fail 'active selector differs from the newly activated release selector'
if [ -n "$ROTATION_SUPERSEDED_ID" ]; then
	archive_and_remove_retired_release "$ROTATION_SUPERSEDED_ID" \
		"$ROTATION_SUPERSEDED_DIR" 1
else
	publish_current_selector_as_previous
fi
# A prior post-activation interruption can leave an older verified immutable
# release that is neither current nor previous. Archive and remove every such
# release now so the card returns to its one-canonical-release contract even
# when staging space did not force an earlier reclamation pass.
for LEFTOVER_RELEASE_DIR in "$BIRD"/bird-releases/*; do
	[ -e "$LEFTOVER_RELEASE_DIR" ] || [ -L "$LEFTOVER_RELEASE_DIR" ] || break
	LEFTOVER_RELEASE_ID=${LEFTOVER_RELEASE_DIR##*/}
	[ "$LEFTOVER_RELEASE_ID" != "$RELEASE_ID" ] || continue
	[ -d "$LEFTOVER_RELEASE_DIR" ] && [ ! -L "$LEFTOVER_RELEASE_DIR" ] || \
		fail "inactive release path is unsafe after activation: $LEFTOVER_RELEASE_ID"
	# A bare directory or one-sided marker can reserve a release name during
	# collision handling, but it is not an immutable release to archive.  Only
	# the canonical manifest + completion-marker pair enters retirement.
	if [ ! -e "$LEFTOVER_RELEASE_DIR/deploy-manifest.tsv" ] || \
	   [ ! -e "$LEFTOVER_RELEASE_DIR/.complete" ]; then
		continue
	fi
	is_regular_file "$LEFTOVER_RELEASE_DIR/deploy-manifest.tsv" && \
		is_regular_file "$LEFTOVER_RELEASE_DIR/.complete" || \
		fail "inactive release authority is unsafe after activation: $LEFTOVER_RELEASE_ID"
	check_archive_repository
	archive_and_remove_retired_release "$LEFTOVER_RELEASE_ID" \
		"$LEFTOVER_RELEASE_DIR" 0
done
verify_archive_selector_unchanged
is_regular_file "$BIRD/extlinux/extlinux.previous.conf" && \
	[ "$(sha256 "$BIRD/extlinux/extlinux.previous.conf")" = \
	"$ARCHIVE_ACTIVE_SELECTOR_SHA" ] || \
	fail 'previous selector does not match the retained current release'
if [ -n "$ROTATION_SUPERSEDED_ID" ]; then
	[ ! -e "$ROTATION_SUPERSEDED_DIR" ] && \
		[ ! -L "$ROTATION_SUPERSEDED_DIR" ] || \
		fail 'superseded release remains after verified rotation'
fi
bird_card_lock_release

printf 'Deployment result: %s\n' "$DEPLOY_RESULT"
printf '\nNext steps:\n'
printf '  1. Eject safely: diskutil eject /dev/%s\n' "$WHOLE"
printf '  2. Insert the card in the RG34XX-SP and boot normally.\n'
if [ "$MODE" = profile ]; then
	printf '  3. After testing, reinsert the card and collect:\n'
	printf '     %s/Bird/log/early-initramfs-latest.log\n' "$DATA"
	printf '     %s/Bird/log/stock-root-supervisor.log\n' "$DATA"
else
	printf '  3. If behavior changes, retain the selected release ID and card logs for comparison.\n'
fi
