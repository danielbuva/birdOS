#!/bin/sh
# Host-only tests for the guarded top-level build/deploy command. Every volume,
# build output and simulated selector is below one private temporary directory.

set -eu

if [ "$(uname -s)" != Darwin ]; then
	printf '%s\n' 'build-and-deploy tests skipped: macOS host required'
	exit 0
fi

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
COMMAND=$ROOT/build-and-deploy.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-build-deploy-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

mode() {
	stat -f '%Lp' "$1"
}

bytes() {
	stat -f '%z' "$1"
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

FAKE_BUILDER=$TMP/fake-builder.sh
FAKE_UPDATER=$TMP/fake-updater.sh
FAKE_TOOL=$TMP/fake-tool
FAKE_GH=$TMP/fake-gh.sh
LOCK_HOLDER=$TMP/lock-holder.sh

cat >"$FAKE_TOOL" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$FAKE_GH" <<'EOF'
#!/bin/sh
set -eu

COMMAND=${1:-}
shift || :
	case "$COMMAND" in
	auth) exit 0 ;;
	repo)
		[ "${1:-}" = view ] || exit 2
		[ "${TEST_GH_BEHAVIOR:-normal}" != public-repository ] || {
			printf '%s\n' PUBLIC
			exit 0
		}
		printf '%s\n' PRIVATE
		;;
	api)
		[ "${TEST_GH_BEHAVIOR:-normal}" != immutable-disabled ] || exit 1
		printf '%s\n' true
		;;
	release)
		SUBCOMMAND=${1:-}
		shift || :
		TAG=${1:-}
		[ -n "$TAG" ] || exit 2
		shift || :
		STATE=$TEST_STATE/gh-release-$TAG-state
		ASSET_DIR=$TEST_STATE/gh-release-$TAG-assets
		case "$SUBCOMMAND" in
			view)
				[ -f "$STATE" ] || exit 1
				case " $* " in
					*' --json isDraft '*) cat "$STATE" ;;
					*' --json assets '*) find "$ASSET_DIR" -type f -maxdepth 1 -print 2>/dev/null | while IFS= read -r FILE; do basename "$FILE"; done | LC_ALL=C sort ;;
				esac
				;;
			create)
				mkdir -p "$ASSET_DIR"
				printf '%s\n' true >"$STATE"
				printf 'create %s\n' "$TAG" >>"$TEST_STATE/gh-events"
				;;
			upload)
				[ -f "$STATE" ] || exit 1
				[ "${TEST_GH_BEHAVIOR:-normal}" != upload-failure ] || exit 1
				mkdir -p "$ASSET_DIR"
				while [ "$#" -gt 0 ]; do
					case "$1" in
						--repo) shift 2 ;;
						--clobber) shift ;;
						--*) shift ;;
						*) cp "$1" "$ASSET_DIR/$(basename "$1")"; shift ;;
					esac
				done
				printf 'upload %s\n' "$TAG" >>"$TEST_STATE/gh-events"
				;;
			edit)
				[ -f "$STATE" ] || exit 1
				printf '%s\n' false >"$STATE"
				printf 'publish %s\n' "$TAG" >>"$TEST_STATE/gh-events"
				;;
			verify)
				[ -f "$STATE" ] && [ "$(cat "$STATE")" = false ] || exit 1
				;;
			verify-asset)
				[ -f "$STATE" ] && [ "$(cat "$STATE")" = false ] || exit 1
				LOCAL_ASSET=${1:-}
				[ -f "$ASSET_DIR/$(basename "$LOCAL_ASSET")" ] || exit 1
				cmp "$LOCAL_ASSET" "$ASSET_DIR/$(basename "$LOCAL_ASSET")"
				;;
			download)
				PATTERN=
				DESTINATION=
				while [ "$#" -gt 0 ]; do
					case "$1" in
						--pattern) PATTERN=$2; shift 2 ;;
						--dir) DESTINATION=$2; shift 2 ;;
						--repo) shift 2 ;;
						*) shift ;;
					esac
				done
				[ -n "$PATTERN" ] && [ -n "$DESTINATION" ] || exit 2
				mkdir -p "$DESTINATION"
				cp "$ASSET_DIR/$PATTERN" "$DESTINATION/$PATTERN"
				;;
			*) exit 2 ;;
		esac
		;;
	*) exit 2 ;;
esac
EOF

cat >"$LOCK_HOLDER" <<'EOF'
#!/bin/sh
set -eu

fail() {
	printf 'lock holder: %s\n' "$*" >&2
	exit 1
}

