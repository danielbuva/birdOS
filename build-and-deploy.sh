#!/bin/sh
# One guarded macOS entry point for the canonical birdOS build and deployment.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
BASE_RELEASE_ID=v6.23
MODE=
REQUESTED_RELEASE_ID=
DRY_RUN=0
HOST_TEST_MODE=${BIRD_BUILD_DEPLOY_HOST_TEST_MODE:-0}
ARCHIVE_REPOSITORY=${BIRD_RELEASE_ARCHIVE_REPOSITORY:-danielbuva/birdOS-release-archive}
RUN_TEMP=
BIRD_WRITE_PROBE=
DATA_WRITE_PROBE=

usage() {
	cat <<'EOF'
Usage:
  ./build-and-deploy.sh --release [--release-id ID] [--dry-run]
  ./build-and-deploy.sh --profile [--release-id ID] [--dry-run]
  ./build-and-deploy.sh --help

Modes:
  --release       Build the ordinary launcher with profiling disabled.
  --profile       Build with BIRD_LAUNCHER_PROFILE=profile.

Options:
  --release-id ID Use ID as the preferred immutable release ID. If that ID is
                  already present on the card or in the GitHub archive, a
                  timestamped unused ID is selected.
  --dry-run       Perform read-only preflight and print the selected commands.
  --help          Show this help text.

The command requires the exact BIRD and BIRD-DATA volumes on the supported
RG34XX-SP card. It never scans or modifies ROMs, BIOS, media, saves, or other
card data. When BIRD lacks staging space, it may retire one inactive completed
release only after archiving and verifying it in the configured private,
immutable GitHub release repository.
EOF
}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

cleanup() {
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
[ -n "$REQUESTED_RELEASE_ID" ] || REQUESTED_RELEASE_ID=$BASE_RELEASE_ID
case "$REQUESTED_RELEASE_ID" in
	''|[![:alnum:]]*|*[![:alnum:]._-]*) fail "unsafe Bird release ID: $REQUESTED_RELEASE_ID" ;;
esac
[ "${#REQUESTED_RELEASE_ID}" -le 64 ] || fail 'Bird release ID is longer than 64 bytes'
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
	firmware/mac-update-rocknix-stock-root-v6.sh \
	firmware/mac-stock-root-card-identity.sh; do
	[ -f "$ROOT/$REQUIRED_SOURCE" ] && [ ! -L "$ROOT/$REQUIRED_SOURCE" ] || \
		fail "required repository source missing or unsafe: $REQUIRED_SOURCE"
done

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
SYSTEM_SOURCE=${SYSTEM_SOURCE:-$DATA/MUOS/runtime/ROCKNIX-SYSTEM}
STORAGE_SOURCE=${STORAGE_SOURCE:-$HOME/rocknix-reference-result/storage.ext4}
SYSTEM_TREE=${SYSTEM_TREE:-$ROOT/kernel/work/rocknix-system-exact-20260701}
OFFICIAL_INIT=${OFFICIAL_INIT:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/init}
JOYPAD=${JOYPAD:-$ROOT/kernel/work/rocknix-system-exact-20260701/usr/lib/kernel-overlays/base/lib/modules/7.0.11/rocknix-joypad/rocknix-singleadc-joypad.ko}
INIT_BUSYBOX=${INIT_BUSYBOX:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/usr/bin/busybox}
PORTMASTER_ARCHIVE=${PORTMASTER_ARCHIVE:-$SYSTEM_TREE/usr/config/PortMaster/release/PortMaster.zip}

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

BIRD_FS=$(field "$BIRD" 'File System Personality')
case "$BIRD_FS" in
	*FAT*|*ExFAT*) BIRD_SYNTHETIC_MODES=1 ;;
	*) BIRD_SYNTHETIC_MODES=0 ;;
esac

is_regular_file() {
	[ -f "$1" ] && [ ! -L "$1" ]
}

for PINNED_FILE in "$SOURCE/KERNEL" "$SOURCE/dtb.img" "$SYSTEM_SOURCE" \
	"$STORAGE_SOURCE" "$SYSTEM_TREE/usr/bin/autostart" "$OFFICIAL_INIT" \
	"$JOYPAD" "$INIT_BUSYBOX" "$PORTMASTER_ARCHIVE"; do
	is_regular_file "$PINNED_FILE" || fail "pinned build input missing or unsafe: $PINNED_FILE"
