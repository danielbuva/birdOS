#!/bin/sh
# Keep ROCKNIX's initramfs contract. The small BIRD partition supplies this
# hook so the selected release's deterministic SYSTEM and writable storage
# image can live on the existing large data partition.

BIRD_HOST_TEST_MODE=${BIRD_HOST_TEST_MODE:-0}
case "$BIRD_HOST_TEST_MODE" in
	0)
		BIRD_FLASH_ROOT=/flash
		BIRD_DATA_DEVICE=/dev/mmcblk0p6
		BIRD_DATA_MOUNT=/birddata
		BIRD_STORAGE_REL=MUOS/runtime/ROCKNIX-STORAGE
		;;
	1)
		BIRD_FLASH_ROOT=${BIRD_FLASH_ROOT:-/flash}
		BIRD_DATA_DEVICE=${BIRD_DATA_DEVICE:-/dev/mmcblk0p6}
		BIRD_DATA_MOUNT=${BIRD_DATA_MOUNT:-/birddata}
		BIRD_STORAGE_REL=${BIRD_STORAGE_REL:-MUOS/runtime/ROCKNIX-STORAGE}
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
BIRD_SYSTEM_RELEASE=$BIRD_RELEASE
if [ "$BIRD_HOST_TEST_MODE" = 1 ]; then
	BIRD_SYSTEM_REL=${BIRD_SYSTEM_REL:-Bird/runtime/$BIRD_SYSTEM_RELEASE/ROCKNIX-SYSTEM}
else
	BIRD_SYSTEM_REL=Bird/runtime/$BIRD_SYSTEM_RELEASE/ROCKNIX-SYSTEM
fi
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