WHOLE=$BIRD_TEST_LOCK_WHOLE
BIRD_CARD_LOCK_OWNED=0
# shellcheck source=/dev/null
. "$BIRD_TEST_LOCK_SOURCE"
cleanup() {
	bird_card_lock_release
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

bird_card_lock_acquire
: >"$BIRD_TEST_LOCK_GATE/ready"
while [ ! -e "$BIRD_TEST_LOCK_GATE/release" ]; do
	sleep 0.02
done
EOF

cat >"$FAKE_BUILDER" <<'EOF'
#!/bin/sh
set -eu

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
mode() { stat -f '%Lp' "$1"; }
bytes() { stat -f '%z' "$1"; }

if [ "${BIRD_BUILD_PREFLIGHT_ONLY:-0}" = 1 ]; then
	[ -f "$SOURCE/KERNEL" ] && [ ! -L "$SOURCE/KERNEL" ]
	[ -f "$SOURCE/dtb.img" ] && [ ! -L "$SOURCE/dtb.img" ]
	[ -f "$FALLBACK_KERNEL" ] && [ ! -L "$FALLBACK_KERNEL" ]
	printf '%s\n' "$BIRD_RELEASE_ID" >"$TEST_STATE/builder-preflight-release-id"
	printf '%s\n' "${BIRD_LAUNCHER_PROFILE-unset}" >"$TEST_STATE/builder-preflight-profile"
	exit 0
fi

[ ! -e "$OUTPUT/stale-marker" ] || {
	printf '%s\n' 'wrapper did not remove matching stale output' >&2
	exit 1
}
mkdir -p "$OUTPUT/card/bird" "$OUTPUT/card/extlinux" "$OUTPUT/build"
printf 'fake launcher for %s\n' "$BIRD_RELEASE_ID" >"$OUTPUT/card/bird/bird-launcher"
printf 'schema\tstring\tbird-device-v1\n' >"$OUTPUT/card/bird/bird-device-contract.tsv"
cp "$SOURCE/KERNEL" "$OUTPUT/card/KERNEL"
cp "$SOURCE/dtb.img" "$OUTPUT/card/dtb.img"
printf '%s\n' \
	'LABEL BIRD' \
	"  LINUX /bird-releases/$BIRD_RELEASE_ID/KERNEL" \
	"  INITRD /bird-releases/$BIRD_RELEASE_ID/bird-initramfs.cpio.gz" \
	"  FDT /bird-releases/$BIRD_RELEASE_ID/dtb.img" \
	"  APPEND bird_release=$BIRD_RELEASE_ID" >"$OUTPUT/card/extlinux/extlinux.conf"
chmod 0755 "$OUTPUT/card/bird/bird-launcher"
chmod 0644 "$OUTPUT/card/KERNEL" "$OUTPUT/card/dtb.img" \
	"$OUTPUT/card/extlinux/extlinux.conf"

printf '%s\n' "$BIRD_RELEASE_ID" >"$TEST_STATE/builder-release-id"
printf '%s\n' "${BIRD_LAUNCHER_PROFILE-unset}" >"$TEST_STATE/builder-profile"
printf '%s\n' "$OUTPUT" >"$TEST_STATE/builder-output"
printf '%s\n' "$SOURCE" >"$TEST_STATE/builder-source"
printf '%s\n' "$(sha256 "$SOURCE/KERNEL")" >"$TEST_STATE/builder-source-kernel-sha"
printf '%s\n' "$(sha256 "$SOURCE/dtb.img")" >"$TEST_STATE/builder-source-dtb-sha"
printf '%s\n' "$(sha256 "$FALLBACK_KERNEL")" >"$TEST_STATE/builder-fallback-kernel-sha"

MANIFEST=$OUTPUT/deploy-manifest.tsv
{
	printf 'schema\tbird-deploy-v1\n'
	printf 'release\t%s\n' "$BIRD_RELEASE_ID"
	printf 'target-mode-policy\tfat-capability\n'
	printf 'source-commit\ttest\tclean\n'
	if [ "${TEST_BUILDER_BEHAVIOR:-normal}" != missing-artifacts ]; then
		DEVICE_ARTIFACT_SHA=$(sha256 "$OUTPUT/card/bird/bird-device-contract.tsv")
		[ "${TEST_BUILDER_BEHAVIOR:-normal}" != bad-contract-artifact ] || \
			DEVICE_ARTIFACT_SHA=0000000000000000000000000000000000000000000000000000000000000000
		printf 'artifact\tdevice-contract\tbird/bird-device-contract.tsv\t%s\n' \
			"$DEVICE_ARTIFACT_SHA"
		CATALOG_ARTIFACT_SHA=$(sha256 "$BIRD_TEST_KOREADER_CATALOG_HEADER")
		[ "${TEST_BUILDER_BEHAVIOR:-normal}" != bad-catalog-artifact ] || \
			CATALOG_ARTIFACT_SHA=2222222222222222222222222222222222222222222222222222222222222222
		printf 'artifact\tcatalog\tlauncher/catalog.generated.h\t%s\n' \
			"$CATALOG_ARTIFACT_SHA"
	fi
	for INPUT in KERNEL KERNEL.fallback PortMaster.zip \
		PortMaster/PortMaster.sh PortMaster/funcs.txt PortMaster/harbourmaster \
		PortMaster/mod_ROCKNIX.txt PortMaster/pugwash ROCKNIX-STORAGE \
		ROCKNIX-SYSTEM dtb.img initramfs/busybox initramfs/init \
		rocknix-singleadc-joypad.ko usr/bin/autostart; do
		printf 'input\t%s\t644\t1\t%s\ttest:%s\n' "$INPUT" \
			1111111111111111111111111111111111111111111111111111111111111111 "$INPUT"
	done
	find "$OUTPUT/card" -type f -print | LC_ALL=C sort | while IFS= read -r FILE; do
		RELATIVE=${FILE#"$OUTPUT/card/"}
		HASH=$(sha256 "$FILE")
		[ "${TEST_BUILDER_BEHAVIOR:-normal}" != bad-manifest ] || \
			[ "$RELATIVE" != bird/bird-launcher ] || \
			HASH=0000000000000000000000000000000000000000000000000000000000000000
		printf 'file\t%s\t%s\t%s\t%s\n' "$RELATIVE" \
			"$(mode "$FILE")" "$(bytes "$FILE")" "$HASH"
	done
} >"$MANIFEST"

if [ "${TEST_BUILDER_BEHAVIOR:-normal}" = preinstall-identical ]; then
	RELEASE=$BIRD/bird-releases/$BIRD_RELEASE_ID
	mkdir -p "$RELEASE"
	cp -R "$OUTPUT/card"/. "$RELEASE"/
	cp "$MANIFEST" "$RELEASE/deploy-manifest.tsv"
	sha256 "$MANIFEST" >"$RELEASE/.complete"
fi
EOF

cat >"$FAKE_UPDATER" <<'EOF'
#!/bin/sh
set -eu

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

printf '%s\n' "$BIRD_RELEASE_ID" >"$TEST_STATE/updater-release-id"
printf '%s\n' "$CANDIDATE" >"$TEST_STATE/updater-candidate"
printf '%s\n' "$MANIFEST" >"$TEST_STATE/updater-manifest"
grep -Fqx "release${TAB:-	}$BIRD_RELEASE_ID" "$MANIFEST" 2>/dev/null || \
	awk -F '\t' -v release="$BIRD_RELEASE_ID" \
		'$1 == "release" && $2 == release {found++} END {exit found != 1}' "$MANIFEST"

RELEASES=$BIRD/bird-releases
RELEASE=$RELEASES/$BIRD_RELEASE_ID
mkdir -p "$RELEASES"
if [ "${TEST_UPDATER_BEHAVIOR:-normal}" = interrupt ]; then
	STAGE=$RELEASES/.$BIRD_RELEASE_ID.new.interrupted
	mkdir -p "$STAGE"
	cp "$CANDIDATE/bird/bird-launcher" "$STAGE/bird-launcher.partial"
	exit 75
fi

for STALE in "$RELEASES/.$BIRD_RELEASE_ID.new."*; do
	[ -e "$STALE" ] || continue
	case "$STALE" in "$RELEASES/.$BIRD_RELEASE_ID.new."*) rm -rf "$STALE" ;; esac
done

MANIFEST_SHA=$(sha256 "$MANIFEST")
if [ -e "$RELEASE" ]; then
	[ "$(cat "$RELEASE/.complete")" = "$MANIFEST_SHA" ] || exit 1
	[ "$(sha256 "$RELEASE/deploy-manifest.tsv")" = "$MANIFEST_SHA" ] || exit 1
else
	STAGE=$RELEASES/.$BIRD_RELEASE_ID.new.$$
	mkdir -p "$STAGE"
	cp -R "$CANDIDATE"/. "$STAGE"/
	cp "$MANIFEST" "$STAGE/deploy-manifest.tsv"
	printf '%s\n' "$MANIFEST_SHA" >"$STAGE/.complete"
	mv "$STAGE" "$RELEASE"
fi
cp "$BIRD/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.previous.conf"
cp "$RELEASE/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.conf"
printf '%s\n' success >"$TEST_STATE/updater-ran"
EOF
chmod 0755 "$FAKE_TOOL" "$FAKE_GH" "$FAKE_BUILDER" "$FAKE_UPDATER" \
	"$LOCK_HOLDER"

new_case() {
	CASE_NAME=$1
	CASE_ROOT=$TMP/$CASE_NAME
	VOLUMES_ROOT=$CASE_ROOT/Volumes
	BIRD=$VOLUMES_ROOT/BIRD
	DATA=$VOLUMES_ROOT/BIRD-DATA
	WORK_ROOT=$CASE_ROOT/kernel/work
	TEST_STATE=$CASE_ROOT/state
	BIRD_DEVICE_INFO=$CASE_ROOT/device-info.tsv
	SYSTEM_TREE=$CASE_ROOT/pinned/system-tree
	OFFICIAL_INIT=$CASE_ROOT/pinned/initramfs/init
	INIT_BUSYBOX=$CASE_ROOT/pinned/initramfs/busybox
	JOYPAD=$CASE_ROOT/pinned/joypad.ko
	STORAGE_SOURCE=$CASE_ROOT/pinned/storage.ext4
	SYSTEM_SOURCE=$DATA/MUOS/runtime/ROCKNIX-SYSTEM
	PORTMASTER_ARCHIVE=$SYSTEM_TREE/usr/config/PortMaster/release/PortMaster.zip
	KOREADER_CATALOG_HEADER=$CASE_ROOT/koreader-catalog.generated.h
	KOREADER_SOURCE=$DATA/ROMS/Ports/KOReader.sh
	KOREADER_ARCHIVE_ROOT=$DATA/ROMS/Ports/koreader
	KOREADER_ARCHIVE=$KOREADER_ARCHIVE_ROOT/koreader.zip
	PORTMASTER_PROVIDER_MANIFEST=$CASE_ROOT/portmaster-provider.manifest.tsv
	PORTMASTER_PYLIBS_FIXTURE=$CASE_ROOT/pylibs.fixture.zip
	mkdir -p "$BIRD/bird-releases" "$BIRD/extlinux" "$DATA/MUOS/runtime" "$DATA/Bird" \
		"$WORK_ROOT" "$TEST_STATE" "$SYSTEM_TREE/usr/bin" \
		"$SYSTEM_TREE/usr/config/PortMaster/release" "${OFFICIAL_INIT%/*}" \
		"$KOREADER_ARCHIVE_ROOT/koreader/frontend/apps/reader" \
		"$KOREADER_ARCHIVE_ROOT/koreader/libs" \
		"$DATA/ROMS/Ports/PortMaster"
	printf 'revision\tbird-canonical-namespace-v1\nstate\tcommitted\n' \
		>"$DATA/Bird/namespace-v1.tsv"
	printf 'rocknix kernel\n' >"$BIRD/KERNEL"
	printf 'fallback kernel\n' >"$BIRD/KERNEL.fallback"
	printf 'fixed dtb\n' >"$BIRD/dtb.img"
	printf 'prior selector\n' >"$BIRD/extlinux/extlinux.conf"
	cp "$ROOT/kernel/rocknix/stock-root/extlinux.fallback.conf" \
		"$BIRD/extlinux/extlinux.fallback.conf"
	printf 'runtime\n' >"$SYSTEM_SOURCE"
	printf 'storage\n' >"$STORAGE_SOURCE"
	printf 'autostart\n' >"$SYSTEM_TREE/usr/bin/autostart"
	printf 'portmaster\n' >"$PORTMASTER_ARCHIVE"
	printf 'init\n' >"$OFFICIAL_INIT"
	printf 'busybox\n' >"$INIT_BUSYBOX"
	printf 'joypad\n' >"$JOYPAD"
	for PORTMASTER_PROVIDER_FILE in pugwash PortMaster.sh control.txt \
		mod_ROCKNIX.txt funcs.txt oga_controls harbourmaster; do
		printf 'fixture provider %s\n' "$PORTMASTER_PROVIDER_FILE" \
			>"$DATA/ROMS/Ports/PortMaster/$PORTMASTER_PROVIDER_FILE"
	done
	printf 'fixture optional pylibs bytes\n' >"$PORTMASTER_PYLIBS_FIXTURE"
	write_portmaster_provider_manifest
	printf '%s\n' \
		'#define CATALOG_LAUNCH_KOREADER 7' \
		'static const u8 catalog_media_category_launch_kinds[CATALOG_MEDIA_CATEGORY_COUNT] = {' \
		'    CATALOG_LAUNCH_KOREADER,' \
		'};' >"$KOREADER_CATALOG_HEADER"
	printf 'fixture KOReader launcher\n' >"$KOREADER_SOURCE"
	printf 'fixture archive payload\n' >"$CASE_ROOT/koreader-payload"
	/usr/bin/zip -q -j "$KOREADER_ARCHIVE" "$CASE_ROOT/koreader-payload"
	KOREADER_SOURCE_SHA=$(sha256 "$KOREADER_SOURCE")
	KOREADER_ARCHIVE_SHA=$(sha256 "$KOREADER_ARCHIVE")
	KOREADER_ARCHIVE_BYTES=$(bytes "$KOREADER_ARCHIVE")
	KOREADER_EXPANDED_BYTES=$(unzip -l "$KOREADER_ARCHIVE" | awk 'END {print $1}')
	KOREADER_ARCHIVE_ENTRIES=$(unzip -l "$KOREADER_ARCHIVE" | awk 'END {print $2}')
	for KOREADER_SENTINEL in luajit reader.lua \
		frontend/apps/reader/readerui.lua libs/libkoreader-cre.so \
		libs/libwrap-mupdf.so defaults.custom.lua; do
		printf 'fixture sentinel\n' \
			>"$KOREADER_ARCHIVE_ROOT/koreader/$KOREADER_SENTINEL"
	done
	mkdir -p "$DATA/.config/bird/koreader-extraction"
	printf '%s\n' "$KOREADER_ARCHIVE_SHA" \
		>"$DATA/.config/bird/koreader-extraction/$KOREADER_ARCHIVE_SHA.complete"
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
		"$BIRD" 'File System Personality' 'MS-DOS FAT32' \
		"$BIRD" 'Volume Read-Only' No \
		"$DATA" 'Device Identifier' testdisks6 \
		"$DATA" 'Partition Offset' '8753512448 Bytes' \
		"$DATA" 'Disk Size' '503320672768 Bytes (503320672768 Bytes)' \
		"$DATA" 'Volume Read-Only' No \
		'/dev/testdisks5' 'Partition Offset' '163577856 Bytes' \
		'/dev/testdisks5' 'Disk Size' '8589934592 Bytes (8589934592 Bytes)' \
		>"$BIRD_DEVICE_INFO"
	TEST_BUILDER_BEHAVIOR=normal
	TEST_UPDATER_BEHAVIOR=normal
	TEST_GH_BEHAVIOR=normal
	BIRD_TEST_BIRD_FREE_BYTES=
	BIRD_TEST_DATA_FREE_BYTES=
	BIRD_TEST_HOST_FREE_BYTES=
}

create_completed_release() {
	FIXTURE_RELEASE_ID=$1
	FIXTURE_PAYLOAD_BYTES=${2:-0}
	FIXTURE_RELEASE=$BIRD/bird-releases/$FIXTURE_RELEASE_ID
	mkdir -p "$FIXTURE_RELEASE/extlinux"
	printf 'fixture release %s\n' "$FIXTURE_RELEASE_ID" >"$FIXTURE_RELEASE/payload.bin"
	if [ "$FIXTURE_PAYLOAD_BYTES" -gt 0 ]; then
		FIXTURE_MIB=$((FIXTURE_PAYLOAD_BYTES / 1048576))
		dd if=/dev/zero bs=1048576 count="$FIXTURE_MIB" \
			of="$FIXTURE_RELEASE/payload.bin" 2>/dev/null
	fi
	cp "$BIRD/KERNEL" "$FIXTURE_RELEASE/KERNEL"
	printf '%s\n' \
		'LABEL BIRD' \
		"  LINUX /bird-releases/$FIXTURE_RELEASE_ID/KERNEL" \
		"  APPEND bird_release=$FIXTURE_RELEASE_ID" \
		>"$FIXTURE_RELEASE/extlinux/extlinux.conf"
	chmod 0644 "$FIXTURE_RELEASE/payload.bin"
	chmod 0644 "$FIXTURE_RELEASE/KERNEL" "$FIXTURE_RELEASE/extlinux/extlinux.conf"
	FIXTURE_MANIFEST=$FIXTURE_RELEASE/deploy-manifest.tsv
	{
		printf 'schema\tbird-deploy-v1\n'
		printf 'release\t%s\n' "$FIXTURE_RELEASE_ID"
		printf 'target-mode-policy\tfat-capability\n'
		printf 'source-commit\ttest\tclean\n'
		for INPUT in KERNEL KERNEL.fallback PortMaster.zip \
			PortMaster/PortMaster.sh PortMaster/funcs.txt PortMaster/harbourmaster \
			PortMaster/mod_ROCKNIX.txt PortMaster/pugwash ROCKNIX-STORAGE \
			ROCKNIX-SYSTEM dtb.img initramfs/busybox initramfs/init \
			rocknix-singleadc-joypad.ko usr/bin/autostart; do
			printf 'input\t%s\t644\t1\t%s\ttest:%s\n' "$INPUT" \
				1111111111111111111111111111111111111111111111111111111111111111 "$INPUT"
		done
		for FIXTURE_FILE in KERNEL extlinux/extlinux.conf payload.bin; do
			printf 'file\t%s\t%s\t%s\t%s\n' "$FIXTURE_FILE" \
				"$(mode "$FIXTURE_RELEASE/$FIXTURE_FILE")" \
				"$(bytes "$FIXTURE_RELEASE/$FIXTURE_FILE")" \
				"$(sha256 "$FIXTURE_RELEASE/$FIXTURE_FILE")"
		done
	} >"$FIXTURE_MANIFEST"
	sha256 "$FIXTURE_MANIFEST" >"$FIXTURE_RELEASE/.complete"
}

select_fixture_release() {
	FIXTURE_ACTIVE_ID=$1
	cp "$BIRD/bird-releases/$FIXTURE_ACTIVE_ID/extlinux/extlinux.conf" \
		"$BIRD/extlinux/extlinux.conf"
}

select_fixture_fallback() {
	FIXTURE_FALLBACK=$ROOT/kernel/rocknix/stock-root/extlinux.fallback.conf
	cp "$FIXTURE_FALLBACK" "$BIRD/extlinux/extlinux.fallback.conf"
	cp "$FIXTURE_FALLBACK" "$BIRD/extlinux/extlinux.conf"
}

select_fixture_fallback_with_previous() {
	FIXTURE_PREVIOUS_ID=$1
	select_fixture_release "$FIXTURE_PREVIOUS_ID"
	cp "$BIRD/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.previous.conf"
	select_fixture_fallback
}

run_command() {
	BIRD_BUILD_DEPLOY_HOST_TEST_MODE=1 \
	BIRD="$BIRD" DATA="$DATA" VOLUMES_ROOT="$VOLUMES_ROOT" \
	WORK_ROOT="$WORK_ROOT" BUILDER="$FAKE_BUILDER" UPDATER="$FAKE_UPDATER" \
	BIRD_DEVICE_INFO="$BIRD_DEVICE_INFO" CLANG="$FAKE_TOOL" LLD="$FAKE_TOOL" \
	READELF="$FAKE_TOOL" GH="$FAKE_GH" SYSTEM_TREE="$SYSTEM_TREE" OFFICIAL_INIT="$OFFICIAL_INIT" \
	INIT_BUSYBOX="$INIT_BUSYBOX" JOYPAD="$JOYPAD" STORAGE_SOURCE="$STORAGE_SOURCE" \
	SYSTEM_SOURCE="$SYSTEM_SOURCE" PORTMASTER_ARCHIVE="$PORTMASTER_ARCHIVE" \
	TEST_STATE="$TEST_STATE" TEST_BUILDER_BEHAVIOR="$TEST_BUILDER_BEHAVIOR" \
	TEST_UPDATER_BEHAVIOR="$TEST_UPDATER_BEHAVIOR" TEST_GH_BEHAVIOR="$TEST_GH_BEHAVIOR" \
	BIRD_RELEASE_ARCHIVE_REPOSITORY=danielbuva/birdOS-release-archive \
	BIRD_TEST_RELEASE_STAMP=20260727-120000 \
	BIRD_TEST_BIRD_FREE_BYTES="$BIRD_TEST_BIRD_FREE_BYTES" \
	BIRD_TEST_DATA_FREE_BYTES="$BIRD_TEST_DATA_FREE_BYTES" \
	BIRD_TEST_HOST_FREE_BYTES="$BIRD_TEST_HOST_FREE_BYTES" \
	BIRD_TEST_KOREADER_CATALOG_HEADER="$KOREADER_CATALOG_HEADER" \
	BIRD_TEST_KOREADER_SOURCE_SHA="$KOREADER_SOURCE_SHA" \
	BIRD_TEST_KOREADER_ARCHIVE_SHA="$KOREADER_ARCHIVE_SHA" \
	BIRD_TEST_KOREADER_ARCHIVE_BYTES="$KOREADER_ARCHIVE_BYTES" \
	BIRD_TEST_KOREADER_EXPANDED_BYTES="$KOREADER_EXPANDED_BYTES" \
	BIRD_TEST_KOREADER_ARCHIVE_ENTRIES="$KOREADER_ARCHIVE_ENTRIES" \
	BIRD_TEST_PORTMASTER_PROVIDER_MANIFEST="$PORTMASTER_PROVIDER_MANIFEST" \
		"$COMMAND" "$@"
}

"$COMMAND" --help | grep -q '^Usage:'
if "$COMMAND" --release --profile >"$TMP/args.out" 2>"$TMP/args.err"; then
	fail 'mutually exclusive modes were accepted'
fi
grep -q 'choose exactly one' "$TMP/args.err"
if "$COMMAND" --release --release-id '../unsafe' >"$TMP/id.out" 2>"$TMP/id.err"; then
	fail 'unsafe release ID was accepted'
fi
grep -q 'unsafe Bird release ID' "$TMP/id.err"

new_case missing-volume
rm -rf "$DATA"
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'missing BIRD-DATA volume was accepted'
fi
grep -q 'BIRD-DATA volume is missing or ambiguous' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case ambiguous-volume
mkdir "$VOLUMES_ROOT/BIRD 1"
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'ambiguous BIRD volumes were accepted'
fi
grep -q 'BIRD volume is missing or ambiguous' "$CASE_ROOT/err"

new_case internal-disk
sed 's/Removable Media\tRemovable/Removable Media\tFixed/' \
	"$BIRD_DEVICE_INFO" >"$CASE_ROOT/device-info.bad"
BIRD_DEVICE_INFO=$CASE_ROOT/device-info.bad
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'non-removable disk identity was accepted'
fi
grep -q 'refusing non-removable disk' "$CASE_ROOT/err"

new_case missing-pinned-input
rm "$JOYPAD"
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'missing pinned build input was accepted'
fi
grep -q 'pinned build input missing or unsafe' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case koreader-not-cataloged
printf '%s\n' \
	'#define CATALOG_LAUNCH_KOREADER 7' \
	'static const u8 catalog_media_category_launch_kinds[CATALOG_MEDIA_CATEGORY_COUNT] = {' \
	'};' >"$KOREADER_CATALOG_HEADER"
rm -f "$KOREADER_SOURCE" "$KOREADER_ARCHIVE"
run_command --release --dry-run >"$CASE_ROOT/out"
grep -q 'Deployment result: not run' "$CASE_ROOT/out"
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case koreader-missing-source
rm -f "$KOREADER_SOURCE"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'cataloged KOReader with a missing source launcher was accepted'
fi
grep -q 'KOReader source launcher is missing or unsafe' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case koreader-source-mismatch
printf 'changed\n' >>"$KOREADER_SOURCE"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'cataloged KOReader with a changed source launcher was accepted'
fi
grep -q 'KOReader source launcher digest changed' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case koreader-corrupt-archive
dd if="$KOREADER_ARCHIVE" of="$CASE_ROOT/truncated.zip" bs=1 count=20 2>/dev/null
mv "$CASE_ROOT/truncated.zip" "$KOREADER_ARCHIVE"
KOREADER_ARCHIVE_SHA=$(sha256 "$KOREADER_ARCHIVE")
KOREADER_ARCHIVE_BYTES=$(bytes "$KOREADER_ARCHIVE")
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'cataloged KOReader with a corrupt archive was accepted'
fi
grep -q 'KOReader archive failed integrity verification' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case koreader-first-extraction-space
rm -f "$DATA/.config/bird/koreader-extraction/$KOREADER_ARCHIVE_SHA.complete"
KOREADER_PENDING_REQUIRED=$((16777216 + KOREADER_EXPANDED_BYTES + $(bytes "$STORAGE_SOURCE")))
BIRD_TEST_DATA_FREE_BYTES=$((KOREADER_PENDING_REQUIRED - 1))
if run_command --release --dry-run >"$CASE_ROOT/low.out" 2>"$CASE_ROOT/low.err"; then
	fail 'KOReader first extraction without sufficient reserve was accepted'
fi
grep -q 'BIRD-DATA has insufficient free space' "$CASE_ROOT/low.err"
BIRD_TEST_DATA_FREE_BYTES=$KOREADER_PENDING_REQUIRED
run_command --release --dry-run >"$CASE_ROOT/exact.out"
grep -q "extraction pending ($KOREADER_EXPANDED_BYTES-byte reserve)" "$CASE_ROOT/exact.out"
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case koreader-unsafe-marker
rm -f "$DATA/.config/bird/koreader-extraction/$KOREADER_ARCHIVE_SHA.complete"
ln -s "$CASE_ROOT/missing-koreader-marker" \
	"$DATA/.config/bird/koreader-extraction/$KOREADER_ARCHIVE_SHA.complete"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'unsafe KOReader extraction marker was accepted'
fi
grep -q 'KOReader extraction completion marker is unsafe' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case portmaster-provider-exact
EXPECTED_PORTMASTER_MARKER=$(portmaster_provider_marker_value)
run_command --release --dry-run >"$CASE_ROOT/out"
grep -Fq "PortMaster preflight: pinned installed provider $EXPECTED_PORTMASTER_MARKER; checkpoint state absent." \
	"$CASE_ROOT/out"
[ ! -e "$TEST_STATE/builder-release-id" ]

# pylibs.zip is the sole optional managed provider file. Absence is covered by
# the exact case above; if present, it must match the one pinned optional-file
# record byte-for-byte.
new_case portmaster-provider-optional-exact
cp "$PORTMASTER_PYLIBS_FIXTURE" \
	"$DATA/ROMS/Ports/PortMaster/pylibs.zip"
run_command --release --dry-run >"$CASE_ROOT/out"
grep -Fq "$(portmaster_provider_marker_value)" "$CASE_ROOT/out"

new_case portmaster-provider-optional-arbitrary
cp "$PORTMASTER_PYLIBS_FIXTURE" \
	"$DATA/ROMS/Ports/PortMaster/pylibs.zip"
printf X | dd of="$DATA/ROMS/Ports/PortMaster/pylibs.zip" \
	bs=1 seek=0 conv=notrunc 2>/dev/null
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'arbitrary present PortMaster pylibs.zip was accepted'
fi
grep -q 'managed file digest changed: pylibs.zip' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

# Provider-local Python caches are rejected by default. Production may ignore
# them only at audited call sites that explicitly establish an isolated fresh
# tmpfs cache for every PortMaster-backed execution path.
new_case portmaster-provider-python-cache-policy
mkdir -p "$DATA/ROMS/Ports/PortMaster/python/__pycache__"
printf 'fixture bytecode cache\n' \
	>"$DATA/ROMS/Ports/PortMaster/python/__pycache__/module.cpython.pyc"
if "$ROOT/kernel/rocknix/stock-root/verify-portmaster-provider.sh" \
		"$PORTMASTER_PROVIDER_MANIFEST" "$DATA/ROMS/Ports/PortMaster" \
		>"$CASE_ROOT/default.out" 2>"$CASE_ROOT/default.err"; then
	fail 'default PortMaster verifier accepted a provider-local Python cache'
fi
grep -q 'managed provider file set differs from the pinned revision' \
	"$CASE_ROOT/default.err"
"$ROOT/kernel/rocknix/stock-root/verify-portmaster-provider.sh" \
	--allow-isolated-python-cache "$PORTMASTER_PROVIDER_MANIFEST" \
	"$DATA/ROMS/Ports/PortMaster" >"$CASE_ROOT/isolated.out"
grep -Fxq "$(portmaster_provider_marker_value)" "$CASE_ROOT/isolated.out"

for PORTMASTER_PRODUCTION_CALLER in "$COMMAND" \
	"$ROOT/firmware/mac-update-rocknix-stock-root-v6.sh"; do
	PORTMASTER_REFERENCE_COUNT=$(grep -Ec \
		'"\$PORTMASTER_PROVIDER_VERIFIER"' \
		"$PORTMASTER_PRODUCTION_CALLER" || :)
	PORTMASTER_FLAG_COUNT=$(grep -Ec \
		'"\$PORTMASTER_PROVIDER_VERIFIER" --allow-isolated-python-cache' \
		"$PORTMASTER_PRODUCTION_CALLER" || :)
	# Exactly one non-call reference validates the verifier file; both actual
	# invocations (preflight and locked recheck) must carry the opt-in flag.
	[ "$PORTMASTER_REFERENCE_COUNT" -eq 3 ] || \
		fail "unexpected PortMaster verifier reference count in $PORTMASTER_PRODUCTION_CALLER"
	[ "$PORTMASTER_FLAG_COUNT" -eq 2 ] || \
		fail "production PortMaster verifier call omitted isolated-cache flag: $PORTMASTER_PRODUCTION_CALLER"
done

PORTMASTER_RUN_CONTENT=$ROOT/kernel/rocknix/stock-root/run-content.sh
awk '
	/^prepare_portmaster_python_cache\(\)/ {inside=1; next}
	inside && /PORTMASTER_PYCACHE=\/run\/bird\/portmaster-pycache/ {if (step != 0) exit 1; step=1; next}
	inside && /rm -rf "\$PORTMASTER_PYCACHE" \|\| return 1/ {if (step != 1) exit 1; step=2; next}
	inside && /umask 077; mkdir -p "\$PORTMASTER_PYCACHE"/ {if (step != 2) exit 1; step=3; next}
	inside && /export PYTHONPYCACHEPREFIX="\$PORTMASTER_PYCACHE"/ {if (step != 3) exit 1; step=4; next}
	inside && /export PYTHONDONTWRITEBYTECODE=1/ {if (step != 4) exit 1; step=5; next}
	inside && /^}/ {closed=1; exit(step == 5 ? 0 : 1)}
	END {if (!closed) exit 1}
