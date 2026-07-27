#!/bin/sh
# Guarded deployment of the compatibility-first stock-root milestone. P5 and
# content bytes stay untouched. V6.23 installs one immutable, manifest-verified
# release and activates it with one extlinux selector rename.
# It retains the exact kernel and complete working ROCKNIX userspace.
# The exact ROCKNIX writable filesystem remains a loop image on p6, and the
# accepted v5.4 kernel remains on p1 as a fallback.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/BIRD-DATA}
CANDIDATE=${CANDIDATE:-$ROOT/kernel/work/bird-rocknix-stock-root-v6.23/card}
MANIFEST=${MANIFEST:-$CANDIDATE/../deploy-manifest.tsv}
STORAGE_SOURCE=${STORAGE_SOURCE:-$HOME/rocknix-reference-result/storage.ext4}
BIRD_HOST_TEST_MODE=${BIRD_HOST_TEST_MODE:-0}
BIRD_DEVICE_INFO=${BIRD_DEVICE_INFO:-}
BIRD_TEST_FAILPOINT=${BIRD_TEST_FAILPOINT:-}
BIRD_TEST_LOCK_GATE=${BIRD_TEST_LOCK_GATE:-}
BIRD_TEST_MANIFEST_GATE=${BIRD_TEST_MANIFEST_GATE:-}
RUNTIME=$DATA/MUOS/runtime/ROCKNIX-SYSTEM
STORAGE_TARGET=$DATA/MUOS/runtime/ROCKNIX-STORAGE

RELEASE_ID=v6.23
BIRD_BYTES=134217728
BIRD_OFFSET=16777216
DISK_BYTES=512074186752
ROOT_BYTES=8589934592
ROOT_OFFSET=163577856
DATA_BYTES=503320672768
DATA_OFFSET=8753512448

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

case "$BIRD_HOST_TEST_MODE" in
	0)
		[ -z "$BIRD_DEVICE_INFO" ] || fail 'device metadata override requires host-test mode'
		[ -z "$BIRD_TEST_FAILPOINT" ] || fail 'failure injection requires host-test mode'
		[ -z "$BIRD_TEST_LOCK_GATE" ] || fail 'lock gate requires host-test mode'
		[ -z "$BIRD_TEST_MANIFEST_GATE" ] || fail 'manifest gate requires host-test mode'
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

field() {
	if [ -n "$BIRD_DEVICE_INFO" ]; then
		awk -F '\t' -v device="$1" -v key="$2" \
			'$1 == device && $2 == key {print $3; exit}' "$BIRD_DEVICE_INFO"
		return
	fi
	diskutil info "$1" | awk -F: -v key="$2" \
		'$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {sub(/^[[:space:]]*/, "", $2); print $2; exit}'
}

disk_bytes() {
	field "$1" 'Disk Size' | sed -n 's/.*(\([0-9][0-9]*\) Bytes).*/\1/p'
}

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

ext4_magic() {
	od -An -tx1 -j 1080 -N 2 "$1" | tr -d ' \n'
}

[ -d "$BIRD" ] && [ ! -L "$BIRD" ] || fail "BIRD volume missing or unsafe: $BIRD"
[ -d "$DATA" ] && [ ! -L "$DATA" ] || fail "data volume missing or unsafe: $DATA"
[ -d "$CANDIDATE" ] && [ ! -L "$CANDIDATE" ] || fail "built candidate missing or unsafe: $CANDIDATE"
is_regular_file "$MANIFEST" || fail "canonical deploy manifest missing or unsafe: $MANIFEST"
is_regular_file "$STORAGE_SOURCE" || fail 'reference ROCKNIX storage image missing or unsafe'
is_regular_file "$RUNTIME" || fail 'exact ROCKNIX runtime missing or unsafe on card'

VERIFY_WORK=$(mktemp -d "${TMPDIR:-/tmp}/bird-deploy.XXXXXX") || \
	fail 'could not create manifest verification directory'
RELEASE_STAGE=
BIRD_CARD_LOCK_OWNED=0
# shellcheck source=mac-bird-card-lock.sh
. "$ROOT/firmware/mac-bird-card-lock.sh"