done
if is_regular_file "$SOURCE/KERNEL.fallback"; then
	FALLBACK_KERNEL=$SOURCE/KERNEL.fallback
elif [ ! -e "$SOURCE/KERNEL.fallback" ]; then
	# The canonical builder will accept this only when the active top-level
	# kernel is the exact pinned v5.4 fallback.
	FALLBACK_KERNEL=$SOURCE/KERNEL
else
	fail 'fallback KERNEL is a symlink or special node'
fi

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

read_active_release_id() {
	ACTIVE_SELECTOR=$BIRD/extlinux/extlinux.conf
	is_regular_file "$ACTIVE_SELECTOR" || fail 'active extlinux selector is missing or unsafe'
	ACTIVE_RELEASE_ID=$(awk '
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
	' "$ACTIVE_SELECTOR") || fail 'active selector does not contain exactly one Bird release ID'
	case "$ACTIVE_RELEASE_ID" in
		''|[![:alnum:]]*|*[![:alnum:]._-]*) fail 'active selector contains an unsafe release ID' ;;
	esac
}

validate_retired_release() {
	RETIRED_DIR=$1
	RETIRED_ID=$2
	case "$RETIRED_ID" in
		''|[![:alnum:]]*|*[![:alnum:]._-]*) fail 'retirement candidate has an unsafe release ID' ;;
	esac
	[ -d "$RETIRED_DIR" ] && [ ! -L "$RETIRED_DIR" ] || \
		fail "retirement candidate is not a safe directory: $RETIRED_DIR"
	[ "$RETIRED_DIR" = "$BIRD/bird-releases/$RETIRED_ID" ] || \
		fail 'retirement candidate path does not match its release ID'
	[ "$RETIRED_ID" != "$ACTIVE_RELEASE_ID" ] || \
		fail 'refusing to archive or remove the active release'
	is_regular_file "$RETIRED_DIR/deploy-manifest.tsv" || \
		fail "retirement candidate manifest is missing or unsafe: $RETIRED_ID"
	is_regular_file "$RETIRED_DIR/.complete" || \
		fail "retirement candidate completion marker is missing or unsafe: $RETIRED_ID"
	RETIRED_MANIFEST_SHA=$(sha256 "$RETIRED_DIR/deploy-manifest.tsv")
	[ "$(cat "$RETIRED_DIR/.complete")" = "$RETIRED_MANIFEST_SHA" ] || \
		fail "retirement candidate completion marker changed: $RETIRED_ID"

	RETIRED_RECORDS=$RUN_TEMP/retired-records
	RETIRED_EXPECTED_FILES=$RUN_TEMP/retired-expected-files
	RETIRED_ACTUAL_FILES=$RUN_TEMP/retired-actual-files
	RETIRED_EXPECTED_DIRS=$RUN_TEMP/retired-expected-dirs
	RETIRED_ACTUAL_DIRS=$RUN_TEMP/retired-actual-dirs
	RETIRED_DUPLICATES=$RUN_TEMP/retired-duplicates
	awk -F '\t' -v expected_release="$RETIRED_ID" '
		function safe_path(path) {
			return path ~ /^[A-Za-z0-9._\/-]+$/ && path !~ /(^|\/)\.\.?($|\/)/
		}
		$1 == "schema" {if (NF != 2 || $2 != "bird-deploy-v1" || schema++) exit 1; next}
		$1 == "release" {if (NF != 2 || $2 != expected_release || release++) exit 1; next}
		$1 == "target-mode-policy" {if (NF != 2 || $2 != "fat-capability" || policy++) exit 1; next}
		$1 == "source-commit" {if (NF != 3 || source++) exit 1; next}
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
		END {if (schema != 1 || release != 1 || policy != 1 || source != 1 || inputs != 15 || files < 1) exit 1}
	' "$RETIRED_DIR/deploy-manifest.tsv" >"$RETIRED_RECORDS" || \
		fail "retirement candidate manifest is malformed: $RETIRED_ID"
	awk -F '\t' '$1 == "file" || $1 == "dir" {print $2}' "$RETIRED_RECORDS" | \
		LC_ALL=C sort | uniq -d >"$RETIRED_DUPLICATES"
	[ ! -s "$RETIRED_DUPLICATES" ] || \
		fail "retirement candidate manifest has duplicate paths: $RETIRED_ID"
	find "$RETIRED_DIR" -mindepth 1 ! -type f ! -type d -print | grep -q . && \
		fail "retirement candidate contains a symlink or special node: $RETIRED_ID"
	{
		printf '%s\n' .complete deploy-manifest.tsv
		awk -F '\t' '$1 == "file" {print $2}' "$RETIRED_RECORDS"
	} | LC_ALL=C sort >"$RETIRED_EXPECTED_FILES"
	find "$RETIRED_DIR" -type f -print | while IFS= read -r RETIRED_FILE; do
		printf '%s\n' "${RETIRED_FILE#"$RETIRED_DIR"/}"
	done | LC_ALL=C sort >"$RETIRED_ACTUAL_FILES"
	cmp "$RETIRED_EXPECTED_FILES" "$RETIRED_ACTUAL_FILES" >/dev/null || \
		fail "retirement candidate file set differs from its manifest: $RETIRED_ID"
	awk -F '\t' '$1 == "dir" {print $2}' "$RETIRED_RECORDS" | \
		LC_ALL=C sort >"$RETIRED_EXPECTED_DIRS"
	find "$RETIRED_DIR" -mindepth 1 -type d -empty -print | while IFS= read -r RETIRED_DIRECTORY; do
		printf '%s\n' "${RETIRED_DIRECTORY#"$RETIRED_DIR"/}"
	done | LC_ALL=C sort >"$RETIRED_ACTUAL_DIRS"
	cmp "$RETIRED_EXPECTED_DIRS" "$RETIRED_ACTUAL_DIRS" >/dev/null || \
		fail "retirement candidate empty-directory set differs from its manifest: $RETIRED_ID"
	TAB=$(printf '\t')
	while IFS="$TAB" read -r KIND RELATIVE MODE_VALUE BYTES_VALUE HASH_VALUE; do
		case "$KIND" in
			dir)
				[ -d "$RETIRED_DIR/$RELATIVE" ] && [ ! -L "$RETIRED_DIR/$RELATIVE" ] || \
					fail "retirement candidate directory is missing or unsafe: $RETIRED_ID/$RELATIVE"
				verify_installed_mode "$RETIRED_DIR/$RELATIVE" "$MODE_VALUE" || \
					fail "retirement candidate directory capabilities changed: $RETIRED_ID/$RELATIVE"
				;;
			file)
				is_regular_file "$RETIRED_DIR/$RELATIVE" || \
					fail "retirement candidate file is missing or unsafe: $RETIRED_ID/$RELATIVE"
				verify_installed_mode "$RETIRED_DIR/$RELATIVE" "$MODE_VALUE" || \
					fail "retirement candidate capabilities changed: $RETIRED_ID/$RELATIVE"
				[ "$(file_bytes "$RETIRED_DIR/$RELATIVE")" = "$BYTES_VALUE" ] || \
					fail "retirement candidate size changed: $RETIRED_ID/$RELATIVE"
				[ "$(sha256 "$RETIRED_DIR/$RELATIVE")" = "$HASH_VALUE" ] || \
					fail "retirement candidate digest changed: $RETIRED_ID/$RELATIVE"
				;;
		esac
	done <"$RETIRED_RECORDS"
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
BIRD_REQUIRED_BYTES=$(( $(file_bytes "$SOURCE/KERNEL") + $(file_bytes "$SOURCE/dtb.img") + 4194304 ))
DATA_REQUIRED_BYTES=16777216
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

