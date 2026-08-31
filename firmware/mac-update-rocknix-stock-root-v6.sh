#!/bin/sh
# Guarded deployment of the compatibility-first stock-root milestone. P5 and
# content bytes stay untouched. V6.23 installs one immutable, manifest-verified
# release and activates it with one extlinux selector rename.
# It retains the exact kernel and complete working ROCKNIX userspace.
# The exact ROCKNIX writable filesystem remains a loop image on p6, and the
# alternate boot assets are removed after the versioned selector commits.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/BIRD-DATA}
CANDIDATE=${CANDIDATE:-$ROOT/kernel/work/bird-rocknix-stock-root-${BIRD_RELEASE_ID:-v6.23}/card}
MANIFEST=${MANIFEST:-$CANDIDATE/../deploy-manifest.tsv}
STORAGE_SOURCE=${STORAGE_SOURCE:-$HOME/rocknix-reference-result/storage.ext4}
BIRD_HOST_TEST_MODE=${BIRD_HOST_TEST_MODE:-0}
BIRD_DEVICE_INFO=${BIRD_DEVICE_INFO:-}
BIRD_TEST_FAILPOINT=${BIRD_TEST_FAILPOINT:-}
BIRD_TEST_LOCK_GATE=${BIRD_TEST_LOCK_GATE:-}
BIRD_TEST_MANIFEST_GATE=${BIRD_TEST_MANIFEST_GATE:-}
PORTMASTER_PROVIDER_MANIFEST=${BIRD_TEST_PORTMASTER_PROVIDER_MANIFEST:-$ROOT/kernel/rocknix/stock-root/portmaster-provider.manifest.tsv}
PORTMASTER_PROVIDER_VERIFIER=$ROOT/kernel/rocknix/stock-root/verify-portmaster-provider.sh
RELEASE_ID=${BIRD_RELEASE_ID:-v6.23}
RUNTIME_ROOT=$DATA/Bird/runtime
RUNTIME=$RUNTIME_ROOT/$RELEASE_ID/ROCKNIX-SYSTEM
LEGACY_RUNTIME=$DATA/MUOS/runtime/ROCKNIX-SYSTEM
SYSTEM_INSTALL_SOURCE=${SYSTEM_INSTALL_SOURCE:-$RUNTIME}
STORAGE_TARGET=$DATA/MUOS/runtime/ROCKNIX-STORAGE
LEGACY_RUNTIME_BYTES=${BIRD_TEST_LEGACY_RUNTIME_BYTES:-1206476800}
LEGACY_RUNTIME_SHA=${BIRD_TEST_LEGACY_RUNTIME_SHA:-6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

case "$RELEASE_ID" in
	''|[![:alnum:]]*|*[![:alnum:]._-]*) fail "unsafe Bird release ID: $RELEASE_ID" ;;
esac
[ "${#RELEASE_ID}" -le 64 ] || fail 'Bird release ID is longer than 64 bytes'
[ "$(printf '%s' "$RELEASE_ID" | LC_ALL=C tr '[:upper:]' '[:lower:]')" != dev-current ] || \
	fail 'production release ID dev-current is reserved; run ./dev-build-and-deploy.sh --clean before production deployment'

case "$BIRD_HOST_TEST_MODE" in
	0)
		[ -z "$BIRD_DEVICE_INFO" ] || fail 'device metadata override requires host-test mode'
		[ -z "$BIRD_TEST_FAILPOINT" ] || fail 'failure injection requires host-test mode'
		[ -z "$BIRD_TEST_LOCK_GATE" ] || fail 'lock gate requires host-test mode'
		[ -z "$BIRD_TEST_MANIFEST_GATE" ] || fail 'manifest gate requires host-test mode'
		[ -z "${BIRD_TEST_PORTMASTER_PROVIDER_MANIFEST:-}" ] || \
			fail 'PortMaster provider manifest override requires host-test mode'
		[ -z "${BIRD_TEST_LEGACY_RUNTIME_BYTES:-}${BIRD_TEST_LEGACY_RUNTIME_SHA:-}" ] || \
			fail 'legacy SYSTEM identity override requires host-test mode'
		;;
	1)
		[ -n "$BIRD_DEVICE_INFO" ] || fail 'host-test device metadata is required'
		case "$BIRD:$DATA" in
			/var/folders/*:/var/folders/*|/private/tmp/*:/private/tmp/*|/tmp/*:/tmp/*) ;;
			*) fail 'host-test volumes must be temporary fixtures' ;;
		esac
		case "$BIRD_DEVICE_INFO" in
			/var/folders/*|/private/tmp/*|/tmp/*) ;;
			*) fail 'host-test device metadata must be a temporary fixture' ;;
		esac
		if [ -n "$BIRD_TEST_LOCK_GATE" ]; then
			case "$BIRD_TEST_LOCK_GATE" in
				/var/folders/*|/private/tmp/*|/tmp/*) ;;
				*) fail 'host-test lock gate must be a temporary fixture' ;;
			esac
		fi
		if [ -n "$BIRD_TEST_MANIFEST_GATE" ]; then
			case "$BIRD_TEST_MANIFEST_GATE" in
				/var/folders/*|/private/tmp/*|/tmp/*) ;;
				*) fail 'host-test manifest gate must be a temporary fixture' ;;
			esac
		fi
		if [ -n "${BIRD_TEST_PORTMASTER_PROVIDER_MANIFEST:-}" ]; then
			case "$PORTMASTER_PROVIDER_MANIFEST" in
				/var/folders/*|/private/tmp/*|/tmp/*) ;;
				*) fail 'host-test PortMaster provider manifest must be a temporary fixture' ;;
			esac
		fi
		;;
	*) fail 'invalid Bird host-test mode' ;;
esac

test_failpoint() {
	[ "$BIRD_HOST_TEST_MODE" = 1 ] && [ "$BIRD_TEST_FAILPOINT" = "$1" ] || return 0
	fail "host-only injected failure: $1"
}

test_failpoint_active() {
	[ "$BIRD_HOST_TEST_MODE" = 1 ] && [ "$BIRD_TEST_FAILPOINT" = "$1" ]
}

# shellcheck source=mac-stock-root-card-identity.sh
. "$ROOT/firmware/mac-stock-root-card-identity.sh"

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

file_bytes() {
	stat -f '%z' "$1"
}

file_mode() {
	stat -f '%Lp' "$1"
}

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
	# The development workflow publishes its initial copy through a hidden
	# same-filesystem sibling. SIGKILL or power loss can leave that directory
	# behind, and generic immutable-release enumeration intentionally ignores
	# hidden entries. Reserve only its exact normalized prefix here.
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

ext4_magic() {
	od -An -tx1 -j 1080 -N 2 "$1" | tr -d ' \n'
}

[ -d "$BIRD" ] && [ ! -L "$BIRD" ] || fail "BIRD volume missing or unsafe: $BIRD"
[ -d "$DATA" ] && [ ! -L "$DATA" ] || fail "data volume missing or unsafe: $DATA"

# The production updater may be invoked directly, so enforce the same mutable
# development boundary as the top-level production command. This runs before
# manifest snapshots, the card lock, stale-stage cleanup, provider checkpoints,
# release publication, or selector writes.
reject_dev_current_production_state

[ -d "$CANDIDATE" ] && [ ! -L "$CANDIDATE" ] || fail "built candidate missing or unsafe: $CANDIDATE"
is_regular_file "$MANIFEST" || fail "canonical deploy manifest missing or unsafe: $MANIFEST"
is_regular_file "$STORAGE_SOURCE" || fail 'reference ROCKNIX storage image missing or unsafe'
is_regular_file "$SYSTEM_INSTALL_SOURCE" || \
	fail 'canonical SYSTEM install source is missing or unsafe'

VERIFY_WORK=$(mktemp -d "${TMPDIR:-/tmp}/bird-deploy.XXXXXX") || \
	fail 'could not create manifest verification directory'
RELEASE_STAGE=
PORTMASTER_MARKER_TEMP=
RUNTIME_TEMP=
BIRD_CARD_LOCK_OWNED=0
# shellcheck source=mac-bird-card-lock.sh
. "$ROOT/firmware/mac-bird-card-lock.sh"

cleanup() {
	if [ -n "$RELEASE_STAGE" ]; then
		case "$RELEASE_STAGE" in
			"$BIRD"/bird-releases/.*.new.*) rm -rf "$RELEASE_STAGE" ;;
		esac
	fi
	if [ -n "$PORTMASTER_MARKER_TEMP" ]; then
		case "$PORTMASTER_MARKER_TEMP" in
			"$DATA"/ROMS/Ports/.bird-portmaster-marker.new.*)
				rm -f "$PORTMASTER_MARKER_TEMP" 2>/dev/null || :
				;;
		esac
	fi
	if [ -n "$RUNTIME_TEMP" ]; then
		case "$RUNTIME_TEMP" in
			"$RUNTIME_ROOT"/*/.ROCKNIX-SYSTEM.new.*)
				rm -f "$RUNTIME_TEMP" 2>/dev/null || :
				;;
		esac
	fi
	bird_card_lock_release
	rm -rf "$VERIFY_WORK"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# The caller-owned manifest path is mutable. Snapshot it once into this
