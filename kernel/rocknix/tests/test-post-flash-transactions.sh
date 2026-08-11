#!/bin/bash
# Host-only proof that boot verification failures persist evidence and stop
# without changing the selected release or invoking an alternate boot path.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
LOADER=$ROOT/kernel/rocknix/stock-root/bird-release-loader.sh
POST_FLASH=$ROOT/kernel/rocknix/stock-root/post-flash.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-boot-failure.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

FLASH=$TMP/flash
CMDLINE=$TMP/cmdline
mkdir -p "$FLASH/extlinux" "$FLASH/bird-releases"
printf '%s\n' 'production-selector' >"$FLASH/extlinux/extlinux.conf"
SELECTOR_BEFORE=$(shasum -a 256 "$FLASH/extlinux/extlinux.conf" | awk '{print $1}')

run_loader_failure() (
	BIRD_HOST_TEST_MODE=1
	BIRD_LOADER_FLASH=$FLASH
	BIRD_LOADER_CMDLINE=$CMDLINE
	BIRD_LOADER_RELEASE=dev-current
	BIRD_LOADER_BUSYBOX=
	export BIRD_HOST_TEST_MODE BIRD_LOADER_FLASH BIRD_LOADER_CMDLINE \
		BIRD_LOADER_RELEASE BIRD_LOADER_BUSYBOX
	mount() { return 0; }
	error() { printf 'error-called\t%s\t%s\n' "$1" "$2" >>"$TMP/error.log"; return 1; }
	export -f mount error
	# shellcheck source=/dev/null
	. "$LOADER"
)

printf '%s\n' 'quiet bird_release=wrong' >"$CMDLINE"
if run_loader_failure; then
	printf '%s\n' 'malformed selector unexpectedly passed release loader' >&2
	exit 1
fi
[ "$(shasum -a 256 "$FLASH/extlinux/extlinux.conf" | awk '{print $1}')" = \
	"$SELECTOR_BEFORE" ]
grep -Fqx 'release=wrong' "$FLASH/bird-loader-failure.txt"
grep -Fqx 'reason=unexpected release selector: wrong' \
	"$FLASH/bird-loader-failure.txt"
grep -Fq 'error-called' "$TMP/error.log"

rm -f "$FLASH/bird-loader-failure.txt" "$TMP/error.log"
printf '%s\n' 'quiet bird_release=dev-current' >"$CMDLINE"
if run_loader_failure; then
	printf '%s\n' 'incomplete release unexpectedly passed release loader' >&2
	exit 1
fi
[ "$(shasum -a 256 "$FLASH/extlinux/extlinux.conf" | awk '{print $1}')" = \
	"$SELECTOR_BEFORE" ]
grep -Fqx 'release=dev-current' "$FLASH/bird-loader-failure.txt"
grep -Fqx 'reason=selected release is incomplete' \
	"$FLASH/bird-loader-failure.txt"

if grep -Eq 'KERNEL\.fallback|extlinux\.fallback|reboot -f|write_attempts|fallback_boot' \
		"$LOADER" "$POST_FLASH"; then
	printf '%s\n' 'alternate-boot or retry machinery remains in active hooks' >&2
	exit 1
fi
grep -Fq 'bird_loader_record_failure "$1"' "$LOADER"
grep -Fq 'stop_boot bird-release "Release verification failed: $BIRD_RELEASE"' \
	"$POST_FLASH"
grep -Fq 'BIRD_SYSTEM_RELEASE=$BIRD_RELEASE' "$POST_FLASH"
grep -Fq 'BIRD_SYSTEM_REL=Bird/runtime/$BIRD_SYSTEM_RELEASE/ROCKNIX-SYSTEM' \
	"$POST_FLASH"

