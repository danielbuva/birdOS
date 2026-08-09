#!/bin/sh
# Host-only transaction tests for the macOS v6.23 updater. Publication and
# selector switching run on a private hdiutil-backed FAT image; disk identity
# metadata comes from a TSV fixture, so no physical block device is addressed.

set -eu

if [ "$(uname -s)" != Darwin ]; then
	printf '%s\n' 'stock-root updater test skipped: macOS host required'
	exit 0
fi

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
UPDATER=$ROOT/firmware/mac-update-rocknix-stock-root-v6.sh
MIGRATION=$ROOT/firmware/mac-migrate-rocknix-ports.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-updater.XXXXXX")
HOST_TMP=$TMP/host-tmp
FAT_DEVICE=
cleanup() {
	[ -z "$FAT_DEVICE" ] || hdiutil detach "$FAT_DEVICE" >/dev/null 2>&1 || :
	rm -rf "$TMP"
}
trap cleanup EXIT INT TERM HUP
mkdir -p "$HOST_TMP"

# Exercise the real publication filesystem, not a spoofed mode field. The
# hdiutil image is private test storage and is never mapped to the physical SD.
BIRD=$TMP/BIRD
FAT_IMAGE=$TMP/bird-fat.dmg
mkdir -p "$BIRD"
hdiutil create -quiet -size 64m -fs MS-DOS -volname BIRDTEST \
	"$FAT_IMAGE"
ATTACH_OUTPUT=$(hdiutil attach -nobrowse -noautoopen -mountpoint "$BIRD" \
	"$FAT_IMAGE")
FAT_DEVICE=$(printf '%s\n' "$ATTACH_OUTPUT" | \
	awk '$2 == "DOS_FAT_32" {print $1; exit}')
