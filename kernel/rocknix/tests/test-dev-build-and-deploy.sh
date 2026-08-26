#!/bin/sh
# Host-only transaction tests for the mutable dev-current workflow. Every
# repository, card volume, build fixture, and selector lives below one private
# temporary directory; this script never addresses a mounted physical card.

set -eu

if [ "$(uname -s)" != Darwin ]; then
	printf '%s\n' 'dev build/deploy tests skipped: macOS host required'
	exit 0
fi

SOURCE_ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-dev-deploy-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
TEMPLATE=$TMP/template-repository
CASE_NUMBER=0
PASS_COUNT=0

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

pass() {
	PASS_COUNT=$((PASS_COUNT + 1))
	printf 'ok %s - %s\n' "$PASS_COUNT" "$1"
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

tree_digest() {
	python3 - "$1" <<'PY'
import hashlib
import os
import pathlib
import stat
import sys

root = pathlib.Path(sys.argv[1])
digest = hashlib.sha256()
if root.exists() or root.is_symlink():
    for path in sorted([root, *root.rglob("*")], key=lambda item: item.as_posix()):
        info = path.lstat()
        relative = "." if path == root else path.relative_to(root).as_posix()
        if stat.S_ISREG(info.st_mode):
            kind = "file"
            value = hashlib.sha256(path.read_bytes()).hexdigest()
        elif stat.S_ISDIR(info.st_mode):
            kind = "dir"
            value = "-"
        elif stat.S_ISLNK(info.st_mode):
            kind = "symlink"
            value = os.readlink(path)
        else:
            kind = "special"
            value = "-"
        digest.update(f"{relative}\0{kind}\0{stat.S_IMODE(info.st_mode):o}\0{info.st_size}\0{value}\n".encode())
print(digest.hexdigest())
PY
}

make_initramfs() {
	OUTPUT_PATH=$1
	RELEASE_ID=$2
	LAUNCHER_PAYLOAD=$3
	python3 - "$OUTPUT_PATH" "$RELEASE_ID" "$LAUNCHER_PAYLOAD" <<'PY'
import gzip
import pathlib
import sys

output = pathlib.Path(sys.argv[1])
release = sys.argv[2]
launcher = sys.argv[3].encode()

def entry(name: str, payload: bytes, inode: int) -> bytes:
    encoded = name.encode() + b"\0"
    values = (
        inode, 0o100755, 0, 0, 1, 0, len(payload),
        0, 0, 0, 0, len(encoded), 0,
    )
    header = b"070701" + b"".join(f"{value:08x}".encode() for value in values)
    result = header + encoded
    result += b"\0" * ((-len(result)) & 3)
    result += payload
    result += b"\0" * ((-len(result)) & 3)
    return result

archive = b"".join(
    (
        entry("bird-release-loader.sh", f"#!/bin/sh\nBIRD_LOADER_RELEASE={release}\n".encode(), 1),
        entry("opt/bird/bird-launcher", launcher, 2),
        entry("TRAILER!!!", b"", 3),
    )
)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(gzip.compress(archive, compresslevel=9, mtime=0))
PY
}

copy_source() {
	SOURCE_PATH=$SOURCE_ROOT/$1
	TARGET_PATH=$TEMPLATE/$1
	[ -e "$SOURCE_PATH" ] || fail "template source is missing: $1"
	mkdir -p "${TARGET_PATH%/*}"
	cp -p "$SOURCE_PATH" "$TARGET_PATH"
}

mkdir -p "$TEMPLATE/kernel/rocknix" "$TEMPLATE/firmware" "$TEMPLATE/launcher"
for SOURCE_PATH in \
	dev-build-and-deploy.sh \
	DEV_WORKFLOW.md \
	bird-device-contract.tsv \
	generate-device-contract.py \
	generate-launcher-catalog.py \
	generate-launcher-catalog.sh \
	launcher/bird-launcher.c \
	launcher/bird-input-tester.c \
	launcher/bird-pidwait.c \
	launcher/bird-powerstate.c \
	launcher/bird-device-contract.h \
	launcher/catalog.generated.h \
	launcher/library.inventory.tsv \
	launcher/catalog.revision \
	firmware/mac-stock-root-card-identity.sh \
	firmware/mac-bird-card-lock.sh \
	firmware/mac-install-bird-uboot.sh \
	firmware/normalize-newc.py \
	firmware/generate-launcher-bootlogo.py \
	firmware/assets/bird-launcher-backdrop.png \
	kernel/rocknix/dev-release-tool.py \
	kernel/rocknix/build-bird-local-binary.sh \
	kernel/rocknix/build-uboot-status-led.sh \
	kernel/rocknix/build-uboot-no-heap-clear.sh \
	kernel/rocknix/build-uboot-fast-init.sh \
	kernel/rocknix/build-uboot-inplace-handoff.sh \
	kernel/rocknix/build-uboot-bootstage-fdt.sh \
	kernel/rocknix/build-lz4-kernel-candidate.sh \
	kernel/rocknix/build-stock-root-compat.sh \
	kernel/rocknix/build-stock-root-early-initramfs.sh \
	kernel/rocknix/inventory-bird-boot-volume.py \
	kernel/rocknix/patch-fit-root-timestamp.py \
	kernel/rocknix/transform-uboot-direct-extlinux.py \
	kernel/rocknix/transform-uboot-fast-init.py \
	kernel/rocknix/transform-uboot-inplace-handoff.py \
	kernel/rocknix/transform-uboot-lz4-kernel.py \
	kernel/rocknix/transform-uboot-no-heap-clear.py \
	kernel/rocknix/transform-uboot-bootstage-fdt.py \
	kernel/rocknix/transform-uboot-environment-nowhere.py \
	kernel/rocknix/transform-uboot-early-led.py \
	kernel/rocknix/transform-uboot-status-led.py \
	kernel/rocknix/verify-selected-bird-release.py \
	kernel/rocknix/verify-uboot-direct-extlinux-build.py \
	kernel/rocknix/verify-uboot-early-led-build.py \
	kernel/rocknix/verify-uboot-environment-nowhere-build.py \
	kernel/rocknix/verify-uboot-install-authority.py \
	kernel/rocknix/verify-uboot-status-led-build.py \
	kernel/rocknix/verify-uboot-no-heap-clear-build.py \
	kernel/rocknix/verify-uboot-fast-init-build.py \
	kernel/rocknix/verify-uboot-inplace-handoff-build.py \
	kernel/rocknix/verify-uboot-bootstage-fdt-build.py \
	kernel/rocknix/verify-lz4-kernel-candidate.py \
	kernel/rocknix/verify-uboot-lz4-pair-build.py; do
	copy_source "$SOURCE_PATH"
done
mkdir -p "$TEMPLATE/kernel/rocknix/tests"
cp -p "$SOURCE_ROOT/kernel/rocknix/tests/test-bird-local-binary.sh" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-bird-boot-volume-inventory.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-dev-build-and-deploy.sh" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-fit-root-timestamp-patch.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-mac-install-bird-uboot.sh" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-direct-extlinux-transform.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-fast-init-transform.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-inplace-handoff-transform.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-lz4-kernel-transform.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-no-heap-clear-transform.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-bootstage-fdt-transform.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-no-heap-clear-build.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-fast-init-build.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-inplace-handoff-build.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-lz4-pair-build.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-bootstage-fdt-build.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-lz4-kernel-candidate.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-environment-nowhere-transform.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-early-led-transform.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-status-led-build.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-uboot-status-led-transform.py" \
	"$TEMPLATE/kernel/rocknix/tests/"
cp -R "$SOURCE_ROOT/kernel/rocknix/stock-root" "$TEMPLATE/kernel/rocknix/stock-root"
chmod 0755 "$TEMPLATE/dev-build-and-deploy.sh"
git -C "$TEMPLATE" init -q
git -C "$TEMPLATE" config user.name 'birdOS host test'
git -C "$TEMPLATE" config user.email 'bird-host-test@example.invalid'
git -C "$TEMPLATE" add -A
git -C "$TEMPLATE" commit -qm 'test: seed dev workflow fixture'

runtime_files() {
	PYTHONDONTWRITEBYTECODE=1 python3 - "$REPO/kernel/rocknix/dev-release-tool.py" <<'PY'
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("bird_dev_release_tool", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
for value in module.RUNTIME_FILES:
    print(value)
PY
}

write_device_info() {
	WHOLE=$1
	INFO=$2
	printf '%s\t%s\t%s\n' \
		"$BIRD" 'Part of Whole' "$WHOLE" \
		"$DATA" 'Part of Whole' "$WHOLE" \
		"/dev/$WHOLE" 'Device Location' External \
		"/dev/$WHOLE" 'Protocol' 'Secure Digital' \
		"/dev/$WHOLE" 'Removable Media' Removable \
		"/dev/$WHOLE" 'Disk Size' '512074186752 Bytes (512074186752 Bytes)' \
		"$BIRD" 'Device Identifier' "${WHOLE}s1" \
		"$BIRD" 'Partition Offset' '16777216 Bytes' \
		"$BIRD" 'Disk Size' '134217728 Bytes (134217728 Bytes)' \
		"$BIRD" 'Volume Read-Only' No \
		"$DATA" 'Device Identifier' "${WHOLE}s6" \
		"$DATA" 'Partition Offset' '8753512448 Bytes' \
		"$DATA" 'Disk Size' '503320672768 Bytes (503320672768 Bytes)' \
		"$DATA" 'Volume Read-Only' No \
		"/dev/${WHOLE}s5" 'Partition Offset' '163577856 Bytes' \
		"/dev/${WHOLE}s5" 'Disk Size' '8589934592 Bytes (8589934592 Bytes)' \
		>"$INFO"
}

write_manifest() {
	RELEASE_ID=$1
	RELEASE_ROOT=$BIRD/bird-releases/$RELEASE_ID
	MANIFEST=$RELEASE_ROOT/deploy-manifest.tsv
	{
		printf 'schema\tbird-deploy-v1\n'
		printf 'release\t%s\n' "$RELEASE_ID"
		printf 'target-mode-policy\tfat-capability\n'
		printf 'source-commit\t%s\tclean\n' "$(git -C "$REPO" rev-parse HEAD)"
		printf 'artifact\tdevice-contract\tbird/bird-device-contract.tsv\t%s\n' \
			"$(sha256 "$RELEASE_ROOT/bird/bird-device-contract.tsv")"
		printf 'artifact\tcatalog\tlauncher/catalog.generated.h\t%s\n' \
			"$(sha256 "$REPO/launcher/catalog.generated.h")"
		for INPUT in KERNEL PortMaster.zip \
			PortMaster/PortMaster.sh PortMaster/funcs.txt PortMaster/harbourmaster \
			PortMaster/mod_ROCKNIX.txt PortMaster/pugwash ROCKNIX-STORAGE \
			ROCKNIX-SYSTEM dtb.img initramfs/busybox initramfs/init \
			rocknix-singleadc-joypad.ko usr/bin/autostart; do
			case "$INPUT" in
				initramfs/init)
					INPUT_SHA=3473415af0cf5df44e70259c3392817b1df421a12a617ec083ec018ff51dbc48 ;;
				initramfs/busybox)
					INPUT_SHA=5ee3d20d8ea5fd9b3ba5109da80599eaf46a5a337d9e40d4c67d28eef44d5dc8 ;;
				rocknix-singleadc-joypad.ko)
					INPUT_SHA=a8ac6cacfa89672fa08dec7fa02179bb108a4a2303fd5c1eb5834f916089b79b ;;
				*) INPUT_SHA=1111111111111111111111111111111111111111111111111111111111111111 ;;
			esac
			printf 'input\t%s\t644\t1\t%s\ttest:%s\n' "$INPUT" \
				"$INPUT_SHA" "$INPUT"
		done
		find "$RELEASE_ROOT" -type f ! -name deploy-manifest.tsv ! -name .complete \
			-print | LC_ALL=C sort | while IFS= read -r FILE; do
			RELATIVE=${FILE#"$RELEASE_ROOT/"}
			printf 'file\t%s\t%s\t%s\t%s\n' "$RELATIVE" \
				"$(mode "$FILE")" "$(bytes "$FILE")" "$(sha256 "$FILE")"
		done
	} >"$MANIFEST"
	sha256 "$MANIFEST" >"$RELEASE_ROOT/.complete"
}

convert_manifest_to_source_parity() {
	MANIFEST=$BIRD/bird-releases/prod-a/deploy-manifest.tsv
	SOURCE_JOYPAD=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05
	SOURCE_AUTHORITY=74ea672573dd80f368314bdef6a9481b2af9cf54b321cfd6e165179cc3185ffc
	awk -F '\t' -v OFS='\t' -v joypad="$SOURCE_JOYPAD" -v authority="$SOURCE_AUTHORITY" '
		$1 == "input" && $2 == "rocknix-singleadc-joypad.ko" {
			$5 = joypad
			print
			print "input", "source-kernel-parity.tsv", "644", "1", authority, "test:source-parity"
			next
		}
		{ print }
	' "$MANIFEST" >"$MANIFEST.new"
	mv "$MANIFEST.new" "$MANIFEST"
	sha256 "$MANIFEST" >"$BIRD/bird-releases/prod-a/.complete"
}

convert_manifest_to_irq_buttons() {
	MANIFEST=$BIRD/bird-releases/prod-a/deploy-manifest.tsv
	SOURCE_JOYPAD=fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05
	SOURCE_AUTHORITY=0020d161b5a2be0d8393267c3eb96794a0c2d9f82e8df5e097932216fad9e45d
	awk -F '\t' -v OFS='\t' -v joypad="$SOURCE_JOYPAD" -v authority="$SOURCE_AUTHORITY" '
		$1 == "input" && $2 == "rocknix-singleadc-joypad.ko" {
			$5 = joypad
			print
			print "input", "source-kernel-irq-buttons.tsv", "644", "1", authority, "test:source-irq-buttons"
			next
		}
		{ print }
	' "$MANIFEST" >"$MANIFEST.new"
	mv "$MANIFEST.new" "$MANIFEST"
	sha256 "$MANIFEST" >"$BIRD/bird-releases/prod-a/.complete"
}