cleanup() {
	if [ -n "$RELEASE_STAGE" ]; then
		case "$RELEASE_STAGE" in
			"$BIRD"/bird-releases/.*.new.*) rm -rf "$RELEASE_STAGE" ;;
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
awk -F '\t' '
	function safe_path(path) {
		return path ~ /^[A-Za-z0-9._\/-]+$/ &&
		       path !~ /(^|\/)\.\.?($|\/)/
	}
	$1 == "schema" {
		if (NF != 2 || $2 != "bird-deploy-v1" || schema++) exit 1
		next
	}
	$1 == "release" {
		if (NF != 2 || $2 != "v6.23" || release++) exit 1
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
		print "file\t" $2
		files++
		next
	}
	{ exit 1 }
	END {
		if (schema != 1 || release != 1 || policy != 1 || source != 1 ||
		    inputs != 15 || files < 1) exit 1
	}
' "$MANIFEST" >"$MANIFEST_RECORDS" || fail 'canonical deploy manifest is malformed'

awk -F '\t' '$1 == "input" {print $2}' "$MANIFEST_RECORDS" | \
	LC_ALL=C sort >"$MANIFEST_INPUTS"
printf '%s\n' KERNEL KERNEL.fallback PortMaster.zip \
	PortMaster/PortMaster.sh PortMaster/funcs.txt PortMaster/harbourmaster \
	PortMaster/mod_ROCKNIX.txt PortMaster/pugwash ROCKNIX-STORAGE \
	ROCKNIX-SYSTEM dtb.img initramfs/busybox initramfs/init \
	rocknix-singleadc-joypad.ko usr/bin/autostart | \
	LC_ALL=C sort >"$VERIFY_WORK/expected-inputs"
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
STORAGE_BYTES=$(manifest_input_field ROCKNIX-STORAGE 4)
STORAGE_SHA=$(manifest_input_field ROCKNIX-STORAGE 5)
V54_KERNEL_SHA=$(manifest_input_field KERNEL.fallback 5)
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

WHOLE=$(field "$BIRD" 'Part of Whole')
[ -n "$WHOLE" ] || fail 'cannot identify card parent'
[ "$WHOLE" = "$(field "$DATA" 'Part of Whole')" ] || fail 'volumes are on different disks'
[ "$(field "/dev/$WHOLE" 'Device Location')" = External ] || \
	[ "$(field "/dev/$WHOLE" 'Protocol')" = 'Secure Digital' ] || \
	fail 'refusing disk that is neither external nor a physical SD card'
[ "$(field "/dev/$WHOLE" 'Removable Media')" = Removable ] || fail 'refusing non-removable disk'
[ "$(disk_bytes "/dev/$WHOLE")" = "$DISK_BYTES" ] || fail 'whole-card size changed'
[ "$(field "$BIRD" 'Device Identifier')" = "${WHOLE}s1" ] || fail 'BIRD is not p1'
[ "$(field "$DATA" 'Device Identifier')" = "${WHOLE}s6" ] || fail 'data is not p6'
[ "$(field "$BIRD" 'Partition Offset' | awk '{print $1}')" = "$BIRD_OFFSET" ] || fail 'p1 offset changed'
[ "$(disk_bytes "$BIRD")" = "$BIRD_BYTES" ] || fail 'p1 size changed'
[ "$(field "/dev/${WHOLE}s5" 'Partition Offset' | awk '{print $1}')" = "$ROOT_OFFSET" ] || fail 'p5 offset changed'
[ "$(disk_bytes "/dev/${WHOLE}s5")" = "$ROOT_BYTES" ] || fail 'p5 size changed'
[ "$(field "$DATA" 'Partition Offset' | awk '{print $1}')" = "$DATA_OFFSET" ] || fail 'p6 offset changed'
[ "$(disk_bytes "$DATA")" = "$DATA_BYTES" ] || fail 'p6 size changed'
[ "$(field "$BIRD" 'Volume Read-Only')" = No ] || fail 'BIRD is read-only'
[ "$(field "$DATA" 'Volume Read-Only')" = No ] || fail 'data is read-only'

