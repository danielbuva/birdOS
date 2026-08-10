#!/bin/sh
# Repack the accepted Bird SYSTEM with only the deterministic source-built
# Linux 7.0.11 module tree substituted. This is a host artifact gate only.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
DOCKERFILE=$ROOT/kernel/rocknix/Dockerfile.hermetic-system
INVENTORY=$ROOT/kernel/rocknix/inventory-rootfs.py
VERIFY=$ROOT/kernel/rocknix/verify-source-kernel-system-delta.py
SYSTEM_SOURCE=${SYSTEM_SOURCE:-}
SYSTEM_SHA=${SYSTEM_SHA:-214ae075864fbe848f0fc6c31d4bec68778a111efb2ed1de78366446348d2af4}
SYSTEM_BYTES=${SYSTEM_BYTES:-1211060224}
SOURCE_BUILD=${SOURCE_BUILD:-$ROOT/kernel/work/rocknix-source-reference/build}
MODULES=${MODULES:-$SOURCE_BUILD/modules.tar.xz}
MODULES_SHA=${MODULES_SHA:-7267770aecb39069bbd5275b4538a9bb666e906cdabc844b275652603e1ad52e}
JOYPAD=${JOYPAD:-$SOURCE_BUILD/rocknix-singleadc-joypad.ko}
JOYPAD_SHA=${JOYPAD_SHA:-fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05}
MKFS_TIME=1782889443
OUTPUT=

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
file_bytes() { stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"; }

usage() {
	printf '%s\n' 'Usage: build-source-kernel-system.sh --build OUTPUT'
}

[ "$#" -gt 0 ] || { usage >&2; exit 2; }
while [ "$#" -gt 0 ]; do
	case "$1" in
		--build)
			[ "$#" -ge 2 ] || fail '--build requires OUTPUT'
			[ -z "$OUTPUT" ] || fail 'output specified more than once'
			OUTPUT=$2
			shift 2
			;;
		--help) usage; exit 0 ;;
		*) fail "unknown argument: $1" ;;
	esac
done