[ -n "$FAT_DEVICE" ] || {
	printf '%s\n' 'could not attach temporary FAT updater fixture' >&2
	exit 1
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

bytes() {
	stat -f '%z' "$1"
}

mode() {
	stat -f '%Lp' "$1"
}

write_portmaster_provider_manifest() {
	{
		printf 'schema\tbird-portmaster-provider-v1\n'
		printf 'revision\t2026.07.28-1212\n'
		printf 'source-url\thttps://github.com/PortsMaster/PortMaster-GUI/releases/download/2026.07.28-1212/PortMaster.zip\n'
		printf 'archive\t1\t%s\t%s\n' \
			aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
			bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
		for MANAGED_PATH in PortMaster.sh funcs.txt harbourmaster \
			mod_ROCKNIX.txt pugwash; do
			MANAGED_FILE=$DATA/ROMS/Ports/PortMaster/$MANAGED_PATH
			printf 'file\t%s\t%s\t%s\n' "$MANAGED_PATH" \
				"$(bytes "$MANAGED_FILE")" "$(sha256 "$MANAGED_FILE")"
		done
		printf 'optional-file\tpylibs.zip\t%s\t%s\n' \
			"$(bytes "$PORTMASTER_PYLIBS_FIXTURE")" \
			"$(sha256 "$PORTMASTER_PYLIBS_FIXTURE")"
	} >"$PORTMASTER_PROVIDER_MANIFEST"
}

portmaster_provider_marker_value() {
	printf 'bird-portmaster-v3:2026.07.28-1212:%s\n' \
		"$(sha256 "$PORTMASTER_PROVIDER_MANIFEST")"
}

portmaster_fixture_provider_value() {
	{
		for PROVIDER_PATH in PortMaster.sh control.txt funcs.txt harbourmaster \
			mod_ROCKNIX.txt oga_controls pugwash; do
			printf '%s\t%s\n' "$PROVIDER_PATH" \
				"$(sha256 "$DATA/ROMS/Ports/PortMaster/$PROVIDER_PATH")"
		done
	} | shasum -a 256 | awk '{print $1}'
}

CARD=$TMP/build/card
MANIFEST=$TMP/build/deploy-manifest.tsv
DATA=$TMP/BIRD-DATA
STORAGE_SOURCE=$TMP/storage.ext4
RUNTIME=$DATA/MUOS/runtime/ROCKNIX-SYSTEM
INFO=$TMP/device-info.tsv
UPDATER_RELEASE_ID=v6.23

mkdir -p "$CARD/bird" "$CARD/extlinux" "$BIRD/bird" "$BIRD/extlinux" \
	"$DATA/MUOS/runtime" "$DATA/Bird/boot-state/releases/v6.22" \
	"$DATA/ROMS/Ports/PortMaster" "$CARD/bird/empty-runtime"
printf 'revision\tbird-canonical-namespace-v1\nstate\tcommitted\n' \
	>"$DATA/Bird/namespace-v1.tsv"
PRIOR_ATTEMPTS=$DATA/Bird/boot-state/releases/v6.22/attempts
RELEASE_ATTEMPTS=$DATA/Bird/boot-state/releases/v6.23/attempts
printf '1\n' >"$PRIOR_ATTEMPTS"

printf 'candidate-kernel\n' >"$CARD/KERNEL"
printf 'fixed-dtb\n' >"$CARD/dtb.img"
printf 'early-initramfs\n' >"$CARD/bird-initramfs.cpio.gz"
printf '#!/bin/sh\nexit 0\n' >"$CARD/post-flash.sh"
printf '#!/bin/sh\nexit 0\n' >"$CARD/mount-storage.sh"
printf '#!/bin/sh\nexit 0\n' >"$CARD/bird/bird-suspend.sh"
: >"$CARD/SYSTEM"
printf '%s\n' \
	'LABEL BIRD' \
	'  LINUX /bird-releases/v6.23/KERNEL' \
	'  INITRD /bird-releases/v6.23/bird-initramfs.cpio.gz' \
	'  FDT /bird-releases/v6.23/dtb.img' \
	'  APPEND bird_release=v6.23' >"$CARD/extlinux/extlinux.conf"
printf '%s\n' \
	'LABEL BIRD-FALLBACK' \
	'  LINUX /KERNEL.fallback' \
	'  FDT /dtb.img' >"$CARD/extlinux/extlinux.fallback.conf"
chmod 0700 "$CARD/KERNEL" "$CARD/dtb.img"
chmod 0755 "$CARD/post-flash.sh" "$CARD/mount-storage.sh" \
	"$CARD/bird/bird-suspend.sh"
chmod 0644 "$CARD/SYSTEM" "$CARD/bird-initramfs.cpio.gz" \
	"$CARD/extlinux/extlinux.conf" "$CARD/extlinux/extlinux.fallback.conf"

printf 'exact-runtime\n' >"$RUNTIME"
dd if=/dev/zero of="$STORAGE_SOURCE" bs=2048 count=1 2>/dev/null
printf '\123\357' | dd of="$STORAGE_SOURCE" bs=1 seek=1080 conv=notrunc 2>/dev/null

ROCKNIX_KERNEL_SHA=$(sha256 "$CARD/KERNEL")
DTB_SHA=$(sha256 "$CARD/dtb.img")
RUNTIME_SHA=$(sha256 "$RUNTIME")
STORAGE_SHA=$(sha256 "$STORAGE_SOURCE")
V54_KERNEL=$TMP/fallback-kernel
printf 'fallback-kernel\n' >"$V54_KERNEL"
V54_KERNEL_SHA=$(sha256 "$V54_KERNEL")
AUTOSTART_SHA=1111111111111111111111111111111111111111111111111111111111111111
OFFICIAL_INIT_SHA=2222222222222222222222222222222222222222222222222222222222222222
JOYPAD_SHA=3333333333333333333333333333333333333333333333333333333333333333
INIT_BUSYBOX_SHA=4444444444444444444444444444444444444444444444444444444444444444
PORTMASTER_ARCHIVE_SHA=5555555555555555555555555555555555555555555555555555555555555555
PORTMASTER_PROVIDER_MANIFEST=$TMP/portmaster-provider.manifest.tsv
PORTMASTER_PYLIBS_FIXTURE=$TMP/pylibs.fixture.zip
for NAME in pugwash PortMaster.sh control.txt mod_ROCKNIX.txt funcs.txt \
	oga_controls harbourmaster; do
	printf 'test provider %s\n' "$NAME" >"$DATA/ROMS/Ports/PortMaster/$NAME"
done
printf 'fixture optional pylibs bytes\n' >"$PORTMASTER_PYLIBS_FIXTURE"
chmod 0755 "$DATA/ROMS/Ports/PortMaster/pugwash" \
	"$DATA/ROMS/Ports/PortMaster/PortMaster.sh" \
	"$DATA/ROMS/Ports/PortMaster/harbourmaster"
PORTMASTER_PUGWASH_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/pugwash")
PORTMASTER_SH_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/PortMaster.sh")
PORTMASTER_MOD_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/mod_ROCKNIX.txt")
PORTMASTER_FUNCS_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/funcs.txt")
PORTMASTER_HARBOURMASTER_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/harbourmaster")
write_portmaster_provider_manifest
PORTMASTER_EXPECTED_MARKER=$(portmaster_provider_marker_value)

FILE_LIST=$TMP/file-list
find "$CARD" -type f -print | LC_ALL=C sort >"$FILE_LIST"
DIR_LIST=$TMP/dir-list
find "$CARD" -mindepth 1 -type d -empty -print | LC_ALL=C sort >"$DIR_LIST"
{
	printf 'schema\tbird-deploy-v1\n'
	printf 'release\tv6.23\n'
	printf 'target-mode-policy\tfat-capability\n'
	printf 'source-commit\ttest\tclean\n'
	printf 'input\tKERNEL\t700\t%s\t%s\ttest:KERNEL\n' \
		"$(bytes "$CARD/KERNEL")" "$ROCKNIX_KERNEL_SHA"
	printf 'input\tdtb.img\t700\t%s\t%s\ttest:dtb.img\n' \
		"$(bytes "$CARD/dtb.img")" "$DTB_SHA"
	printf 'input\tROCKNIX-SYSTEM\t644\t%s\t%s\ttest:SYSTEM\n' \
		"$(bytes "$RUNTIME")" "$RUNTIME_SHA"
	printf 'input\tROCKNIX-STORAGE\t644\t%s\t%s\ttest:STORAGE\n' \
		"$(bytes "$STORAGE_SOURCE")" "$STORAGE_SHA"
	printf 'input\tusr/bin/autostart\t755\t1\t%s\ttest:autostart\n' "$AUTOSTART_SHA"
	printf 'input\tinitramfs/init\t755\t1\t%s\ttest:init\n' "$OFFICIAL_INIT_SHA"
	printf 'input\trocknix-singleadc-joypad.ko\t644\t1\t%s\ttest:joypad\n' "$JOYPAD_SHA"
	printf 'input\tinitramfs/busybox\t755\t1\t%s\ttest:busybox\n' "$INIT_BUSYBOX_SHA"
	printf 'input\tPortMaster.zip\t644\t1\t%s\ttest:PortMaster.zip\n' "$PORTMASTER_ARCHIVE_SHA"
	printf 'input\tKERNEL.fallback\t%s\t%s\t%s\ttest:fallback-KERNEL\n' \
		"$(mode "$V54_KERNEL")" "$(bytes "$V54_KERNEL")" "$V54_KERNEL_SHA"
	for NAME in pugwash PortMaster.sh mod_ROCKNIX.txt funcs.txt harbourmaster; do
		FILE=$DATA/ROMS/Ports/PortMaster/$NAME
		printf 'input\tPortMaster/%s\t%s\t%s\t%s\ttest:PortMaster/%s\n' \
			"$NAME" "$(mode "$FILE")" "$(bytes "$FILE")" "$(sha256 "$FILE")" "$NAME"
	done
	while IFS= read -r DIRECTORY; do
		printf 'dir\t%s\t%s\n' "${DIRECTORY#"$CARD"/}" "$(mode "$DIRECTORY")"
	done <"$DIR_LIST"
	while IFS= read -r FILE; do
		RELATIVE=${FILE#"$CARD/"}
		printf 'file\t%s\t%s\t%s\t%s\n' "$RELATIVE" \
			"$(mode "$FILE")" "$(bytes "$FILE")" "$(sha256 "$FILE")"
	done <"$FILE_LIST"
} >"$MANIFEST"

cp "$V54_KERNEL" "$BIRD/KERNEL"
cp "$CARD/dtb.img" "$BIRD/dtb.img"
printf '#!/bin/sh\n# preserved legacy hook\nexit 0\n' >"$BIRD/post-flash.sh"
cp "$CARD/mount-storage.sh" "$BIRD/mount-storage.sh"
cp "$CARD/SYSTEM" "$BIRD/SYSTEM"
printf 'legacy-runtime\n' >"$BIRD/bird/legacy-marker"
printf 'LABEL LEGACY\n  LINUX /KERNEL\n' >"$BIRD/extlinux/extlinux.conf"
touch "$DATA/ROMS/Ports/PortMaster/.bird-release-complete"
LEGACY_HOOK_SHA=$(sha256 "$BIRD/post-flash.sh")

printf '%s\t%s\t%s\n' \
	"$BIRD" 'Part of Whole' testdisk \
	"$DATA" 'Part of Whole' testdisk \
	'/dev/testdisk' 'Device Location' External \
	'/dev/testdisk' 'Protocol' 'Secure Digital' \
	'/dev/testdisk' 'Removable Media' Removable \
	'/dev/testdisk' 'Disk Size' '512074186752 Bytes (512074186752 Bytes)' \
	"$BIRD" 'Device Identifier' testdisks1 \
	"$BIRD" 'Partition Offset' '16777216 Bytes' \
	"$BIRD" 'Disk Size' '134217728 Bytes (134217728 Bytes)' \
	"$BIRD" 'Volume Read-Only' No \
	"$BIRD" 'File System Personality' 'MS-DOS FAT32' \
	'/dev/testdisks5' 'Partition Offset' '163577856 Bytes' \
	'/dev/testdisks5' 'Disk Size' '8589934592 Bytes (8589934592 Bytes)' \
	"$DATA" 'Device Identifier' testdisks6 \
	"$DATA" 'Partition Offset' '8753512448 Bytes' \
	"$DATA" 'Disk Size' '503320672768 Bytes (503320672768 Bytes)' \
	"$DATA" 'Volume Read-Only' No >"$INFO"

run_updater() {
	FAILPOINT=$1
	LC_ALL=${TEST_LOCALE:-C} TMPDIR=${TEST_TMPDIR:-$HOST_TMP} \
	BIRD_HOST_TEST_MODE=1 BIRD=$BIRD DATA=$DATA \
	BIRD_RELEASE_ID=$UPDATER_RELEASE_ID \
	CANDIDATE=$CARD MANIFEST=$MANIFEST \
	STORAGE_SOURCE=$STORAGE_SOURCE BIRD_DEVICE_INFO=$INFO \
	BIRD_TEST_FAILPOINT=$FAILPOINT \
	BIRD_TEST_LOCK_GATE=${LOCK_GATE:-} \
	BIRD_TEST_MANIFEST_GATE=${MANIFEST_GATE:-} \
	BIRD_TEST_PORTMASTER_PROVIDER_MANIFEST="$PORTMASTER_PROVIDER_MANIFEST" \
	"$UPDATER"
}

run_migration() {
	LC_ALL=${TEST_LOCALE:-C} TMPDIR=${TEST_TMPDIR:-$HOST_TMP} \
	BIRD_HOST_TEST_MODE=1 BIRD=$BIRD DATA=$DATA \
	BIRD_DEVICE_INFO=${MIGRATION_INFO:-$INFO} \
	BIRD_TEST_LOCK_GATE=${MIGRATION_GATE:-} \
		"$MIGRATION"
}

assert_production_dev_rejection_unchanged() {
	EXPECTED_SELECTOR_SHA=$1
	[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = \
		"$EXPECTED_SELECTOR_SHA" ]
	[ "$(sha256 "$BIRD/KERNEL")" = "$DEV_GUARD_KERNEL_SHA" ]
	[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/.bird-release-complete")" = \
		"$DEV_GUARD_MARKER_SHA" ]
	[ ! -e "$BIRD/KERNEL.fallback" ]
	[ ! -e "$DATA/MUOS/runtime/ROCKNIX-STORAGE" ]
	[ ! -e "$BIRD/bird-releases/v6.23" ]
	if find "$BIRD/bird-releases" -maxdepth 1 -name '.v6.23.new.*' \
		-print 2>/dev/null | grep -q .; then
		printf '%s\n' 'production dev guard left a release stage' >&2
		exit 1
	fi
}

# dev-current is mutable development state. Neither a requested production ID,
# an active dev selector, dev metadata, nor an installed inactive dev release
# may enter the production updater. Each rejection must precede provider marker
# migration, fallback/storage creation, release staging and selector writes.
DEV_GUARD_ORIGINAL_SELECTOR=$TMP/dev-guard-original-selector.conf
cp "$BIRD/extlinux/extlinux.conf" "$DEV_GUARD_ORIGINAL_SELECTOR"
DEV_GUARD_ORIGINAL_SELECTOR_SHA=$(sha256 "$DEV_GUARD_ORIGINAL_SELECTOR")
DEV_GUARD_KERNEL_SHA=$(sha256 "$BIRD/KERNEL")
DEV_GUARD_MARKER_SHA=$(sha256 \
	"$DATA/ROMS/Ports/PortMaster/.bird-release-complete")

for UPDATER_RELEASE_ID in dev-current Dev-Current DEV-CURRENT; do
	if run_updater none >"$TMP/dev-id.out" 2>"$TMP/dev-id.err"; then
		printf 'production updater accepted reserved release ID: %s\n' \
			"$UPDATER_RELEASE_ID" >&2
		exit 1
	fi
	grep -q 'production release ID dev-current is reserved' "$TMP/dev-id.err"
	grep -Fq 'run ./dev-build-and-deploy.sh --clean' "$TMP/dev-id.err"
	assert_production_dev_rejection_unchanged \
		"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
done
UPDATER_RELEASE_ID=v6.23

printf '%s\n' \
	'LABEL BIRD-DEV' \
	'  LINUX /bird-releases/DEV-CURRENT/KERNEL' \
	'  APPEND bird_release=DEV-CURRENT' >"$BIRD/extlinux/extlinux.conf"
DEV_GUARD_ACTIVE_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
if run_updater none >"$TMP/dev-active.out" 2>"$TMP/dev-active.err"; then
	printf '%s\n' 'production updater accepted active dev-current selector' >&2
	exit 1
fi
grep -q 'active selector names mutable dev-current' "$TMP/dev-active.err"
grep -Fq 'run ./dev-build-and-deploy.sh --clean' "$TMP/dev-active.err"
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ACTIVE_SELECTOR_SHA"
cp "$DEV_GUARD_ORIGINAL_SELECTOR" "$BIRD/extlinux/extlinux.conf"

mkdir "$BIRD/BIRD-DEV"
printf 'must survive production rejection\n' >"$BIRD/BIRD-DEV/state.tsv"
DEV_GUARD_METADATA_SHA=$(sha256 "$BIRD/BIRD-DEV/state.tsv")
if run_updater none >"$TMP/dev-metadata.out" \
		2>"$TMP/dev-metadata.err"; then
	printf '%s\n' 'production updater accepted development metadata' >&2
	exit 1
fi
grep -q 'development metadata exists at BIRD/bird-dev' \
	"$TMP/dev-metadata.err"
grep -Fq 'run ./dev-build-and-deploy.sh --clean' \
	"$TMP/dev-metadata.err"
[ "$(sha256 "$BIRD/BIRD-DEV/state.tsv")" = "$DEV_GUARD_METADATA_SHA" ]
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
rm -rf "$BIRD/BIRD-DEV"

mkdir -p "$BIRD/bird-releases/DEV-CURRENT"
printf 'must survive production rejection\n' \
	>"$BIRD/bird-releases/DEV-CURRENT/.complete"
DEV_GUARD_RELEASE_SHA=$(sha256 \
	"$BIRD/bird-releases/DEV-CURRENT/.complete")
if run_updater none >"$TMP/dev-release.out" \
		2>"$TMP/dev-release.err"; then
	printf '%s\n' 'production updater accepted installed dev-current' >&2
	exit 1
fi
grep -q 'mutable release exists at BIRD/bird-releases/dev-current' \
	"$TMP/dev-release.err"
grep -Fq 'run ./dev-build-and-deploy.sh --clean' \
	"$TMP/dev-release.err"
[ "$(sha256 "$BIRD/bird-releases/DEV-CURRENT/.complete")" = \
	"$DEV_GUARD_RELEASE_SHA" ]
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
rm -rf "$BIRD/bird-releases/DEV-CURRENT"

printf '%s\n' 'schema	bird-dev-cleanup-v1' \
	>"$BIRD/BIRD-DEV-CLEANUP.TSV"
DEV_GUARD_CLEANUP_SHA=$(sha256 "$BIRD/BIRD-DEV-CLEANUP.TSV")
if run_updater none >"$TMP/dev-cleanup.out" \
		2>"$TMP/dev-cleanup.err"; then
	printf '%s\n' 'production updater accepted pending development cleanup' >&2
	exit 1
fi
grep -q 'development cleanup authority exists at BIRD/bird-dev-cleanup.tsv' \
	"$TMP/dev-cleanup.err"
grep -Fq 'run ./dev-build-and-deploy.sh --recover-production then --clean-recovered' \
	"$TMP/dev-cleanup.err"
[ "$(sha256 "$BIRD/BIRD-DEV-CLEANUP.TSV")" = "$DEV_GUARD_CLEANUP_SHA" ]
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
rm -f "$BIRD/BIRD-DEV-CLEANUP.TSV"

printf 'unpublished authority bytes\n' \
	>"$BIRD/.BIRD-DEV-CLEANUP.TSV.DEV-NEW.killed"
DEV_GUARD_CLEANUP_TEMP_SHA=$(sha256 \
	"$BIRD/.BIRD-DEV-CLEANUP.TSV.DEV-NEW.killed")
if run_updater none >"$TMP/dev-cleanup-temp.out" \
		2>"$TMP/dev-cleanup-temp.err"; then
	printf '%s\n' 'production updater accepted interrupted cleanup authority' >&2
	exit 1
fi
grep -q 'interrupted development cleanup-authority publication exists' \
	"$TMP/dev-cleanup-temp.err"
[ "$(sha256 "$BIRD/.BIRD-DEV-CLEANUP.TSV.DEV-NEW.killed")" = \
	"$DEV_GUARD_CLEANUP_TEMP_SHA" ]
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
rm -f "$BIRD/.BIRD-DEV-CLEANUP.TSV.DEV-NEW.killed"

printf 'orphan authority metadata\n' >"$BIRD/._bird-dev-cleanup.tsv"
printf 'orphan temporary metadata\n' \
	>"$BIRD/._.BIRD-DEV-CLEANUP.TSV.DEV-NEW.killed"
printf 'near-prefix metadata\n' >"$BIRD/._bird-dev-cleanup.tsv.keep"
DEV_GUARD_AUTHORITY_SIDECAR_SHA=$(sha256 \
	"$BIRD/._bird-dev-cleanup.tsv")
DEV_GUARD_TEMP_SIDECAR_SHA=$(sha256 \
	"$BIRD/._.BIRD-DEV-CLEANUP.TSV.DEV-NEW.killed")
DEV_GUARD_NEAR_SIDECAR_SHA=$(sha256 \
	"$BIRD/._bird-dev-cleanup.tsv.keep")
if run_updater none >"$TMP/dev-cleanup-sidecar.out" \
		2>"$TMP/dev-cleanup-sidecar.err"; then
	printf '%s\n' 'production updater accepted cleanup AppleDouble metadata' >&2
	exit 1
fi
grep -q 'interrupted development cleanup-authority metadata exists' \
	"$TMP/dev-cleanup-sidecar.err"
[ "$(sha256 "$BIRD/._bird-dev-cleanup.tsv")" = \
	"$DEV_GUARD_AUTHORITY_SIDECAR_SHA" ]
[ "$(sha256 "$BIRD/._.BIRD-DEV-CLEANUP.TSV.DEV-NEW.killed")" = \
	"$DEV_GUARD_TEMP_SIDECAR_SHA" ]
[ "$(sha256 "$BIRD/._bird-dev-cleanup.tsv.keep")" = \
	"$DEV_GUARD_NEAR_SIDECAR_SHA" ]
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
rm -f "$BIRD/._bird-dev-cleanup.tsv" \
	"$BIRD/._.BIRD-DEV-CLEANUP.TSV.DEV-NEW.killed"

# A SIGKILL or power interruption during the initial development copy can
# leave only the hidden publication sibling. It is reserved case-insensitively
# and must block production before provider, fallback, storage, release or
# selector mutation. Other hidden release directories are not development
# state and must remain untouched.
STALE_DEV_STAGE=$BIRD/bird-releases/.DEV-CURRENT.NEW.killed-copy
UNRELATED_HIDDEN=$BIRD/bird-releases/.dev-current.newish.keep
mkdir "$STALE_DEV_STAGE" "$UNRELATED_HIDDEN"
printf 'partial development copy\n' >"$STALE_DEV_STAGE/payload"
printf 'unrelated hidden bytes\n' >"$UNRELATED_HIDDEN/payload"
STALE_DEV_STAGE_SHA=$(sha256 "$STALE_DEV_STAGE/payload")
UNRELATED_HIDDEN_SHA=$(sha256 "$UNRELATED_HIDDEN/payload")
if run_updater none >"$TMP/dev-stage.out" 2>"$TMP/dev-stage.err"; then
	printf '%s\n' 'production updater accepted stale development stage' >&2
	exit 1
fi
grep -Fq 'stale mutable release stage exists at BIRD/bird-releases/.dev-current.new.*' \
	"$TMP/dev-stage.err"
grep -Fq 'run ./dev-build-and-deploy.sh --clean' "$TMP/dev-stage.err"
[ "$(sha256 "$STALE_DEV_STAGE/payload")" = "$STALE_DEV_STAGE_SHA" ]
[ "$(sha256 "$UNRELATED_HIDDEN/payload")" = "$UNRELATED_HIDDEN_SHA" ]
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
rm -rf "$STALE_DEV_STAGE"

# The early read-only guard is not sufficient: a completed development
# transaction can publish mutable state while production is preparing its
# manifest. The updater must reject that state again after it owns the shared
# card lock and before any deployment mutation.
MANIFEST_GATE=$TMP/dev-post-lock-gate
mkdir "$MANIFEST_GATE"
run_updater none >"$TMP/dev-post-lock.out" 2>"$TMP/dev-post-lock.err" &
DEV_POST_LOCK_JOB=$!
DEV_POST_LOCK_WAIT=0
while [ ! -f "$MANIFEST_GATE/snapshot-ready" ]; do
	DEV_POST_LOCK_WAIT=$((DEV_POST_LOCK_WAIT + 1))
	[ "$DEV_POST_LOCK_WAIT" -le 400 ] || {
		cat "$TMP/dev-post-lock.err" >&2
		printf '%s\n' 'updater did not reach the post-preflight dev race gate' >&2
		exit 1
	}
	sleep 0.02
done
mkdir "$BIRD/bird-dev"
printf 'published after production preflight\n' >"$BIRD/bird-dev/state.tsv"
DEV_POST_LOCK_STATE_SHA=$(sha256 "$BIRD/bird-dev/state.tsv")
: >"$MANIFEST_GATE/release-snapshot"
set +e
wait "$DEV_POST_LOCK_JOB"
DEV_POST_LOCK_STATUS=$?
set -e
[ "$DEV_POST_LOCK_STATUS" -ne 0 ] || {
	printf '%s\n' 'updater accepted dev-current state published after preflight' >&2
	exit 1
}
grep -q 'development metadata exists at BIRD/bird-dev' \
	"$TMP/dev-post-lock.err"
[ "$(sha256 "$BIRD/bird-dev/state.tsv")" = "$DEV_POST_LOCK_STATE_SHA" ]
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
rm -rf "$BIRD/bird-dev"
MANIFEST_GATE=
[ "$(sha256 "$BIRD/._bird-dev-cleanup.tsv.keep")" = \
	"$DEV_GUARD_NEAR_SIDECAR_SHA" ]
rm -f "$BIRD/._bird-dev-cleanup.tsv.keep"

MANIFEST_GATE=$TMP/cleanup-authority-post-lock-gate
mkdir "$MANIFEST_GATE"
run_updater none >"$TMP/cleanup-post-lock.out" \
	2>"$TMP/cleanup-post-lock.err" &
CLEANUP_POST_LOCK_JOB=$!
CLEANUP_POST_LOCK_WAIT=0
while [ ! -f "$MANIFEST_GATE/snapshot-ready" ]; do
	CLEANUP_POST_LOCK_WAIT=$((CLEANUP_POST_LOCK_WAIT + 1))
	[ "$CLEANUP_POST_LOCK_WAIT" -le 400 ] || {
		cat "$TMP/cleanup-post-lock.err" >&2
		printf '%s\n' 'updater did not reach cleanup-authority race gate' >&2
		exit 1
	}
	sleep 0.02
done
printf 'published cleanup authority after preflight\n' \
	>"$BIRD/BIRD-DEV-CLEANUP.TSV"
CLEANUP_POST_LOCK_SHA=$(sha256 "$BIRD/BIRD-DEV-CLEANUP.TSV")
: >"$MANIFEST_GATE/release-snapshot"
set +e
wait "$CLEANUP_POST_LOCK_JOB"
CLEANUP_POST_LOCK_STATUS=$?
set -e
[ "$CLEANUP_POST_LOCK_STATUS" -ne 0 ] || {
	printf '%s\n' 'updater accepted cleanup authority published after preflight' >&2
	exit 1
}
grep -q 'development cleanup authority exists at BIRD/bird-dev-cleanup.tsv' \
	"$TMP/cleanup-post-lock.err"
[ "$(sha256 "$BIRD/BIRD-DEV-CLEANUP.TSV")" = "$CLEANUP_POST_LOCK_SHA" ]
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
rm -f "$BIRD/BIRD-DEV-CLEANUP.TSV"
MANIFEST_GATE=

# Revalidation must remain bound to the same whole disk whose lock is held.
# Swapping the identity fixture after preflight models an unmount/remount race;
# production must stop before touching the newly resolved card.
ORIGINAL_INFO=$TMP/device-info-original.tsv
SWITCHED_INFO=$TMP/device-info-switched.tsv
cp "$INFO" "$ORIGINAL_INFO"
sed 's/testdisk/otherdisk/g' "$ORIGINAL_INFO" >"$SWITCHED_INFO"
LOCK_GATE=$TMP/identity-post-lock-gate
mkdir "$LOCK_GATE"
run_updater hold-after-lock >"$TMP/identity-post-lock.out" \
	2>"$TMP/identity-post-lock.err" &
IDENTITY_POST_LOCK_JOB=$!
IDENTITY_POST_LOCK_WAIT=0
while [ ! -f "$LOCK_GATE/owner-ready" ]; do
	IDENTITY_POST_LOCK_WAIT=$((IDENTITY_POST_LOCK_WAIT + 1))
	[ "$IDENTITY_POST_LOCK_WAIT" -le 400 ] || {
		cat "$TMP/identity-post-lock.err" >&2
		printf '%s\n' 'updater did not reach the identity-switch race gate' >&2
		exit 1
	}
	sleep 0.02
done
cp "$SWITCHED_INFO" "$INFO"
: >"$LOCK_GATE/release-owner"
set +e
wait "$IDENTITY_POST_LOCK_JOB"
IDENTITY_POST_LOCK_STATUS=$?
set -e
[ "$IDENTITY_POST_LOCK_STATUS" -ne 0 ] || {
	printf '%s\n' 'updater accepted a different card after acquiring its lock' >&2
	exit 1
}
grep -q 'card identity changed after acquiring its production transaction lock' \
	"$TMP/identity-post-lock.err"
assert_production_dev_rejection_unchanged \
	"$DEV_GUARD_ORIGINAL_SELECTOR_SHA"
cp "$ORIGINAL_INFO" "$INFO"
LOCK_GATE=

ACTIVE_BEFORE=$(sha256 "$BIRD/extlinux/extlinux.conf")
mkdir -p "$DATA/ports/LegacyGame"
if run_updater none >"$TMP/legacy.out" 2>"$TMP/legacy.err"; then
	printf '%s\n' 'legacy Port migration unexpectedly ran inside updater' >&2
	exit 1
fi
grep -q 'legacy /ports data must be migrated separately' "$TMP/legacy.err"
[ -d "$DATA/ports/LegacyGame" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
rm -rf "$DATA/ports"

# Exact provider verification precedes every destructive deployment action.
# A rejected managed revision must not remove an interrupted stage, create a
# fallback/storage copy, publish a marker, stage a release or switch selectors.
PROVIDER_REJECT_STAGE=$BIRD/bird-releases/.v6.23.new.provider-reject
mkdir -p "$PROVIDER_REJECT_STAGE"
printf 'must survive provider rejection\n' >"$PROVIDER_REJECT_STAGE/sentinel"
cp "$DATA/ROMS/Ports/PortMaster/funcs.txt" "$TMP/provider-funcs.original"
printf 'managed mutation\n' >>"$DATA/ROMS/Ports/PortMaster/funcs.txt"
PROVIDER_REJECT_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
PROVIDER_REJECT_KERNEL_SHA=$(sha256 "$BIRD/KERNEL")
PROVIDER_REJECT_MARKER_SHA=$(sha256 \
	"$DATA/ROMS/Ports/PortMaster/.bird-release-complete")
if run_updater none >"$TMP/provider-reject.out" 2>"$TMP/provider-reject.err"; then
	printf '%s\n' 'mutated managed PortMaster provider unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'managed file size changed: funcs.txt' "$TMP/provider-reject.err"
grep -q 'installed PortMaster provider is not a pinned complete revision' \
	"$TMP/provider-reject.err"
[ -f "$PROVIDER_REJECT_STAGE/sentinel" ]
[ ! -e "$BIRD/KERNEL.fallback" ]
[ ! -e "$DATA/MUOS/runtime/ROCKNIX-STORAGE" ]
[ ! -e "$BIRD/bird-releases/v6.23" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PROVIDER_REJECT_SELECTOR_SHA" ]
[ "$(sha256 "$BIRD/KERNEL")" = "$PROVIDER_REJECT_KERNEL_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/.bird-release-complete")" = \
	"$PROVIDER_REJECT_MARKER_SHA" ]
mv "$TMP/provider-funcs.original" "$DATA/ROMS/Ports/PortMaster/funcs.txt"
rm -rf "$PROVIDER_REJECT_STAGE"

# A syntactically valid v3 checkpoint is immutable evidence, not a migratable
# legacy marker.  If it names any other manifest, reject before stale-stage
# cleanup or publication and leave every provider/card byte untouched.
PORTMASTER_MARKER=$DATA/ROMS/Ports/PortMaster/.bird-release-complete
PROVIDER_V3_REJECT_STAGE=$BIRD/bird-releases/.v6.23.new.v3-marker-reject
mkdir -p "$PROVIDER_V3_REJECT_STAGE"
printf 'must survive v3 marker rejection\n' \
	>"$PROVIDER_V3_REJECT_STAGE/sentinel"
PROVIDER_MISMATCHED_V3=bird-portmaster-v3:2026.07.28-1212:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
printf '%s\n' "$PROVIDER_MISMATCHED_V3" >"$PORTMASTER_MARKER"
PROVIDER_V3_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
PROVIDER_V3_KERNEL_SHA=$(sha256 "$BIRD/KERNEL")
PROVIDER_V3_PUGWASH_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/pugwash")
PROVIDER_V3_SCRIPT_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/PortMaster.sh")
PROVIDER_V3_MOD_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/mod_ROCKNIX.txt")
PROVIDER_V3_FUNCS_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/funcs.txt")
PROVIDER_V3_HARBOURMASTER_SHA=$(sha256 \
	"$DATA/ROMS/Ports/PortMaster/harbourmaster")
PROVIDER_V3_CONTROL_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/control.txt")
PROVIDER_V3_OGA_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/oga_controls")
if run_updater none >"$TMP/v3-marker-reject.out" \
		2>"$TMP/v3-marker-reject.err"; then
	printf '%s\n' 'mismatched PortMaster v3 marker unexpectedly migrated' >&2
	exit 1
fi
grep -q 'PortMaster' "$TMP/v3-marker-reject.err"
[ -f "$PROVIDER_V3_REJECT_STAGE/sentinel" ]
[ ! -e "$BIRD/KERNEL.fallback" ]
[ ! -e "$DATA/MUOS/runtime/ROCKNIX-STORAGE" ]
[ ! -e "$BIRD/bird-releases/v6.23" ]
[ "$(cat "$PORTMASTER_MARKER")" = "$PROVIDER_MISMATCHED_V3" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PROVIDER_V3_SELECTOR_SHA" ]
[ "$(sha256 "$BIRD/KERNEL")" = "$PROVIDER_V3_KERNEL_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/pugwash")" = \
	"$PROVIDER_V3_PUGWASH_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/PortMaster.sh")" = \
	"$PROVIDER_V3_SCRIPT_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/mod_ROCKNIX.txt")" = \
	"$PROVIDER_V3_MOD_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/funcs.txt")" = \
	"$PROVIDER_V3_FUNCS_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/harbourmaster")" = \
	"$PROVIDER_V3_HARBOURMASTER_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/control.txt")" = \
	"$PROVIDER_V3_CONTROL_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/oga_controls")" = \
	"$PROVIDER_V3_OGA_SHA" ]
: >"$PORTMASTER_MARKER"
rm -rf "$PROVIDER_V3_REJECT_STAGE"

# Replacing the caller-owned manifest after its complete preflight must not
# affect any later field lookup or staging loop. The injected replacement
# points KERNEL one level above the hidden stage; the private snapshot must be
# the only manifest read, so that out-of-stage destination never appears.
ORIGINAL_MANIFEST=$MANIFEST
SWAPPABLE_MANIFEST=$TMP/deploy-manifest-swappable.tsv
MALICIOUS_MANIFEST=$TMP/deploy-manifest-traversal-after-preflight.tsv
ESCAPE_SOURCE=$CARD/../escaped-output
ESCAPE_TARGET=$BIRD/bird-releases/escaped-output
cp "$ORIGINAL_MANIFEST" "$SWAPPABLE_MANIFEST"
cp "$CARD/KERNEL" "$ESCAPE_SOURCE"
awk -F '\t' 'BEGIN {OFS="\t"}
	$1 == "file" && $2 == "KERNEL" {$2="../escaped-output"}
	{print}
' "$ORIGINAL_MANIFEST" >"$MALICIOUS_MANIFEST"
MANIFEST=$SWAPPABLE_MANIFEST
MANIFEST_GATE=$TMP/manifest-snapshot-gate
mkdir "$MANIFEST_GATE"
run_updater during-release-stage >"$TMP/manifest-swap.out" \
	2>"$TMP/manifest-swap.err" &
MANIFEST_SWAP_JOB=$!
GATE_WAIT=0
while [ ! -f "$MANIFEST_GATE/snapshot-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/manifest-swap.err" >&2
		printf '%s\n' 'updater did not complete manifest snapshot preflight' >&2
		exit 1
	}
	sleep 0.02
done
mv -f "$MALICIOUS_MANIFEST" "$SWAPPABLE_MANIFEST"
: >"$MANIFEST_GATE/release-snapshot"
set +e
wait "$MANIFEST_SWAP_JOB"
MANIFEST_SWAP_STATUS=$?
set -e
[ "$MANIFEST_SWAP_STATUS" -ne 0 ] || {
	printf '%s\n' 'manifest-swap stage failure unexpectedly succeeded' >&2
	exit 1
}
grep -q 'host-only injected failure: during-release-stage' \
	"$TMP/manifest-swap.err"
[ ! -e "$ESCAPE_TARGET" ] || {
	printf '%s\n' 'mutable manifest escaped the private release stage' >&2
	exit 1
}
[ ! -e "$BIRD/bird-releases/v6.23" ]
MANIFEST_GATE=
MANIFEST=$ORIGINAL_MANIFEST
rm -f "$ESCAPE_SOURCE"

if run_updater kill-during-release-stage >"$TMP/kill.out" 2>"$TMP/kill.err"; then
	printf '%s\n' 'SIGKILL stage injection unexpectedly succeeded' >&2
	exit 1
fi
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
find "$BIRD/bird-releases" -maxdepth 1 -name '.v6.23.new.*' | grep -q .

if run_updater during-release-stage >"$TMP/stage.out" 2>"$TMP/stage.err"; then
	printf '%s\n' 'incomplete-stage injection unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'host-only injected failure: during-release-stage' "$TMP/stage.err"
[ ! -e "$BIRD/bird-releases/v6.23" ]
if find "$BIRD/bird-releases" -maxdepth 1 -name '.v6.23.new.*' | grep -q .; then
	printf '%s\n' 'incomplete release staging directory survived' >&2
	exit 1
fi
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
[ "$(sha256 "$BIRD/post-flash.sh")" = "$LEGACY_HOOK_SHA" ]

# A complete release may become durable before the one selector switch.  An
# interruption at that boundary must leave the previous selector active.
if run_updater before-selector-activation >"$TMP/pre-activation.out" \
	2>"$TMP/pre-activation.err"; then
	printf '%s\n' 'pre-activation injection unexpectedly succeeded' >&2
	exit 1
fi
if ! grep -q 'host-only injected failure: before-selector-activation' \
	"$TMP/pre-activation.err"; then
	cat "$TMP/pre-activation.err" >&2
	printf '%s\n' 'pre-activation failpoint was not reached' >&2
	exit 1
fi
[ -f "$BIRD/bird-releases/v6.23/.complete" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
[ "$(cat "$RELEASE_ATTEMPTS")" = 0 ]
[ "$(cat "$PRIOR_ATTEMPTS")" = 1 ]

if run_updater after-selector-rename >"$TMP/post-activation.out" \
	2>"$TMP/post-activation.err"; then
	printf '%s\n' 'post-selector injection unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'selector activation failed; previous selector restored' \
	"$TMP/post-activation.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
[ "$(sha256 "$BIRD/post-flash.sh")" = "$LEGACY_HOOK_SHA" ]
[ "$(cat "$PRIOR_ATTEMPTS")" = 1 ]

# The abrupt boundary differs from the rollback simulation above: terminate
# immediately after the selector rename, before post-rename sync/verification.
# The exact new selector may remain active only because its complete release
# was already durable; the next invocation must recover the stale host owner.
CARD_LOCK_ROOT=/tmp/bird-card-locks
CARD_LOCK=$CARD_LOCK_ROOT/testdisk.lock
if run_updater kill-after-selector-rename >"$TMP/selector-kill.out" \
	2>"$TMP/selector-kill.err"; then
	printf '%s\n' 'post-selector SIGKILL unexpectedly succeeded' >&2
	exit 1
fi
cmp "$CARD/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.conf"
[ -f "$BIRD/bird-releases/v6.23/.complete" ]
cmp "$MANIFEST" "$BIRD/bird-releases/v6.23/deploy-manifest.tsv"
[ -L "$CARD_LOCK" ]

if ! run_updater none >"$TMP/install.out" 2>"$TMP/install.err"; then
	cat "$TMP/install.err" >&2
	exit 1
fi
grep -Fq 'Production omits the serial console; the fixed diagnostic fallback retains it.' \
	"$TMP/install.out"
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]

# The namespace is deliberately fixed across effective UIDs. Simulate a
# privileged/unprivileged mismatch through id(1): the second identity must
# reject the first owner's verified root rather than create a parallel lock.
FAKE_UID_BIN=$TMP/fake-cross-uid-bin
mkdir "$FAKE_UID_BIN"
cat >"$FAKE_UID_BIN/id" <<'EOF'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = -u ]; then
	printf '%s\n' 4294967294
	exit 0
fi
exec /usr/bin/id "$@"
EOF
chmod 0755 "$FAKE_UID_BIN/id"
HOST_REAL_PATH=$PATH
if PATH=$FAKE_UID_BIN:$PATH run_migration >"$TMP/cross-uid.out" \
	2>"$TMP/cross-uid.err"; then
	printf '%s\n' 'migration acquired a parallel cross-UID card lock' >&2
	exit 1
fi
PATH=$HOST_REAL_PATH
grep -q 'Bird card lock directory owner is unsafe' "$TMP/cross-uid.err"
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]