# Serialize every host-side card mutation with the same inherited advisory
# transaction lock used by the explicit Ports migration. The owner symlink is
# diagnostic; PID plus process-start identity prevents PID-reuse confusion.
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
[ "$(sha256 "$RUNTIME")" = "$RUNTIME_SHA" ] || fail 'card SYSTEM changed'
[ "$(sha256 "$STORAGE_SOURCE")" = "$STORAGE_SHA" ] || fail 'reference STORAGE changed'
is_regular_file "$BIRD/dtb.img" && [ "$(sha256 "$BIRD/dtb.img")" = "$DTB_SHA" ] || \
	fail 'fallback DTB changed, missing, or unsafe'

# Data-layout conversion is deliberately outside this runtime transaction.
# Refuse the legacy tree rather than moving user content entry-by-entry while
# either the prior selector or fallback runtime remains active.
LEGACY_PORTS=$DATA/ports
NATIVE_PORTS=$DATA/ROMS/Ports
if [ -d "$LEGACY_PORTS" ] &&
	find "$LEGACY_PORTS" -mindepth 1 -maxdepth 1 -print | grep -q .; then
	fail 'legacy /ports data must be migrated separately before runtime deployment'
fi

portmaster_payload_valid() {
	PORTMASTER=$NATIVE_PORTS/PortMaster
	[ -d "$PORTMASTER" ] && [ ! -L "$PORTMASTER" ] &&
	is_regular_file "$PORTMASTER/pugwash" &&
	is_regular_file "$PORTMASTER/PortMaster.sh" &&
	is_regular_file "$PORTMASTER/control.txt" && [ -s "$PORTMASTER/control.txt" ] &&
	is_regular_file "$PORTMASTER/mod_ROCKNIX.txt" &&
	is_regular_file "$PORTMASTER/funcs.txt" &&
	is_regular_file "$PORTMASTER/oga_controls" && [ -s "$PORTMASTER/oga_controls" ] &&
	is_regular_file "$PORTMASTER/harbourmaster" &&
	[ "$(file_bytes "$PORTMASTER/pugwash")" = "$PORTMASTER_PUGWASH_BYTES" ] &&
	[ "$(file_bytes "$PORTMASTER/PortMaster.sh")" = "$PORTMASTER_SH_BYTES" ] &&
	[ "$(file_bytes "$PORTMASTER/mod_ROCKNIX.txt")" = "$PORTMASTER_MOD_BYTES" ] &&
	[ "$(file_bytes "$PORTMASTER/funcs.txt")" = "$PORTMASTER_FUNCS_BYTES" ] &&
	[ "$(file_bytes "$PORTMASTER/harbourmaster")" = "$PORTMASTER_HARBOURMASTER_BYTES" ] &&
	[ "$(sha256 "$PORTMASTER/pugwash")" = "$PORTMASTER_PUGWASH_SHA" ] &&
	[ "$(sha256 "$PORTMASTER/PortMaster.sh")" = "$PORTMASTER_SH_SHA" ] &&
	[ "$(sha256 "$PORTMASTER/mod_ROCKNIX.txt")" = "$PORTMASTER_MOD_SHA" ] &&
	[ "$(sha256 "$PORTMASTER/funcs.txt")" = "$PORTMASTER_FUNCS_SHA" ] &&
	[ "$(sha256 "$PORTMASTER/harbourmaster")" = \
		"$PORTMASTER_HARBOURMASTER_SHA" ]
}

portmaster_payload_valid || \
	fail 'PortMaster provider must be prepared and verified before runtime deployment'

# Earlier Bird versions published an empty completion marker. Upgrade that
# valid installed provider in place without replacing mutable control.txt or
# oga_controls state. The marker content-addresses the five immutable files.
PORTMASTER_MARKER_VALUE=bird-portmaster-v1:$PORTMASTER_PUGWASH_SHA:$PORTMASTER_SH_SHA:$PORTMASTER_MOD_SHA:$PORTMASTER_FUNCS_SHA:$PORTMASTER_HARBOURMASTER_SHA
PORTMASTER_MARKER=$NATIVE_PORTS/PortMaster/.bird-release-complete
if [ -e "$PORTMASTER_MARKER" ] && ! is_regular_file "$PORTMASTER_MARKER"; then
	fail 'PortMaster completion marker is a symlink or special node'