select_retirement_candidate() {
	read_active_release_id
	ARCHIVE_ACTIVE_RELEASE_ID=$ACTIVE_RELEASE_ID
	ACTIVE_RELEASE_DIR=$BIRD/bird-releases/$ACTIVE_RELEASE_ID
	[ -d "$ACTIVE_RELEASE_DIR" ] && [ ! -L "$ACTIVE_RELEASE_DIR" ] || \
		fail 'active selector does not name a safe installed release directory'
	RETIREMENT_CANDIDATES=$RUN_TEMP/retirement-candidates
	find "$BIRD/bird-releases" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print | \
		LC_ALL=C sort >"$RETIREMENT_CANDIDATES"
	RETIRED_DIR=
	RETIRED_ID=
	RETIRED_BYTES=0
	while IFS= read -r POSSIBLE_DIR; do
		POSSIBLE_ID=${POSSIBLE_DIR##*/}
		[ "$POSSIBLE_ID" != "$ACTIVE_RELEASE_ID" ] || continue
		[ "$POSSIBLE_ID" != "$RELEASE_ID" ] || continue
		POSSIBLE_KIB=$(du -sk "$POSSIBLE_DIR" | awk '{print $1}')
		case "$POSSIBLE_KIB" in
			''|*[!0-9]*) fail 'could not size inactive release candidate' ;;
		esac
		POSSIBLE_BYTES=$((POSSIBLE_KIB * 1024))
		if [ $((BIRD_EFFECTIVE_BYTES + POSSIBLE_BYTES)) -ge "$BIRD_REQUIRED_BYTES" ]; then
			RETIRED_DIR=$POSSIBLE_DIR
			RETIRED_ID=$POSSIBLE_ID
			RETIRED_BYTES=$POSSIBLE_BYTES
			break
		fi
	done <"$RETIREMENT_CANDIDATES"
	[ -n "$RETIRED_DIR" ] || \
		fail "BIRD has insufficient staging space and no single inactive release can safely provide it: need $BIRD_REQUIRED_BYTES bytes, have $BIRD_AVAILABLE_BYTES plus $((STALE_RECLAIM_KIB * 1024)) stale bytes"
	validate_retired_release "$RETIRED_DIR" "$RETIRED_ID"
	check_archive_repository
}

