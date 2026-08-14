#!/bin/sh
# Reproduce the shipping H700 DDR4 U-Boot and build the one-byte green-LED
# defconfig candidate. This is a host artifact builder; it never opens a card.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROCKNIX_SOURCE=${ROCKNIX_SOURCE:-$HOME/rocknix-distribution-20260701}
ROCKNIX_BUILD=${ROCKNIX_BUILD:-$ROCKNIX_SOURCE/build.ROCKNIX-H700.aarch64}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-uboot-green-20260701}
SHIPPING=${SHIPPING:-$ROOT/kernel/work/rocknix-system-exact-20260701/usr/share/bootloader/H700_DDR4_u-boot-sunxi-with-spl.bin}
BL31=${BL31:-$ROOT/kernel/work/rocknix-system-exact-20260701/usr/share/bootloader/bl31.bin}
FIT_TIMESTAMP_PATCHER=$ROOT/kernel/rocknix/patch-fit-root-timestamp.py
DOCKER=${DOCKER:-docker}
PYTHON=${PYTHON:-python3}

ROCKNIX_COMMIT=3e4ee5852e6ca5ea73a38369d2639fad2262648b
UBOOT_VERSION=v2026.01
SOURCE_DATE_EPOCH=1782880730
PACKAGE_REL=projects/ROCKNIX/devices/H700/packages/u-boot-DDR4
GCC_PACKAGE_REL=projects/ROCKNIX/packages/lang/gcc/package.mk
DEFCONFIG=anbernic_rg35xx_h700_lpddr4_defconfig
SOURCE_REL=sources/u-boot-DDR4/u-boot-DDR4-v2026.01.tar.gz
SOURCE_SHA=03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654
PACKAGE_SHA=07c3e190986d1c8f875b92465684a53329efde0427ace9425fe164c2e8ae0f7b
PATCH_SHA=596674be315fbb74f670cf04639f10ea2b5629fd9eb72d944084a04cd0e5fab5
GCC_PACKAGE_SHA=f1416c2f83be951ef2de9320369f05d6296ee171c822ada6491e91c9f53d7ffc
GCC_SOURCE_SHA=438fd996826b0c82485a29da03a72d71d6e3541a83ec702df4271f6fe025d24e
DEFCONFIG_SHA=24013855fefbe911cf664301940e8b6b514e4961ed414f324dae491f56d6bfe4
GREEN_SHA=cea8a54adaf9c55b22c767361bdc79aab4972b931df762b330d6359d73844295
SHIPPING_SHA=42c01f4524b45cba7c239cd940fc4e71eed7545901da201f27fed2193b7fdf45
BL31_SHA=431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673
DOCKER_IMAGE=ghcr.io/rocknix/rocknix-build@sha256:a360f7280ff4b87f2614dd6085336df287c3bc6f2fccd87c7f5673f5cef1daed

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

sha256_file() {
	shasum -a 256 "$1" | awk '{print $1}'
}

require_file() {
	[ -f "$1" ] && [ ! -L "$1" ] || fail "unsafe or missing input: $1"
}

require_hash() {
	ACTUAL=$(sha256_file "$1")
	[ "$ACTUAL" = "$2" ] || fail "checksum mismatch for $1: $ACTUAL"
}

