#!/bin/sh
# Transactionally change only the one raw sector containing the exact paired
# compressed-kernel bound. No partition or filesystem byte is a write target.

set -eu
umask 077

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DEVICE=${1:-}
ACTION=${2:---install}
PAIR_PROFILE=${BIRD_BOOT_PAIR_PROFILE:-no-raid6-benchmark}
case "$PAIR_PROFILE" in
	no-raid6-benchmark)
		DEFAULT_AUTHORITY=$ROOT/kernel/work/bird-no-raid6-benchmark-pair-20260830
		RESTORE_ACTION=--restore-fixed-command-closure
		BASE_PREFIX_SHA=c156973946fd1f1fcb581eeb669abb638ce554cf16356db60428ba1ebb3a9c1b
		TARGET_PREFIX_SHA=c1a390a9c674029a21caf12eaec8d7b788dbe700b20cd7729276c9cf03214d32
		BASE_UBOOT_SHA=918d9b8a0dd89ffb291a866eefa630c796ea7e3199ba92ce9664e6a72500161f
		TARGET_UBOOT_SHA=5352c2f635b1f741c8d1fcfb647e9ce2ea570311cbd8b476944d71338654f2f0
		VERIFIER=$ROOT/kernel/rocknix/verify-no-raid6-benchmark-pair-build.py
		VERIFIER_SHA=20216c5047503134b3952fe181b2adf0c095fdb04f913304adbb6fd9f4062f16
		BASE_PREFIX_FILE=fixed-command-closure-base-prefix-16m.bin
		TARGET_PREFIX_FILE=no-raid6-benchmark-pair-prefix-16m.bin
		BASE_UBOOT_FILE=fixed-command-closure-base.bin
		TARGET_UBOOT_FILE=no-raid6-benchmark-pair.bin
		TARGET_DESCRIPTION='no-RAID6-benchmark paired U-Boot'
		BASE_DESCRIPTION='accepted fixed-command-closure U-Boot'
		;;
	deferred-wifi)
		DEFAULT_AUTHORITY=$ROOT/kernel/work/bird-deferred-wifi-pair-20260830-v3
		RESTORE_ACTION=--restore-stage11
		BASE_PREFIX_SHA=c1a390a9c674029a21caf12eaec8d7b788dbe700b20cd7729276c9cf03214d32
		TARGET_PREFIX_SHA=b1a27dda2742c8982be848aef35db1f8e340c0feb24aaeeca94028d10b02ae2d
		BASE_UBOOT_SHA=5352c2f635b1f741c8d1fcfb647e9ce2ea570311cbd8b476944d71338654f2f0
		TARGET_UBOOT_SHA=d0a9fcab2c7908c44febe1d387d99dc1916ff0d6b6dcb4a398c7df77a9a7a3e8
		VERIFIER=$ROOT/kernel/rocknix/verify-deferred-wifi-pair-build.py
		VERIFIER_SHA=09e786c6994ea31bae139307fe3608131e0ae4a0a3e9a466fa04db96e0ebdce9
		BASE_PREFIX_FILE=stage11-no-raid6-benchmark-prefix-16m.bin
		TARGET_PREFIX_FILE=deferred-wifi-pair-prefix-16m.bin
		BASE_UBOOT_FILE=stage11-no-raid6-benchmark.bin
		TARGET_UBOOT_FILE=deferred-wifi-pair.bin
		TARGET_DESCRIPTION='deferred-Wi-Fi paired U-Boot'
		BASE_DESCRIPTION='accepted Stage 11 U-Boot'
		;;
	*) printf 'error: unknown BIRD_BOOT_PAIR_PROFILE: %s\n' "$PAIR_PROFILE" >&2; exit 1 ;;
esac
AUTHORITY=${3:-$DEFAULT_AUTHORITY}
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/BIRD-DATA}
GDD=${GDD:-/opt/homebrew/bin/gdd}

PREFIX_BYTES=16777216
SECTOR_BYTES=512
SECTOR_INDEX=571
SECTOR_OFFSET=292352
INVENTORY=$ROOT/kernel/rocknix/inventory-bird-boot-volume.py
VERIFY_WORK=
MOUNTED=1
LOCKED=0
COMMITTED=0

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
regular() { [ -f "$1" ] && [ ! -L "$1" ]; }

case "$DEVICE" in /dev/disk[0-9]*) ;; *) fail 'first argument must be a whole /dev/diskN device' ;; esac
case "${DEVICE#/dev/disk}" in *[!0-9]*|'') fail 'partition devices and unsafe disk names are refused' ;; esac
case "$ACTION" in --install|"$RESTORE_ACTION") ;; *) fail "action must be --install or $RESTORE_ACTION" ;; esac
[ "$(uname -s)" = Darwin ] || fail 'this installer is supported only on macOS'
command -v "$GDD" >/dev/null 2>&1 || fail 'GNU dd is required'
regular "$VERIFIER" && [ "$(sha256 "$VERIFIER")" = "$VERIFIER_SHA" ] || fail 'boot-pair verifier identity changed'
regular "$INVENTORY" || fail 'BIRD inventory tool is missing or unsafe'
[ -d "$AUTHORITY" ] && [ ! -L "$AUTHORITY" ] || fail 'boot-pair authority is missing or unsafe'
python3 "$VERIFIER" --verify-output "$AUTHORITY" >/dev/null || fail 'boot-pair authority verification failed'