# process-private directory, then parse, hash, stage and verify only that
# immutable pathname. A concurrent source rename cannot change paths after
# validation.
MANIFEST_SOURCE=$MANIFEST
MANIFEST=$VERIFY_WORK/deploy-manifest.snapshot.tsv
COPYFILE_DISABLE=1 cp -f "$MANIFEST_SOURCE" "$MANIFEST" || \
	fail 'could not snapshot canonical deploy manifest'
is_regular_file "$MANIFEST" || fail 'private deploy manifest snapshot is unsafe'

MANIFEST_RECORDS=$VERIFY_WORK/manifest-records
MANIFEST_PATHS=$VERIFY_WORK/manifest-paths
MANIFEST_DIRS=$VERIFY_WORK/manifest-dirs
MANIFEST_INPUTS=$VERIFY_WORK/manifest-inputs
CANDIDATE_PATHS=$VERIFY_WORK/candidate-paths
CANDIDATE_DIRS=$VERIFY_WORK/candidate-dirs
DUPLICATE_PATHS=$VERIFY_WORK/duplicate-paths
SPECIAL_PATHS=$VERIFY_WORK/special-paths
TAB=$(printf '\t')

# Fail closed on unknown records, malformed fields, unsafe paths and duplicate
# destinations. `file` plus explicit empty-`dir` records are the sole deploy
# inventory used below; input records are the sole external-byte contract.
awk -F '\t' -v expected_release="$RELEASE_ID" '
	function safe_path(path) {
		return path ~ /^[A-Za-z0-9._\/-]+$/ &&
		       path !~ /(^|\/)\.\.?($|\/)/
	}
	$1 == "schema" {
		if (NF != 2 || $2 != "bird-deploy-v1" || schema++) exit 1
		next
	}
	$1 == "release" {
		if (NF != 2 || $2 != expected_release || release++) exit 1
		next
	}
	$1 == "target-mode-policy" {
		if (NF != 2 || $2 != "fat-capability" || policy++) exit 1
		next
	}
	$1 == "source-commit" {
		if (NF != 3 || source++) exit 1
		next
	}
	$1 == "artifact" {
		if (NF != 4 || ($2 != "device-contract" && $2 != "catalog") ||
		    !safe_path($3) || length($4) != 64 || $4 ~ /[^0-9a-f]/) exit 1
		if ($2 == "device-contract") device_contract++
		if ($2 == "catalog") catalog++
		print "artifact\t" $2 "\t" $3 "\t" $4
		artifacts++
		next
	}
	$1 == "input" {
		if (NF != 6 || !safe_path($2) ||
		    $3 !~ /^[0-7][0-7][0-7]$/ || $4 !~ /^[0-9]+$/ ||
		    length($5) != 64 || $5 ~ /[^0-9a-f]/ || $6 == "") exit 1
		print "input\t" $2
		inputs++
		next
	}
	$1 == "dir" {
		if (NF != 3 || !safe_path($2) ||
		    $3 !~ /^[0-7][0-7][0-7]$/) exit 1
		print "dir\t" $2
		dirs++
		next
	}
	$1 == "file" {
		if (NF != 5 || !safe_path($2) ||
		    $3 !~ /^[0-7][0-7][0-7]$/ ||
		    $4 !~ /^[0-9]+$/ || length($5) != 64 || $5 ~ /[^0-9a-f]/) exit 1
		print "file\t" $2 "\t" $3 "\t" $4 "\t" $5
		files++
		next
	}
	{ exit 1 }
	END {
		if (schema != 1 || release != 1 || policy != 1 || source != 1 ||
		    (inputs != 14 && inputs != 15) || files < 1 ||
		    (artifacts != 0 && artifacts != 2) ||
		    (artifacts == 2 && (device_contract != 1 || catalog != 1))) exit 1
	}
' "$MANIFEST" >"$MANIFEST_RECORDS" || fail 'canonical deploy manifest is malformed'

if [ "$(awk -F '\t' '$1 == "artifact" {count++} END {print count + 0}' \
	"$MANIFEST_RECORDS")" -eq 2 ]; then
	DEVICE_CONTRACT_PATH=$(awk -F '\t' '$1 == "artifact" && $2 == "device-contract" {print $3}' \
		"$MANIFEST_RECORDS")
	DEVICE_CONTRACT_SHA=$(awk -F '\t' '$1 == "artifact" && $2 == "device-contract" {print $4}' \
		"$MANIFEST_RECORDS")
	CATALOG_ARTIFACT_PATH=$(awk -F '\t' '$1 == "artifact" && $2 == "catalog" {print $3}' \
		"$MANIFEST_RECORDS")
	[ "$DEVICE_CONTRACT_PATH" = bird/bird-device-contract.tsv ] || \
		fail 'device-contract artifact path changed'
	[ "$CATALOG_ARTIFACT_PATH" = launcher/catalog.generated.h ] || \
		fail 'catalog artifact path changed'
	awk -F '\t' -v path="$DEVICE_CONTRACT_PATH" -v digest="$DEVICE_CONTRACT_SHA" \
		'$1 == "file" && $2 == path && $5 == digest {found++} END {exit found != 1}' \
		"$MANIFEST_RECORDS" || fail 'device-contract artifact does not match its file record'
fi

awk -F '\t' '$1 == "input" {print $2}' "$MANIFEST_RECORDS" | \
	LC_ALL=C sort >"$MANIFEST_INPUTS"
printf '%s\n' KERNEL PortMaster.zip \
	PortMaster/PortMaster.sh PortMaster/funcs.txt PortMaster/harbourmaster \
	PortMaster/mod_ROCKNIX.txt PortMaster/pugwash ROCKNIX-STORAGE \
	ROCKNIX-SYSTEM dtb.img initramfs/busybox initramfs/init \
	rocknix-singleadc-joypad.ko usr/bin/autostart | \
	LC_ALL=C sort >"$VERIFY_WORK/expected-inputs"
