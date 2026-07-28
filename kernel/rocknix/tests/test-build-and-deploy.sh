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

FAKE_BUILDER=$TMP/fake-builder.sh
FAKE_UPDATER=$TMP/fake-updater.sh
FAKE_TOOL=$TMP/fake-tool
FAKE_GH=$TMP/fake-gh.sh

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

cat >"$FAKE_BUILDER" <<'EOF'
#!/bin/sh
set -eu

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
mode() { stat -f '%Lp' "$1"; }
bytes() { stat -f '%z' "$1"; }

if [ "${BIRD_BUILD_PREFLIGHT_ONLY:-0}" = 1 ]; then
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
printf '%s\n' \
	'LABEL BIRD' \
	"  LINUX /bird-releases/$BIRD_RELEASE_ID/KERNEL" \
	"  INITRD /bird-releases/$BIRD_RELEASE_ID/bird-initramfs.cpio.gz" \
	"  FDT /bird-releases/$BIRD_RELEASE_ID/dtb.img" \
	"  APPEND bird_release=$BIRD_RELEASE_ID" >"$OUTPUT/card/extlinux/extlinux.conf"
chmod 0755 "$OUTPUT/card/bird/bird-launcher"
chmod 0644 "$OUTPUT/card/extlinux/extlinux.conf"

printf '%s\n' "$BIRD_RELEASE_ID" >"$TEST_STATE/builder-release-id"
printf '%s\n' "${BIRD_LAUNCHER_PROFILE-unset}" >"$TEST_STATE/builder-profile"
printf '%s\n' "$OUTPUT" >"$TEST_STATE/builder-output"

MANIFEST=$OUTPUT/deploy-manifest.tsv
{
	printf 'schema\tbird-deploy-v1\n'
	printf 'release\t%s\n' "$BIRD_RELEASE_ID"
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
chmod 0755 "$FAKE_TOOL" "$FAKE_GH" "$FAKE_BUILDER" "$FAKE_UPDATER"

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
	mkdir -p "$BIRD/bird-releases" "$BIRD/extlinux" "$DATA/MUOS/runtime" \
		"$WORK_ROOT" "$TEST_STATE" "$SYSTEM_TREE/usr/bin" \
		"$SYSTEM_TREE/usr/config/PortMaster/release" "${OFFICIAL_INIT%/*}"
	printf 'rocknix kernel\n' >"$BIRD/KERNEL"
	printf 'fallback kernel\n' >"$BIRD/KERNEL.fallback"
	printf 'fixed dtb\n' >"$BIRD/dtb.img"
	printf 'prior selector\n' >"$BIRD/extlinux/extlinux.conf"
	printf 'runtime\n' >"$SYSTEM_SOURCE"
	printf 'storage\n' >"$STORAGE_SOURCE"
	printf 'autostart\n' >"$SYSTEM_TREE/usr/bin/autostart"
	printf 'portmaster\n' >"$PORTMASTER_ARCHIVE"
	printf 'init\n' >"$OFFICIAL_INIT"
	printf 'busybox\n' >"$INIT_BUSYBOX"
	printf 'joypad\n' >"$JOYPAD"
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
	mkdir -p "$FIXTURE_RELEASE"
	printf 'fixture release %s\n' "$FIXTURE_RELEASE_ID" >"$FIXTURE_RELEASE/payload.bin"
	if [ "$FIXTURE_PAYLOAD_BYTES" -gt 0 ]; then
		FIXTURE_MIB=$((FIXTURE_PAYLOAD_BYTES / 1048576))
		dd if=/dev/zero bs=1048576 count="$FIXTURE_MIB" \
			of="$FIXTURE_RELEASE/payload.bin" 2>/dev/null
	fi
	chmod 0644 "$FIXTURE_RELEASE/payload.bin"
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
		printf 'file\tpayload.bin\t%s\t%s\t%s\n' \
			"$(mode "$FIXTURE_RELEASE/payload.bin")" \
			"$(bytes "$FIXTURE_RELEASE/payload.bin")" \
			"$(sha256 "$FIXTURE_RELEASE/payload.bin")"
	} >"$FIXTURE_MANIFEST"
	sha256 "$FIXTURE_MANIFEST" >"$FIXTURE_RELEASE/.complete"
}

select_fixture_release() {
	FIXTURE_ACTIVE_ID=$1
	printf '%s\n' \
		'LABEL BIRD' \
		"  LINUX /bird-releases/$FIXTURE_ACTIVE_ID/KERNEL" \
		"  APPEND bird_release=$FIXTURE_ACTIVE_ID" \
		>"$BIRD/extlinux/extlinux.conf"
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
