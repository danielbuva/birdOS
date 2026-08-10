#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
DOCKERFILE=$ROOT/kernel/rocknix/Dockerfile.hermetic-system
INVENTORY_SOURCE=$ROOT/kernel/rocknix/inventory-rootfs.py
SYSTEM_SOURCE=${SYSTEM_SOURCE:-/Volumes/BIRD-DATA/MUOS/runtime/ROCKNIX-SYSTEM}
SYSTEM_SHA=${SYSTEM_SHA:-6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac}
SYSTEM_BYTES=${SYSTEM_BYTES:-1206476800}
SYSTEM_MKFS_TIME=${SYSTEM_MKFS_TIME:-1782889443}
OUTPUT=

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage: build-stock-root-hermetic-system.sh --parity OUTPUT

Build the shipping ROCKNIX SYSTEM twice in isolated containers. The command
requires byte-identical repacks and complete effective-tree identity with the
shipping input. It never deploys or writes to the card.
EOF
}

[ "$#" -gt 0 ] || { usage >&2; exit 2; }
while [ "$#" -gt 0 ]; do
	case "$1" in
		--parity)
			[ "$#" -ge 2 ] || fail '--parity requires OUTPUT'
			[ -z "$OUTPUT" ] || fail 'output specified more than once'
			OUTPUT=$2
			shift 2
			;;
		--help)
			usage
			exit 0
			;;
		*) fail "unknown argument: $1" ;;
	esac
done

