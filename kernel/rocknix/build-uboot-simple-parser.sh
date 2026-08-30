#!/bin/sh
# Reproduce and seal the fixed RG34XX-SP simple-parser U-Boot candidate twice.
# This builder has no media-write mode.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROCKNIX_SOURCE=${ROCKNIX_SOURCE:-$HOME/rocknix-distribution-20260701}
TOOLCHAIN=${TOOLCHAIN:-$HOME/rocknix-uboot-build-20260701/toolchain}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-uboot-simple-parser-20260829}
BASE=$ROOT/kernel/work/bird-uboot-inplace-handoff-20260701
DOCKER=${DOCKER:-docker}
PYTHON=${PYTHON:-python3}

SOURCE=$ROCKNIX_SOURCE/sources/u-boot-DDR4/u-boot-DDR4-v2026.01.tar.gz
PACKAGE=$ROCKNIX_SOURCE/projects/ROCKNIX/devices/H700/packages/u-boot-DDR4/package.mk
PATCH=$ROCKNIX_SOURCE/projects/ROCKNIX/devices/H700/packages/u-boot-DDR4/patches/0001-Update-dram_sun50i_h616.c.patch
DEFCONFIG=$ROCKNIX_SOURCE/projects/ROCKNIX/devices/H700/packages/u-boot-DDR4/sources/configs/anbernic_rg35xx_h700_lpddr4_defconfig
BL31=$BASE/bl31.bin
TOOLCHAIN_AUTHORITY=$BASE/toolchain-authority.tsv
IMAGE=ghcr.io/rocknix/rocknix-build@sha256:a360f7280ff4b87f2614dd6085336df287c3bc6f2fccd87c7f5673f5cef1daed
CONTAINER_TOOLCHAIN=/work/build.ROCKNIX-H700.aarch64/toolchain
BOARD_CONFIG=anbernic_rg35xx_h700_lpddr4_defconfig
SOURCE_DATE_EPOCH=1782880730
FIT_DATE_EPOCH=1782880744

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
require_file() { [ -f "$1" ] && [ ! -L "$1" ] || fail "unsafe or missing input: $1"; }
require_hash() {
	require_file "$1"
	[ "$(sha256_file "$1")" = "$2" ] || fail "checksum mismatch for $1"
}