if grep -Fqx source-kernel-parity.tsv "$MANIFEST_INPUTS"; then
	printf '%s\n' source-kernel-parity.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
elif grep -Fqx source-kernel-builtin-input.tsv "$MANIFEST_INPUTS"; then
	printf '%s\n' source-kernel-builtin-input.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
elif grep -Fqx source-kernel-single-gpio-read.tsv "$MANIFEST_INPUTS"; then
	printf '%s\n' source-kernel-single-gpio-read.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
elif grep -Fqx source-kernel-single-input-sync.tsv "$MANIFEST_INPUTS"; then
	printf '%s\n' source-kernel-single-input-sync.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
elif grep -Fqx source-kernel-changed-input-sync.tsv "$MANIFEST_INPUTS"; then
	printf '%s\n' source-kernel-changed-input-sync.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
elif grep -Fqx source-kernel-fixed-gpio-fastpath.tsv "$MANIFEST_INPUTS"; then
	printf '%s\n' source-kernel-fixed-gpio-fastpath.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
elif grep -Fqx source-kernel-irq-buttons.tsv "$MANIFEST_INPUTS"; then
	printf '%s\n' source-kernel-irq-buttons.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
elif grep -Fqx source-kernel-irq-buttons-lz4.tsv "$MANIFEST_INPUTS"; then
	# Why before: production input validation enumerates every accepted kernel
	# authority so an unknown or extra manifest input always fails closed.
	# Why change: the reviewed LZ4 payload has its own exact authority record and
	# must be admitted as the one optional source-kernel input.
	printf '%s\n' source-kernel-irq-buttons-lz4.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
elif grep -Fqx source-kernel-irq-buttons-no-raid6-benchmark-lz4.tsv "$MANIFEST_INPUTS"; then
	printf '%s\n' source-kernel-irq-buttons-no-raid6-benchmark-lz4.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
elif grep -Fqx source-kernel-irq-buttons-no-raid6-deferred-wifi-lz4.tsv "$MANIFEST_INPUTS"; then
	printf '%s\n' source-kernel-irq-buttons-no-raid6-deferred-wifi-lz4.tsv >>"$VERIFY_WORK/expected-inputs"
	LC_ALL=C sort -o "$VERIFY_WORK/expected-inputs" \
		"$VERIFY_WORK/expected-inputs"
fi
cmp "$VERIFY_WORK/expected-inputs" "$MANIFEST_INPUTS" >/dev/null || \
	fail 'canonical deploy manifest input set is incomplete or duplicated'
awk -F '\t' '$1 == "file" || $1 == "dir" {print $2}' \
	"$MANIFEST_RECORDS" | LC_ALL=C sort | uniq -d >"$DUPLICATE_PATHS"
[ ! -s "$DUPLICATE_PATHS" ] || fail 'canonical deploy manifest has duplicate paths'
awk -F '\t' '$1 == "file" {print $2}' "$MANIFEST_RECORDS" | \
	LC_ALL=C sort >"$MANIFEST_PATHS"
awk -F '\t' '$1 == "dir" {print $2}' "$MANIFEST_RECORDS" | \
	LC_ALL=C sort >"$MANIFEST_DIRS"
find "$CANDIDATE" -mindepth 1 ! -type f ! -type d -print >"$SPECIAL_PATHS" || \
	fail 'could not inventory candidate node types'
[ ! -s "$SPECIAL_PATHS" ] || fail 'candidate contains a symlink or special node'
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

while IFS="$TAB" read -r KIND REL_PATH MODE BYTES HASH REST; do
	if [ "$KIND" = dir ]; then
		[ -d "$CANDIDATE/$REL_PATH" ] && [ ! -L "$CANDIDATE/$REL_PATH" ] || \
			fail "candidate directory missing or unsafe: $REL_PATH"
		[ "$(file_mode "$CANDIDATE/$REL_PATH")" = "$MODE" ] || \
			fail "candidate directory mode changed: $REL_PATH"
		continue
	fi
	[ "$KIND" = file ] || continue
	is_regular_file "$CANDIDATE/$REL_PATH" || fail "candidate payload missing or unsafe: $REL_PATH"
	[ "$(file_mode "$CANDIDATE/$REL_PATH")" = "$MODE" ] || \
		fail "candidate mode changed: $REL_PATH"
	[ "$(file_bytes "$CANDIDATE/$REL_PATH")" = "$BYTES" ] || \
		fail "candidate size changed: $REL_PATH"
	[ "$(sha256 "$CANDIDATE/$REL_PATH")" = "$HASH" ] || \
		fail "candidate digest changed: $REL_PATH"
done <"$MANIFEST"

manifest_input_field() {
	awk -F '\t' -v name="$1" -v field="$2" \
		'$1 == "input" && $2 == name {print $field}' "$MANIFEST"
}

ROCKNIX_KERNEL_SHA=$(manifest_input_field KERNEL 5)
DTB_SHA=$(manifest_input_field dtb.img 5)
RUNTIME_SHA=$(manifest_input_field ROCKNIX-SYSTEM 5)
RUNTIME_BYTES=$(manifest_input_field ROCKNIX-SYSTEM 4)
STORAGE_BYTES=$(manifest_input_field ROCKNIX-STORAGE 4)
STORAGE_SHA=$(manifest_input_field ROCKNIX-STORAGE 5)
PORTMASTER_PUGWASH_BYTES=$(manifest_input_field PortMaster/pugwash 4)
PORTMASTER_PUGWASH_SHA=$(manifest_input_field PortMaster/pugwash 5)
PORTMASTER_SH_BYTES=$(manifest_input_field PortMaster/PortMaster.sh 4)
PORTMASTER_SH_SHA=$(manifest_input_field PortMaster/PortMaster.sh 5)
PORTMASTER_MOD_BYTES=$(manifest_input_field PortMaster/mod_ROCKNIX.txt 4)
PORTMASTER_MOD_SHA=$(manifest_input_field PortMaster/mod_ROCKNIX.txt 5)
PORTMASTER_FUNCS_BYTES=$(manifest_input_field PortMaster/funcs.txt 4)
PORTMASTER_FUNCS_SHA=$(manifest_input_field PortMaster/funcs.txt 5)
PORTMASTER_HARBOURMASTER_BYTES=$(manifest_input_field PortMaster/harbourmaster 4)
PORTMASTER_HARBOURMASTER_SHA=$(manifest_input_field PortMaster/harbourmaster 5)

if [ -n "$BIRD_TEST_MANIFEST_GATE" ]; then
	printf '%s\n' "$$" >"$BIRD_TEST_MANIFEST_GATE/snapshot-ready"
	MANIFEST_GATE_WAIT=0
	while [ ! -f "$BIRD_TEST_MANIFEST_GATE/release-snapshot" ]; do
		MANIFEST_GATE_WAIT=$((MANIFEST_GATE_WAIT + 1))
		[ "$MANIFEST_GATE_WAIT" -le 400 ] || \
			fail 'host-only manifest snapshot gate timed out'
		sleep 0.02
	done
fi

validate_stock_root_card_identity

