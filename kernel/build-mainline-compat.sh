#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
IMAGE=${DANI_MAINLINE_BUILD_IMAGE:-dani-rg34xxsp-kernel-build:7.0.11}
OUTPUT="$ROOT/kernel/work/mainline-compat"
JOBS=${JOBS:-4}

mkdir -p "$OUTPUT"
rm -f \
	"$OUTPUT/Image" \
	"$OUTPUT/sun50i-h700-anbernic-rg34xx-sp-dani.dtb" \
	"$OUTPUT/built.config" \
	"$OUTPUT/System.map" \
	"$OUTPUT/Module.symvers" \
	"$OUTPUT/modules.tar.xz" \
	"$OUTPUT/built.dts" \
	"$OUTPUT/kernel.release" \
	"$OUTPUT/modules.list" \
	"$OUTPUT/sizes.txt" \
	"$OUTPUT/sha256sums.txt"

docker build --platform linux/arm64 \
	-f "$ROOT/kernel/Dockerfile.mainline" \
	-t "$IMAGE" "$ROOT"

docker run --rm --platform linux/arm64 \
	-e KBUILD_BUILD_USER=dani \
	-e KBUILD_BUILD_HOST=rg34xxsp \
	-e KBUILD_BUILD_VERSION=1 \
	-e KBUILD_BUILD_TIMESTAMP='Tue Jul 21 00:00:00 PDT 2026' \
	-e LOCALVERSION= \
	-e JOBS="$JOBS" \
	-v "$ROOT:/workspace" \
	"$IMAGE" sh -eu -c '
		make -j"$JOBS" ARCH=arm64 Image modules \
			allwinner/sun50i-h700-anbernic-rg34xx-sp-dani.dtb
		cp -f arch/arm64/boot/Image /workspace/kernel/work/mainline-compat/Image
		cp -f arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp-dani.dtb \
			/workspace/kernel/work/mainline-compat/
		scripts/dtc/dtc -q -I dtb -O dts \
			-o /workspace/kernel/work/mainline-compat/built.dts \
			arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp-dani.dtb
		make -s ARCH=arm64 kernelrelease \
			> /workspace/kernel/work/mainline-compat/kernel.release
		cp -f .config /workspace/kernel/work/mainline-compat/built.config
		cp -f System.map /workspace/kernel/work/mainline-compat/System.map
		cp -f Module.symvers /workspace/kernel/work/mainline-compat/Module.symvers
		make ARCH=arm64 INSTALL_MOD_PATH=/tmp/modules modules_install
		rm -f /tmp/modules/lib/modules/*/build /tmp/modules/lib/modules/*/source
		find /tmp/modules -type f -print | LC_ALL=C sort \
			> /workspace/kernel/work/mainline-compat/modules.list
		tar --sort=name --mtime="@1784617200" --owner=0 --group=0 \
			--numeric-owner --format=gnu -C /tmp/modules -cJf \
			/workspace/kernel/work/mainline-compat/modules.tar.xz .
	'

wc -c \
	"$OUTPUT/Image" \
	"$OUTPUT/sun50i-h700-anbernic-rg34xx-sp-dani.dtb" \
	"$OUTPUT/modules.tar.xz" >"$OUTPUT/sizes.txt"

(
	cd "$OUTPUT"
	shasum -a 256 \
		Image \
		sun50i-h700-anbernic-rg34xx-sp-dani.dtb \
		built.config \
		built.dts \
		kernel.release \
		System.map \
		Module.symvers \
		modules.list \
		modules.tar.xz \
		sizes.txt >sha256sums.txt
)

printf 'Built non-deploying RG34XX-SP compatibility kernel under %s\n' "$OUTPUT"
cat "$OUTPUT/sha256sums.txt"