[ "$#" -eq 0 ] || fail 'this builder takes no positional arguments; use environment overrides'
command -v "$DOCKER" >/dev/null 2>&1 || fail 'Docker is required'
command -v "$PYTHON" >/dev/null 2>&1 || fail 'Python 3 is required'
[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || fail "output already exists: $OUTPUT"
[ -d "$TOOLCHAIN" ] && [ ! -L "$TOOLCHAIN" ] || fail "safe toolchain directory missing: $TOOLCHAIN"

require_hash "$SOURCE" 03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654
require_hash "$PACKAGE" 07c3e190986d1c8f875b92465684a53329efde0427ace9425fe164c2e8ae0f7b
require_hash "$PATCH" 596674be315fbb74f670cf04639f10ea2b5629fd9eb72d944084a04cd0e5fab5
require_hash "$DEFCONFIG" 24013855fefbe911cf664301940e8b6b514e4961ed414f324dae491f56d6bfe4
require_hash "$BL31" 431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673
require_hash "$TOOLCHAIN_AUTHORITY" 78ce9836240e264c933dac577348a01c56f2d8359d084439aa9aab6204733631
require_hash "$TOOLCHAIN/bin/aarch64-rocknix-linux-gnu-gcc-15.2.0" 088e5129e588d3491ee72d26c57e10637c6ebaeae083b6c4c50004401bd9996a
require_hash "$TOOLCHAIN/bin/host-gcc" ab0fa4da281340ca28206722afbe07e9c07ddd24cbc4a73a19fb56b58dd42c57

ENV_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-environment-nowhere.py
DIRECT_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-direct-extlinux.py
CLEAR_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-no-heap-clear.py
FAST_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-fast-init.py
INPLACE_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-inplace-handoff.py
SIMPLE_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-simple-parser.py
LZ4_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-lz4-kernel.py
TIMESTAMP_PATCHER=$ROOT/kernel/rocknix/patch-fit-root-timestamp.py
VERIFIER=$ROOT/kernel/rocknix/verify-uboot-simple-parser-build.py
require_hash "$ENV_TRANSFORM" 70446ed9d2ffe3b99f167702911b3670bbb062123dc34c0182e6e1f69ef08d1c
require_hash "$DIRECT_TRANSFORM" d493e6f263eda9badb97e9073e382e78e8d8448b2835d05b900c18db8658cc93
require_hash "$CLEAR_TRANSFORM" 684327be55262676b0eedcdfcc10f373017fba22e941005312c3fb1cf1493124
require_hash "$FAST_TRANSFORM" de952664ce1c879b7e5192f6c18f9d411f61363ee15cc9af7245386451562bd1
require_hash "$INPLACE_TRANSFORM" a4b85a19f6db4fbdc7fc055d631121a90411f21b7ea557fe6cc9d2d691c802e7
require_hash "$SIMPLE_TRANSFORM" 62bb12ee346368c805bdb878d29924f6caeb12752d944a88d8a612fff0e9693d
require_hash "$LZ4_TRANSFORM" fc1a398c270ccd67636e67155b0443fa7601f7d108f87449c54f5ae10eae434a
require_hash "$TIMESTAMP_PATCHER" 8a4aad7d7dcee9b5d058b1f25587bd1d3998049c5425c1a3c4813ddadfe6e79e
require_hash "$VERIFIER" 0b63927c18213864be9162872ebba7b3def4e2d6b3d49e0eb56eba96bde8ba3d

IMAGE_ID=$($DOCKER image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null) || fail 'pinned Docker image unavailable'
[ "$IMAGE_ID" = sha256:a360f7280ff4b87f2614dd6085336df287c3bc6f2fccd87c7f5673f5cef1daed ] || fail 'Docker image identity changed'

OUTPUT_PARENT=$(dirname "$OUTPUT")
[ -d "$OUTPUT_PARENT" ] && [ ! -L "$OUTPUT_PARENT" ] || fail 'unsafe output parent'
WORK=$(mktemp -d "$OUTPUT_PARENT/.bird-uboot-simple-parser.XXXXXX") || fail 'could not create staging directory'
cleanup() {
	case "$WORK" in "$OUTPUT_PARENT"/.bird-uboot-simple-parser.*) rm -rf -- "$WORK" ;; *) fail 'unsafe staging cleanup' ;; esac
}
trap cleanup EXIT HUP INT TERM
mkdir "$WORK/input" "$WORK/builds"
cp -p "$SOURCE" "$WORK/input/u-boot.tar.gz"
cp -p "$PATCH" "$WORK/input/rocknix.patch"
cp -p "$DEFCONFIG" "$WORK/input/upstream.defconfig"
cp -p "$BL31" "$WORK/input/bl31.bin"
cp -p "$LZ4_TRANSFORM" "$WORK/input/transform-lz4.py"
cp -p "$TIMESTAMP_PATCHER" "$WORK/input/patch-timestamp.py"

"$PYTHON" "$ENV_TRANSFORM" "$WORK/input/upstream.defconfig" "$WORK/input/env.defconfig"
"$PYTHON" "$DIRECT_TRANSFORM" "$WORK/input/env.defconfig" "$WORK/input/direct.defconfig"
"$PYTHON" "$CLEAR_TRANSFORM" "$WORK/input/direct.defconfig" "$WORK/input/no-clear.defconfig"
"$PYTHON" "$FAST_TRANSFORM" "$WORK/input/no-clear.defconfig" "$WORK/input/fast.defconfig"
mkdir "$WORK/input/inplace"
"$PYTHON" "$INPLACE_TRANSFORM" "$WORK/input/fast.defconfig" \
	"$WORK/input/inplace/inplace.defconfig" "$WORK/input/inplace/bird-rg34xx-sp-handoff.env"
"$PYTHON" "$SIMPLE_TRANSFORM" "$WORK/input/inplace/inplace.defconfig" "$WORK/input/simple.defconfig"
require_hash "$WORK/input/simple.defconfig" 743fa795fef9bea6e20b95cf18686982a87d46806eba253dbbe0d77a6850d28e