NAMESPACE_MARKER=$DATA/Bird/namespace-v1.tsv
[ -f "$NAMESPACE_MARKER" ] && [ ! -L "$NAMESPACE_MARKER" ] &&
	[ "$(wc -l <"$NAMESPACE_MARKER" | tr -d ' ')" -eq 2 ] &&
	grep -Fqx 'revision	bird-canonical-namespace-v1' "$NAMESPACE_MARKER" &&
	grep -Fqx 'state	committed' "$NAMESPACE_MARKER" ||
	fail 'canonical namespace v1 is not committed'

# Serialize every host-side card mutation with the same inherited advisory
# transaction lock used by the explicit Ports migration. The owner symlink is
# diagnostic; PID plus process-start identity prevents PID-reuse confusion.
BIRD_PRODUCTION_LOCKED_WHOLE=$WHOLE
bird_card_lock_acquire
if test_failpoint_active hold-after-lock; then
	[ -d "$BIRD_TEST_LOCK_GATE" ] || fail 'host-only lock gate directory is missing'
	printf '%s\n' "$$" >"$BIRD_TEST_LOCK_GATE/owner-ready"
	LOCK_GATE_WAIT=0
	while [ ! -f "$BIRD_TEST_LOCK_GATE/release-owner" ]; do
		LOCK_GATE_WAIT=$((LOCK_GATE_WAIT + 1))
		[ "$LOCK_GATE_WAIT" -le 400 ] || fail 'host-only lock gate timed out'
		sleep 0.02
	done
fi
# A development transaction may have completed after the early read-only
# preflight. Revalidate both card identity and the reserved mutable-release
# boundary while this updater owns the whole-card mutation lock.
validate_stock_root_card_identity
[ "$WHOLE" = "$BIRD_PRODUCTION_LOCKED_WHOLE" ] || \
	fail 'card identity changed after acquiring its production transaction lock'
reject_dev_current_production_state
if test_failpoint_active orphan-child-after-lock; then
	[ -d "$BIRD_TEST_LOCK_GATE" ] || fail 'host-only orphan gate directory is missing'
	BIRD_ORPHAN_GATE=$BIRD_TEST_LOCK_GATE \
	BIRD_ORPHAN_TARGET=$DATA/orphan-mutator-probe \
	/bin/sh -c '
		printf "%s\n" "$$" >"$BIRD_ORPHAN_GATE/mutator-ready"
		while [ ! -f "$BIRD_ORPHAN_GATE/release-mutator" ]; do
			printf x >>"$BIRD_ORPHAN_TARGET"
			sleep 0.02
		done
	' &
	printf '%s\n' "$$" >"$BIRD_TEST_LOCK_GATE/owner-ready"
	while :; do sleep 1; done
fi

# Refuse an unknown network-updated provider before cleaning a stale candidate
# stage or performing any other deployment mutation. The transaction lock makes
# this exact verified inventory authoritative until the updater exits.
LEGACY_PORTS=$DATA/ports
NATIVE_PORTS=$DATA/ROMS/Ports
if [ -d "$LEGACY_PORTS" ] &&
	find "$LEGACY_PORTS" -mindepth 1 -maxdepth 1 -print | grep -q .; then
	fail 'legacy /ports data must be migrated separately before runtime deployment'
fi
PORTMASTER=$NATIVE_PORTS/PortMaster
is_regular_file "$PORTMASTER_PROVIDER_MANIFEST" || \
	fail 'pinned PortMaster provider manifest is missing or unsafe'
is_regular_file "$PORTMASTER_PROVIDER_VERIFIER" || \
	fail 'PortMaster provider verifier is missing or unsafe'
for PORTMASTER_ADAPTER in control.txt oga_controls; do
	is_regular_file "$PORTMASTER/$PORTMASTER_ADAPTER" && \
		[ -s "$PORTMASTER/$PORTMASTER_ADAPTER" ] || \
		fail "PortMaster runtime adapter is incomplete or unsafe: $PORTMASTER_ADAPTER"
done
PORTMASTER_MARKER_VALUE=$(
	# The staged runtime redirects every provider execution to a fresh tmpfs
	# PYTHONPYCACHEPREFIX, so generated provider-local caches are never loaded.
	"$PORTMASTER_PROVIDER_VERIFIER" --allow-isolated-python-cache \
		"$PORTMASTER_PROVIDER_MANIFEST" "$PORTMASTER"
) || fail 'installed PortMaster provider is not a pinned complete revision'
PORTMASTER_MARKER=$PORTMASTER/.bird-release-complete
PORTMASTER_MARKER_STATE=legacy
if [ -e "$PORTMASTER_MARKER" ] || [ -L "$PORTMASTER_MARKER" ]; then
	is_regular_file "$PORTMASTER_MARKER" || \
		fail 'PortMaster completion marker is a symlink or special node'
	PORTMASTER_MARKER_BYTES=$(file_bytes "$PORTMASTER_MARKER")
	case "$PORTMASTER_MARKER_BYTES" in
		''|*[!0-9]*) fail 'PortMaster completion marker size is malformed' ;;
	esac
	[ "$PORTMASTER_MARKER_BYTES" -le 1024 ] || \
		fail 'PortMaster completion marker is unexpectedly large'
	if [ "$PORTMASTER_MARKER_BYTES" -gt 0 ]; then
		[ "$(wc -l <"$PORTMASTER_MARKER" | tr -d '[:space:]')" = 1 ] || \
			fail 'PortMaster completion marker must contain one newline-terminated record'
		if grep -Fqx "$PORTMASTER_MARKER_VALUE" "$PORTMASTER_MARKER"; then
			PORTMASTER_MARKER_STATE=exact
		elif grep -Eq '^bird-portmaster-v(1|2):[A-Za-z0-9:._/-]+$' \
			"$PORTMASTER_MARKER"; then
			PORTMASTER_MARKER_STATE=legacy
		elif grep -Eq '^bird-portmaster-v3:' "$PORTMASTER_MARKER"; then
			fail 'PortMaster v3 completion marker does not match the pinned revision'
		else
			fail 'PortMaster completion marker has an unrecognized format'
		fi
	fi
fi

# A SIGKILL between temporary publication and marker commit may leave this
# same-filesystem sibling behind. It is outside the provider inventory, and a
# later locked invocation removes only this exact validated temporary pattern.
for STALE_PORTMASTER_MARKER in \
	"$NATIVE_PORTS"/.bird-portmaster-marker.new.*; do
	[ -e "$STALE_PORTMASTER_MARKER" ] || [ -L "$STALE_PORTMASTER_MARKER" ] || break
	case "$STALE_PORTMASTER_MARKER" in
		"$NATIVE_PORTS"/.bird-portmaster-marker.new.*) ;;
		*) fail 'unsafe stale PortMaster marker path' ;;
	esac
	is_regular_file "$STALE_PORTMASTER_MARKER" || \
		fail 'stale PortMaster marker temporary is unsafe'
	rm -f "$STALE_PORTMASTER_MARKER" || \
		fail 'could not remove stale PortMaster marker temporary'
done

RELEASES=$BIRD/bird-releases
mkdir -p "$RELEASES"
for STALE_STAGE in "$RELEASES"/.$RELEASE_ID.new.*; do
	[ -e "$STALE_STAGE" ] || break
	case "$STALE_STAGE" in
		"$RELEASES"/.$RELEASE_ID.new.*) rm -rf "$STALE_STAGE" ;;
		*) fail 'unsafe stale release stage path' ;;
	esac
done

