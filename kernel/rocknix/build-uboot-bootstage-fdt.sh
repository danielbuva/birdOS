#!/bin/sh
# Why before: the accepted in-place handoff build intentionally excluded timing
# instrumentation, and the first measurement builder assumed SPL_BOOTSTAGE=n
# would also keep the generated SPL byte-identical to that accepted build.
# Why change: raw CONFIG_BOOTSTAGE adds gd->bootstage and shifts cyclic_list in
# the generated SPL even with SPL_BOOTSTAGE=n. Package the exact accepted SPL
# and retain the reproducible generated-but-unused SPL as evidence, without
# adding a deployment or media-write path.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROCKNIX_SOURCE=${ROCKNIX_SOURCE:-$HOME/rocknix-distribution-20260701}
ROCKNIX_BUILD=${ROCKNIX_BUILD:-$HOME/rocknix-uboot-build-20260701}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/bird-uboot-bootstage-fdt-20260701}
BASE=${BASE:-$ROOT/kernel/work/bird-uboot-inplace-handoff-20260701}
BL31=${BL31:-$BASE/bl31.bin}
TOOLCHAIN_AUTHORITY=${TOOLCHAIN_AUTHORITY:-$BASE/toolchain-authority.tsv}
DOCKER=${DOCKER:-docker}
PYTHON=${PYTHON:-python3}

ROCKNIX_COMMIT=3e4ee5852e6ca5ea73a38369d2639fad2262648b
SOURCE_DATE_EPOCH=1782880730
FIT_DATE_EPOCH=1782880744
PACKAGE_REL=projects/ROCKNIX/devices/H700/packages/u-boot-DDR4
GCC_PACKAGE_REL=projects/ROCKNIX/packages/lang/gcc/package.mk
DEFCONFIG=anbernic_rg35xx_h700_lpddr4_defconfig
SOURCE_REL=sources/u-boot-DDR4/u-boot-DDR4-v2026.01.tar.gz
SOURCE_SHA=03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654
PACKAGE_SHA=07c3e190986d1c8f875b92465684a53329efde0427ace9425fe164c2e8ae0f7b
PATCH_SHA=596674be315fbb74f670cf04639f10ea2b5629fd9eb72d944084a04cd0e5fab5
GCC_PACKAGE_SHA=f1416c2f83be951ef2de9320369f05d6296ee171c822ada6491e91c9f53d7ffc
GCC_SOURCE_SHA=438fd996826b0c82485a29da03a72d71d6e3541a83ec702df4271f6fe025d24e
UPSTREAM_DEFCONFIG_SHA=24013855fefbe911cf664301940e8b6b514e4961ed414f324dae491f56d6bfe4
ENV_DEFCONFIG_SHA=1bfd8861e74dea0534cd83037d0277ad8d0b46850d4c9e32726dcdeb76267a63
DIRECT_DEFCONFIG_SHA=784d76e328d1c1821a655176ecb805f10408f0b04f130acbb1b0e7ba38a6645a
NO_CLEAR_DEFCONFIG_SHA=74d6dc38c098657e081877f321470455556ae385e1642e36151d32da2faa9bc1
FAST_DEFCONFIG_SHA=f0b0c44e54c28675fddc2d92243ff0b35d475a07b2c196af053294fa38e90922
INPLACE_DEFCONFIG_SHA=0254301f87e2222f04c67a34e5351bce16ebaac712bd96cc096f76027d9ded13
BOOTSTAGE_DEFCONFIG_SHA=ba2ab6692aff37a163324e34717649780099ec0ec9cb57e7941b58f286788cc9
INPLACE_ENV_SHA=335b569a6f63acab13d20bccb843b5d6d979b7141ede3a5a5a2647b59ec132ce
INPLACE_TRANSFORM_SHA=a4b85a19f6db4fbdc7fc055d631121a90411f21b7ea557fe6cc9d2d691c802e7
BOOTSTAGE_TRANSFORM_SHA=ffc16982dcd4288070d942d8b8442dcf0fd9e588768c40c5cb48fc9fe8290743
BASE_VERIFIER_SHA=bb09b2f6cb1e88445005f93f7aac369dfd63955ddc72b468abce00beef3d4dc2
INPLACE_ENV=bird-rg34xx-sp-handoff.env
BASE_AUTHORITY_SHA=bc6296164aab24516b11ed77ee7f9f992932a9a55d3e17b1abf7d8681ec5ba33
INPLACE_SPL_SHA=0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c
INPLACE_DTB_SHA=ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589
BL31_SHA=431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673
TOOLCHAIN_AUTHORITY_SHA=78ce9836240e264c933dac577348a01c56f2d8359d084439aa9aab6204733631
DOCKER_IMAGE=ghcr.io/rocknix/rocknix-build@sha256:a360f7280ff4b87f2614dd6085336df287c3bc6f2fccd87c7f5673f5cef1daed
CONTAINER_TOOLCHAIN=/work/build.ROCKNIX-H700.aarch64/toolchain

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
	require_file "$1"
	ACTUAL=$(sha256_file "$1")
	[ "$ACTUAL" = "$2" ] || fail "checksum mismatch for $1: $ACTUAL"
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
PATCH="$ROCKNIX_SOURCE/$PACKAGE_REL/patches/0001-Update-dram_sun50i_h616.c.patch"
UPSTREAM_DEFCONFIG="$ROCKNIX_SOURCE/$PACKAGE_REL/sources/configs/$DEFCONFIG"
GCC_PACKAGE="$ROCKNIX_SOURCE/$GCC_PACKAGE_REL"
FIT_TIMESTAMP_PATCHER="$ROOT/kernel/rocknix/patch-fit-root-timestamp.py"
ENV_TRANSFORM="$ROOT/kernel/rocknix/transform-uboot-environment-nowhere.py"
DIRECT_TRANSFORM="$ROOT/kernel/rocknix/transform-uboot-direct-extlinux.py"
NO_CLEAR_TRANSFORM="$ROOT/kernel/rocknix/transform-uboot-no-heap-clear.py"
FAST_TRANSFORM="$ROOT/kernel/rocknix/transform-uboot-fast-init.py"
INPLACE_TRANSFORM="$ROOT/kernel/rocknix/transform-uboot-inplace-handoff.py"
BOOTSTAGE_TRANSFORM="$ROOT/kernel/rocknix/transform-uboot-bootstage-fdt.py"
VERIFIER="$ROOT/kernel/rocknix/verify-uboot-bootstage-fdt-build.py"
BASE_VERIFIER="$ROOT/kernel/rocknix/verify-uboot-inplace-handoff-build.py"

