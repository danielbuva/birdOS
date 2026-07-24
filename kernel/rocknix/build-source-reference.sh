#!/bin/sh
# Rebuild the untrimmed ROCKNIX 20260701 H700 kernel from the exact stable
# source, executed patch order, shipping configuration, RG34XX-SP DTB and
# separately packaged H700 joypad driver.
# This is an offline artifact gate only; it never writes to removable media.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROCKNIX_SOURCE=${ROCKNIX_SOURCE:-$HOME/rocknix-distribution-20260701}
JOYPAD_SOURCE=${JOYPAD_SOURCE:-$HOME/muos-kernel-source/rocknix-joypad}
FIRMWARE_SOURCE=${FIRMWARE_SOURCE:-$HOME/muos-kernel-source/linux-firmware-20260309}
IMAGE=${BIRD_MAINLINE_BUILD_IMAGE:-bird-rg34xxsp-kernel-build:7.0.11}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/rocknix-source-reference}
BUILD_OUTPUT="$OUTPUT/build"
SHIPPING_KERNEL=${SHIPPING_KERNEL:-$OUTPUT/shipping-KERNEL}
INITRAMFS_ARCHIVE=${INITRAMFS_ARCHIVE:-}
DEFER_PANFROST=${DEFER_PANFROST:-0}
JOBS=${JOBS:-4}

ROCKNIX_COMMIT=3e4ee5852e6ca5ea73a38369d2639fad2262648b
LINUX_COMMIT=bb532bfaf7919c7c98caab81864e9ce2646e11e3
JOYPAD_COMMIT=7647fdb0fc89cd69b284903bf7707e861df5dc7e
SHIPPING_KERNEL_SHA=af4e75cb30b097ee5764764eb056d686bc00c6bd03fefece26b0ebbaa7fbb673
SHIPPING_DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
SHIPPING_DTB_BYTES=49010
PATCH_COUNT=30

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

command -v docker >/dev/null 2>&1 || fail 'docker is required'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
case "$DEFER_PANFROST" in
	0 | 1) ;;
	*) fail 'DEFER_PANFROST must be 0 or 1' ;;
esac
[ -d "$ROCKNIX_SOURCE/.git" ] || fail "ROCKNIX source missing: $ROCKNIX_SOURCE"
[ "$(git -C "$ROCKNIX_SOURCE" rev-parse HEAD)" = "$ROCKNIX_COMMIT" ] || \
	fail 'ROCKNIX source commit mismatch'
[ -d "$JOYPAD_SOURCE/.git" ] || fail "ROCKNIX joypad source missing: $JOYPAD_SOURCE"
[ "$(git -C "$JOYPAD_SOURCE" rev-parse HEAD)" = "$JOYPAD_COMMIT" ] || \
	fail 'ROCKNIX joypad source commit mismatch'
[ -z "$(git -C "$JOYPAD_SOURCE" status --short)" ] || \
	fail 'ROCKNIX joypad source is not clean'
[ -f "$SHIPPING_KERNEL" ] || fail "shipping KERNEL oracle missing: $SHIPPING_KERNEL"
[ "$(shasum -a 256 "$SHIPPING_KERNEL" | awk '{print $1}')" = \
	"$SHIPPING_KERNEL_SHA" ] || fail 'shipping KERNEL checksum mismatch'

for firmware in \
	rtl_bt/rtl8821cs_config.bin \
	rtl_bt/rtl8821cs_fw.bin \
	rtw88/rtw8821c_fw.bin; do
	[ -f "$FIRMWARE_SOURCE/$firmware" ] || \
		fail "required shipping firmware missing: $FIRMWARE_SOURCE/$firmware"
done

mkdir -p "$BUILD_OUTPUT"
find "$BUILD_OUTPUT" -mindepth 1 -depth -delete