BIRD_FS=$(field "$BIRD" 'File System Personality')
case "$BIRD_FS" in
	*FAT*|*ExFAT*) BIRD_SYNTHETIC_MODES=1 ;;
	*) BIRD_SYNTHETIC_MODES=0 ;;
esac

verify_target_mode() {
	TARGET_PATH=$1
	EXPECTED=$2
	if [ "$BIRD_SYNTHETIC_MODES" -eq 0 ]; then
		[ "$(file_mode "$TARGET_PATH")" = "$EXPECTED" ]
		return
	fi

	# FAT does not persist per-file Unix mode bits.  Verify the effective owner
	# capabilities required by the intended manifest mode instead of demanding
	# a synthetic stat value that macOS cannot reproduce exactly.
	OWNER=$(printf '%s' "$EXPECTED" | cut -c1)
	[ -r "$TARGET_PATH" ] || return 1
	case "$OWNER" in 2|3|6|7) [ -w "$TARGET_PATH" ] || return 1 ;; esac
	case "$OWNER" in 1|3|5|7) [ -x "$TARGET_PATH" ] || return 1 ;; esac
	return 0
}

apply_target_metadata() {
	TARGET_PATH=$1
	EXPECTED=$2
	# FAT/ExFAT synthesize Unix modes.  chmod/xattr writes on macOS create
	# AppleDouble sidecars, so they are both meaningless and harmful there.
	if [ "$BIRD_SYNTHETIC_MODES" -eq 0 ]; then
		chmod "$EXPECTED" "$TARGET_PATH" 2>/dev/null || :
		xattr -c "$TARGET_PATH" 2>/dev/null || :
	fi
}

[ "$(sha256 "$CANDIDATE/KERNEL")" = "$ROCKNIX_KERNEL_SHA" ] || fail 'candidate KERNEL changed'
[ "$(sha256 "$CANDIDATE/dtb.img")" = "$DTB_SHA" ] || fail 'candidate DTB changed'
[ "$(file_bytes "$SYSTEM_INSTALL_SOURCE")" = "$RUNTIME_BYTES" ] || \
	fail 'canonical SYSTEM install source size changed'
[ "$(sha256 "$SYSTEM_INSTALL_SOURCE")" = "$RUNTIME_SHA" ] || \
	fail 'canonical SYSTEM install source changed'

# Publish the selected release's SYSTEM beside any currently bootable source.
# The selector is unchanged until this same-volume copy, rename and reread are
# complete. A future SYSTEM can therefore be staged without changing the bytes
# used by the currently selected release.
[ -d "$DATA/Bird" ] && [ ! -L "$DATA/Bird" ] || \
	fail 'canonical Bird data root is missing or unsafe'
mkdir -p "$RUNTIME_ROOT"
[ -d "$RUNTIME_ROOT" ] && [ ! -L "$RUNTIME_ROOT" ] || \
	fail 'canonical SYSTEM runtime root is unsafe'
RUNTIME_RELEASE_ROOT=$RUNTIME_ROOT/$RELEASE_ID
if [ -e "$RUNTIME_RELEASE_ROOT" ] || [ -L "$RUNTIME_RELEASE_ROOT" ]; then
	[ -d "$RUNTIME_RELEASE_ROOT" ] && [ ! -L "$RUNTIME_RELEASE_ROOT" ] || \
		fail 'release SYSTEM directory is unsafe'
else
	mkdir "$RUNTIME_RELEASE_ROOT"
fi
if is_regular_file "$RUNTIME"; then
	[ "$(file_bytes "$RUNTIME")" = "$RUNTIME_BYTES" ] && \
	[ "$(sha256 "$RUNTIME")" = "$RUNTIME_SHA" ] || \
		fail 'installed release SYSTEM differs from its manifest'
elif [ -e "$RUNTIME" ] || [ -L "$RUNTIME" ]; then
	fail 'release SYSTEM destination is unsafe'
else
	for STALE_RUNTIME in "$RUNTIME_RELEASE_ROOT"/.ROCKNIX-SYSTEM.new.*; do
		[ -e "$STALE_RUNTIME" ] || [ -L "$STALE_RUNTIME" ] || break
		case "$STALE_RUNTIME" in
			"$RUNTIME_RELEASE_ROOT"/.ROCKNIX-SYSTEM.new.*) ;;
			*) fail 'unsafe stale release SYSTEM stage path' ;;
		esac
		is_regular_file "$STALE_RUNTIME" || \
			fail 'stale release SYSTEM stage is unsafe'
		rm -f "$STALE_RUNTIME"
	done
	RUNTIME_TEMP=$RUNTIME_RELEASE_ROOT/.ROCKNIX-SYSTEM.new.$$
	[ ! -e "$RUNTIME_TEMP" ] && [ ! -L "$RUNTIME_TEMP" ] || \
		fail 'release SYSTEM staging path is occupied'
	COPYFILE_DISABLE=1 cp -f "$SYSTEM_INSTALL_SOURCE" "$RUNTIME_TEMP" || \
		fail 'could not stage release SYSTEM'
	[ "$(file_bytes "$RUNTIME_TEMP")" = "$RUNTIME_BYTES" ] && \
	[ "$(sha256 "$RUNTIME_TEMP")" = "$RUNTIME_SHA" ] || \
		fail 'staged release SYSTEM verification failed'
	sync
	mv "$RUNTIME_TEMP" "$RUNTIME"
	RUNTIME_TEMP=
	sync
	[ "$(file_bytes "$RUNTIME")" = "$RUNTIME_BYTES" ] && \
	[ "$(sha256 "$RUNTIME")" = "$RUNTIME_SHA" ] || \
		fail 'release SYSTEM commit verification failed'
fi
RUNTIME_SIDECAR=$RUNTIME_RELEASE_ROOT/._ROCKNIX-SYSTEM
if is_regular_file "$RUNTIME_SIDECAR"; then
	rm -f "$RUNTIME_SIDECAR"
elif [ -e "$RUNTIME_SIDECAR" ] || [ -L "$RUNTIME_SIDECAR" ]; then
	fail 'release SYSTEM AppleDouble is unsafe'
fi
sync
[ ! -e "$RUNTIME_SIDECAR" ] && [ ! -L "$RUNTIME_SIDECAR" ] || \
	fail 'release SYSTEM AppleDouble remains after publication'
[ "$(sha256 "$STORAGE_SOURCE")" = "$STORAGE_SHA" ] || fail 'reference STORAGE changed'
# PortMaster may update itself over the network, but an offline birdOS
# deployment accepts only a revision whose complete managed inventory has been
# imported into the repository manifest. Migrate stale empty/v1/v2 checkpoints
# only after that exact verification; never rewrite or replace provider bytes.
if [ "$PORTMASTER_MARKER_STATE" = legacy ]; then
	PORTMASTER_MARKER_TEMP=$NATIVE_PORTS/.bird-portmaster-marker.new.$$
	[ ! -e "$PORTMASTER_MARKER_TEMP" ] && [ ! -L "$PORTMASTER_MARKER_TEMP" ] || \
		fail 'PortMaster marker temporary path is occupied'
	(umask 077; set -C; printf '%s\n' "$PORTMASTER_MARKER_VALUE" \
		>"$PORTMASTER_MARKER_TEMP") 2>/dev/null || \
		fail 'PortMaster marker temporary publication failed'
	[ "$(cat "$PORTMASTER_MARKER_TEMP")" = "$PORTMASTER_MARKER_VALUE" ] || \
		fail 'PortMaster marker temporary verification failed'
	if test_failpoint_active kill-during-portmaster-marker-stage; then
		kill -KILL $$
	fi
	test_failpoint before-portmaster-marker-commit
	sync
	mv -f "$PORTMASTER_MARKER_TEMP" "$PORTMASTER_MARKER"
	PORTMASTER_MARKER_TEMP=
	sync
	[ "$(cat "$PORTMASTER_MARKER")" = "$PORTMASTER_MARKER_VALUE" ] || \
		fail 'PortMaster marker commit failed'