verify_published_archive() {
	VERIFY_TAG=$1
	VERIFY_ARCHIVE_ASSET=$2
	VERIFY_MANIFEST_ASSET=$3
	VERIFY_CHECKSUM_ASSET=$4
	VERIFY_LOCAL_MANIFEST=$5
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
		--pattern "$VERIFY_MANIFEST_ASSET" --dir "$VERIFY_DOWNLOAD" >/dev/null || \
		fail "could not download archived manifest for verification: $VERIFY_TAG"
	cmp "$VERIFY_LOCAL_MANIFEST" "$VERIFY_DOWNLOAD/$VERIFY_MANIFEST_ASSET" >/dev/null || \
		fail "published archive manifest differs from the card release: $VERIFY_TAG"
}

archive_and_remove_retired_release() {
	validate_retired_release "$RETIRED_DIR" "$RETIRED_ID"
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
					"$ARCHIVE_MANIFEST"
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
		"$GH" release verify-asset "$ARCHIVE_TAG" "$ARCHIVE_FILE" \
			--repo "$ARCHIVE_REPOSITORY" >/dev/null || \
			fail "uploaded archive asset differs from the verified local archive: $ARCHIVE_TAG"
		verify_published_archive "$ARCHIVE_TAG" "$ARCHIVE_ASSET" \
			"$ARCHIVE_MANIFEST_ASSET" "$ARCHIVE_CHECKSUM_ASSET" \
			"$ARCHIVE_MANIFEST"
	fi

	read_active_release_id
	[ "$ACTIVE_RELEASE_ID" = "$ARCHIVE_ACTIVE_RELEASE_ID" ] || \
		fail 'active selector changed during GitHub archival; inactive release retained'
	validate_retired_release "$RETIRED_DIR" "$RETIRED_ID"
	case "$RETIRED_DIR" in
		"$BIRD"/bird-releases/"$RETIRED_ID") ;;
		*) fail "refusing to remove unsafe archived release path: $RETIRED_DIR" ;;
	esac
	printf 'Archived inactive release %s to private GitHub release %s/%s.\n' \
		"$RETIRED_ID" "$ARCHIVE_REPOSITORY" "$ARCHIVE_TAG"
	rm -rf "$RETIRED_DIR"
	[ ! -e "$RETIRED_DIR" ] && [ ! -L "$RETIRED_DIR" ] || \
		fail "verified archive was published but inactive card release could not be removed: $RETIRED_ID"
	sync
	printf 'Reclaimed inactive card release: %s\n' "$RETIRED_ID"
}

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
	select_retirement_candidate
fi
require_free_space "$WORK_ROOT_REAL" "$HOST_REQUIRED_BYTES" 'kernel/work'
require_free_space "$DATA" "$DATA_REQUIRED_BYTES" 'BIRD-DATA'