# A predictable mutex below /tmp must never be opened through a hostile
# symlink. Use a distinct synthetic whole-disk identity so the safe testdisk
# mutex remains untouched, and prove the writable target retains its bytes.
HOSTILE_WHOLE=hostiletestdisk$$
HOSTILE_INFO=$TMP/device-info-hostile-lock.tsv
awk -F '\t' -v bird="$BIRD" -v data="$DATA" -v whole="$HOSTILE_WHOLE" \
	'BEGIN {OFS="\t"}
	$1 == bird && $2 == "Part of Whole" {$3=whole}
	$1 == data && $2 == "Part of Whole" {$3=whole}
	$1 == bird && $2 == "Device Identifier" {$3=whole "s1"}
	$1 == data && $2 == "Device Identifier" {$3=whole "s6"}
	$1 == "/dev/testdisk" {$1="/dev/" whole}
	{print}
' "$INFO" >"$HOSTILE_INFO"
HOSTILE_TARGET=$TMP/hostile-lock-target
HOSTILE_SERIAL=$CARD_LOCK_ROOT/$HOSTILE_WHOLE.serial
HOSTILE_TRANSACTION=$CARD_LOCK_ROOT/$HOSTILE_WHOLE.transaction
printf '%s\n' 'must-not-be-truncated' >"$HOSTILE_TARGET"
ln -s "$HOSTILE_TARGET" "$HOSTILE_SERIAL"
MIGRATION_INFO=$HOSTILE_INFO
if run_migration >"$TMP/hostile-lock.out" 2>"$TMP/hostile-lock.err"; then
	printf '%s\n' 'migration opened a hostile lock mutex symlink' >&2
	exit 1