' "$PORTMASTER_RUN_CONTENT" || \
	fail 'PortMaster Python cache setup is not a fresh isolated /run/bird directory'
awk '
	/^run_selected\(\)/ {inside=1; next}
	inside && /prepare_portmaster_python_cache \|\| return 1/ {prepared++; ready++; next}
	inside && /start_portmaster\.sh/ {
		if (ready != 1) exit 1
		ready=0
		executions++
		next
	}
	inside && /--core=portmaster --emulator=portmaster/ {
		if (ready != 1) exit 1
		ready=0
		executions++
		next
	}
	inside && /^}/ {
		closed=1
		exit(prepared == 3 && executions == 3 && ready == 0 ? 0 : 1)
	}
	END {if (!closed) exit 1}
' "$PORTMASTER_RUN_CONTENT" || \
	fail 'not every PortMaster execution path establishes a fresh Python cache first'

# A signal received while the verifier is hashing managed provider bytes must
# abort verification.  Interpose only the host shasum process so the signal is
# deterministic: it targets the verifier while real digest work is in flight,
# then lets that digest complete.  Resuming after SIGTERM would therefore
# expose the bug by publishing an otherwise-valid v3 checkpoint.
new_case portmaster-provider-sigterm
PORTMASTER_SIGNAL_BIN=$CASE_ROOT/signal-bin
PORTMASTER_SIGNAL_PID_FILE=$CASE_ROOT/verifier.pid
PORTMASTER_SIGNAL_FIRED=$CASE_ROOT/signal-fired
PORTMASTER_SIGNAL_TARGET=$DATA/ROMS/Ports/PortMaster/funcs.txt
PORTMASTER_REAL_SHASUM=$(command -v shasum)
mkdir -p "$PORTMASTER_SIGNAL_BIN"
cat >"$PORTMASTER_SIGNAL_BIN/shasum" <<'EOF'
#!/bin/sh
set -eu

