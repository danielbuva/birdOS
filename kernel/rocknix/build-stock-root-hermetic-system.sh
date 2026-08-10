#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
DOCKERFILE=$ROOT/kernel/rocknix/Dockerfile.hermetic-system
INVENTORY_SOURCE=$ROOT/kernel/rocknix/inventory-rootfs.py
MASK_POLICY_SOURCE=$ROOT/kernel/rocknix/hermetic-system-masks.tsv
MASK_VERIFY_SOURCE=$ROOT/kernel/rocknix/verify-system-mask-delta.py
OVERRIDE_POLICY_SOURCE=$ROOT/kernel/rocknix/hermetic-system-overrides.tsv
FIXED_VERIFY_SOURCE=$ROOT/kernel/rocknix/verify-system-fixed-delta.py
STOCK_ROOT_SOURCE=$ROOT/kernel/rocknix/stock-root
SYSTEM_SOURCE=${SYSTEM_SOURCE:-/Volumes/BIRD-DATA/MUOS/runtime/ROCKNIX-SYSTEM}
SYSTEM_SHA=${SYSTEM_SHA:-6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac}
SYSTEM_BYTES=${SYSTEM_BYTES:-1206476800}
SYSTEM_MKFS_TIME=${SYSTEM_MKFS_TIME:-1782889443}
OUTPUT=
MODE=

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage: build-stock-root-hermetic-system.sh --parity OUTPUT
       build-stock-root-hermetic-system.sh --mask-policy OUTPUT
       build-stock-root-hermetic-system.sh --fixed-policy OUTPUT

Build the shipping ROCKNIX SYSTEM twice in isolated containers. The command
requires byte-identical repacks and complete effective-tree identity with the
shipping input. It never deploys or writes to the card.

--mask-policy additionally bakes the fixed, reviewed systemd masks into both
isolated builds and proves that no undeclared filesystem node changed.

--fixed-policy also bakes the exact reviewed Bird service/config replacements
into both builds and proves the combined mask/file delta.
EOF
}

[ "$#" -gt 0 ] || { usage >&2; exit 2; }
while [ "$#" -gt 0 ]; do
	case "$1" in
		--parity)
			[ "$#" -ge 2 ] || fail '--parity requires OUTPUT'
			[ -z "$OUTPUT" ] || fail 'output specified more than once'
			MODE=parity
			OUTPUT=$2
			shift 2
			;;
		--mask-policy)
			[ "$#" -ge 2 ] || fail '--mask-policy requires OUTPUT'
			[ -z "$OUTPUT" ] || fail 'output specified more than once'
			MODE=mask-policy
			OUTPUT=$2
			shift 2
			;;
		--fixed-policy)
			[ "$#" -ge 2 ] || fail '--fixed-policy requires OUTPUT'
			[ -z "$OUTPUT" ] || fail 'output specified more than once'
			MODE=fixed-policy
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