BASE_PREFIX=$AUTHORITY/$BASE_PREFIX_FILE
TARGET_PREFIX=$AUTHORITY/$TARGET_PREFIX_FILE
BASE_UBOOT=$AUTHORITY/$BASE_UBOOT_FILE
TARGET_UBOOT=$AUTHORITY/$TARGET_UBOOT_FILE
regular "$BASE_PREFIX" && [ "$(stat -f %z "$BASE_PREFIX")" -eq "$PREFIX_BYTES" ] && [ "$(sha256 "$BASE_PREFIX")" = "$BASE_PREFIX_SHA" ] || fail 'accepted base prefix changed'
regular "$TARGET_PREFIX" && [ "$(stat -f %z "$TARGET_PREFIX")" -eq "$PREFIX_BYTES" ] && [ "$(sha256 "$TARGET_PREFIX")" = "$TARGET_PREFIX_SHA" ] || fail 'target prefix changed'
regular "$BASE_UBOOT" && [ "$(sha256 "$BASE_UBOOT")" = "$BASE_UBOOT_SHA" ] || fail 'accepted base U-Boot changed'
regular "$TARGET_UBOOT" && [ "$(sha256 "$TARGET_UBOOT")" = "$TARGET_UBOOT_SHA" ] || fail 'target U-Boot changed'

# shellcheck source=mac-removable-device.sh
. "$ROOT/firmware/mac-removable-device.sh"
# shellcheck source=mac-stock-root-card-identity.sh
. "$ROOT/firmware/mac-stock-root-card-identity.sh"
# shellcheck source=mac-bird-card-lock.sh
. "$ROOT/firmware/mac-bird-card-lock.sh"

plist_value() { diskutil info -plist "$1" | plutil -extract "$2" raw -o - -; }
validate_card() {
	validate_stock_root_card_identity
	[ "/dev/$WHOLE" = "$DEVICE" ] || fail 'requested disk differs from the mounted Bird card'
	bird_require_safe_removable_device "$DEVICE"
}