LAST_ARGUMENT=
for ARGUMENT do
	LAST_ARGUMENT=$ARGUMENT
done
if [ "$LAST_ARGUMENT" = "$BIRD_TEST_SIGNAL_TARGET" ]; then
	while [ ! -s "$BIRD_TEST_SIGNAL_PID_FILE" ]; do
		sleep 0.01
	done
	: >"$BIRD_TEST_SIGNAL_FIRED"
	kill -TERM "$(cat "$BIRD_TEST_SIGNAL_PID_FILE")"
fi
exec "$BIRD_TEST_REAL_SHASUM" "$@"
EOF
chmod 0755 "$PORTMASTER_SIGNAL_BIN/shasum"
PORTMASTER_SIGNAL_STATUS=0
PATH="$PORTMASTER_SIGNAL_BIN:/usr/bin:/bin" \
BIRD_TEST_SIGNAL_TARGET="$PORTMASTER_SIGNAL_TARGET" \
BIRD_TEST_SIGNAL_PID_FILE="$PORTMASTER_SIGNAL_PID_FILE" \
BIRD_TEST_SIGNAL_FIRED="$PORTMASTER_SIGNAL_FIRED" \
BIRD_TEST_REAL_SHASUM="$PORTMASTER_REAL_SHASUM" \
	"$ROOT/kernel/rocknix/stock-root/verify-portmaster-provider.sh" \
	"$PORTMASTER_PROVIDER_MANIFEST" "$DATA/ROMS/Ports/PortMaster" \
	>"$CASE_ROOT/out" 2>"$CASE_ROOT/err" &