fi
grep -q 'Bird card lock mutex is unsafe' "$TMP/hostile-lock.err"
[ "$(cat "$HOSTILE_TARGET")" = 'must-not-be-truncated' ]
rm -f "$HOSTILE_SERIAL"
rm -f "$HOSTILE_TRANSACTION"
MIGRATION_INFO=

RELEASE=$BIRD/bird-releases/v6.23
[ -f "$RELEASE/.complete" ]
cmp "$MANIFEST" "$RELEASE/deploy-manifest.tsv"
[ -d "$RELEASE/bird/empty-runtime" ]
cmp "$CARD/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.conf"
[ "$(sha256 "$BIRD/post-flash.sh")" = "$LEGACY_HOOK_SHA" ]
[ -s "$DATA/ROMS/Ports/PortMaster/.bird-release-complete" ]
[ "$(cat "$DATA/ROMS/Ports/PortMaster/.bird-release-complete")" = \
	"$PORTMASTER_EXPECTED_MARKER" ]
PREVIOUS_SHA=$(sha256 "$BIRD/extlinux/extlinux.previous.conf")

run_updater none >"$TMP/idempotent.out"
[ "$(sha256 "$BIRD/extlinux/extlinux.previous.conf")" = "$PREVIOUS_SHA" ]

# SIGKILL after publishing the same-filesystem marker temporary must leave the
# legacy marker authoritative. The only .new artifact is the external sibling;
# a later locked invocation removes it, migrates the marker and succeeds.
PORTMASTER_MARKER=$DATA/ROMS/Ports/PortMaster/.bird-release-complete
PORTMASTER_INTERRUPTED_LEGACY=bird-portmaster-v2:interrupted-marker-stage
printf '%s\n' "$PORTMASTER_INTERRUPTED_LEGACY" >"$PORTMASTER_MARKER"
PORTMASTER_INTERRUPTED_PROVIDER_SHA=$(portmaster_fixture_provider_value)
PORTMASTER_INTERRUPTED_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
if run_updater kill-during-portmaster-marker-stage \
		>"$TMP/portmaster-marker-kill.out" \
		2>"$TMP/portmaster-marker-kill.err"; then
	printf '%s\n' 'PortMaster marker-stage SIGKILL unexpectedly succeeded' >&2
	exit 1
