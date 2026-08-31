#!/bin/sh
# Reproduce and seal the exact RG34XX-SP kernel/U-Boot boot pair twice.
# This builder has no media-write mode.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROCKNIX_SOURCE=${ROCKNIX_SOURCE:-$HOME/rocknix-distribution-20260701}
PAIR_PROFILE=${BIRD_BOOT_PAIR_PROFILE:-no-raid6-benchmark}
case "$PAIR_PROFILE" in
	no-raid6-benchmark)
		DEFAULT_OUTPUT=$ROOT/kernel/work/bird-no-raid6-benchmark-pair-20260830
		DEFAULT_KERNEL_A=$ROOT/kernel/work/rocknix-source-irq-buttons-no-raid6-benchmark-a/build/Image
		DEFAULT_KERNEL_B=$ROOT/kernel/work/rocknix-source-irq-buttons-no-raid6-benchmark-b/build/Image
		KERNEL_SHA=b1d5eba80c2a9b07d4c99057fa9817403bd5de4e8f1dfc4cfcc5064443b6386e
		BOUND_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-no-raid6-benchmark-kernel.py
		BOUND_TRANSFORM_SHA=61a0b4bd9df23f33ad8be1f8bfa880e2193666f6c9879f6934784514da2f7bcb
		VERIFIER=$ROOT/kernel/rocknix/verify-no-raid6-benchmark-pair-build.py
		VERIFIER_SHA=20216c5047503134b3952fe181b2adf0c095fdb04f913304adbb6fd9f4062f16
		PAIR_LABEL=no-RAID6-benchmark
		;;
	deferred-wifi)
		DEFAULT_OUTPUT=$ROOT/kernel/work/bird-deferred-wifi-pair-20260830-v3
		DEFAULT_KERNEL_A=$ROOT/kernel/work/rocknix-source-deferred-wifi-a/build/Image
		DEFAULT_KERNEL_B=$ROOT/kernel/work/rocknix-source-deferred-wifi-b/build/Image
		KERNEL_SHA=efc9de3ca0ee03191f2df48ed87467f2a295537dd5ef09cf2932500b0a46f8e4
		BOUND_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-deferred-wifi-kernel.py
		BOUND_TRANSFORM_SHA=1cb17a248dbd6e1722b399c0682a6f2172e14bda33f4c504e089046fa1acc581
		VERIFIER=$ROOT/kernel/rocknix/verify-deferred-wifi-pair-build.py
		VERIFIER_SHA=09e786c6994ea31bae139307fe3608131e0ae4a0a3e9a466fa04db96e0ebdce9
		PAIR_LABEL=deferred-Wi-Fi
		;;
	*) printf 'error: unknown BIRD_BOOT_PAIR_PROFILE: %s\n' "$PAIR_PROFILE" >&2; exit 1 ;;
esac
OUTPUT=${OUTPUT:-$DEFAULT_OUTPUT}
KERNEL_A=${KERNEL_A:-$DEFAULT_KERNEL_A}
KERNEL_B=${KERNEL_B:-$DEFAULT_KERNEL_B}
BASE=$ROOT/kernel/work/bird-uboot-inplace-handoff-20260701
DOCKER=${DOCKER:-docker}
PYTHON=${PYTHON:-python3}
LZ4=${LZ4:-/opt/homebrew/Cellar/lz4/1.10.0/bin/lz4}
TOOLCHAIN_VOLUME=${TOOLCHAIN_VOLUME:-bird-rocknix-uboot-20260701}