PORTMASTER_SIGNAL_PID=$!
printf '%s\n' "$PORTMASTER_SIGNAL_PID" >"$PORTMASTER_SIGNAL_PID_FILE"
wait "$PORTMASTER_SIGNAL_PID" || PORTMASTER_SIGNAL_STATUS=$?
[ -f "$PORTMASTER_SIGNAL_FIRED" ] || \
	fail 'SIGTERM verifier fixture did not reach managed digest work'
[ "$PORTMASTER_SIGNAL_STATUS" -ne 0 ] || \
	fail 'PortMaster verifier resumed successfully after SIGTERM'
if grep -q '^bird-portmaster-v3:' "$CASE_ROOT/out"; then
	fail 'PortMaster verifier published a v3 checkpoint after SIGTERM'
fi

# A digest command failure while checking the immutable manifest source is not
# an empty/malformed digest and must never fall through to checkpoint output.
new_case portmaster-provider-manifest-digest-failure
PORTMASTER_DIGEST_BIN=$CASE_ROOT/digest-bin
PORTMASTER_REAL_SHASUM=$(command -v shasum)
mkdir -p "$PORTMASTER_DIGEST_BIN"
cat >"$PORTMASTER_DIGEST_BIN/shasum" <<'EOF'
#!/bin/sh
set -eu

LAST_ARGUMENT=
for ARGUMENT do
	LAST_ARGUMENT=$ARGUMENT
done
if [ "$LAST_ARGUMENT" = "$BIRD_TEST_DIGEST_FAIL_TARGET" ]; then
	exit 73
fi
exec "$BIRD_TEST_REAL_SHASUM" "$@"
EOF
chmod 0755 "$PORTMASTER_DIGEST_BIN/shasum"
PORTMASTER_DIGEST_STATUS=0
PATH="$PORTMASTER_DIGEST_BIN:/usr/bin:/bin" \
BIRD_TEST_DIGEST_FAIL_TARGET="$PORTMASTER_PROVIDER_MANIFEST" \
BIRD_TEST_REAL_SHASUM="$PORTMASTER_REAL_SHASUM" \
	"$ROOT/kernel/rocknix/stock-root/verify-portmaster-provider.sh" \
	"$PORTMASTER_PROVIDER_MANIFEST" "$DATA/ROMS/Ports/PortMaster" \
	>"$CASE_ROOT/out" 2>"$CASE_ROOT/err" || PORTMASTER_DIGEST_STATUS=$?
[ "$PORTMASTER_DIGEST_STATUS" -ne 0 ] || \
	fail 'PortMaster verifier accepted a failed manifest digest command'
grep -q 'could not hash:' "$CASE_ROOT/err"
if grep -q '^bird-portmaster-v3:' "$CASE_ROOT/out"; then
	fail 'PortMaster verifier published a v3 checkpoint after digest failure'
fi

new_case portmaster-provider-mutation
printf 'changed managed provider\n' >>"$DATA/ROMS/Ports/PortMaster/pugwash"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'mutated managed PortMaster provider was accepted'
fi
grep -q 'managed file size changed: pugwash' "$CASE_ROOT/err"
grep -q 'installed PortMaster provider is not a pinned complete revision' \
	"$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case portmaster-provider-extra
printf 'unmanaged executable\n' >"$DATA/ROMS/Ports/PortMaster/unlisted-managed-file"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'extra managed PortMaster provider file was accepted'
fi
grep -q 'managed provider file set differs from the pinned revision' \
	"$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case portmaster-provider-symlink
cp "$DATA/ROMS/Ports/PortMaster/pugwash" "$CASE_ROOT/provider-target"
rm -f "$DATA/ROMS/Ports/PortMaster/pugwash"
ln -s "$CASE_ROOT/provider-target" "$DATA/ROMS/Ports/PortMaster/pugwash"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'symlinked managed PortMaster provider was accepted'
fi
grep -Eq 'managed provider file set differs|managed provider contains a symlink' \
	"$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case portmaster-provider-mutable-exclusions
printf 'user controller mapping\n' >"$DATA/ROMS/Ports/PortMaster/control.txt"
printf 'user controls\n' >"$DATA/ROMS/Ports/PortMaster/oga_controls"
mkdir -p "$DATA/ROMS/Ports/PortMaster/config" \
	"$DATA/ROMS/Ports/PortMaster/runtimes/custom"
printf 'mutable settings\n' >"$DATA/ROMS/Ports/PortMaster/config/user.ini"
printf 'downloaded runtime\n' \
	>"$DATA/ROMS/Ports/PortMaster/runtimes/custom/runtime.bin"
printf 'session log\n' >"$DATA/ROMS/Ports/PortMaster/log.txt"
CONTROL_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/control.txt")
OGA_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/oga_controls")
run_command --release --dry-run >"$CASE_ROOT/out"
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/control.txt")" = "$CONTROL_SHA" ]
[ "$(sha256 "$DATA/ROMS/Ports/PortMaster/oga_controls")" = "$OGA_SHA" ]
grep -Fq "$(portmaster_provider_marker_value)" "$CASE_ROOT/out"

new_case portmaster-provider-failure-no-mutation
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
BIRD_TEST_BIRD_FREE_BYTES=1
STALE_OUTPUT=$WORK_ROOT/bird-rocknix-stock-root-v6.23
mkdir "$STALE_OUTPUT"
printf 'must survive provider rejection\n' >"$STALE_OUTPUT/stale-marker"
printf 'changed managed provider\n' >>"$DATA/ROMS/Ports/PortMaster/funcs.txt"
ROOT_KERNEL_SHA=$(sha256 "$BIRD/KERNEL")
ACTIVE_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'invalid PortMaster provider reached destructive deployment work'
fi
grep -q 'installed PortMaster provider is not a pinned complete revision' \
	"$CASE_ROOT/err"
[ -f "$STALE_OUTPUT/stale-marker" ]
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
[ "$(sha256 "$BIRD/KERNEL")" = "$ROOT_KERNEL_SHA" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SELECTOR_SHA" ]
[ ! -e "$TEST_STATE/gh-events" ]
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]
[ ! -e "$TEST_STATE/builder-release-id" ]
[ ! -e "$TEST_STATE/updater-ran" ]

new_case read-only-volume
chmod 0555 "$BIRD"
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'non-writable BIRD fixture was accepted'
fi
grep -q 'volume is not writable' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-release-id" ]
chmod 0755 "$BIRD"

new_case dry-run
mkdir "$WORK_ROOT/bird-rocknix-stock-root-v6.23"
printf 'keep\n' >"$WORK_ROOT/bird-rocknix-stock-root-v6.23/stale-marker"
run_command --release --dry-run >"$CASE_ROOT/out"
grep -q 'Deployment result: not run' "$CASE_ROOT/out"
[ -f "$WORK_ROOT/bird-rocknix-stock-root-v6.23/stale-marker" ]
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case unsafe-output
mkdir "$CASE_ROOT/must-survive"
printf 'keep\n' >"$CASE_ROOT/must-survive/value"
ln -s "$CASE_ROOT/must-survive" "$WORK_ROOT/bird-rocknix-stock-root-v6.23"
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'symlinked generated output was accepted'
fi
grep -q 'matching generated output is not a safe directory' "$CASE_ROOT/err"
[ "$(cat "$CASE_ROOT/must-survive/value")" = keep ]