fi
[ "$(cat "$PORTMASTER_MARKER")" = "$PORTMASTER_INTERRUPTED_LEGACY" ]
[ "$(portmaster_fixture_provider_value)" = \
	"$PORTMASTER_INTERRUPTED_PROVIDER_SHA" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = \
	"$PORTMASTER_INTERRUPTED_SELECTOR_SHA" ]
PORTMASTER_STALE_LIST=$TMP/portmaster-stale-markers
find "$DATA/ROMS/Ports" -name '*.new.*' -print | \
	LC_ALL=C sort >"$PORTMASTER_STALE_LIST"
[ "$(wc -l <"$PORTMASTER_STALE_LIST" | tr -d '[:space:]')" = 1 ]
PORTMASTER_STALE_MARKER=$(cat "$PORTMASTER_STALE_LIST")
case "$PORTMASTER_STALE_MARKER" in
	"$DATA"/ROMS/Ports/.bird-portmaster-marker.new.*) ;;
	*) printf '%s\n' 'marker-stage interruption left an unsafe temporary' >&2; exit 1 ;;
esac
[ -f "$PORTMASTER_STALE_MARKER" ] && [ ! -L "$PORTMASTER_STALE_MARKER" ]
[ "$(cat "$PORTMASTER_STALE_MARKER")" = "$PORTMASTER_EXPECTED_MARKER" ]
if find "$BIRD/bird-releases" -maxdepth 1 -name '.v6.23.new.*' | grep -q .; then
	printf '%s\n' 'marker-stage interruption left a release stage' >&2
	exit 1