stop_boot() {
	FAILURE_TAG=$1
	FAILURE_MESSAGE=$2
	# Flush and unwind any mounts established before the failure, then persist
	# the reason on BIRD. Never select or boot a different release.
	BIRD_FAILURE_CLEAN=1
	sync || BIRD_FAILURE_CLEAN=0
	if [ "$BIRD_SYSTEM_BIND_MOUNTED" -eq 1 ]; then
		if umount "$BIRD_FLASH_ROOT/SYSTEM" 2>/dev/null; then
			BIRD_SYSTEM_BIND_MOUNTED=0
		else
			BIRD_FAILURE_CLEAN=0
		fi
	fi
	if [ "$BIRD_STORAGE_BIND_MOUNTED" -eq 1 ]; then
		if umount "$BIRD_FLASH_ROOT/mount-storage.sh" 2>/dev/null; then
			BIRD_STORAGE_BIND_MOUNTED=0
		else
			BIRD_FAILURE_CLEAN=0
		fi
	fi
	if [ "$BIRD_RUNTIME_BIND_MOUNTED" -eq 1 ]; then
		if umount "$BIRD_FLASH_ROOT/bird" 2>/dev/null; then
			BIRD_RUNTIME_BIND_MOUNTED=0
		else
			BIRD_FAILURE_CLEAN=0
		fi
	fi
	if [ "$BIRD_DATA_MOUNTED" -eq 1 ]; then
		if umount "$BIRD_DATA_MOUNT" 2>/dev/null; then
			BIRD_DATA_MOUNTED=0
		else
			BIRD_FAILURE_CLEAN=0
		fi
	fi
	sync || BIRD_FAILURE_CLEAN=0
	if [ "$BIRD_FAILURE_CLEAN" -ne 1 ]; then
		{ printf 'bird post-flash: %s: failure cleanup failed\n' \
			"$FAILURE_TAG" >/dev/kmsg; } 2>/dev/null || :
		FAILURE_MESSAGE="$FAILURE_MESSAGE; mount cleanup incomplete"
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
		BEGIN {
			required_input["KERNEL"] = 1
			required_input["dtb.img"] = 1
			required_input["ROCKNIX-SYSTEM"] = 1
			required_input["ROCKNIX-STORAGE"] = 1
			required_input["usr/bin/autostart"] = 1
			required_input["initramfs/init"] = 1
			required_input["rocknix-singleadc-joypad.ko"] = 1
			required_input["initramfs/busybox"] = 1
			required_input["PortMaster.zip"] = 1
			required_input["PortMaster/pugwash"] = 1
			required_input["PortMaster/PortMaster.sh"] = 1
			required_input["PortMaster/mod_ROCKNIX.txt"] = 1
			required_input["PortMaster/funcs.txt"] = 1
			required_input["PortMaster/harbourmaster"] = 1
		}
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
		$1 == "artifact" {
			if (NF != 4 || ($2 != "device-contract" && $2 != "catalog") ||
			    $3 !~ /^[A-Za-z0-9._\/-]+$/ || $3 ~ /(^|\/)\.\.?($|\/)/ ||
			    length($4) != 64 || $4 ~ /[^0-9a-f]/) exit 1
			artifacts++
			if ($2 == "device-contract") {
				if (device_contract++) exit 1
				device_contract_path = $3
				device_contract_digest = $4
			} else {
				if (catalog++) exit 1
				catalog_path = $3
			}
			next
		}
		$1 == "input" {
			if (NF != 6 || $2 !~ /^[A-Za-z0-9._\/-]+$/ ||
			    $2 ~ /(^|\/)\.\.?($|\/)/ ||
			    $3 !~ /^[0-7][0-7][0-7]$/ || $4 !~ /^[0-9]+$/ ||
			    length($5) != 64 || $5 ~ /[^0-9a-f]/ || $6 == "") exit 1
			if (!($2 in required_input) && $2 != "source-kernel-parity.tsv" &&
			    $2 != "source-kernel-builtin-input.tsv" &&
			    $2 != "source-kernel-single-gpio-read.tsv" &&
			    $2 != "source-kernel-single-input-sync.tsv")
				exit 1
			if (input_seen[$2]++) exit 1
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
			if ($2 == "bird/bird-device-contract.tsv") {
				if (device_contract_file++) exit 1
				device_contract_file_digest = $5
			}
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
			for (input_name in required_input)
				if (input_seen[input_name] != 1) exit 1
			if (schema != 1 || release != 1 || policy != 1 || source != 1 ||
			    artifacts != 2 || device_contract != 1 || catalog != 1 ||
			    device_contract_path != "bird/bird-device-contract.tsv" ||
			    catalog_path != "launcher/catalog.generated.h" ||
			    device_contract_file != 1 ||
			    device_contract_digest != device_contract_file_digest ||
			    inputs != 14 + (input_seen["source-kernel-parity.tsv"] == 1) + (input_seen["source-kernel-builtin-input.tsv"] == 1) + (input_seen["source-kernel-single-gpio-read.tsv"] == 1) + (input_seen["source-kernel-single-input-sync.tsv"] == 1) ||
			    input_seen["source-kernel-parity.tsv"] + input_seen["source-kernel-builtin-input.tsv"] + input_seen["source-kernel-single-gpio-read.tsv"] + input_seen["source-kernel-single-input-sync.tsv"] > 1 ||
			    files < 1 || runtime < 1 || hook != 1 ||
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
# Empty or malformed selection is never valid here.
case "$BIRD_RELEASE" in
	''|*[!A-Za-z0-9._-]*|.*|*..*)
	stop_boot bird-release "Invalid release selector: $BIRD_RELEASE"
	return 1
	;;
esac

mkdir -p "$BIRD_DATA_MOUNT" || {
	stop_boot bird-data "Could not create $BIRD_DATA_MOUNT"
	return 1
}
# ExFAT has no stored Unix mode bits. The explicit masks reproduce the proven
# muOS mount contract and make PortMaster's scripts and native payloads 0755.
mount -t exfat -o rw,exec,noatime,fmask=0022,dmask=0022 \
	"$BIRD_DATA_DEVICE" "$BIRD_DATA_MOUNT" || {
	stop_boot bird-data "Could not mount $BIRD_DATA_DEVICE"
	return 1
}
BIRD_DATA_MOUNTED=1

SYSTEM_SOURCE=$BIRD_DATA_MOUNT/$BIRD_SYSTEM_REL
STORAGE_SOURCE=$BIRD_DATA_MOUNT/$BIRD_STORAGE_REL
[ -f "$SYSTEM_SOURCE" ] || {
	stop_boot bird-system "Missing $SYSTEM_SOURCE"
	return 1
}
[ -f "$STORAGE_SOURCE" ] || {
	stop_boot bird-storage "Missing $STORAGE_SOURCE"
	return 1
}

verify_release_runtime || {
	stop_boot bird-release "Release verification failed: $BIRD_RELEASE"
	return 1
}
[ -d "$BIRD_FLASH_ROOT/bird" ] &&
[ -f "$BIRD_FLASH_ROOT/mount-storage.sh" ] || {
	stop_boot bird-release 'Release bind targets are missing'
	return 1
}
mount --bind "$RELEASE_ROOT/bird" "$BIRD_FLASH_ROOT/bird" || {
	stop_boot bird-release "Could not bind release runtime: $BIRD_RELEASE"
	return 1
}
BIRD_RUNTIME_BIND_MOUNTED=1
mount --bind "$RELEASE_ROOT/mount-storage.sh" \
	"$BIRD_FLASH_ROOT/mount-storage.sh" || {
	stop_boot bird-release \
		"Could not bind release storage hook: $BIRD_RELEASE"
	return 1
}
BIRD_STORAGE_BIND_MOUNTED=1

# /flash/SYSTEM is an empty mount target on the small FAT partition. Bind the
# exact immutable image over it so the unmodified ROCKNIX mount_sysroot path is
# used without copying or repacking SYSTEM.
mount --bind "$SYSTEM_SOURCE" "$BIRD_FLASH_ROOT/SYSTEM" || {
	stop_boot bird-system-bind 'Could not bind exact ROCKNIX SYSTEM'
	return 1
}
BIRD_SYSTEM_BIND_MOUNTED=1

export BIRD_DATA_MOUNT BIRD_STORAGE_REL BIRD_RELEASE
