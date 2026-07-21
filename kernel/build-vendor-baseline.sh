#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
IMAGE=${DANI_KERNEL_BUILD_IMAGE:-dani-rg34xxsp-kernel-build:4.9.170}
OUTPUT="$ROOT/kernel/work/vendor-baseline"
JOBS=${JOBS:-4}

mkdir -p "$OUTPUT"
rm -f \
	"$OUTPUT/Image" \
	"$OUTPUT/System.map" \
	"$OUTPUT/Module.symvers" \
	"$OUTPUT/modules.tar.xz" \
	"$OUTPUT/sha256sums.txt" \
	"$OUTPUT/comparison-sha256sums.txt"

docker build --platform linux/amd64 \
	-f "$ROOT/kernel/Dockerfile.vendor-4.9" \
	-t "$IMAGE" "$ROOT/kernel"

docker run --rm --platform linux/amd64 \
	-e KBUILD_BUILD_USER=flower \
	-e KBUILD_BUILD_HOST=flower-B85M-D2V \
	-e KBUILD_BUILD_VERSION=2 \
	-e 'KBUILD_BUILD_TIMESTAMP=Wed Dec 24 23:00:24 CST 2025' \
	-e JOBS="$JOBS" \
	-v "$ROOT:/workspace" \
	"$IMAGE" sh -eu -c '
		cp /workspace/kernel/baseline/vendor.config .config
		cp .config /tmp/vendor.config
		make ARCH=arm64 olddefconfig
		if ! cmp -s /tmp/vendor.config .config; then
			diff -u /tmp/vendor.config .config > \
				/workspace/kernel/work/vendor-baseline/config-normalization.diff || true
			cp -f .config /workspace/kernel/work/vendor-baseline/built.config
			exit 0
		else
			rm -f /workspace/kernel/work/vendor-baseline/config-normalization.diff
		fi
		make -j"$JOBS" ARCH=arm64 Image modules
		cp -f arch/arm64/boot/Image /workspace/kernel/work/vendor-baseline/Image
		cp -f .config /workspace/kernel/work/vendor-baseline/built.config
		cp -f System.map /workspace/kernel/work/vendor-baseline/System.map
		cp -f Module.symvers /workspace/kernel/work/vendor-baseline/Module.symvers
		make ARCH=arm64 INSTALL_MOD_PATH=/tmp/modules modules_install
		tar -C /tmp/modules -cJf /workspace/kernel/work/vendor-baseline/modules.tar.xz .
	'

if [ -f "$OUTPUT/config-normalization.diff" ]; then
	shasum -a 256 \
		"$ROOT/kernel/baseline/vendor.config" \
		"$OUTPUT/built.config" \
		"$OUTPUT/config-normalization.diff" > \
		"$OUTPUT/comparison-sha256sums.txt"
	printf 'Audited incomplete public vendor lineage under %s\n' "$OUTPUT"
	printf 'No Image was built: the source cannot represent the active config.\n'
	cat "$OUTPUT/comparison-sha256sums.txt"
	exit 0
fi

shasum -a 256 \
	"$OUTPUT/Image" \
	"$OUTPUT/built.config" \
	"$OUTPUT/System.map" \
	"$OUTPUT/Module.symvers" \
	"$OUTPUT/modules.tar.xz" >"$OUTPUT/sha256sums.txt"

printf 'Built source-complete vendor baseline under %s\n' "$OUTPUT"
cat "$OUTPUT/sha256sums.txt"