require_hash "$SOURCE" "$SOURCE_SHA"
require_hash "$PACKAGE" "$PACKAGE_SHA"
require_hash "$PATCH" "$PATCH_SHA"
require_hash "$GCC_PACKAGE" "$GCC_PACKAGE_SHA"
grep -Fqx 'PKG_VERSION="15.2.0"' "$GCC_PACKAGE" || \
	fail 'ROCKNIX GCC package version changed'
grep -Fqx "PKG_SHA256=\"$GCC_SOURCE_SHA\"" "$GCC_PACKAGE" || \
	fail 'ROCKNIX GCC source authority changed'
require_hash "$UPSTREAM_DEFCONFIG" "$UPSTREAM_DEFCONFIG_SHA"
require_hash "$BASE/authority.tsv" "$BASE_AUTHORITY_SHA"
require_hash "$BASE/bird-uboot-inplace-handoff.bin" \
	7423ffeda197645b6b774c83fcebcbefef47bd7eaa6f087c71ab339750af4e91
require_hash "$BASE/inplace-handoff.config" \
	77f2bee66adc542e3475594c4727933607f76c2adf72e6428e0e57cadb6de762
require_hash "$BASE/inplace-handoff-spl.bin" "$INPLACE_SPL_SHA"
require_hash "$BASE/inplace-handoff-control.dtb" "$INPLACE_DTB_SHA"
require_hash "$BASE/$INPLACE_ENV" "$INPLACE_ENV_SHA"
require_hash "$BL31" "$BL31_SHA"
require_hash "$TOOLCHAIN_AUTHORITY" "$TOOLCHAIN_AUTHORITY_SHA"
require_hash "$INPLACE_TRANSFORM" "$INPLACE_TRANSFORM_SHA"
require_hash "$BOOTSTAGE_TRANSFORM" "$BOOTSTAGE_TRANSFORM_SHA"
require_hash "$BASE_VERIFIER" "$BASE_VERIFIER_SHA"
for INPUT in "$FIT_TIMESTAMP_PATCHER" "$ENV_TRANSFORM" "$DIRECT_TRANSFORM" \
	"$NO_CLEAR_TRANSFORM" "$FAST_TRANSFORM" "$INPLACE_TRANSFORM" \
	"$BOOTSTAGE_TRANSFORM" "$VERIFIER" "$BASE_VERIFIER"; do
	require_file "$INPUT"