CONTAINER_SCRIPT='set -eu
name=$1
mkdir -p /tmp/source /tmp/home "/result/$name"
tar -xzf /input/u-boot.tar.gz -C /tmp/source
cd /tmp/source/u-boot-2026.01
patch -p1 --fuzz=0 < /input/rocknix.patch
cp /input/simple.defconfig configs/'"$BOARD_CONFIG"'
cp /input/inplace/bird-rg34xx-sp-handoff.env board/sunxi/bird-rg34xx-sp-handoff.env
python3 /input/transform-lz4.py include/configs/sunxi-common.h /tmp/sunxi-common.h
cp /tmp/sunxi-common.h include/configs/sunxi-common.h
TOOLCHAIN='"$CONTAINER_TOOLCHAIN"'
PATH=$TOOLCHAIN/bin:$PATH
HOME=/tmp/home
export TOOLCHAIN PATH HOME
export SOURCE_DATE_EPOCH='"$SOURCE_DATE_EPOCH"' CCACHE_DISABLE=1 LC_ALL=C TZ=UTC DEBUG=0
export CROSS_COMPILE=aarch64-rocknix-linux-gnu- ARCH=arm LDFLAGS=
make mrproper
make HOSTCC=host-gcc HOSTCFLAGS=-I$TOOLCHAIN/include HOSTLDFLAGS="-Wl,-rpath,$TOOLCHAIN/lib -L$TOOLCHAIN/lib" '"$BOARD_CONFIG"'
grep -Fqx "# CONFIG_HUSH_PARSER is not set" .config
grep -Fqx "CONFIG_CMD_SYSBOOT=y" .config
grep -Fqx "CONFIG_PXE_UTILS=y" .config
grep -Fqx "CONFIG_LZ4=y" .config
grep -Fqx "CONFIG_MMC_SUNXI=y" .config
_python_sysroot=$TOOLCHAIN _python_prefix=/ _python_exec_prefix=/ make -j2 BL31=/input/bl31.bin HOSTCC=host-gcc HOSTCFLAGS=-I$TOOLCHAIN/include HOSTLDFLAGS="-Wl,-rpath,$TOOLCHAIN/lib -L$TOOLCHAIN/lib" HOSTSTRIP=true CONFIG_MKIMAGE_DTC_PATH=scripts/dtc/dtc
dd if=u-boot-sunxi-with-spl.bin of=/tmp/u-boot.itb bs=40960 skip=1 status=none
python3 /input/patch-timestamp.py /tmp/u-boot.itb '"$SOURCE_DATE_EPOCH"' '"$FIT_DATE_EPOCH"'
cp spl/sunxi-spl.bin /tmp/spl.bin
truncate -s 40960 /tmp/spl.bin
cat /tmp/spl.bin /tmp/u-boot.itb > "/result/$name/u-boot-sunxi-with-spl.bin"
cp /tmp/u-boot.itb "/result/$name/u-boot.itb"
cp u-boot-nodtb.bin "/result/$name/u-boot-nodtb.bin"
cp u-boot.dtb "/result/$name/u-boot.dtb"
mkdir "/result/$name/spl"
cp /tmp/spl.bin "/result/$name/spl/sunxi-spl.bin"
cp .config "/result/$name/build.config"'

for PASS in a b; do
	printf 'Building isolated simple-parser pass: %s\n' "$PASS"
	"$DOCKER" run --rm --init --network none --user "$(id -u):$(id -g)" \
		--read-only --tmpfs /tmp:rw,exec,nosuid,size=2g \
		-v "$WORK/input:/input:ro" -v "$TOOLCHAIN:$CONTAINER_TOOLCHAIN:ro" \
		-v "$WORK/builds:/result:rw" "$IMAGE" /bin/sh -c "$CONTAINER_SCRIPT" sh "$PASS"
done

"$PYTHON" "$VERIFIER" --build-a "$WORK/builds/a" --build-b "$WORK/builds/b" --output "$WORK/publish"
mv "$WORK/publish" "$OUTPUT"
trap - EXIT HUP INT TERM
cleanup
printf 'Verified non-deploying simple-parser U-Boot authority: %s\n' "$OUTPUT"