fi
if [ "$(cat "$PORTMASTER_MARKER" 2>/dev/null || :)" != \
	"$PORTMASTER_MARKER_VALUE" ]; then
	PORTMASTER_MARKER_TEMP=$NATIVE_PORTS/PortMaster/.bird-release-complete.new.$$
	printf '%s\n' "$PORTMASTER_MARKER_VALUE" >"$PORTMASTER_MARKER_TEMP"
	[ "$(cat "$PORTMASTER_MARKER_TEMP")" = "$PORTMASTER_MARKER_VALUE" ] || \
		fail 'PortMaster marker temporary verification failed'
	sync
	mv -f "$PORTMASTER_MARKER_TEMP" "$PORTMASTER_MARKER"
	sync
	[ "$(cat "$PORTMASTER_MARKER")" = "$PORTMASTER_MARKER_VALUE" ] || \
		fail 'PortMaster marker commit failed'
fi

is_regular_file "$BIRD/KERNEL" || fail 'active KERNEL is missing or unsafe'
CURRENT=$(sha256 "$BIRD/KERNEL")
case "$CURRENT" in
	"$V54_KERNEL_SHA"|"$ROCKNIX_KERNEL_SHA") ;;
	*) fail "unexpected active KERNEL: $CURRENT" ;;
esac