fi
run_updater none >"$TMP/portmaster-marker-recovery.out"
[ "$(cat "$PORTMASTER_MARKER")" = "$PORTMASTER_EXPECTED_MARKER" ]
[ "$(portmaster_fixture_provider_value)" = \
	"$PORTMASTER_INTERRUPTED_PROVIDER_SHA" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = \
	"$PORTMASTER_INTERRUPTED_SELECTOR_SHA" ]
if find "$DATA/ROMS/Ports" -name '*.new.*' -print | grep -q .; then
	printf '%s\n' 'recovered updater left a PortMaster marker temporary' >&2
	exit 1
fi

# Stale empty/v1/v2 markers are migratable only after the exact managed tree
# verifies. Marker migration never rewrites provider or mutable adapter bytes.
PORTMASTER_MARKER=$DATA/ROMS/Ports/PortMaster/.bird-release-complete
PORTMASTER_MANAGED_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/pugwash")
PORTMASTER_CONTROL_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/control.txt")
for PORTMASTER_LEGACY_KIND in empty v1 v2; do
	case "$PORTMASTER_LEGACY_KIND" in
		empty) : >"$PORTMASTER_MARKER" ;;
		v1) printf 'bird-portmaster-v1:stale-checkpoint\n' >"$PORTMASTER_MARKER" ;;
		v2) printf 'bird-portmaster-v2:stale-checkpoint\n' >"$PORTMASTER_MARKER" ;;
	esac
	run_updater none >"$TMP/stale-portmaster-$PORTMASTER_LEGACY_KIND.out"
	[ "$(cat "$PORTMASTER_MARKER")" = "$PORTMASTER_EXPECTED_MARKER" ]
	[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/pugwash")" = \
		"$PORTMASTER_MANAGED_SHA" ]
	[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/control.txt")" = \
		"$PORTMASTER_CONTROL_SHA" ]
done

# The single optional pylibs.zip record permits absence or the exact pinned
# bytes, but never an arbitrary network-provided archive.
cp "$PORTMASTER_PYLIBS_FIXTURE" \
	"$DATA/ROMS/Ports/PortMaster/pylibs.zip"
run_updater none >"$TMP/portmaster-pylibs-exact.out"
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/pylibs.zip")" = \
	"$(sha256 "$PORTMASTER_PYLIBS_FIXTURE")" ]
printf X | dd of="$DATA/ROMS/Ports/PortMaster/pylibs.zip" \
	bs=1 seek=0 conv=notrunc 2>/dev/null
PORTMASTER_PYLIBS_BAD_SHA=$(sha256 \
	"$DATA/ROMS/Ports/PortMaster/pylibs.zip")
PORTMASTER_PYLIBS_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
PORTMASTER_PYLIBS_MARKER_SHA=$(sha256 "$PORTMASTER_MARKER")
if run_updater none >"$TMP/portmaster-pylibs-arbitrary.out" \
		2>"$TMP/portmaster-pylibs-arbitrary.err"; then
	printf '%s\n' 'arbitrary present PortMaster pylibs.zip unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'managed file digest changed: pylibs.zip' \
	"$TMP/portmaster-pylibs-arbitrary.err"
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/pylibs.zip")" = \
	"$PORTMASTER_PYLIBS_BAD_SHA" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = \
	"$PORTMASTER_PYLIBS_SELECTOR_SHA" ]
[ "$(sha256 "$PORTMASTER_MARKER")" = "$PORTMASTER_PYLIBS_MARKER_SHA" ]
rm -f "$DATA/ROMS/Ports/PortMaster/pylibs.zip"
run_updater none >"$TMP/portmaster-pylibs-absent.out"

# Managed byte mutation, an unlisted managed file and a managed symlink all
# fail closed without moving the selector or rewriting the last good marker.
cp "$DATA/ROMS/Ports/PortMaster/pugwash" "$TMP/portmaster-pugwash.saved"
printf 'network mutation\n' >>"$DATA/ROMS/Ports/PortMaster/pugwash"
PORTMASTER_FAILURE_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
PORTMASTER_FAILURE_MARKER_SHA=$(sha256 "$PORTMASTER_MARKER")
if run_updater none >"$TMP/mutated-portmaster.out" \
		2>"$TMP/mutated-portmaster.err"; then
	printf '%s\n' 'mutated managed PortMaster provider unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'managed file size changed: pugwash' "$TMP/mutated-portmaster.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PORTMASTER_FAILURE_SELECTOR_SHA" ]
[ "$(sha256 "$PORTMASTER_MARKER")" = "$PORTMASTER_FAILURE_MARKER_SHA" ]
mv "$TMP/portmaster-pugwash.saved" "$DATA/ROMS/Ports/PortMaster/pugwash"

printf 'extra managed byte\n' >"$DATA/ROMS/Ports/PortMaster/unlisted-managed-file"
if run_updater none >"$TMP/extra-portmaster.out" \
		2>"$TMP/extra-portmaster.err"; then
	printf '%s\n' 'extra managed PortMaster file unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'managed provider file set differs from the pinned revision' \
	"$TMP/extra-portmaster.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PORTMASTER_FAILURE_SELECTOR_SHA" ]
[ "$(sha256 "$PORTMASTER_MARKER")" = "$PORTMASTER_FAILURE_MARKER_SHA" ]
rm -f "$DATA/ROMS/Ports/PortMaster/unlisted-managed-file"

cp "$DATA/ROMS/Ports/PortMaster/funcs.txt" "$TMP/portmaster-funcs.saved"
rm -f "$DATA/ROMS/Ports/PortMaster/funcs.txt"
ln -s "$TMP/portmaster-funcs.saved" \
	"$DATA/ROMS/Ports/PortMaster/funcs.txt"
if run_updater none >"$TMP/symlink-portmaster.out" \
		2>"$TMP/symlink-portmaster.err"; then
	printf '%s\n' 'managed PortMaster symlink unexpectedly succeeded' >&2
	exit 1
fi
if ! grep -Eq \
		'managed provider file set differs|managed provider contains a symlink' \
		"$TMP/symlink-portmaster.err"; then
	cat "$TMP/symlink-portmaster.err" >&2
	printf '%s\n' 'managed PortMaster symlink failed for the wrong reason' >&2
	exit 1
fi
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PORTMASTER_FAILURE_SELECTOR_SHA" ]
[ "$(sha256 "$PORTMASTER_MARKER")" = "$PORTMASTER_FAILURE_MARKER_SHA" ]
rm -f "$DATA/ROMS/Ports/PortMaster/funcs.txt"
mv "$TMP/portmaster-funcs.saved" "$DATA/ROMS/Ports/PortMaster/funcs.txt"

# Runtime adapters, downloaded runtimes, settings and logs are deliberately
# excluded. They may vary and must remain byte-identical through deployment.
printf 'custom controls\n' >"$DATA/ROMS/Ports/PortMaster/control.txt"
printf 'custom oga mapping\n' >"$DATA/ROMS/Ports/PortMaster/oga_controls"
mkdir -p "$DATA/ROMS/Ports/PortMaster/config" \
	"$DATA/ROMS/Ports/PortMaster/runtimes/custom"
