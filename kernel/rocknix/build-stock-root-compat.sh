#!/bin/sh
# Build the compatibility-first Bird milestone from one exact ROCKNIX release.
# KERNEL, dtb.img, SYSTEM and the initial STORAGE filesystem are checksummed as
# a set. Bird's normal userspace executable, tiny early overlay and integration
# hooks are the only rebuilt pieces.

set -eu

configure_reproducible_build_environment() {
	# Neither archive metadata nor output permissions may inherit the invoking
	# shell's locale, timezone or umask.
	umask 022
	LC_ALL=C
	TZ=UTC
	export LC_ALL TZ
}
configure_reproducible_build_environment

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SOURCE=${SOURCE:-/Volumes/BIRD}
SYSTEM_SOURCE=${SYSTEM_SOURCE:-/Volumes/BIRD-DATA/MUOS/runtime/ROCKNIX-SYSTEM}
STORAGE=${STORAGE:-$HOME/rocknix-reference-result/storage.ext4}
SYSTEM_TREE=${SYSTEM_TREE:-$ROOT/kernel/work/rocknix-system-exact-20260701}
RELEASE_ID=${BIRD_RELEASE_ID:-v6.23}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-rocknix-stock-root-$RELEASE_ID}
CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
LLD=${LLD:-/opt/homebrew/opt/lld/bin/ld.lld}
READELF=${READELF:-/opt/homebrew/opt/llvm/bin/llvm-readelf}

KERNEL_SHA=af4e75cb30b097ee5764764eb056d686bc00c6bd03fefece26b0ebbaa7fbb673
DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
SYSTEM_SHA=6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac
STORAGE_SHA=12affdad7bc2042cb590fea60fc015a7ee8d4374ebcc3b1c11098a64b9ffa3be
AUTOSTART_SHA=7f8671aa1bb9239a193f84e667d55e169f983bcb015d98c345b60d0b80a77639
OFFICIAL_INIT_SHA=3473415af0cf5df44e70259c3392817b1df421a12a617ec083ec018ff51dbc48
JOYPAD_SHA=a8ac6cacfa89672fa08dec7fa02179bb108a4a2303fd5c1eb5834f916089b79b
INIT_BUSYBOX_SHA=5ee3d20d8ea5fd9b3ba5109da80599eaf46a5a337d9e40d4c67d28eef44d5dc8
SYSTEM_BUSYBOX_SHA=b90f5f58dd5c39348f7be9bbef79b349f51e6ac0117b217691e2701d73714b38
PORTMASTER_ARCHIVE_SHA=9d6f25d461afced95569923a57c6a9c42df225190c043d74fe2ec0edcf40a477
PORTMASTER_PUGWASH_SHA=3b9ea60ccf202f64155c669fd0b2b18fcb0e5c72e293ad0c61f7c2f2fdcb51d8
PORTMASTER_SH_SHA=554c92cf5ea6656a6bfbd1ddd81619fdf4ff0524ac40d14c19193f2aa33da804
PORTMASTER_MOD_SHA=8eaf22ed31bbf446c5113b56b55666f42317f8f81d96e1c86a0f04dde07277a1
PORTMASTER_FUNCS_SHA=f72b9971c2964e44592dd3ffca1b3ccf0ae31e9c4dd2cb32508a6990f81a5d22
PORTMASTER_HARBOURMASTER_SHA=74f55c5cf9335ac56dc6b4dbbdd8c26a0a198e4117b2887323eec070c734ff40
OFFICIAL_INIT=${OFFICIAL_INIT:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/init}
JOYPAD=${JOYPAD:-$ROOT/kernel/work/rocknix-system-exact-20260701/usr/lib/kernel-overlays/base/lib/modules/7.0.11/rocknix-joypad/rocknix-singleadc-joypad.ko}
INIT_BUSYBOX=${INIT_BUSYBOX:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/usr/bin/busybox}
SYSTEM_BUSYBOX=${SYSTEM_BUSYBOX:-$SYSTEM_TREE/usr/bin/busybox}
PORTMASTER_ARCHIVE=${PORTMASTER_ARCHIVE:-$SYSTEM_TREE/usr/config/PortMaster/release/PortMaster.zip}