new_case insufficient-space
create_completed_release active
select_fixture_release active
BIRD_TEST_BIRD_FREE_BYTES=1
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'insufficient BIRD staging space was accepted'
fi
grep -q 'BIRD has insufficient staging space' "$CASE_ROOT/err"

new_case archive-dry-run
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
BIRD_TEST_BIRD_FREE_BYTES=1
run_command --release --dry-run >"$CASE_ROOT/out"
grep -q 'would archive and verify inactive release retired' "$CASE_ROOT/out"
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
[ ! -e "$TEST_STATE/gh-events" ]

new_case archive-lock-contention
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
PRIOR_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
BIRD_TEST_BIRD_FREE_BYTES=1
LOCK_GATE=$CASE_ROOT/lock-gate
mkdir "$LOCK_GATE"
BIRD_TEST_LOCK_SOURCE=$ROOT/firmware/mac-bird-card-lock.sh \
BIRD_TEST_LOCK_WHOLE=testdisk BIRD_TEST_LOCK_GATE=$LOCK_GATE \
	"$LOCK_HOLDER" >"$CASE_ROOT/lock-holder.out" \
	2>"$CASE_ROOT/lock-holder.err" &
LOCK_HOLDER_PID=$!
LOCK_WAIT=0
while [ ! -e "$LOCK_GATE/ready" ]; do
	LOCK_WAIT=$((LOCK_WAIT + 1))
	if [ "$LOCK_WAIT" -gt 400 ]; then
		kill "$LOCK_HOLDER_PID" 2>/dev/null || :
		wait "$LOCK_HOLDER_PID" 2>/dev/null || :
		fail 'cooperating card lock holder did not become ready'
	fi
	sleep 0.02
done
LOCKED_STATUS=0
run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err" || LOCKED_STATUS=$?
: >"$LOCK_GATE/release"
wait "$LOCK_HOLDER_PID" || fail 'cooperating card lock holder failed'
[ "$LOCKED_STATUS" -ne 0 ] || fail 'concurrent card transaction was accepted'
grep -q 'another Bird card transaction is active' "$CASE_ROOT/err"
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PRIOR_SELECTOR_SHA" ]
[ ! -e "$TEST_STATE/gh-events" ]
[ ! -e "$TEST_STATE/builder-release-id" ]
[ ! -e "$TEST_STATE/updater-ran" ]

new_case archive-reclaim
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
BIRD_TEST_BIRD_FREE_BYTES=1
run_command --release >"$CASE_ROOT/out"
[ -d "$BIRD/bird-releases/active" ]
[ ! -e "$BIRD/bird-releases/retired" ]
[ -f "$TEST_STATE/gh-release-card-retired-state" ]
[ "$(cat "$TEST_STATE/gh-release-card-retired-state")" = false ]
[ -f "$TEST_STATE/gh-release-card-retired-assets/birdOS-RG34XX-SP-retired.tar" ]
[ -f "$TEST_STATE/gh-release-card-retired-assets/retired.deploy-manifest.tsv" ]
grep -q 'Archived inactive release retired' "$CASE_ROOT/out"
grep -Fq 'bird_release=v6.23' "$BIRD/extlinux/extlinux.conf"