printf 'Selected release ID: %s\n' "$RELEASE_ID"
printf 'Build mode: %s\n' "$MODE"
printf 'Output directory: %s\n' "$OUTPUT"
printf 'Card identity: /dev/%s (p1 BIRD, p6 BIRD-DATA)\n' "$WHOLE"
if [ "$ARCHIVE_NEEDED" -eq 1 ]; then
	printf 'Retirement plan: archive inactive %s to %s, then reclaim %s bytes.\n' \
		"$RETIRED_ID" "$ARCHIVE_REPOSITORY" "$RETIRED_BYTES"
fi

run_builder_preflight() {
	if [ "$MODE" = profile ]; then
		BIRD_BUILD_PREFLIGHT_ONLY=1 BIRD_LAUNCHER_PROFILE=profile \
		BIRD_RELEASE_ID="$RELEASE_ID" SOURCE="$SOURCE" SYSTEM_SOURCE="$SYSTEM_SOURCE" \
		STORAGE="$STORAGE_SOURCE" SYSTEM_TREE="$SYSTEM_TREE" OUTPUT="$OUTPUT" \
		CLANG="$CLANG" LLD="$LLD" READELF="$READELF" \
		FALLBACK_KERNEL="$FALLBACK_KERNEL" OFFICIAL_INIT="$OFFICIAL_INIT" \
		JOYPAD="$JOYPAD" INIT_BUSYBOX="$INIT_BUSYBOX" \
		PORTMASTER_ARCHIVE="$PORTMASTER_ARCHIVE" "$BUILDER"
		return
	fi
	(
		unset BIRD_LAUNCHER_PROFILE
		BIRD_BUILD_PREFLIGHT_ONLY=1 BIRD_RELEASE_ID="$RELEASE_ID" \
		SOURCE="$SOURCE" SYSTEM_SOURCE="$SYSTEM_SOURCE" STORAGE="$STORAGE_SOURCE" \
		SYSTEM_TREE="$SYSTEM_TREE" OUTPUT="$OUTPUT" CLANG="$CLANG" LLD="$LLD" \
		READELF="$READELF" FALLBACK_KERNEL="$FALLBACK_KERNEL" \
		OFFICIAL_INIT="$OFFICIAL_INIT" JOYPAD="$JOYPAD" INIT_BUSYBOX="$INIT_BUSYBOX" \
		PORTMASTER_ARCHIVE="$PORTMASTER_ARCHIVE" "$BUILDER"
	)
}
run_builder_preflight || fail 'canonical pinned-input preflight failed; no build or deployment was attempted'

