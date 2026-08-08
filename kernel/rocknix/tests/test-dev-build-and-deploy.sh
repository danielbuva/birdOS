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
	launcher/bird-pidwait.c \
	launcher/bird-powerstate.c \
	launcher/bird-device-contract.h \
	launcher/catalog.generated.h \
	launcher/library.inventory.tsv \
	launcher/catalog.revision \
	firmware/mac-stock-root-card-identity.sh \
	firmware/mac-bird-card-lock.sh \
	firmware/normalize-newc.py \
	firmware/generate-launcher-bootlogo.py \
	firmware/assets/bird-launcher-backdrop.png \
	kernel/rocknix/dev-release-tool.py \
	kernel/rocknix/build-bird-local-binary.sh \
	kernel/rocknix/build-stock-root-compat.sh \
	kernel/rocknix/build-stock-root-early-initramfs.sh; do
	copy_source "$SOURCE_PATH"
done
mkdir -p "$TEMPLATE/kernel/rocknix/tests"
cp -p "$SOURCE_ROOT/kernel/rocknix/tests/test-bird-local-binary.sh" \
	"$SOURCE_ROOT/kernel/rocknix/tests/test-dev-build-and-deploy.sh" \
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
		for INPUT in KERNEL KERNEL.fallback PortMaster.zip \
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

create_release() {
	RELEASE_ID=$1
	RELEASE_ROOT=$BIRD/bird-releases/$RELEASE_ID
	mkdir -p "$RELEASE_ROOT/bird" "$RELEASE_ROOT/extlinux"
	printf 'kernel %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/KERNEL"
	printf 'fallback kernel %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/KERNEL.fallback"
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
	for NAME in bird-launcher bird-pidwait bird-powerstate bird-fixed-controls bird-mpv-controls; do
		printf '%s %s\n' "$NAME" "$RELEASE_ID" >"$RELEASE_ROOT/bird/$NAME"
		chmod 0755 "$RELEASE_ROOT/bird/$NAME"
	done
	printf 'frame contract %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/bird/boot-frame.contract"
	printf 'frame pixels %s\n' "$RELEASE_ID" >"$RELEASE_ROOT/bird/launcher-base.xrgb"
	find "$RELEASE_ROOT" -type f -exec chmod 0644 {} +
	chmod 0755 "$RELEASE_ROOT/post-flash.sh" "$RELEASE_ROOT/mount-storage.sh" \
		"$RELEASE_ROOT/bird/bird-launcher" "$RELEASE_ROOT/bird/bird-pidwait" \
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
	for NAME in bird-launcher bird-pidwait bird-powerstate bird-fixed-controls bird-mpv-controls; do
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
	printf 'top fallback kernel\n' >"$BIRD/KERNEL.fallback"
	printf 'top dtb\n' >"$BIRD/dtb.img"
	printf 'fallback selector\n' >"$BIRD/extlinux/extlinux.fallback.conf"
	printf 'previous selector\n' >"$BIRD/extlinux/extlinux.previous.conf"
	create_build_fixture one
	create_release prod-a
	select_release prod-a
	write_device_info "$WHOLE" "$DEVICE_INFO"
	COMMAND=$REPO/dev-build-and-deploy.sh
	BASE_BEFORE=$(tree_digest "$BIRD/bird-releases/prod-a")
	FALLBACK_SELECTOR_BEFORE=$(sha256 "$BIRD/extlinux/extlinux.fallback.conf")
	PREVIOUS_SELECTOR_BEFORE=$(sha256 "$BIRD/extlinux/extlinux.previous.conf")
	TOP_FALLBACK_BEFORE=$(sha256 "$BIRD/KERNEL.fallback")
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
	[ "$(sha256 "$BIRD/extlinux/extlinux.fallback.conf")" = "$FALLBACK_SELECTOR_BEFORE" ] || \
		fail "$CASE_NAME changed extlinux.fallback.conf"
	[ "$(sha256 "$BIRD/extlinux/extlinux.previous.conf")" = "$PREVIOUS_SELECTOR_BEFORE" ] || \
		fail "$CASE_NAME changed extlinux.previous.conf"
	[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$TOP_FALLBACK_BEFORE" ] || \
		fail "$CASE_NAME changed top-level KERNEL.fallback"
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

new_case first-changed
initialize_dev
[ "$(selector_release)" = dev-current ] || fail 'first invocation did not select dev-current'
grep -q '^activation[[:space:]]*complete$' "$BIRD/bird-dev/state.tsv"
grep -q '^Rebuilt groups: .*launcher' "$CASE_ROOT/initialize.out"
grep -q '^release[[:space:]]*dev-current$' "$BIRD/bird-releases/dev-current/deploy-manifest.tsv"
[ "$(cat "$BIRD/bird-releases/dev-current/.complete")" = \
	"$(sha256 "$BIRD/bird-releases/dev-current/deploy-manifest.tsv")" ] || fail 'dev completion marker is wrong'
grep -q '^RELEASE_ID=dev-current$' "$BIRD/bird-releases/dev-current/bird/supervisor.sh"
gzip -dc "$BIRD/bird-releases/dev-current/bird-initramfs.cpio.gz" | \
	grep -a -q 'BIRD_LOADER_RELEASE=dev-current'
[ "$(cat "$DATA/Bird/boot-state/releases/dev-current/attempts")" = 0 ]
assert_base_and_fallback_unchanged
[ -z "$(find "$BIRD/bird-releases/dev-current" -name '._*' -print -quit)" ]
pass 'first changed invocation is all-local and produces a verified dev-current'

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
[ "$(sha256 "$DEV/bird/bird-network.sh")" != "$RUNTIME_BEFORE" ]
[ "$(sha256 "$DEV/bird-initramfs.cpio.gz")" = "$INITRAMFS_BEFORE" ]
[ "$(sha256 "$DEV/bird/bird-launcher")" = "$LAUNCHER_BEFORE" ]
[ "$(sha256 "$DEV/KERNEL")" = "$KERNEL_BEFORE" ]
[ "$(sha256 "$DEV/dtb.img")" = "$DTB_BEFORE" ]
[ "$(sha256 "$DEV/deploy-manifest.tsv")" != "$MANIFEST_BEFORE" ]
[ "$(sha256 "$DEV/.complete")" != "$COMPLETE_BEFORE" ]
assert_base_and_fallback_unchanged
pass 'runtime-only change preserves initramfs, launcher, kernel, and DTB'

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
	fail 'actual enlarged output was not included in the space gate'
fi
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

# 22. Both process-lifetime release authorities are specialized to dev-current.
new_case specialized-authorities
initialize_dev
grep -q '^RELEASE_ID=dev-current$' "$BIRD/bird-releases/dev-current/bird/supervisor.sh"
gzip -dc "$BIRD/bird-releases/dev-current/bird-initramfs.cpio.gz" | \
	grep -a -q 'BIRD_LOADER_RELEASE=dev-current'
run_dev --status >"$CASE_ROOT/status.out"
grep -q '^selector-kind[[:space:]]*development$' "$CASE_ROOT/status.out"
grep -q '^dev-current-verifies[[:space:]]*yes$' "$CASE_ROOT/status.out"
assert_base_and_fallback_unchanged
pass 'early loader and final supervisor both name dev-current'

printf 'PASS: %s dev-current host transaction cases\n' "$PASS_COUNT"