printf 'mutable settings\n' >"$DATA/ROMS/Ports/PortMaster/config/user.ini"
printf 'downloaded runtime\n' \
	>"$DATA/ROMS/Ports/PortMaster/runtimes/custom/runtime.bin"
printf 'session log\n' >"$DATA/ROMS/Ports/PortMaster/log.txt"
PORTMASTER_CONTROL_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/control.txt")
PORTMASTER_OGA_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/oga_controls")
PORTMASTER_CONFIG_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/config/user.ini")
PORTMASTER_RUNTIME_SHA=$(sha256 \
	"$DATA/ROMS/Ports/PortMaster/runtimes/custom/runtime.bin")
run_updater none >"$TMP/mutable-portmaster.out"
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/control.txt")" = \
	"$PORTMASTER_CONTROL_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/oga_controls")" = \
	"$PORTMASTER_OGA_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/config/user.ini")" = \
	"$PORTMASTER_CONFIG_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/runtimes/custom/runtime.bin")" = \
	"$PORTMASTER_RUNTIME_SHA" ]
[ "$(cat "$PORTMASTER_MARKER")" = "$PORTMASTER_EXPECTED_MARKER" ]

# Once an immutable release is authoritative, the pre-versioned root KERNEL is
# redundant. Its absence must remain a supported steady state; the selected
# release, selector and fallback are still independently verified.
ABSENT_KERNEL_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
ABSENT_KERNEL_RELEASE_SHA=$(sha256 "$RELEASE/KERNEL")
ABSENT_KERNEL_FALLBACK_SHA=$(sha256 "$BIRD/KERNEL.fallback")
rm -f "$BIRD/KERNEL"
run_updater none >"$TMP/absent-root-kernel.out"
[ ! -e "$BIRD/KERNEL" ] && [ ! -L "$BIRD/KERNEL" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ABSENT_KERNEL_SELECTOR_SHA" ]
[ "$(sha256 "$RELEASE/KERNEL")" = "$ABSENT_KERNEL_RELEASE_SHA" ]
[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$ABSENT_KERNEL_FALLBACK_SHA" ]

ln -s "$TMP/missing-kernel-target" "$BIRD/KERNEL"
if run_updater none >"$TMP/dangling-root-kernel.out" \
		2>"$TMP/dangling-root-kernel.err"; then
	printf '%s\n' 'dangling legacy root KERNEL unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'legacy top-level KERNEL is a symlink or special node' \
	"$TMP/dangling-root-kernel.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ABSENT_KERNEL_SELECTOR_SHA" ]
rm -f "$BIRD/KERNEL"

mv "$BIRD/KERNEL.fallback" "$TMP/KERNEL.fallback.saved"
if run_updater none >"$TMP/missing-fallback.out" 2>"$TMP/missing-fallback.err"; then
	printf '%s\n' 'missing fallback with no root KERNEL unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'v5.4 fallback KERNEL is missing' "$TMP/missing-fallback.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ABSENT_KERNEL_SELECTOR_SHA" ]
mv "$TMP/KERNEL.fallback.saved" "$BIRD/KERNEL.fallback"
[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$ABSENT_KERNEL_FALLBACK_SHA" ]

# Prove lock ordering, not only exclusion: a contender waiting on the lifetime
# transaction lock must not hold the short serial mutex needed by the owner to
# release. Once the live owner is ungated, both operations finish successfully
# instead of deadlocking until the contender timeout.
ORDER_GATE=$TMP/lock-order-gate
mkdir "$ORDER_GATE"
LOCK_GATE=$ORDER_GATE
run_updater hold-after-lock >"$TMP/order-owner.out" \
	2>"$TMP/order-owner.err" &
ORDER_OWNER_JOB=$!
GATE_WAIT=0
while [ ! -f "$ORDER_GATE/owner-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/order-owner.err" >&2
		printf '%s\n' 'lock-order owner did not become ready' >&2
		exit 1
	}
	sleep 0.02
done
run_migration >"$TMP/order-contender.out" \
	2>"$TMP/order-contender.err" &
ORDER_CONTENDER_JOB=$!
sleep 0.1
kill -0 "$ORDER_CONTENDER_JOB"
: >"$ORDER_GATE/release-owner"
set +e
wait "$ORDER_OWNER_JOB"
ORDER_OWNER_STATUS=$?
wait "$ORDER_CONTENDER_JOB"
ORDER_CONTENDER_STATUS=$?
set -e
[ "$ORDER_OWNER_STATUS" -eq 0 ] || {
	cat "$TMP/order-owner.err" >&2
	exit 1
}
[ "$ORDER_CONTENDER_STATUS" -eq 0 ] || {
	cat "$TMP/order-contender.err" >&2
	exit 1
}
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]
LOCK_GATE=

# Updater and migration share one atomic owner symlink. A paused live updater
# blocks migration; SIGKILL leaves a complete stale identity which migration
# recovers under the lockf mutex. Killing that recovery owner is recoverable.
mkdir -p "$DATA/ports/SharedLockTest"
BAD_MIGRATION_INFO=$TMP/device-info-not-p6.tsv
awk -F '\t' -v data="$DATA" 'BEGIN {OFS="\t"}
	$1 == data && $2 == "Device Identifier" {$3="testdisks5"}
	{print}
' "$INFO" >"$BAD_MIGRATION_INFO"
MIGRATION_INFO=$BAD_MIGRATION_INFO
if run_migration >"$TMP/migrate-not-p6.out" 2>"$TMP/migrate-not-p6.err"; then
	printf '%s\n' 'migration accepted a data volume that was not p6' >&2
	exit 1
fi
if ! grep -q 'data is not p6' "$TMP/migrate-not-p6.err"; then
	cat "$TMP/migrate-not-p6.err" >&2
	printf '%s\n' 'migration p6 rejection was not reported' >&2
	exit 1
fi
[ -d "$DATA/ports/SharedLockTest" ]
MIGRATION_INFO=
# The lock owner and contender both run under a locale whose ps(1) lstart
# rendering is non-English. The helper's internal LC_ALL=C normalization must
# still preserve the live owner's exact identity and reject the contender.
TEST_LOCALE=fa_IR.UTF-8
[ "$(LC_ALL=$TEST_LOCALE ps -p $$ -o lstart=)" != \
	"$(LC_ALL=C ps -p $$ -o lstart=)" ] || {
	printf '%s\n' 'lock locale fixture did not produce localized ps output' >&2
	exit 1
}
LOCK_GATE=$TMP/update-lock-gate
mkdir "$LOCK_GATE"
run_updater hold-after-lock >"$TMP/paused-owner.out" \
	2>"$TMP/paused-owner.err" &
PAUSED_JOB=$!
GATE_WAIT=0
while [ ! -f "$LOCK_GATE/owner-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/paused-owner.err" >&2
		printf '%s\n' 'updater did not publish its atomic host lock' >&2
		exit 1
	}
	sleep 0.02
done
PAUSED_OWNER=$(cat "$LOCK_GATE/owner-ready")
PAUSED_TOKEN=$(readlink "$CARD_LOCK")
[ "${PAUSED_TOKEN%%:*}" = "$PAUSED_OWNER" ]
case "$PAUSED_TOKEN" in *[!0-9A-Za-z:]*) exit 1 ;; esac
kill -STOP "$PAUSED_OWNER"
# A second process deliberately uses a different TMPDIR. It must still reach
# the same fixed /tmp lock and reject the paused live owner.
TEST_TMPDIR=$TMP/different-host-tmp
mkdir "$TEST_TMPDIR"
if run_migration >"$TMP/migrate-blocked.out" 2>"$TMP/migrate-blocked.err"; then
	printf '%s\n' 'migration bypassed a paused updater owner' >&2
	exit 1
fi
grep -q 'another Bird card transaction is active' "$TMP/migrate-blocked.err"
[ -d "$DATA/ports/SharedLockTest" ]
TEST_TMPDIR=
kill -KILL "$PAUSED_OWNER"
set +e
wait "$PAUSED_JOB"
set -e
[ "$(readlink "$CARD_LOCK")" = "$PAUSED_TOKEN" ]
LOCK_GATE=

MIGRATION_GATE=$TMP/migration-lock-gate
mkdir "$MIGRATION_GATE"
run_migration >"$TMP/recovery-owner.out" 2>"$TMP/recovery-owner.err" &
RECOVERY_JOB=$!
GATE_WAIT=0
while [ ! -f "$MIGRATION_GATE/owner-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/recovery-owner.err" >&2
		printf '%s\n' 'migration did not recover the SIGKILLed updater lock' >&2
		exit 1
	}
	sleep 0.02
done
RECOVERY_OWNER=$(cat "$MIGRATION_GATE/owner-ready")
RECOVERY_TOKEN=$(readlink "$CARD_LOCK")
[ "${RECOVERY_TOKEN%%:*}" = "$RECOVERY_OWNER" ]
kill -KILL "$RECOVERY_OWNER"
set +e
wait "$RECOVERY_JOB"
set -e
[ "$(readlink "$CARD_LOCK")" = "$RECOVERY_TOKEN" ]
MIGRATION_GATE=

run_migration >"$TMP/migration-recovered.out"
[ -d "$DATA/ROMS/Ports/SharedLockTest" ]
[ ! -e "$DATA/ports" ]
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]
TEST_LOCALE=C