if [ "$DRY_RUN" -eq 1 ]; then
	if [ "$ARCHIVE_NEEDED" -eq 1 ]; then
		printf 'Dry run: would archive and verify inactive release %s before reclaiming it.\n' \
			"$RETIRED_ID"
	fi
	if [ -e "$OUTPUT" ] || [ -L "$OUTPUT" ]; then
		printf 'Dry run: would validate and remove matching stale output: %s\n' "$OUTPUT"
	fi
	printf 'Dry run: would run canonical builder: %s\n' "$BUILDER"
	printf 'Dry run: would validate deploy-manifest.tsv, then run updater: %s\n' "$UPDATER"
	printf 'Launcher SHA-256: not built (dry run)\n'
	printf 'Manifest SHA-256: not built (dry run)\n'
	printf 'Deployment result: not run (dry run)\n'
	exit 0
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
	archive_and_remove_retired_release
	if [ "$HOST_TEST_MODE" -eq 1 ]; then
		BIRD_POST_ARCHIVE_BYTES=$((BIRD_EFFECTIVE_BYTES + RETIRED_BYTES))
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
		SOURCE="$SOURCE" SYSTEM_SOURCE="$SYSTEM_SOURCE" STORAGE="$STORAGE_SOURCE" \
		SYSTEM_TREE="$SYSTEM_TREE" OUTPUT="$OUTPUT" CLANG="$CLANG" LLD="$LLD" \
		READELF="$READELF" FALLBACK_KERNEL="$FALLBACK_KERNEL" \
		OFFICIAL_INIT="$OFFICIAL_INIT" JOYPAD="$JOYPAD" INIT_BUSYBOX="$INIT_BUSYBOX" \
		PORTMASTER_ARCHIVE="$PORTMASTER_ARCHIVE" "$BUILDER"
		return
	fi
	(
		unset BIRD_LAUNCHER_PROFILE
		BIRD_RELEASE_ID="$RELEASE_ID" SOURCE="$SOURCE" SYSTEM_SOURCE="$SYSTEM_SOURCE" \
		STORAGE="$STORAGE_SOURCE" SYSTEM_TREE="$SYSTEM_TREE" OUTPUT="$OUTPUT" \
		CLANG="$CLANG" LLD="$LLD" READELF="$READELF" \
		FALLBACK_KERNEL="$FALLBACK_KERNEL" OFFICIAL_INIT="$OFFICIAL_INIT" \
		JOYPAD="$JOYPAD" INIT_BUSYBOX="$INIT_BUSYBOX" \
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
	awk -F '\t' -v expected_release="$RELEASE_ID" '
		function safe_path(path) {
			return path ~ /^[A-Za-z0-9._\/-]+$/ && path !~ /(^|\/)\.\.?($|\/)/
		}
		$1 == "schema" {if (NF != 2 || $2 != "bird-deploy-v1" || schema++) exit 1; next}
		$1 == "release" {if (NF != 2 || $2 != expected_release || release++) exit 1; next}
		$1 == "target-mode-policy" {if (NF != 2 || $2 != "fat-capability" || policy++) exit 1; next}
		$1 == "source-commit" {if (NF != 3 || source++) exit 1; next}
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
			print "file\t" $2; files++; next
		}
		{exit 1}
		END {if (schema != 1 || release != 1 || policy != 1 || source != 1 || inputs != 15 || files < 1) exit 1}
	' "$MANIFEST" >"$RECORDS" || fail 'canonical deploy manifest is malformed or has the wrong release ID'
	awk -F '\t' '$1 == "file" || $1 == "dir" {print $2}' "$RECORDS" | \
		LC_ALL=C sort | uniq -d >"$DUPLICATES"
	[ ! -s "$DUPLICATES" ] || fail 'canonical deploy manifest has duplicate paths'
	awk -F '\t' '$1 == "input" {print $2}' "$RECORDS" | LC_ALL=C sort \
		>"$RUN_TEMP/manifest-inputs"
	printf '%s\n' KERNEL KERNEL.fallback PortMaster.zip \
		PortMaster/PortMaster.sh PortMaster/funcs.txt PortMaster/harbourmaster \
		PortMaster/mod_ROCKNIX.txt PortMaster/pugwash ROCKNIX-STORAGE \
		ROCKNIX-SYSTEM dtb.img initramfs/busybox initramfs/init \
		rocknix-singleadc-joypad.ko usr/bin/autostart | LC_ALL=C sort \
		>"$RUN_TEMP/expected-inputs"
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
	"$UPDATER"; then
	fail "deployment failed; the previous selector remains authoritative unless the updater reported a verified post-selector commit. Build output retained at: $OUTPUT"
fi

is_regular_file "$INSTALLED_RELEASE/.complete" || fail 'deployed completion marker is missing or unsafe'
[ "$(cat "$INSTALLED_RELEASE/.complete")" = "$MANIFEST_SHA" ] || fail 'deployed completion marker does not match the build manifest'
is_regular_file "$INSTALLED_RELEASE/deploy-manifest.tsv" || fail 'deployed canonical manifest is missing or unsafe'
[ "$(sha256 "$INSTALLED_RELEASE/deploy-manifest.tsv")" = "$MANIFEST_SHA" ] || fail 'deployed canonical manifest hash changed'
grep -Fq "bird_release=$RELEASE_ID" "$BIRD/extlinux/extlinux.conf" || \
	fail 'active selector does not name the deployed release'

printf 'Deployment result: %s\n' "$DEPLOY_RESULT"
printf '\nNext steps:\n'
printf '  1. Eject safely: diskutil eject /dev/%s\n' "$WHOLE"
printf '  2. Insert the card in the RG34XX-SP and boot normally.\n'
if [ "$MODE" = profile ]; then
	printf '  3. After testing, reinsert the card and collect:\n'
	printf '     %s/MUOS/Bird/log/early-initramfs-latest.log\n' "$DATA"
	printf '     %s/MUOS/Bird/log/stock-root-supervisor.log\n' "$DATA"
else
	printf '  3. If behavior changes, retain the selected release ID and card logs for comparison.\n'
fi