SOURCE=$ROCKNIX_SOURCE/sources/u-boot-DDR4/u-boot-DDR4-v2026.01.tar.gz
PATCH=$ROCKNIX_SOURCE/projects/ROCKNIX/devices/H700/packages/u-boot-DDR4/patches/0001-Update-dram_sun50i_h616.c.patch
DEFCONFIG=$ROCKNIX_SOURCE/projects/ROCKNIX/devices/H700/packages/u-boot-DDR4/sources/configs/anbernic_rg35xx_h700_lpddr4_defconfig
BL31=$BASE/bl31.bin
IMAGE=ghcr.io/rocknix/rocknix-build@sha256:a360f7280ff4b87f2614dd6085336df287c3bc6f2fccd87c7f5673f5cef1daed
BOARD_CONFIG=anbernic_rg35xx_h700_lpddr4_defconfig

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
[ -x "$LZ4" ] && [ ! -L "$LZ4" ] || fail 'pinned LZ4 compressor is missing or unsafe'
[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || fail "output already exists: $OUTPUT"

require_hash "$SOURCE" 03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654
require_hash "$PATCH" 596674be315fbb74f670cf04639f10ea2b5629fd9eb72d944084a04cd0e5fab5
require_hash "$DEFCONFIG" 24013855fefbe911cf664301940e8b6b514e4961ed414f324dae491f56d6bfe4
require_hash "$BL31" 431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673
require_hash "$KERNEL_A" "$KERNEL_SHA"
require_hash "$KERNEL_B" "$KERNEL_SHA"
require_hash "$LZ4" 4fef8dd687478d1a8dcf4e2db25defd2daf76f7e0bb3478f023b738f9501f48c
[ "$("$LZ4" --version 2>&1)" = '*** lz4 v1.10.0 64-bit multithread, by Yann Collet ***' ] || fail 'LZ4 version authority changed'

ENV_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-environment-nowhere.py
DIRECT_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-direct-extlinux.py
CLEAR_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-no-heap-clear.py
FAST_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-fast-init.py
INPLACE_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-inplace-handoff.py
SIMPLE_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-simple-parser.py
FIXED_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-fixed-read-path.py
COMMAND_TRANSFORM=$ROOT/kernel/rocknix/transform-uboot-fixed-command-closure.py
TIMESTAMP_PATCHER=$ROOT/kernel/rocknix/patch-fit-root-timestamp.py
require_hash "$BOUND_TRANSFORM" "$BOUND_TRANSFORM_SHA"
require_hash "$TIMESTAMP_PATCHER" 8a4aad7d7dcee9b5d058b1f25587bd1d3998049c5425c1a3c4813ddadfe6e79e
require_hash "$VERIFIER" "$VERIFIER_SHA"

IMAGE_ID=$($DOCKER image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null) || fail 'pinned Docker image unavailable'
[ "$IMAGE_ID" = sha256:a360f7280ff4b87f2614dd6085336df287c3bc6f2fccd87c7f5673f5cef1daed ] || fail 'Docker image identity changed'
$DOCKER volume inspect "$TOOLCHAIN_VOLUME" >/dev/null 2>&1 || fail 'pinned U-Boot toolchain volume is unavailable'
$DOCKER run --rm --network none --read-only -v "$TOOLCHAIN_VOLUME:/work:ro" "$IMAGE" /bin/sh -eu -c '
test "$(sha256sum /work/build.ROCKNIX-H700.aarch64/toolchain/bin/aarch64-rocknix-linux-gnu-gcc-15.2.0 | cut -d" " -f1)" = 088e5129e588d3491ee72d26c57e10637c6ebaeae083b6c4c50004401bd9996a
test "$(sha256sum /work/build.ROCKNIX-H700.aarch64/toolchain/bin/host-gcc | cut -d" " -f1)" = ab0fa4da281340ca28206722afbe07e9c07ddd24cbc4a73a19fb56b58dd42c57
' || fail 'pinned U-Boot toolchain identity changed'

OUTPUT_PARENT=$(dirname "$OUTPUT")
[ -d "$OUTPUT_PARENT" ] && [ ! -L "$OUTPUT_PARENT" ] || fail 'unsafe output parent'
WORK=$(mktemp -d "$OUTPUT_PARENT/.bird-no-raid6-pair.XXXXXX") || fail 'could not create staging directory'
cleanup() {
	case "$WORK" in "$OUTPUT_PARENT"/.bird-no-raid6-pair.*) rm -rf -- "$WORK" ;; *) fail 'unsafe staging cleanup' ;; esac
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$WORK/input/inplace" "$WORK/builds" "$WORK/lz4"
cp -p "$SOURCE" "$WORK/input/u-boot.tar.gz"
cp -p "$PATCH" "$WORK/input/rocknix.patch"
cp -p "$DEFCONFIG" "$WORK/input/upstream.defconfig"
cp -p "$BL31" "$WORK/input/bl31.bin"
cp -p "$BOUND_TRANSFORM" "$WORK/input/transform-bound.py"
cp -p "$TIMESTAMP_PATCHER" "$WORK/input/patch-timestamp.py"