fi
[ "$("$PORTMASTER_PROVIDER_VERIFIER" --allow-isolated-python-cache \
	"$PORTMASTER_PROVIDER_MANIFEST" "$PORTMASTER")" = \
	"$PORTMASTER_MARKER_VALUE" ] || \
	fail 'PortMaster provider changed after marker publication'

CURRENT=missing
if is_regular_file "$BIRD/KERNEL"; then
	CURRENT=$(sha256 "$BIRD/KERNEL")
	case "$CURRENT" in
		"$ROCKNIX_KERNEL_SHA") ;;
		*) fail "unexpected legacy top-level KERNEL: $CURRENT" ;;
	esac
elif [ -e "$BIRD/KERNEL" ] || [ -L "$BIRD/KERNEL" ]; then
	fail 'legacy top-level KERNEL is a symlink or special node'
fi

if is_regular_file "$STORAGE_TARGET"; then
	[ "$(file_bytes "$STORAGE_TARGET")" = "$STORAGE_BYTES" ] || fail 'installed STORAGE size changed'
	[ "$(ext4_magic "$STORAGE_TARGET")" = 53ef ] || fail 'installed STORAGE is not ext4'
elif [ -e "$STORAGE_TARGET" ]; then
	fail 'installed STORAGE is a symlink or special node'
else
	COPYFILE_DISABLE=1 cp -f "$STORAGE_SOURCE" "$DATA/MUOS/runtime/.ROCKNIX-STORAGE.new"
	[ "$(sha256 "$DATA/MUOS/runtime/.ROCKNIX-STORAGE.new")" = "$STORAGE_SHA" ] || fail 'storage copy failed'
	sync
	mv -f "$DATA/MUOS/runtime/.ROCKNIX-STORAGE.new" "$STORAGE_TARGET"
	sync
	[ "$(sha256 "$STORAGE_TARGET")" = "$STORAGE_SHA" ] || \
		fail 'storage commit failed'
fi

RELEASE=$RELEASES/$RELEASE_ID
MANIFEST_SHA=$(sha256 "$MANIFEST")
mkdir -p "$BIRD/extlinux"

manifest_file_field() {
	REQUEST_PATH=$1
	FIELD_NUMBER=$2
	awk -F '\t' -v path="$REQUEST_PATH" -v field="$FIELD_NUMBER" \
		'$1 == "file" && $2 == path {print $field}' "$MANIFEST"
}

verify_release_file() {
	ROOT_PATH=$1
	RELATIVE=$2
	MODE=$3
	BYTES=$4
	HASH=$5
	TARGET=$ROOT_PATH/$RELATIVE
	is_regular_file "$TARGET" || fail "installed release file missing or unsafe: $RELATIVE"
	[ "$(file_bytes "$TARGET")" = "$BYTES" ] || fail "installed release size changed: $RELATIVE"
	[ "$(sha256 "$TARGET")" = "$HASH" ] || fail "installed release digest changed: $RELATIVE"
	verify_target_mode "$TARGET" "$MODE" || fail "installed release mode contract failed: $RELATIVE"
}

verify_release_dir() {
	ROOT_PATH=$1
	RELATIVE=$2
	MODE=$3
	TARGET=$ROOT_PATH/$RELATIVE
	[ -d "$TARGET" ] && [ ! -L "$TARGET" ] || \
		fail "installed release directory missing or unsafe: $RELATIVE"
	verify_target_mode "$TARGET" "$MODE" || \
		fail "installed release directory mode contract failed: $RELATIVE"
}

verify_release() {
	ROOT_PATH=$1
	[ -d "$ROOT_PATH" ] && [ ! -L "$ROOT_PATH" ] || \
		fail 'installed release root is missing or unsafe'
	is_regular_file "$ROOT_PATH/deploy-manifest.tsv" || fail 'installed canonical manifest missing or unsafe'
	is_regular_file "$ROOT_PATH/.complete" || fail 'installed release completion marker missing or unsafe'
	[ "$(cat "$ROOT_PATH/.complete")" = "$MANIFEST_SHA" ] || fail 'installed completion marker changed'
	[ "$(sha256 "$ROOT_PATH/deploy-manifest.tsv")" = "$MANIFEST_SHA" ] || fail 'installed canonical manifest changed'
	while IFS="$TAB" read -r KIND REL_PATH MODE BYTES HASH REST; do
		case "$KIND" in
			file) verify_release_file "$ROOT_PATH" "$REL_PATH" "$MODE" "$BYTES" "$HASH" ;;
			dir) verify_release_dir "$ROOT_PATH" "$REL_PATH" "$MODE" ;;
		esac
	done <"$MANIFEST"
	find "$ROOT_PATH" -mindepth 1 ! -type f ! -type d -print \
		>"$VERIFY_WORK/release-special-paths" || \
		fail 'could not inventory installed release node types'
	[ ! -s "$VERIFY_WORK/release-special-paths" ] || \
		fail 'installed release contains a symlink or special node'
	find "$ROOT_PATH" -type f ! -path "$ROOT_PATH/deploy-manifest.tsv" \
		! -path "$ROOT_PATH/.complete" -print | while IFS= read -r FILE; do
		printf '%s\n' "${FILE#"$ROOT_PATH"/}"
	done | LC_ALL=C sort >"$VERIFY_WORK/release-paths"
	if ! cmp "$MANIFEST_PATHS" "$VERIFY_WORK/release-paths" >/dev/null; then
		printf '%s\n' 'release paths present only in manifest (-) or install (+):' >&2
		comm -3 "$MANIFEST_PATHS" "$VERIFY_WORK/release-paths" >&2 || :
		fail 'installed release file set differs from canonical manifest'
	fi
	find "$ROOT_PATH" -mindepth 1 -type d -empty -print | while IFS= read -r DIRECTORY; do
		printf '%s\n' "${DIRECTORY#"$ROOT_PATH"/}"
	done | LC_ALL=C sort >"$VERIFY_WORK/release-dirs"
	if ! cmp "$MANIFEST_DIRS" "$VERIFY_WORK/release-dirs" >/dev/null; then
		printf '%s\n' 'empty directories present only in manifest (-) or install (+):' >&2
		comm -3 "$MANIFEST_DIRS" "$VERIFY_WORK/release-dirs" >&2 || :
		fail 'installed release empty-directory set differs from canonical manifest'
	fi
}

if [ -e "$RELEASE" ]; then
	[ -d "$RELEASE" ] && [ ! -L "$RELEASE" ] || \
		fail "release destination is not a safe directory: $RELEASE"
	verify_release "$RELEASE"