create_release() {
	RELEASE_ID=$1
	RELEASE_ROOT=$BIRD/bird-releases/$RELEASE_ID
	mkdir -p "$RELEASE_ROOT/bird" "$RELEASE_ROOT/extlinux"
	printf 'kernel %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/KERNEL"
	printf 'dtb %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/dtb.img"
	printf 'system %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/ROCKNIX-SYSTEM"
	printf 'storage %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/ROCKNIX-STORAGE"
	printf 'provider %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/provider.bin"
	printf '%s\n' \
		'LABEL BIRD' \
		"  LINUX /bird-releases/$RELEASE_ID/KERNEL" \
		"  INITRD /bird-releases/$RELEASE_ID/bird-initramfs.cpio.gz" \
		"  FDT /bird-releases/$RELEASE_ID/dtb.img" \
		"  APPEND bird_release=$RELEASE_ID" \
		>"$RELEASE_ROOT/extlinux/extlinux.conf"
	make_initramfs "$RELEASE_ROOT/bird-initramfs.cpio.gz" "$RELEASE_ID" "base launcher $RELEASE_ID"
	cp "$REPO/bird-device-contract.tsv" "$RELEASE_ROOT/bird/bird-device-contract.tsv"
	for NAME in $(runtime_files); do
		cp -p "$REPO/kernel/rocknix/stock-root/$NAME" "$RELEASE_ROOT/bird/$NAME"
	done
	# A production release contains its immutable release ID, while dev-current
	# is specialized from the canonical v6.23 source during a local update.
	python3 - "$RELEASE_ROOT/bird/supervisor.sh" "$RELEASE_ID" <<'PY'
import pathlib
import re
import sys
path = pathlib.Path(sys.argv[1])
text, count = re.subn(r"^RELEASE_ID=v6\.23$", f"RELEASE_ID={sys.argv[2]}", path.read_text(), flags=re.M)
assert count == 1
path.write_text(text)
PY
	cp -p "$REPO/kernel/rocknix/stock-root/post-flash.sh" "$RELEASE_ROOT/post-flash.sh"
	cp -p "$REPO/kernel/rocknix/stock-root/mount-storage.sh" "$RELEASE_ROOT/mount-storage.sh"
	for NAME in bird-launcher bird-input-tester bird-pidwait bird-powerstate bird-fixed-controls bird-mpv-controls; do
		printf '%s %s\n' "$NAME" "$RELEASE_ID" >"$RELEASE_ROOT/bird/$NAME"
		chmod 0755 "$RELEASE_ROOT/bird/$NAME"
	done
	printf 'frame contract %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/bird/boot-frame.contract"
	printf 'frame pixels %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/bird/launcher-base.xrgb"
	find "$RELEASE_ROOT" -type f -exec chmod 0644 {} +
	chmod 0755 "$RELEASE_ROOT/post-flash.sh" "$RELEASE_ROOT/mount-storage.sh" \
		"$RELEASE_ROOT/bird/bird-launcher" "$RELEASE_ROOT/bird/bird-pidwait" \
		"$RELEASE_ROOT/bird/bird-input-tester" \
		"$RELEASE_ROOT/bird/bird-powerstate" "$RELEASE_ROOT/bird/bird-fixed-controls" \
		"$RELEASE_ROOT/bird/bird-mpv-controls"
	for NAME in $(runtime_files); do
		[ -x "$REPO/kernel/rocknix/stock-root/$NAME" ] && chmod 0755 "$RELEASE_ROOT/bird/$NAME"
	done
	write_manifest "$RELEASE_ID"
}

create_build_fixture() {
	VERSION=${1:-one}
	mkdir -p "$BUILD_FIXTURE/bird"
	for NAME in bird-launcher bird-input-tester bird-pidwait bird-powerstate bird-fixed-controls bird-mpv-controls; do
		printf 'fixture %s %s\n' "$NAME" "$VERSION" >"$BUILD_FIXTURE/bird/$NAME"
	done
	printf 'fixture boot contract %s\n' "$VERSION" >"$BUILD_FIXTURE/bird/boot-frame.contract"
	printf 'fixture frame pixels %s\n' "$VERSION" >"$BUILD_FIXTURE/bird/launcher-base.xrgb"
	make_initramfs "$BUILD_FIXTURE/bird-initramfs.cpio.gz" dev-current "fixture early launcher $VERSION"
}

select_release() {
	cp "$BIRD/bird-releases/$1/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.conf"
}

new_case() {
	CASE_NUMBER=$((CASE_NUMBER + 1))
	CASE_NAME=$1
	CASE_ROOT=$TMP/case-$CASE_NUMBER-$CASE_NAME
	REPO=$CASE_ROOT/repository
	BIRD=$CASE_ROOT/Volumes/BIRD
	DATA=$CASE_ROOT/Volumes/BIRD-DATA
	BUILD_FIXTURE=$CASE_ROOT/build-fixture
	DEVICE_INFO=$CASE_ROOT/device-info.tsv
	WHOLE=birddev${CASE_NUMBER}$$
	git clone -q "$TEMPLATE" "$REPO"
	git -C "$REPO" config user.name 'birdOS host test'
	git -C "$REPO" config user.email 'bird-host-test@example.invalid'
	mkdir -p "$BIRD/bird-releases" "$BIRD/extlinux" \
		"$DATA/Bird/boot-state/releases/prod-a" "$DATA/ROMS" "$DATA/MEDIA" "$BUILD_FIXTURE"
	printf 'production attempts\n' >"$DATA/Bird/boot-state/releases/prod-a/attempts"
	printf 'top dtb\n' >"$BIRD/dtb.img"
	printf 'previous selector\n' >"$BIRD/extlinux/extlinux.previous.conf"
	create_build_fixture one
	create_release prod-a
	select_release prod-a
	write_device_info "$WHOLE" "$DEVICE_INFO"
	COMMAND=$REPO/dev-build-and-deploy.sh
	BASE_BEFORE=$(tree_digest "$BIRD/bird-releases/prod-a")
	PREVIOUS_SELECTOR_BEFORE=$(sha256 "$BIRD/extlinux/extlinux.previous.conf")
	TOP_DTB_BEFORE=$(sha256 "$BIRD/dtb.img")
	PRODUCTION_ATTEMPTS_BEFORE=$(sha256 "$DATA/Bird/boot-state/releases/prod-a/attempts")
}

run_dev() {
	BIRD_DEV_HOST_TEST_MODE=1 \
	BIRD="$BIRD" DATA="$DATA" BIRD_DEVICE_INFO="$DEVICE_INFO" \
	BIRD_DEV_TEST_BUILD_FIXTURE="$BUILD_FIXTURE" \
		"$COMMAND" "$@"
}

run_dev_failpoint() {
	FAILPOINT=$1
	shift
	BIRD_DEV_HOST_TEST_MODE=1 \
	BIRD="$BIRD" DATA="$DATA" BIRD_DEVICE_INFO="$DEVICE_INFO" \
	BIRD_DEV_TEST_BUILD_FIXTURE="$BUILD_FIXTURE" \
	BIRD_DEV_TEST_FAILPOINT="$FAILPOINT" \
		"$COMMAND" "$@"
}

assert_base_and_fallback_unchanged() {
	[ "$(tree_digest "$BIRD/bird-releases/prod-a")" = "$BASE_BEFORE" ] || \
		fail "$CASE_NAME changed the base production release"
	[ "$(sha256 "$BIRD/extlinux/extlinux.previous.conf")" = "$PREVIOUS_SELECTOR_BEFORE" ] || \
		fail "$CASE_NAME changed extlinux.previous.conf"
	[ "$(sha256 "$BIRD/dtb.img")" = "$TOP_DTB_BEFORE" ] || \
		fail "$CASE_NAME changed top-level fallback DTB"
	[ "$(sha256 "$DATA/Bird/boot-state/releases/prod-a/attempts")" = "$PRODUCTION_ATTEMPTS_BEFORE" ] || \
		fail "$CASE_NAME reset production boot attempts"
}

initialize_dev() {
	run_dev --changed >"$CASE_ROOT/initialize.out" 2>"$CASE_ROOT/initialize.err" || {
		cat "$CASE_ROOT/initialize.err" >&2
		fail "$CASE_NAME could not initialize dev-current"
	}
}

selector_release() {
	sed -n 's/.*bird_release=\([A-Za-z0-9._-]*\).*/\1/p' "$BIRD/extlinux/extlinux.conf"
}

# 1. First --changed creates a complete mutable release and behaves as all-local.
new_case atomic-appledouble
mkdir "$CASE_ROOT/atomic"
printf 'stale metadata\n' >"$CASE_ROOT/atomic/._state.tsv"
python3 - "$REPO/kernel/rocknix/dev-release-tool.py" \
	"$CASE_ROOT/atomic/state.tsv" <<'PY'
import importlib.util
import pathlib
import sys