# A child doing card I/O inherits the full-lifetime advisory descriptor. If
# the updater shell is SIGKILLed, its owner symlink becomes diagnostically
# stale but must not be recovered while that orphan can still mutate bytes.
mkdir -p "$DATA/ports/OrphanChildLockTest"
ORPHAN_GATE=$TMP/orphan-child-lock-gate
mkdir "$ORPHAN_GATE"
LOCK_GATE=$ORPHAN_GATE
run_updater orphan-child-after-lock >"$TMP/orphan-owner.out" \
	2>"$TMP/orphan-owner.err" &
ORPHAN_JOB=$!
GATE_WAIT=0
while [ ! -f "$ORPHAN_GATE/owner-ready" ] || \
	[ ! -f "$ORPHAN_GATE/mutator-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/orphan-owner.err" >&2
		printf '%s\n' 'orphan-child lock fixture did not become ready' >&2
		exit 1
	}
	sleep 0.02
done
ORPHAN_OWNER=$(cat "$ORPHAN_GATE/owner-ready")
ORPHAN_MUTATOR=$(cat "$ORPHAN_GATE/mutator-ready")
ORPHAN_TOKEN=$(readlink "$CARD_LOCK")
[ "${ORPHAN_TOKEN%%:*}" = "$ORPHAN_OWNER" ]
kill -0 "$ORPHAN_MUTATOR"
ORPHAN_TARGET=$DATA/orphan-mutator-probe
MUTATOR_BEFORE=$(bytes "$ORPHAN_TARGET")
sleep 0.1
MUTATOR_AFTER=$(bytes "$ORPHAN_TARGET")
[ "$MUTATOR_AFTER" -gt "$MUTATOR_BEFORE" ]
kill -KILL "$ORPHAN_OWNER"
set +e
wait "$ORPHAN_JOB"
set -e
[ "$(readlink "$CARD_LOCK")" = "$ORPHAN_TOKEN" ]
kill -0 "$ORPHAN_MUTATOR"
MUTATOR_BEFORE=$(bytes "$ORPHAN_TARGET")
if run_migration >"$TMP/orphan-contender.out" \
	2>"$TMP/orphan-contender.err"; then
	printf '%s\n' 'migration bypassed an inherited orphan mutator lock' >&2
	exit 1
fi
grep -q 'another Bird card transaction is active (owner or inherited mutator child)' \
	"$TMP/orphan-contender.err"
MUTATOR_AFTER=$(bytes "$ORPHAN_TARGET")
[ "$MUTATOR_AFTER" -gt "$MUTATOR_BEFORE" ]
[ "$(readlink "$CARD_LOCK")" = "$ORPHAN_TOKEN" ]
: >"$ORPHAN_GATE/release-mutator"
GATE_WAIT=0
while kill -0 "$ORPHAN_MUTATOR" 2>/dev/null; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		printf '%s\n' 'orphan mutator did not exit after release' >&2
		exit 1
	}
	sleep 0.02
done
LOCK_GATE=
run_migration >"$TMP/orphan-recovered.out"
[ -d "$DATA/ROMS/Ports/OrphanChildLockTest" ]
[ ! -e "$DATA/ports" ]
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]

GOOD_MANIFEST=$MANIFEST
ACTIVE_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")

MALFORMED_MANIFEST=$TMP/deploy-manifest-malformed.tsv
cp "$GOOD_MANIFEST" "$MALFORMED_MANIFEST"
printf 'unknown\trecord\n' >>"$MALFORMED_MANIFEST"
if MANIFEST=$MALFORMED_MANIFEST run_updater none >"$TMP/malformed.out" 2>"$TMP/malformed.err"; then
	printf '%s\n' 'malformed manifest unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'canonical deploy manifest is malformed' "$TMP/malformed.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

DUPLICATE_MANIFEST=$TMP/deploy-manifest-duplicate.tsv
cp "$GOOD_MANIFEST" "$DUPLICATE_MANIFEST"
awk -F '\t' '$1 == "file" && $2 == "KERNEL" {print; exit}' \
	"$GOOD_MANIFEST" >>"$DUPLICATE_MANIFEST"
if MANIFEST=$DUPLICATE_MANIFEST run_updater none >"$TMP/duplicate.out" 2>"$TMP/duplicate.err"; then
	printf '%s\n' 'duplicate manifest path unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'canonical deploy manifest has duplicate paths' "$TMP/duplicate.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

TRAVERSAL_MANIFEST=$TMP/deploy-manifest-traversal.tsv
cp "$GOOD_MANIFEST" "$TRAVERSAL_MANIFEST"
printf 'file\t../escape\t644\t1\t%s\n' \
	0000000000000000000000000000000000000000000000000000000000000000 \
	>>"$TRAVERSAL_MANIFEST"
if MANIFEST=$TRAVERSAL_MANIFEST run_updater none >"$TMP/traversal.out" 2>"$TMP/traversal.err"; then
	printf '%s\n' 'manifest traversal unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'canonical deploy manifest is malformed' "$TMP/traversal.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

MANIFEST=$GOOD_MANIFEST
ln -s KERNEL "$CARD/candidate-link"
if run_updater none >"$TMP/candidate-link.out" 2>"$TMP/candidate-link.err"; then
	printf '%s\n' 'candidate symlink unexpectedly succeeded' >&2
	exit 1
fi
if ! grep -q 'candidate contains a symlink or special node' \
	"$TMP/candidate-link.err"; then
	cat "$TMP/candidate-link.err" >&2
	printf '%s\n' 'candidate symlink rejection was not reported' >&2
	exit 1
fi
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]
rm -f "$CARD/candidate-link"

BAD_MANIFEST=$TMP/deploy-manifest-corrupt.tsv
awk -F '\t' 'BEGIN {OFS="\t"}
	$1 == "file" && $2 == "KERNEL" {
		$5="0000000000000000000000000000000000000000000000000000000000000000"
	}
	{print}
' "$MANIFEST" >"$BAD_MANIFEST"
if MANIFEST=$BAD_MANIFEST run_updater none >"$TMP/bad-manifest.out" 2>"$TMP/bad-manifest.err"; then
	printf '%s\n' 'corrupt manifest unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'candidate digest changed: KERNEL' "$TMP/bad-manifest.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

MANIFEST=$GOOD_MANIFEST
printf 'unlisted\n' >"$CARD/unlisted-payload"
if run_updater none >"$TMP/unlisted.out" 2>"$TMP/unlisted.err"; then
	printf '%s\n' 'unlisted candidate payload unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'candidate regular-file set differs from canonical manifest' \
	"$TMP/unlisted.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]
rm -f "$CARD/unlisted-payload"

printf 'corrupt\n' >>"$RELEASE/bird/bird-suspend.sh"
if run_updater none >"$TMP/bad-release.out" 2>"$TMP/bad-release.err"; then
	printf '%s\n' 'corrupt installed release unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'installed release size changed: bird/bird-suspend.sh' \
	"$TMP/bad-release.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]
cp "$CARD/bird/bird-suspend.sh" "$RELEASE/bird/bird-suspend.sh"

printf 'corrupt\n' >>"$CARD/bird/bird-suspend.sh"
if run_updater none >"$TMP/bad-candidate.out" 2>"$TMP/bad-candidate.err"; then
	printf '%s\n' 'corrupt candidate unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'candidate size changed: bird/bird-suspend.sh' "$TMP/bad-candidate.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

# A caller-selected release ID must drive the manifest contract, immutable
# directory, selector and boot-attempt namespace together. Rebuild only the
# small fixture selector and its canonical file record; every other byte stays
# identical to the already-verified candidate.
cp "$RELEASE/bird/bird-suspend.sh" "$CARD/bird/bird-suspend.sh"
DYNAMIC_ID=v6.23-host-test
DYNAMIC_CARD=$TMP/dynamic-build/card
mkdir -p "${DYNAMIC_CARD%/*}"
cp -R "$CARD" "$DYNAMIC_CARD"
sed "s#v6\.23#$DYNAMIC_ID#g" "$CARD/extlinux/extlinux.conf" \
	>"$DYNAMIC_CARD/extlinux/extlinux.conf"
DYNAMIC_SELECTOR_BYTES=$(bytes "$DYNAMIC_CARD/extlinux/extlinux.conf")
DYNAMIC_SELECTOR_SHA=$(sha256 "$DYNAMIC_CARD/extlinux/extlinux.conf")
DYNAMIC_MANIFEST=$TMP/dynamic-build/deploy-manifest.tsv
awk -F '\t' -v release="$DYNAMIC_ID" -v selector_bytes="$DYNAMIC_SELECTOR_BYTES" \
	-v selector_sha="$DYNAMIC_SELECTOR_SHA" 'BEGIN {OFS="\t"}
	$1 == "release" {$2=release}
	$1 == "file" && $2 == "extlinux/extlinux.conf" {
		$4=selector_bytes
		$5=selector_sha
	}
	{print}
' "$GOOD_MANIFEST" >"$DYNAMIC_MANIFEST"
CARD=$DYNAMIC_CARD
MANIFEST=$DYNAMIC_MANIFEST
UPDATER_RELEASE_ID=$DYNAMIC_ID
run_updater none >"$TMP/dynamic-release.out"
DYNAMIC_RELEASE=$BIRD/bird-releases/$DYNAMIC_ID
[ -f "$DYNAMIC_RELEASE/.complete" ]
cmp "$DYNAMIC_MANIFEST" "$DYNAMIC_RELEASE/deploy-manifest.tsv"
grep -Fq "bird_release=$DYNAMIC_ID" "$BIRD/extlinux/extlinux.conf"
[ "$(cat "$DATA/Bird/boot-state/releases/$DYNAMIC_ID/attempts")" = 0 ]
[ -f "$BIRD/bird-releases/v6.23/.complete" ]

printf '%s\n' 'stock-root updater transaction tests passed'