if is_regular_file "$BIRD/KERNEL.fallback"; then
	[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$V54_KERNEL_SHA" ] || fail 'fallback KERNEL changed'
elif [ -e "$BIRD/KERNEL.fallback" ]; then
	fail 'fallback KERNEL is a symlink or special node'
elif [ "$CURRENT" = "$V54_KERNEL_SHA" ]; then
	COPYFILE_DISABLE=1 cp -f "$BIRD/KERNEL" "$BIRD/.KERNEL.fallback.new"
	[ "$(sha256 "$BIRD/.KERNEL.fallback.new")" = "$V54_KERNEL_SHA" ] || fail 'fallback copy failed'
	sync
	mv -f "$BIRD/.KERNEL.fallback.new" "$BIRD/KERNEL.fallback"
	sync
	[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$V54_KERNEL_SHA" ] || \
		fail 'fallback KERNEL commit failed'
else
	fail 'v5.4 fallback KERNEL is missing'
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
ATTEMPTS_DIR=$DATA/MUOS/Bird/boot-state/releases/$RELEASE_ID
mkdir -p "$BIRD/extlinux" "$ATTEMPTS_DIR"

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

# Copy one manifest-listed inactive recovery config through a same-directory
# rename, then verify the committed destination.
atomic_install_manifest_file() {
	RELATIVE=$1
	DESTINATION=$2
	MODE=$(manifest_file_field "$RELATIVE" 3)
	BYTES=$(manifest_file_field "$RELATIVE" 4)
	HASH=$(manifest_file_field "$RELATIVE" 5)
	[ -n "$MODE" ] && [ -n "$BYTES" ] && [ -n "$HASH" ] || \
		fail "manifest activation record missing: $RELATIVE"
	TEMP=${DESTINATION%/*}/.${DESTINATION##*/}.new.$$
	COPYFILE_DISABLE=1 cp -f "$RELEASE/$RELATIVE" "$TEMP"
	apply_target_metadata "$TEMP" "$MODE"
	[ "$(file_bytes "$TEMP")" = "$BYTES" ] || fail "activation size changed: $RELATIVE"
	[ "$(sha256 "$TEMP")" = "$HASH" ] || fail "activation digest changed: $RELATIVE"
	verify_target_mode "$TEMP" "$MODE" || fail "activation mode contract failed: $RELATIVE"
	sync
	mv -f "$TEMP" "$DESTINATION"
	sync
	[ "$(file_bytes "$DESTINATION")" = "$BYTES" ] || fail "committed size changed: $RELATIVE"
	[ "$(sha256 "$DESTINATION")" = "$HASH" ] || fail "committed digest changed: $RELATIVE"
	verify_target_mode "$DESTINATION" "$MODE" || fail "committed mode contract failed: $RELATIVE"
}

[ -d "$BIRD/bird" ] && [ ! -L "$BIRD/bird" ] || fail 'legacy Bird runtime bind target is missing or unsafe'
is_regular_file "$BIRD/mount-storage.sh" || fail 'legacy storage-hook bind target is missing or unsafe'
is_regular_file "$BIRD/SYSTEM" || fail 'legacy SYSTEM bind target is missing or unsafe'
is_regular_file "$BIRD/post-flash.sh" || fail 'legacy boot hook is missing or unsafe'
LEGACY_HOOK_SHA=$(sha256 "$BIRD/post-flash.sh")
atomic_install_manifest_file extlinux/extlinux.fallback.conf \
	"$BIRD/extlinux/extlinux.fallback.conf"

# Preserve the exact selector for the previous complete runtime.  This is a
# manual recovery point; the automatic three-attempt path remains v5.4.
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

# Complete every cleanup and immutable verification before activation. No
# release or recovery byte is mutated after the selector transaction starts.
if [ "$BIRD_SYNTHETIC_MODES" -eq 0 ]; then
	xattr -cr "$RELEASE" 2>/dev/null || :
	xattr -c "$BIRD/KERNEL" "$BIRD/KERNEL.fallback" \
		"$BIRD/extlinux/extlinux.fallback.conf" \
		"$BIRD/extlinux/extlinux.previous.conf" "$STORAGE_TARGET" 2>/dev/null || :
fi
find "$RELEASE" "$BIRD/extlinux" -name '._*' -delete
find "$BIRD" -maxdepth 1 -name '._KERNEL*' -delete
find "$DATA/MUOS/runtime" -maxdepth 1 -name '._ROCKNIX-STORAGE' -delete
sync
[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$V54_KERNEL_SHA" ] || \
	fail 'installed fallback verification failed'
[ "$(file_bytes "$STORAGE_TARGET")" = "$STORAGE_BYTES" ] || \
	fail 'installed STORAGE size verification failed'
[ "$(ext4_magic "$STORAGE_TARGET")" = 53ef ] || \
	fail 'installed STORAGE ext4 verification failed'
verify_release "$RELEASE"
[ "$(sha256 "$BIRD/post-flash.sh")" = "$LEGACY_HOOK_SHA" ] || \
	fail 'legacy boot hook changed before activation'

# Arm only this candidate release before the sole activation switch. A failed
# activation must never reset the health journal for the previously selected
# release. The release-scoped transaction leaves either its prior value or 0.
ATTEMPTS=$ATTEMPTS_DIR/attempts
ATTEMPTS_TEMP=$ATTEMPTS_DIR/.attempts.new.$$
printf '0\n' >"$ATTEMPTS_TEMP"
sync
mv -f "$ATTEMPTS_TEMP" "$ATTEMPTS"
sync
[ "$(cat "$ATTEMPTS")" = 0 ] || fail 'boot-attempt reset transaction failed'

# This verified rename is the only operation that makes v6.23 bootable.
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

# A loader failure record describes the selector that was active before this
# verified activation. Do not let stale evidence masquerade as a failure of
# the newly armed release; the loader recreates it before any future fallback.
rm -f "$BIRD/bird-loader-failure.txt" 2>/dev/null || :

printf 'Bird stock-root v6.23 activated on /dev/%s.\n' "$WHOLE"
printf 'Complete immutable release: %s\n' "$RELEASE"
printf 'Canonical manifest: %s\n' "$MANIFEST_SHA"
printf 'Legacy Port data preflight is clean; no user content was moved.\n'
printf 'Generic storage discovery replaced by the fixed p6 Bird view.\n'
printf 'MPV physical volume ownership is system-only.\n'
printf 'Bird starts before generic userspace; autostart cannot repaint it.\n'
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
printf 'Storage readiness has a bounded self-healing probe until success.\n'
printf 'Storage/config are retained after prepare_sysroot and before switch_root.\n'
printf 'A failed final-root anchor retires into the systemd fallback.\n'
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
printf 'Exact ROCKNIX KERNEL: %s\n' "$ROCKNIX_KERNEL_SHA"
printf 'Automatic fallback KERNEL: %s\n' "$V54_KERNEL_SHA"
printf 'Test early interaction timing, then repeat the broad compatibility gate.\n'