module_path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("bird_dev_release_tool", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
target = pathlib.Path(sys.argv[2])
module.atomic_write(target, b"published state\n")
assert target.read_bytes() == b"published state\n"
assert not target.with_name("._state.tsv").exists()
PY
pass 'atomic publication removes the matching FAT AppleDouble sidecar'

mkdir -p "$CASE_ROOT/selector/BIRD/extlinux" "$CASE_ROOT/selector/DATA"
printf 'already visible selector\n' \
	>"$CASE_ROOT/selector/BIRD/extlinux/extlinux.conf"
printf 'stale selector metadata\n' \
	>"$CASE_ROOT/selector/BIRD/extlinux/._extlinux.conf"
BIRD_DEV_HOST_TEST_MODE=1 python3 - \
	"$REPO/kernel/rocknix/dev-release-tool.py" \
	"$REPO" "$CASE_ROOT/selector/BIRD" "$CASE_ROOT/selector/DATA" <<'PY'
import argparse
import importlib.util
import pathlib
import sys

module_path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("bird_dev_release_tool", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
arguments = argparse.Namespace(
    root=pathlib.Path(sys.argv[2]),
    bird=pathlib.Path(sys.argv[3]),
    data=pathlib.Path(sys.argv[4]),
    mode="recover-production",
    profile=0,
    dry_run=0,
)
workflow = module.Workflow(arguments)
selector = workflow.selector_path.read_bytes()
barriers = []
module.fsync_directory = lambda path: barriers.append(path)
workflow.restore_selector(selector)
assert barriers == [workflow.selector_path.parent]
assert not workflow.selector_path.with_name("._extlinux.conf").exists()
assert workflow.selector_path.read_bytes() == selector
PY
pass 'selector recovery is durable even when retry bytes already match'

python3 - "$REPO/kernel/rocknix/dev-release-tool.py" <<'PY'
import importlib.util
import os
import pathlib
import sys

module_path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("bird_dev_release_tool", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
for name in module.CANONICAL_BUILD_TOOLS:
    os.environ.pop(name, None)
assert module.build_tool_configuration(False) == module.CANONICAL_BUILD_TOOLS
os.environ["CLANG"] = "/bin/sh"
try:
    module.reject_ambient_build_tool_overrides(False)
except module.DevError as error:
    assert "ambient compiler override is not permitted" in str(error)
else:
    raise AssertionError("real development accepted an ambient compiler override")
assert module.build_tool_configuration(False) == module.CANONICAL_BUILD_TOOLS
assert module.build_tool_configuration(True)["CLANG"] == "/bin/sh"
PY
pass 'real development pins canonical compiler tools while host fixtures remain overridable'

python3 - "$SOURCE_ROOT/kernel/rocknix/dev-release-tool.py" "$TMP/committed-history" <<'PY'
import importlib.util
import pathlib
import subprocess
import sys

module_path = pathlib.Path(sys.argv[1])
repository = pathlib.Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("bird_dev_release_tool", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
assert spec.loader is not None
spec.loader.exec_module(module)

def git(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repository), *args],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()

repository.mkdir()
git("init", "-q")
git("config", "user.name", "birdOS history test")
git("config", "user.email", "bird-history-test@example.invalid")
(repository / "production-tool.sh").write_text("original\n", encoding="utf-8")
(repository / "rename-old.txt").write_text("rename me\n", encoding="utf-8")
git("add", "-A")
git("commit", "-qm", "test: seed history")
base = git("rev-parse", "HEAD")
main_branch = git("branch", "--show-current")

(repository / "production-tool.sh").write_text("changed\n", encoding="utf-8")
git("add", "production-tool.sh")
git("commit", "-qm", "test: change production tool")
git("revert", "--no-edit", "HEAD")

git("checkout", "-qb", "rename-side")
git("mv", "rename-old.txt", "rename-new.txt")
git("commit", "-qm", "test: rename source")
git("checkout", "-q", main_branch)
(repository / "main-only.txt").write_text("main\n", encoding="utf-8")
git("add", "main-only.txt")
git("commit", "-qm", "test: main-side change")
git("merge", "--no-ff", "--no-commit", "rename-side")
(repository / "merge-only.txt").write_text("merge resolution\n", encoding="utf-8")
git("add", "merge-only.txt")
git("commit", "-qm", "test: merge with explicit resolution bytes")

paths = module.committed_paths_since(repository, base, git("rev-parse", "HEAD"))
expected = {
    "production-tool.sh",
    "rename-old.txt",
    "rename-new.txt",
    "main-only.txt",
    "merge-only.txt",
}
assert expected <= paths, (expected - paths, paths)
PY
pass 'committed history retains reverted, renamed, and merge-resolution paths'

python3 - "$SOURCE_ROOT/kernel/rocknix/dev-release-tool.py" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-canonical-namespace.sh" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-application-contract.sh" <<'PY'
import importlib.util
import pathlib
import sys

module_path, bash_test, sh_test = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("bird_dev_release_tool", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
assert spec.loader is not None
spec.loader.exec_module(module)
assert module.all_component_groups() == set(module.COMPONENT_HOST_TESTS)
assert len(module.BROAD_PRODUCT_HOST_TESTS) == 60
assert "test-dev-build-and-deploy.sh" in module.BROAD_PRODUCT_HOST_TESTS
assert module.COMPONENT_HOST_TESTS["runtime:capture-boot-state.sh"] == (
    "test-stock-root-unit-ordering.sh",
)
expected_host_only = {
    "firmware/mac-install-bird-uboot.sh": ("test-mac-install-bird-uboot.sh",),
    "kernel/rocknix/stock-root/capture-uboot-bootstage.sh": (
        "test-mac-install-bird-uboot.sh",
    ),
    "kernel/rocknix/build-uboot-status-led.sh": ("test-uboot-status-led-build.py",),
    "kernel/rocknix/build-uboot-no-heap-clear.sh": (
        "test-uboot-no-heap-clear-build.py",
    ),
    "kernel/rocknix/build-uboot-fast-init.sh": (
        "test-uboot-fast-init-build.py",
    ),
    "kernel/rocknix/build-uboot-inplace-handoff.sh": (
        "test-uboot-inplace-handoff-build.py",
    ),
    "kernel/rocknix/build-uboot-bootstage-fdt.sh": (
        "test-uboot-bootstage-fdt-build.py",
    ),
    "kernel/rocknix/build-lz4-kernel-candidate.sh": (
        "test-lz4-kernel-candidate.py",
    ),
    "kernel/rocknix/inventory-bird-boot-volume.py": (
        "test-bird-boot-volume-inventory.py",
        "test-mac-install-bird-uboot.sh",
    ),
    "kernel/rocknix/patch-fit-root-timestamp.py": (
        "test-fit-root-timestamp-patch.py",
    ),
    "kernel/rocknix/transform-uboot-direct-extlinux.py": (
        "test-uboot-direct-extlinux-transform.py",
    ),
    "kernel/rocknix/transform-uboot-fast-init.py": (
        "test-uboot-fast-init-transform.py",
    ),
    "kernel/rocknix/transform-uboot-inplace-handoff.py": (
        "test-uboot-inplace-handoff-transform.py",
    ),
    "kernel/rocknix/transform-uboot-lz4-kernel.py": (
        "test-uboot-lz4-kernel-transform.py",
    ),
    "kernel/rocknix/transform-uboot-no-heap-clear.py": (
        "test-uboot-no-heap-clear-transform.py",
    ),
    "kernel/rocknix/transform-uboot-bootstage-fdt.py": (
        "test-uboot-bootstage-fdt-transform.py",
    ),
    "kernel/rocknix/transform-uboot-environment-nowhere.py": (
        "test-uboot-environment-nowhere-transform.py",
    ),
    "kernel/rocknix/transform-uboot-early-led.py": (
        "test-uboot-early-led-transform.py",
    ),
    "kernel/rocknix/transform-uboot-status-led.py": (
        "test-uboot-status-led-transform.py",
    ),
    "kernel/rocknix/verify-selected-bird-release.py": ("test-mac-install-bird-uboot.sh",),
    "kernel/rocknix/verify-uboot-direct-extlinux-build.py": (
        "test-uboot-direct-extlinux-transform.py",
        "test-mac-install-bird-uboot.sh",
    ),
    "kernel/rocknix/verify-uboot-early-led-build.py": (
        "test-uboot-early-led-transform.py",
    ),
    "kernel/rocknix/verify-uboot-environment-nowhere-build.py": (
        "test-uboot-environment-nowhere-transform.py",
        "test-mac-install-bird-uboot.sh",
    ),
    "kernel/rocknix/verify-uboot-install-authority.py": ("test-mac-install-bird-uboot.sh",),
    "kernel/rocknix/verify-uboot-status-led-build.py": (
        "test-uboot-status-led-build.py",
        "test-mac-install-bird-uboot.sh",
    ),
    "kernel/rocknix/verify-uboot-no-heap-clear-build.py": (
        "test-uboot-no-heap-clear-build.py",
        "test-mac-install-bird-uboot.sh",
    ),
    "kernel/rocknix/verify-uboot-fast-init-build.py": (
        "test-uboot-fast-init-build.py",
        "test-mac-install-bird-uboot.sh",
    ),
    "kernel/rocknix/verify-uboot-inplace-handoff-build.py": (
        "test-uboot-inplace-handoff-build.py",
        "test-mac-install-bird-uboot.sh",
    ),
    "kernel/rocknix/verify-uboot-bootstage-fdt-build.py": (
        "test-uboot-bootstage-fdt-build.py",
    ),
    "kernel/rocknix/verify-lz4-kernel-candidate.py": (
        "test-lz4-kernel-candidate.py",
    ),
    "kernel/rocknix/verify-uboot-lz4-pair-build.py": (
        "test-uboot-lz4-pair-build.py",
        "test-mac-install-bird-uboot.sh",
    ),
}
assert module.HOST_ONLY_SOURCE_TESTS == expected_host_only
for source, tests in expected_host_only.items():
    assert module.classify_path(source) == ("host-only", set())
    assert set(tests) <= module.KNOWN_STANDALONE_HOST_TESTS
    assert not module.classify_path(source)[1]
assert module.host_test_command(bash_test)[:1] == ["/bin/bash"]
assert module.host_test_command(sh_test)[:1] == ["/bin/sh"]
PY
pass 'every component has a deterministic test map and test shebangs are preserved'

new_case first-changed
initialize_dev
[ "$(selector_release)" = dev-current ] || fail 'first invocation did not select dev-current'
grep -q '^activation[[:space:]]*complete$' "$BIRD/bird-dev/state.tsv"
grep -q '^schema[[:space:]]*bird-dev-state-v2$' "$BIRD/bird-dev/state.tsv"
grep -q '^last-build-kind[[:space:]]*changed$' "$BIRD/bird-dev/state.tsv"
grep -Eq '^all-local-source-inventory-sha256[[:space:]]*[0-9a-f]{64}$' \
	"$BIRD/bird-dev/state.tsv"
grep -Eq '^host-test-source-inventory-sha256[[:space:]]*[0-9a-f]{64}$' \
	"$BIRD/bird-dev/state.tsv"
grep -q '^host-test-set[[:space:]]*bird-dev-host-gate-v1$' "$BIRD/bird-dev/state.tsv"
grep -q '^Rebuilt groups: .*launcher' "$CASE_ROOT/initialize.out"
grep -q 'host fixture mapped test: test-bird-local-binary.sh' "$CASE_ROOT/initialize.out"
grep -q 'host fixture mapped test: test-stock-root-updater.sh' "$CASE_ROOT/initialize.out"
grep -q '^release[[:space:]]*dev-current$' "$BIRD/bird-releases/dev-current/deploy-manifest.tsv"
[ "$(cat "$BIRD/bird-releases/dev-current/.complete")" = \
	"$(sha256 "$BIRD/bird-releases/dev-current/deploy-manifest.tsv")" ] || fail 'dev completion marker is wrong'
grep -q '^RELEASE_ID=dev-current$' "$BIRD/bird-releases/dev-current/bird/supervisor.sh"
grep -q '^BIRD_SYSTEM_RELEASE=prod-a$' \
	"$BIRD/bird-releases/dev-current/post-flash.sh"
grep -Fq 'BIRD_SYSTEM_REL=Bird/runtime/$BIRD_SYSTEM_RELEASE/ROCKNIX-SYSTEM' \
	"$BIRD/bird-releases/dev-current/post-flash.sh"
gzip -dc "$BIRD/bird-releases/dev-current/bird-initramfs.cpio.gz" | \
	grep -a -q 'BIRD_LOADER_RELEASE=dev-current'
[ ! -e "$DATA/Bird/boot-state/releases/dev-current/attempts" ]
assert_base_and_fallback_unchanged
[ -z "$(find "$BIRD/bird-releases/dev-current" -name '._*' -print -quit)" ]
run_dev --status >"$CASE_ROOT/ready.status"
grep -q '^all-local-current[[:space:]]*yes$' "$CASE_ROOT/ready.status"
grep -q '^required-host-tests-current[[:space:]]*yes$' "$CASE_ROOT/ready.status"
grep -q '^ready-for-production-build[[:space:]]*yes$' "$CASE_ROOT/ready.status"
pass 'first changed invocation is all-local and produces a verified dev-current'

new_case catalog-metadata-ignore
mkdir -p "$DATA/ROMS/GBA" "$DATA/MEDIA/WATCH"
initialize_dev
DEV=$BIRD/bird-releases/dev-current
DEV_BEFORE=$(tree_digest "$DEV")
STATE_BEFORE=$(sha256 "$BIRD/bird-dev/state.tsv")
SELECTOR_BEFORE=$(sha256 "$BIRD/extlinux/extlinux.conf")
SELECTOR_INODE_BEFORE=$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")
mkdir -p "$DATA/ROMS/GBA/.hidden" "$DATA/ROMS/GBA/ImGs" \
	"$DATA/MEDIA/WATCH/IMAGES"
printf 'apple metadata\n' >"$DATA/ROMS/GBA/._Game.gba"
printf 'finder metadata\n' >"$DATA/ROMS/.DS_Store"
printf 'hidden game\n' >"$DATA/ROMS/GBA/.hidden/Secret.gba"
printf 'artwork bytes\n' >"$DATA/ROMS/GBA/ImGs/Cover.gba"
printf 'media artwork bytes\n' >"$DATA/MEDIA/WATCH/IMAGES/Poster.mp4"
mkdir -p "$DATA/ROMS/Ports/Test Game/conf/saves"
printf 'runtime save bytes\n' \
	>"$DATA/ROMS/Ports/Test Game/conf/saves/slot1.sav"
run_dev --status >"$CASE_ROOT/ignored.status"
grep -q '^changed-components[[:space:]]*-$' "$CASE_ROOT/ignored.status"
run_dev --changed >"$CASE_ROOT/ignored.out"
grep -q '^No supported payload component changed; card release was not rewritten or reactivated\.$' \
	"$CASE_ROOT/ignored.out"
[ "$(tree_digest "$DEV")" = "$DEV_BEFORE" ]
[ "$(sha256 "$BIRD/bird-dev/state.tsv")" = "$STATE_BEFORE" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$SELECTOR_BEFORE" ]
[ "$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")" = "$SELECTOR_INODE_BEFORE" ]
printf 'visible game\n' >"$DATA/ROMS/GBA/Visible.gba"
run_dev --status >"$CASE_ROOT/visible.status"
grep -q '^changed-components[[:space:]]*catalog$' "$CASE_ROOT/visible.status"
run_dev --changed >"$CASE_ROOT/visible.out"
grep -q '^Rebuilt groups: catalog, early-initramfs, launcher$' "$CASE_ROOT/visible.out"
assert_base_and_fallback_unchanged
pass 'catalog fingerprint ignores generator-excluded metadata, artwork and nested Port data only'

new_case cleanup-pending-readiness
initialize_dev
run_dev --status >"$CASE_ROOT/ready.status"
grep -q '^ready-for-production-build[[:space:]]*yes$' "$CASE_ROOT/ready.status"
printf 'interrupted publication\n' \
	>"$BIRD/.bird-dev-cleanup.tsv.dev-new.orphan"
run_dev --status >"$CASE_ROOT/publication.status"
grep -q '^cleanup-authority-pending[[:space:]]*no$' \
	"$CASE_ROOT/publication.status"
grep -q '^cleanup-publication-pending[[:space:]]*yes$' \
	"$CASE_ROOT/publication.status"
grep -q '^ready-for-production-build[[:space:]]*no$' \
	"$CASE_ROOT/publication.status"
rm "$BIRD/.bird-dev-cleanup.tsv.dev-new.orphan"
if run_dev_failpoint cleanup-after-authority-publication --clean \
		>"$CASE_ROOT/cleanup.out" 2>"$CASE_ROOT/cleanup.err"; then
	fail 'cleanup readiness setup did not publish its durable authority'
fi
run_dev --status >"$CASE_ROOT/authority.status"
grep -q '^cleanup-authority-pending[[:space:]]*yes$' \
	"$CASE_ROOT/authority.status"
grep -q '^cleanup-publication-pending[[:space:]]*no$' \
	"$CASE_ROOT/authority.status"
grep -q '^ready-for-production-build[[:space:]]*no$' \
	"$CASE_ROOT/authority.status"
run_dev --recover-production >"$CASE_ROOT/recover.out"
run_dev --clean-recovered >"$CASE_ROOT/clean-recovered.out"
assert_base_and_fallback_unchanged
pass 'status never reports production readiness while cleanup is pending'

new_case profile-status
run_dev --changed --profile >"$CASE_ROOT/profile-build.out"
run_dev --status --profile >"$CASE_ROOT/profile.status"
grep -q '^active-dev-profile[[:space:]]*profile$' "$CASE_ROOT/profile.status"
grep -q '^requested-target-profile[[:space:]]*profile$' "$CASE_ROOT/profile.status"
grep -q '^changed-components[[:space:]]*-$' "$CASE_ROOT/profile.status"
run_dev --status >"$CASE_ROOT/release-preview.status"
grep -q '^active-dev-profile[[:space:]]*profile$' "$CASE_ROOT/release-preview.status"
grep -q '^requested-target-profile[[:space:]]*release$' "$CASE_ROOT/release-preview.status"
grep -q '^changed-components[[:space:]].*launcher' "$CASE_ROOT/release-preview.status"
pass 'status distinguishes the active dev profile from the requested target profile'

# 2. A runtime-only edit changes no launcher/initramfs/kernel/DTB bytes.
new_case runtime-only
initialize_dev
DEV=$BIRD/bird-releases/dev-current
INITRAMFS_BEFORE=$(sha256 "$DEV/bird-initramfs.cpio.gz")
LAUNCHER_BEFORE=$(sha256 "$DEV/bird/bird-launcher")
KERNEL_BEFORE=$(sha256 "$DEV/KERNEL")
DTB_BEFORE=$(sha256 "$DEV/dtb.img")
RUNTIME_BEFORE=$(sha256 "$DEV/bird/bird-network.sh")
MANIFEST_BEFORE=$(sha256 "$DEV/deploy-manifest.tsv")
COMPLETE_BEFORE=$(sha256 "$DEV/.complete")
printf '\n# host runtime delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
run_dev --changed >"$CASE_ROOT/runtime.out"
grep -q '^Rebuilt groups: runtime:bird-network.sh$' "$CASE_ROOT/runtime.out"
grep -q 'host fixture mapped test: test-stock-root-content-scope.sh' "$CASE_ROOT/runtime.out"
if grep -q 'host fixture mapped test: test-stock-root-updater.sh' "$CASE_ROOT/runtime.out"; then
	fail 'focused runtime change ran the broad product host gate'
fi
[ "$(sha256 "$DEV/bird/bird-network.sh")" != "$RUNTIME_BEFORE" ]
[ "$(sha256 "$DEV/bird-initramfs.cpio.gz")" = "$INITRAMFS_BEFORE" ]
[ "$(sha256 "$DEV/bird/bird-launcher")" = "$LAUNCHER_BEFORE" ]
[ "$(sha256 "$DEV/KERNEL")" = "$KERNEL_BEFORE" ]
[ "$(sha256 "$DEV/dtb.img")" = "$DTB_BEFORE" ]
[ "$(sha256 "$DEV/deploy-manifest.tsv")" != "$MANIFEST_BEFORE" ]
[ "$(sha256 "$DEV/.complete")" != "$COMPLETE_BEFORE" ]
run_dev --status >"$CASE_ROOT/runtime.status"
grep -q '^all-local-current[[:space:]]*no$' "$CASE_ROOT/runtime.status"
grep -q '^required-host-tests-current[[:space:]]*no$' "$CASE_ROOT/runtime.status"
grep -q '^ready-for-production-build[[:space:]]*no$' "$CASE_ROOT/runtime.status"
assert_base_and_fallback_unchanged
pass 'runtime-only change preserves initramfs, launcher, kernel, and DTB'

run_dev --all-local >"$CASE_ROOT/all-local.out"
grep -q 'host fixture mapped test: test-application-contract.sh' "$CASE_ROOT/all-local.out"
grep -q 'host fixture mapped test: test-stock-root-updater.sh' "$CASE_ROOT/all-local.out"
run_dev --status >"$CASE_ROOT/all-local.status"
grep -q '^last-build-kind[[:space:]]*all-local$' "$CASE_ROOT/all-local.status"
grep -q '^all-local-current[[:space:]]*yes$' "$CASE_ROOT/all-local.status"
grep -q '^required-host-tests-current[[:space:]]*yes$' "$CASE_ROOT/all-local.status"
grep -q '^ready-for-production-build[[:space:]]*yes$' "$CASE_ROOT/all-local.status"
pass 'all-local runs the broad product gate and binds readiness to exact source'

# 3. Launcher source changes replace final launcher and external initramfs only.
new_case launcher-change
initialize_dev
DEV=$BIRD/bird-releases/dev-current
KERNEL_BEFORE=$(sha256 "$DEV/KERNEL")
DTB_BEFORE=$(sha256 "$DEV/dtb.img")
POWERSTATE_BEFORE=$(sha256 "$DEV/bird/bird-powerstate")
printf '\n/* host launcher delta */\n' >>"$REPO/launcher/bird-launcher.c"
create_build_fixture two
run_dev --changed >"$CASE_ROOT/launcher.out"
grep -q '^Rebuilt groups: early-initramfs, launcher$' "$CASE_ROOT/launcher.out"
grep -q 'fixture bird-launcher two' "$DEV/bird/bird-launcher"
gzip -dc "$DEV/bird-initramfs.cpio.gz" | grep -a -q 'fixture early launcher two'
[ "$(sha256 "$DEV/KERNEL")" = "$KERNEL_BEFORE" ]
[ "$(sha256 "$DEV/dtb.img")" = "$DTB_BEFORE" ]
[ "$(sha256 "$DEV/bird/bird-powerstate")" = "$POWERSTATE_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'launcher change rebuilds both launcher variants without kernel/DTB work'

# 4. One small helper source rebuilds only its manifest-listed helper binary.
new_case helper-only
initialize_dev
DEV=$BIRD/bird-releases/dev-current
LAUNCHER_BEFORE=$(sha256 "$DEV/bird/bird-launcher")
INITRAMFS_BEFORE=$(sha256 "$DEV/bird-initramfs.cpio.gz")
PIDWAIT_BEFORE=$(sha256 "$DEV/bird/bird-pidwait")
printf '\n/* host powerstate delta */\n' >>"$REPO/launcher/bird-powerstate.c"
printf 'fixture bird-powerstate two\n' >"$BUILD_FIXTURE/bird/bird-powerstate"
run_dev --changed >"$CASE_ROOT/helper.out"
grep -q '^Rebuilt groups: powerstate$' "$CASE_ROOT/helper.out"
grep -q 'fixture bird-powerstate two' "$DEV/bird/bird-powerstate"
[ "$(sha256 "$DEV/bird/bird-launcher")" = "$LAUNCHER_BEFORE" ]
[ "$(sha256 "$DEV/bird-initramfs.cpio.gz")" = "$INITRAMFS_BEFORE" ]
[ "$(sha256 "$DEV/bird/bird-pidwait")" = "$PIDWAIT_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'small-helper change has a one-binary payload boundary'

new_case input-tester-only
initialize_dev
DEV=$BIRD/bird-releases/dev-current
LAUNCHER_BEFORE=$(sha256 "$DEV/bird/bird-launcher")
INITRAMFS_BEFORE=$(sha256 "$DEV/bird-initramfs.cpio.gz")
FIXED_CONTROLS_BEFORE=$(sha256 "$DEV/bird/bird-fixed-controls")
printf '\n/* host input tester delta */\n' >>"$REPO/launcher/bird-input-tester.c"
printf 'fixture bird-input-tester two\n' >"$BUILD_FIXTURE/bird/bird-input-tester"
run_dev --changed >"$CASE_ROOT/input-tester.out"
grep -q '^Rebuilt groups: input-tester$' "$CASE_ROOT/input-tester.out"
grep -q 'fixture bird-input-tester two' "$DEV/bird/bird-input-tester"
[ "$(sha256 "$DEV/bird/bird-launcher")" = "$LAUNCHER_BEFORE" ]
[ "$(sha256 "$DEV/bird-initramfs.cpio.gz")" = "$INITRAMFS_BEFORE" ]
[ "$(sha256 "$DEV/bird/bird-fixed-controls")" = "$FIXED_CONTROLS_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'input tester changes retain a one-binary fast-development boundary'

new_case mapped-test-failure
initialize_dev
DEV_BEFORE=$(tree_digest "$BIRD/bird-releases/dev-current")
printf '\n# mapped test failure delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
if run_dev_failpoint before-product-host-tests --changed \
	>"$CASE_ROOT/mapped-fail.out" 2>"$CASE_ROOT/mapped-fail.err"; then
	fail 'mapped host-test failpoint did not fail'
fi
grep -q 'host-only injected failure: before-product-host-tests' "$CASE_ROOT/mapped-fail.err"
[ "$(selector_release)" = prod-a ]
[ "$(tree_digest "$BIRD/bird-releases/dev-current")" = "$DEV_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'behavior-test failure occurs before dev payload mutation and restores production'

# 5. Identical --changed is a true no-op, including the top-level selector.
new_case identical-noop
initialize_dev
CARD_BEFORE=$(tree_digest "$BIRD")
DATA_BEFORE=$(tree_digest "$DATA")
SELECTOR_INODE_BEFORE=$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")
run_dev --changed >"$CASE_ROOT/noop.out"
grep -q '^No supported payload component changed; card release was not rewritten or reactivated\.$' "$CASE_ROOT/noop.out"
[ "$(tree_digest "$BIRD")" = "$CARD_BEFORE" ]
[ "$(tree_digest "$DATA")" = "$DATA_BEFORE" ]
[ "$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")" = "$SELECTOR_INODE_BEFORE" ]
pass 'identical changed invocation performs no card write or reactivation'

# Documentation/test-only deltas run their host check without a card rewrite.
new_case host-only-change
initialize_dev
mkdir -p "$REPO/kernel/rocknix/tests"
printf '%s\n' '#!/bin/sh' 'set -eu' ': host-only syntax fixture' \
	>"$REPO/kernel/rocknix/tests/test-canonical-namespace.sh"
CARD_BEFORE=$(tree_digest "$BIRD")
SELECTOR_INODE_BEFORE=$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")
run_dev --changed >"$CASE_ROOT/host-only.out"
grep -q '^No supported payload component changed; card release was not rewritten or reactivated\.$' \
	"$CASE_ROOT/host-only.out"
grep -q 'host test: test-canonical-namespace.sh' "$CASE_ROOT/host-only.out"
[ "$(tree_digest "$BIRD")" = "$CARD_BEFORE" ]
[ "$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")" = "$SELECTOR_INODE_BEFORE" ]
pass 'test-only source changes run host checks without card writes'

new_case uboot-host-only-source-change
initialize_dev
CARD_BEFORE=$(tree_digest "$BIRD")
DATA_BEFORE=$(tree_digest "$DATA")
DEV_BEFORE=$(tree_digest "$BIRD/bird-releases/dev-current")
SELECTOR_INODE_BEFORE=$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")
printf '\n# host-only mapping fixture\n' \
	>>"$REPO/kernel/rocknix/inventory-bird-boot-volume.py"
run_dev --status >"$CASE_ROOT/uboot-host-only.status"
grep -q '^full-release-only-changes[[:space:]]*-$' \
	"$CASE_ROOT/uboot-host-only.status"
run_dev --changed >"$CASE_ROOT/uboot-host-only.out"
grep -q '^No supported payload component changed; card release was not rewritten or reactivated\.$' \
	"$CASE_ROOT/uboot-host-only.out"
grep -q 'host fixture mapped test: test-bird-boot-volume-inventory.py' \
	"$CASE_ROOT/uboot-host-only.out"
grep -q 'host fixture mapped test: test-mac-install-bird-uboot.sh' \
	"$CASE_ROOT/uboot-host-only.out"
[ "$(tree_digest "$BIRD")" = "$CARD_BEFORE" ]
[ "$(tree_digest "$DATA")" = "$DATA_BEFORE" ]
[ "$(tree_digest "$BIRD/bird-releases/dev-current")" = "$DEV_BEFORE" ]
[ "$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")" = "$SELECTOR_INODE_BEFORE" ]
pass 'Stage 10 host source changes run mapped tests without card or release mutation'

new_case removed-uboot-host-only-source
initialize_dev
CARD_BEFORE=$(tree_digest "$BIRD")
DATA_BEFORE=$(tree_digest "$DATA")
DEV_BEFORE=$(tree_digest "$BIRD/bird-releases/dev-current")
STATE_BEFORE=$(sha256 "$BIRD/bird-dev/state.tsv")
SELECTOR_INODE_BEFORE=$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")
rm "$REPO/kernel/rocknix/inventory-bird-boot-volume.py"
if run_dev --changed >"$CASE_ROOT/removed-host-only.out" \
	2>"$CASE_ROOT/removed-host-only.err"; then
	fail 'changed accepted a removed mapped Stage 10 host source'
fi
grep -q 'removed mapped host-only source cannot satisfy its host gate: kernel/rocknix/inventory-bird-boot-volume.py' \
	"$CASE_ROOT/removed-host-only.err"
[ "$(selector_release)" = dev-current ]
[ "$(tree_digest "$BIRD")" = "$CARD_BEFORE" ]
[ "$(tree_digest "$DATA")" = "$DATA_BEFORE" ]
[ "$(tree_digest "$BIRD/bird-releases/dev-current")" = "$DEV_BEFORE" ]
[ "$(sha256 "$BIRD/bird-dev/state.tsv")" = "$STATE_BEFORE" ]
[ "$(stat -f '%i' "$BIRD/extlinux/extlinux.conf")" = "$SELECTOR_INODE_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'removed Stage 10 host sources fail closed before card payload mutation'

new_case removed-transaction-test
initialize_dev
DEV_BEFORE=$(tree_digest "$BIRD/bird-releases/dev-current")
STATE_BEFORE=$(sha256 "$BIRD/bird-dev/state.tsv")
rm "$REPO/kernel/rocknix/tests/test-dev-build-and-deploy.sh"
if run_dev --all-local >"$CASE_ROOT/removed-test.out" 2>"$CASE_ROOT/removed-test.err"; then
	fail 'all-local accepted a missing transaction suite and stamped readiness'
fi
grep -q 'removed test-only source cannot satisfy its host gate' "$CASE_ROOT/removed-test.err"
[ "$(selector_release)" = prod-a ]
[ "$(tree_digest "$BIRD/bird-releases/dev-current")" = "$DEV_BEFORE" ]
[ "$(sha256 "$BIRD/bird-dev/state.tsv")" = "$STATE_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'missing transaction suite cannot produce an all-local readiness record'

# 6. Provenance captures unstaged, staged, and untracked bytes.
new_case source-provenance
printf '\n# unstaged delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
printf '\n# staged delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-volume.sh"
git -C "$REPO" add kernel/rocknix/stock-root/bird-volume.sh
printf 'untracked documentation bytes\n' >"$REPO/local-notes.md"
run_dev --changed >"$CASE_ROOT/provenance.out"
grep -Eq '^source-state[[:space:]]+dirty:[0-9a-f]{64}$' "$BIRD/bird-dev/state.tsv"
grep -q 'path[[:space:]]*local-notes.md[[:space:]]*file' "$BIRD/bird-dev/source-inventory.tsv"
grep -q 'path[[:space:]]*kernel/rocknix/stock-root/bird-network.sh[[:space:]]*file' "$BIRD/bird-dev/source-inventory.tsv"
grep -q 'path[[:space:]]*kernel/rocknix/stock-root/bird-volume.sh[[:space:]]*file' "$BIRD/bird-dev/source-inventory.tsv"
assert_base_and_fallback_unchanged
pass 'dirty, staged, and untracked source bytes are recorded'

# 7. A clean committed delta since activation remains detectable.
new_case committed-delta
initialize_dev
printf '\n# committed after activation\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
git -C "$REPO" add kernel/rocknix/stock-root/bird-network.sh
git -C "$REPO" commit -qm 'test: committed runtime delta'
[ -z "$(git -C "$REPO" status --porcelain)" ]
run_dev --status >"$CASE_ROOT/committed.status"
grep -q 'changed-components[[:space:]].*runtime:bird-network.sh' "$CASE_ROOT/committed.status"
run_dev --changed >"$CASE_ROOT/committed.out"
grep -q '^Rebuilt groups: runtime:bird-network.sh$' "$CASE_ROOT/committed.out"
grep -q "^repository-commit[[:space:]]*$(git -C "$REPO" rev-parse HEAD)$" "$BIRD/bird-dev/state.tsv"
assert_base_and_fallback_unchanged
pass 'clean committed changes since activation are rebuilt'

new_case toolchain-boundary
initialize_dev
BEFORE=$(tree_digest "$BIRD")
if CLANG=/bin/sh run_dev --changed >"$CASE_ROOT/toolchain.out" 2>"$CASE_ROOT/toolchain.err"; then
	fail 'changed compiler identity was accepted by the fast workflow'
fi
grep -q 'resolved compiler/linker/readelf/cpio/compressor identity changed' \
	"$CASE_ROOT/toolchain.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
pass 'toolchain identity changes remain full-release-only'

new_case actual-output-space
initialize_dev
python3 - "$REPO/kernel/rocknix/stock-root/bird-network.sh" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
with path.open("a", encoding="utf-8") as output:
    output.write("# space growth fixture\n" * 220000)
PY
BEFORE=$(tree_digest "$BIRD")
if BIRD_DEV_TEST_FREE_BYTES=5000000 run_dev --changed \
		>"$CASE_ROOT/space.out" 2>"$CASE_ROOT/space.err"; then
	unset BIRD_DEV_TEST_FREE_BYTES
	fail 'actual enlarged output was not included in the space gate'
fi
unset BIRD_DEV_TEST_FREE_BYTES
grep -q 'insufficient space for dev-current' "$CASE_ROOT/space.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
pass 'space gate uses actual built output growth before card writes'

# 8. Unsupported and full-release-only paths fail before writes.
new_case unsupported-prewrite
initialize_dev
printf 'unsupported product bytes\n' >"$REPO/unknown-product.bin"
BEFORE=$(tree_digest "$BIRD")
if run_dev --changed >"$CASE_ROOT/unsupported.out" 2>"$CASE_ROOT/unsupported.err"; then
	fail 'unsupported source path was accepted'
fi
grep -q 'changed paths require the full release workflow: unknown-product.bin (unsupported)' "$CASE_ROOT/unsupported.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
rm "$REPO/unknown-product.bin"
printf '\n# full builder delta\n' >>"$REPO/kernel/rocknix/build-stock-root-compat.sh"
if run_dev --changed >"$CASE_ROOT/full.out" 2>"$CASE_ROOT/full.err"; then
	fail 'full-release-only path was accepted'
fi
grep -q 'kernel/rocknix/build-stock-root-compat.sh' "$CASE_ROOT/full.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
pass 'unsupported paths fail before card mutation with an exact reason'

new_case removed-source
initialize_dev
mv "$REPO/kernel/rocknix/stock-root/bird-network.sh" "$CASE_ROOT/removed-bird-network.sh"
BEFORE=$(tree_digest "$BIRD")
if run_dev --changed >"$CASE_ROOT/removed.out" 2>"$CASE_ROOT/removed.err"; then
	fail 'removed deployed source path was accepted'
fi
grep -q 'bird-network.sh (deployed/source-path removal requires full release)' \
	"$CASE_ROOT/removed.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
pass 'removing an existing deployed source requires the full release workflow'

# Dirty production-tool bytes are not represented by HEAD, so the transition
# guidance must first require committing the intended source authority.
new_case dirty-production-tooling-guidance
printf '\n# uncommitted production builder delta\n' >>"$REPO/build-and-deploy.sh"
BEFORE_BIRD=$(tree_digest "$BIRD")
BEFORE_DATA=$(tree_digest "$DATA")
if run_dev --changed >"$CASE_ROOT/dirty-transition.out" \
		2>"$CASE_ROOT/dirty-transition.err"; then
	fail 'dirty full-release-only tooling was accepted by the fast workflow'
fi
grep -q 'uncommitted full-release-only bytes are not contained in current HEAD' \
	"$CASE_ROOT/dirty-transition.err"
grep -q 'commit the intended bytes' "$CASE_ROOT/dirty-transition.err"
if grep -q 'canonical release from current HEAD' "$CASE_ROOT/dirty-transition.err"; then
	fail 'dirty transition guidance falsely claimed current HEAD contained intended bytes'
fi
[ "$(tree_digest "$BIRD")" = "$BEFORE_BIRD" ]
[ "$(tree_digest "$DATA")" = "$BEFORE_DATA" ]
pass 'dirty full-release guidance requires committing intended bytes before transition'

# A committed production-tool change remains an authority boundary even when
# another commit restores the endpoint bytes exactly.
new_case reverted-production-tooling-transition
BASE_TOOL_SHA=$(sha256 "$REPO/generate-launcher-catalog.sh")
printf '\n# temporary committed production catalog-tool delta\n' \
	>>"$REPO/generate-launcher-catalog.sh"
git -C "$REPO" add generate-launcher-catalog.sh
git -C "$REPO" commit -qm 'test: temporary production tooling change'
git -C "$REPO" revert --no-edit HEAD >/dev/null
[ "$(sha256 "$REPO/generate-launcher-catalog.sh")" = "$BASE_TOOL_SHA" ]
[ -z "$(git -C "$REPO" status --porcelain)" ]
BEFORE_BIRD=$(tree_digest "$BIRD")
BEFORE_DATA=$(tree_digest "$DATA")
if run_dev --changed >"$CASE_ROOT/reverted-transition.out" \
		2>"$CASE_ROOT/reverted-transition.err"; then
	fail 'committed then reverted production-tooling change disappeared from provenance'
fi
grep -q 'generate-launcher-catalog.sh (full-release-only)' \
	"$CASE_ROOT/reverted-transition.err"
grep -q 'build and physically verify one canonical release from current HEAD' \
	"$CASE_ROOT/reverted-transition.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE_BIRD" ]
[ "$(tree_digest "$DATA")" = "$BEFORE_DATA" ]
pass 'committed production-tool history survives an exact committed revert'

# A production release from before committed production-only tooling changes
# is intentionally not a valid first fast-development base.
new_case older-production-tooling-transition
OLD_BASE_COMMIT=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' '#!/bin/sh' 'exit 0' >"$REPO/build-and-deploy.sh"
printf '%s\n' '#!/bin/sh' 'exit 0' \
	>"$REPO/firmware/mac-update-rocknix-stock-root-v6.sh"
git -C "$REPO" add build-and-deploy.sh firmware/mac-update-rocknix-stock-root-v6.sh
git -C "$REPO" commit -qm 'fix: change canonical production tooling'
[ "$(git -C "$REPO" rev-parse HEAD)" != "$OLD_BASE_COMMIT" ]
BEFORE_BIRD=$(tree_digest "$BIRD")
BEFORE_DATA=$(tree_digest "$DATA")
for MODE in --changed --all-local; do
	if run_dev "$MODE" >"$CASE_ROOT/transition.out" 2>"$CASE_ROOT/transition.err"; then
		fail "$MODE accepted an older base across committed production-tooling changes"
	fi
	grep -q 'build-and-deploy.sh (full-release-only)' "$CASE_ROOT/transition.err"
	grep -q 'mac-update-rocknix-stock-root-v6.sh (full-release-only)' \
		"$CASE_ROOT/transition.err"
	grep -q 'build and physically verify one canonical release from current HEAD' \
		"$CASE_ROOT/transition.err"
	[ "$(tree_digest "$BIRD")" = "$BEFORE_BIRD" ]
	[ "$(tree_digest "$DATA")" = "$BEFORE_DATA" ]
done
create_release prod-current
select_release prod-current
CURRENT_BASE_BEFORE=$(tree_digest "$BIRD/bird-releases/prod-current")
initialize_dev
[ "$(selector_release)" = dev-current ]
grep -q '^base-release[[:space:]]*prod-current$' "$BIRD/bird-dev/state.tsv"
grep -q '^activation[[:space:]]*complete$' "$BIRD/bird-dev/state.tsv"
[ "$(tree_digest "$BIRD/bird-releases/prod-current")" = "$CURRENT_BASE_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'one canonical current-HEAD release closes the older-base transition'

# 9. A selected production change requires an explicit, successful rebase.
new_case base-rebase
initialize_dev
create_release prod-b
select_release prod-b
printf '\n# force one supported local delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
if run_dev --changed >"$CASE_ROOT/base-change.out" 2>"$CASE_ROOT/base-change.err"; then
	fail 'production base mismatch was accepted without rebase'
fi
grep -q 'selected production release differs from dev base (prod-a); use --rebase' "$CASE_ROOT/base-change.err"
if run_dev --all-local >"$CASE_ROOT/base-all.out" 2>"$CASE_ROOT/base-all.err"; then
	fail 'all-local accepted a production base mismatch without rebase'
fi
grep -q 'selected production release differs from dev base (prod-a); use --rebase' "$CASE_ROOT/base-all.err"
create_build_fixture rebased
run_dev --rebase >"$CASE_ROOT/rebase.out"
grep -q '^base-release[[:space:]]*prod-b$' "$BIRD/bird-dev/state.tsv"
[ "$(selector_release)" = dev-current ]
[ "$(tree_digest "$BIRD/bird-releases/prod-a")" = "$BASE_BEFORE" ]
pass 'production base mismatch is rejected until explicit rebase'

# Rebase must have enough currently free space to publish its recovery
# metadata before it may count old mutable/staging bytes as reclaimable.
new_case rebase-pre-reclaim-space
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
STALE_STAGE=$BIRD/bird-releases/.dev-current.new.space-recovery
mkdir "$STALE_STAGE"
python3 - "$STALE_STAGE/recoverable-payload" <<'PY'
import pathlib
import sys
with pathlib.Path(sys.argv[1]).open("wb") as output:
    output.truncate(8 * 1024 * 1024)
PY
BEFORE_BIRD=$(tree_digest "$BIRD")
BEFORE_DATA=$(tree_digest "$DATA")
if BIRD_DEV_TEST_FREE_BYTES=65536 run_dev --rebase \
		>"$CASE_ROOT/rebase-space.out" 2>"$CASE_ROOT/rebase-space.err"; then
	unset BIRD_DEV_TEST_FREE_BYTES
	fail 'rebase funded pre-reclaim metadata from bytes that were not free yet'
fi
unset BIRD_DEV_TEST_FREE_BYTES
grep -q 'insufficient immediate space for rebase recovery metadata' \
	"$CASE_ROOT/rebase-space.err"
grep -q 'recoverable bytes cannot fund pre-reclaim atomic writes' \
	"$CASE_ROOT/rebase-space.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE_BIRD" ]
[ "$(tree_digest "$DATA")" = "$BEFORE_DATA" ]
[ "$(selector_release)" = prod-a ]
assert_base_and_fallback_unchanged
pass 'rebase requires immediate recovery-metadata headroom before card mutation'

# Passing the immediate metadata gate does not replace the independent final
# capacity check for the completed release after safe reclamation.
new_case rebase-final-capacity
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
python3 - "$REPO/kernel/rocknix/stock-root/bird-network.sh" <<'PY'
import pathlib
import sys
with pathlib.Path(sys.argv[1]).open("ab") as output:
    output.write(b"#" + (b"x" * (5 * 1024 * 1024)) + b"\n")
PY
BEFORE_BIRD=$(tree_digest "$BIRD")
BEFORE_DATA=$(tree_digest "$DATA")
if BIRD_DEV_TEST_FREE_BYTES=3145728 run_dev --rebase \
		>"$CASE_ROOT/rebase-capacity.out" 2>"$CASE_ROOT/rebase-capacity.err"; then
	unset BIRD_DEV_TEST_FREE_BYTES
	fail 'rebase accepted insufficient final capacity after metadata headroom passed'
fi
unset BIRD_DEV_TEST_FREE_BYTES
grep -q '^error: insufficient space for dev-current:' "$CASE_ROOT/rebase-capacity.err"
if grep -q 'insufficient immediate space' "$CASE_ROOT/rebase-capacity.err"; then
	fail 'final-capacity fixture did not pass the immediate metadata gate'
fi
[ "$(tree_digest "$BIRD")" = "$BEFORE_BIRD" ]
[ "$(tree_digest "$DATA")" = "$BEFORE_DATA" ]
[ "$(selector_release)" = prod-a ]
assert_base_and_fallback_unchanged
pass 'rebase separately proves final post-reclaim capacity before card mutation'

# 10. Rollback restores the saved production selector byte-for-byte.
new_case exact-rollback
initialize_dev
SAVED_SELECTOR_SHA=$(sha256 "$BIRD/bird-dev/base-selector.conf")
run_dev --rollback >"$CASE_ROOT/rollback.out"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$SAVED_SELECTOR_SHA" ]
[ "$(selector_release)" = prod-a ]
[ -d "$BIRD/bird-releases/dev-current" ]
assert_base_and_fallback_unchanged
pass 'rollback restores the exact saved production selector and retains dev-current'

new_case malformed-state-recovery
initialize_dev
SAVED_SELECTOR_SHA=$(sha256 "$BIRD/bird-dev/base-selector.conf")
printf 'damaged-state-kept-for-diagnosis\n' >"$BIRD/bird-dev/state.tsv"
DAMAGED_STATE_SHA=$(sha256 "$BIRD/bird-dev/state.tsv")
if run_dev --rollback >"$CASE_ROOT/rollback.out" 2>"$CASE_ROOT/rollback.err"; then
	fail 'normal rollback accepted malformed state metadata'
fi
[ "$(selector_release)" = dev-current ]
run_dev --recover-production >"$CASE_ROOT/recover.out"
grep -q '^Recovered exact verified production selector: prod-a$' "$CASE_ROOT/recover.out"
[ "$(selector_release)" = prod-a ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$SAVED_SELECTOR_SHA" ]
[ "$(sha256 "$BIRD/bird-dev/state.tsv")" = "$DAMAGED_STATE_SHA" ]
STALE_STAGE=$BIRD/bird-releases/.DEV-CURRENT.NEW.killed-copy
UNRELATED_HIDDEN=$BIRD/bird-releases/.other-hidden-release
mkdir "$STALE_STAGE" "$UNRELATED_HIDDEN"
printf 'partial development copy\n' >"$STALE_STAGE/payload"
printf 'unrelated hidden bytes\n' >"$UNRELATED_HIDDEN/payload"
UNRELATED_HIDDEN_SHA=$(sha256 "$UNRELATED_HIDDEN/payload")
RECOVERED_BEFORE_BIRD=$(tree_digest "$BIRD")
RECOVERED_BEFORE_DATA=$(tree_digest "$DATA")
run_dev --clean-recovered --dry-run >"$CASE_ROOT/clean-recovered-dry.out"
[ "$(tree_digest "$BIRD")" = "$RECOVERED_BEFORE_BIRD" ]
[ "$(tree_digest "$DATA")" = "$RECOVERED_BEFORE_DATA" ]
run_dev --clean-recovered >"$CASE_ROOT/clean-recovered.out"
grep -q '^Production development-state guards are clear for: prod-a$' \
	"$CASE_ROOT/clean-recovered.out"
[ "$(selector_release)" = prod-a ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$SAVED_SELECTOR_SHA" ]
[ ! -e "$BIRD/bird-dev" ]
[ ! -e "$BIRD/bird-releases/dev-current" ]
[ ! -e "$DATA/Bird/boot-state/releases/dev-current" ]
[ ! -e "$STALE_STAGE" ]
[ "$(sha256 "$UNRELATED_HIDDEN/payload")" = "$UNRELATED_HIDDEN_SHA" ]
[ -z "$(find "$BIRD" -mindepth 1 -maxdepth 1 -iname bird-dev -print -quit)" ]
[ -z "$(find "$BIRD/bird-releases" -mindepth 1 -maxdepth 1 \
	\( -iname dev-current -o -iname '.dev-current.new.*' \) -print -quit)" ]
assert_base_and_fallback_unchanged
pass 'emergency recovery and state-independent cleanup restore a production-ready boundary'

new_case clean-recovered-needs-active-base
initialize_dev
printf 'damaged state\n' >"$BIRD/bird-dev/state.tsv"
BEFORE=$(tree_digest "$BIRD")
if run_dev --clean-recovered >"$CASE_ROOT/clean-recovered.out" \
		2>"$CASE_ROOT/clean-recovered.err"; then
	fail 'recovered cleanup accepted an active development selector'
fi
grep -q 'run --recover-production first' "$CASE_ROOT/clean-recovered.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
[ "$(selector_release)" = dev-current ]
assert_base_and_fallback_unchanged
pass 'recovered cleanup requires the exact independently verified production selector'

new_case clean-recovered-unsafe-tree
initialize_dev
printf 'damaged state\n' >"$BIRD/bird-dev/state.tsv"
run_dev --recover-production >"$CASE_ROOT/recover.out"
ln -s "$CASE_ROOT" "$BIRD/bird-releases/dev-current/unsafe-link"
BEFORE=$(tree_digest "$BIRD")
if run_dev --clean-recovered >"$CASE_ROOT/clean-recovered.out" \
		2>"$CASE_ROOT/clean-recovered.err"; then
	fail 'recovered cleanup accepted a symlink in development state'
fi
grep -q 'dev-current release contains a symlink or special node' \
	"$CASE_ROOT/clean-recovered.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
[ -d "$BIRD/bird-dev" ]
assert_base_and_fallback_unchanged
pass 'recovered cleanup inventories all reserved trees before deletion'

new_case unsafe-recovery-selector
initialize_dev
cp "$BIRD/bird-releases/dev-current/extlinux/extlinux.conf" \
	"$BIRD/bird-dev/base-selector.conf"
SELECTOR_BEFORE=$(sha256 "$BIRD/extlinux/extlinux.conf")
if run_dev --recover-production >"$CASE_ROOT/recover.out" 2>"$CASE_ROOT/recover.err"; then
	fail 'recovery accepted a saved mutable development selector'
fi
grep -q 'saved recovery selector names mutable dev-current, not production' \
	"$CASE_ROOT/recover.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$SELECTOR_BEFORE" ]
sed 's/dev-current/DEV-CURRENT/g' \
	"$BIRD/bird-releases/dev-current/extlinux/extlinux.conf" \
	>"$BIRD/bird-dev/base-selector.conf"
if run_dev --recover-production >"$CASE_ROOT/recover-case.out" \
		2>"$CASE_ROOT/recover-case.err"; then
	fail 'recovery accepted a FAT case alias of mutable dev-current'
fi
grep -q 'saved recovery selector names mutable dev-current, not production' \
	"$CASE_ROOT/recover-case.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$SELECTOR_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'emergency recovery rejects development aliases, fallback, and unverified selectors'

new_case legacy-v1-state
initialize_dev
awk '
	$1 == "schema" { print "schema\tbird-dev-state-v1"; next }
	$1 == "last-build-kind" ||
	$1 == "all-local-source-inventory-sha256" ||
	$1 == "host-test-source-inventory-sha256" ||
	$1 == "host-test-set" { next }
	{ print }
' "$BIRD/bird-dev/state.tsv" >"$CASE_ROOT/state-v1.tsv"
cp "$CASE_ROOT/state-v1.tsv" "$BIRD/bird-dev/state.tsv"
run_dev --status >"$CASE_ROOT/v1.status"
grep -q '^dev-state-verifies[[:space:]]*yes$' "$CASE_ROOT/v1.status"
grep -q '^last-build-kind[[:space:]]*unknown$' "$CASE_ROOT/v1.status"
grep -q '^all-local-current[[:space:]]*unknown$' "$CASE_ROOT/v1.status"
grep -q '^required-host-tests-current[[:space:]]*unknown$' "$CASE_ROOT/v1.status"
grep -q '^ready-for-production-build[[:space:]]*unknown$' "$CASE_ROOT/v1.status"
run_dev --rollback >"$CASE_ROOT/v1.rollback"
[ "$(selector_release)" = prod-a ]
run_dev --all-local >"$CASE_ROOT/v1-upgrade.out"
grep -q '^schema[[:space:]]*bird-dev-state-v2$' "$BIRD/bird-dev/state.tsv"
grep -q '^last-build-kind[[:space:]]*all-local$' "$BIRD/bird-dev/state.tsv"
assert_base_and_fallback_unchanged
pass 'deployed v1 state remains recoverable and upgrades after a verified local build'

new_case unchanged-reactivation
initialize_dev
DEV_BEFORE=$(tree_digest "$BIRD/bird-releases/dev-current")
run_dev --rollback >"$CASE_ROOT/rollback.out"
[ "$(selector_release)" = prod-a ]
run_dev --changed >"$CASE_ROOT/reactivate.out"
grep -q '^Reactivated unchanged verified dev-current; no release payload file was rewritten\.$' \
	"$CASE_ROOT/reactivate.out"
[ "$(selector_release)" = dev-current ]
[ "$(tree_digest "$BIRD/bird-releases/dev-current")" = "$DEV_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'changed reactivates an unchanged verified dev release after rollback'

# 11. Clean removes only the verified dev release and its metadata.
new_case safe-clean
initialize_dev
create_release prod-extra
EXTRA_BEFORE=$(tree_digest "$BIRD/bird-releases/prod-extra")
run_dev --clean >"$CASE_ROOT/clean.out"
[ "$(selector_release)" = prod-a ]
[ ! -e "$BIRD/bird-releases/dev-current" ]
[ ! -e "$BIRD/bird-dev" ]
[ ! -e "$DATA/Bird/boot-state/releases/dev-current" ]
[ "$(tree_digest "$BIRD/bird-releases/prod-extra")" = "$EXTRA_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'clean cannot remove a production release'

# Cleanup publishes a durable, state-independent selector authority before
# changing the selector or removing any reserved development tree. Every
# interruption boundary must remain recoverable even when bird-dev is then
# only partially readable.
for CLEANUP_FAILPOINT in \
	cleanup-after-authority-publication \
	cleanup-after-selector-restoration \
	cleanup-after-dev-release-removal \
	cleanup-after-attempt-state-removal \
	cleanup-after-stale-stage-removal \
	cleanup-after-authority-temporary-removal \
	cleanup-after-metadata-removal \
	cleanup-before-authority-removal \
	cleanup-after-authority-sidecar-removal; do
	new_case "durable-$CLEANUP_FAILPOINT"
	initialize_dev
	STALE_STAGE=$BIRD/bird-releases/.DEV-CURRENT.NEW.cleanup-interruption
	cp -R "$BIRD/bird-releases/dev-current" "$STALE_STAGE"
	CLEANUP_COMMAND=--clean
	if [ "$CLEANUP_FAILPOINT" = cleanup-after-authority-sidecar-removal ]; then
		if run_dev_failpoint cleanup-after-metadata-removal --clean \
				>"$CASE_ROOT/setup-fail.out" 2>"$CASE_ROOT/setup-fail.err"; then
			fail 'sidecar-boundary setup did not interrupt cleanup'
		fi
		printf 'late AppleDouble metadata\n' >"$BIRD/._bird-dev-cleanup.tsv"
		CLEANUP_COMMAND=--clean-recovered
	fi
	if run_dev_failpoint "$CLEANUP_FAILPOINT" "$CLEANUP_COMMAND" \
			>"$CASE_ROOT/clean-fail.out" 2>"$CASE_ROOT/clean-fail.err"; then
		fail "$CLEANUP_FAILPOINT did not interrupt cleanup"
	fi
	grep -q "host-only injected failure: $CLEANUP_FAILPOINT" \
		"$CASE_ROOT/clean-fail.err"
	[ -f "$BIRD/bird-dev-cleanup.tsv" ]
	grep -q '^schema[[:space:]]*bird-dev-cleanup-v1$' \
		"$BIRD/bird-dev-cleanup.tsv"
	grep -q '^base-release[[:space:]]*prod-a$' \
		"$BIRD/bird-dev-cleanup.tsv"
	if [ "$CLEANUP_FAILPOINT" = cleanup-after-authority-sidecar-removal ]; then
		[ ! -e "$BIRD/._bird-dev-cleanup.tsv" ]
	fi
	# Model a hard interruption in recursive metadata deletion. Recovery must
	# now depend only on the durable top-level authority.
	if [ -d "$BIRD/bird-dev" ]; then
		rm -f "$BIRD/bird-dev/state.tsv" "$BIRD/bird-dev/base-selector.conf"
	fi
	for BLOCKED_MODE in --changed --all-local --rebase --rollback --clean; do
		if run_dev "$BLOCKED_MODE" >"$CASE_ROOT/blocked.out" \
				2>"$CASE_ROOT/blocked.err"; then
			fail "$BLOCKED_MODE accepted a pending cleanup authority"
		fi
		grep -q 'durable development cleanup is pending' "$CASE_ROOT/blocked.err"
	done
	run_dev --recover-production >"$CASE_ROOT/recover.out"
	[ "$(selector_release)" = prod-a ]
	run_dev --clean-recovered >"$CASE_ROOT/clean-recovered.out"
	[ "$(selector_release)" = prod-a ]
	[ ! -e "$BIRD/bird-dev-cleanup.tsv" ]
	[ ! -e "$BIRD/bird-dev" ]
	[ ! -e "$BIRD/bird-releases/dev-current" ]
	[ ! -e "$DATA/Bird/boot-state/releases/dev-current" ]
	[ ! -e "$STALE_STAGE" ]
	assert_base_and_fallback_unchanged
	pass "$CLEANUP_FAILPOINT retains restartable cleanup authority"
done

new_case cleanup-missing-protected-type-invariant
initialize_dev
rm "$BIRD/extlinux/extlinux.previous.conf"
if run_dev_failpoint cleanup-after-authority-publication --clean \
		>"$CASE_ROOT/fail.out" 2>"$CASE_ROOT/fail.err"; then
	fail 'missing-protected cleanup setup did not publish authority'
fi
run_dev --recover-production >"$CASE_ROOT/recover.out"
AUTHORITY_SHA=$(sha256 "$BIRD/bird-dev-cleanup.tsv")
DEV_SHA=$(tree_digest "$BIRD/bird-releases/dev-current")
for PROTECTED_TYPE in directory symlink fifo; do
	case "$PROTECTED_TYPE" in
		directory) mkdir "$BIRD/extlinux/extlinux.previous.conf" ;;
		symlink) ln -s "$CASE_ROOT" "$BIRD/extlinux/extlinux.previous.conf" ;;
		fifo) mkfifo "$BIRD/extlinux/extlinux.previous.conf" ;;
	esac
	BEFORE_BIRD=$(tree_digest "$BIRD")
	BEFORE_DATA=$(tree_digest "$DATA")
	if run_dev --clean-recovered >"$CASE_ROOT/$PROTECTED_TYPE.out" \
			2>"$CASE_ROOT/$PROTECTED_TYPE.err"; then
		fail "cleanup accepted $PROTECTED_TYPE at a protected missing path"
	fi
	grep -q 'fallback/recovery since cleanup publication path became a symlink, directory, or special node' \
		"$CASE_ROOT/$PROTECTED_TYPE.err"
	[ "$(sha256 "$BIRD/bird-dev-cleanup.tsv")" = "$AUTHORITY_SHA" ]
	[ "$(tree_digest "$BIRD/bird-releases/dev-current")" = "$DEV_SHA" ]
	[ "$(tree_digest "$BIRD")" = "$BEFORE_BIRD" ]
	[ "$(tree_digest "$DATA")" = "$BEFORE_DATA" ]
	case "$PROTECTED_TYPE" in
		directory) rmdir "$BIRD/extlinux/extlinux.previous.conf" ;;
		symlink|fifo) rm "$BIRD/extlinux/extlinux.previous.conf" ;;
	esac
done
run_dev --clean-recovered >"$CASE_ROOT/clean.out"
[ ! -e "$BIRD/bird-dev-cleanup.tsv" ]
[ ! -e "$BIRD/bird-releases/dev-current" ]
[ "$(selector_release)" = prod-a ]
[ "$(tree_digest "$BIRD/bird-releases/prod-a")" = "$BASE_BEFORE" ]
[ "$(sha256 "$BIRD/dtb.img")" = "$TOP_DTB_BEFORE" ]
[ "$(sha256 "$DATA/Bird/boot-state/releases/prod-a/attempts")" = \
	"$PRODUCTION_ATTEMPTS_BEFORE" ]
pass 'protected missing paths reject directories, symlinks, and special nodes across restart'

new_case interrupted-cleanup-authority-temporary
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
CLEANUP_TEMP=$BIRD/.BIRD-DEV-CLEANUP.TSV.DEV-NEW.interrupted
printf 'unpublished cleanup authority bytes\n' >"$CLEANUP_TEMP"
printf 'orphan authority metadata\n' >"$BIRD/._bird-dev-cleanup.tsv"
printf 'orphan temporary metadata\n' \
	>"$BIRD/._.bird-dev-cleanup.tsv.dev-new.orphan"
printf 'near-prefix authority metadata\n' \
	>"$BIRD/._bird-dev-cleanup.tsv.keep"
printf 'near-prefix temporary metadata\n' \
	>"$BIRD/._.bird-dev-cleanup.tsv.dev-newish.keep"
printf 'double-prefix authority near name\n' \
	>"$BIRD/._._bird-dev-cleanup.tsv"
printf 'double-prefix temporary near name\n' \
	>"$BIRD/._._.bird-dev-cleanup.tsv.dev-new.orphan"
NEAR_AUTHORITY_SHA=$(sha256 "$BIRD/._bird-dev-cleanup.tsv.keep")
NEAR_TEMP_SHA=$(sha256 \
	"$BIRD/._.bird-dev-cleanup.tsv.dev-newish.keep")
DOUBLE_AUTHORITY_SHA=$(sha256 "$BIRD/._._bird-dev-cleanup.tsv")
DOUBLE_TEMP_SHA=$(sha256 \
	"$BIRD/._._.bird-dev-cleanup.tsv.dev-new.orphan")
if run_dev --changed >"$CASE_ROOT/changed.out" 2>"$CASE_ROOT/changed.err"; then
	fail 'development build accepted an interrupted cleanup-authority temporary'
fi
grep -q 'interrupted cleanup-authority publication is pending' \
	"$CASE_ROOT/changed.err"
run_dev --clean >"$CASE_ROOT/clean.out"
[ ! -e "$CLEANUP_TEMP" ]
[ ! -e "$BIRD/bird-dev-cleanup.tsv" ]
[ ! -e "$BIRD/._bird-dev-cleanup.tsv" ]
[ ! -e "$BIRD/._.bird-dev-cleanup.tsv.dev-new.orphan" ]
[ "$(sha256 "$BIRD/._bird-dev-cleanup.tsv.keep")" = "$NEAR_AUTHORITY_SHA" ]
[ "$(sha256 "$BIRD/._.bird-dev-cleanup.tsv.dev-newish.keep")" = \
	"$NEAR_TEMP_SHA" ]
[ "$(sha256 "$BIRD/._._bird-dev-cleanup.tsv")" = \
	"$DOUBLE_AUTHORITY_SHA" ]
[ "$(sha256 "$BIRD/._._.bird-dev-cleanup.tsv.dev-new.orphan")" = \
	"$DOUBLE_TEMP_SHA" ]
[ "$(selector_release)" = prod-a ]
assert_base_and_fallback_unchanged
pass 'clean removes only reserved interrupted cleanup-authority temporaries'

new_case unsafe-cleanup-authority-residue
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
ln -s "$CASE_ROOT" "$BIRD/._bird-dev-cleanup.tsv"
BEFORE_BIRD=$(tree_digest "$BIRD")
BEFORE_DATA=$(tree_digest "$DATA")
if run_dev --clean >"$CASE_ROOT/symlink.out" 2>"$CASE_ROOT/symlink.err"; then
	fail 'cleanup accepted a symlinked cleanup-authority sidecar'
fi
grep -q 'interrupted cleanup-authority temporary is not a safe regular file' \
	"$CASE_ROOT/symlink.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE_BIRD" ]
[ "$(tree_digest "$DATA")" = "$BEFORE_DATA" ]
rm "$BIRD/._bird-dev-cleanup.tsv"
mkfifo "$BIRD/._.bird-dev-cleanup.tsv.dev-new.special"
BEFORE_BIRD=$(tree_digest "$BIRD")
BEFORE_DATA=$(tree_digest "$DATA")
if run_dev --clean >"$CASE_ROOT/special.out" 2>"$CASE_ROOT/special.err"; then
	fail 'cleanup accepted a special cleanup-authority sidecar'
fi
grep -q 'interrupted cleanup-authority temporary is not a safe regular file' \
	"$CASE_ROOT/special.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE_BIRD" ]
[ "$(tree_digest "$DATA")" = "$BEFORE_DATA" ]
rm "$BIRD/._.bird-dev-cleanup.tsv.dev-new.special"
run_dev --clean >"$CASE_ROOT/clean.out"
assert_base_and_fallback_unchanged
pass 'cleanup residue symlinks and special nodes fail before mutation'

new_case strict-cleanup-authority
initialize_dev
if run_dev_failpoint cleanup-after-authority-publication --clean \
		>"$CASE_ROOT/clean-fail.out" 2>"$CASE_ROOT/clean-fail.err"; then
	fail 'cleanup authority publication failpoint did not fire'
fi
cp "$BIRD/bird-dev-cleanup.tsv" "$CASE_ROOT/authority.good"
for AUTHORITY_DAMAGE in duplicate unknown reordered digest encoding trailing-cr; do
	cp "$CASE_ROOT/authority.good" "$BIRD/bird-dev-cleanup.tsv"
	case "$AUTHORITY_DAMAGE" in
		duplicate) printf 'schema\tbird-dev-cleanup-v1\n' >>"$BIRD/bird-dev-cleanup.tsv" ;;
		unknown) sed 's/^base-selector-bytes/new-field/' "$CASE_ROOT/authority.good" \
			>"$BIRD/bird-dev-cleanup.tsv" ;;
		reordered) awk 'NR == 2 { saved=$0; next } NR == 3 { print; print saved; next } { print }' \
			"$CASE_ROOT/authority.good" >"$BIRD/bird-dev-cleanup.tsv" ;;
		digest) sed 's/^base-selector-sha256.*/base-selector-sha256\t0000000000000000000000000000000000000000000000000000000000000000/' \
			"$CASE_ROOT/authority.good" >"$BIRD/bird-dev-cleanup.tsv" ;;
		encoding) sed 's/^base-selector-hex.*/base-selector-hex\tzz/' \
			"$CASE_ROOT/authority.good" >"$BIRD/bird-dev-cleanup.tsv" ;;
		trailing-cr) perl -pe 's/\n/\r\n/g' "$CASE_ROOT/authority.good" \
			>"$BIRD/bird-dev-cleanup.tsv" ;;
	esac
	if run_dev --recover-production >"$CASE_ROOT/$AUTHORITY_DAMAGE.out" \
			2>"$CASE_ROOT/$AUTHORITY_DAMAGE.err"; then
		fail "cleanup authority accepted $AUTHORITY_DAMAGE damage"
	fi