INITRAMFS_CONFIG=
if [ -n "$INITRAMFS_ARCHIVE" ]; then
	case "$INITRAMFS_ARCHIVE" in
	/*) ;;
	*) INITRAMFS_ARCHIVE="$PWD/$INITRAMFS_ARCHIVE" ;;
	esac
	[ -f "$INITRAMFS_ARCHIVE" ] || \
		fail "Bird initramfs archive missing: $INITRAMFS_ARCHIVE"
	INITRAMFS_CONFIG=/bird-initramfs.cpio
	shasum -a 256 "$INITRAMFS_ARCHIVE" >"$BUILD_OUTPUT/input-initramfs.sha256"
else
	printf '%s\n' 'none  no-embedded-initramfs' \
		>"$BUILD_OUTPUT/input-initramfs.sha256"
fi

set -- docker run --rm --platform linux/arm64 \
	-e JOBS="$JOBS" \
	-e LINUX_COMMIT="$LINUX_COMMIT" \
	-e JOYPAD_COMMIT="$JOYPAD_COMMIT" \
	-e INITRAMFS_CONFIG="$INITRAMFS_CONFIG" \
	-e DEFER_PANFROST="$DEFER_PANFROST" \
	-e LOCALVERSION= \
	-v "$ROCKNIX_SOURCE:/rocknix:ro" \
	-v "$JOYPAD_SOURCE:/rocknix-joypad:ro" \
	-v "$FIRMWARE_SOURCE:/shipping-firmware:ro" \
	-v "$SHIPPING_KERNEL:/shipping-KERNEL:ro" \
	-v "$BUILD_OUTPUT:/out"
if [ -n "$INITRAMFS_ARCHIVE" ]; then
	set -- "$@" -v "$INITRAMFS_ARCHIVE:/bird-initramfs.cpio:ro"
fi
set -- "$@" "$IMAGE" sh -eu -c '
		export KBUILD_BUILD_USER=bird
		export KBUILD_BUILD_HOST=rg34xxsp
		export KBUILD_BUILD_VERSION=1
		export KBUILD_BUILD_TIMESTAMP="2026-07-01 04:53:00 UTC"
		export SOURCE_DATE_EPOCH=1782881580
		cd /src/linux
		git reset --hard "$LINUX_COMMIT" >/dev/null
		git clean -fdx >/dev/null
		test "$(git rev-parse HEAD)" = "$LINUX_COMMIT"

		: > /out/applied-patches.txt
		for group in \
			/rocknix/projects/ROCKNIX/packages/linux/patches/mainline \
			/rocknix/projects/ROCKNIX/packages/linux/patches/7.0 \
			/rocknix/projects/ROCKNIX/devices/H700/patches/linux; do
			for item in "$group"/*.patch; do
				test -f "$item"
				printf "%s  %s\n" \
					"$(sha256sum "$item" | awk "{print \$1}")" \
					"${item#/rocknix/}" >> /out/applied-patches.txt
				sed -e "s#@TARGET_CPU@#cortex-a53#g" \
					-e "s#@DEVICE@#H700#g" "$item" | patch -s -p1
			done
		done

		rsync -a \
			/rocknix/projects/ROCKNIX/devices/H700/linux/dts/ \
			arch/arm64/boot/dts/

		mkdir -p external-firmware/panels external-firmware/rtl_bt \
			external-firmware/rtw88
		cp -L \
			/rocknix/projects/ROCKNIX/packages/linux-firmware/kernel-firmware/extra-firmware/panels/* \
			external-firmware/panels/
		cp -L /shipping-firmware/rtl_bt/rtl8821cs_config.bin \
			/shipping-firmware/rtl_bt/rtl8821cs_fw.bin \
			external-firmware/rtl_bt/
		cp -L /shipping-firmware/rtw88/rtw8821c_fw.bin \
			external-firmware/rtw88/

		/src/linux/scripts/extract-ikconfig /shipping-KERNEL \
			> /out/shipping.config
		cp /out/shipping.config .config
		scripts/config --file .config --set-str CONFIG_INITRAMFS_SOURCE \
			"$INITRAMFS_CONFIG"
		scripts/config --file .config --set-str CONFIG_EXTRA_FIRMWARE_DIR \
			"external-firmware"
		if [ "$DEFER_PANFROST" = 1 ]; then
			scripts/config --file .config --module CONFIG_DRM_PANFROST
		fi
		make ARCH=arm64 olddefconfig >/dev/null
		cp .config /out/built.config
		gcc --version | head -1 > /out/compiler.txt
		make -s ARCH=arm64 kernelrelease > /out/kernel.release

		make -j"$JOBS" ARCH=arm64 DTC_FLAGS=-@ \
			allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb
		cp arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb \
			/out/
		scripts/dtc/dtc -q -I dtb -O dts \
			-o /out/built.dts \
			arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb

		make -j"$JOBS" ARCH=arm64 DTC_FLAGS=-@ Image modules
		cp arch/arm64/boot/Image /out/Image
		if [ "$DEFER_PANFROST" = 1 ]; then
			cp drivers/gpu/drm/drm_shmem_helper.ko \
				/out/drm_shmem_helper.ko
			cp drivers/gpu/drm/scheduler/gpu-sched.ko \
				/out/gpu-sched.ko
			cp drivers/gpu/drm/panfrost/panfrost.ko /out/panfrost.ko
		fi
		cp System.map Module.symvers /out/
		mkdir -p /tmp/rocknix-joypad
		cp /rocknix-joypad/Makefile /rocknix-joypad/*.c \
			/rocknix-joypad/*.h /tmp/rocknix-joypad/
		make -j"$JOBS" ARCH=arm64 DEVICE=H700 \
			-C /src/linux M=/tmp/rocknix-joypad modules
		cp /tmp/rocknix-joypad/rocknix-singleadc-joypad.ko /out/
		printf "%s\n" "$JOYPAD_COMMIT" > /out/joypad.commit
		make ARCH=arm64 INSTALL_MOD_PATH=/tmp/reference-modules modules_install >/dev/null
		find /tmp/reference-modules/lib/modules -type l \
			\( -name build -o -name source \) -delete
		find /tmp/reference-modules -type f -print | LC_ALL=C sort \
			> /out/modules.list
		tar --sort=name --mtime="@1784617200" --owner=0 --group=0 \
			--numeric-owner --format=gnu -C /tmp/reference-modules -cJf \
			/out/modules.tar.xz .
'
"$@"

[ "$(wc -l < "$BUILD_OUTPUT/applied-patches.txt" | tr -d ' ')" -eq \
	"$PATCH_COUNT" ] || fail 'executed patch count mismatch'

DTB="$BUILD_OUTPUT/sun50i-h700-anbernic-rg34xx-sp.dtb"
[ "$(stat -f %z "$DTB")" -eq "$SHIPPING_DTB_BYTES" ] || \
	fail 'source-built RG34XX-SP DTB size differs from shipping'
[ "$(shasum -a 256 "$DTB" | awk '{print $1}')" = "$SHIPPING_DTB_SHA" ] || \
	fail 'source-built RG34XX-SP DTB differs from shipping'

JOYPAD_MODULE="$BUILD_OUTPUT/rocknix-singleadc-joypad.ko"
strings "$JOYPAD_MODULE" | grep -Fqx \
	'vermagic=7.0.11 SMP preempt mod_unload modversions aarch64' || \
	fail 'H700 joypad module vermagic mismatch'
strings "$JOYPAD_MODULE" | grep -Fqx 'depends=' || \
	fail 'H700 joypad module gained a module dependency'
strings "$JOYPAD_MODULE" | grep -Fqx \
	'alias=of:N*T*Crocknix-singleadc-joypad' || \
	fail 'H700 joypad module DT alias missing'

python3 - "$BUILD_OUTPUT/shipping.config" "$BUILD_OUTPUT/built.config" \
	"$BUILD_OUTPUT/config-diff.txt" "$DEFER_PANFROST" <<'PY'
import re
import sys

oracle_path, built_path, report_path, defer_panfrost_arg = sys.argv[1:]
defer_panfrost = defer_panfrost_arg == "1"

def symbols(path):
    result = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            match = re.match(r"(CONFIG_[A-Z0-9_]+)=", line)
            if match:
                result[match.group(1)] = line
                continue
            match = re.match(r"# (CONFIG_[A-Z0-9_]+) is not set$", line)
            if match:
                result[match.group(1)] = line
    return result

oracle = symbols(oracle_path)
built = symbols(built_path)
changed = []
for name in sorted(set(oracle) | set(built)):
    if oracle.get(name) != built.get(name):
        changed.append((name, oracle.get(name, "<missing>"), built.get(name, "<missing>")))

allowed = re.compile(
    r"^CONFIG_(?:INITRAMFS_.*|EXTRA_FIRMWARE_DIR|CC_VERSION_TEXT|GCC_.*|CLANG_VERSION|"
    r"AS_VERSION|LD_VERSION|LLD_VERSION|RUSTC_VERSION|RUSTC_LLVM_VERSION|"
    r"PAHOLE_VERSION|CC_HAS_.*|AS_HAS_.*|LD_CAN_.*|TOOLS_SUPPORT_.*|"
    r"KSTACK_ERASE|RANDSTRUCT_.*)$"
)
def is_allowed(name):
    return bool(allowed.match(name)) or (
        defer_panfrost and name in {
            "CONFIG_DRM_GEM_SHMEM_HELPER",
            "CONFIG_DRM_PANFROST",
            "CONFIG_DRM_SCHED",
        }
    )

unexpected = [entry for entry in changed if not is_allowed(entry[0])]

with open(report_path, "w", encoding="utf-8") as report:
    for name, old, new in changed:
        status = "allowed-fixed-profile-change" if is_allowed(name) else "UNEXPECTED"
        report.write(f"{status}: {name}\n  shipping: {old}\n  rebuilt:  {new}\n")

if unexpected:
    for name, old, new in unexpected:
        print(f"unexpected config drift: {name}\n  shipping: {old}\n  rebuilt:  {new}", file=sys.stderr)
    raise SystemExit(1)
PY

PANFROST_ARTIFACT=
if [ "$DEFER_PANFROST" = 1 ]; then
	PANFROST_MODULE="$BUILD_OUTPUT/panfrost.ko"
	DRM_SHMEM_MODULE="$BUILD_OUTPUT/drm_shmem_helper.ko"
	GPU_SCHED_MODULE="$BUILD_OUTPUT/gpu-sched.ko"
	grep -qx 'CONFIG_DRM_PANFROST=m' "$BUILD_OUTPUT/built.config" || \
		fail 'Panfrost was not made a deferred module'
	for MODULE in "$DRM_SHMEM_MODULE" "$GPU_SCHED_MODULE" \
		"$PANFROST_MODULE"; do
		[ -f "$MODULE" ] || fail "deferred GPU module is missing: $MODULE"
		strings "$MODULE" | grep -Fqx \
			'vermagic=7.0.11 SMP preempt mod_unload modversions aarch64' || \
			fail "deferred GPU module vermagic mismatch: $MODULE"
	done
	strings "$PANFROST_MODULE" | grep -Fqx \
		'depends=gpu-sched,drm_shmem_helper' || \
		fail 'deferred Panfrost dependency set changed'
	PANFROST_ARTIFACT='drm_shmem_helper.ko gpu-sched.ko panfrost.ko'
else
	grep -qx 'CONFIG_DRM_PANFROST=y' "$BUILD_OUTPUT/built.config" || \
		fail 'shipping Panfrost configuration changed'
fi

if [ -n "$INITRAMFS_ARCHIVE" ]; then
	python3 - "$BUILD_OUTPUT/Image" "$INITRAMFS_ARCHIVE" \
		"$BUILD_OUTPUT/embedded-initramfs.txt" <<'PY'
import hashlib
import sys
import zlib

image_path, archive_path, report_path = sys.argv[1:]
image = open(image_path, "rb").read()
archive = open(archive_path, "rb").read()
expected = hashlib.sha256(archive).hexdigest()
offsets = []
position = 0
while True:
    position = image.find(b"\x1f\x8b\x08", position)
    if position < 0:
        break
    offsets.append(position)
    position += 1

match = None
for offset in offsets:
    try:
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        unpacked = decoder.decompress(image[offset:]) + decoder.flush()
    except zlib.error:
        continue
    if decoder.eof and hashlib.sha256(unpacked).hexdigest() == expected:
        match = (offset, len(unpacked))
        break

if match is None:
    raise SystemExit("embedded Bird initramfs does not reproduce its input archive")
with open(report_path, "w", encoding="utf-8") as report:
    report.write(f"gzip_offset={match[0]}\n")
    report.write(f"uncompressed_bytes={match[1]}\n")
    report.write(f"uncompressed_sha256={expected}\n")
PY
else
	printf '%s\n' 'none' >"$BUILD_OUTPUT/embedded-initramfs.txt"
fi

(
	cd "$BUILD_OUTPUT"
	wc -c Image sun50i-h700-anbernic-rg34xx-sp.dtb modules.tar.xz \
		rocknix-singleadc-joypad.ko $PANFROST_ARTIFACT >sizes.txt
)
(
	cd "$BUILD_OUTPUT"
	shasum -a 256 \
		Image \
		sun50i-h700-anbernic-rg34xx-sp.dtb \
		shipping.config \
		built.config \
		built.dts \
		compiler.txt \
		kernel.release \
		System.map \
		Module.symvers \
		rocknix-singleadc-joypad.ko \
		$PANFROST_ARTIFACT \
		joypad.commit \
		modules.list \
		modules.tar.xz \
		applied-patches.txt \
		config-diff.txt \
		embedded-initramfs.txt \
		input-initramfs.sha256 \
		sizes.txt > sha256sums.txt
)

printf 'Exact untrimmed ROCKNIX source gate passed under:\n  %s\n' "$BUILD_OUTPUT"
printf 'Shipping-identical DTB:\n'
shasum -a 256 "$DTB"
printf 'Build artifacts:\n'
cat "$BUILD_OUTPUT/sizes.txt"
