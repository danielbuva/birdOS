#!/bin/sh
# Keep ROCKNIX's initramfs and SYSTEM unchanged. The small BIRD partition only
# supplies this hook so the exact release SYSTEM and writable storage image can
# live on the existing large data partition.

BIRD_HOST_TEST_MODE=${BIRD_HOST_TEST_MODE:-0}
case "$BIRD_HOST_TEST_MODE" in
	0)
		BIRD_FLASH_ROOT=/flash
		BIRD_DATA_DEVICE=/dev/mmcblk0p6
		BIRD_DATA_MOUNT=/birddata
		BIRD_SYSTEM_REL=MUOS/runtime/ROCKNIX-SYSTEM
		BIRD_STORAGE_REL=MUOS/runtime/ROCKNIX-STORAGE
		BIRD_STATE_REL=MUOS/Bird/boot-state
		;;
	1)
		BIRD_FLASH_ROOT=${BIRD_FLASH_ROOT:-/flash}
		BIRD_DATA_DEVICE=${BIRD_DATA_DEVICE:-/dev/mmcblk0p6}
		BIRD_DATA_MOUNT=${BIRD_DATA_MOUNT:-/birddata}
		BIRD_SYSTEM_REL=${BIRD_SYSTEM_REL:-MUOS/runtime/ROCKNIX-SYSTEM}
		BIRD_STORAGE_REL=${BIRD_STORAGE_REL:-MUOS/runtime/ROCKNIX-STORAGE}
		BIRD_STATE_REL=${BIRD_STATE_REL:-MUOS/Bird/boot-state}
		case "$BIRD_FLASH_ROOT:$BIRD_DATA_MOUNT" in
			/var/folders/*:/var/folders/*|/private/tmp/*:/private/tmp/*|/tmp/*:/tmp/*) ;;
			*) printf '%s\n' 'unsafe Bird post-flash test paths' >&2; return 1 ;;
		esac
		case "$BIRD_DATA_DEVICE" in /dev/bird-test) ;; *) return 1 ;; esac
		;;
	*)
		printf '%s\n' 'invalid Bird host-test mode' >&2
		return 1
		;;
esac
[ -n "${BIRD_LOADER_SELECTED:-}" ] || return 1
BIRD_RELEASE=$BIRD_LOADER_SELECTED
BIRD_ATTEMPTS_REL=$BIRD_STATE_REL/releases/$BIRD_RELEASE/attempts
BIRD_RELEASES_ROOT=$BIRD_FLASH_ROOT/bird-releases
BIRD_DATA_MOUNTED=0
BIRD_RUNTIME_BIND_MOUNTED=0
BIRD_STORAGE_BIND_MOUNTED=0
BIRD_SYSTEM_BIND_MOUNTED=0

sha256_file() {
	# The release loader owns the pinned initramfs BusyBox contract. Reuse its
	# implementation so the hook cannot drift to a second, host-only verifier.
	bird_loader_sha256 "$1"
}

bytes_file() {
	bird_loader_bytes "$1"
}

write_attempts() (
	VALUE=$1
	TEMP=$STATE_DIR/.attempts.$$
	umask 077
	printf '%s\n' "$VALUE" >"$TEMP" || return 1
	[ "$(cat "$TEMP" 2>/dev/null)" = "$VALUE" ] || {
		rm -f "$TEMP"
		return 1
	}
	sync || {
		rm -f "$TEMP"
		return 1
	}
	mv -f "$TEMP" "$ATTEMPTS_FILE" || {
		rm -f "$TEMP"
		return 1
	}
	[ "$(cat "$ATTEMPTS_FILE" 2>/dev/null)" = "$VALUE" ] || return 1
	sync || return 1
)

fallback_boot() {
	FAILURE_TAG=$1
	FAILURE_MESSAGE=$2
	# A fallback selector is followed by an immediate forced reboot. Flush p6,
	# tear down only the release binds that actually succeeded, in reverse
	# order, then require ExFAT to unmount before the loader mutates FAT
	# metadata or reboots.  A cleanup failure deliberately leaves the current
	# boot stopped on the failed candidate instead of risking cross-filesystem
	# corruption during an automatic retry.
	BIRD_FALLBACK_CLEAN=1
	sync || BIRD_FALLBACK_CLEAN=0
	if [ "$BIRD_SYSTEM_BIND_MOUNTED" -eq 1 ]; then
		if umount "$BIRD_FLASH_ROOT/SYSTEM" 2>/dev/null; then
			BIRD_SYSTEM_BIND_MOUNTED=0
		else
			BIRD_FALLBACK_CLEAN=0
		fi
	fi
	if [ "$BIRD_STORAGE_BIND_MOUNTED" -eq 1 ]; then
		if umount "$BIRD_FLASH_ROOT/mount-storage.sh" 2>/dev/null; then
			BIRD_STORAGE_BIND_MOUNTED=0
		else
			BIRD_FALLBACK_CLEAN=0
		fi
	fi
	if [ "$BIRD_RUNTIME_BIND_MOUNTED" -eq 1 ]; then
		if umount "$BIRD_FLASH_ROOT/bird" 2>/dev/null; then
			BIRD_RUNTIME_BIND_MOUNTED=0
		else
			BIRD_FALLBACK_CLEAN=0
		fi
	fi
	if [ "$BIRD_DATA_MOUNTED" -eq 1 ]; then
		if umount "$BIRD_DATA_MOUNT" 2>/dev/null; then
			BIRD_DATA_MOUNTED=0
		else
			BIRD_FALLBACK_CLEAN=0
		fi
	fi
	sync || BIRD_FALLBACK_CLEAN=0
	if [ "$BIRD_FALLBACK_CLEAN" -ne 1 ]; then
		{ printf 'bird post-flash: %s: fallback cleanup failed\n' \
			"$FAILURE_TAG" >/dev/kmsg; } 2>/dev/null || :
		return 1
	fi
	bird_loader_fail "$FAILURE_TAG: $FAILURE_MESSAGE"
	return 1
}

verify_release_runtime() {
	RELEASE_ROOT=$BIRD_RELEASES_ROOT/$BIRD_RELEASE
	RELEASE_MANIFEST=$RELEASE_ROOT/deploy-manifest.tsv
	RELEASE_COMPLETE=$RELEASE_ROOT/.complete
	RUNTIME_RECORDS=/tmp/bird-release-runtime.$$
	TAB=$(printf '\t')

	[ -d "$RELEASE_ROOT/bird" ] &&
	[ -f "$RELEASE_ROOT/post-flash.sh" ] &&
	[ -f "$RELEASE_ROOT/mount-storage.sh" ] &&
	[ -f "$RELEASE_MANIFEST" ] &&
	[ -s "$RELEASE_COMPLETE" ] || return 1
	EXPECTED_MANIFEST_SHA=$(cat "$RELEASE_COMPLETE" 2>/dev/null || printf '')
	case "$EXPECTED_MANIFEST_SHA" in *[!0-9a-f]*|'') return 1 ;; esac
	[ "${#EXPECTED_MANIFEST_SHA}" -eq 64 ] || return 1
	[ "$(sha256_file "$RELEASE_MANIFEST")" = "$EXPECTED_MANIFEST_SHA" ] || \
		return 1

	# The completion digest is co-located transactional evidence, not an
	# authenticity signature.  Parse its complete inventory and re-hash every
	# file the initramfs will source or expose through the two release binds.
	awk -F '\t' -v expected="$BIRD_RELEASE" '
		$1 == "schema" {
			if (NF != 2 || $2 != "bird-deploy-v1" || schema++) exit 1
			next
		}
		$1 == "release" {
			if (NF != 2 || $2 != expected || release++) exit 1
			next
		}
		$1 == "target-mode-policy" {
			if (NF != 2 || $2 != "fat-capability" || policy++) exit 1
			next
		}
		$1 == "source-commit" { if (NF != 3 || source++) exit 1; next }
		$1 == "input" {
			if (NF != 6 || $2 !~ /^[A-Za-z0-9._\/-]+$/ ||
			    $2 ~ /(^|\/)\.\.?($|\/)/ ||
			    $3 !~ /^[0-7][0-7][0-7]$/ || $4 !~ /^[0-9]+$/ ||
			    length($5) != 64 || $5 ~ /[^0-9a-f]/ || $6 == "") exit 1
			inputs++
			next
		}
		$1 == "dir" {
			if (NF != 3 || $2 !~ /^[A-Za-z0-9._\/-]+$/ ||
			    $2 ~ /(^|\/)\.\.?($|\/)/ ||
			    $3 !~ /^[0-7][0-7][0-7]$/) exit 1
			dirs++
			next
		}
		$1 == "file" {
			if (NF != 5 || $2 !~ /^[A-Za-z0-9._\/-]+$/ ||
			    $2 ~ /(^|\/)\.\.?($|\/)/ || $3 !~ /^[0-7][0-7][0-7]$/ ||
			    $4 !~ /^[0-9]+$/ || length($5) != 64 || $5 ~ /[^0-9a-f]/)
				exit 1
			files++
			if ($2 == "post-flash.sh" || $2 == "mount-storage.sh" ||
			    index($2, "bird/") == 1) {
				print $2 "\t" $3 "\t" $4 "\t" $5
				runtime++
				if ($2 == "post-flash.sh") hook++
				if ($2 == "mount-storage.sh") storage_hook++
				if (index($2, "bird/") == 1) bird++
			}
			next
		}
		{ exit 1 }
		END {
			if (schema != 1 || release != 1 || policy != 1 || source != 1 ||
			    inputs != 15 || files < 1 || runtime < 1 || hook != 1 ||
			    storage_hook != 1 || bird < 1) exit 1
		}
	' "$RELEASE_MANIFEST" >"$RUNTIME_RECORDS" || {
		rm -f "$RUNTIME_RECORDS"
		return 1
	}

	while IFS="$TAB" read -r RELATIVE MODE BYTES HASH; do
		TARGET=$RELEASE_ROOT/$RELATIVE
		[ -f "$TARGET" ] || { rm -f "$RUNTIME_RECORDS"; return 1; }
		ACTUAL_BYTES=$(bytes_file "$TARGET" 2>/dev/null || printf invalid)
		[ "$ACTUAL_BYTES" = "$BYTES" ] || {
			rm -f "$RUNTIME_RECORDS"
			return 1
		}
		[ "$(sha256_file "$TARGET")" = "$HASH" ] || {
			rm -f "$RUNTIME_RECORDS"
			return 1
		}
	done <"$RUNTIME_RECORDS"
	rm -f "$RUNTIME_RECORDS"
	return 0
}

# The immutable release loader has already selected and verified this hook.
# Empty/legacy selection is never valid here; the preserved legacy initramfs
# continues to source its untouched top-level hook instead.
case "$BIRD_RELEASE" in
	''|*[!A-Za-z0-9._-]*|.*|*..*)
	fallback_boot bird-release "Invalid release selector: $BIRD_RELEASE"
	return 1
	;;
esac

mkdir -p "$BIRD_DATA_MOUNT" || {
	fallback_boot bird-data "Could not create $BIRD_DATA_MOUNT"
	return 1
}
# ExFAT has no stored Unix mode bits. The explicit masks reproduce the proven
# muOS mount contract and make PortMaster's scripts and native payloads 0755.
mount -t exfat -o rw,exec,noatime,fmask=0022,dmask=0022 \
	"$BIRD_DATA_DEVICE" "$BIRD_DATA_MOUNT" || {
	fallback_boot bird-data "Could not mount $BIRD_DATA_DEVICE"
	return 1
}
BIRD_DATA_MOUNTED=1

SYSTEM_SOURCE=$BIRD_DATA_MOUNT/$BIRD_SYSTEM_REL
STORAGE_SOURCE=$BIRD_DATA_MOUNT/$BIRD_STORAGE_REL
STATE_DIR=${BIRD_DATA_MOUNT:?}/${BIRD_ATTEMPTS_REL%/*}
ATTEMPTS_FILE=$BIRD_DATA_MOUNT/$BIRD_ATTEMPTS_REL

mkdir -p "$STATE_DIR" || {
	fallback_boot bird-attempts "Could not create $STATE_DIR"
	return 1
}
[ -e "$ATTEMPTS_FILE" ] || {
	fallback_boot bird-attempts 'Selected release has no boot-attempt state'
	return 1
}
ATTEMPTS=$(cat "$ATTEMPTS_FILE" 2>/dev/null || printf '')
# An unreadable, empty, malformed or out-of-range file may be a legacy/torn
# state write. Consume the remaining retry budget instead of silently granting
# more attempts or feeding an overflowing value to shell arithmetic.
case "$ATTEMPTS" in 0|1|2) ;; *) ATTEMPTS=2 ;; esac
ATTEMPTS=$((ATTEMPTS + 1))
write_attempts "$ATTEMPTS" || {
	fallback_boot bird-attempts 'Could not commit the boot-attempt transaction'
	return 1
}

# Two failed full-stack starts are enough evidence to return to the preserved
# clean-root kernel. The fallback is selected before the third candidate boot.
if [ "$ATTEMPTS" -ge 3 ]; then
	fallback_boot bird-attempts 'Candidate retry budget exhausted'
	return 1
fi

[ -f "$SYSTEM_SOURCE" ] || {
	fallback_boot bird-system "Missing $SYSTEM_SOURCE"
	return 1
}
[ -f "$STORAGE_SOURCE" ] || {
	fallback_boot bird-storage "Missing $STORAGE_SOURCE"
	return 1
}

verify_release_runtime || {
	fallback_boot bird-release "Release verification failed: $BIRD_RELEASE"
	return 1
}
[ -d "$BIRD_FLASH_ROOT/bird" ] &&
[ -f "$BIRD_FLASH_ROOT/mount-storage.sh" ] || {
	fallback_boot bird-release 'Legacy bind targets are missing'
	return 1
}
mount --bind "$RELEASE_ROOT/bird" "$BIRD_FLASH_ROOT/bird" || {
	fallback_boot bird-release "Could not bind release runtime: $BIRD_RELEASE"
	return 1
}
BIRD_RUNTIME_BIND_MOUNTED=1
mount --bind "$RELEASE_ROOT/mount-storage.sh" \
	"$BIRD_FLASH_ROOT/mount-storage.sh" || {
	fallback_boot bird-release \
		"Could not bind release storage hook: $BIRD_RELEASE"
	return 1
}
BIRD_STORAGE_BIND_MOUNTED=1

# /flash/SYSTEM is an empty mount target on the small FAT partition. Bind the
# exact immutable image over it so the unmodified ROCKNIX mount_sysroot path is
# used without copying or repacking SYSTEM.
mount --bind "$SYSTEM_SOURCE" "$BIRD_FLASH_ROOT/SYSTEM" || {
	fallback_boot bird-system-bind 'Could not bind exact ROCKNIX SYSTEM'
	return 1
}
BIRD_SYSTEM_BIND_MOUNTED=1

export BIRD_DATA_MOUNT BIRD_STORAGE_REL BIRD_ATTEMPTS_REL BIRD_RELEASE