done
cp "$CASE_ROOT/authority.good" "$BIRD/bird-dev-cleanup.tsv"
run_dev --recover-production >"$CASE_ROOT/recover.out"
run_dev --clean-recovered >"$CASE_ROOT/clean.out"
assert_base_and_fallback_unchanged
pass 'cleanup authority parser rejects noncanonical, reordered, and damaged records'

new_case recovered-cleanup-publication
initialize_dev
printf 'damaged state\n' >"$BIRD/bird-dev/state.tsv"
run_dev --recover-production >"$CASE_ROOT/recover.out"
if run_dev_failpoint cleanup-after-authority-publication --clean-recovered \
		>"$CASE_ROOT/fail.out" 2>"$CASE_ROOT/fail.err"; then
	fail 'clean-recovered did not publish authority before interruption'
fi
[ -f "$BIRD/bird-dev-cleanup.tsv" ]
rm -f "$BIRD/bird-dev/base-selector.conf" "$BIRD/bird-dev/state.tsv"
run_dev --recover-production >"$CASE_ROOT/recover-again.out"
run_dev --clean-recovered >"$CASE_ROOT/clean-again.out"
[ ! -e "$BIRD/bird-dev-cleanup.tsv" ]
[ ! -e "$BIRD/bird-dev" ]
[ "$(selector_release)" = prod-a ]
assert_base_and_fallback_unchanged
pass 'clean-recovered also publishes restartable authority before deletion'