require_tool() {
	[ -x "$1" ] || fail "missing executable toolchain input: $1"
	RESOLVED=$($PYTHON -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).resolve())' "$1")
	case "$RESOLVED" in
		"$TOOLCHAIN"/*) ;;
		*) fail "toolchain input resolves outside its read-only tree: $1" ;;
	esac
	[ -f "$RESOLVED" ] || fail "toolchain input does not resolve to a file: $1"
}

require_toolchain_file() {
	[ -e "$1" ] || [ -L "$1" ] || fail "missing toolchain input: $1"
	RESOLVED=$($PYTHON -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).resolve())' "$1")
	case "$RESOLVED" in
		"$TOOLCHAIN"/*) ;;
		*) fail "toolchain input resolves outside its read-only tree: $1" ;;
	esac
	[ -f "$RESOLVED" ] || fail "toolchain input does not resolve to a file: $1"
}

hash_toolchain_tree() {
	$PYTHON - "$TOOLCHAIN" "$1" <<'PY'
import hashlib
import os
import pathlib
import stat
import sys

authority = pathlib.Path(sys.argv[1]).resolve(strict=True)
tree = pathlib.Path(sys.argv[2]).resolve(strict=True)
try:
    tree.relative_to(authority)
except ValueError:
    raise SystemExit("compiler include tree resolves outside toolchain authority")
if not tree.is_dir():
    raise SystemExit("compiler include authority is not a directory")
digest = hashlib.sha256()
files = 0
total_bytes = 0
for path in sorted(tree.rglob("*"), key=lambda item: os.fsencode(item.relative_to(tree))):
    relative = os.fsencode(path.relative_to(tree))
    metadata = path.lstat()
    if stat.S_ISDIR(metadata.st_mode):
        digest.update(b"D\0" + relative + b"\0")
    elif stat.S_ISREG(metadata.st_mode):
        data = path.read_bytes()
        digest.update(b"F\0" + relative + b"\0")
        digest.update(str(len(data)).encode("ascii") + b"\0")
        digest.update(hashlib.sha256(data).digest())
        files += 1
        total_bytes += len(data)
    else:
        raise SystemExit(f"unsafe compiler include node: {path}")
print(files, total_bytes, digest.hexdigest())
PY
}

[ "$#" -eq 0 ] || fail 'this builder takes no positional arguments; use environment overrides'
command -v "$DOCKER" >/dev/null 2>&1 || fail 'Docker is required'
command -v "$PYTHON" >/dev/null 2>&1 || fail 'Python 3 is required'
[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || fail "output already exists: $OUTPUT"
[ -d "$ROCKNIX_SOURCE/.git" ] || fail "ROCKNIX source checkout missing: $ROCKNIX_SOURCE"
[ "$(git -C "$ROCKNIX_SOURCE" rev-parse HEAD)" = "$ROCKNIX_COMMIT" ] || \
	fail 'ROCKNIX source checkout is not at the pinned commit'
[ -z "$(git -C "$ROCKNIX_SOURCE" status --short --untracked-files=no)" ] || \
	fail 'ROCKNIX tracked source checkout is dirty'

SOURCE="$ROCKNIX_SOURCE/$SOURCE_REL"
PACKAGE="$ROCKNIX_SOURCE/$PACKAGE_REL/package.mk"
GCC_PACKAGE="$ROCKNIX_SOURCE/$GCC_PACKAGE_REL"
PATCH="$ROCKNIX_SOURCE/$PACKAGE_REL/patches/0001-Update-dram_sun50i_h616.c.patch"
UPSTREAM_DEFCONFIG="$ROCKNIX_SOURCE/$PACKAGE_REL/sources/configs/$DEFCONFIG"
require_file "$SOURCE"
require_hash "$SOURCE" "$SOURCE_SHA"
require_file "$PACKAGE"
require_hash "$PACKAGE" "$PACKAGE_SHA"
require_file "$GCC_PACKAGE"
require_hash "$GCC_PACKAGE" "$GCC_PACKAGE_SHA"
grep -Fqx 'PKG_VERSION="15.2.0"' "$GCC_PACKAGE" || \
	fail 'ROCKNIX GCC package version changed'
grep -Fqx "PKG_SHA256=\"$GCC_SOURCE_SHA\"" "$GCC_PACKAGE" || \
	fail 'ROCKNIX GCC source authority changed'
require_file "$PATCH"
require_hash "$PATCH" "$PATCH_SHA"
require_file "$UPSTREAM_DEFCONFIG"
require_hash "$UPSTREAM_DEFCONFIG" "$DEFCONFIG_SHA"
require_file "$SHIPPING"
require_hash "$SHIPPING" "$SHIPPING_SHA"
require_file "$BL31"
require_hash "$BL31" "$BL31_SHA"
require_file "$FIT_TIMESTAMP_PATCHER"

TOOLCHAIN="$ROCKNIX_BUILD/toolchain"
CONTAINER_TOOLCHAIN=/work/build.ROCKNIX-H700.aarch64/toolchain
CROSS_PREFIX=aarch64-rocknix-linux-gnu-
for TOOL in \
	bin/aarch64-rocknix-linux-gnu-gcc \
	bin/aarch64-rocknix-linux-gnu-gcc-15.2.0 \
	bin/aarch64-rocknix-linux-gnu-ld \
	bin/aarch64-rocknix-linux-gnu-as \
	bin/aarch64-rocknix-linux-gnu-ar \
	bin/aarch64-rocknix-linux-gnu-nm \
	bin/aarch64-rocknix-linux-gnu-strip \
	bin/aarch64-rocknix-linux-gnu-objcopy \
	bin/aarch64-rocknix-linux-gnu-objdump \
	bin/aarch64-rocknix-linux-gnu-readelf \
	bin/ccache \
	bin/host-gcc \
	bin/host-g++ \
	bin/make \
	bin/python \
	bin/python3; do
	require_tool "$TOOLCHAIN/$TOOL"
done
EXPECTED_CROSS_WRAPPER="$CONTAINER_TOOLCHAIN/bin/ccache $CONTAINER_TOOLCHAIN/bin/aarch64-rocknix-linux-gnu-gcc-15.2.0 \"\$@\""
grep -Fqx "$EXPECTED_CROSS_WRAPPER" "$TOOLCHAIN/bin/aarch64-rocknix-linux-gnu-gcc" || \
	fail 'ROCKNIX cross-compiler wrapper does not invoke the pinned compiler through ccache'
EXPECTED_HOST_WRAPPER="$CONTAINER_TOOLCHAIN/bin/ccache /usr/bin/gcc \"\$@\""
grep -Fqx "$EXPECTED_HOST_WRAPPER" "$TOOLCHAIN/bin/host-gcc" || \
	fail 'ROCKNIX host-compiler wrapper authority changed'
EXPECTED_HOST_CXX_WRAPPER="$CONTAINER_TOOLCHAIN/bin/ccache /usr/bin/g++ \"\$@\""
grep -Fqx "$EXPECTED_HOST_CXX_WRAPPER" "$TOOLCHAIN/bin/host-g++" || \
	fail 'ROCKNIX host-C++ wrapper authority changed'

IMAGE_ID=$($DOCKER image inspect "$DOCKER_IMAGE" --format '{{.Id}}' 2>/dev/null) || \
	fail "pinned ROCKNIX builder image is unavailable: $DOCKER_IMAGE"
[ "$IMAGE_ID" = sha256:a360f7280ff4b87f2614dd6085336df287c3bc6f2fccd87c7f5673f5cef1daed ] || \
	fail "pinned ROCKNIX builder image ID changed: $IMAGE_ID"

TOOLCHAIN_PROBE=$(
	"$DOCKER" run --rm --network none --read-only \
		--user "$(id -u):$(id -g)" \
		--tmpfs /tmp:rw,exec,nosuid,size=16m \
		-v "$TOOLCHAIN:$CONTAINER_TOOLCHAIN:ro" \
		-e CCACHE_DISABLE=1 \
		"$DOCKER_IMAGE" /bin/sh -eu -c '
TOOLCHAIN=/work/build.ROCKNIX-H700.aarch64/toolchain
GCC=$TOOLCHAIN/bin/aarch64-rocknix-linux-gnu-gcc-15.2.0
PATH=$TOOLCHAIN/bin:$PATH
export PATH
printf "gcc-version\t%s\n" "$("$GCC" -dumpfullversion -dumpversion)"
printf "cc1\t%s\n" "$("$GCC" -print-prog-name=cc1)"
printf "include\t%s\n" "$("$GCC" -print-file-name=include)"
printf "libgcc\t%s\n" "$("$GCC" -print-libgcc-file-name)"
for tool in gcc g++; do
  resolved=$(readlink -f "/usr/bin/$tool")
  digest=$(sha256sum "$resolved")
  digest=${digest%% *}
  printf "host-%s\t%s\t%s\n" "$tool" "$resolved" "$digest"
done'
) || fail 'pinned ROCKNIX cross-compiler preflight failed'
[ "$(printf '%s\n' "$TOOLCHAIN_PROBE" | wc -l | tr -d ' ')" -eq 6 ] || \
	fail 'pinned ROCKNIX toolchain probe inventory changed'
TOOLCHAIN_VERSION=$(printf '%s\n' "$TOOLCHAIN_PROBE" | awk -F '\t' '$1 == "gcc-version" { print $2 }')
[ "$TOOLCHAIN_VERSION" = 15.2.0 ] || \
	fail "ROCKNIX cross-compiler version changed: $TOOLCHAIN_VERSION"
CC1_CONTAINER=$(printf '%s\n' "$TOOLCHAIN_PROBE" | awk -F '\t' '$1 == "cc1" { print $2 }')
INCLUDE_CONTAINER=$(printf '%s\n' "$TOOLCHAIN_PROBE" | awk -F '\t' '$1 == "include" { print $2 }')
LIBGCC_CONTAINER=$(printf '%s\n' "$TOOLCHAIN_PROBE" | awk -F '\t' '$1 == "libgcc" { print $2 }')
HOST_GCC_CONTAINER=$(printf '%s\n' "$TOOLCHAIN_PROBE" | awk -F '\t' '$1 == "host-gcc" { print $2 }')
HOST_GCC_SHA=$(printf '%s\n' "$TOOLCHAIN_PROBE" | awk -F '\t' '$1 == "host-gcc" { print $3 }')
HOST_CXX_CONTAINER=$(printf '%s\n' "$TOOLCHAIN_PROBE" | awk -F '\t' '$1 == "host-g++" { print $2 }')
HOST_CXX_SHA=$(printf '%s\n' "$TOOLCHAIN_PROBE" | awk -F '\t' '$1 == "host-g++" { print $3 }')
for INTERNAL in "$CC1_CONTAINER" "$INCLUDE_CONTAINER" "$LIBGCC_CONTAINER"; do
	case "$INTERNAL" in
		"$CONTAINER_TOOLCHAIN"/*) ;;
		*) fail "compiler internal path is outside the toolchain: $INTERNAL" ;;
	esac
done
for HOST_TOOL in "$HOST_GCC_CONTAINER" "$HOST_CXX_CONTAINER"; do
	case "$HOST_TOOL" in
		/usr/*) ;;
		*) fail "host compiler resolves outside pinned image system tree: $HOST_TOOL" ;;
	esac
done
for HOST_SHA in "$HOST_GCC_SHA" "$HOST_CXX_SHA"; do
	case "$HOST_SHA" in
		*[!0-9a-f]*|'') fail 'host compiler hash is malformed' ;;
	esac
	[ "${#HOST_SHA}" -eq 64 ] || fail 'host compiler hash length changed'
done
CC1_REL=${CC1_CONTAINER#"$CONTAINER_TOOLCHAIN/"}
INCLUDE_REL=${INCLUDE_CONTAINER#"$CONTAINER_TOOLCHAIN/"}
LIBGCC_REL=${LIBGCC_CONTAINER#"$CONTAINER_TOOLCHAIN/"}
require_tool "$TOOLCHAIN/$CC1_REL"
require_toolchain_file "$TOOLCHAIN/$LIBGCC_REL"
[ -d "$TOOLCHAIN/$INCLUDE_REL" ] && [ ! -L "$TOOLCHAIN/$INCLUDE_REL" ] || \
	fail 'compiler internal include tree authority changed'
INCLUDE_AUTHORITY=$(hash_toolchain_tree "$TOOLCHAIN/$INCLUDE_REL")
set -- $INCLUDE_AUTHORITY
[ "$#" -eq 3 ] || fail 'compiler internal include inventory is malformed'
INCLUDE_FILES=$1
INCLUDE_BYTES=$2
INCLUDE_SHA=$3

WORK=$(mktemp -d "${TMPDIR:-/tmp}/bird-uboot-green.XXXXXX")
cleanup() {
	rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM

mkdir "$WORK/input" "$WORK/output"
cp -fp "$SOURCE" "$WORK/input/u-boot.tar.gz"
cp -fp "$PATCH" "$WORK/input/rocknix.patch"
cp -fp "$UPSTREAM_DEFCONFIG" "$WORK/input/$DEFCONFIG"
cp -fp "$BL31" "$WORK/input/bl31.bin"
cp -fp "$FIT_TIMESTAMP_PATCHER" "$WORK/input/patch-fit-root-timestamp.py"
"$PYTHON" "$ROOT/kernel/rocknix/transform-uboot-status-led.py" \
	"$WORK/input/$DEFCONFIG" "$WORK/input/green.defconfig"
require_hash "$WORK/input/green.defconfig" "$GREEN_SHA"

TOOLCHAIN_AUTHORITY="$WORK/input/toolchain-authority.tsv"
(
	printf 'schema\tbird-rocknix-uboot-toolchain-v1\n'
	printf 'docker-image\t%s\n' "$DOCKER_IMAGE"
	printf 'target-triplet\taarch64-rocknix-linux-gnu\n'
	printf 'gcc-version\t%s\n' "$TOOLCHAIN_VERSION"
	printf 'gcc-package-path\t%s\n' "$GCC_PACKAGE_REL"
	printf 'gcc-package-sha256\t%s\n' "$GCC_PACKAGE_SHA"
	printf 'gcc-source-sha256\t%s\n' "$GCC_SOURCE_SHA"
	printf 'cross-compiler-invocation\tbin/ccache\tbin/aarch64-rocknix-linux-gnu-gcc-15.2.0\n'
	printf 'host-compiler-invocation\tbin/ccache\t/usr/bin/gcc\n'
	printf 'host-cxx-wrapper-authority\tbin/host-g++\tbin/ccache\t/usr/bin/g++\n'
	printf 'host-compiler-resolved\t%s\t%s\n' "$HOST_GCC_CONTAINER" "$HOST_GCC_SHA"
	printf 'host-cxx-resolved\t%s\t%s\n' "$HOST_CXX_CONTAINER" "$HOST_CXX_SHA"
	for TOOL in \
		bin/aarch64-rocknix-linux-gnu-gcc \
		bin/aarch64-rocknix-linux-gnu-gcc-15.2.0 \
		bin/aarch64-rocknix-linux-gnu-ld \
		bin/aarch64-rocknix-linux-gnu-as \
		bin/aarch64-rocknix-linux-gnu-ar \
		bin/aarch64-rocknix-linux-gnu-nm \
		bin/aarch64-rocknix-linux-gnu-strip \
		bin/aarch64-rocknix-linux-gnu-objcopy \
		bin/aarch64-rocknix-linux-gnu-objdump \
		bin/aarch64-rocknix-linux-gnu-readelf \
		bin/ccache \
		bin/host-gcc \
		bin/host-g++ \
		bin/make \
		bin/python \
		bin/python3; do
		TOOL_PATH="$TOOLCHAIN/$TOOL"
		RESOLVED=$($PYTHON -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).resolve())' "$TOOL_PATH")
		RESOLVED_REL=${RESOLVED#"$TOOLCHAIN/"}
		if [ -L "$TOOL_PATH" ]; then
			printf 'tool-entry-symlink\t%s\t%s\n' "$TOOL" "$(readlink "$TOOL_PATH")"
		else
			printf 'tool-entry-file\t%s\t%s\n' "$TOOL" "$(sha256_file "$TOOL_PATH")"
		fi
		printf 'tool-resolved\t%s\t%s\t%s\n' \
			"$TOOL" "$RESOLVED_REL" "$(sha256_file "$RESOLVED")"
	done
	printf 'compiler-internal-file\tcc1\t%s\t%s\n' \
		"$CC1_REL" "$(sha256_file "$TOOLCHAIN/$CC1_REL")"
	printf 'compiler-internal-file\tlibgcc\t%s\t%s\n' \
		"$LIBGCC_REL" "$(sha256_file "$TOOLCHAIN/$LIBGCC_REL")"
	printf 'compiler-internal-tree\tinclude\t%s\t%s\t%s\t%s\tno-symlinks-special-nodes\n' \
		"$INCLUDE_REL" "$INCLUDE_FILES" "$INCLUDE_BYTES" "$INCLUDE_SHA"
	printf 'uboot-lto\tdisabled\n'
	printf 'bl31\t%s\t%s\n' "$(stat -f %z "$BL31")" "$BL31_SHA"
) >"$TOOLCHAIN_AUTHORITY"

# The build tree is copied into the container's temporary filesystem for each
# pass. The toolchain is mounted read-only at its exact original absolute
# ROCKNIX build path (its wrappers embed that path), and the source checkout is
# not mounted at all, so neither external input can be modified by U-Boot.
CONTAINER_SCRIPT='set -eu
case "$1" in baseline-a|baseline-b) DEFCONFIG_SOURCE=/input/'"$DEFCONFIG"' ;; green-a|green-b) DEFCONFIG_SOURCE=/input/green.defconfig ;; *) exit 2 ;; esac
mkdir -p "/result/$1"
tar -xzf /input/u-boot.tar.gz -C /tmp
cd /tmp/u-boot-2026.01
patch -p1 --fuzz=0 < /input/rocknix.patch
cp "$DEFCONFIG_SOURCE" "configs/'"$DEFCONFIG"'"
export TOOLCHAIN=/work/build.ROCKNIX-H700.aarch64/toolchain
export PATH="$TOOLCHAIN/bin:$PATH"
export HOME=/tmp/home
mkdir -p "$HOME"
export SOURCE_DATE_EPOCH='"$SOURCE_DATE_EPOCH"'
export CCACHE_DISABLE=1
export LC_ALL=C
export TZ=UTC
export DEBUG=0
export CROSS_COMPILE='"$CROSS_PREFIX"'
export LDFLAGS=
export ARCH=arm
make mrproper
make HOSTCC=host-gcc HOSTCFLAGS=-I$TOOLCHAIN/include HOSTLDFLAGS="-Wl,-rpath,$TOOLCHAIN/lib -L$TOOLCHAIN/lib" '"$DEFCONFIG"'
grep -Fqx "# CONFIG_LTO is not set" .config
_python_sysroot=$TOOLCHAIN _python_prefix=/ _python_exec_prefix=/ make -j2 BL31=/input/bl31.bin HOSTCC=host-gcc HOSTCFLAGS=-I$TOOLCHAIN/include HOSTLDFLAGS="-Wl,-rpath,$TOOLCHAIN/lib -L$TOOLCHAIN/lib" HOSTSTRIP=true CONFIG_MKIMAGE_DTC_PATH=scripts/dtc/dtc
# The shipping build started at 04:38:50 UTC and emitted its FIT 14 seconds
# later. The prior mkimage update was the official convenient way to set that
# date, but it reparsed and rewrote the FIT. Reproduce both historical inputs
# explicitly while owning only the four root-timestamp data bytes: the exported
# epoch above owns compiled U-Boot/SPL strings, and this strict patch requires
# that same epoch before replacing it with the historical FIT epoch. Exact
# shipping baseline parity below remains the authority.
test "$(wc -c < u-boot-sunxi-with-spl.bin)" -gt 40960
dd if=u-boot-sunxi-with-spl.bin of=u-boot.itb bs=40960 skip=1 status=none
python3 /input/patch-fit-root-timestamp.py u-boot.itb 1782880730 1782880744
cp spl/sunxi-spl.bin u-boot-sunxi-with-spl.bin
truncate -s 40960 u-boot-sunxi-with-spl.bin
cat u-boot.itb >> u-boot-sunxi-with-spl.bin
cp .config build.config
for artifact in u-boot-sunxi-with-spl.bin u-boot.itb u-boot-nodtb.bin u-boot.dtb spl/sunxi-spl.bin build.config; do
  mkdir -p "/result/$1/$(dirname "$artifact")"
  cp "$artifact" "/result/$1/$artifact"
done'

for BUILD_NAME in baseline-a baseline-b green-a green-b; do
	printf 'Building isolated U-Boot pass: %s\n' "$BUILD_NAME"
	"$DOCKER" run --rm --init --network none \
		--user "$(id -u):$(id -g)" \
		--read-only \
		--tmpfs /tmp:rw,exec,nosuid,size=2g \
		-v "$WORK/input:/input:ro" \
		-v "$TOOLCHAIN:$CONTAINER_TOOLCHAIN:ro" \
		-v "$WORK/output:/result:rw" \
		"$DOCKER_IMAGE" \
		/bin/sh -c "$CONTAINER_SCRIPT" sh "$BUILD_NAME"
done

"$PYTHON" "$ROOT/kernel/rocknix/verify-uboot-status-led-build.py" \
	--baseline-a "$WORK/output/baseline-a" \
	--baseline-b "$WORK/output/baseline-b" \
	--green-a "$WORK/output/green-a" \
	--green-b "$WORK/output/green-b" \
	--shipping "$SHIPPING" \
	--bl31 "$BL31" \
	--toolchain-authority "$TOOLCHAIN_AUTHORITY" \
	--output "$WORK/publish"

mkdir -p "$(dirname "$OUTPUT")"
mv "$WORK/publish" "$OUTPUT"
printf 'Verified non-deploying green-LED U-Boot built:\n  %s\n' "$OUTPUT"
cat "$OUTPUT/authority.tsv"
