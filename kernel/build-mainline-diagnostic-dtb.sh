#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
IMAGE=${BIRD_MAINLINE_BUILD_IMAGE:-bird-rg34xxsp-kernel-build:7.0.11}
OUTPUT="$ROOT/kernel/work/mainline-diagnostic"
BASE_DTB_SHA=5c695aa096d7b03a4d1acceead274e4d8571124f9edbd33b9f0363e4444cb597

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"
mkdir -p "$OUTPUT"

docker build --platform linux/arm64 \
	-f "$ROOT/kernel/Dockerfile.mainline" \
	-t "$IMAGE" "$ROOT"

docker run --rm --platform linux/arm64 \
	-v "$ROOT:/workspace" \
	"$IMAGE" sh -eu -c '
		make -j4 ARCH=arm64 \
			allwinner/sun50i-h700-anbernic-rg34xx-sp-bird.dtb \
			allwinner/sun50i-h700-anbernic-rg34xx-sp-bird-diagnostic.dtb
		cp arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp-bird.dtb \
			/workspace/kernel/work/mainline-diagnostic/base.dtb
		cp arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp-bird-diagnostic.dtb \
			/workspace/kernel/work/mainline-diagnostic/diagnostic.dtb
		scripts/dtc/dtc -q -I dtb -O dts \
			-o /workspace/kernel/work/mainline-diagnostic/diagnostic.dts \
			arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp-bird-diagnostic.dtb
	'

[ "$(shasum -a 256 "$OUTPUT/base.dtb" | awk '{print $1}')" = \
	"$BASE_DTB_SHA" ] || fail 'production DTB changed while building diagnostic'
grep -q 'linux,default-trigger = "heartbeat"' "$OUTPUT/diagnostic.dts" || \
	fail 'heartbeat trigger missing from diagnostic DTB'
grep -q 'panic-indicator;' "$OUTPUT/diagnostic.dts" || \
	fail 'panic indicator missing from diagnostic DTB'
shasum -a 256 "$OUTPUT/base.dtb" "$OUTPUT/diagnostic.dtb" \
	"$OUTPUT/diagnostic.dts" >"$OUTPUT/sha256sums.txt"

printf 'Built non-deploying boot-boundary DTB under %s\n' "$OUTPUT"
cat "$OUTPUT/sha256sums.txt"