new_case true-case-alias-cleanup-rejection
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
if mkdir "$BIRD/BIRD-DEV" 2>/dev/null; then
	printf 'distinct alias\n' >"$BIRD/BIRD-DEV/evidence"
	BEFORE=$(tree_digest "$BIRD")
	if run_dev --clean >"$CASE_ROOT/alias.out" 2>"$CASE_ROOT/alias.err"; then
		fail 'cleanup accepted two distinct case aliases'
	fi
	grep -Eq 'multiple case aliases of bird-dev|ambiguous case alias of bird-dev' \
		"$CASE_ROOT/alias.err"
	[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
	rm -rf "$BIRD/BIRD-DEV"
fi
run_dev --clean >"$CASE_ROOT/clean.out"
assert_base_and_fallback_unchanged
pass 'cleanup rejects only a true distinct case alias on case-sensitive fixtures'

new_case single-fat-case-entry-cleanup
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
mv "$BIRD/bird-dev" "$BIRD/BIRD-DEV"
	if [ -d "$BIRD/bird-dev" ]; then
	mv "$BIRD/bird-releases/dev-current" "$BIRD/bird-releases/DEV-CURRENT"
	if [ -d "$DATA/Bird/boot-state/releases/dev-current" ]; then
		mv "$DATA/Bird/boot-state/releases/dev-current" \
			"$DATA/Bird/boot-state/releases/DEV-CURRENT"
	fi
	run_dev --clean >"$CASE_ROOT/clean.out"
	[ ! -e "$BIRD/BIRD-DEV" ]
	[ ! -e "$BIRD/bird-releases/DEV-CURRENT" ]
	[ ! -e "$DATA/Bird/boot-state/releases/DEV-CURRENT" ]
else
	# A case-sensitive fixture cannot model a single FAT directory entry under
	# two path spellings; restore the canonical spelling and retain the direct
	# distinct-alias coverage above.
	mv "$BIRD/BIRD-DEV" "$BIRD/bird-dev"
	run_dev --clean >"$CASE_ROOT/clean.out"
fi
assert_base_and_fallback_unchanged
pass 'one differently cased FAT entry is cleaned by filesystem identity'

new_case hard-killed-stage-clean
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
STALE_STAGE=$BIRD/bird-releases/.DEV-CURRENT.NEW.killed-copy
UNRELATED_HIDDEN=$BIRD/bird-releases/.other-hidden-release
cp -R "$BIRD/bird-releases/dev-current" "$STALE_STAGE"
mkdir "$UNRELATED_HIDDEN"
printf 'unrelated hidden bytes\n' >"$UNRELATED_HIDDEN/payload"
UNRELATED_HIDDEN_SHA=$(sha256 "$UNRELATED_HIDDEN/payload")
rm -rf "$BIRD/bird-releases/dev-current"
run_dev --clean >"$CASE_ROOT/clean.out"
[ ! -e "$STALE_STAGE" ]
[ ! -e "$BIRD/bird-dev" ]
[ "$(sha256 "$UNRELATED_HIDDEN/payload")" = "$UNRELATED_HIDDEN_SHA" ]
[ "$(selector_release)" = prod-a ]
assert_base_and_fallback_unchanged
pass 'clean removes a hard-killed initial-copy stage and leaves unrelated hidden state'

new_case stale-stage-rebase
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
STALE_STAGE=$BIRD/bird-releases/.dev-current.new.interrupted
UNRELATED_HIDDEN=$BIRD/bird-releases/.unrelated-stage
cp -R "$BIRD/bird-releases/dev-current" "$STALE_STAGE"
mkdir "$UNRELATED_HIDDEN"
printf 'unrelated hidden bytes\n' >"$UNRELATED_HIDDEN/payload"
UNRELATED_HIDDEN_SHA=$(sha256 "$UNRELATED_HIDDEN/payload")
run_dev --rebase >"$CASE_ROOT/rebase.out"
[ ! -e "$STALE_STAGE" ]
[ "$(sha256 "$UNRELATED_HIDDEN/payload")" = "$UNRELATED_HIDDEN_SHA" ]
[ "$(selector_release)" = dev-current ]
assert_base_and_fallback_unchanged
pass 'rebase removes stale dev copy stages without touching other hidden releases'

new_case stale-stage-symlink
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
ln -s "$CASE_ROOT" "$BIRD/bird-releases/.dev-current.new.unsafe"
BEFORE=$(tree_digest "$BIRD")
if run_dev --clean >"$CASE_ROOT/clean.out" 2>"$CASE_ROOT/clean.err"; then
	fail 'clean accepted a symlinked stale dev copy stage'
fi
grep -q 'stale dev-current staging directory is not a safe directory' \
	"$CASE_ROOT/clean.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
assert_base_and_fallback_unchanged
pass 'stale development stages fail closed on symlinks and special nodes'

# 12. Dry-run is read-only even on the first invocation.
new_case dry-run
BEFORE_BIRD=$(tree_digest "$BIRD")
BEFORE_DATA=$(tree_digest "$DATA")
run_dev --changed --dry-run >"$CASE_ROOT/dry-run.out"
grep -q '^dry-run: base=prod-a dev=dev-current profile=release$' "$CASE_ROOT/dry-run.out"
[ "$(tree_digest "$BIRD")" = "$BEFORE_BIRD" ]
[ "$(tree_digest "$DATA")" = "$BEFORE_DATA" ]
[ ! -e "$BIRD/bird-dev" ]
pass 'dry-run performs no writes'

# 13. Wrong identity and symlinked card paths fail closed.
new_case identity-symlink
sed 's/Removable Media\tRemovable/Removable Media\tFixed/' "$DEVICE_INFO" >"$CASE_ROOT/device-info.bad"
GOOD_INFO=$DEVICE_INFO
DEVICE_INFO=$CASE_ROOT/device-info.bad
BEFORE=$(tree_digest "$BIRD")
if run_dev --status >"$CASE_ROOT/identity.out" 2>"$CASE_ROOT/identity.err"; then
	fail 'non-removable identity was accepted'
fi
grep -q 'refusing non-removable disk' "$CASE_ROOT/identity.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
DEVICE_INFO=$GOOD_INFO
mv "$BIRD/bird-releases" "$BIRD/releases-real"
ln -s releases-real "$BIRD/bird-releases"
if run_dev --status >"$CASE_ROOT/symlink.out" 2>"$CASE_ROOT/symlink.err"; then
	fail 'symlinked release root was accepted'
fi
grep -q 'release root is not a safe directory' "$CASE_ROOT/symlink.err"
pass 'identity ambiguity and symlinked paths fail closed'

new_case source-symlink
initialize_dev
printf '%s\n' '#!/bin/sh' 'exit 0' >"$CASE_ROOT/external-runtime.sh"
mv "$REPO/kernel/rocknix/stock-root/bird-network.sh" \
	"$CASE_ROOT/original-bird-network.sh"
ln -s "$CASE_ROOT/external-runtime.sh" \
	"$REPO/kernel/rocknix/stock-root/bird-network.sh"
BEFORE=$(tree_digest "$BIRD")
if run_dev --changed >"$CASE_ROOT/source-symlink.out" 2>"$CASE_ROOT/source-symlink.err"; then
	fail 'symlinked supported source was accepted'
fi
grep -q 'repository source kernel/rocknix/stock-root/bird-network.sh is not a safe regular file' \
	"$CASE_ROOT/source-symlink.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
pass 'symlinked supported source bytes fail before card mutation'

new_case clean-ancestor-symlink
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
mv "$DATA/Bird/boot-state/releases" "$CASE_ROOT/attempt-releases"
ln -s "$CASE_ROOT/attempt-releases" "$DATA/Bird/boot-state/releases"
BEFORE=$(tree_digest "$BIRD")
if run_dev --clean >"$CASE_ROOT/clean-symlink.out" 2>"$CASE_ROOT/clean-symlink.err"; then
	fail 'symlinked attempt-state ancestor was accepted by clean'
fi
grep -q 'fixed directory chain is not a safe directory' "$CASE_ROOT/clean-symlink.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
[ -d "$BIRD/bird-releases/dev-current" ]
pass 'clean validates every attempt-state ancestor before deletion'

# 14-17. Transaction failpoints always restore/retain the production selector.
new_case fail-after-base
initialize_dev
printf '\n# failpoint delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
if run_dev_failpoint after-base-selector-restoration --changed >"$CASE_ROOT/fail.out" 2>"$CASE_ROOT/fail.err"; then
	fail 'after-base-selector-restoration failpoint did not fail'
fi
[ "$(selector_release)" = prod-a ]
[ -f "$BIRD/bird-releases/dev-current/.complete" ]
assert_base_and_fallback_unchanged
pass 'failure after base restoration leaves the base selected'

new_case fail-dev-incomplete
initialize_dev
printf '\n# incremental incomplete delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
if run_dev_failpoint after-dev-incomplete --changed >"$CASE_ROOT/fail.out" 2>"$CASE_ROOT/fail.err"; then
	fail 'after-dev-incomplete failpoint did not fail'
fi
[ "$(selector_release)" = prod-a ]
[ -d "$BIRD/bird-releases/dev-current" ]
[ ! -e "$BIRD/bird-releases/dev-current/.complete" ]
grep -q '^activation[[:space:]]*incomplete$' "$BIRD/bird-dev/state.tsv"
assert_base_and_fallback_unchanged
run_dev --rebase >"$CASE_ROOT/recover.out"
grep -q '^activation[[:space:]]*complete$' "$BIRD/bird-dev/state.tsv"
[ "$(selector_release)" = dev-current ]
pass 'incremental failure records incomplete state and rebase recovers it'

new_case fail-before-activation
initialize_dev
printf '\n# failpoint delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
if run_dev_failpoint before-selector-activation --changed >"$CASE_ROOT/fail.out" 2>"$CASE_ROOT/fail.err"; then
	fail 'before-selector-activation failpoint did not fail'
fi
[ "$(selector_release)" = prod-a ]
[ ! -e "$BIRD/bird-releases/dev-current/.complete" ]
grep -q '^activation[[:space:]]*incomplete$' "$BIRD/bird-dev/state.tsv"
assert_base_and_fallback_unchanged
pass 'failure before activation leaves the production selector active'

new_case fail-after-rename
initialize_dev
printf '\n# failpoint delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
if run_dev_failpoint after-selector-rename --changed >"$CASE_ROOT/fail.out" 2>"$CASE_ROOT/fail.err"; then
	fail 'after-selector-rename failpoint did not fail'
fi
[ "$(selector_release)" = prod-a ]
[ ! -e "$BIRD/bird-releases/dev-current/.complete" ]
grep -q '^activation[[:space:]]*incomplete$' "$BIRD/bird-dev/state.tsv"
assert_base_and_fallback_unchanged
pass 'failure after selector rename restores the production selector'

new_case fail-after-state-commit
initialize_dev
printf '\n# post-state-commit delta\n' >>"$REPO/kernel/rocknix/stock-root/bird-network.sh"
if run_dev_failpoint after-state-commit --changed >"$CASE_ROOT/fail.out" 2>"$CASE_ROOT/fail.err"; then
	fail 'after-state-commit failpoint did not fail'
fi
[ "$(selector_release)" = prod-a ]
[ ! -e "$BIRD/bird-releases/dev-current/.complete" ]
grep -q '^activation[[:space:]]*incomplete$' "$BIRD/bird-dev/state.tsv"
assert_base_and_fallback_unchanged
run_dev --rebase >"$CASE_ROOT/recover.out"
grep -q '^activation[[:space:]]*complete$' "$BIRD/bird-dev/state.tsv"
[ "$(selector_release)" = dev-current ]
assert_base_and_fallback_unchanged
pass 'failure after complete-state publication downgrades metadata and rebase recovers it'

# 18-20 are asserted throughout: base/fallback bytes, attempts, and sidecars.
new_case appledouble
initialize_dev
[ -z "$(find "$BIRD/bird-releases/dev-current" -name '._*' -print -quit)" ]
assert_base_and_fallback_unchanged
pass 'development deployment creates no AppleDouble files or fallback drift'

# 21. Duplicate manifest paths, omitted files, and mismatched hashes are rejected.
new_case duplicate-manifest
MANIFEST=$BIRD/bird-releases/prod-a/deploy-manifest.tsv
grep '^file[[:space:]]' "$MANIFEST" | head -1 >>"$MANIFEST"
sha256 "$MANIFEST" >"$BIRD/bird-releases/prod-a/.complete"
BEFORE=$(tree_digest "$BIRD")
if run_dev --changed >"$CASE_ROOT/duplicate.out" 2>"$CASE_ROOT/duplicate.err"; then
	fail 'duplicate manifest path was accepted'
fi
grep -q 'deploy manifest has invalid file records' "$CASE_ROOT/duplicate.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
pass 'duplicate manifest paths are rejected before writes'

new_case omitted-manifest-file
printf 'unlisted bytes\n' >"$BIRD/bird-releases/prod-a/unlisted.bin"
BEFORE=$(tree_digest "$BIRD")
if run_dev --changed >"$CASE_ROOT/omitted.out" 2>"$CASE_ROOT/omitted.err"; then
	fail 'file omitted from manifest was accepted'
fi
grep -q 'release file inventory differs from manifest' "$CASE_ROOT/omitted.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
pass 'files omitted from a manifest are rejected before writes'

new_case mismatched-hash
printf 'tampered kernel\n' >"$BIRD/bird-releases/prod-a/KERNEL"
BEFORE=$(tree_digest "$BIRD")
if run_dev --changed >"$CASE_ROOT/hash.out" 2>"$CASE_ROOT/hash.err"; then
	fail 'mismatched release hash was accepted'
fi
grep -q 'release file changed: prod-a/KERNEL' "$CASE_ROOT/hash.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
pass 'mismatched manifest hashes are rejected before writes'

new_case corrupt-dev-status
initialize_dev
printf '\n# corrupt dev manifest binding\n' >>"$BIRD/bird-releases/dev-current/deploy-manifest.tsv"
run_dev --status >"$CASE_ROOT/corrupt.status"
grep -q '^dev-current-verifies[[:space:]]*no$' "$CASE_ROOT/corrupt.status"
grep -q '^dev-state-verifies[[:space:]]*no$' "$CASE_ROOT/corrupt.status"
grep -q '^rebase-required[[:space:]]*yes$' "$CASE_ROOT/corrupt.status"
run_dev --rollback >"$CASE_ROOT/corrupt.rollback"
[ "$(selector_release)" = prod-a ]
assert_base_and_fallback_unchanged
pass 'status diagnoses corrupt dev bytes and rollback remains available'

new_case malformed-state-status
initialize_dev
run_dev --rollback >"$CASE_ROOT/rollback.out"
printf 'not-a-valid-state\n' >"$BIRD/bird-dev/state.tsv"
run_dev --status >"$CASE_ROOT/malformed-state.status"
grep -q '^dev-state-verifies[[:space:]]*no$' "$CASE_ROOT/malformed-state.status"
grep -q '^rebase-required[[:space:]]*yes$' "$CASE_ROOT/malformed-state.status"
pass 'status reports malformed development metadata without writing'

new_case malformed-selector-status
initialize_dev
printf '\377not-ascii\n' >"$BIRD/extlinux/extlinux.conf"
run_dev --status >"$CASE_ROOT/malformed-selector.status"
grep -q '^selector-kind[[:space:]]*malformed-or-incomplete$' \
	"$CASE_ROOT/malformed-selector.status"
grep -q '^rebase-required[[:space:]]*yes$' "$CASE_ROOT/malformed-selector.status"
pass 'status reports a malformed selector without writing'

# 22. Process lifetime uses dev-current while immutable SYSTEM uses its base.
new_case specialized-authorities
initialize_dev
grep -q '^RELEASE_ID=dev-current$' "$BIRD/bird-releases/dev-current/bird/supervisor.sh"
grep -q '^BIRD_SYSTEM_RELEASE=prod-a$' \
	"$BIRD/bird-releases/dev-current/post-flash.sh"
gzip -dc "$BIRD/bird-releases/dev-current/bird-initramfs.cpio.gz" | \
	grep -a -q 'BIRD_LOADER_RELEASE=dev-current'
run_dev --status >"$CASE_ROOT/status.out"
grep -q '^selector-kind[[:space:]]*development$' "$CASE_ROOT/status.out"
grep -q '^dev-current-verifies[[:space:]]*yes$' "$CASE_ROOT/status.out"
assert_base_and_fallback_unchanged
pass 'dev process authorities and immutable SYSTEM base are specialized independently'

new_case source-parity-authority-mismatch
MANIFEST=$BIRD/bird-releases/prod-a/deploy-manifest.tsv
sed -i '' \
	's/a8ac6cacfa89672fa08dec7fa02179bb108a4a2303fd5c1eb5834f916089b79b/fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05/' \
	"$MANIFEST"
sha256 "$MANIFEST" >"$BIRD/bird-releases/prod-a/.complete"
BEFORE=$(tree_digest "$BIRD")
if run_dev --changed >"$CASE_ROOT/source-mismatch.out" 2>"$CASE_ROOT/source-mismatch.err"; then
	fail 'source joypad without its source-kernel authority was accepted'
fi
grep -q 'kernel authority and early joypad input do not agree' \
	"$CASE_ROOT/source-mismatch.err"
[ "$(tree_digest "$BIRD")" = "$BEFORE" ]
pass 'source joypad and source-kernel authority must be bound together'

new_case source-parity-base
convert_manifest_to_source_parity
BASE_BEFORE=$(tree_digest "$BIRD/bird-releases/prod-a")
run_dev --changed >"$CASE_ROOT/source-parity.out"
awk -F '\t' '$1 == "input" && $2 == "source-kernel-parity.tsv" && \
	$5 == "74ea672573dd80f368314bdef6a9481b2af9cf54b321cfd6e165179cc3185ffc" { found = 1 } \
	END { exit !found }' "$BIRD/bird-releases/dev-current/deploy-manifest.tsv"
[ "$(selector_release)" = dev-current ]
assert_base_and_fallback_unchanged
pass 'a verified source-kernel production base initializes dev-current'

new_case source-irq-buttons-base
convert_manifest_to_irq_buttons
BASE_BEFORE=$(tree_digest "$BIRD/bird-releases/prod-a")
run_dev --changed >"$CASE_ROOT/source-irq-buttons.out"
awk -F '\t' '$1 == "input" && $2 == "source-kernel-irq-buttons.tsv" && \
	$5 == "0020d161b5a2be0d8393267c3eb96794a0c2d9f82e8df5e097932216fad9e45d" { found = 1 } \
	END { exit !found }' "$BIRD/bird-releases/dev-current/deploy-manifest.tsv"
[ "$(selector_release)" = dev-current ]
assert_base_and_fallback_unchanged
pass 'a verified IRQ-buttons production base initializes dev-current'

printf 'PASS: %s dev-current host transaction cases\n' "$PASS_COUNT"