[ -n "$OUTPUT" ] || fail '--parity OUTPUT is required'
case "$OUTPUT" in /*) ;; *) fail 'OUTPUT must be absolute' ;; esac
[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || fail 'OUTPUT already exists'
[ -f "$SYSTEM_SOURCE" ] && [ ! -L "$SYSTEM_SOURCE" ] || fail 'SYSTEM input must be a regular non-symlink file'
[ -f "$DOCKERFILE" ] && [ ! -L "$DOCKERFILE" ] || fail 'toolchain Dockerfile missing or unsafe'
[ -f "$INVENTORY_SOURCE" ] && [ ! -L "$INVENTORY_SOURCE" ] || fail 'inventory source missing or unsafe'
command -v docker >/dev/null 2>&1 || fail 'docker is required'
docker info >/dev/null 2>&1 || fail 'Docker engine is not running'

case "$SYSTEM_SHA" in *[!0-9a-f]*|'') fail 'SYSTEM_SHA must be lowercase SHA-256' ;; esac
[ "${#SYSTEM_SHA}" -eq 64 ] || fail 'SYSTEM_SHA must be lowercase SHA-256'
case "$SYSTEM_BYTES" in *[!0-9]*|'') fail 'SYSTEM_BYTES must be decimal' ;; esac
case "$SYSTEM_MKFS_TIME" in *[!0-9]*|'') fail 'SYSTEM_MKFS_TIME must be decimal' ;; esac

file_bytes() { stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

[ "$(file_bytes "$SYSTEM_SOURCE")" = "$SYSTEM_BYTES" ] || fail 'SYSTEM input size changed'
[ "$(sha256 "$SYSTEM_SOURCE")" = "$SYSTEM_SHA" ] || fail 'SYSTEM input digest changed'

SOURCE_BEFORE=$SYSTEM_SHA
RECIPE_SHA=$(cat "$DOCKERFILE" "$INVENTORY_SOURCE" | shasum -a 256 | awk '{print $1}')
IMAGE="bird-hermetic-system:${RECIPE_SHA}"

docker build --platform linux/arm64 --pull=false --quiet \
	-f "$DOCKERFILE" -t "$IMAGE" "$ROOT" >/dev/null

TOOLCHAIN=$(docker run --rm --platform linux/arm64 --entrypoint /bin/sh "$IMAGE" -ec '
printf "mksquashfs\t"; sha256sum /usr/bin/mksquashfs | cut -d" " -f1
printf "unsquashfs\t"; sha256sum /usr/bin/unsquashfs | cut -d" " -f1
printf "python3\t"; sha256sum /usr/bin/python3.11 | cut -d" " -f1
printf "squashfs-tools\t"; dpkg-query -W -f="\${Version}\\n" squashfs-tools
')
EXPECTED_TOOLCHAIN='mksquashfs	82f6a73c4ade40a9c0c58215fb576368cff385458d9c3364ea40cd60b77445e5
unsquashfs	cb10af7fcbaf1eba05976b86ac0310e3df1ad57eb5e7e3af37ef2fae959087fa
python3	304aa87a76ebb13fd22d253ac157f14980ff2cdb23e6274f3b045571405e07dc
squashfs-tools	1:4.5.1-1'
[ "$TOOLCHAIN" = "$EXPECTED_TOOLCHAIN" ] || fail 'hermetic toolchain identity changed'

PARENT=${OUTPUT%/*}
[ -d "$PARENT" ] && [ ! -L "$PARENT" ] || fail 'OUTPUT parent must be an existing non-symlink directory'
STAGE=$(mktemp -d "$PARENT/.bird-hermetic-system.XXXXXX")
cleanup() { rm -rf -- "$STAGE"; }
trap cleanup EXIT HUP INT TERM

mkdir "$STAGE/run-a" "$STAGE/run-b"
run_build() {
	RUN_OUTPUT=$1
	docker run --rm --platform linux/arm64 \
		-v "$SYSTEM_SOURCE:/input/SYSTEM:ro" \
		-v "$RUN_OUTPUT:/output" \
		-e BIRD_SYSTEM_MKFS_TIME="$SYSTEM_MKFS_TIME" \
		"$IMAGE" '
rm -rf /work && mkdir -p /work/source /work/repacked
unsquashfs -no-progress -d /work/source /input/SYSTEM >/output/unsquashfs-input.log
/usr/local/libexec/inventory-rootfs.py /work/source > /output/input-inventory.tsv
mksquashfs /work/source /output/SYSTEM \
  -noappend -no-progress -processors 1 -no-xattrs \
  -comp zstd -Xcompression-level 19 -b 1048576 \
  -mkfs-time "$BIRD_SYSTEM_MKFS_TIME" > /output/mksquashfs.log
unsquashfs -no-progress -d /work/repacked /output/SYSTEM >/output/unsquashfs-output.log
/usr/local/libexec/inventory-rootfs.py /work/repacked > /output/output-inventory.tsv
cmp /output/input-inventory.tsv /output/output-inventory.tsv
unsquashfs -s /output/SYSTEM > /output/superblock.txt
'
}

run_build "$STAGE/run-a"
run_build "$STAGE/run-b"

cmp "$STAGE/run-a/SYSTEM" "$STAGE/run-b/SYSTEM" || fail 'isolated SYSTEM repacks differ'
cmp "$STAGE/run-a/input-inventory.tsv" "$STAGE/run-b/input-inventory.tsv" || fail 'input inventories differ'
cmp "$STAGE/run-a/output-inventory.tsv" "$STAGE/run-b/output-inventory.tsv" || fail 'output inventories differ'

[ "$(sha256 "$SYSTEM_SOURCE")" = "$SOURCE_BEFORE" ] || fail 'SYSTEM input changed during build'
mkdir "$STAGE/final"
cp "$STAGE/run-a/SYSTEM" "$STAGE/final/SYSTEM"
cp "$STAGE/run-a/input-inventory.tsv" "$STAGE/final/shipping-inventory.tsv"
cp "$STAGE/run-a/output-inventory.tsv" "$STAGE/final/repacked-inventory.tsv"
cp "$STAGE/run-a/superblock.txt" "$STAGE/final/superblock.txt"
printf '%s\n' "$TOOLCHAIN" >"$STAGE/final/toolchain.tsv"
{
	printf 'schema\tbird-hermetic-system-parity-v1\n'
	printf 'input-sha256\t%s\n' "$SYSTEM_SHA"
	printf 'input-bytes\t%s\n' "$SYSTEM_BYTES"
	printf 'mkfs-time\t%s\n' "$SYSTEM_MKFS_TIME"
	printf 'toolchain-recipe-sha256\t%s\n' "$RECIPE_SHA"
	printf 'container-image-id\t%s\n' "$(docker image inspect --format '{{.Id}}' "$IMAGE")"
	printf 'output-sha256\t%s\n' "$(sha256 "$STAGE/final/SYSTEM")"
	printf 'output-bytes\t%s\n' "$(file_bytes "$STAGE/final/SYSTEM")"
	printf 'inventory-sha256\t%s\n' "$(sha256 "$STAGE/final/shipping-inventory.tsv")"
} >"$STAGE/final/parity.tsv"

mv "$STAGE/final" "$OUTPUT"
trap - EXIT HUP INT TERM
rm -rf -- "$STAGE"
printf 'Hermetic SYSTEM parity passed: %s\n' "$OUTPUT"
cat "$OUTPUT/parity.tsv"