# Exercise the initramfs verifier against both canonical manifest authorities.
# Source parity adds one provenance input; it must not weaken the exact stock
# input set or permit arbitrary/duplicate records.
host_sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
host_bytes() { stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"; }

write_runtime_manifest() {
	MODE=$1
	RELEASE_ROOT=$FLASH/bird-releases/dev-current
	rm -rf "$RELEASE_ROOT" "$TMP/data" "$TMP/mounted-data"
	mkdir -p "$RELEASE_ROOT/bird" \
		"$TMP/data/Bird/runtime/dev-current" "$TMP/data/MUOS/runtime" \
		"$TMP/mounted-data" "$FLASH/bird"
	cp "$POST_FLASH" "$RELEASE_ROOT/post-flash.sh"
	printf '%s\n' '#!/bin/sh' ':' >"$RELEASE_ROOT/mount-storage.sh"
	printf '%s\n' '#!/bin/sh' ':' >"$FLASH/mount-storage.sh"
	printf '%s\n' 'contract-fixture' >"$RELEASE_ROOT/bird/bird-device-contract.tsv"
	: >"$TMP/data/Bird/runtime/dev-current/ROCKNIX-SYSTEM"
	: >"$TMP/data/MUOS/runtime/ROCKNIX-STORAGE"
	CONTRACT_SHA=$(host_sha256 "$RELEASE_ROOT/bird/bird-device-contract.tsv")
	MANIFEST=$RELEASE_ROOT/deploy-manifest.tsv
	{
		printf '%b\n' \
			'schema\tbird-deploy-v1' \
			'release\tdev-current' \
			'target-mode-policy\tfat-capability' \
			'source-commit\t0000000000000000000000000000000000000000\tclean'
		printf 'artifact\tdevice-contract\tbird/bird-device-contract.tsv\t%s\n' \
			"$CONTRACT_SHA"
		printf 'artifact\tcatalog\tlauncher/catalog.generated.h\t%s\n' \
			'0000000000000000000000000000000000000000000000000000000000000000'
		for INPUT in \
			KERNEL dtb.img ROCKNIX-SYSTEM ROCKNIX-STORAGE \
			usr/bin/autostart initramfs/init rocknix-singleadc-joypad.ko \
			initramfs/busybox PortMaster.zip PortMaster/pugwash \
			PortMaster/PortMaster.sh PortMaster/mod_ROCKNIX.txt \
			PortMaster/funcs.txt PortMaster/harbourmaster; do
			if [ "$MODE" = missing ] && [ "$INPUT" = KERNEL ]; then
				continue
			fi
			printf 'input\t%s\t644\t1\t%s\tfixture\n' "$INPUT" \
				'0000000000000000000000000000000000000000000000000000000000000000'
		done
		case "$MODE" in
			source|duplicate)
				printf 'input\tsource-kernel-parity.tsv\t644\t1\t%s\tfixture\n' \
					'0000000000000000000000000000000000000000000000000000000000000000'
				;;
			builtin|mixed)
				printf 'input\tsource-kernel-builtin-input.tsv\t644\t1\t%s\tfixture\n' \
					'0000000000000000000000000000000000000000000000000000000000000000'
				;;
			unknown)
				printf 'input\tunknown-authority.tsv\t644\t1\t%s\tfixture\n' \
					'0000000000000000000000000000000000000000000000000000000000000000'
				;;
		esac
		if [ "$MODE" = duplicate ]; then
			printf 'input\tsource-kernel-parity.tsv\t644\t1\t%s\tfixture\n' \
				'0000000000000000000000000000000000000000000000000000000000000000'
		fi
		if [ "$MODE" = mixed ]; then
			printf 'input\tsource-kernel-parity.tsv\t644\t1\t%s\tfixture\n' \
				'0000000000000000000000000000000000000000000000000000000000000000'
		fi
		for SPEC in \
			'post-flash.sh:755' 'mount-storage.sh:755' \
			'bird/bird-device-contract.tsv:644'; do
			REL=${SPEC%:*}
			FILE_MODE=${SPEC#*:}
			printf 'file\t%s\t%s\t%s\t%s\n' "$REL" "$FILE_MODE" \
				"$(host_bytes "$RELEASE_ROOT/$REL")" \
				"$(host_sha256 "$RELEASE_ROOT/$REL")"
		done
	} >"$MANIFEST"
	host_sha256 "$MANIFEST" >"$RELEASE_ROOT/.complete"
}

run_runtime_verifier() (
	BIRD_HOST_TEST_MODE=1
	BIRD_FLASH_ROOT=$FLASH
	BIRD_DATA_DEVICE=/dev/bird-test
	BIRD_DATA_MOUNT=$TMP/mounted-data
	BIRD_SYSTEM_REL=Bird/runtime/dev-current/ROCKNIX-SYSTEM
	BIRD_STORAGE_REL=MUOS/runtime/ROCKNIX-STORAGE
	BIRD_LOADER_SELECTED=dev-current
	export BIRD_HOST_TEST_MODE BIRD_FLASH_ROOT BIRD_DATA_DEVICE \
		BIRD_DATA_MOUNT BIRD_SYSTEM_REL BIRD_STORAGE_REL BIRD_LOADER_SELECTED
	mount() { return 0; }
	umount() { return 0; }
	sync() { return 0; }
	ln -s "$TMP/data/Bird" "$BIRD_DATA_MOUNT/Bird"
	ln -s "$TMP/data/MUOS" "$BIRD_DATA_MOUNT/MUOS"
	bird_loader_sha256() { host_sha256 "$1"; }
	bird_loader_bytes() { host_bytes "$1"; }
	bird_loader_fail() { return 1; }
	. "$FLASH/bird-releases/dev-current/post-flash.sh"
)

for MODE in stock source builtin; do
	write_runtime_manifest "$MODE"
	run_runtime_verifier || {
		printf 'valid %s manifest failed initramfs runtime verification\n' "$MODE" >&2
		exit 1
	}
done
for MODE in unknown duplicate mixed missing; do
	write_runtime_manifest "$MODE"
	if run_runtime_verifier; then
		printf 'invalid %s input manifest passed runtime verification\n' "$MODE" >&2
		exit 1
	fi
done

printf '%s\n' 'boot failure persistence tests passed'