done

"$PYTHON" "$BASE_VERIFIER" --verify-output "$BASE" >/dev/null

# Reconstruct the physical acceptance oracle from its prior exact prefix and
# accepted combined image. The diagnostic may derive only from these bytes.
"$PYTHON" - "$BASE" <<'PY'
import hashlib
import pathlib
import sys

base = pathlib.Path(sys.argv[1])
prefix = bytearray((base / "base-fast-init-prefix-16m.bin").read_bytes())
combined = (base / "bird-uboot-inplace-handoff.bin").read_bytes()
if len(prefix) != 16 * 1024 * 1024:
    raise SystemExit("accepted prefix size changed")
prefix[8192:8192 + len(combined)] = combined
if hashlib.sha256(prefix).hexdigest() != (
    "c168640be0e3b0fc3899853d71aabc0c3b3e65fdf230b19782ff40ff19f001dd"
):
    raise SystemExit("accepted in-place-handoff prefix reconstruction changed")
PY

TOOLCHAIN="$ROCKNIX_BUILD/toolchain"
[ -d "$TOOLCHAIN" ] && [ ! -L "$TOOLCHAIN" ] || \
	fail "safe pinned toolchain directory missing: $TOOLCHAIN"

# Verify every retained executable and compiler-internal byte before mounting
# the toolchain read-only.  The retained table was produced independently by
# the reproducible shipping build authority.
"$PYTHON" - "$TOOLCHAIN_AUTHORITY" "$TOOLCHAIN" <<'PY'
import hashlib
import os
import pathlib
import stat
import sys

authority_path = pathlib.Path(sys.argv[1])
toolchain = pathlib.Path(sys.argv[2]).resolve(strict=True)
rows = [line.split("\t") for line in authority_path.read_text().splitlines()]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

entries = {row[1]: row for row in rows if row[0] in {"tool-entry-file", "tool-entry-symlink"}}
resolved = {row[1]: row for row in rows if row[0] == "tool-resolved"}
if set(entries) != set(resolved) or len(entries) != 16:
    raise SystemExit("toolchain executable authority inventory changed")
for name, row in entries.items():
    path = toolchain / name
    metadata = path.lstat()
    if row[0] == "tool-entry-symlink":
        if not stat.S_ISLNK(metadata.st_mode) or os.readlink(path) != row[2]:
            raise SystemExit(f"toolchain symlink authority changed: {name}")
    elif not stat.S_ISREG(metadata.st_mode) or digest(path) != row[2]:
        raise SystemExit(f"toolchain file authority changed: {name}")
    resolved_path = path.resolve(strict=True)
    try:
        relative = resolved_path.relative_to(toolchain).as_posix()
    except ValueError:
        raise SystemExit(f"toolchain path escapes authority: {name}")
    if relative != resolved[name][2] or digest(resolved_path) != resolved[name][3]:
        raise SystemExit(f"toolchain resolved authority changed: {name}")

for row in (row for row in rows if row[0] == "compiler-internal-file"):
    path = toolchain / row[2]
    if path.is_symlink() or not path.is_file() or digest(path) != row[3]:
        raise SystemExit(f"compiler internal authority changed: {row[1]}")

trees = [row for row in rows if row[0] == "compiler-internal-tree"]
if len(trees) != 1:
    raise SystemExit("compiler include-tree authority changed")