[ -n "$OUTPUT" ] || fail '--build OUTPUT is required'
case "$OUTPUT" in /*) ;; *) fail 'OUTPUT must be absolute' ;; esac
[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || fail 'OUTPUT already exists'
[ -n "$SYSTEM_SOURCE" ] || fail 'SYSTEM_SOURCE is required'
for INPUT in "$SYSTEM_SOURCE" "$MODULES" "$JOYPAD" "$DOCKERFILE" "$INVENTORY" "$VERIFY"; do
	[ -f "$INPUT" ] && [ ! -L "$INPUT" ] || fail "input missing or unsafe: $INPUT"
done
[ "$(file_bytes "$SYSTEM_SOURCE")" = "$SYSTEM_BYTES" ] || fail 'accepted SYSTEM size changed'
[ "$(sha256 "$SYSTEM_SOURCE")" = "$SYSTEM_SHA" ] || fail 'accepted SYSTEM digest changed'
[ "$(sha256 "$MODULES")" = "$MODULES_SHA" ] || fail 'source module archive digest changed'
[ "$(sha256 "$JOYPAD")" = "$JOYPAD_SHA" ] || fail 'source joypad module digest changed'
command -v docker >/dev/null 2>&1 || fail 'docker is required'
docker info >/dev/null 2>&1 || fail 'Docker engine is not running'

RECIPE_SHA=$(cat "$DOCKERFILE" "$INVENTORY" "$VERIFY" | shasum -a 256 | awk '{print $1}')
IMAGE=bird-source-kernel-system:$RECIPE_SHA
docker build --platform linux/arm64 --pull=false --quiet \
	-f "$DOCKERFILE" -t "$IMAGE" "$ROOT" >/dev/null
TOOLCHAIN=$(docker run --rm --platform linux/arm64 --entrypoint /bin/sh "$IMAGE" -ec '
printf "mksquashfs\t"; sha256sum /usr/bin/mksquashfs | cut -d" " -f1
printf "unsquashfs\t"; sha256sum /usr/bin/unsquashfs | cut -d" " -f1
printf "python3\t"; sha256sum /usr/bin/python3.11 | cut -d" " -f1
printf "squashfs-tools\t"; dpkg-query -W -f="\${Version}\n" squashfs-tools
')
EXPECTED_TOOLCHAIN='mksquashfs	82f6a73c4ade40a9c0c58215fb576368cff385458d9c3364ea40cd60b77445e5
unsquashfs	cb10af7fcbaf1eba05976b86ac0310e3df1ad57eb5e7e3af37ef2fae959087fa
python3	304aa87a76ebb13fd22d253ac157f14980ff2cdb23e6274f3b045571405e07dc
squashfs-tools	1:4.5.1-1'
[ "$TOOLCHAIN" = "$EXPECTED_TOOLCHAIN" ] || fail 'hermetic SYSTEM toolchain changed'

PARENT=${OUTPUT%/*}
[ -d "$PARENT" ] && [ ! -L "$PARENT" ] || fail 'OUTPUT parent is unsafe'
STAGE=$(mktemp -d "$PARENT/.bird-source-kernel-system.XXXXXX")
cleanup() { rm -rf -- "$STAGE"; }
trap cleanup EXIT HUP INT TERM
mkdir "$STAGE/run-a" "$STAGE/run-b"

run_build() {
	RUN=$1
	docker run --rm --platform linux/arm64 \
		-v "$SYSTEM_SOURCE:/input/SYSTEM:ro" \
		-v "$MODULES:/input/modules.tar.xz:ro" \
		-v "$JOYPAD:/input/rocknix-singleadc-joypad.ko:ro" \
		-v "$INVENTORY:/usr/local/libexec/inventory-rootfs.py:ro" \
		-v "$VERIFY:/usr/local/libexec/verify-source-kernel-system-delta.py:ro" \
		-v "$RUN:/output" -e BIRD_SYSTEM_MKFS_TIME="$MKFS_TIME" \
		"$IMAGE" '
rm -rf /work && mkdir -p /work/source /work/repacked /work/source-modules
unsquashfs -no-progress -d /work/source /input/SYSTEM >/output/unsquashfs-input.log
/usr/local/libexec/inventory-rootfs.py /work/source >/output/input-inventory.tsv
module_base=/work/source/usr/lib/kernel-overlays/base
module_tree=$module_base/lib/modules/7.0.11
test -d "$module_tree" && test ! -L "$module_tree"
touch -r "$module_base" /work/module-base.timestamp
touch -r "$module_base/lib" /work/module-lib.timestamp
touch -r "$module_base/lib/modules" /work/modules-parent.timestamp
rm -rf "$module_tree"
python3 - "$module_base" <<"PY"
import pathlib
import sys
import tarfile

target = pathlib.Path(sys.argv[1]).resolve()
with tarfile.open("/input/modules.tar.xz", "r:xz") as archive:
    for member in archive.getmembers():
        path = pathlib.PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit("unsafe module archive path")
        if not (member.isdir() or member.isfile()):
            raise SystemExit("unsafe module archive node")
    archive.extractall(target)
PY
mkdir -p "$module_tree/rocknix-joypad"
install -o 0 -g 0 -m 0644 /input/rocknix-singleadc-joypad.ko \
  "$module_tree/rocknix-joypad/rocknix-singleadc-joypad.ko"
touch -d @1784617200 "$module_tree/rocknix-joypad" \
  "$module_tree/rocknix-joypad/rocknix-singleadc-joypad.ko"
touch -d @1784617200 "$module_tree"
touch -r /work/module-lib.timestamp "$module_base/lib"
touch -r /work/modules-parent.timestamp "$module_base/lib/modules"
touch -r /work/module-base.timestamp "$module_base"
mkdir -p /work/source-modules/lib/modules
cp -a "$module_tree" /work/source-modules/lib/modules/7.0.11
touch -d @1784617200 /work/source-modules/lib /work/source-modules/lib/modules
/usr/local/libexec/inventory-rootfs.py /work/source-modules >/output/source-modules-inventory.tsv
/usr/local/libexec/inventory-rootfs.py /work/source >/output/policy-inventory.tsv
python3 /usr/local/libexec/verify-source-kernel-system-delta.py \
  /output/input-inventory.tsv /output/policy-inventory.tsv \
  /output/source-modules-inventory.tsv >/output/policy-verification.tsv
mksquashfs /work/source /output/SYSTEM -noappend -no-progress -processors 1 \
  -no-xattrs -comp zstd -Xcompression-level 19 -b 1048576 \
  -mkfs-time "$BIRD_SYSTEM_MKFS_TIME" >/output/mksquashfs.log
unsquashfs -no-progress -d /work/repacked /output/SYSTEM >/output/unsquashfs-output.log
/usr/local/libexec/inventory-rootfs.py /work/repacked >/output/output-inventory.tsv
if ! cmp /output/policy-inventory.tsv /output/output-inventory.tsv; then
  diff -u /output/policy-inventory.tsv /output/output-inventory.tsv \
    >/output/inventory.diff || true
  head -40 /output/inventory.diff >&2
  exit 1
fi
'
}

run_build "$STAGE/run-a"
run_build "$STAGE/run-b"
for FILE in SYSTEM input-inventory.tsv policy-inventory.tsv output-inventory.tsv \
	source-modules-inventory.tsv policy-verification.tsv; do
	cmp "$STAGE/run-a/$FILE" "$STAGE/run-b/$FILE" || fail "isolated source SYSTEM $FILE differs"
done
[ "$(sha256 "$SYSTEM_SOURCE")" = "$SYSTEM_SHA" ] || fail 'accepted SYSTEM changed during build'

mkdir "$STAGE/final"
for FILE in SYSTEM input-inventory.tsv policy-inventory.tsv output-inventory.tsv \
	source-modules-inventory.tsv policy-verification.tsv; do
	cp "$STAGE/run-a/$FILE" "$STAGE/final/$FILE"
done
printf '%s\n' "$TOOLCHAIN" >"$STAGE/final/toolchain.tsv"
{
	printf 'schema\tbird-source-kernel-system-v1\n'
	printf 'input-system-sha256\t%s\n' "$SYSTEM_SHA"
	printf 'source-modules-sha256\t%s\n' "$MODULES_SHA"
	printf 'source-joypad-sha256\t%s\n' "$JOYPAD_SHA"
	printf 'toolchain-recipe-sha256\t%s\n' "$RECIPE_SHA"
	printf 'container-image-id\t%s\n' "$(docker image inspect --format '{{.Id}}' "$IMAGE")"
	printf 'output-system-sha256\t%s\n' "$(sha256 "$STAGE/final/SYSTEM")"
	printf 'output-system-bytes\t%s\n' "$(file_bytes "$STAGE/final/SYSTEM")"
	printf 'output-inventory-sha256\t%s\n' "$(sha256 "$STAGE/final/output-inventory.tsv")"
} >"$STAGE/final/parity.tsv"

mv "$STAGE/final" "$OUTPUT"
trap - EXIT HUP INT TERM
rm -rf -- "$STAGE"
printf 'Source-kernel SYSTEM gate passed: %s\n' "$OUTPUT"
cat "$OUTPUT/parity.tsv"