new_case legacy-kernel-retirement
dd if=/dev/zero bs=1048576 count=2 of="$BIRD/KERNEL" 2>/dev/null
LEGACY_KERNEL_SHA=$(sha256 "$BIRD/KERNEL")
LEGACY_DTB_SHA=$(sha256 "$BIRD/dtb.img")
LEGACY_FALLBACK_SHA=$(sha256 "$BIRD/KERNEL.fallback")
create_completed_release active
create_completed_release retired 2097152
select_fixture_release active
BIRD_TEST_BIRD_FREE_BYTES=1
run_command --release --dry-run >"$CASE_ROOT/dry-run.out"
grep -q 'would remove the verified redundant top-level KERNEL' "$CASE_ROOT/dry-run.out"
[ "$(sha256 "$BIRD/KERNEL")" = "$LEGACY_KERNEL_SHA" ]
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
run_command --release >"$CASE_ROOT/out"
[ ! -e "$BIRD/KERNEL" ] && [ ! -L "$BIRD/KERNEL" ]
[ -d "$BIRD/bird-releases/active" ]
[ ! -e "$BIRD/bird-releases/retired" ]
[ "$(sha256 "$BIRD/bird-releases/active/KERNEL")" = "$LEGACY_KERNEL_SHA" ]
[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$LEGACY_FALLBACK_SHA" ]
[ "$(sha256 "$BIRD/dtb.img")" = "$LEGACY_DTB_SHA" ]
[ "$(cat "$TEST_STATE/builder-source-kernel-sha")" = "$LEGACY_KERNEL_SHA" ]
[ "$(cat "$TEST_STATE/builder-source-dtb-sha")" = "$LEGACY_DTB_SHA" ]
[ "$(cat "$TEST_STATE/builder-fallback-kernel-sha")" = "$LEGACY_FALLBACK_SHA" ]
grep -q 'Reclaimed redundant top-level KERNEL' "$CASE_ROOT/out"
grep -Fq 'bird_release=v6.23' "$BIRD/extlinux/extlinux.conf"

# The next invocation must source pinned bytes from the now-active immutable
# release; retirement cannot make the one-command path a one-shot operation.
BIRD_TEST_BIRD_FREE_BYTES=134217728
run_command --release --release-id after-retirement >"$CASE_ROOT/retry.out"
[ "$(cat "$TEST_STATE/builder-release-id")" = after-retirement ]
[ "$(cat "$TEST_STATE/builder-source-kernel-sha")" = "$LEGACY_KERNEL_SHA" ]
[ "$(cat "$TEST_STATE/builder-source-dtb-sha")" = "$LEGACY_DTB_SHA" ]
[ "$(cat "$TEST_STATE/builder-fallback-kernel-sha")" = "$LEGACY_FALLBACK_SHA" ]
[ ! -e "$BIRD/KERNEL" ] && [ ! -L "$BIRD/KERNEL" ]
grep -Fq 'bird_release=after-retirement' "$BIRD/extlinux/extlinux.conf"

# A card on the exact fallback selector can no longer rely on the retired
# pre-versioned root KERNEL. Its canonical previous selector is sufficient only
# when the named immutable release and every manifest-recorded byte verify.
new_case fallback-versioned-build-source
create_completed_release previous
create_completed_release retired 5242880
select_fixture_fallback_with_previous previous
PREVIOUS_KERNEL_SHA=$(sha256 "$BIRD/bird-releases/previous/KERNEL")
PREVIOUS_DTB_SHA=$(sha256 "$BIRD/dtb.img")
PREVIOUS_FALLBACK_SHA=$(sha256 "$BIRD/KERNEL.fallback")
rm -f "$BIRD/KERNEL"
BIRD_TEST_BIRD_FREE_BYTES=1
run_command --release --release-id fallback-recovered >"$CASE_ROOT/out"
[ "$(cat "$TEST_STATE/builder-release-id")" = fallback-recovered ]
[ "$(cat "$TEST_STATE/builder-source-kernel-sha")" = "$PREVIOUS_KERNEL_SHA" ]
[ "$(cat "$TEST_STATE/builder-source-dtb-sha")" = "$PREVIOUS_DTB_SHA" ]
[ "$(cat "$TEST_STATE/builder-fallback-kernel-sha")" = "$PREVIOUS_FALLBACK_SHA" ]
[ ! -e "$BIRD/KERNEL" ] && [ ! -L "$BIRD/KERNEL" ]
[ -d "$BIRD/bird-releases/previous" ]
[ ! -e "$BIRD/bird-releases/retired" ]
[ -f "$TEST_STATE/gh-release-card-retired-assets/birdOS-RG34XX-SP-retired.tar" ]
grep -Fq 'bird_release=fallback-recovered' "$BIRD/extlinux/extlinux.conf"

# The canonical updater records the active fallback selector as previous when
# activating from fallback. A later fallback cycle must therefore recover a
# build source from installed immutable releases without making deployment a
# one-shot operation.
new_case fallback-versioned-source-second-cycle
create_completed_release previous
create_completed_release retired 5242880
select_fixture_fallback_with_previous previous
SECOND_CYCLE_KERNEL_SHA=$(sha256 "$BIRD/bird-releases/previous/KERNEL")
rm -f "$BIRD/KERNEL"
run_command --release --release-id z-current >"$CASE_ROOT/first.out"
[ "$(sha256 "$BIRD/extlinux/extlinux.previous.conf")" = \
	"$(sha256 "$BIRD/extlinux/extlinux.fallback.conf")" ]
[ -d "$BIRD/bird-releases/z-current" ]
select_fixture_fallback
BIRD_TEST_BIRD_FREE_BYTES=1
run_command --release --release-id zz-next >"$CASE_ROOT/second.out"
[ "$(cat "$TEST_STATE/builder-release-id")" = zz-next ]
[ "$(cat "$TEST_STATE/builder-source-kernel-sha")" = \
	"$SECOND_CYCLE_KERNEL_SHA" ]
[ -d "$BIRD/bird-releases/z-current" ]
[ ! -e "$BIRD/bird-releases/previous" ]
[ ! -e "$BIRD/bird-releases/retired" ]
grep -Fq 'bird_release=zz-next' "$BIRD/extlinux/extlinux.conf"

new_case fallback-versioned-source-deterministic-corruption
create_completed_release z-source
select_fixture_fallback
cp "$BIRD/extlinux/extlinux.fallback.conf" \
	"$BIRD/extlinux/extlinux.previous.conf"
printf '%s\n' changed >>"$BIRD/bird-releases/z-source/payload.bin"
rm -f "$BIRD/KERNEL"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'corrupt deterministic fallback build source was accepted'
fi
grep -q 'deterministic fallback immutable build source size changed: z-source/payload.bin' \
	"$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case fallback-versioned-source-deterministic-missing
select_fixture_fallback
cp "$BIRD/extlinux/extlinux.fallback.conf" \
	"$BIRD/extlinux/extlinux.previous.conf"
rm -f "$BIRD/KERNEL"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'fallback without an immutable installed build source was accepted'
fi
grep -q 'fallback selector has no immutable installed release build source' \
	"$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case fallback-versioned-source-noncanonical-previous-fallback
create_completed_release z-source
select_fixture_fallback
cp "$BIRD/extlinux/extlinux.fallback.conf" \
	"$BIRD/extlinux/extlinux.previous.conf"
printf '\n' >>"$BIRD/extlinux/extlinux.previous.conf"
rm -f "$BIRD/KERNEL"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'noncanonical previous fallback selector triggered deterministic recovery'
fi
grep -q 'fallback previous selector does not contain exactly one Bird release ID' \
	"$CASE_ROOT/err"
[ -d "$BIRD/bird-releases/z-source" ]
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case fallback-versioned-source-unsafe-selector
create_completed_release previous
select_fixture_fallback
ln -s "$BIRD/bird-releases/previous/extlinux/extlinux.conf" \
	"$BIRD/extlinux/extlinux.previous.conf"
rm -f "$BIRD/KERNEL"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'symlinked fallback previous selector was accepted as a build source'
fi
grep -q 'fallback previous selector is missing or unsafe' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case fallback-versioned-source-changed-marker
create_completed_release previous
select_fixture_fallback_with_previous previous
printf '%s\n' changed >"$BIRD/bird-releases/previous/.complete"
rm -f "$BIRD/KERNEL"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'fallback previous release with a changed completion marker was accepted'
fi
grep -q 'fallback previous immutable build source completion marker changed: previous' \
	"$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case fallback-versioned-source-malformed-manifest
create_completed_release previous
select_fixture_fallback_with_previous previous
rm -f "$BIRD/bird-releases/previous/KERNEL"
awk -F '\t' '!($1 == "file" && $2 == "KERNEL")' \
	"$BIRD/bird-releases/previous/deploy-manifest.tsv" \
	>"$CASE_ROOT/manifest-without-kernel"
mv "$CASE_ROOT/manifest-without-kernel" \
	"$BIRD/bird-releases/previous/deploy-manifest.tsv"
sha256 "$BIRD/bird-releases/previous/deploy-manifest.tsv" \
	>"$BIRD/bird-releases/previous/.complete"
rm -f "$BIRD/KERNEL"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'fallback previous release without a KERNEL manifest record was accepted'
fi
grep -q 'fallback previous immutable build source manifest has no unique valid KERNEL record' \
	"$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case fallback-versioned-source-selector-mismatch
create_completed_release previous
select_fixture_fallback_with_previous previous
printf '%s\n' '# changed previous selector' \
	>>"$BIRD/extlinux/extlinux.previous.conf"
rm -f "$BIRD/KERNEL"
if run_command --release --dry-run >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'fallback previous selector differing from its immutable release was accepted'
fi
grep -q 'fallback previous selector differs from its verified immutable release selector' \
	"$CASE_ROOT/err"
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case legacy-kernel-mismatch
dd if=/dev/zero bs=1048576 count=2 of="$BIRD/KERNEL" 2>/dev/null
create_completed_release active
dd if=/dev/zero bs=1048576 count=2 of="$BIRD/KERNEL" 2>/dev/null
printf 'changed' | dd of="$BIRD/KERNEL" conv=notrunc 2>/dev/null
create_completed_release retired 2097152
select_fixture_release active
MISMATCH_KERNEL_SHA=$(sha256 "$BIRD/KERNEL")
BIRD_TEST_BIRD_FREE_BYTES=1
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'top-level KERNEL differing from the active immutable release was retired'
fi
grep -q 'legacy top-level KERNEL is not byte-identical to the active release' "$CASE_ROOT/err"
[ "$(sha256 "$BIRD/KERNEL")" = "$MISMATCH_KERNEL_SHA" ]
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
[ ! -e "$TEST_STATE/gh-events" ]
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case archive-multiple-reclaim
create_completed_release active
create_completed_release retired-a 2097152
create_completed_release retired-b 2097152
create_completed_release retired-c 2097152
select_fixture_release active
BIRD_TEST_BIRD_FREE_BYTES=1
run_command --release >"$CASE_ROOT/out"
[ -d "$BIRD/bird-releases/active" ]
[ ! -e "$BIRD/bird-releases/retired-a" ]
[ ! -e "$BIRD/bird-releases/retired-b" ]
[ -d "$BIRD/bird-releases/retired-c" ]
grep -q 'Archived inactive release retired-a' "$CASE_ROOT/out"
grep -q 'Archived inactive release retired-b' "$CASE_ROOT/out"
[ ! -e "$TEST_STATE/gh-release-card-retired-c-state" ]
grep -Fq 'bird_release=v6.23' "$BIRD/extlinux/extlinux.conf"

new_case fallback-archive-dry-run
create_completed_release fallback-old-a 2097152
create_completed_release fallback-old-b 2097152
select_fixture_fallback
FALLBACK_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
BIRD_TEST_BIRD_FREE_BYTES=1
run_command --release --dry-run >"$CASE_ROOT/out"
grep -q 'would archive and verify inactive release fallback-old-a' "$CASE_ROOT/out"
grep -q 'would archive and verify inactive release fallback-old-b' "$CASE_ROOT/out"
[ -d "$BIRD/bird-releases/fallback-old-a" ]
[ -d "$BIRD/bird-releases/fallback-old-b" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$FALLBACK_SELECTOR_SHA" ]
[ ! -e "$TEST_STATE/gh-events" ]

new_case fallback-archive-reclaim
create_completed_release fallback-old-a 2097152
create_completed_release fallback-old-b 2097152
select_fixture_fallback
FALLBACK_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
FALLBACK_CONFIG_SHA=$(sha256 "$BIRD/extlinux/extlinux.fallback.conf")
FALLBACK_KERNEL_SHA=$(sha256 "$BIRD/KERNEL.fallback")
FALLBACK_DTB_SHA=$(sha256 "$BIRD/dtb.img")
BIRD_TEST_BIRD_FREE_BYTES=1
run_command --release >"$CASE_ROOT/out"
[ ! -e "$BIRD/bird-releases/fallback-old-a" ]
[ ! -e "$BIRD/bird-releases/fallback-old-b" ]
for FALLBACK_OLD_ID in fallback-old-a fallback-old-b; do
	[ "$(cat "$TEST_STATE/gh-release-card-$FALLBACK_OLD_ID-state")" = false ]
	[ -f "$TEST_STATE/gh-release-card-$FALLBACK_OLD_ID-assets/birdOS-RG34XX-SP-$FALLBACK_OLD_ID.tar" ]
done
[ "$(sha256 "$BIRD/extlinux/extlinux.previous.conf")" = "$FALLBACK_SELECTOR_SHA" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.fallback.conf")" = "$FALLBACK_CONFIG_SHA" ]
[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$FALLBACK_KERNEL_SHA" ]
[ "$(sha256 "$BIRD/dtb.img")" = "$FALLBACK_DTB_SHA" ]
grep -Fq 'bird_release=v6.23' "$BIRD/extlinux/extlinux.conf"

new_case fallback-interrupted-deployment
create_completed_release fallback-old-a 2097152
create_completed_release fallback-old-b 2097152
select_fixture_fallback
FALLBACK_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
FALLBACK_CONFIG_SHA=$(sha256 "$BIRD/extlinux/extlinux.fallback.conf")
FALLBACK_KERNEL_SHA=$(sha256 "$BIRD/KERNEL.fallback")
FALLBACK_DTB_SHA=$(sha256 "$BIRD/dtb.img")
BIRD_TEST_BIRD_FREE_BYTES=1
TEST_UPDATER_BEHAVIOR=interrupt
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'fallback interrupted deployment unexpectedly succeeded'
fi
[ ! -e "$BIRD/bird-releases/fallback-old-a" ]
[ ! -e "$BIRD/bird-releases/fallback-old-b" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$FALLBACK_SELECTOR_SHA" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.fallback.conf")" = "$FALLBACK_CONFIG_SHA" ]
[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$FALLBACK_KERNEL_SHA" ]
[ "$(sha256 "$BIRD/dtb.img")" = "$FALLBACK_DTB_SHA" ]
[ -d "$BIRD/bird-releases/.v6.23.new.interrupted" ]

new_case near-fallback-rejected
create_completed_release fallback-old 5242880
select_fixture_fallback
printf '\n' >>"$BIRD/extlinux/extlinux.conf"
NEAR_FALLBACK_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
BIRD_TEST_BIRD_FREE_BYTES=1
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'non-canonical fallback selector was accepted'
fi
grep -q 'active selector does not contain exactly one Bird release ID' "$CASE_ROOT/err"
[ -d "$BIRD/bird-releases/fallback-old" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$NEAR_FALLBACK_SHA" ]
[ ! -e "$TEST_STATE/gh-events" ]
[ ! -e "$TEST_STATE/builder-preflight-release-id" ]

new_case fallback-changed-marker
create_completed_release fallback-old 5242880
select_fixture_fallback
printf '%s\n' changed >"$BIRD/bird-releases/fallback-old/.complete"
FALLBACK_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
BIRD_TEST_BIRD_FREE_BYTES=1
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'fallback inactive release with changed completion marker was archived'
fi
grep -q 'retirement candidate completion marker changed: fallback-old' "$CASE_ROOT/err"
[ -d "$BIRD/bird-releases/fallback-old" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$FALLBACK_SELECTOR_SHA" ]
[ ! -e "$TEST_STATE/gh-events" ]

new_case archive-upload-failure
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
PRIOR_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
BIRD_TEST_BIRD_FREE_BYTES=1
TEST_GH_BEHAVIOR=upload-failure
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'GitHub archive upload failure unexpectedly deployed'
fi
grep -q 'could not upload inactive release archive' "$CASE_ROOT/err"
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PRIOR_SELECTOR_SHA" ]
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case archive-published-tar-mismatch
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
PUBLISHED_ASSETS=$TEST_STATE/gh-release-card-retired-assets
mkdir -p "$PUBLISHED_ASSETS"
printf '%s\n' false >"$TEST_STATE/gh-release-card-retired-state"
printf '%s\n' 'wrong archived release bytes' \
	>"$PUBLISHED_ASSETS/birdOS-RG34XX-SP-retired.tar"
cp "$BIRD/bird-releases/retired/deploy-manifest.tsv" \
	"$PUBLISHED_ASSETS/retired.deploy-manifest.tsv"
printf '%s\n' 'fixture checksum asset' >"$PUBLISHED_ASSETS/retired.SHA256SUMS"
PRIOR_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
BIRD_TEST_BIRD_FREE_BYTES=1
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'published archive with mismatched tar bytes unexpectedly deployed'
fi
grep -q 'published archive differs from the verified card release: card-retired' \
	"$CASE_ROOT/err"
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PRIOR_SELECTOR_SHA" ]
[ ! -e "$TEST_STATE/builder-release-id" ]
[ ! -e "$TEST_STATE/updater-ran" ]

new_case archive-published-equivalent-tar-metadata
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
PUBLISHED_ASSETS=$TEST_STATE/gh-release-card-retired-assets
mkdir -p "$PUBLISHED_ASSETS"
printf '%s\n' false >"$TEST_STATE/gh-release-card-retired-state"
COPYFILE_DISABLE=1 tar -cf \
	"$PUBLISHED_ASSETS/birdOS-RG34XX-SP-retired.tar" \
	-C "$BIRD/bird-releases" retired
cp "$BIRD/bird-releases/retired/deploy-manifest.tsv" \
	"$PUBLISHED_ASSETS/retired.deploy-manifest.tsv"
printf '%s\n' 'fixture checksum asset' >"$PUBLISHED_ASSETS/retired.SHA256SUMS"
# Change only archive-header metadata after publication. The canonical payload
# and manifest remain identical, so retirement must not depend on rebuilt tar
# byte identity.
touch -t 202001010000 "$BIRD/bird-releases/retired"
BIRD_TEST_BIRD_FREE_BYTES=1
run_command --release >"$CASE_ROOT/out"
[ ! -e "$BIRD/bird-releases/retired" ]
grep -q 'Archived inactive release retired' "$CASE_ROOT/out"
[ -e "$TEST_STATE/updater-ran" ]

new_case archive-changed-marker
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
printf '%s\n' changed >"$BIRD/bird-releases/retired/.complete"
PRIOR_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
BIRD_TEST_BIRD_FREE_BYTES=1
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'changed inactive completion marker was archived'
fi
grep -q 'retirement candidate completion marker changed' "$CASE_ROOT/err"
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PRIOR_SELECTOR_SHA" ]
[ ! -e "$TEST_STATE/gh-events" ]
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case archive-immutability-required
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
PRIOR_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
BIRD_TEST_BIRD_FREE_BYTES=1
TEST_GH_BEHAVIOR=immutable-disabled
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'archive repository without immutability was accepted'
fi
grep -q 'GitHub release immutability is not enabled' "$CASE_ROOT/err"
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PRIOR_SELECTOR_SHA" ]
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case archive-private-required
create_completed_release active
create_completed_release retired 5242880
select_fixture_release active
PRIOR_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
BIRD_TEST_BIRD_FREE_BYTES=1
TEST_GH_BEHAVIOR=public-repository
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'public archive repository was accepted'
fi
grep -q 'GitHub release archive is not private' "$CASE_ROOT/err"
[ -d "$BIRD/bird-releases/active" ]
[ -d "$BIRD/bird-releases/retired" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PRIOR_SELECTOR_SHA" ]
[ ! -e "$TEST_STATE/builder-release-id" ]

new_case stale-output
mkdir "$WORK_ROOT/bird-rocknix-stock-root-v6.23"
printf 'stale\n' >"$WORK_ROOT/bird-rocknix-stock-root-v6.23/stale-marker"
run_command --release >"$CASE_ROOT/out"
[ "$(cat "$TEST_STATE/builder-profile")" = unset ]
[ "$(cat "$TEST_STATE/builder-release-id")" = v6.23 ]
[ "$(cat "$TEST_STATE/updater-release-id")" = v6.23 ]
[ ! -e "$WORK_ROOT/bird-rocknix-stock-root-v6.23/stale-marker" ]
grep -q 'Deployment result: activated new immutable release' "$CASE_ROOT/out"

new_case profile
run_command --profile --release-id phase2 >"$CASE_ROOT/out"
[ "$(cat "$TEST_STATE/builder-profile")" = profile ]
[ "$(cat "$TEST_STATE/builder-release-id")" = phase2 ]
[ "$(cat "$TEST_STATE/updater-release-id")" = phase2 ]
grep -q 'early-initramfs-latest.log' "$CASE_ROOT/out"

new_case occupied-id
mkdir "$BIRD/bird-releases/v6.23"
printf 'changed marker\n' >"$BIRD/bird-releases/v6.23/.complete"
run_command --release >"$CASE_ROOT/out"
[ "$(cat "$TEST_STATE/builder-release-id")" = v6.23-20260727-120000 ]
[ "$(cat "$TEST_STATE/updater-release-id")" = v6.23-20260727-120000 ]
[ "$(cat "$BIRD/bird-releases/v6.23/.complete")" = 'changed marker' ]
grep -q 'already occupied on the card or in the archive; selected v6.23-20260727-120000' "$CASE_ROOT/out"

new_case archived-id
mkdir -p "$TEST_STATE/gh-release-card-v6.23-assets"
printf '%s\n' false >"$TEST_STATE/gh-release-card-v6.23-state"
run_command --release >"$CASE_ROOT/out"
[ "$(cat "$TEST_STATE/builder-release-id")" = v6.23-20260727-120000 ]
[ "$(cat "$TEST_STATE/updater-release-id")" = v6.23-20260727-120000 ]
grep -q 'already occupied on the card or in the archive; selected v6.23-20260727-120000' "$CASE_ROOT/out"

new_case manifest-failure
TEST_BUILDER_BEHAVIOR=bad-manifest
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'corrupt generated manifest was accepted'
fi
grep -q 'candidate digest changed: bird/bird-launcher' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/updater-ran" ]
[ ! -e "$BIRD/bird-releases/v6.23" ]

new_case manifest-artifacts-missing
TEST_BUILDER_BEHAVIOR=missing-artifacts
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'generated manifest without Stage 0 artifact bindings was accepted'
fi
grep -q 'canonical deploy manifest is malformed' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/updater-ran" ]

new_case manifest-contract-binding
TEST_BUILDER_BEHAVIOR=bad-contract-artifact
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'generated manifest with a mismatched device contract was accepted'
fi
grep -q 'device-contract artifact does not match' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/updater-ran" ]

new_case manifest-catalog-binding
TEST_BUILDER_BEHAVIOR=bad-catalog-artifact
if run_command --release >"$CASE_ROOT/out" 2>"$CASE_ROOT/err"; then
	fail 'generated manifest with a mismatched catalog was accepted'
fi
grep -q 'catalog artifact does not match' "$CASE_ROOT/err"
[ ! -e "$TEST_STATE/updater-ran" ]

new_case interrupted-deployment
PRIOR_SELECTOR_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")
TEST_UPDATER_BEHAVIOR=interrupt
if run_command --release >"$CASE_ROOT/first.out" 2>"$CASE_ROOT/first.err"; then
	fail 'interrupted deployment unexpectedly succeeded'
fi
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$PRIOR_SELECTOR_SHA" ]
[ -d "$BIRD/bird-releases/.v6.23.new.interrupted" ]
[ ! -e "$BIRD/bird-releases/v6.23" ]
TEST_UPDATER_BEHAVIOR=normal
run_command --release >"$CASE_ROOT/second.out"
[ ! -e "$BIRD/bird-releases/.v6.23.new.interrupted" ]
[ -f "$BIRD/bird-releases/v6.23/.complete" ]
grep -Fq 'bird_release=v6.23' "$BIRD/extlinux/extlinux.conf"

new_case identical-race
TEST_BUILDER_BEHAVIOR=preinstall-identical
run_command --release >"$CASE_ROOT/out"
grep -q 'verified and activated already-installed identical release' "$CASE_ROOT/out"
[ -f "$TEST_STATE/updater-ran" ]

printf '%s\n' 'build-and-deploy host tests: PASS'