row = trees[0]
tree = toolchain / row[2]
aggregate = hashlib.sha256()
files = total = 0
for path in sorted(tree.rglob("*"), key=lambda item: os.fsencode(item.relative_to(tree))):
    relative = os.fsencode(path.relative_to(tree))
    metadata = path.lstat()
    if stat.S_ISDIR(metadata.st_mode):
        aggregate.update(b"D\0" + relative + b"\0")
    elif stat.S_ISREG(metadata.st_mode):
        data = path.read_bytes()
        aggregate.update(b"F\0" + relative + b"\0")
        aggregate.update(str(len(data)).encode() + b"\0")
        aggregate.update(hashlib.sha256(data).digest())
        files += 1
        total += len(data)
    else:
        raise SystemExit(f"unsafe compiler include node: {path}")
if (str(files), str(total), aggregate.hexdigest(), row[6]) != (
    row[3], row[4], row[5], "no-symlinks-special-nodes"
):
    raise SystemExit("compiler include-tree bytes changed")
PY

IMAGE_ID=$($DOCKER image inspect "$DOCKER_IMAGE" --format '{{.Id}}' 2>/dev/null) || \
	fail "pinned ROCKNIX builder image is unavailable: $DOCKER_IMAGE"
[ "$IMAGE_ID" = sha256:a360f7280ff4b87f2614dd6085336df287c3bc6f2fccd87c7f5673f5cef1daed ] || \
	fail "pinned ROCKNIX builder image ID changed: $IMAGE_ID"