[ -n "$OUTPUT" ] || fail '--parity, --mask-policy or --fixed-policy OUTPUT is required'
case "$OUTPUT" in /*) ;; *) fail 'OUTPUT must be absolute' ;; esac
[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || fail 'OUTPUT already exists'
[ -f "$SYSTEM_SOURCE" ] && [ ! -L "$SYSTEM_SOURCE" ] || fail 'SYSTEM input must be a regular non-symlink file'
[ -f "$DOCKERFILE" ] && [ ! -L "$DOCKERFILE" ] || fail 'toolchain Dockerfile missing or unsafe'
[ -f "$INVENTORY_SOURCE" ] && [ ! -L "$INVENTORY_SOURCE" ] || fail 'inventory source missing or unsafe'
[ -f "$MASK_POLICY_SOURCE" ] && [ ! -L "$MASK_POLICY_SOURCE" ] || fail 'mask policy missing or unsafe'
[ -f "$MASK_VERIFY_SOURCE" ] && [ ! -L "$MASK_VERIFY_SOURCE" ] || fail 'mask verifier missing or unsafe'
[ -f "$OVERRIDE_POLICY_SOURCE" ] && [ ! -L "$OVERRIDE_POLICY_SOURCE" ] || fail 'fixed-file policy missing or unsafe'
[ -f "$FIXED_VERIFY_SOURCE" ] && [ ! -L "$FIXED_VERIFY_SOURCE" ] || fail 'fixed-policy verifier missing or unsafe'
[ -d "$STOCK_ROOT_SOURCE" ] && [ ! -L "$STOCK_ROOT_SOURCE" ] || fail 'stock-root source missing or unsafe'
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

MASK_COUNT=$(awk -F '\t' '
	function safe(path, n, part, i) {
		if (path !~ /^[A-Za-z0-9._@\/-]+$/ || substr(path, 1, 1) == "/") return 0
		n=split(path, part, "/")
		for (i=1; i<=n; i++) if (part[i] == "" || part[i] == "." || part[i] == "..") return 0
		return 1
	}
	NF != 2 || $1 != "mask" || $2 !~ /^usr\/lib\/systemd\/system\// ||
		!safe($2) || seen[$2]++ {exit 1}
	{count++}
	END {if (count == 0) exit 1; print count}
' "$MASK_POLICY_SOURCE") || fail 'mask policy is malformed'
[ "$MASK_COUNT" -eq 16 ] || fail 'mask policy target count changed'

OVERRIDE_COUNT=$(awk -F '\t' '
	function safe(path, nested, n, part, i) {
		if (path !~ /^[A-Za-z0-9._@\/-]+$/ || substr(path, 1, 1) == "/") return 0
		n=split(path, part, "/")
		if (!nested && n != 1) return 0
		for (i=1; i<=n; i++) if (part[i] == "" || part[i] == "." || part[i] == "..") return 0
		return 1
	}
	NF != 5 || $1 != "file" || !safe($2, 0) || !safe($3, 1) ||
		$4 != "0644" || $5 !~ /^[0-9a-f]{64}$/ || source[$2]++ || target[$3]++ {exit 1}
	{count++}
	END {if (count == 0) exit 1; print count}
' "$OVERRIDE_POLICY_SOURCE") || fail 'fixed-file policy is malformed'
[ "$OVERRIDE_COUNT" -eq 14 ] || fail 'fixed-file policy target count changed'
while IFS="$(printf '\t')" read -r KIND SOURCE_NAME TARGET MODE_BITS SOURCE_SHA; do
	[ "$KIND" = file ] || fail 'fixed-file policy kind changed'
	SOURCE_PATH=$STOCK_ROOT_SOURCE/$SOURCE_NAME
	[ -f "$SOURCE_PATH" ] && [ ! -L "$SOURCE_PATH" ] || fail "fixed-file source missing or unsafe: $SOURCE_NAME"
	[ "$(sha256 "$SOURCE_PATH")" = "$SOURCE_SHA" ] || fail "fixed-file source digest changed: $SOURCE_NAME"
done <"$OVERRIDE_POLICY_SOURCE"

SOURCE_BEFORE=$SYSTEM_SHA
RECIPE_SHA=$({
	cat "$DOCKERFILE" "$INVENTORY_SOURCE" "$MASK_POLICY_SOURCE" \
		"$MASK_VERIFY_SOURCE" "$OVERRIDE_POLICY_SOURCE" "$FIXED_VERIFY_SOURCE"
	while IFS="$(printf '\t')" read -r KIND SOURCE_NAME TARGET MODE_BITS SOURCE_SHA; do
		cat "$STOCK_ROOT_SOURCE/$SOURCE_NAME"
	done <"$OVERRIDE_POLICY_SOURCE"
} | shasum -a 256 | awk '{print $1}')
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
		-v "$MASK_POLICY_SOURCE:/input/masks.tsv:ro" \
		-v "$MASK_VERIFY_SOURCE:/usr/local/libexec/verify-system-mask-delta.py:ro" \
		-v "$OVERRIDE_POLICY_SOURCE:/input/overrides.tsv:ro" \
		-v "$FIXED_VERIFY_SOURCE:/usr/local/libexec/verify-system-fixed-delta.py:ro" \
		-v "$STOCK_ROOT_SOURCE:/input/stock-root:ro" \
		-v "$RUN_OUTPUT:/output" \
		-e BIRD_SYSTEM_MKFS_TIME="$SYSTEM_MKFS_TIME" \
		-e BIRD_SYSTEM_POLICY="$MODE" \
		"$IMAGE" '
rm -rf /work && mkdir -p /work/source /work/repacked
unsquashfs -no-progress -d /work/source /input/SYSTEM >/output/unsquashfs-input.log
/usr/local/libexec/inventory-rootfs.py /work/source > /output/input-inventory.tsv
if [ "$BIRD_SYSTEM_POLICY" = mask-policy ] || [ "$BIRD_SYSTEM_POLICY" = fixed-policy ]; then
  TAB=$(printf "\t")
  touch -r /work/source/usr/lib/systemd/system /work/systemd-parent.timestamp
  while IFS="$TAB" read -r kind target; do
    [ "$kind" = mask ] && [ -n "$target" ] || exit 1
    [ -e "/work/source/$target" ] || [ -L "/work/source/$target" ] || exit 1
    rm -f "/work/source/$target"
    ln -s /dev/null "/work/source/$target"
    touch -h -d "@$BIRD_SYSTEM_MKFS_TIME" "/work/source/$target"
  done < /input/masks.tsv
  touch -r /work/systemd-parent.timestamp /work/source/usr/lib/systemd/system
fi
if [ "$BIRD_SYSTEM_POLICY" = fixed-policy ]; then
  TAB=$(printf "\t")
  touch -r /work/source/usr/lib/systemd/system /work/systemd-parent.timestamp
  touch -r /work/source/etc/systemd /work/etc-systemd-parent.timestamp
  while IFS="$TAB" read -r kind source target mode digest; do
    [ "$kind" = file ] && [ -n "$source" ] && [ -n "$target" ] || exit 1
    source_path=/input/stock-root/$source
    target_path=/work/source/$target
    [ -f "$source_path" ] && [ ! -L "$source_path" ] || exit 1
    [ "$(sha256sum "$source_path" | cut -d" " -f1)" = "$digest" ] || exit 1
    [ -e "$target_path" ] || [ -L "$target_path" ] || exit 1
    rm -f "$target_path"
    install -o 0 -g 0 -m "$mode" "$source_path" "$target_path"
    touch -d "@$BIRD_SYSTEM_MKFS_TIME" "$target_path"
  done < /input/overrides.tsv
  touch -r /work/systemd-parent.timestamp /work/source/usr/lib/systemd/system
  touch -r /work/etc-systemd-parent.timestamp /work/source/etc/systemd
fi
/usr/local/libexec/inventory-rootfs.py /work/source > /output/policy-inventory.tsv
if [ "$BIRD_SYSTEM_POLICY" = mask-policy ]; then
  python3 /usr/local/libexec/verify-system-mask-delta.py \
    /output/input-inventory.tsv /output/policy-inventory.tsv /input/masks.tsv \
    > /output/policy-verification.tsv
elif [ "$BIRD_SYSTEM_POLICY" = fixed-policy ]; then
  python3 /usr/local/libexec/verify-system-fixed-delta.py \
    /output/input-inventory.tsv /output/policy-inventory.tsv /input/masks.tsv \
    /input/overrides.tsv > /output/policy-verification.tsv
else
  cmp /output/input-inventory.tsv /output/policy-inventory.tsv
  printf "verified-mask-targets\t0\n" > /output/policy-verification.tsv
fi
mksquashfs /work/source /output/SYSTEM \
  -noappend -no-progress -processors 1 -no-xattrs \
  -comp zstd -Xcompression-level 19 -b 1048576 \
  -mkfs-time "$BIRD_SYSTEM_MKFS_TIME" > /output/mksquashfs.log
unsquashfs -no-progress -d /work/repacked /output/SYSTEM >/output/unsquashfs-output.log
/usr/local/libexec/inventory-rootfs.py /work/repacked > /output/output-inventory.tsv
cmp /output/policy-inventory.tsv /output/output-inventory.tsv
unsquashfs -s /output/SYSTEM > /output/superblock.txt
'
}

run_build "$STAGE/run-a"
run_build "$STAGE/run-b"

cmp "$STAGE/run-a/SYSTEM" "$STAGE/run-b/SYSTEM" || fail 'isolated SYSTEM repacks differ'
cmp "$STAGE/run-a/input-inventory.tsv" "$STAGE/run-b/input-inventory.tsv" || fail 'input inventories differ'
cmp "$STAGE/run-a/policy-inventory.tsv" "$STAGE/run-b/policy-inventory.tsv" || fail 'policy inventories differ'
cmp "$STAGE/run-a/output-inventory.tsv" "$STAGE/run-b/output-inventory.tsv" || fail 'output inventories differ'

[ "$(sha256 "$SYSTEM_SOURCE")" = "$SOURCE_BEFORE" ] || fail 'SYSTEM input changed during build'
mkdir "$STAGE/final"
cp "$STAGE/run-a/SYSTEM" "$STAGE/final/SYSTEM"
cp "$STAGE/run-a/input-inventory.tsv" "$STAGE/final/shipping-inventory.tsv"
cp "$STAGE/run-a/policy-inventory.tsv" "$STAGE/final/policy-inventory.tsv"
cp "$STAGE/run-a/output-inventory.tsv" "$STAGE/final/repacked-inventory.tsv"
cp "$STAGE/run-a/policy-verification.tsv" "$STAGE/final/policy-verification.tsv"
cp "$MASK_POLICY_SOURCE" "$STAGE/final/hermetic-system-masks.tsv"
cp "$OVERRIDE_POLICY_SOURCE" "$STAGE/final/hermetic-system-overrides.tsv"
cp "$STAGE/run-a/superblock.txt" "$STAGE/final/superblock.txt"
printf '%s\n' "$TOOLCHAIN" >"$STAGE/final/toolchain.tsv"
{
	printf 'schema\tbird-hermetic-system-%s-v1\n' "$MODE"
	printf 'input-sha256\t%s\n' "$SYSTEM_SHA"
	printf 'input-bytes\t%s\n' "$SYSTEM_BYTES"
	printf 'mkfs-time\t%s\n' "$SYSTEM_MKFS_TIME"
	printf 'toolchain-recipe-sha256\t%s\n' "$RECIPE_SHA"
	printf 'container-image-id\t%s\n' "$(docker image inspect --format '{{.Id}}' "$IMAGE")"
	printf 'output-sha256\t%s\n' "$(sha256 "$STAGE/final/SYSTEM")"
	printf 'output-bytes\t%s\n' "$(file_bytes "$STAGE/final/SYSTEM")"
	printf 'inventory-sha256\t%s\n' "$(sha256 "$STAGE/final/shipping-inventory.tsv")"
	printf 'policy-inventory-sha256\t%s\n' "$(sha256 "$STAGE/final/policy-inventory.tsv")"
	printf 'mask-policy-sha256\t%s\n' "$(sha256 "$MASK_POLICY_SOURCE")"
	printf 'mask-targets\t%s\n' "$MASK_COUNT"
	printf 'fixed-file-targets\t%s\n' "$OVERRIDE_COUNT"
} >"$STAGE/final/parity.tsv"

mv "$STAGE/final" "$OUTPUT"
trap - EXIT HUP INT TERM
rm -rf -- "$STAGE"
printf 'Hermetic SYSTEM parity passed: %s\n' "$OUTPUT"
cat "$OUTPUT/parity.tsv"