else
	RELEASE_STAGE=$RELEASES/.$RELEASE_ID.new.$$
	[ ! -e "$RELEASE_STAGE" ] || fail "release staging path already exists: $RELEASE_STAGE"
	mkdir -p "$RELEASE_STAGE"
	while IFS="$TAB" read -r KIND REL_PATH MODE BYTES HASH REST; do
		if [ "$KIND" = dir ]; then
			mkdir -p "$RELEASE_STAGE/$REL_PATH"
			apply_target_metadata "$RELEASE_STAGE/$REL_PATH" "$MODE"
			verify_release_dir "$RELEASE_STAGE" "$REL_PATH" "$MODE"
			continue
		fi
		[ "$KIND" = file ] || continue
		DESTINATION=$RELEASE_STAGE/$REL_PATH
		mkdir -p "$(dirname "$DESTINATION")"
		COPYFILE_DISABLE=1 cp -f "$CANDIDATE/$REL_PATH" "$DESTINATION"
		apply_target_metadata "$DESTINATION" "$MODE"
		verify_release_file "$RELEASE_STAGE" "$REL_PATH" "$MODE" "$BYTES" "$HASH"
		if test_failpoint_active kill-during-release-stage; then
			kill -KILL $$
		fi
		test_failpoint during-release-stage
	done <"$MANIFEST"
	COPYFILE_DISABLE=1 cp -f "$MANIFEST" "$RELEASE_STAGE/deploy-manifest.tsv"
	printf '%s\n' "$MANIFEST_SHA" >"$RELEASE_STAGE/.complete"
	apply_target_metadata "$RELEASE_STAGE/deploy-manifest.tsv" 0644
	apply_target_metadata "$RELEASE_STAGE/.complete" 0644
	find "$RELEASE_STAGE" -name '._*' -delete
	verify_release "$RELEASE_STAGE"
	sync
	mv "$RELEASE_STAGE" "$RELEASE"
	RELEASE_STAGE=
	sync
	verify_release "$RELEASE"
fi

[ -d "$BIRD/bird" ] && [ ! -L "$BIRD/bird" ] || fail 'legacy Bird runtime bind target is missing or unsafe'
is_regular_file "$BIRD/mount-storage.sh" || fail 'legacy storage-hook bind target is missing or unsafe'
is_regular_file "$BIRD/SYSTEM" || fail 'legacy SYSTEM bind target is missing or unsafe'
is_regular_file "$BIRD/post-flash.sh" || fail 'legacy boot hook is missing or unsafe'
LEGACY_HOOK_SHA=$(sha256 "$BIRD/post-flash.sh")
# Preserve the exact pre-activation selector as the updater's transaction
# rollback source. Canonical rotation later makes this file self-reference the
# new active selector; it is not an alternate boot target.
is_regular_file "$BIRD/extlinux/extlinux.conf" || fail 'active extlinux selector is missing or unsafe'
PREVIOUS_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
SELECTOR_ROLLBACK_SOURCE=$VERIFY_WORK/active-extlinux.conf
COPYFILE_DISABLE=1 cp -f "$BIRD/extlinux/extlinux.conf" "$SELECTOR_ROLLBACK_SOURCE"
[ "$(sha256 "$SELECTOR_ROLLBACK_SOURCE")" = "$PREVIOUS_SHA" ] || \
	fail 'active selector rollback source verification failed'
NEXT_SELECTOR_SHA=$(manifest_file_field extlinux/extlinux.conf 5)
if [ "$PREVIOUS_SHA" != "$NEXT_SELECTOR_SHA" ]; then
	PREVIOUS_TEMP=$BIRD/extlinux/.extlinux.previous.conf.new.$$
	COPYFILE_DISABLE=1 cp -f "$BIRD/extlinux/extlinux.conf" "$PREVIOUS_TEMP"
	[ "$(sha256 "$PREVIOUS_TEMP")" = "$PREVIOUS_SHA" ] || fail 'previous selector copy failed'
	sync
	mv -f "$PREVIOUS_TEMP" "$BIRD/extlinux/extlinux.previous.conf"
	sync
	[ "$(sha256 "$BIRD/extlinux/extlinux.previous.conf")" = "$PREVIOUS_SHA" ] || \
		fail 'previous selector commit failed'
else
	[ -f "$BIRD/extlinux/extlinux.previous.conf" ] || \
		fail 'idempotent activation is missing its preserved previous selector'
fi

# Complete every cleanup and immutable verification before activation.
if [ "$BIRD_SYNTHETIC_MODES" -eq 0 ]; then
	xattr -cr "$RELEASE" 2>/dev/null || :
	if is_regular_file "$BIRD/KERNEL"; then
		xattr -c "$BIRD/KERNEL" \
			"$BIRD/extlinux/extlinux.previous.conf" "$STORAGE_TARGET" \
			2>/dev/null || :
	else
		xattr -c "$BIRD/extlinux/extlinux.previous.conf" "$STORAGE_TARGET" \
			2>/dev/null || :
	fi
fi
find "$RELEASE" "$BIRD/extlinux" -name '._*' -delete
find "$BIRD" -maxdepth 1 -name '._KERNEL*' -delete
find "$DATA/MUOS/runtime" -maxdepth 1 -name '._ROCKNIX-STORAGE' -delete
sync
[ "$(file_bytes "$STORAGE_TARGET")" = "$STORAGE_BYTES" ] || \
	fail 'installed STORAGE size verification failed'
[ "$(ext4_magic "$STORAGE_TARGET")" = 53ef ] || \
	fail 'installed STORAGE ext4 verification failed'
verify_release "$RELEASE"
[ "$(sha256 "$BIRD/post-flash.sh")" = "$LEGACY_HOOK_SHA" ] || \
	fail 'legacy boot hook changed before activation'

# This verified rename is the only operation that makes this release bootable.
test_failpoint before-selector-activation
SELECTOR_MODE=$(manifest_file_field extlinux/extlinux.conf 3)
SELECTOR_BYTES=$(manifest_file_field extlinux/extlinux.conf 4)
SELECTOR_HASH=$(manifest_file_field extlinux/extlinux.conf 5)
SELECTOR_TEMP=$BIRD/extlinux/.extlinux.conf.new.$$
COPYFILE_DISABLE=1 cp -f "$RELEASE/extlinux/extlinux.conf" "$SELECTOR_TEMP"
apply_target_metadata "$SELECTOR_TEMP" "$SELECTOR_MODE"
[ "$(file_bytes "$SELECTOR_TEMP")" = "$SELECTOR_BYTES" ] &&
[ "$(sha256 "$SELECTOR_TEMP")" = "$SELECTOR_HASH" ] &&
verify_target_mode "$SELECTOR_TEMP" "$SELECTOR_MODE" || \
	fail 'selector activation temporary verification failed'
sync
mv -f "$SELECTOR_TEMP" "$BIRD/extlinux/extlinux.conf"
if test_failpoint_active kill-after-selector-rename; then
	kill -KILL $$
fi
SELECTOR_COMMITTED=1
if test_failpoint_active after-selector-rename; then
	SELECTOR_COMMITTED=0
elif ! sync; then
	SELECTOR_COMMITTED=0