case "$OUTPUT" in
	/*) ;;
	*) OUTPUT=$PWD/$OUTPUT ;;
esac

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

validate_final_launcher_static_assets() {
	FINAL_BASE=$OUTPUT/card/bird/launcher-base.xrgb
	[ -f "$FINAL_BASE" ] && [ ! -L "$FINAL_BASE" ] || \
		fail 'final-root launcher static base is missing or unsafe'
	[ "$(file_bytes "$FINAL_BASE")" -eq 1382400 ] || \
		fail 'final-root launcher static base size changed'
	[ "$(sha256 "$FINAL_BASE")" = \
		6f9daae758675bd8bb805a851b30f1d64b06ec6e8367a17749707ac61824843a ] || \
		fail 'final-root launcher static base digest changed'
	if find "$OUTPUT/card/bird" -type f ! -path "$FINAL_BASE" \
		\( -iname '*.bmp' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
			-o -iname '*.rgb' -o -iname '*.rgba' -o -iname '*.xrgb' -o -iname '*.raw' \) \
		-print -quit | grep -q .; then
		fail 'final-root launcher payload contains an unbudgeted static image'
	fi
}

case "$RELEASE_ID" in
	''|[![:alnum:]]*|*[![:alnum:]._-]*) fail "unsafe Bird release ID: $RELEASE_ID" ;;
esac
[ "${#RELEASE_ID}" -le 64 ] || fail 'Bird release ID is longer than 64 bytes'
export BIRD_RELEASE_ID="$RELEASE_ID"

# Production builds must never inherit an ambient off-tree launcher override.
# The narrowly scoped dev workflow is the only caller allowed to opt in, and
# only for its explicitly mutable release.
case "${BIRD_DEV_LOCAL_BUILD:-0}" in
	0|'') unset BIRD_LOCAL_LAUNCHER_DIR ;;
	1)
		[ "$RELEASE_ID" = dev-current ] || \
			fail 'local launcher override is restricted to dev-current'
		[ -n "${BIRD_LOCAL_LAUNCHER_DIR:-}" ] || \
			fail 'dev local build requires its private launcher directory'
		;;
	*) fail 'invalid Bird dev local-build mode' ;;
esac

BIRD_INITRAMFS_GZIP_LEVEL=${BIRD_INITRAMFS_GZIP_LEVEL:-9}
case "$BIRD_INITRAMFS_GZIP_LEVEL" in
	1|9) ;;
	*) fail 'Bird initramfs gzip level must be 1 or 9' ;;
esac
export BIRD_INITRAMFS_GZIP_LEVEL

case "${BIRD_LAUNCHER_PROFILE:-none}" in
	none|0|'') ;;
	profile|1) ;;
	deep) fail 'BIRD_PROFILE_DEEP is host-test-only' ;;
	*) fail "unknown BIRD_LAUNCHER_PROFILE mode: $BIRD_LAUNCHER_PROFILE" ;;
esac
export BIRD_LAUNCHER_PROFILE

BIRD_BUILD_PREFLIGHT_ONLY=${BIRD_BUILD_PREFLIGHT_ONLY:-0}
case "$BIRD_BUILD_PREFLIGHT_ONLY" in
	0|1) ;;
	*) fail 'invalid Bird build preflight mode' ;;
esac

sha256() {
	BIRD_SHA256_LINE=$(shasum -a 256 "$1") || return 1
	printf '%s\n' "$BIRD_SHA256_LINE" | awk '{print $1}'
}

file_bytes() {
	stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"
}

file_mode() {
	stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

is_regular_file() {
	[ -f "$1" ] && [ ! -L "$1" ]
}

capture_source_identity() {
	BIRD_PROVENANCE_UNTRACKED=$1
	BIRD_PROVENANCE_INPUT=$2
	BIRD_CAPTURED_SOURCE_COMMIT=$(git -C "$ROOT" rev-parse --verify HEAD) ||
		fail 'could not read source commit'
	[ "${#BIRD_CAPTURED_SOURCE_COMMIT}" -eq 40 ] ||
		fail 'source commit is not a full object ID'
	case "$BIRD_CAPTURED_SOURCE_COMMIT" in
		*[!0-9a-f]*) fail 'source commit is not a lowercase hexadecimal object ID' ;;
	esac
	BIRD_CAPTURED_SOURCE_STATUS=$(
		git -C "$ROOT" status --porcelain --untracked-files=normal
	) || fail 'could not read source status'
	BIRD_PROVENANCE_UNSORTED=$BIRD_PROVENANCE_UNTRACKED.unsorted.$$
	git -C "$ROOT" ls-files --others --exclude-standard \
		>"$BIRD_PROVENANCE_UNSORTED" || fail 'could not inventory untracked sources'
	sort "$BIRD_PROVENANCE_UNSORTED" >"$BIRD_PROVENANCE_UNTRACKED" ||
		fail 'could not sort untracked sources'
	rm -f "$BIRD_PROVENANCE_UNSORTED"
	{
		printf '%s\n' "$BIRD_CAPTURED_SOURCE_STATUS"
		git -C "$ROOT" diff --binary HEAD -- || fail 'could not read source diff'
		while IFS= read -r BIRD_UNTRACKED_PATH; do
			[ -f "$ROOT/$BIRD_UNTRACKED_PATH" ] || continue
			printf 'untracked\t%s\t%s\t%s\t%s\n' "$BIRD_UNTRACKED_PATH" \
				"$(file_mode "$ROOT/$BIRD_UNTRACKED_PATH")" \
				"$(file_bytes "$ROOT/$BIRD_UNTRACKED_PATH")" \
				"$(sha256 "$ROOT/$BIRD_UNTRACKED_PATH")"
		done <"$BIRD_PROVENANCE_UNTRACKED"
	} >"$BIRD_PROVENANCE_INPUT" || fail 'could not capture source fingerprint input'
	BIRD_CAPTURED_SOURCE_DIFF_SHA=$(sha256 "$BIRD_PROVENANCE_INPUT") ||
		fail 'could not hash source fingerprint'
	rm -f "$BIRD_PROVENANCE_INPUT"
	if [ -z "$BIRD_CAPTURED_SOURCE_STATUS" ]; then
		BIRD_CAPTURED_SOURCE_STATE=clean
	else
		BIRD_CAPTURED_SOURCE_STATE=dirty:$BIRD_CAPTURED_SOURCE_DIFF_SHA
	fi
}

record_source_identity() {
	capture_source_identity "$OUTPUT/build/source-untracked.list" \
		"$OUTPUT/build/.source-fingerprint.before.$$"
	SOURCE_COMMIT=$BIRD_CAPTURED_SOURCE_COMMIT
	SOURCE_STATE=$BIRD_CAPTURED_SOURCE_STATE
}

verify_source_identity() {
	capture_source_identity "$OUTPUT/build/source-untracked.list" \
		"$OUTPUT/build/.source-fingerprint.after.$$"
	[ "$BIRD_CAPTURED_SOURCE_COMMIT" = "$SOURCE_COMMIT" ] &&
		[ "$BIRD_CAPTURED_SOURCE_STATE" = "$SOURCE_STATE" ] ||
		fail 'source tree changed while candidate bytes were being built'
}

[ -d "$SOURCE" ] || fail "mounted exact ROCKNIX release missing: $SOURCE"
is_regular_file "$SOURCE/KERNEL" || fail 'release KERNEL missing or not regular'
is_regular_file "$SOURCE/dtb.img" || fail 'release DTB missing or not regular'
is_regular_file "$SYSTEM_SOURCE" || fail 'release SYSTEM missing or not regular'
is_regular_file "$STORAGE" || fail 'captured ROCKNIX STORAGE image missing or not regular'
is_regular_file "$SYSTEM_TREE/usr/bin/autostart" || fail 'extracted exact autostart missing or not regular'
is_regular_file "$OFFICIAL_INIT" || fail 'exact initramfs init missing or not regular'
is_regular_file "$JOYPAD" || fail 'exact H700 input module missing or not regular'
is_regular_file "$INIT_BUSYBOX" || fail 'exact initramfs BusyBox missing or not regular'
is_regular_file "$SYSTEM_BUSYBOX" || fail 'extracted exact SYSTEM BusyBox missing or not regular'
is_regular_file "$PORTMASTER_ARCHIVE" || fail 'exact PortMaster archive missing or not regular'
[ "$(sha256 "$SOURCE/KERNEL")" = "$KERNEL_SHA" ] || fail 'release KERNEL changed'
[ "$(sha256 "$SOURCE/dtb.img")" = "$DTB_SHA" ] || fail 'release DTB changed'
[ "$(sha256 "$SYSTEM_SOURCE")" = "$SYSTEM_SHA" ] || fail 'release SYSTEM changed'
[ "$(sha256 "$STORAGE")" = "$STORAGE_SHA" ] || fail 'reference STORAGE changed'
[ "$(sha256 "$SYSTEM_TREE/usr/bin/autostart")" = "$AUTOSTART_SHA" ] || fail 'extracted exact autostart changed'
[ "$(file_bytes "$SYSTEM_TREE/usr/bin/autostart")" = 2168 ] || fail 'extracted exact autostart size changed'
[ "$(file_mode "$SYSTEM_TREE/usr/bin/autostart")" = 755 ] || fail 'extracted exact autostart mode changed'
[ "$(sha256 "$OFFICIAL_INIT")" = "$OFFICIAL_INIT_SHA" ] || fail 'exact initramfs init changed'
[ "$(sha256 "$JOYPAD")" = "$JOYPAD_SHA" ] || fail 'exact H700 input module changed'
[ "$(sha256 "$INIT_BUSYBOX")" = "$INIT_BUSYBOX_SHA" ] || fail 'exact initramfs BusyBox changed'
[ "$(sha256 "$SYSTEM_BUSYBOX")" = "$SYSTEM_BUSYBOX_SHA" ] || fail 'extracted exact SYSTEM BusyBox changed'
for APPLET in awk chmod cmp cp mv rm stat; do
	strings -a -n 2 "$SYSTEM_BUSYBOX" | grep -Fqx "$APPLET" || \
		fail "exact SYSTEM BusyBox lacks required $APPLET applet"
done
[ "$(sha256 "$PORTMASTER_ARCHIVE")" = "$PORTMASTER_ARCHIVE_SHA" ] || fail 'exact PortMaster archive changed'
[ -x "$CLANG" ] || fail 'LLVM clang missing'
[ -x "$LLD" ] || fail 'LLVM lld missing'
[ -x "$READELF" ] || fail 'LLVM readelf missing'
python3 "$ROOT/generate-device-contract.py" \
	"$ROOT/bird-device-contract.tsv" \
	"$ROOT/launcher/bird-device-contract.h" --check \
	--suspend-policy-output \
		"$ROOT/kernel/rocknix/stock-root/bird-suspend-policy.generated.sh" \
	--sleep-policy-output "$ROOT/kernel/rocknix/stock-root/bird-sleep.conf" \
	--logind-policy-output "$ROOT/kernel/rocknix/stock-root/bird-logind.conf" || \
fail 'generated fixed-device contract is stale or invalid'
python3 "$ROOT/kernel/rocknix/validate-canonical-namespace.py" || \
	fail 'canonical namespace contract is stale or invalid'
if [ "$BIRD_BUILD_PREFLIGHT_ONLY" = 1 ]; then
	printf 'Canonical pinned-input preflight passed for release %s.\n' "$RELEASE_ID"
	exit 0
fi
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"

mkdir -p "$OUTPUT/card/bird" "$OUTPUT/card/extlinux" "$OUTPUT/build"
chmod 0755 "$OUTPUT" "$OUTPUT/card" "$OUTPUT/card/bird" \
	"$OUTPUT/card/extlinux" "$OUTPUT/build"
record_source_identity
cp -fp "$ROOT/bird-device-contract.tsv" \
	"$OUTPUT/card/bird/bird-device-contract.tsv"
chmod 0644 "$OUTPUT/card/bird/bird-device-contract.tsv"
DEVICE_CONTRACT_SHA=$(sha256 "$ROOT/bird-device-contract.tsv")
CATALOG_SHA=$(sha256 "$ROOT/launcher/catalog.generated.h")
{
	printf 'component\tmode\tflags\n'
	sh "$ROOT/kernel/rocknix/build-bird-local-binary.sh" --contract final
	printf 'initramfs\trelease\t%s\n' \
		"find . -print | LC_ALL=C sort | cpio -o --format newc --owner 0:0; gzip -n -$BIRD_INITRAMFS_GZIP_LEVEL -c"
} >"$OUTPUT/build/build-flags.tsv"

BOOT_FRAME_WORK=$OUTPUT/build/boot-frame
mkdir -p "$BOOT_FRAME_WORK"
python3 "$ROOT/firmware/generate-launcher-bootlogo.py" \
	"$BOOT_FRAME_WORK/bird-frame-zero.bmp" \
	--contract "$OUTPUT/card/bird/boot-frame.contract" \
	--xrgb-output "$OUTPUT/card/bird/launcher-base.xrgb"
chmod 0644 "$OUTPUT/card/bird/boot-frame.contract" \
	"$OUTPUT/card/bird/launcher-base.xrgb"

# These five immutable provider files are deployment inputs even though they
# live inside the pinned PortMaster archive at build time and on p6 at update
# time. Materialize and verify each member so the canonical manifest can be the
# updater's sole byte contract for the installed provider.
PORTMASTER_INPUTS=$OUTPUT/build/manifest-inputs/PortMaster
mkdir -p "$PORTMASTER_INPUTS"
extract_portmaster_input() {
	NAME=$1
	MODE=$2
	EXPECTED_BYTES=$3
	EXPECTED_SHA=$4
	MEMBER=PortMaster/$NAME
	[ "$(unzip -Z1 "$PORTMASTER_ARCHIVE" "$MEMBER" | wc -l | tr -d ' ')" = 1 ] || \
		fail "PortMaster archive member is not unique: $MEMBER"
	unzip -p "$PORTMASTER_ARCHIVE" "$MEMBER" >"$PORTMASTER_INPUTS/$NAME" || \
		fail "could not extract PortMaster input: $MEMBER"
	chmod "$MODE" "$PORTMASTER_INPUTS/$NAME"
	[ "$(file_bytes "$PORTMASTER_INPUTS/$NAME")" = "$EXPECTED_BYTES" ] || \
		fail "PortMaster input size changed: $MEMBER"
	[ "$(sha256 "$PORTMASTER_INPUTS/$NAME")" = "$EXPECTED_SHA" ] || \
		fail "PortMaster input digest changed: $MEMBER"
}
extract_portmaster_input pugwash 0755 70737 "$PORTMASTER_PUGWASH_SHA"
extract_portmaster_input PortMaster.sh 0755 7356 "$PORTMASTER_SH_SHA"
extract_portmaster_input mod_ROCKNIX.txt 0644 895 "$PORTMASTER_MOD_SHA"
extract_portmaster_input funcs.txt 0644 4281 "$PORTMASTER_FUNCS_SHA"
extract_portmaster_input harbourmaster 0755 18807 "$PORTMASTER_HARBOURMASTER_SHA"

build_bird_local_binary() {
	BIRD_LOCAL_COMPONENT=$1
	BIRD_LOCAL_NAME=$2
	CLANG="$CLANG" LLD="$LLD" READELF="$READELF" \
		sh "$ROOT/kernel/rocknix/build-bird-local-binary.sh" \
		--build "$BIRD_LOCAL_COMPONENT" \
		--object "$OUTPUT/build/$BIRD_LOCAL_NAME.o" \
		--output "$OUTPUT/card/bird/$BIRD_LOCAL_NAME"
}
build_bird_local_binary final-launcher bird-launcher
build_bird_local_binary bird-pidwait bird-pidwait
build_bird_local_binary bird-fixed-controls bird-fixed-controls
build_bird_local_binary bird-mpv-controls bird-mpv-controls
build_bird_local_binary bird-powerstate bird-powerstate

OUTPUT="$OUTPUT" OFFICIAL_INIT="$OFFICIAL_INIT" JOYPAD="$JOYPAD" \
	INIT_BUSYBOX="$INIT_BUSYBOX" \
	"$ROOT/kernel/rocknix/build-stock-root-early-initramfs.sh"

cp -fp "$SOURCE/KERNEL" "$OUTPUT/card/KERNEL"
cp -fp "$SOURCE/dtb.img" "$OUTPUT/card/dtb.img"
cp -fp "$ROOT/kernel/rocknix/stock-root/post-flash.sh" \
	"$OUTPUT/card/post-flash.sh"
cp -fp "$ROOT/kernel/rocknix/stock-root/mount-storage.sh" \
	"$OUTPUT/card/mount-storage.sh"
for FILE in 090-ui_service 999-export bird-autostart bird-journald.conf \
	essway.service rocknix.target \
	rocknix-automount.service rocknix-autostart.service \
	rocknix-report-stats.service \
	NetworkManager.service iwd.service systemd-resolved.service \
	systemd-timesyncd.service systemd-rfkill.service \
	bird-fixed-controls.service \
	bird-powerstate.service supervisor.sh run-content.sh bird-mpv-player.sh \
	prepare-ports.sh verify-portmaster-provider.sh \
	portmaster-provider.manifest.tsv fixed-storage.sh first-frame-prep.sh \
	capture-boot-state.sh capture-requested-diagnostics.sh capture-stage5-state.sh \
	capture-stage5-window-counters.sh capture-stage5-window.sh \
	bird-network.sh bird-fixed-control-exit.sh \
	bird-emergency-recover.sh \
	bird-save-config.sh bird-save-config.service bird-suspend.sh \
	bird-restore-suspend-policy.sh bird-volume.sh bird-control-osd.sh \
	bird-fixed-sway.sh bird-fixed-platform.sh bird-fixed-logging.sh \
	bird-fixed-pico8.sh bird-fixed-controller.sh bird-fixed-setup.sh \
	bird-fixed-performance.sh bird-fixed-gpu-overclock.sh \
	bird-fixed-rumble.sh bird-fixed-turbo.sh \
	bird-controller-profile \
	bird-swap.conf bird-suspend-policy.generated.sh bird-sleep.conf; do
	cp -fp "$ROOT/kernel/rocknix/stock-root/$FILE" "$OUTPUT/card/bird/$FILE"
done
cp -fp "$ROOT/kernel/rocknix/stock-root/mpv-input.conf" \
	"$OUTPUT/card/bird/mpv-input.conf"
cp -fp "$ROOT/kernel/rocknix/stock-root/extlinux.conf" \
	"$OUTPUT/card/extlinux/extlinux.conf"
touch "$OUTPUT/card/SYSTEM"

# These three generated runtime files must agree with the manifest release.
# Their committed sources retain v6.23 as the accepted direct-test default;
# only candidate output is specialized for a selected immutable release ID.
sed "s#v6\.23#$RELEASE_ID#g" \
	"$ROOT/kernel/rocknix/stock-root/extlinux.conf" \
	>"$OUTPUT/card/extlinux/extlinux.conf"
sed "s#^RELEASE_ID=v6\.23\$#RELEASE_ID=$RELEASE_ID#" \
	"$ROOT/kernel/rocknix/stock-root/supervisor.sh" \
	>"$OUTPUT/card/bird/supervisor.sh"
chmod 0644 "$OUTPUT/card/SYSTEM"
chmod 0755 "$OUTPUT/card/post-flash.sh" "$OUTPUT/card/mount-storage.sh" \
	"$OUTPUT/card/bird/090-ui_service" \
	"$OUTPUT/card/bird/999-export" \
	"$OUTPUT/card/bird/supervisor.sh" "$OUTPUT/card/bird/run-content.sh" \
	"$OUTPUT/card/bird/bird-mpv-player.sh" \
	"$OUTPUT/card/bird/prepare-ports.sh" \
	"$OUTPUT/card/bird/verify-portmaster-provider.sh" \
	"$OUTPUT/card/bird/fixed-storage.sh" \
	"$OUTPUT/card/bird/first-frame-prep.sh" \
	"$OUTPUT/card/bird/capture-boot-state.sh" \
	"$OUTPUT/card/bird/capture-requested-diagnostics.sh" \
	"$OUTPUT/card/bird/capture-stage5-state.sh" \
	"$OUTPUT/card/bird/capture-stage5-window-counters.sh" \
	"$OUTPUT/card/bird/capture-stage5-window.sh" \
	"$OUTPUT/card/bird/bird-network.sh" \
	"$OUTPUT/card/bird/bird-fixed-control-exit.sh" \
	"$OUTPUT/card/bird/bird-emergency-recover.sh" \
	"$OUTPUT/card/bird/bird-save-config.sh" \
	"$OUTPUT/card/bird/bird-suspend.sh" \
	"$OUTPUT/card/bird/bird-restore-suspend-policy.sh" \
	"$OUTPUT/card/bird/bird-volume.sh" \
	"$OUTPUT/card/bird/bird-control-osd.sh" \
	"$OUTPUT/card/bird/bird-autostart" \
	"$OUTPUT/card/bird/bird-fixed-sway.sh" \
	"$OUTPUT/card/bird/bird-fixed-platform.sh" \
	"$OUTPUT/card/bird/bird-fixed-logging.sh" \
	"$OUTPUT/card/bird/bird-fixed-pico8.sh" \
	"$OUTPUT/card/bird/bird-fixed-controller.sh" \
	"$OUTPUT/card/bird/bird-fixed-setup.sh" \
	"$OUTPUT/card/bird/bird-fixed-performance.sh" \
	"$OUTPUT/card/bird/bird-fixed-gpu-overclock.sh" \
	"$OUTPUT/card/bird/bird-fixed-rumble.sh" \
	"$OUTPUT/card/bird/bird-fixed-turbo.sh"

for SCRIPT in "$OUTPUT/card/post-flash.sh" \
	"$OUTPUT/card/mount-storage.sh" \
	"$OUTPUT/card/bird/090-ui_service" \
	"$OUTPUT/card/bird/999-export" \
	"$OUTPUT/card/bird/supervisor.sh" \
	"$OUTPUT/card/bird/run-content.sh" \
	"$OUTPUT/card/bird/prepare-ports.sh" \
	"$OUTPUT/card/bird/verify-portmaster-provider.sh" \
	"$OUTPUT/card/bird/fixed-storage.sh" \
	"$OUTPUT/card/bird/first-frame-prep.sh" \
	"$OUTPUT/card/bird/capture-boot-state.sh" \
	"$OUTPUT/card/bird/capture-requested-diagnostics.sh" \
	"$OUTPUT/card/bird/capture-stage5-state.sh" \
	"$OUTPUT/card/bird/capture-stage5-window-counters.sh" \
	"$OUTPUT/card/bird/capture-stage5-window.sh" \
	"$OUTPUT/card/bird/bird-network.sh" \
	"$OUTPUT/card/bird/bird-fixed-control-exit.sh" \
	"$OUTPUT/card/bird/bird-emergency-recover.sh" \
	"$OUTPUT/card/bird/bird-save-config.sh" \
	"$OUTPUT/card/bird/bird-suspend.sh" \
	"$OUTPUT/card/bird/bird-restore-suspend-policy.sh" \
	"$OUTPUT/card/bird/bird-volume.sh" \
	"$OUTPUT/card/bird/bird-control-osd.sh" \
	"$OUTPUT/card/bird/bird-autostart" \
	"$OUTPUT/card/bird/bird-fixed-sway.sh" \
	"$OUTPUT/card/bird/bird-fixed-platform.sh" \
	"$OUTPUT/card/bird/bird-fixed-logging.sh" \
	"$OUTPUT/card/bird/bird-fixed-pico8.sh" \
	"$OUTPUT/card/bird/bird-fixed-controller.sh" \
	"$OUTPUT/card/bird/bird-fixed-setup.sh" \
	"$OUTPUT/card/bird/bird-fixed-performance.sh" \
	"$OUTPUT/card/bird/bird-fixed-gpu-overclock.sh" \
	"$OUTPUT/card/bird/bird-fixed-rumble.sh" \
	"$OUTPUT/card/bird/bird-fixed-turbo.sh"; do
	bash -n "$SCRIPT" || fail "shell syntax failed: $SCRIPT"
done
bash -n "$OUTPUT/card/bird/bird-suspend-policy.generated.sh" || \
	fail 'generated suspend policy shell syntax failed'
chmod 0644 "$OUTPUT/card/bird/portmaster-provider.manifest.tsv"
chmod 0644 "$OUTPUT/card/bird/bird-suspend-policy.generated.sh" \
	"$OUTPUT/card/bird/bird-sleep.conf" \
	"$OUTPUT/card/bird/bird-journald.conf" \
	"$OUTPUT/card/bird/bird-controller-profile"
[ "$(file_mode "$OUTPUT/card/bird/verify-portmaster-provider.sh")" = 755 ] || \
	fail 'PortMaster provider verifier mode changed'
[ "$(file_mode "$OUTPUT/card/bird/portmaster-provider.manifest.tsv")" = 644 ] || \
	fail 'PortMaster provider manifest mode changed'
[ "$(file_mode "$OUTPUT/card/bird/bird-suspend-policy.generated.sh")" = 644 ] || \
	fail 'generated suspend policy mode changed'
[ "$(file_mode "$OUTPUT/card/bird/bird-sleep.conf")" = 644 ] || \
	fail 'systemd sleep policy mode changed'
[ "$(file_mode "$OUTPUT/card/bird/bird-journald.conf")" = 644 ] || \
	fail 'journald policy mode changed'
[ "$(file_mode "$OUTPUT/card/bird/bird-controller-profile")" = 644 ] || \
	fail 'fixed controller profile mode changed'

[ "$(sha256 "$OUTPUT/card/KERNEL")" = "$KERNEL_SHA" ] || fail 'copied KERNEL changed'
[ "$(sha256 "$OUTPUT/card/dtb.img")" = "$DTB_SHA" ] || fail 'copied DTB changed'
grep -q 'runemu.sh' "$OUTPUT/card/bird/run-content.sh" || fail 'ROCKNIX dispatcher missing'
grep -Fq '/storage/roms/A2600/*)' "$OUTPUT/card/bird/run-content.sh" || \
	fail 'canonical ROM provider mapping missing'
if grep -Fq '*/ROMS/A2600/*)' "$OUTPUT/card/bird/run-content.sh"; then
	fail 'legacy ROM provider mapping remains active'
fi
grep -q 'PortMaster.zip' "$OUTPUT/card/bird/prepare-ports.sh" || fail 'exact PortMaster bootstrap missing'
grep -Fq 'FIXED_STORAGE=/flash/bird/fixed-storage.sh' \
	"$OUTPUT/card/bird/prepare-ports.sh" || \
	fail 'immutable fixed storage repair path missing'
grep -Fq 'PROVIDER_MANIFEST=/flash/bird/portmaster-provider.manifest.tsv' \
	"$OUTPUT/card/bird/prepare-ports.sh" || \
	fail 'immutable PortMaster provider manifest integration missing'
grep -Fq 'PROVIDER_VERIFIER=/flash/bird/verify-portmaster-provider.sh' \
	"$OUTPUT/card/bird/prepare-ports.sh" || \
	fail 'immutable PortMaster provider verifier integration missing'
grep -Fq 'schema	bird-portmaster-provider-v1' \
	"$OUTPUT/card/bird/portmaster-provider.manifest.tsv" || \
	fail 'exact PortMaster provider manifest missing'
grep -Fq 'provider_install_checkpoint_valid' \
	"$OUTPUT/card/bird/prepare-ports.sh" || \
	fail 'PortMaster transactional installation checkpoint missing'
if grep -Fq 'provider_checkpoint "$PORTMASTER"' \
	"$OUTPUT/card/bird/prepare-ports.sh"; then
	fail 'PortMaster provider verification returned to a launch path'
fi
grep -Fq 'preserving it without replacement' \
	"$OUTPUT/card/bird/prepare-ports.sh" || \
	fail 'PortMaster unverified-provider preservation gate missing'
if grep -Fq 'rm -rf "$PORTMASTER"' \
	"$OUTPUT/card/bird/prepare-ports.sh"; then
	fail 'PortMaster runtime still deletes an installed provider'
fi
grep -q '^VOLUME_UP ignore$' "$OUTPUT/card/bird/mpv-input.conf" || fail 'MPV volume policy missing'
if grep -q '^GAMEPAD_' "$OUTPUT/card/bird/mpv-input.conf"; then
	fail 'MPV policy still contains a second gamepad translation path'
fi
grep -Fq -- '--input-gamepad=no' "$OUTPUT/card/bird/bird-mpv-player.sh" || \
	fail 'MPV SDL gamepad path is not disabled'
grep -Fq -- '--input-default-bindings=no' \
	"$OUTPUT/card/bird/bird-mpv-player.sh" || \
	fail 'MPV default input path is not disabled'
grep -Fq -- '--term-osd=no' "$OUTPUT/card/bird/bird-mpv-player.sh" || \
	fail 'MPV release terminal status suppression is missing'
grep -Fq -- '--msg-level=all=warn' "$OUTPUT/card/bird/bird-mpv-player.sh" || \
	fail 'MPV release warning/error policy is missing'
grep -Fq 'BIRD_MPV_TRACE' "$OUTPUT/card/bird/bird-mpv-player.sh" || \
	fail 'MPV trace-mode diagnostic override is missing'
grep -Fq '/flash/bird/bird-mpv-controls' \
	"$OUTPUT/card/bird/bird-mpv-player.sh" || \
	fail 'fixed MPV controls are not launched'
grep -Fq 'set_kill set "mpv"' "$OUTPUT/card/bird/bird-mpv-player.sh" || \
	fail 'MPV fake-suspend process publication is missing'
grep -Fq 'set_kill stop' "$OUTPUT/card/bird/bird-mpv-player.sh" || \
	fail 'MPV fake-suspend process cleanup is missing'
grep -Fq 'run_managed "$MPV_PLAYER" "$CONTENT"' \
	"$OUTPUT/card/bird/run-content.sh" || \
	fail 'content runner does not use the fixed MPV player'
grep -q "RESUME='save-position-on-quit=yes'" \
	"$OUTPUT/card/bird/run-content.sh" || fail 'MPV resume policy missing'
grep -q "RESUME_OPTIONS='watch-later-options=start'" \
	"$OUTPUT/card/bird/run-content.sh" || fail 'MPV position-only resume policy missing'
grep -q "s#/mnt/mmc/MUOS/PortMaster#/storage/roms/ports/PortMaster#g" \
	"$OUTPUT/card/bird/run-content.sh" || fail 'legacy PortMaster path translation missing'
grep -q 'ExecStart=/flash/bird/fixed-storage.sh' \
	"$OUTPUT/card/bird/rocknix-automount.service" || fail 'fixed storage unit missing'
grep -q '^DefaultDependencies=no$' \
	"$OUTPUT/card/bird/essway.service" || fail 'early Bird ordering missing'
grep -q '^After=rocknix-automount.service graphical.target$' \
	"$OUTPUT/card/bird/essway.service" || fail 'stable supervisor boundary missing'
grep -q '^ExecStartPre=/flash/bird/first-frame-prep.sh$' \
	"$OUTPUT/card/bird/essway.service" || \
	fail 'immutable first-frame preparation path missing'
grep -q '^Wants=.*essway.service' \
	"$OUTPUT/card/bird/rocknix.target" || fail 'early Bird target request missing'
grep -q '^BindPaths=/dev/null:/dev/console$' \
	"$OUTPUT/card/bird/rocknix-autostart.service" || fail 'autostart console isolation missing'
grep -q 'exec /flash/bird/bird-autostart' \
	"$OUTPUT/card/bird/rocknix-autostart.service" || fail 'fixed autostart coordinator missing'
grep -q '^BIRD_AUTOSTART_REVISION=bird-fixed-autostart-v2$' \
	"$OUTPUT/card/bird/bird-autostart" || fail 'fixed autostart revision missing'
grep -q '\$FLASH_ROOT/bird-fixed-gpu-overclock.sh' \
	"$OUTPUT/card/bird/bird-autostart" || \
	fail 'fixed H700 GPU policy missing'
grep -q 'common/050-audio' "$OUTPUT/card/bird/bird-autostart" || \
	fail 'fixed audio preparation missing'
grep -q '\$FLASH_ROOT/999-export' "$OUTPUT/card/bird/bird-autostart" || \
	fail 'application milestone coordinator step missing'
if grep -Eq 'autostart/(common|quirks)/\[\*\]|(^|[^[:alnum:]_])date([^[:alnum:]_]|$)|tocon|systemctl' \
	"$OUTPUT/card/bird/bird-autostart"; then
	fail 'generic autostart discovery or helper remained'
fi
grep -q '^ConditionPathExists=/run/bird/network-request$' \
	"$OUTPUT/card/bird/NetworkManager.service" || fail 'NetworkManager gate missing'
grep -q '^ConditionPathExists=/run/bird/network-request$' \
	"$OUTPUT/card/bird/systemd-resolved.service" || fail 'resolver gate missing'
grep -q '^ConditionPathExists=/run/bird/network-request$' \
	"$OUTPUT/card/bird/systemd-timesyncd.service" || fail 'time sync gate missing'
grep -q '^ConditionPathExists=/run/bird/network-request$' \
	"$OUTPUT/card/bird/systemd-rfkill.service" || fail 'rfkill gate missing'
grep -q 'systemd-resolved.service systemd-timesyncd.service' \
	"$OUTPUT/card/bird/bird-network.sh" || fail 'network release missing'
grep -q 'systemd-rfkill.service' \
	"$OUTPUT/card/bird/bird-network.sh" || fail 'rfkill release missing'
grep -q '/usr/bin/nm-online -q --timeout=10' \
	"$OUTPUT/card/bird/bird-network.sh" || fail 'network readiness join missing'
grep -q '/usr/bin/nmcli -w 30 connection up' \
	"$OUTPUT/card/bird/bird-network.sh" || fail 'saved Wi-Fi activation missing'
grep -q 'device wifi rescan' \
	"$OUTPUT/card/bird/bird-network.sh" || fail 'Wi-Fi scan barrier missing'
grep -q 'systemd-rfkill.socket' \
	"$OUTPUT/card/mount-storage.sh" || fail 'rfkill activation socket remained'
grep -q '^After=rocknix-autostart.service$' \
	"$OUTPUT/card/bird/rocknix-report-stats.service" || fail 'event-ordered snapshot missing'
grep -Fq 'ConditionPathExists=|/storage/bird-data/Bird/boot-diagnostics.request' \
	"$OUTPUT/card/bird/rocknix-report-stats.service" || \
	fail 'ordinary-boot snapshot gate missing'
grep -Fq 'ConditionPathExists=|/storage/bird-data/Bird/stage5-idle-window.request' \
	"$OUTPUT/card/bird/rocknix-report-stats.service" || \
	fail 'Stage 5 snapshot gate missing'
grep -q '^Type=simple$' \
	"$OUTPUT/card/bird/rocknix-report-stats.service" || fail 'nonblocking snapshot missing'
grep -q '^RuntimeMaxSec=120s$' \
	"$OUTPUT/card/bird/rocknix-report-stats.service" || fail 'bounded snapshot runtime missing'
grep -q '^ExecStart=/flash/bird/capture-requested-diagnostics.sh$' \
	"$OUTPUT/card/bird/rocknix-report-stats.service" || \
	fail 'immutable diagnostic dispatcher missing'
grep -q 'timeout 2s pactl info' \
	"$OUTPUT/card/bird/capture-boot-state.sh" || fail 'bounded audio diagnostic missing'
grep -q 'stock-root-boot-state-\$BOOT_ID.log' \
	"$OUTPUT/card/bird/capture-boot-state.sh" || \
	fail 'boot-scoped snapshot publication missing'
grep -Fq 'STAGE5_CAPTURE=${BIRD_STAGE5_CAPTURE:-/flash/bird/capture-stage5-window.sh}' \
	"$OUTPUT/card/bird/capture-requested-diagnostics.sh" || \
	fail 'standalone Stage 5 acquisition missing'
grep -Fq 'BOOT_CAPTURE=${BIRD_BOOT_DIAGNOSTICS_CAPTURE:-/flash/bird/capture-boot-state.sh}' \
	"$OUTPUT/card/bird/capture-requested-diagnostics.sh" || \
	fail 'broad snapshot dispatch missing'
grep -Fq '"$COUNTERS" start' \
	"$OUTPUT/card/bird/capture-stage5-window.sh" || \
	fail 'Stage 5 idle start sample missing'
grep -Fq '"$COUNTERS" end' \
	"$OUTPUT/card/bird/capture-stage5-window.sh" || \
	fail 'Stage 5 idle end sample missing'
if grep -q 'stage5-idle-window.request' \
	"$OUTPUT/card/bird/capture-boot-state.sh"; then
	fail 'broad snapshot still owns the Stage 5 window'
fi
grep -Fq 'bird_stage5_window_version=2 mode=%s' \
	"$OUTPUT/card/bird/capture-stage5-window-counters.sh" || \
	fail 'Stage 5 window counter revision missing'
grep -Fq 'bird_stage5_snapshot_version=1 label=%s' \
	"$OUTPUT/card/bird/capture-stage5-state.sh" || \
	fail 'Stage 5 snapshot revision missing'
grep -q "^  LINUX /bird-releases/$RELEASE_ID/KERNEL$" \
	"$OUTPUT/card/extlinux/extlinux.conf" || fail 'versioned KERNEL selector missing'
grep -q "^  INITRD /bird-releases/$RELEASE_ID/bird-initramfs.cpio.gz$" \
	"$OUTPUT/card/extlinux/extlinux.conf" || fail 'versioned early initramfs selector missing'
grep -q "^  FDT /bird-releases/$RELEASE_ID/dtb.img$" \
	"$OUTPUT/card/extlinux/extlinux.conf" || fail 'versioned DTB selector missing'
grep -Fq "bird_release=$RELEASE_ID" \
	"$OUTPUT/card/extlinux/extlinux.conf" || fail 'release identity missing from kernel command line'
if grep -Fq 'console=ttyS0,115200' \
		"$OUTPUT/card/extlinux/extlinux.conf"; then
	fail 'production selector unexpectedly enables the diagnostic serial console'
fi
[ "$(awk '{ for (field = 1; field <= NF; field++) if ($field == "fbcon=map:1") { count++; if ($1 == "APPEND") append++ } } END { print (count + 0) ":" (append + 0) }' \
	"$OUTPUT/card/extlinux/extlinux.conf")" = 1:1 ] || \
	fail 'active selector must map fbcon away from the fixed panel exactly once'
[ "$(awk '{ for (field = 1; field <= NF; field++) if ($field == "vt.global_cursor_default=0") { count++; if ($1 == "APPEND") append++ } } END { print (count + 0) ":" (append + 0) }' \
	"$OUTPUT/card/extlinux/extlinux.conf")" = 1:1 ] || \
	fail 'active selector must disable the VT cursor exactly once'
if grep -Eq 'KERNEL\.fallback|extlinux\.fallback|BIRD_LOADER_(SELECTOR|KERNEL|DTB)_SHA|reboot -f' \
		"$OUTPUT/build/early-initramfs/payload/bird-release-loader.sh"; then
	fail 'alternate-boot machinery remained in release loader'
fi
grep -Fq 'bird_loader_record_failure "$1"' \
	"$OUTPUT/build/early-initramfs/payload/bird-release-loader.sh" || \
	fail 'durable boot-failure recording missing from release loader'
grep -Fq '"$BIRD_LOADER_BUSYBOX" stat -Lt "$1"' \
	"$OUTPUT/build/early-initramfs/payload/bird-release-loader.sh" || \
	fail 'release loader does not use the pinned ROCKNIX BusyBox stat contract'
grep -Fq 'stat -Lt ' "$OFFICIAL_INIT" || \
	fail 'pinned ROCKNIX init no longer proves the selected BusyBox stat contract'
grep -Fq 'bird_loader_bytes "$1"' "$OUTPUT/card/post-flash.sh" || \
	fail 'post-flash runtime verifier does not reuse the release-loader byte contract'
if grep -Fq "stat -c" "$OUTPUT/card/post-flash.sh"; then
	fail 'host-only GNU stat syntax leaked into the initramfs post-flash hook'
fi
grep -Fq 'if ! . /bird-release-loader.sh; then' \
	"$OUTPUT/build/early-initramfs/payload/init" || fail 'versioned release loader missing'
grep -Fq 'while :; do sleep 3600; done' \
	"$OUTPUT/build/early-initramfs/payload/init" || fail 'release-loader fatal boundary missing'
if grep -q '/flash/post-flash.sh' "$OUTPUT/build/early-initramfs/payload/init"; then
	fail 'top-level mutable boot hook remained in versioned init'
fi
if grep -Eq 'boot-attempt|write_attempts|fallback_boot|extlinux\.fallback' \
		"$OUTPUT/card/post-flash.sh"; then
	fail 'boot retry or fallback machinery remained in post-flash'
fi
grep -Fq '$BUSYBOX kill -0 "$PID"' \
	"$OUTPUT/build/early-initramfs/payload/bird-early.sh" || \
	fail 'persistent early owner validation missing'
grep -Fq '[ -s "$STORAGE_MARKER" ]' \
	"$OUTPUT/build/early-initramfs/payload/bird-early.sh" || \
	fail 'storage anchor readiness barrier missing'
grep -Fq "printf '%s\\n' ready >&4" \
	"$OUTPUT/build/early-initramfs/payload/bird-early.sh" || \
	fail 'explicit storage readiness signal missing'
if grep -Eq 'final-root storage signalled|storage anchor acknowledged|persistent-owner uptime|log_leds root-ready|log_leds handoff([[:space:]]|$)' \
	"$OUTPUT/build/early-initramfs/payload/bird-early.sh"; then
	fail 'normal-success early diagnostics remained'
fi
grep -q 'final-root timeout retired' \
	"$OUTPUT/build/early-initramfs/payload/bird-early.sh" || \
	fail 'failed early launcher retirement missing'
grep -q '/sysroot/storage/bird-data' \
	"$ROOT/launcher/bird-launcher.c" || \
	fail 'post-prepare_sysroot storage path missing'
grep -Fq 'mount --move /birddata /run/bird-data' \
	"$OUTPUT/card/mount-storage.sh" || \
	fail 'acyclic real data mount missing'
grep -Fq 'mount --bind /run/bird-data /storage/bird-data' \
	"$OUTPUT/card/mount-storage.sh" || \
	fail 'published data bind missing'
if grep -Eq '^mount --move /birddata /storage(/|[[:space:]])' \
	"$OUTPUT/card/mount-storage.sh"; then
	fail 'real data mount moved beneath its loop-backed filesystem'
fi
if grep -Eq '^[[:space:]]*chmod[[:space:]]' \
	"$OUTPUT/card/mount-storage.sh"; then
	fail 'mount-storage depends on unavailable initramfs chmod'
fi
if grep -Fq '/sysroot/usr/bin/busybox chmod 0755' \
	"$OUTPUT/card/mount-storage.sh"; then
	fail 'immutable executable publication transaction remained'
fi
grep -Fq '/sysroot/usr/bin/busybox chmod 0644' \
	"$OUTPUT/card/mount-storage.sh" || \
	fail 'SYSTEM BusyBox data-mode transaction missing'
grep -Fq 'cp -f /flash/bird/bird-swap.conf /storage/.config/swap.conf' \
	"$OUTPUT/card/mount-storage.sh" || \
	fail 'mutable ROCKNIX memory policy publication missing'
if grep -Fq '"/storage/bird-data/Bird/state/$FILE"' \
	"$OUTPUT/card/mount-storage.sh"; then
	fail 'immutable final-root publication remained'
fi
grep -Fq 'if [ "${BOOT_STEP}" = "mount_storage" ]; then' \
	"$OUTPUT/build/early-initramfs/payload/init" || \
	fail 'mount-storage failure boundary missing'
grep -Fq 'status=failed step=mount_storage' \
	"$OUTPUT/build/early-initramfs/payload/init" || \
	fail 'mount-storage failure evidence missing'
grep -Fq 'mount-storage-latest.log' \
	"$OUTPUT/build/early-initramfs/payload/init" || \
	fail 'mount-storage failure log path missing'
grep -Fq '/usr/bin/busybox mount --move /run /sysroot/run' \
	"$OUTPUT/build/early-initramfs/payload/init" || \
	fail 'final-root /run mount-tree handoff missing'
grep -q 'mknod -m 0600.*STORAGE_SIGNAL.* p' \
	"$OUTPUT/build/early-initramfs/payload/bird-early.sh" || \
	fail 'supported FIFO creation applet missing'
if grep -q '^/bird-early.sh resume$' \
	"$OUTPUT/build/early-initramfs/payload/init"; then
	fail 'obsolete chroot bridge remained'
fi
grep -q 'power_supply/battery/status' \
	"$ROOT/launcher/bird-launcher.c" || fail 'battery indicator missing'
grep -q 'pidfd_open' \
	"$ROOT/launcher/bird-pidwait.c" || fail 'pidfd waiter missing'
grep -q 'power supplies' \
	"$OUTPUT/card/bird/capture-boot-state.sh" || fail 'power snapshot missing'
grep -q 'mount --bind "$ROM_SOURCE" "$ROM_TARGET"' \
	"$OUTPUT/card/bird/fixed-storage.sh" || fail 'fixed ROM bind missing'
grep -q 'application-contract-ready' \
	"$OUTPUT/card/bird/999-export" || fail 'application milestone missing'
grep -q '^CONTRACT_REVISION=bird-application-v1$' \
	"$OUTPUT/card/bird/999-export" || fail 'application contract revision missing'
grep -q '^PLATFORM_STAGE=/run/bird/fixed-platform$' \
	"$OUTPUT/card/bird/999-export" || fail 'fixed platform readiness input missing'
grep -q '^SWAY_STAGE=/run/bird/fixed-sway$' \
	"$OUTPUT/card/bird/999-export" || fail 'fixed Sway readiness input missing'
grep -Fq 'cmp -s "$PLATFORM_STAGE/$PROFILE_NAME" "$PROFILE_DIR/$PROFILE_NAME"' \
	"$OUTPUT/card/bird/999-export" || fail 'fixed platform readiness validation missing'
grep -Fq 'cmp -s "$SWAY_STAGE/config" "$SWAY_CONFIG"' \
	"$OUTPUT/card/bird/999-export" || fail 'fixed Sway config validation missing'
grep -Fq 'cmp -s "$SWAY_STAGE/095-sway" "$SWAY_PROFILE"' \
	"$OUTPUT/card/bird/999-export" || fail 'fixed Sway profile validation missing'
grep -Fq 'mv -f "$READY_TMP" "$READY"' \
	"$OUTPUT/card/bird/999-export" || fail 'atomic application marker publication missing'
grep -q '\$FLASH_ROOT/999-export' \
	"$OUTPUT/card/bird/bird-autostart" || fail 'application milestone step missing'
grep -q 'wait_application_contract' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'early selection queue missing'
grep -q '^APPLICATION_CONTRACT_REVISION=bird-application-v1$' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'dispatcher application revision missing'
grep -q 'contract_revision=$APPLICATION_CONTRACT_REVISION' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'dispatcher revision validation missing'
grep -Fq 'wait_application_contract && . /etc/profile; then' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'post-contract profile refresh missing'
grep -q 'ExecStart=/flash/bird/supervisor.sh' \
	"$OUTPUT/card/bird/essway.service" || fail 'Bird UI unit missing'
grep -Fq 'LAUNCHER=/flash/bird/bird-launcher' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'immutable final-root launcher path missing'
grep -Fq 'RUNNER=/flash/bird/run-content.sh' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'immutable content dispatcher path missing'
grep -Fq 'PIDWAIT=/flash/bird/bird-pidwait' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'immutable supervisor waiter path missing'
grep -Fq 'EXPECTED='\''UI_SERVICE="essway.service"'\''' \
	"$OUTPUT/card/bird/090-ui_service" || fail 'boot compositor deferral missing'
grep -Fq '[ "$FIRST" = "$EXPECTED" ]' \
	"$OUTPUT/card/bird/090-ui_service" || fail 'UI profile idempotency missing'
grep -q '^JobTimeoutAction=reboot-force$' \
	"$OUTPUT/card/bird/rocknix.target" || fail 'target watchdog missing'
grep -q 'queue_game_launch' \
	"$ROOT/launcher/bird-launcher.c" || fail 'pre-storage selection queue missing'
grep -q '^Wants=.*input.service.*powerstate.service' \
	"$OUTPUT/card/bird/rocknix.target" || fail 'fixed control/power target requests missing'
grep -q 'ExecStart=/flash/bird/bird-fixed-controls$' \
	"$OUTPUT/card/bird/bird-fixed-controls.service" || fail 'fixed controls unit missing'
grep -q 'ExecStart=/flash/bird/bird-powerstate$' \
	"$OUTPUT/card/bird/bird-powerstate.service" || fail 'fixed powerstate unit missing'
grep -q '^After=local-fs.target$' \
	"$OUTPUT/card/bird/bird-powerstate.service" || fail 'fixed powerstate ordering changed'
if grep -Eq '^(After|Before|Wants|Requires)=.*essway\.service' \
	"$OUTPUT/card/bird/bird-powerstate.service"; then
	fail 'fixed powerstate recreates the graphical target ordering cycle'
fi
grep -q '/flash/bird/bird-fixed-controls.service' \
	"$OUTPUT/card/mount-storage.sh" || fail 'stock input replacement missing'
grep -q '/flash/bird/bird-powerstate.service' \
	"$OUTPUT/card/mount-storage.sh" || fail 'stock powerstate replacement missing'
grep -Fq '!state->select_held || !state->start_held' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'Bird exit chord missing'
grep -Fq '#define EMERGENCY_HELPER "/flash/bird/bird-emergency-recover.sh"' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'Bird emergency helper path missing'
grep -Fq 'state->menu_held' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'Bird emergency chord missing'
grep -Fq 'restart --no-block essway.service' \
	"$OUTPUT/card/bird/bird-emergency-recover.sh" || fail 'Bird emergency UI restart missing'
grep -Fq '#define VOLUME_PROGRAM "/flash/bird/bird-volume.sh"' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'unmuting volume wrapper missing'
grep -Fq '#define OSD_PROGRAM "/flash/bird/bird-control-osd.sh"' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'immutable control OSD path missing'
grep -Fq '#define EXIT_HELPER "/flash/bird/bird-fixed-control-exit.sh"' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'immutable control exit path missing'
grep -Fq 'set-sink-mute @DEFAULT_SINK@ 0' \
	"$OUTPUT/card/bird/bird-volume.sh" || fail 'default audio sink unmute missing'
grep -Fq "iface=CARD,name='Headphone Jack'" \
	"$OUTPUT/card/bird/bird-volume.sh" || fail 'headphone route inspection missing'
grep -Fq "cset \"name='Speaker Switch'\"" \
	"$OUTPUT/card/bird/bird-volume.sh" || fail 'speaker route reconciliation missing'
grep -Fq 'pactl get-sink-volume @DEFAULT_SINK@' \
	"$OUTPUT/card/bird/bird-volume.sh" || fail 'no-op audio volume inspection missing'
grep -Fq 'must never prevent a game' \
	"$OUTPUT/card/bird/bird-volume.sh" || fail 'nonfatal audio policy contract missing'
if grep -Fq 'suspend-sink' "$OUTPUT/card/bird/bird-volume.sh"; then
	fail 'rejected codec prewake remains in audio policy'
fi
if grep -Fq 'bird-volume.sh' "$OUTPUT/card/bird/999-export"; then
	fail 'application contract still performs an unnecessary audio restore'
fi
grep -Fq '/flash/bird/bird-volume.sh restore' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'per-launch audio policy missing'
grep -Fq 'PORT_PREP=/flash/bird/prepare-ports.sh' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'immutable PortMaster preparation path missing'
grep -Fq 'NETWORK=/flash/bird/bird-network.sh' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'immutable network helper path missing'
grep -Fq "bird-content-guard /flash/bird/bird-pidwait" \
	"$OUTPUT/card/bird/run-content.sh" || fail 'immutable content guard waiter path missing'
grep -Fq '/flash/bird/bird-fixed-control-exit.sh "$NETWORK"' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'immutable guard exit path missing'
grep -Fq 'pactl get-sink-mute @DEFAULT_SINK@' \
	"$OUTPUT/card/bird/capture-boot-state.sh" || fail 'effective audio mute diagnostic missing'
grep -Fq 'h700_input ? BTN_NORTH : BUTTON_Y' \
	"$ROOT/launcher/bird-launcher.c" || fail 'physical Y favorite mapping missing'
grep -Fq 'input_watch_fd = open_fixed_input_watch();' \
	"$ROOT/launcher/bird-launcher.c" || fail 'watch-before-scan input discovery missing'
grep -Fq 'event->mask & IN_Q_OVERFLOW' \
	"$ROOT/launcher/bird-launcher.c" || fail 'input discovery overflow recovery missing'
grep -Fq 'try_fixed_input_index(index)' \
	"$ROOT/launcher/bird-launcher.c" || fail 'created input node validation missing'
grep -Fq 'h700_input_contract_matches(input_fd)' \
	"$ROOT/launcher/bird-launcher.c" || fail 'complete H700 input validation missing'
grep -Fq 'BIRD_DEVICE_INPUT_FF_BITMAP_WORDS' \
	"$ROOT/launcher/bird-launcher.c" || fail 'fixed H700 force-feedback closure missing'
grep -q 'sys_pipe2(handshake, O_CLOEXEC)' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'control exec handshake missing'
grep -q 'SPAWN_EXEC_FAILED' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'control exec failure state missing'
grep -q 'poll-failed-recovering' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'control poll recovery missing'
grep -q '^static u64 recover_poll_failure' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'bounded control poll recovery missing'
grep -Fq 'watch_fd = open_input_watch();' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'control watch-before-scan discovery missing'
grep -Fq 'process_input_watch(watch_fd, sources)' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'control creation-edge discovery missing'
grep -Fq 'poll_timeout(sources, &state, &suspend,' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'control polling fallback is not inotify-scoped'
grep -Fq 'h700_input_contract_matches((int)fd)' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'fixed controls H700 contract validation missing'
grep -Fq '#define POWER_SUSPEND_ACTIVE "/var/run/power-fake-suspend-active.flag"' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'power resume transaction detection missing'
grep -Fq 'complete_resume_state(suspend)' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'persistent suspend completion coordinator missing'
grep -Fq 'O_WRONLY | O_CREAT | O_APPEND | O_DSYNC | O_CLOEXEC' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'durable suspend trace missing'
grep -Fq ': >"$RESUME_READY"' \
	"$ROOT/kernel/rocknix/stock-root/bird-suspend.sh" || fail 'resume transaction completion marker missing'
for ACTION in volume suspend content-exit; do
	grep -q "$ACTION-exec-failed" \
		"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || \
		fail "control $ACTION exec failure diagnostic missing"
done
if grep -q 'BTN_TL' "$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c"; then
	fail 'obsolete L1 exit requirement remained'
fi
grep -q 'SESSION_PID=/run/bird/content-session.pid' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'managed content root missing'
grep -Fq '/usr/bin/systemd-run --quiet --scope --collect' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'systemd content scope boundary missing'
[ "$(grep -c -- '--expand-environment=no' \
	"$OUTPUT/card/bird/run-content.sh")" -eq 2 ] || \
	fail 'systemd command argument preservation missing'
grep -q 'boundary=systemd-scope' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'content scope metadata contract missing'
grep -q 'InvocationID' "$OUTPUT/card/bird/run-content.sh" || \
	fail 'content scope invocation identity missing'
grep -q '^scope_activity_status()' "$OUTPUT/card/bird/run-content.sh" || \
	fail 'content scope tri-state activity query missing'
grep -Fq 'usleep 250000' "$OUTPUT/card/bird/run-content.sh" || \
	fail 'content scope query backoff missing'
if grep -Eq '^[[:space:]]*systemctl start --wait' \
	"$OUTPUT/card/bird/run-content.sh"; then
	fail 'nonjoining systemctl start --wait returned'
fi
grep -q -- '--kill-whom=all' "$OUTPUT/card/bird/run-content.sh" || \
	fail 'content scope all-process termination missing'
grep -q 'bird-content-guard-' "$OUTPUT/card/bird/run-content.sh" || \
	fail 'content cleanup guard boundary missing'
grep -q 'InvocationID' "$OUTPUT/card/bird/bird-fixed-control-exit.sh" || \
	fail 'global exit scope identity validation missing'
grep -q '^parse_metadata_snapshot()' \
	"$OUTPUT/card/bird/bird-fixed-control-exit.sh" || fail 'single-generation exit metadata parser missing'
grep -Fq 'METADATA_CAPTURE=$(cat "$SESSION_PID"' \
	"$OUTPUT/card/bird/bird-fixed-control-exit.sh" || fail 'single-open exit metadata snapshot missing'
grep -Fq '__BIRD_METADATA_EOF__")' \
	"$OUTPUT/card/bird/bird-fixed-control-exit.sh" || fail 'exit metadata newline validation missing'
if grep -Eq '^(VERSION|BOUNDARY|RECORDED_STATE|RECORDED_SESSION_TOKEN|RECORDED_BOOT_ID|UNIT|INVOCATION|CONTROL_GROUP)=\$\(metadata_value' \
	"$OUTPUT/card/bird/bird-fixed-control-exit.sh"; then
	fail 'multi-open exit metadata load returned'
fi
grep -q -- '--kill-whom=all' "$OUTPUT/card/bird/bird-fixed-control-exit.sh" || \
	fail 'global exit all-process termination missing'
if grep -q 'pgrep' "$OUTPUT/card/bird/run-content.sh" \
	"$OUTPUT/card/bird/bird-fixed-control-exit.sh"; then
	fail 'snapshot PID-tree content termination returned'
fi
grep -q 'retroarch fmsx' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'fixed MSX provider missing'
grep -q '^#define BIRD_DEVICE_INPUT_SCAN_COUNT 32U$' \
	"$ROOT/launcher/bird-device-contract.h" || fail 'complete fixed input search missing'
grep -q '^CATALOG_PATH_MAX_BYTES = 4095$' \
	"$ROOT/generate-launcher-catalog.py" || fail 'catalogue path size contract missing'
grep -Fq 'byte < 0x20 or byte == 0x7F' \
	"$ROOT/generate-launcher-catalog.py" || fail 'generator path control-byte rejection missing'
grep -q '^#define CATALOG_PATH_MAX_BYTES 4095U$' \
	"$ROOT/launcher/catalog.generated.h" || fail 'generated catalogue path contract missing'
grep -Fq 'byte < 32U || byte == 127U' \
	"$ROOT/launcher/bird-launcher.c" || fail 'launcher path control-byte rejection missing'
grep -Fq 'result=blocked reason=load-incomplete' \
	"$ROOT/launcher/bird-launcher.c" || fail 'incomplete favorites save gate missing'
grep -q '^static void schedule_favorites_retry' \
	"$ROOT/launcher/bird-launcher.c" || fail 'favorites read retry missing'
grep -q '^static int classify_poll_result' \
	"$ROOT/launcher/bird-launcher.c" || fail 'launcher poll error classification missing'
grep -q '^static u64 recover_poll_delay' \
	"$ROOT/launcher/bird-launcher.c" || fail 'launcher poll backoff missing'
grep -q '^static void reset_input_latches' \
	"$ROOT/launcher/bird-launcher.c" || fail 'launcher reconnect latch reset missing'
grep -q '^static int reconnect_input' \
	"$ROOT/launcher/bird-launcher.c" || fail 'launcher reconnect helper missing'
[ "$(grep -c '^[[:space:]]*abandon_input();' \
	"$ROOT/launcher/bird-launcher.c")" -eq 1 ] || fail 'launcher reconnect helper must abandon prior input state once'
grep -Fq 'reconnect_input("poll-descriptor")' \
	"$ROOT/launcher/bird-launcher.c" || fail 'poll-descriptor reconnect path missing'
grep -Fq 'reconnect_input("drain-terminal")' \
	"$ROOT/launcher/bird-launcher.c" || fail 'drain-terminal reconnect path missing'
grep -q '#define EVENT_SCAN_COUNT 32' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'complete global input search missing'
grep -q -- '-DPERSIST_UI_STATE' "$0" || fail 'launcher recovery state missing'
grep -q '^#define ACTION_RECOVER 1$' \
	"$ROOT/launcher/bird-launcher.c" || fail 'launcher recover action missing'
grep -Fq 'exit_action == ACTION_RECOVER)' \
	"$ROOT/launcher/bird-launcher.c" || fail 'launcher recover return contract missing'
grep -q '^#define ACTION_RELOAD 13$' \
	"$ROOT/launcher/bird-launcher.c" || fail 'launcher reload action missing'
grep -Fq '13) consume_handoff_action ;;' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'supervisor reload handoff missing'
grep -Fq 'bird launcher user-requested reload' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'supervisor reload result missing'
grep -q '^#define ACTION_REBOOT 14$' \
	"$ROOT/launcher/bird-launcher.c" || fail 'launcher reboot action missing'
grep -Fq '14) consume_handoff_action && request_reboot ;;' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'supervisor reboot handoff missing'
grep -Fq 'static const char *play_item[2] = {"SYSTEMS", "FAVORITES"};' \
	"$ROOT/launcher/bird-launcher.c" || fail 'Play hierarchy changed'
grep -Fq 'static const char *tools_item[1] = {"PORTMASTER"};' \
	"$ROOT/launcher/bird-launcher.c" || fail 'Tools hierarchy changed'
grep -Fq 'static const char *quit_item[3] = {"RELOAD", "REBOOT", "SHUTDOWN"};' \
	"$ROOT/launcher/bird-launcher.c" || fail 'Quit hierarchy changed'
grep -Fq 'start_portmaster_network start' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'direct PortMaster network session missing'
grep -Fq 'export PYTHONPYCACHEPREFIX="$PORTMASTER_PYCACHE"' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'PortMaster Python cache isolation missing'
grep -Fq 'export PYTHONDONTWRITEBYTECODE=1' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'PortMaster Python bytecode-write isolation missing'
[ "$(grep -Fc 'prepare_portmaster_python_cache || return 1' \
	"$OUTPUT/card/bird/run-content.sh")" -eq 3 ] || \
	fail 'PortMaster Python isolation does not cover every provider execution path'
grep -Fq 'run_managed env XCOMPOSEFILE=/dev/null /usr/bin/start_portmaster.sh' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'direct PortMaster provider missing'
if grep -Eq -- '--rocknix|start_es[.]sh|start-interactive|stock_rocknix_diagnostics|write_shareable_stock_diagnostics' \
	"$OUTPUT/card/bird/supervisor.sh" "$OUTPUT/card/bird/run-content.sh"; then
	fail 'temporary stock frontend path returned'
fi
grep -q 'SUSPEND_PROGRAM "/flash/bird/bird-suspend.sh"' \
	"$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c" || fail 'fixed suspend wrapper missing'
grep -q 'brightness_raw_target(75, 2499, -1) == 25' \
	"$ROOT/kernel/rocknix/tests/fixed-controls-host.c" || fail 'stable one-percent brightness test missing'
grep -Fq 'STRIKE=$(((MAXIMUM * 10 + 50) / 100))' \
	"$OUTPUT/card/bird/bird-suspend.sh" || fail 'measured ten-percent wake strike missing'
grep -Fq '"$SETTLE" 50000' \
	"$OUTPUT/card/bird/bird-suspend.sh" || fail 'bounded wake strike missing'
grep -q 'bird-pre-suspend-brightness' \
	"$OUTPUT/card/bird/bird-suspend.sh" || fail 'suspend brightness preservation missing'
grep -q 'suspend-latest.log' \
	"$OUTPUT/card/bird/bird-suspend.sh" || fail 'suspend brightness evidence missing'
grep -Fq 'STRIKE=$(((MAX * 10 + 50) / 100))' \
	"$OUTPUT/build/early-initramfs/payload/bird-early.sh" || \
	fail 'early measured ten-percent wake strike missing'
grep -Fq '$BUSYBOX usleep 50000' \
	"$OUTPUT/build/early-initramfs/payload/bird-early.sh" || \
	fail 'early bounded wake strike missing'
grep -Fq 'systemctl stop --no-block sway.service' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'nonblocking Sway stop missing'
grep -Fq '"$TIMEOUT_PROGRAM" --signal=TERM --kill-after=1s 3s' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'bounded systemd client wrapper missing'
grep -q 'NETLINK_KOBJECT_UEVENT' \
	"$ROOT/launcher/bird-powerstate.c" || fail 'event-driven power source missing'
grep -q '^KSM_ENABLE="disable"$' \
	"$OUTPUT/card/bird/bird-swap.conf" || fail 'fixed KSM policy missing'
grep -q '/flash/bird/bird-swap.conf' \
	"$OUTPUT/card/mount-storage.sh" || fail 'fixed memory policy install missing'
grep -q 'brightness_write=none' \
	"$OUTPUT/card/bird/first-frame-prep.sh" || fail 'brightness ownership missing'
grep -Fq "[ \"\$PANEL_FIRST\" = 'DEVICE_HAS_DUAL_SCREEN=false' ]" \
	"$OUTPUT/card/bird/999-export" || fail 'fixed panel profile missing'
grep -Fq '[ "$PANEL_READY" -ne 1 ]' \
	"$OUTPUT/card/bird/999-export" || fail 'fixed panel profile idempotency missing'
if grep -q '/usr/lib/autostart' "$OUTPUT/card/mount-storage.sh"; then
	fail 'autostart bind replacement remained'
fi
grep -q '\$FLASH_ROOT/bird-fixed-sway.sh' \
	"$OUTPUT/card/bird/bird-autostart" || fail 'fixed Sway step missing'
grep -q '\$FLASH_ROOT/bird-fixed-platform.sh' \
	"$OUTPUT/card/bird/bird-autostart" || fail 'fixed H700 step missing'
grep -q '\$FLASH_ROOT/bird-fixed-logging.sh' \
	"$OUTPUT/card/bird/bird-autostart" || fail 'fixed logging step missing'
grep -q '\$FLASH_ROOT/bird-fixed-pico8.sh' \
	"$OUTPUT/card/bird/bird-autostart" || fail 'fixed Pico-8 step missing'
grep -q '\$FLASH_ROOT/bird-fixed-controller.sh' \
	"$OUTPUT/card/bird/bird-autostart" || fail 'fixed controller step missing'
grep -q '\$FLASH_ROOT/bird-fixed-setup.sh' \
	"$OUTPUT/card/bird/bird-autostart" || fail 'fixed setup step missing'
if grep -q 'common/003-logging\|common/010-pico8\|common/001-controller\|common/001-setup\|start[.]games' \
	"$OUTPUT/card/bird/bird-autostart"; then
	fail 'write-heavy generic fixed-profile setup remained active'
fi
for FIXED_POLICY in bird-fixed-performance.sh bird-fixed-gpu-overclock.sh \
	bird-fixed-rumble.sh bird-fixed-turbo.sh; do
	grep -q "\\\$FLASH_ROOT/$FIXED_POLICY" \
		"$OUTPUT/card/bird/bird-autostart" || \
		fail "fixed device policy missing: $FIXED_POLICY"
done
if grep -q 'common/008-perfmode\|common/020-rumble\|common/095-turbo-mode\|400-set_gpu_overclock\|get_setting system.cpugovernor' \
	"$OUTPUT/card/bird/bird-autostart"; then
	fail 'generic performance or rumble policy remained active'
fi
grep -q '^Storage=volatile$' "$OUTPUT/card/bird/bird-journald.conf" || \
	fail 'explicit volatile journal policy missing'
grep -q 'systemd-journal-flush.service' \
	"$OUTPUT/card/mount-storage.sh" || fail 'journal flush mask missing'
grep -q 'systemd-journal-catalog-update.service' \
	"$OUTPUT/card/mount-storage.sh" || fail 'journal catalog mask missing'
grep -q 'systemd-logind.service' \
	"$OUTPUT/card/mount-storage.sh" || fail 'unused logind mask missing'
grep -q 'systemd-tmpfiles-clean.timer' \
	"$OUTPUT/card/mount-storage.sh" || fail 'tmpfiles wakeup mask missing'
grep -q 'systemd-update-utmp.service' \
	"$OUTPUT/card/mount-storage.sh" || fail 'volatile UTMP boot mask missing'
grep -q 'systemd-update-utmp-runlevel.service' \
	"$OUTPUT/card/mount-storage.sh" || fail 'volatile UTMP runlevel mask missing'
grep -Fq 'systemctl start seatd.service' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'explicit seat provider join missing'
grep -Fq 'print "system.suspendmode=" mode' \
	"$OUTPUT/card/mount-storage.sh" || fail 'pre-systemd fake-suspend mode enforcement missing'
grep -Fq '/flash/bird/bird-suspend-policy.generated.sh' \
	"$OUTPUT/card/mount-storage.sh" || fail 'generated suspend policy is not consumed'
grep -Fq '$FLASH_ROOT/bird-restore-suspend-policy.sh' \
	"$OUTPUT/card/bird/bird-autostart" || \
	fail 'post-recovery suspend policy step missing'
grep -Fq '/usr/bin/suspendmode' \
	"$OUTPUT/card/bird/bird-restore-suspend-policy.sh" || \
	fail 'fixed suspendmode transaction missing'
if grep -Fq '030-suspend_mode' "$OUTPUT/card/mount-storage.sh" \
	"$OUTPUT/card/bird/bird-autostart"; then
	fail 'late H700 suspend writer remained active'
fi
grep -Fxq 'AllowSuspend=no' \
	"$OUTPUT/card/bird/bird-sleep.conf" || fail 'kernel suspend disable policy missing'
if [ -e "$OUTPUT/card/bird/bird-logind.conf" ]; then
	fail 'unused logind runtime policy remained in release'
fi
grep -Fxq 'BIRD_SUSPEND_PROVIDER_MODE=off' \
	"$OUTPUT/card/bird/bird-suspend-policy.generated.sh" || \
	fail 'generated fake-suspend provider policy missing'
grep -q 'DEVICE_TEMP_SENSOR=.*thermal_zone2/temp' \
	"$OUTPUT/card/bird/bird-fixed-platform.sh" || fail 'fixed thermal profile missing'
if grep -q '001-sync-modules' "$OUTPUT/card/mount-storage.sh" \
	"$OUTPUT/card/bird/bird-autostart"; then
	fail 'immutable module sync remained active'
fi
grep -q 'XCOMPOSEFILE=/dev/null' \
	"$OUTPUT/card/bird/run-content.sh" || fail 'English PortMaster policy missing'
grep -q -- '--- audio graph ---' \
	"$OUTPUT/card/bird/capture-boot-state.sh" || fail 'audio audit missing'
grep -q '^WLR_DRM_DEVICES=/dev/dri/card1$' \
	"$OUTPUT/card/bird/bird-fixed-sway.sh" || fail 'fixed DRM card missing'
grep -q '^WLR_CON=DSI-1$' \
	"$OUTPUT/card/bird/bird-fixed-sway.sh" || fail 'fixed panel connector missing'
if grep -q 'output_monitor\|DP-1\|HDMI' \
	"$OUTPUT/card/bird/bird-fixed-sway.sh"; then
	fail 'unused external-display path remained in fixed Sway profile'
fi
grep -q '/flash/bird/bird-save-config.service' \
	"$OUTPUT/card/mount-storage.sh" || fail 'fixed shutdown checkpoint missing'
if grep -q '/flash/bird/bird-poweroff.target' \
	"$OUTPUT/card/mount-storage.sh"; then
	fail 'shutdown timeout target returned'
fi
grep -q 'set -C' "$OUTPUT/card/bird/bird-save-config.sh" || \
	fail 'shutdown exclusive temporary creation missing'
grep -Fq 'while [ "$TEMP_SUFFIX" -lt 32 ]; do' \
	"$OUTPUT/card/bird/bird-save-config.sh" || fail 'bounded shutdown temp suffix search missing'
grep -Fq 'cmp -s "$SOURCE" "$TEMP"' \
	"$OUTPUT/card/bird/bird-save-config.sh" || fail 'shutdown byte verification missing'
grep -Fq 'sync "$TEMP"' \
	"$OUTPUT/card/bird/bird-save-config.sh" || fail 'shutdown data flush missing'
grep -Fq 'mv -f -- "$TEMP" "$BACKUP"' \
	"$OUTPUT/card/bird/bird-save-config.sh" || fail 'shutdown atomic checkpoint missing'
if grep -E 'cp .*\$BACKUP' "$OUTPUT/card/bird/bird-save-config.sh"; then
	fail 'shutdown direct backup overwrite returned'
fi
grep -q 'systemctl --no-block start poweroff.target' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'ordered poweroff target request missing'
grep -q 'systemctl --no-block start reboot.target' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'ordered reboot target request missing'
if grep -Eq 'systemctl --no-block (poweroff|reboot)$' \
	"$OUTPUT/card/bird/supervisor.sh"; then
	fail 'logind-routed systemctl verb returned'
fi
grep -Fq '/usr/bin/timeout --signal=TERM --kill-after=1s 3s' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'bounded poweroff client missing'
if grep -q 'systemctl .*--force.*poweroff' \
	"$OUTPUT/card/bird/supervisor.sh"; then
	fail 'forced poweroff bypass returned'
fi
grep -q '^TimeoutStartSec=15s$' \
	"$OUTPUT/card/bird/bird-save-config.service" || fail 'bounded shutdown checkpoint missing'
grep -q '^ExecStart=/flash/bird/bird-save-config.sh$' \
	"$OUTPUT/card/bird/bird-save-config.service" || \
	fail 'immutable shutdown checkpoint path missing'
grep -q 'for PROPERTY in run pages_to_scan' \
	"$OUTPUT/card/bird/capture-boot-state.sh" || fail 'KSM diagnostic missing'
grep -q '^#define LOW_PERCENT 41$' \
	"$ROOT/launcher/bird-powerstate.c" || fail 'fixed low-battery threshold missing'
grep -Fq 'if (STORAGE_READY_SIGNAL[0] && !storage_handoff_signaled) return;' \
	"$ROOT/launcher/bird-launcher.c" || fail 'pre-signal storage gate missing'
grep -Fq 'storage_probe_attempted = 1;' \
	"$ROOT/launcher/bird-launcher.c" || fail 'one-shot storage acquisition missing'
grep -Fq 'for ((check = 0; check < 1000; check++)); do' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'bounded launcher health race missing'
grep -Fq 'if launcher_exited "$pid"; then' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'immediate launcher-exit check missing'
if grep -Fq '"$PIDWAIT" "$pid" &' "$OUTPUT/card/bird/supervisor.sh"; then
	fail 'cancellable background pidwait race returned'
fi
if grep -Eq 'ATTEMPTS|boot-attempt|reset_boot_attempts' \
		"$OUTPUT/card/bird/supervisor.sh"; then
	fail 'boot-attempt state remained in supervisor'
fi
grep -Fq 'bird launcher startup failure reason=%s result=%s; stopping' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'launcher startup failure stop missing'
if grep -Eq 'systemctl reboot --force|startup_backoff|runtime_backoff' \
		"$OUTPUT/card/bird/supervisor.sh"; then
	fail 'automatic launcher restart/reboot recovery remained in supervisor'
fi
grep -Fq 'read_completed_handoff_action || return 0' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'completed early action validation missing'
grep -Fq 'accept_completed_early_action || return 1' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'pre-dispatch boot-health transaction missing'
grep -Fq 'if ! service_handoff_action; then' \
	"$OUTPUT/card/bird/supervisor.sh" || fail 'failed early health retry gate missing'

# Recovery keeps one complete native XRGB base outside the launcher binary.
# Validate the exact budgeted file after every copy and generated file so the
# canonical manifest cannot admit a late or unverified image.
validate_final_launcher_static_assets

# This is the only deploy inventory.  It records every regular candidate file
# with its intended Unix mode, size and digest, plus every pinned external byte
# stream used by the build or first deployment.  The updater derives preflight,
# staging and installed-release verification from these file records.
verify_source_identity
MANIFEST=$OUTPUT/deploy-manifest.tsv
MANIFEST_TEMP=$OUTPUT/.deploy-manifest.tsv.new
FILE_LIST=$OUTPUT/build/deploy-files.list
EMPTY_DIR_LIST=$OUTPUT/build/deploy-empty-dirs.list
if find "$OUTPUT/card" ! -type f ! -type d -print | grep -q .; then
	fail 'candidate contains a symlink or special node'
fi
(
	cd "$OUTPUT/card"
	find . -type f -print | sed 's#^\./##' | sort >"$FILE_LIST"
	find . -mindepth 1 -type d -empty -print | sed 's#^\./##' | \
		sort >"$EMPTY_DIR_LIST"
)
{
	printf 'schema\tbird-deploy-v1\n'
	printf 'release\t%s\n' "$RELEASE_ID"
	printf 'target-mode-policy\tfat-capability\n'
	printf 'source-commit\t%s\t%s\n' "$SOURCE_COMMIT" "$SOURCE_STATE"
	printf 'artifact\tdevice-contract\t%s\t%s\n' \
		'bird/bird-device-contract.tsv' "$DEVICE_CONTRACT_SHA"
	printf 'artifact\tcatalog\t%s\t%s\n' \
		'launcher/catalog.generated.h' "$CATALOG_SHA"
	printf 'input\tKERNEL\t%s\t%s\t%s\t%s\n' \
		"$(file_mode "$SOURCE/KERNEL")" "$(file_bytes "$SOURCE/KERNEL")" \
		"$KERNEL_SHA" 'ROCKNIX-H700-20260701:KERNEL'
	printf 'input\tdtb.img\t%s\t%s\t%s\t%s\n' \
		"$(file_mode "$SOURCE/dtb.img")" "$(file_bytes "$SOURCE/dtb.img")" \
		"$DTB_SHA" 'ROCKNIX-H700-20260701:dtb.img'
	printf 'input\tROCKNIX-SYSTEM\t%s\t%s\t%s\t%s\n' \
		"$(file_mode "$SYSTEM_SOURCE")" "$(file_bytes "$SYSTEM_SOURCE")" \
		"$SYSTEM_SHA" 'ROCKNIX-H700-20260701:SYSTEM'
	printf 'input\tROCKNIX-STORAGE\t%s\t%s\t%s\t%s\n' \
		"$(file_mode "$STORAGE")" "$(file_bytes "$STORAGE")" \
		"$STORAGE_SHA" 'ROCKNIX-H700-20260701:STORAGE'
	printf 'input\tusr/bin/autostart\t%s\t%s\t%s\t%s\n' \
		"$(file_mode "$SYSTEM_TREE/usr/bin/autostart")" \
		"$(file_bytes "$SYSTEM_TREE/usr/bin/autostart")" "$AUTOSTART_SHA" \
		'ROCKNIX-SYSTEM:/usr/bin/autostart'
	printf 'input\tinitramfs/init\t%s\t%s\t%s\t%s\n' \
		"$(file_mode "$OFFICIAL_INIT")" "$(file_bytes "$OFFICIAL_INIT")" \
		"$OFFICIAL_INIT_SHA" 'ROCKNIX-initramfs:/init'
	printf 'input\trocknix-singleadc-joypad.ko\t%s\t%s\t%s\t%s\n' \
		"$(file_mode "$JOYPAD")" "$(file_bytes "$JOYPAD")" "$JOYPAD_SHA" \
		'ROCKNIX-SYSTEM:kernel-overlay/rocknix-singleadc-joypad.ko'
	printf 'input\tinitramfs/busybox\t%s\t%s\t%s\t%s\n' \
		"$(file_mode "$INIT_BUSYBOX")" "$(file_bytes "$INIT_BUSYBOX")" \
		"$INIT_BUSYBOX_SHA" 'ROCKNIX-initramfs:/usr/bin/busybox'
	printf 'input\tPortMaster.zip\t%s\t%s\t%s\t%s\n' \
		"$(file_mode "$PORTMASTER_ARCHIVE")" "$(file_bytes "$PORTMASTER_ARCHIVE")" \
		"$PORTMASTER_ARCHIVE_SHA" 'ROCKNIX-SYSTEM:/usr/config/PortMaster/release/PortMaster.zip'
	for PROVIDER_SPEC in \
		'pugwash:ROCKNIX-PortMaster.zip:/PortMaster/pugwash' \
		'PortMaster.sh:ROCKNIX-PortMaster.zip:/PortMaster/PortMaster.sh' \
		'mod_ROCKNIX.txt:ROCKNIX-PortMaster.zip:/PortMaster/mod_ROCKNIX.txt' \
		'funcs.txt:ROCKNIX-PortMaster.zip:/PortMaster/funcs.txt' \
		'harbourmaster:ROCKNIX-PortMaster.zip:/PortMaster/harbourmaster'; do
		PROVIDER_NAME=${PROVIDER_SPEC%%:*}
		PROVIDER_ORIGIN=${PROVIDER_SPEC#*:}
		PROVIDER_FILE=$PORTMASTER_INPUTS/$PROVIDER_NAME
		printf 'input\tPortMaster/%s\t%s\t%s\t%s\t%s\n' \
			"$PROVIDER_NAME" "$(file_mode "$PROVIDER_FILE")" \
			"$(file_bytes "$PROVIDER_FILE")" "$(sha256 "$PROVIDER_FILE")" \
			"$PROVIDER_ORIGIN"
	done
	while IFS= read -r RELATIVE; do
		case "$RELATIVE" in
			''|/*|*/../*|../*|*'/..'|*[!A-Za-z0-9._/-]*) fail "unsafe manifest path: $RELATIVE" ;;
		esac
		printf 'dir\t%s\t%s\n' "$RELATIVE" \
			"$(file_mode "$OUTPUT/card/$RELATIVE")"
	done <"$EMPTY_DIR_LIST"
	while IFS= read -r RELATIVE; do
		case "$RELATIVE" in
			''|/*|*/../*|../*|*'/..'|*[!A-Za-z0-9._/-]*) fail "unsafe manifest path: $RELATIVE" ;;
		esac
		FILE=$OUTPUT/card/$RELATIVE
		printf 'file\t%s\t%s\t%s\t%s\n' "$RELATIVE" \
			"$(file_mode "$FILE")" "$(file_bytes "$FILE")" "$(sha256 "$FILE")"
	done <"$FILE_LIST"
} >"$MANIFEST_TEMP"
mv -f "$MANIFEST_TEMP" "$MANIFEST"

printf 'Built exact ROCKNIX compatibility baseline: %s\n' "$OUTPUT"
printf 'KERNEL remains byte-identical to release 20260701: %s\n' "$KERNEL_SHA"
printf 'Bird launcher: %s\n' "$(sha256 "$OUTPUT/card/bird/bird-launcher")"
printf 'Early overlay: %s\n' "$(sha256 "$OUTPUT/card/bird-initramfs.cpio.gz")"
printf 'Canonical deploy manifest: %s (%s)\n' "$MANIFEST" "$(sha256 "$MANIFEST")"