remove_work() {
	[ -n "$VERIFY_WORK" ] || return 0
	case "$VERIFY_WORK" in
		/var/folders/*|/private/var/folders/*|/private/tmp/*|/tmp/*) /bin/rm -rf "$VERIFY_WORK" ;;
		*) return 1 ;;
	esac
}
mount_card() {
	[ "$MOUNTED" -eq 0 ] || return 0
	diskutil mountDisk "$DEVICE" >/dev/null || return 1
	MOUNTED=1
}
unmount_card() {
	[ "$MOUNTED" -eq 1 ] || return 0
	sync
	if ! diskutil unmountDisk "$DEVICE" >/dev/null; then
		printf 'Ordinary unmount was refused; retrying the exact verified card with force.\n' >&2
		diskutil unmountDisk force "$DEVICE" >/dev/null || return 1
	fi
	MOUNTED=0
}
force_unmount_card() {
	if ! diskutil unmountDisk "$DEVICE" >/dev/null; then
		diskutil unmountDisk force "$DEVICE" >/dev/null || return 1
	fi
	MOUNTED=0
}
read_prefix() {
	destination=$1
	: >"$destination" && chmod 600 "$destination" || return 1
	sudo -n "$GDD" if="/dev/r${WHOLE}" bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock status=none >"$destination" || return 1
	[ "$(stat -f %z "$destination")" -eq "$PREFIX_BYTES" ]
}
write_sector() {
	source=$1
	sudo -n "$GDD" if="$source" of="/dev/r${WHOLE}" bs="$SECTOR_BYTES" seek="$SECTOR_INDEX" count=1 conv=notrunc status=none
	sync
}
recover_original() {
	printf 'Boot-pair transaction did not commit; restoring the exact original U-Boot sector...\n' >&2
	force_unmount_card || return 1
	write_sector "$VERIFY_WORK/before-sector.bin" || return 1
	read_prefix "$VERIFY_WORK/recovered-prefix.bin" || return 1
	[ "$(sha256 "$VERIFY_WORK/recovered-prefix.bin")" = "$EXPECTED_CURRENT_SHA" ] || return 1
	mount_card || return 1
}
cleanup() {
	status=$?
	if [ "$MOUNTED" -eq 0 ]; then mount_card || :; fi
	if [ "$LOCKED" -eq 1 ]; then bird_card_lock_release || :; fi
	if [ "$status" -eq 0 ] && [ "$COMMITTED" -eq 1 ]; then
		remove_work || :
	elif [ -n "$VERIFY_WORK" ]; then
		printf 'Host diagnostic snapshot retained at: %s\n' "$VERIFY_WORK" >&2
	fi
	exit "$status"
}
trap cleanup EXIT HUP INT TERM

validate_card
LOCKED_WHOLE=$WHOLE
sudo -v
bird_card_lock_acquire
LOCKED=1
validate_card
[ "$WHOLE" = "$LOCKED_WHOLE" ] || fail 'card identity changed after acquiring its transaction lock'

VERIFY_WORK=$(mktemp -d "${TMPDIR:-/tmp}/bird-boot-pair-install.XXXXXX") || fail 'could not create private verification directory'
COPYFILE_DISABLE=1 cp -R "$AUTHORITY" "$VERIFY_WORK/authority" || fail 'could not snapshot the complete boot-pair authority under lock'
python3 "$VERIFIER" --verify-output "$VERIFY_WORK/authority" >/dev/null || fail 'snapshotted boot-pair authority verification failed'
BASE_PREFIX=$VERIFY_WORK/authority/$BASE_PREFIX_FILE
TARGET_PREFIX=$VERIFY_WORK/authority/$TARGET_PREFIX_FILE
BASE_UBOOT=$VERIFY_WORK/authority/$BASE_UBOOT_FILE
TARGET_UBOOT=$VERIFY_WORK/authority/$TARGET_UBOOT_FILE
python3 "$INVENTORY" "$BIRD" >"$VERIFY_WORK/bird-before.tsv" || fail 'could not inventory BIRD before raw write'
read_prefix "$VERIFY_WORK/before-prefix.bin" || fail 'could not snapshot the current raw prefix'
CURRENT_SHA=$(sha256 "$VERIFY_WORK/before-prefix.bin")

if [ "$ACTION" = --install ]; then
	EXPECTED_CURRENT_SHA=$BASE_PREFIX_SHA
	EXPECTED_TARGET_SHA=$TARGET_PREFIX_SHA
	SECTOR_SOURCE=$TARGET_PREFIX
	DESCRIPTION=$TARGET_DESCRIPTION
else
	EXPECTED_CURRENT_SHA=$TARGET_PREFIX_SHA
	EXPECTED_TARGET_SHA=$BASE_PREFIX_SHA
	SECTOR_SOURCE=$BASE_PREFIX
	DESCRIPTION=$BASE_DESCRIPTION
fi
if [ "$CURRENT_SHA" = "$EXPECTED_TARGET_SHA" ]; then
	printf 'Verified %s is already installed.\n' "$DESCRIPTION"
	COMMITTED=1
	exit 0
fi
[ "$CURRENT_SHA" = "$EXPECTED_CURRENT_SHA" ] || fail "current raw prefix is not the exact reviewed predecessor: $CURRENT_SHA"

"$GDD" if="$VERIFY_WORK/before-prefix.bin" of="$VERIFY_WORK/before-sector.bin" bs="$SECTOR_BYTES" skip="$SECTOR_INDEX" count=1 status=none
"$GDD" if="$SECTOR_SOURCE" of="$VERIFY_WORK/target-sector.bin" bs="$SECTOR_BYTES" skip="$SECTOR_INDEX" count=1 status=none
[ "$(stat -f %z "$VERIFY_WORK/before-sector.bin")" -eq "$SECTOR_BYTES" ] && [ "$(stat -f %z "$VERIFY_WORK/target-sector.bin")" -eq "$SECTOR_BYTES" ] || fail 'bounded sector extraction changed'

unmount_card || fail 'could not unmount the complete Bird card before raw write'
if ! write_sector "$VERIFY_WORK/target-sector.bin" || ! read_prefix "$VERIFY_WORK/after-prefix.bin" || [ "$(sha256 "$VERIFY_WORK/after-prefix.bin" 2>/dev/null || :)" != "$EXPECTED_TARGET_SHA" ]; then
	if ! recover_original; then fail 'automatic original-prefix restoration failed'; fi
	fail 'bounded paired U-Boot write did not verify and was restored'
fi
mount_card || {
	if ! recover_original; then fail 'card remount failed and automatic restoration also failed'; fi
	fail 'card remount failed after paired U-Boot write; accepted prefix restored'
}
python3 "$INVENTORY" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" || {
	if ! recover_original; then fail 'BIRD verification failed and automatic restoration also failed'; fi
	fail 'BIRD verification failed after raw write; accepted prefix restored'
}
if ! cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null; then
	if ! recover_original; then fail 'BIRD changed and automatic restoration also failed'; fi
	fail 'BIRD payload changed during raw write; accepted prefix restored'
fi

COMMITTED=1
printf '%s installed; exact 16 MiB prefix and unchanged BIRD payload verified.\n' "$DESCRIPTION"
printf 'Only raw sector %s at byte range [%s,%s) was a write target.\n' "$SECTOR_INDEX" "$SECTOR_OFFSET" "$((SECTOR_OFFSET + SECTOR_BYTES))"
printf 'Safe eject: diskutil eject /dev/%s\n' "$WHOLE"