IMAGE_PROBE=$(
	"$DOCKER" run --rm --network none --read-only \
		--user "$(id -u):$(id -g)" \
		--tmpfs /tmp:rw,exec,nosuid,size=16m \
		-v "$TOOLCHAIN:$CONTAINER_TOOLCHAIN:ro" \
		-e CCACHE_DISABLE=1 \
		"$DOCKER_IMAGE" /bin/sh -eu -c '
TOOLCHAIN=/work/build.ROCKNIX-H700.aarch64/toolchain
GCC=$TOOLCHAIN/bin/aarch64-rocknix-linux-gnu-gcc-15.2.0
printf "gcc-version\t%s\n" "$("$GCC" -dumpfullversion -dumpversion)"
for tool in gcc g++; do
  resolved=$(readlink -f "/usr/bin/$tool")
  digest=$(sha256sum "$resolved"); digest=${digest%% *}
  printf "host-%s\t%s\t%s\n" "$tool" "$resolved" "$digest"
done'
) || fail 'pinned compiler/image probe failed'
EXPECTED_IMAGE_PROBE='gcc-version	15.2.0
host-gcc	/usr/bin/x86_64-linux-gnu-gcc-12	03767455d313a6b35dab71113f074b8a8b438034ff9d5e561bc156f0ca2dedc6
host-g++	/usr/bin/x86_64-linux-gnu-g++-12	88315fd2d961a1f4e4070b104d7bd4c7670df19d9949409879ba269466c196d3'
[ "$IMAGE_PROBE" = "$EXPECTED_IMAGE_PROBE" ] || fail 'pinned compiler/image identity changed'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/bird-uboot-bootstage-fdt.XXXXXX")
cleanup() {
	rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM
mkdir "$WORK/input" "$WORK/output"
cp -fp "$SOURCE" "$WORK/input/u-boot.tar.gz"
cp -fp "$PATCH" "$WORK/input/rocknix.patch"
cp -fp "$UPSTREAM_DEFCONFIG" "$WORK/input/upstream.defconfig"
cp -fp "$BL31" "$WORK/input/bl31.bin"
cp -fp "$BASE/inplace-handoff-spl.bin" "$WORK/input/accepted-inplace-spl.bin"
cp -fp "$FIT_TIMESTAMP_PATCHER" "$WORK/input/patch-fit-root-timestamp.py"
cp -fp "$TOOLCHAIN_AUTHORITY" "$WORK/input/toolchain-authority.tsv"
require_hash "$WORK/input/accepted-inplace-spl.bin" "$INPLACE_SPL_SHA"

"$PYTHON" "$ENV_TRANSFORM" \
	"$WORK/input/upstream.defconfig" "$WORK/input/env.defconfig"
require_hash "$WORK/input/env.defconfig" "$ENV_DEFCONFIG_SHA"
"$PYTHON" "$DIRECT_TRANSFORM" \
	"$WORK/input/env.defconfig" "$WORK/input/direct.defconfig"
require_hash "$WORK/input/direct.defconfig" "$DIRECT_DEFCONFIG_SHA"
"$PYTHON" "$NO_CLEAR_TRANSFORM" \
	"$WORK/input/direct.defconfig" "$WORK/input/no-clear.defconfig"
require_hash "$WORK/input/no-clear.defconfig" "$NO_CLEAR_DEFCONFIG_SHA"
"$PYTHON" "$FAST_TRANSFORM" \
	"$WORK/input/no-clear.defconfig" "$WORK/input/fast.defconfig"
require_hash "$WORK/input/fast.defconfig" "$FAST_DEFCONFIG_SHA"
"$PYTHON" "$INPLACE_TRANSFORM" \
	"$WORK/input/fast.defconfig" "$WORK/input/inplace.defconfig" \
	"$WORK/input/$INPLACE_ENV"
require_hash "$WORK/input/inplace.defconfig" "$INPLACE_DEFCONFIG_SHA"
require_hash "$WORK/input/$INPLACE_ENV" "$INPLACE_ENV_SHA"
"$PYTHON" "$BOOTSTAGE_TRANSFORM" \
	"$WORK/input/inplace.defconfig" "$WORK/input/bootstage.defconfig"
require_hash "$WORK/input/bootstage.defconfig" "$BOOTSTAGE_DEFCONFIG_SHA"

CONTAINER_SCRIPT='set -eu
case "$1" in bootstage-fdt-a|bootstage-fdt-b) ;; *) exit 2 ;; esac
mkdir -p "/result/$1" /tmp/source
tar -xzf /input/u-boot.tar.gz -C /tmp/source
cd /tmp/source/u-boot-2026.01
patch -p1 --fuzz=0 < /input/rocknix.patch
cp /input/bootstage.defconfig "configs/'"$DEFCONFIG"'"
cp /input/'"$INPLACE_ENV"' board/sunxi/'"$INPLACE_ENV"'
TOOLCHAIN=/work/build.ROCKNIX-H700.aarch64/toolchain
PATH=$TOOLCHAIN/bin:$PATH
HOME=/tmp/home
mkdir -p "$HOME"
export TOOLCHAIN PATH HOME
export SOURCE_DATE_EPOCH='"$SOURCE_DATE_EPOCH"'
export CCACHE_DISABLE=1 LC_ALL=C TZ=UTC DEBUG=0
export CROSS_COMPILE=aarch64-rocknix-linux-gnu- ARCH=arm LDFLAGS=
make mrproper
make HOSTCC=host-gcc HOSTCFLAGS=-I$TOOLCHAIN/include HOSTLDFLAGS="-Wl,-rpath,$TOOLCHAIN/lib -L$TOOLCHAIN/lib" '"$DEFCONFIG"'
grep -Fqx "# CONFIG_LTO is not set" .config
grep -Fqx "CONFIG_BOOTSTAGE=y" .config
grep -Fqx "CONFIG_BOOTSTAGE_FDT=y" .config
grep -Fqx "CONFIG_BOOTSTAGE_RECORD_COUNT=50" .config
grep -Fqx "# CONFIG_BOOTSTAGE_REPORT is not set" .config
grep -Fqx "# CONFIG_CMD_BOOTSTAGE is not set" .config
grep -Fqx "# CONFIG_SPL_BOOTSTAGE is not set" .config
grep -Fqx "# CONFIG_BOOTSTAGE_STASH is not set" .config
grep -Fqx "# CONFIG_SYS_MALLOC_CLEAR_ON_INIT is not set" .config
grep -Fqx "CONFIG_SYS_MALLOC_LEN=0x4020000" .config
grep -Fqx "CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT=y" .config
grep -Fqx "CONFIG_ENV_IS_NOWHERE=y" .config
grep -Fqx "# CONFIG_ENV_IS_IN_FAT is not set" .config
grep -Fqx '\''CONFIG_ENV_SOURCE_FILE="bird-rg34xx-sp-handoff"'\'' .config
grep -Fqx "# CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE is not set" .config
grep -Fqx "# CONFIG_DEFAULT_ENV_IS_RW is not set" .config
grep -Fqx "CONFIG_BOOTDELAY=-2" .config
grep -Fqx '\''CONFIG_BOOTCOMMAND="sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux.conf"'\'' .config
grep -Fqx "CONFIG_NO_NET=y" .config
grep -Fqx "# CONFIG_NET is not set" .config
grep -Fqx "# CONFIG_BOOTSTD is not set" .config
grep -Fqx "CONFIG_CMD_SYSBOOT=y" .config
grep -Fqx "CONFIG_PXE_UTILS=y" .config
grep -Fqx "CONFIG_FS_FAT=y" .config
grep -Fqx "CONFIG_MMC_SUNXI=y" .config
_python_sysroot=$TOOLCHAIN _python_prefix=/ _python_exec_prefix=/ make -j2 BL31=/input/bl31.bin HOSTCC=host-gcc HOSTCFLAGS=-I$TOOLCHAIN/include HOSTLDFLAGS="-Wl,-rpath,$TOOLCHAIN/lib -L$TOOLCHAIN/lib" HOSTSTRIP=true CONFIG_MKIMAGE_DTC_PATH=scripts/dtc/dtc
test "$(grep -ao '\''fdt_high=ffffffffffffffff'\'' u-boot-nodtb.bin | wc -l)" -eq 1
test "$(grep -ao '\''initrd_high=ffffffffffffffff'\'' u-boot-nodtb.bin | wc -l)" -eq 1
test "$(wc -c < u-boot-sunxi-with-spl.bin)" -gt 40960
dd if=u-boot-sunxi-with-spl.bin of=u-boot.itb bs=40960 skip=1 status=none
python3 /input/patch-fit-root-timestamp.py u-boot.itb '"$SOURCE_DATE_EPOCH"' '"$FIT_DATE_EPOCH"'
cp spl/sunxi-spl.bin generated-unused-spl.bin
cp /input/accepted-inplace-spl.bin packaged-accepted-spl.bin
test ! generated-unused-spl.bin -ef packaged-accepted-spl.bin
! cmp -s generated-unused-spl.bin packaged-accepted-spl.bin
cp packaged-accepted-spl.bin u-boot-sunxi-with-spl.bin
truncate -s 40960 u-boot-sunxi-with-spl.bin
cat u-boot.itb >> u-boot-sunxi-with-spl.bin
cp .config build.config
for artifact in u-boot-sunxi-with-spl.bin u-boot.itb u-boot-nodtb.bin u-boot.dtb generated-unused-spl.bin packaged-accepted-spl.bin build.config; do
  mkdir -p "/result/$1/$(dirname "$artifact")"
  cp "$artifact" "/result/$1/$artifact"