elif [ "$(file_bytes "$BIRD/extlinux/extlinux.conf")" != "$SELECTOR_BYTES" ] ||
	[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" != "$SELECTOR_HASH" ] ||
	! verify_target_mode "$BIRD/extlinux/extlinux.conf" "$SELECTOR_MODE"; then
	SELECTOR_COMMITTED=0
fi
if [ "$SELECTOR_COMMITTED" -ne 1 ]; then
	ROLLBACK_TEMP=$BIRD/extlinux/.extlinux.conf.rollback.$$
	COPYFILE_DISABLE=1 cp -f "$SELECTOR_ROLLBACK_SOURCE" "$ROLLBACK_TEMP"
	[ "$(sha256 "$ROLLBACK_TEMP")" = "$PREVIOUS_SHA" ] || \
		fail 'selector rollback temporary verification failed'
	sync
	mv -f "$ROLLBACK_TEMP" "$BIRD/extlinux/extlinux.conf"
	sync
	[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PREVIOUS_SHA" ] || \
		fail 'selector activation failed and rollback did not verify'
	fail 'selector activation failed; previous selector restored'
fi

# The newly selected release is verified. Retire the obsolete alternate-boot
# assets only now, so a pre-activation failure still leaves the original card
# bytes untouched. Future loader failures persist evidence and stop.
for OBSOLETE_BOOT_ASSET in \
	"$BIRD/KERNEL.fallback" \
	"$BIRD/dtb.img" \
	"$BIRD/extlinux/extlinux.fallback.conf"; do
	if is_regular_file "$OBSOLETE_BOOT_ASSET"; then
		rm -f "$OBSOLETE_BOOT_ASSET"
	elif [ -e "$OBSOLETE_BOOT_ASSET" ] || [ -L "$OBSOLETE_BOOT_ASSET" ]; then
		fail "obsolete boot asset is not a safe regular file: $OBSOLETE_BOOT_ASSET"
	fi
done
sync
[ ! -e "$BIRD/KERNEL.fallback" ] && [ ! -L "$BIRD/KERNEL.fallback" ] &&
[ ! -e "$BIRD/dtb.img" ] && [ ! -L "$BIRD/dtb.img" ] &&
[ ! -e "$BIRD/extlinux/extlinux.fallback.conf" ] &&
	[ ! -L "$BIRD/extlinux/extlinux.fallback.conf" ] || \
	fail 'obsolete alternate-boot assets remain after activation'

OBSOLETE_ATTEMPT_ROOT=$DATA/Bird/boot-state/releases
if [ -d "$OBSOLETE_ATTEMPT_ROOT" ] && [ ! -L "$OBSOLETE_ATTEMPT_ROOT" ]; then
	if find "$OBSOLETE_ATTEMPT_ROOT" -mindepth 1 ! -type f ! -type d \
			-print -quit | grep -q .; then
		fail 'obsolete boot-attempt tree contains a symlink or special node'
	fi
	rm -rf "$OBSOLETE_ATTEMPT_ROOT"
elif [ -e "$OBSOLETE_ATTEMPT_ROOT" ] || [ -L "$OBSOLETE_ATTEMPT_ROOT" ]; then
	fail 'obsolete boot-attempt root is not a safe directory'
fi
sync
[ ! -e "$OBSOLETE_ATTEMPT_ROOT" ] && [ ! -L "$OBSOLETE_ATTEMPT_ROOT" ] || \
	fail 'obsolete boot-attempt state remains after activation'

# A loader failure record describes the selector that was active before this
# verified activation. Do not let stale evidence masquerade as a failure of
# the newly armed release.
rm -f "$BIRD/bird-loader-failure.txt" 2>/dev/null || :

# The selected release now owns the canonical deterministic SYSTEM. The old
# shared muOS image is neither a boot fallback nor a build input. Remove it only
# after selector activation and only when it is the exact shipping image that
# the hermetic parity gate replaced.
if is_regular_file "$LEGACY_RUNTIME"; then
	[ "$(file_bytes "$LEGACY_RUNTIME")" = "$LEGACY_RUNTIME_BYTES" ] && \
	[ "$(sha256 "$LEGACY_RUNTIME")" = "$LEGACY_RUNTIME_SHA" ] || \
		fail 'legacy SYSTEM changed; refusing automatic retirement'
	rm -f "$LEGACY_RUNTIME"
elif [ -e "$LEGACY_RUNTIME" ] || [ -L "$LEGACY_RUNTIME" ]; then
	fail 'legacy SYSTEM path is unsafe'
fi
sync
[ ! -e "$LEGACY_RUNTIME" ] && [ ! -L "$LEGACY_RUNTIME" ] || \
	fail 'legacy SYSTEM remains after canonical activation'

printf 'Bird stock-root %s activated on /dev/%s.\n' "$RELEASE_ID" "$WHOLE"
printf 'Complete immutable release: %s\n' "$RELEASE"
printf 'Canonical manifest: %s\n' "$MANIFEST_SHA"
printf 'Legacy Port data preflight is clean; no user content was moved.\n'
printf 'Generic storage discovery replaced by the fixed p6 Bird view.\n'
printf 'MPV physical volume ownership is system-only.\n'
printf 'Bird starts before generic userspace; autostart cannot repaint it.\n'
printf 'Production omits the serial console and has no alternate boot target.\n'
printf 'Network is PortMaster-only; unused fixed-profile units are masked.\n'
printf 'Early content selections queue once; fixed input and power events replace polling.\n'
printf 'Resolver and time synchronization now share that PortMaster-only gate.\n'
printf 'Bird and the release-matched H700 input module now begin in external initramfs.\n'
printf 'Battery percentage is kernel-driven, uevent-fed and shown in Bird.\n'
printf 'The original pidfd-adopted Bird owns input continuously across switch_root.\n'
printf 'Storage and config descriptors are acknowledged before special-mount handoff.\n'
printf 'The acknowledgement is an explicit post-prepare_sysroot FIFO event.\n'
printf 'Early content selections remain queued until the app contract is ready.\n'
printf 'Late generic display ownership and fixed-profile autostart no-ops are removed.\n'
printf 'Shutdown keeps the config checkpoint without a full interactive-profile load.\n'
printf 'The low-battery red LED threshold is fixed at 41 percent.\n'
printf 'Storage readiness uses one ordered post-prepare_sysroot anchor acquisition.\n'
printf 'Storage/config are retained after prepare_sysroot and before switch_root.\n'
printf 'A broken anchor contract remains an explicit supervisor recovery condition.\n'
printf 'The application compositor uses one fixed card1/DSI-1 profile.\n'
printf 'RF-kill state management now exists only inside network sessions.\n'
printf 'PortMaster networking waits for one usable NetworkManager link.\n'
printf 'The saved Wi-Fi profile is explicitly activated only for PortMaster.\n'
printf 'Generic autostart no longer starts the already-running Bird UI again.\n'
printf 'Generic autostart no longer requests already-completed fixed storage.\n'
printf 'Constant H700 profile writers are collapsed into one fixed transaction.\n'
printf 'PortMaster networking waits for iwd registration and a fresh Wi-Fi scan.\n'
printf 'The final-root supervisor starts once at the stable graphical boundary.\n'
printf 'Post-frame diagnostics cannot hold the target reboot watchdog open.\n'
printf 'Input recovery searches the complete fixed event range and retains the exact screen.\n'
printf 'Suspend restores stable 5, 3 and 1 percent brightness ticks; zero remains display-off.\n'
printf 'Per-boot supervisor, early-launcher and boot-state evidence is retained.\n'
printf 'Select+Start exits the managed foreground tree without grabbing app input.\n'
printf 'MSX uses the pinned fMSX core and its existing shared BIOS ROMs.\n'
printf 'p5 was not modified; this runtime transaction moved no p6 user content.\n'
printf 'The deterministic SYSTEM is release-scoped under Bird/runtime; the legacy shared SYSTEM is removed.\n'
printf 'Exact ROCKNIX KERNEL: %s\n' "$ROCKNIX_KERNEL_SHA"
printf 'Release verification failures persist a diagnostic and stop for host repair.\n'
printf 'Test early interaction timing, then repeat the broad compatibility gate.\n'