"$PYTHON" "$ENV_TRANSFORM" "$WORK/input/upstream.defconfig" "$WORK/input/env.defconfig"
"$PYTHON" "$DIRECT_TRANSFORM" "$WORK/input/env.defconfig" "$WORK/input/direct.defconfig"
"$PYTHON" "$CLEAR_TRANSFORM" "$WORK/input/direct.defconfig" "$WORK/input/no-clear.defconfig"
"$PYTHON" "$FAST_TRANSFORM" "$WORK/input/no-clear.defconfig" "$WORK/input/fast.defconfig"
"$PYTHON" "$INPLACE_TRANSFORM" "$WORK/input/fast.defconfig" "$WORK/input/inplace/inplace.defconfig" "$WORK/input/inplace/bird-rg34xx-sp-handoff.env"
"$PYTHON" "$SIMPLE_TRANSFORM" "$WORK/input/inplace/inplace.defconfig" "$WORK/input/simple.defconfig"
"$PYTHON" "$FIXED_TRANSFORM" "$WORK/input/simple.defconfig" "$WORK/input/fixed.defconfig"
"$PYTHON" "$COMMAND_TRANSFORM" "$WORK/input/fixed.defconfig" "$WORK/input/commands.defconfig"

"$LZ4" -9 -T1 -f -q "$KERNEL_A" "$WORK/lz4/a.lz4"
"$LZ4" -9 -T1 -f -q "$KERNEL_B" "$WORK/lz4/b.lz4"

CONTAINER_SCRIPT='set -eu
name=$1
mkdir -p /tmp/source /tmp/home "/result/$name"
tar -xzf /input/u-boot.tar.gz -C /tmp/source
cd /tmp/source/u-boot-2026.01
patch -p1 --fuzz=0 < /input/rocknix.patch
cp /input/commands.defconfig configs/'"$BOARD_CONFIG"'
cp /input/inplace/bird-rg34xx-sp-handoff.env board/sunxi/bird-rg34xx-sp-handoff.env
python3 /input/transform-bound.py include/configs/sunxi-common.h /tmp/sunxi-common.h
cp /tmp/sunxi-common.h include/configs/sunxi-common.h
TOOLCHAIN=/work/build.ROCKNIX-H700.aarch64/toolchain
PATH=$TOOLCHAIN/bin:$PATH
HOME=/tmp/home
export TOOLCHAIN PATH HOME
export SOURCE_DATE_EPOCH=1782880730 CCACHE_DISABLE=1 LC_ALL=C TZ=UTC DEBUG=0
export CROSS_COMPILE=aarch64-rocknix-linux-gnu- ARCH=arm LDFLAGS=
make mrproper
make HOSTCC=host-gcc HOSTCFLAGS=-I$TOOLCHAIN/include HOSTLDFLAGS="-Wl,-rpath,$TOOLCHAIN/lib -L$TOOLCHAIN/lib" '"$BOARD_CONFIG"'
_python_sysroot=$TOOLCHAIN _python_prefix=/ _python_exec_prefix=/ make -j2 BL31=/input/bl31.bin HOSTCC=host-gcc HOSTCFLAGS=-I$TOOLCHAIN/include HOSTLDFLAGS="-Wl,-rpath,$TOOLCHAIN/lib -L$TOOLCHAIN/lib" HOSTSTRIP=true CONFIG_MKIMAGE_DTC_PATH=scripts/dtc/dtc
dd if=u-boot-sunxi-with-spl.bin of=/tmp/u-boot.itb bs=40960 skip=1 status=none
python3 /input/patch-timestamp.py /tmp/u-boot.itb 1782880730 1782880744
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
	printf 'Building isolated %s U-Boot pass: %s\n' "$PAIR_LABEL" "$PASS"
	"$DOCKER" run --rm --init --network none --user "$(id -u):$(id -g)" \
		--read-only --tmpfs /tmp:rw,exec,nosuid,size=2g \
		-v "$TOOLCHAIN_VOLUME:/work:ro" -v "$WORK/input:/input:ro" \
		-v "$WORK/builds:/result:rw" "$IMAGE" /bin/sh -c "$CONTAINER_SCRIPT" sh "$PASS"
done

"$PYTHON" "$VERIFIER" \
	--build-a "$WORK/builds/a" --build-b "$WORK/builds/b" \
	--kernel-a "$KERNEL_A" --kernel-b "$KERNEL_B" \
	--lz4-a "$WORK/lz4/a.lz4" --lz4-b "$WORK/lz4/b.lz4" \
	--output "$WORK/publish"
mv "$WORK/publish" "$OUTPUT"
trap - EXIT HUP INT TERM
cleanup
printf 'Verified non-deploying %s boot pair: %s\n' "$PAIR_LABEL" "$OUTPUT"