done'

for BUILD_NAME in bootstage-fdt-a bootstage-fdt-b; do
	printf 'Building isolated measurement-only U-Boot pass: %s\n' "$BUILD_NAME"
	"$DOCKER" run --rm --init --network none \
		--user "$(id -u):$(id -g)" \
		--read-only \
		--tmpfs /tmp:rw,exec,nosuid,size=2g \
		-v "$WORK/input:/input:ro" \
		-v "$TOOLCHAIN:$CONTAINER_TOOLCHAIN:ro" \
		-v "$WORK/output:/result:rw" \
		"$DOCKER_IMAGE" /bin/sh -c "$CONTAINER_SCRIPT" sh "$BUILD_NAME"
done

	"$PYTHON" "$VERIFIER" \
	--build-a "$WORK/output/bootstage-fdt-a" \
	--build-b "$WORK/output/bootstage-fdt-b" \
	--base-authority "$BASE" \
	--bl31 "$BL31" \
	--toolchain-authority "$TOOLCHAIN_AUTHORITY" \
	--output "$WORK/publish"

mkdir -p "$(dirname "$OUTPUT")"
mv "$WORK/publish" "$OUTPUT"
printf 'Verified non-deploying measurement-only bootstage-FDT U-Boot candidate built:\n  %s\n' "$OUTPUT"
cat "$OUTPUT/authority.tsv"
