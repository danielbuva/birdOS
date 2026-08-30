#!/bin/sh
# Host-only end-to-end gate for the exact 8 KiB mainline U-Boot transaction.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
INSTALLER=$ROOT/firmware/mac-install-bird-uboot.sh
INVENTORY=$ROOT/kernel/rocknix/inventory-bird-boot-volume.py
UBOOT_BUILD=${UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-green-20260701}
EARLY_UBOOT_BUILD=${EARLY_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-early-led-20260701}
ENV_UBOOT_BUILD=${ENV_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-env-nowhere-20260701}
DIRECT_UBOOT_BUILD=${DIRECT_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-direct-extlinux-20260701}
NO_HEAP_CLEAR_UBOOT_BUILD=${NO_HEAP_CLEAR_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-no-heap-clear-20260701}
FAST_INIT_UBOOT_BUILD=${FAST_INIT_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-fast-init-20260701}
INPLACE_HANDOFF_UBOOT_BUILD=${INPLACE_HANDOFF_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-inplace-handoff-20260701}
BOOTSTAGE_FDT_UBOOT_BUILD=${BOOTSTAGE_FDT_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-bootstage-fdt-20260701}
LZ4_PAIR_UBOOT_BUILD=${LZ4_PAIR_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-lz4-pair-20260813}
SIMPLE_PARSER_UBOOT_BUILD=${SIMPLE_PARSER_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-simple-parser-20260829}
FIXED_READ_PATH_UBOOT_BUILD=${FIXED_READ_PATH_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-fixed-read-path-20260829}
FIXED_COMMAND_CLOSURE_UBOOT_BUILD=${FIXED_COMMAND_CLOSURE_UBOOT_BUILD:-$ROOT/kernel/work/bird-uboot-fixed-command-closure-20260829}
GDD=${GDD:-/opt/homebrew/bin/gdd}
GTRUNCATE=${GTRUNCATE:-/opt/homebrew/bin/gtruncate}
PREFIX_BYTES=16777216
RAW_OFFSET=8192
UBOOT_BYTES=621049
NO_HEAP_CLEAR_UBOOT_BYTES=620745
FAST_INIT_UBOOT_BYTES=556977
INPLACE_HANDOFF_UBOOT_BYTES=556977
SIMPLE_PARSER_UBOOT_BYTES=518369
FIXED_READ_PATH_UBOOT_BYTES=478033
FIXED_COMMAND_CLOSURE_UBOOT_BYTES=411977
BOOTSTAGE_FDT_UBOOT_BYTES=561073
RAW_SECTOR_BYTES=512
RAW_WRITE_BYTES=621056
RAW_WRITE_SECTORS=1213
TAIL_BYTES=4096

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

[ "$(uname -s)" = Darwin ] || {
	printf 'SKIP: raw U-Boot installer host gate requires macOS\n'
	exit 0
}
[ -x "$GDD" ] && [ -x "$GTRUNCATE" ] ||
	fail 'GNU coreutils are required'
CASE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bird-uboot-installer-test.XXXXXX") ||
	fail 'could not create U-Boot installer fixture'
cleanup() {
	case "$CASE_ROOT" in
		/var/folders/*|/private/tmp/*|/tmp/*) /bin/rm -rf "$CASE_ROOT" ;;
	esac
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

BIRD=$CASE_ROOT/BIRD
DATA=$CASE_ROOT/BIRD-DATA
ARTIFACTS=$CASE_ROOT/authority
EARLY_ARTIFACTS=$CASE_ROOT/early-authority
ENV_ARTIFACTS=$CASE_ROOT/env-authority
NO_HEAP_CLEAR_ARTIFACTS=$CASE_ROOT/no-heap-clear-authority
FAST_INIT_ARTIFACTS=$CASE_ROOT/fast-init-authority
INPLACE_HANDOFF_ARTIFACTS=$CASE_ROOT/inplace-handoff-authority
BOOTSTAGE_FDT_ARTIFACTS=$CASE_ROOT/bootstage-fdt-authority
LZ4_PAIR_ARTIFACTS=$CASE_ROOT/lz4-pair-authority
SIMPLE_PARSER_ARTIFACTS=$CASE_ROOT/simple-parser-authority
FIXED_READ_PATH_ARTIFACTS=$CASE_ROOT/fixed-read-path-authority
FIXED_COMMAND_CLOSURE_ARTIFACTS=$CASE_ROOT/fixed-command-closure-authority
RAW=$CASE_ROOT/raw-card.img
DEVICE_INFO=$CASE_ROOT/device.tsv
WHOLE=disk$$
RAW_GDD=$CASE_ROOT/gdd-sector-guard
cat >"$RAW_GDD" <<'SH'
#!/bin/sh
set -eu

RAW_WRITE=0
FULLBLOCK=0
BS=
COUNT=
SEEK=
for ARG in "$@"; do
	case "$ARG" in
		of="$BIRD_TEST_GUARDED_RAW") RAW_WRITE=1 ;;
		iflag=*fullblock*) FULLBLOCK=1 ;;
		bs=*) BS=${ARG#bs=} ;;
		count=*) COUNT=${ARG#count=} ;;
		seek=*) SEEK=${ARG#seek=} ;;
	esac
done
if [ "$RAW_WRITE" -eq 1 ] && [ "$FULLBLOCK" -eq 1 ]; then
	[ "$BS" = 512 ] && { [ "$COUNT" = 805 ] || [ "$COUNT" = 934 ] || [ "$COUNT" = 1013 ] || [ "$COUNT" = 1088 ] || [ "$COUNT" = 1096 ] ||
		[ "$COUNT" = 1213 ] || [ "$COUNT" = 1214 ]; } &&
		[ "$SEEK" = 16 ] || {
		printf 'gdd-sector-guard: Invalid argument: unaligned raw write\n' >&2
		exit 1
	}
fi
exec "$BIRD_TEST_REAL_GDD" "$@"
SH
chmod 700 "$RAW_GDD"
export BIRD_TEST_GUARDED_RAW=$RAW
export BIRD_TEST_REAL_GDD=$GDD
mkdir -p "$BIRD" "$DATA/Bird"
python3 - "$BIRD" "$ROOT" <<'PY'
import hashlib
import pathlib
import sys

bird = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
release_id = "v6.23-20260814-201218"
release = bird / "bird-releases" / release_id
for relative in ("bird", "extlinux", "launcher"):
    (release / relative).mkdir(parents=True, exist_ok=True)
(bird / "extlinux").mkdir(parents=True, exist_ok=True)

selector = (
    "LABEL BIRD-DEV\n"
    f"  LINUX /bird-releases/{release_id}/KERNEL\n"
    f"  INITRD /bird-releases/{release_id}/bird-initramfs.cpio.gz\n"
    f"  FDT /bird-releases/{release_id}/dtb.img\n"
    f"  APPEND bird_release={release_id}\n"
).encode("ascii")
files = {
    "KERNEL": b"candidate kernel\n",
    "bird-initramfs.cpio.gz": b"candidate initramfs\n",
    "dtb.img": b"candidate dtb\n",
    "extlinux/extlinux.conf": selector,
    "bird/bird-device-contract.tsv": b"schema\tfixture-device-contract-v1\n",
    "bird/capture-uboot-bootstage.sh": (
        root / "kernel/rocknix/stock-root/capture-uboot-bootstage.sh"
    ).read_bytes(),
    "launcher/catalog.generated.h": b"/* fixture catalog */\n",
}
file_modes = {"bird/capture-uboot-bootstage.sh": 0o755}
for relative, data in files.items():
    target = release / relative
    target.write_bytes(data)
    target.chmod(file_modes.get(relative, 0o644))
(bird / "extlinux/extlinux.conf").write_bytes(selector)
(bird / "extlinux/extlinux.conf").chmod(0o644)

inputs = (
    "KERNEL",
    "PortMaster.zip",
    "PortMaster/PortMaster.sh",
    "PortMaster/funcs.txt",
    "PortMaster/harbourmaster",
    "PortMaster/mod_ROCKNIX.txt",
    "PortMaster/pugwash",
    "ROCKNIX-STORAGE",
    "ROCKNIX-SYSTEM",
    "dtb.img",
    "initramfs/busybox",
    "initramfs/init",
    "rocknix-singleadc-joypad.ko",
    "usr/bin/autostart",
)
lines = [
    "schema\tbird-deploy-v1",
    f"release\t{release_id}",
    "target-mode-policy\tfat-capability",
    "source-commit\t" + ("1" * 40) + "\tclean",
]
for name in inputs:
    lines.append(f"input\t{name}\t644\t1\t{'0' * 64}\tfixture")
for relative, data in files.items():
    lines.append(
        f"file\t{relative}\t{file_modes.get(relative, 0o644):o}\t"
        f"{len(data)}\t{hashlib.sha256(data).hexdigest()}"
    )
lines.extend(
    (
        "artifact\tdevice-contract\tbird/bird-device-contract.tsv\t"
        + hashlib.sha256(files["bird/bird-device-contract.tsv"]).hexdigest(),
        "artifact\tcatalog\tlauncher/catalog.generated.h\t"
        + hashlib.sha256(files["launcher/catalog.generated.h"]).hexdigest(),
    )
)
manifest = ("\n".join(lines) + "\n").encode("utf-8")
(release / "deploy-manifest.tsv").write_bytes(manifest)
(release / "deploy-manifest.tsv").chmod(0o644)
(release / ".complete").write_text(
    hashlib.sha256(manifest).hexdigest() + "\n", encoding="ascii"
)
(release / ".complete").chmod(0o644)
PY
printf 'revision\tbird-canonical-namespace-v1\nstate\tcommitted\n' \
	>"$DATA/Bird/namespace-v1.tsv"
: >"$DATA/Bird/boot-diagnostics.request"
mkdir "$BIRD/.Spotlight-V100" "$BIRD/.fseventsd"
printf 'ignored host metadata\n' >"$BIRD/.Spotlight-V100/index"
printf 'ignored AppleDouble\n' >"$BIRD/._extlinux"

USING_REVIEWED_AUTHORITY=0
if [ -d "$UBOOT_BUILD" ] && [ ! -L "$UBOOT_BUILD" ]; then
	COPYFILE_DISABLE=1 cp -R "$UBOOT_BUILD" "$ARTIFACTS"
	USING_REVIEWED_AUTHORITY=1
else
	# Exercise the complete installer even before the slow external build is
	# available. The build verifier publishes a structurally valid authority
	# from the exact shipping SPL/FIT with one modeled U-Boot-proper byte change.
	python3 - "$ROOT" "$ARTIFACTS" <<'PY'
import importlib.util
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
verifier_path = root / "kernel/rocknix/verify-uboot-status-led-build.py"
spec = importlib.util.spec_from_file_location("bird_uboot_build", verifier_path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
oracle = root / (
    "kernel/work/rocknix-system-exact-20260701/usr/share/bootloader/"
    "H700_DDR4_u-boot-sunxi-with-spl.bin"
)
bl31_path = oracle.with_name("bl31.bin")
shipping = oracle.read_bytes()
bl31 = bl31_path.read_bytes()
spl = shipping[: module.SPL_REGION_BYTES]
fit = shipping[module.SPL_REGION_BYTES :]
properties = module.parse_fit(fit)
uboot = properties["/images/uboot"]["data"]
control = properties["/images/fdt-1"]["data"]
changed_uboot = bytearray(uboot)
changed_uboot[100] ^= 1
changed_uboot = bytes(changed_uboot)
offset = fit.find(uboot)
assert offset >= 0 and fit.find(uboot, offset + 1) == -1
changed_fit = bytearray(fit)
changed_fit[offset + 100] ^= 1
changed_fit = bytes(changed_fit)

baseline_config = b"# CONFIG_LTO is not set\nCONFIG_LED_STATUS_BIT=267\n"
green_config = b"# CONFIG_LTO is not set\nCONFIG_LED_STATUS_BIT=268\n"

def write_build(path, combined, fit_blob, uboot_blob, config):
    (path / "spl").mkdir(parents=True)
    (path / "u-boot-sunxi-with-spl.bin").write_bytes(combined)
    (path / "u-boot.itb").write_bytes(fit_blob)
    (path / "u-boot-nodtb.bin").write_bytes(uboot_blob)
    (path / "u-boot.dtb").write_bytes(control)
    (path / "spl/sunxi-spl.bin").write_bytes(spl)
    (path / "build.config").write_bytes(config)

baseline_a = output.parent / "baseline-a"
baseline_b = output.parent / "baseline-b"
green_a = output.parent / "green-a"
green_b = output.parent / "green-b"
for path in (baseline_a, baseline_b):
    write_build(path, shipping, fit, uboot, baseline_config)
for path in (green_a, green_b):
    write_build(path, spl + changed_fit, changed_fit, changed_uboot, green_config)
digest = hashlib.sha256(b"fixture-tool").hexdigest()
tools = [
    f"bin/{module.TARGET_TRIPLET}-{suffix}"
    for suffix in (
        "gcc", "gcc-15.2.0", "ld", "as", "ar", "nm", "strip",
        "objcopy", "objdump", "readelf",
    )
] + [
    "bin/ccache", "bin/host-gcc", "bin/host-g++", "bin/make",
    "bin/python", "bin/python3",
]
toolchain_lines = [
    f"schema\t{module.TOOLCHAIN_SCHEMA}",
    f"docker-image\t{module.DOCKER_IMAGE}",
    f"target-triplet\t{module.TARGET_TRIPLET}",
    "gcc-version\t15.2.0",
    f"gcc-package-path\t{module.GCC_PACKAGE_PATH}",
    f"gcc-package-sha256\t{module.GCC_PACKAGE_SHA256}",
    f"gcc-source-sha256\t{module.GCC_SOURCE_SHA256}",
    "cross-compiler-invocation\tbin/ccache\t"
    f"bin/{module.TARGET_TRIPLET}-gcc-15.2.0",
    "host-compiler-invocation\tbin/ccache\t/usr/bin/gcc",
    "host-cxx-wrapper-authority\tbin/host-g++\tbin/ccache\t/usr/bin/g++",
    f"host-compiler-resolved\t/usr/bin/gcc-actual\t{digest}",
    f"host-cxx-resolved\t/usr/bin/g++-actual\t{digest}",
]
for tool in tools:
    toolchain_lines.append(f"tool-entry-file\t{tool}\t{digest}")
    toolchain_lines.append(f"tool-resolved\t{tool}\t{tool}\t{digest}")
toolchain_lines.extend((
    f"compiler-internal-file\tcc1\tlibexec/gcc/cc1\t{digest}",
    f"compiler-internal-file\tlibgcc\tlib/gcc/libgcc.a\t{digest}",
    "compiler-internal-tree\tinclude\tlib/gcc/include\t32\t4096\t"
    f"{digest}\tno-symlinks-special-nodes",
    "uboot-lto\tdisabled",
    f"bl31\t{module.BL31_BYTES}\t{module.BL31_SHA256}",
))
toolchain = output.parent / "toolchain.tsv"
toolchain.write_text("\n".join(toolchain_lines) + "\n", encoding="utf-8")
module.publish(
    baseline_a,
    baseline_b,
    green_a,
    green_b,
    oracle,
    bl31_path,
    toolchain,
    output,
)
PY
fi
[ -d "$EARLY_UBOOT_BUILD" ] && [ ! -L "$EARLY_UBOOT_BUILD" ] ||
	fail 'reviewed early-LED U-Boot authority is required'
COPYFILE_DISABLE=1 cp -R "$EARLY_UBOOT_BUILD" "$EARLY_ARTIFACTS"
[ -d "$ENV_UBOOT_BUILD" ] && [ ! -L "$ENV_UBOOT_BUILD" ] ||
	fail 'reviewed nowhere-environment U-Boot authority is required'
COPYFILE_DISABLE=1 cp -R "$ENV_UBOOT_BUILD" "$ENV_ARTIFACTS"
DIRECT_ARTIFACTS=$CASE_ROOT/direct-artifacts
[ -d "$DIRECT_UBOOT_BUILD" ] && [ ! -L "$DIRECT_UBOOT_BUILD" ] ||
	fail 'reviewed direct-extlinux U-Boot authority is required'
COPYFILE_DISABLE=1 cp -R "$DIRECT_UBOOT_BUILD" "$DIRECT_ARTIFACTS"
[ -d "$NO_HEAP_CLEAR_UBOOT_BUILD" ] && [ ! -L "$NO_HEAP_CLEAR_UBOOT_BUILD" ] ||
	fail 'verified no-heap-clear U-Boot authority is required'
COPYFILE_DISABLE=1 cp -R "$NO_HEAP_CLEAR_UBOOT_BUILD" \
	"$NO_HEAP_CLEAR_ARTIFACTS"
[ -d "$FAST_INIT_UBOOT_BUILD" ] && [ ! -L "$FAST_INIT_UBOOT_BUILD" ] ||
	fail 'verified fast-init U-Boot authority is required'
COPYFILE_DISABLE=1 cp -R "$FAST_INIT_UBOOT_BUILD" "$FAST_INIT_ARTIFACTS"
[ -d "$INPLACE_HANDOFF_UBOOT_BUILD" ] && [ ! -L "$INPLACE_HANDOFF_UBOOT_BUILD" ] ||
	fail 'verified in-place-handoff U-Boot authority is required'
COPYFILE_DISABLE=1 cp -R "$INPLACE_HANDOFF_UBOOT_BUILD" \
	"$INPLACE_HANDOFF_ARTIFACTS"
[ -d "$BOOTSTAGE_FDT_UBOOT_BUILD" ] && [ ! -L "$BOOTSTAGE_FDT_UBOOT_BUILD" ] ||
	fail 'reviewed bootstage-FDT measurement authority is required'
COPYFILE_DISABLE=1 cp -R "$BOOTSTAGE_FDT_UBOOT_BUILD" \
	"$BOOTSTAGE_FDT_ARTIFACTS"
LZ4_PAIR_AVAILABLE=0
if [ -d "$LZ4_PAIR_UBOOT_BUILD" ] && [ ! -L "$LZ4_PAIR_UBOOT_BUILD" ]; then
	COPYFILE_DISABLE=1 cp -R "$LZ4_PAIR_UBOOT_BUILD" "$LZ4_PAIR_ARTIFACTS"
	LZ4_PAIR_AVAILABLE=1
fi
[ -d "$SIMPLE_PARSER_UBOOT_BUILD" ] && [ ! -L "$SIMPLE_PARSER_UBOOT_BUILD" ] ||
	fail 'reviewed simple-parser U-Boot authority is required'
COPYFILE_DISABLE=1 cp -R "$SIMPLE_PARSER_UBOOT_BUILD" \
	"$SIMPLE_PARSER_ARTIFACTS"
[ -d "$FIXED_READ_PATH_UBOOT_BUILD" ] && [ ! -L "$FIXED_READ_PATH_UBOOT_BUILD" ] ||
	fail 'reviewed fixed-read-path U-Boot authority is required'
COPYFILE_DISABLE=1 cp -R "$FIXED_READ_PATH_UBOOT_BUILD" \
	"$FIXED_READ_PATH_ARTIFACTS"
[ -d "$FIXED_COMMAND_CLOSURE_UBOOT_BUILD" ] &&
	[ ! -L "$FIXED_COMMAND_CLOSURE_UBOOT_BUILD" ] ||
	fail 'reviewed fixed-command-closure U-Boot authority is required'
COPYFILE_DISABLE=1 cp -R "$FIXED_COMMAND_CLOSURE_UBOOT_BUILD" \
	"$FIXED_COMMAND_CLOSURE_ARTIFACTS"
BASELINE=$ARTIFACTS/rocknix-baseline.bin
CANDIDATE=$ARTIFACTS/bird-uboot-green.bin

cat >"$DEVICE_INFO" <<EOF
$BIRD	Part of Whole	$WHOLE
$DATA	Part of Whole	$WHOLE
/dev/$WHOLE	Device Location	External
/dev/$WHOLE	Protocol	USB
/dev/$WHOLE	Removable Media	Removable
/dev/$WHOLE	Disk Size	512074186752 Bytes (512074186752 Bytes)
/dev/$WHOLE	Internal	false
/dev/$WHOLE	Removable	true
$BIRD	Device Identifier	${WHOLE}s1
$DATA	Device Identifier	${WHOLE}s6
$BIRD	Partition Offset	16777216 Bytes
$BIRD	Disk Size	134217728 Bytes (134217728 Bytes)
/dev/${WHOLE}s5	Partition Offset	163577856 Bytes
/dev/${WHOLE}s5	Disk Size	8589934592 Bytes (8589934592 Bytes)
$DATA	Partition Offset	8753512448 Bytes
$DATA	Disk Size	503320672768 Bytes (503320672768 Bytes)
$BIRD	Volume Read-Only	No
$DATA	Volume Read-Only	No
EOF

reset_raw() {
	cp "$EARLY_ARTIFACTS/baseline-prefix-16m.bin" "$RAW"
	"$GTRUNCATE" -s $((PREFIX_BYTES + TAIL_BYTES)) "$RAW"
	printf 'p1 sentinel outside the raw prefix\n' >"$CASE_ROOT/tail-sentinel"
	"$GDD" if="$CASE_ROOT/tail-sentinel" of="$RAW" bs=1 \
		seek="$PREFIX_BYTES" conv=notrunc status=none
}

flip_raw_byte() {
	python3 - "$RAW" "$1" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
offset = int(sys.argv[2])
with path.open("r+b") as image:
    image.seek(offset)
    original = image.read(1)
    assert len(original) == 1
    image.seek(offset)
    image.write(bytes((original[0] ^ 1,)))
PY
}

reset_raw
# Model the macOS raw-device contract directly: the former 621,049-byte write
# must be rejected without changing the fixture, while the installer below is
# allowed only when it submits the complete 621,056-byte sector span.
cp "$RAW" "$CASE_ROOT/raw.before-unaligned-probe"
if "$RAW_GDD" if="$BASELINE" of="$RAW" bs=64K seek="$RAW_OFFSET" \
	count="$UBOOT_BYTES" iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=fsync,notrunc status=none 2>"$CASE_ROOT/unaligned-probe.err"; then
	fail 'sector guard accepted the former unaligned raw write'
fi
cmp "$RAW" "$CASE_ROOT/raw.before-unaligned-probe" >/dev/null ||
	fail 'rejected unaligned raw write changed the fixture'
grep -Fq 'Invalid argument: unaligned raw write' \
	"$CASE_ROOT/unaligned-probe.err" ||
	fail 'sector guard did not model the observed macOS failure'
TEST_BASELINE_PREFIX_SHA=$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')
RESTORE_ARTIFACTS=$CASE_ROOT/restore-artifacts
mkdir "$RESTORE_ARTIFACTS"
cp "$ARTIFACTS/rocknix-baseline.bin" "$RESTORE_ARTIFACTS/shipping-baseline.bin"
"$GDD" if="$RAW" of="$RESTORE_ARTIFACTS/baseline-prefix-16m.bin" bs=4M \
	count="$PREFIX_BYTES" iflag=count_bytes,fullblock status=none
cp "$RAW" "$CASE_ROOT/green-prefix-oracle"
"$GDD" if="$CANDIDATE" of="$CASE_ROOT/green-prefix-oracle" bs=64K \
	seek="$RAW_OFFSET" count="$UBOOT_BYTES" \
	iflag=count_bytes,fullblock oflag=seek_bytes conv=notrunc status=none
TEST_GREEN_PREFIX_SHA=$("$GDD" if="$CASE_ROOT/green-prefix-oracle" \
	bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock status=none |
	shasum -a 256 | awk '{print $1}')
cp "$CASE_ROOT/green-prefix-oracle" "$CASE_ROOT/early-prefix-oracle"
"$GDD" if="$EARLY_ARTIFACTS/early-green.bin" \
	of="$CASE_ROOT/early-prefix-oracle" bs=64K seek="$RAW_OFFSET" \
	count=621073 iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=notrunc status=none
TEST_EARLY_PREFIX_SHA=$("$GDD" if="$CASE_ROOT/early-prefix-oracle" \
	bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock status=none |
	shasum -a 256 | awk '{print $1}')
cp "$EARLY_ARTIFACTS/baseline-prefix-16m.bin" "$CASE_ROOT/env-prefix-oracle"
"$GDD" if="$ENV_ARTIFACTS/env-nowhere.bin" of="$CASE_ROOT/env-prefix-oracle" \
	bs=64K seek="$RAW_OFFSET" count=620745 iflag=count_bytes,fullblock \
	oflag=seek_bytes conv=notrunc status=none
TEST_ENV_PREFIX_SHA=$(shasum -a 256 "$CASE_ROOT/env-prefix-oracle" | awk '{print $1}')
cp "$ENV_ARTIFACTS/baseline-prefix-16m.bin" "$CASE_ROOT/direct-prefix-oracle"
"$GDD" if="$DIRECT_ARTIFACTS/direct-extlinux.bin" \
	of="$CASE_ROOT/direct-prefix-oracle" bs=64K seek="$RAW_OFFSET" \
	count=620745 iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=notrunc status=none
TEST_DIRECT_PREFIX_SHA=$(shasum -a 256 "$CASE_ROOT/direct-prefix-oracle" | awk '{print $1}')
[ "$TEST_DIRECT_PREFIX_SHA" = f81187878bbe491dabaf1a4f5fda051d4edabbcb476681d1323d73557e3072ff ] ||
	fail 'direct-extlinux fixture does not match the reviewed prefix identity'
cp "$NO_HEAP_CLEAR_ARTIFACTS/baseline-prefix-16m.bin" \
	"$CASE_ROOT/no-heap-clear-prefix-oracle"
	"$GDD" if="$NO_HEAP_CLEAR_ARTIFACTS/no-heap-clear.bin" \
	of="$CASE_ROOT/no-heap-clear-prefix-oracle" bs=64K seek="$RAW_OFFSET" \
	count="$NO_HEAP_CLEAR_UBOOT_BYTES" iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=notrunc status=none
TEST_NO_HEAP_CLEAR_UBOOT_SHA=$(shasum -a 256 \
	"$NO_HEAP_CLEAR_ARTIFACTS/no-heap-clear.bin" | awk '{print $1}')
TEST_NO_HEAP_CLEAR_PREFIX_SHA=$(shasum -a 256 \
	"$CASE_ROOT/no-heap-clear-prefix-oracle" | awk '{print $1}')
cp "$FAST_INIT_ARTIFACTS/base-no-heap-clear-prefix-16m.bin" \
	"$CASE_ROOT/fast-init-prefix-oracle"
"$GDD" if="$FAST_INIT_ARTIFACTS/fast-init.bin" \
	of="$CASE_ROOT/fast-init-prefix-oracle" bs=64K seek="$RAW_OFFSET" \
	count="$FAST_INIT_UBOOT_BYTES" iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=notrunc status=none
TEST_FAST_INIT_UBOOT_SHA=$(shasum -a 256 \
	"$FAST_INIT_ARTIFACTS/fast-init.bin" | awk '{print $1}')
TEST_FAST_INIT_PREFIX_SHA=$(shasum -a 256 \
	"$CASE_ROOT/fast-init-prefix-oracle" | awk '{print $1}')
cp "$INPLACE_HANDOFF_ARTIFACTS/base-fast-init-prefix-16m.bin" \
	"$CASE_ROOT/inplace-handoff-prefix-oracle"
"$GDD" if="$INPLACE_HANDOFF_ARTIFACTS/inplace-handoff.bin" \
	of="$CASE_ROOT/inplace-handoff-prefix-oracle" bs=64K seek="$RAW_OFFSET" \
	count="$INPLACE_HANDOFF_UBOOT_BYTES" iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=notrunc status=none
TEST_INPLACE_HANDOFF_UBOOT_SHA=$(shasum -a 256 \
	"$INPLACE_HANDOFF_ARTIFACTS/inplace-handoff.bin" | awk '{print $1}')
TEST_INPLACE_HANDOFF_PREFIX_SHA=$(shasum -a 256 \
	"$CASE_ROOT/inplace-handoff-prefix-oracle" | awk '{print $1}')
if [ "$LZ4_PAIR_AVAILABLE" -eq 1 ]; then
	TEST_LZ4_PAIR_UBOOT_SHA=$(shasum -a 256 \
		"$LZ4_PAIR_ARTIFACTS/lz4-pair.bin" | awk '{print $1}')
	TEST_LZ4_PAIR_PREFIX_SHA=$(shasum -a 256 \
		"$LZ4_PAIR_ARTIFACTS/lz4-pair-prefix-16m.bin" | awk '{print $1}')
fi
TEST_SIMPLE_PARSER_UBOOT_SHA=$(shasum -a 256 \
	"$SIMPLE_PARSER_ARTIFACTS/simple-parser.bin" | awk '{print $1}')
TEST_SIMPLE_PARSER_PREFIX_SHA=$(shasum -a 256 \
	"$SIMPLE_PARSER_ARTIFACTS/simple-parser-prefix-16m.bin" | awk '{print $1}')
TEST_FIXED_READ_PATH_UBOOT_SHA=$(shasum -a 256 \
	"$FIXED_READ_PATH_ARTIFACTS/fixed-read-path.bin" | awk '{print $1}')
TEST_FIXED_READ_PATH_PREFIX_SHA=$(shasum -a 256 \
	"$FIXED_READ_PATH_ARTIFACTS/fixed-read-path-prefix-16m.bin" | awk '{print $1}')
TEST_FIXED_COMMAND_CLOSURE_UBOOT_SHA=$(shasum -a 256 \
	"$FIXED_COMMAND_CLOSURE_ARTIFACTS/fixed-command-closure.bin" | awk '{print $1}')
TEST_FIXED_COMMAND_CLOSURE_PREFIX_SHA=$(shasum -a 256 \
	"$FIXED_COMMAND_CLOSURE_ARTIFACTS/fixed-command-closure-prefix-16m.bin" | awk '{print $1}')
cp "$BOOTSTAGE_FDT_ARTIFACTS/bootstage-fdt-prefix-16m.bin" \
	"$CASE_ROOT/bootstage-fdt-prefix-oracle"
TEST_BOOTSTAGE_FDT_UBOOT_SHA=$(shasum -a 256 \
	"$BOOTSTAGE_FDT_ARTIFACTS/bird-uboot-bootstage-fdt.bin" | awk '{print $1}')
TEST_BOOTSTAGE_FDT_PREFIX_SHA=$(shasum -a 256 \
	"$CASE_ROOT/bootstage-fdt-prefix-oracle" | awk '{print $1}')
TEST_BOOTSTAGE_FDT_MANIFEST_SHA=$(shasum -a 256 \
	"$BIRD/bird-releases/v6.23-20260814-201218/deploy-manifest.tsv" |
	awk '{print $1}')

run_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-green "$ARTIFACTS"
}

run_early_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-early-green \
		"$EARLY_ARTIFACTS"
}

run_early_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-early-green "$EARLY_ARTIFACTS"
}

run_env_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		BIRD_TEST_ENV_PREFIX_SHA=$TEST_ENV_PREFIX_SHA GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-env-nowhere "$ENV_ARTIFACTS"
}

run_direct_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		BIRD_TEST_ENV_PREFIX_SHA=$TEST_ENV_PREFIX_SHA GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-direct-extlinux \
		"$DIRECT_ARTIFACTS"
}

run_no_heap_clear_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		BIRD_TEST_ENV_PREFIX_SHA=$TEST_ENV_PREFIX_SHA \
		BIRD_TEST_NO_HEAP_CLEAR_UBOOT_SHA=$TEST_NO_HEAP_CLEAR_UBOOT_SHA \
		BIRD_TEST_NO_HEAP_CLEAR_PREFIX_SHA=$TEST_NO_HEAP_CLEAR_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-no-heap-clear \
		"$NO_HEAP_CLEAR_ARTIFACTS"
}

run_no_heap_clear_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		BIRD_TEST_ENV_PREFIX_SHA=$TEST_ENV_PREFIX_SHA \
		BIRD_TEST_NO_HEAP_CLEAR_UBOOT_SHA=$TEST_NO_HEAP_CLEAR_UBOOT_SHA \
		BIRD_TEST_NO_HEAP_CLEAR_PREFIX_SHA=$TEST_NO_HEAP_CLEAR_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-no-heap-clear \
		"$NO_HEAP_CLEAR_ARTIFACTS"
}

run_fast_init_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		BIRD_TEST_ENV_PREFIX_SHA=$TEST_ENV_PREFIX_SHA \
		BIRD_TEST_FAST_INIT_UBOOT_SHA=$TEST_FAST_INIT_UBOOT_SHA \
		BIRD_TEST_FAST_INIT_PREFIX_SHA=$TEST_FAST_INIT_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-fast-init \
		"$FAST_INIT_ARTIFACTS"
}

run_fast_init_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		BIRD_TEST_ENV_PREFIX_SHA=$TEST_ENV_PREFIX_SHA \
		BIRD_TEST_FAST_INIT_UBOOT_SHA=$TEST_FAST_INIT_UBOOT_SHA \
		BIRD_TEST_FAST_INIT_PREFIX_SHA=$TEST_FAST_INIT_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-fast-init \
		"$FAST_INIT_ARTIFACTS"
}

run_inplace_handoff_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		BIRD_TEST_ENV_PREFIX_SHA=$TEST_ENV_PREFIX_SHA \
		BIRD_TEST_INPLACE_HANDOFF_UBOOT_SHA=$TEST_INPLACE_HANDOFF_UBOOT_SHA \
		BIRD_TEST_INPLACE_HANDOFF_PREFIX_SHA=$TEST_INPLACE_HANDOFF_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-inplace-handoff \
		"$INPLACE_HANDOFF_ARTIFACTS"
}

run_inplace_handoff_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA \
		BIRD_TEST_ENV_PREFIX_SHA=$TEST_ENV_PREFIX_SHA \
		BIRD_TEST_INPLACE_HANDOFF_UBOOT_SHA=$TEST_INPLACE_HANDOFF_UBOOT_SHA \
		BIRD_TEST_INPLACE_HANDOFF_PREFIX_SHA=$TEST_INPLACE_HANDOFF_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-inplace-handoff \
		"$INPLACE_HANDOFF_ARTIFACTS"
}

run_lz4_pair_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_LZ4_PAIR_UBOOT_SHA=$TEST_LZ4_PAIR_UBOOT_SHA \
		BIRD_TEST_LZ4_PAIR_PREFIX_SHA=$TEST_LZ4_PAIR_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-lz4-pair \
		"$LZ4_PAIR_ARTIFACTS"
}

run_lz4_pair_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_LZ4_PAIR_UBOOT_SHA=$TEST_LZ4_PAIR_UBOOT_SHA \
		BIRD_TEST_LZ4_PAIR_PREFIX_SHA=$TEST_LZ4_PAIR_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-lz4-pair "$LZ4_PAIR_ARTIFACTS"
}

run_lz4_pair_restore() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_LZ4_PAIR_UBOOT_SHA=$TEST_LZ4_PAIR_UBOOT_SHA \
		BIRD_TEST_LZ4_PAIR_PREFIX_SHA=$TEST_LZ4_PAIR_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --restore-inplace-from-lz4 \
		"$LZ4_PAIR_ARTIFACTS"
}

run_simple_parser_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-simple-parser \
		"$SIMPLE_PARSER_ARTIFACTS"
}

run_simple_parser_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-simple-parser \
		"$SIMPLE_PARSER_ARTIFACTS"
}

run_simple_parser_restore() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" \
		--restore-lz4-from-simple-parser "$SIMPLE_PARSER_ARTIFACTS"
}

run_fixed_read_path_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-fixed-read-path \
		"$FIXED_READ_PATH_ARTIFACTS"
}

run_fixed_read_path_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-fixed-read-path \
		"$FIXED_READ_PATH_ARTIFACTS"
}

run_fixed_read_path_restore() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" \
		--restore-simple-parser-from-fixed-read-path "$FIXED_READ_PATH_ARTIFACTS"
}

run_fixed_command_closure_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-fixed-command-closure \
		"$FIXED_COMMAND_CLOSURE_ARTIFACTS"
}

run_fixed_command_closure_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-fixed-command-closure \
		"$FIXED_COMMAND_CLOSURE_ARTIFACTS"
}

run_fixed_command_closure_restore() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" \
		--restore-fixed-read-path-from-command-closure \
		"$FIXED_COMMAND_CLOSURE_ARTIFACTS"
}

run_bootstage_fdt_installer() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_BOOTSTAGE_FDT_MANIFEST_SHA=$TEST_BOOTSTAGE_FDT_MANIFEST_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --install-bootstage-fdt \
		"$BOOTSTAGE_FDT_ARTIFACTS"
}

run_bootstage_fdt_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_BOOTSTAGE_FDT_MANIFEST_SHA=$TEST_BOOTSTAGE_FDT_MANIFEST_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-bootstage-fdt \
		"$BOOTSTAGE_FDT_ARTIFACTS"
}

run_inplace_handoff_restore() {
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_BOOTSTAGE_FDT_MANIFEST_SHA=$TEST_BOOTSTAGE_FDT_MANIFEST_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --restore-inplace-handoff \
		"$BOOTSTAGE_FDT_ARTIFACTS"
}

run_inplace_handoff_restore_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_BOOTSTAGE_FDT_MANIFEST_SHA=$TEST_BOOTSTAGE_FDT_MANIFEST_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --restore-inplace-handoff \
		"$BOOTSTAGE_FDT_ARTIFACTS"
}

run_restore() {
	RESTORE_BUILD=${1:-$RESTORE_ARTIFACTS}
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		GDD=$RAW_GDD sh "$INSTALLER" "/dev/$WHOLE" --restore-baseline "$RESTORE_BUILD"
}

run_restore_failpoint() {
	FAILPOINT=$1
	RESTORE_BUILD=${2:-$RESTORE_ARTIFACTS}
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --restore-baseline "$RESTORE_BUILD"
}

run_failpoint() {
	FAILPOINT=$1
	BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT BIRD=$BIRD DATA=$DATA \
		BIRD_DEVICE_INFO=$DEVICE_INFO BIRD_TEST_RAW_DISK=$RAW \
		BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
		BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA \
		BIRD_TEST_FAILPOINT=$FAILPOINT GDD=$RAW_GDD \
		sh "$INSTALLER" "/dev/$WHOLE" --install-green "$ARTIFACTS"
}

expect_prewrite_rejection() {
	CASE_NAME=$1
	EXPECTED_ERROR=$2
	reset_raw
	cp "$RAW" "$CASE_ROOT/$CASE_NAME.raw-before"
	if run_installer >"$CASE_ROOT/$CASE_NAME.out" \
		2>"$CASE_ROOT/$CASE_NAME.err"; then
		fail "invalid selected release was accepted: $CASE_NAME"
	fi
	cmp "$RAW" "$CASE_ROOT/$CASE_NAME.raw-before" >/dev/null ||
		fail "selected-release rejection changed raw bytes: $CASE_NAME"
	grep -Fq "$EXPECTED_ERROR" "$CASE_ROOT/$CASE_NAME.err" ||
		fail "prewrite rejection was not explicit: $CASE_NAME"
}

# The historical capacity installer let sudo create a root-owned 0600
# snapshot, then invoked cmp as the user. Guard the corrected ownership model.
grep -Fq ': >"$SNAPSHOT"' "$INSTALLER" ||
	fail 'raw-read snapshot is not created by the invoking user'
grep -Fq 'status=none >"$DESTINATION"' "$INSTALLER" ||
	fail 'privileged raw reads no longer redirect into a user-owned snapshot'
if grep -E 'sudo .*of=.*(VERIFY_WORK|DESTINATION|prefix\.bin)' "$INSTALLER" >/dev/null; then
	fail 'sudo can create a root-owned host verification snapshot'
fi

# Production accepts only the independently reviewed four-pass result. The
# fallback fixture remains useful when that slow host artifact is absent, but
# its structurally valid modeled candidate must not inherit the promotion.
if [ "$USING_REVIEWED_AUTHORITY" -eq 1 ]; then
	python3 "$ROOT/kernel/rocknix/verify-uboot-install-authority.py" \
		"$ARTIFACTS" >"$CASE_ROOT/production-authority.out" \
		2>"$CASE_ROOT/production-authority.err" ||
		fail 'production verifier rejected the reviewed four-pass result'
else
	if python3 "$ROOT/kernel/rocknix/verify-uboot-install-authority.py" \
		"$ARTIFACTS" >"$CASE_ROOT/production-authority.out" \
		2>"$CASE_ROOT/production-authority.err"; then
		fail 'production verifier accepted an unreviewed synthetic candidate'
	fi
	grep -Fq 'green U-Boot candidate is not the reviewed result' \
		"$CASE_ROOT/production-authority.err" ||
		fail 'production verifier did not reject the unreviewed result explicitly'
fi

grep -Fq \
	'GREEN_PREFIX_SHA=fe363dd09e40ccef994912c01ed1c77d3285485299a40ce7ae7fc74431b5a998' \
	"$INSTALLER" || fail 'reviewed green prefix identity is not pinned'
NO_HEAP_CLEAR_INSTALLER_SHA=$(sed -n \
	's/^NO_HEAP_CLEAR_UBOOT_SHA=//p' "$INSTALLER")
NO_HEAP_CLEAR_INSTALLER_PREFIX_SHA=$(sed -n \
	's/^NO_HEAP_CLEAR_PREFIX_SHA=//p' "$INSTALLER")
case "$NO_HEAP_CLEAR_INSTALLER_SHA:$NO_HEAP_CLEAR_INSTALLER_PREFIX_SHA" in
	pending:pending) ;;
	pending:*|*:pending)
		fail 'no-heap-clear candidate and prefix promotion is not atomic'
		;;
	*)
		printf '%s\n' "$NO_HEAP_CLEAR_INSTALLER_SHA" |
			grep -Eq '^[0-9a-f]{64}$' &&
			printf '%s\n' "$NO_HEAP_CLEAR_INSTALLER_PREFIX_SHA" |
			grep -Eq '^[0-9a-f]{64}$' ||
			fail 'promoted no-heap-clear installer identities are malformed'
		[ "$NO_HEAP_CLEAR_INSTALLER_SHA" = "$TEST_NO_HEAP_CLEAR_UBOOT_SHA" ] &&
			[ "$NO_HEAP_CLEAR_INSTALLER_PREFIX_SHA" = \
				"$TEST_NO_HEAP_CLEAR_PREFIX_SHA" ] ||
			fail 'promoted no-heap-clear installer identities differ from authority'
		;;
esac
FAST_INIT_INSTALLER_SHA=$(sed -n 's/^FAST_INIT_UBOOT_SHA=//p' "$INSTALLER")
FAST_INIT_INSTALLER_PREFIX_SHA=$(sed -n \
	's/^FAST_INIT_PREFIX_SHA=//p' "$INSTALLER")
case "$FAST_INIT_INSTALLER_SHA:$FAST_INIT_INSTALLER_PREFIX_SHA" in
	pending:pending) ;;
	pending:*|*:pending)
		fail 'fast-init candidate and prefix promotion is not atomic'
		;;
	*)
		printf '%s\n' "$FAST_INIT_INSTALLER_SHA" |
			grep -Eq '^[0-9a-f]{64}$' &&
			printf '%s\n' "$FAST_INIT_INSTALLER_PREFIX_SHA" |
			grep -Eq '^[0-9a-f]{64}$' ||
			fail 'promoted fast-init installer identities are malformed'
		[ "$FAST_INIT_INSTALLER_SHA" = "$TEST_FAST_INIT_UBOOT_SHA" ] &&
			[ "$FAST_INIT_INSTALLER_PREFIX_SHA" = \
				"$TEST_FAST_INIT_PREFIX_SHA" ] ||
			fail 'promoted fast-init installer identities differ from authority'
		;;
esac
INPLACE_HANDOFF_INSTALLER_SHA=$(sed -n \
	's/^INPLACE_HANDOFF_UBOOT_SHA=//p' "$INSTALLER")
INPLACE_HANDOFF_INSTALLER_PREFIX_SHA=$(sed -n \
	's/^INPLACE_HANDOFF_PREFIX_SHA=//p' "$INSTALLER")
printf '%s\n' "$INPLACE_HANDOFF_INSTALLER_SHA" |
	grep -Eq '^[0-9a-f]{64}$' &&
	printf '%s\n' "$INPLACE_HANDOFF_INSTALLER_PREFIX_SHA" |
	grep -Eq '^[0-9a-f]{64}$' ||
	fail 'promoted in-place-handoff installer identities are malformed'
[ "$INPLACE_HANDOFF_INSTALLER_SHA" = "$TEST_INPLACE_HANDOFF_UBOOT_SHA" ] &&
	[ "$INPLACE_HANDOFF_INSTALLER_PREFIX_SHA" = \
		"$TEST_INPLACE_HANDOFF_PREFIX_SHA" ] ||
	fail 'promoted in-place-handoff installer identities differ from authority'
SIMPLE_PARSER_INSTALLER_SHA=$(sed -n \
	's/^SIMPLE_PARSER_UBOOT_SHA=//p' "$INSTALLER")
SIMPLE_PARSER_INSTALLER_PREFIX_SHA=$(sed -n \
	's/^SIMPLE_PARSER_PREFIX_SHA=//p' "$INSTALLER")
[ "$SIMPLE_PARSER_INSTALLER_SHA" = "$TEST_SIMPLE_PARSER_UBOOT_SHA" ] &&
	[ "$SIMPLE_PARSER_INSTALLER_PREFIX_SHA" = \
		"$TEST_SIMPLE_PARSER_PREFIX_SHA" ] ||
	fail 'simple-parser installer identities differ from reviewed authority'
grep -Fq \
	'SIMPLE_PARSER_AUTHORITY_SHA=4037c6c7e04df724dc3e817dbf2b4708dbbca2489e9a111e0edcac65b0a3b700' \
	"$INSTALLER" ||
	fail 'simple-parser installer does not pin the reviewed authority record'
FIXED_READ_PATH_INSTALLER_SHA=$(sed -n \
	's/^FIXED_READ_PATH_UBOOT_SHA=//p' "$INSTALLER")
FIXED_READ_PATH_INSTALLER_PREFIX_SHA=$(sed -n \
	's/^FIXED_READ_PATH_PREFIX_SHA=//p' "$INSTALLER")
[ "$FIXED_READ_PATH_INSTALLER_SHA" = "$TEST_FIXED_READ_PATH_UBOOT_SHA" ] &&
	[ "$FIXED_READ_PATH_INSTALLER_PREFIX_SHA" = \
		"$TEST_FIXED_READ_PATH_PREFIX_SHA" ] ||
	fail 'fixed-read-path installer identities differ from reviewed authority'
grep -Fq \
	'FIXED_READ_PATH_AUTHORITY_SHA=4e387e0b326fb84d9cdc04fa34dccec4d79d46b8df8b6cfff0233d0d10632a37' \
	"$INSTALLER" ||
fail 'fixed-read-path installer does not pin the reviewed authority record'
FIXED_COMMAND_CLOSURE_INSTALLER_SHA=$(sed -n \
	's/^FIXED_COMMAND_CLOSURE_UBOOT_SHA=//p' "$INSTALLER")
FIXED_COMMAND_CLOSURE_INSTALLER_PREFIX_SHA=$(sed -n \
	's/^FIXED_COMMAND_CLOSURE_PREFIX_SHA=//p' "$INSTALLER")
[ "$FIXED_COMMAND_CLOSURE_INSTALLER_SHA" = \
	"$TEST_FIXED_COMMAND_CLOSURE_UBOOT_SHA" ] &&
	[ "$FIXED_COMMAND_CLOSURE_INSTALLER_PREFIX_SHA" = \
		"$TEST_FIXED_COMMAND_CLOSURE_PREFIX_SHA" ] ||
	fail 'fixed-command-closure installer identities differ from reviewed authority'
grep -Fq \
	'FIXED_COMMAND_CLOSURE_AUTHORITY_SHA=f03b3ecfea6966284a8aff5fcd7aff42856314047e5a67421b73e141dc514187' \
	"$INSTALLER" ||
	fail 'fixed-command-closure installer does not pin the reviewed authority record'
BOOTSTAGE_FDT_INSTALLER_SHA=$(sed -n \
	's/^BOOTSTAGE_FDT_UBOOT_SHA=//p' "$INSTALLER")
BOOTSTAGE_FDT_INSTALLER_PREFIX_SHA=$(sed -n \
	's/^BOOTSTAGE_FDT_PREFIX_SHA=//p' "$INSTALLER")
[ "$BOOTSTAGE_FDT_INSTALLER_SHA" = "$TEST_BOOTSTAGE_FDT_UBOOT_SHA" ] &&
	[ "$BOOTSTAGE_FDT_INSTALLER_PREFIX_SHA" = \
		"$TEST_BOOTSTAGE_FDT_PREFIX_SHA" ] ||
	fail 'bootstage-FDT installer identities differ from reviewed authority'
grep -Fq 'BOOTSTAGE_FDT_CLASSIFICATION=temporary-measurement-only' \
	"$INSTALLER" ||
	fail 'bootstage-FDT installer does not retain its measurement-only classification'
grep -Fq 'BOOTSTAGE_FDT_REQUIRED_RELEASE=v6.23-20260814-201218' \
	"$INSTALLER" ||
	fail 'bootstage-FDT installer does not pin the accepted canonical release'
grep -Fq \
	'BOOTSTAGE_FDT_REQUIRED_MANIFEST_SHA=904c8da42a6ec84ccf4b291205999c3b0e25900f4bec7bb3f9e0cfefb29164dd' \
	"$INSTALLER" ||
	fail 'bootstage-FDT installer does not pin the canonical manifest'
grep -Fq \
	'BOOTSTAGE_FDT_CAPTURE_SHA=e7fa642aa6b4a7407e7cae26bab37ae65a59036feac2d0aeb526811cecd50104' \
	"$INSTALLER" ||
	fail 'bootstage-FDT installer does not pin the capture helper inventory'
grep -Fq 'diskutil unmountDisk force "/dev/$WHOLE"' "$INSTALLER" ||
	fail 'recovery unmount no longer has the bounded whole-card force fallback'
grep -Fq \
	'080ae5fde3476addb5aa74f03a021aa4fbaa5deccb0964227c0fc91fe657b584' \
	"$ROOT/kernel/rocknix/verify-uboot-install-authority.py" ||
	fail 'reviewed green U-Boot identity is not pinned'

# The checksum list alone cannot replace the retained four-pass evidence. A
# changed B-pass binary with a freshly republished checksum list must still
# disagree with the sealed per-pass inventory before any installer path runs.
cp -R "$ARTIFACTS" "$CASE_ROOT/tampered-four-pass-authority"
TAMPERED_FOUR_PASS=$CASE_ROOT/tampered-four-pass-authority
python3 - "$TAMPERED_FOUR_PASS" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
path = root / "baseline-b-combined.bin"
data = bytearray(path.read_bytes())
data[100] ^= 1
path.write_bytes(data)
names = sorted(
    item.name for item in root.iterdir()
    if item.name not in {"authority.tsv", "sha256sums.txt"}
)
lines = [
    f"{hashlib.sha256((root / name).read_bytes()).hexdigest()}  {name}"
    for name in names
]
lines.append(
    f"{hashlib.sha256((root / 'authority.tsv').read_bytes()).hexdigest()}  authority.tsv"
)
(root / "sha256sums.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
PY
if BIRD_UBOOT_AUTHORITY_HOST_TEST=1 python3 \
	"$ROOT/kernel/rocknix/verify-uboot-install-authority.py" \
	--allow-unreviewed-test-candidate "$TAMPERED_FOUR_PASS" \
	>"$CASE_ROOT/four-pass-tamper.out" 2>"$CASE_ROOT/four-pass-tamper.err"; then
	fail 'checksummed but changed four-pass output was accepted'
fi
grep -Fq \
	'U-Boot four-pass retained artifact differs from inventory: baseline-b-combined.bin' \
	"$CASE_ROOT/four-pass-tamper.err" ||
	fail 'four-pass evidence rejection was not explicit'

# The installer independently revalidates both the exact publisher schema and
# the complete toolchain authority. A checksummed but semantically changed
# toolchain record cannot be accepted merely because all sums are republished.
cp -R "$ARTIFACTS" "$CASE_ROOT/tampered-toolchain-authority"
TAMPERED_AUTHORITY=$CASE_ROOT/tampered-toolchain-authority
sed -i '' 's/^uboot-lto\tdisabled$/uboot-lto\tenabled/' \
	"$TAMPERED_AUTHORITY/toolchain-authority.tsv"
python3 - "$TAMPERED_AUTHORITY" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
names = sorted(
    path.name for path in root.iterdir()
    if path.name not in {"authority.tsv", "sha256sums.txt"}
)
lines = [
    f"{hashlib.sha256((root / name).read_bytes()).hexdigest()}  {name}"
    for name in names
]
lines.append(
    f"{hashlib.sha256((root / 'authority.tsv').read_bytes()).hexdigest()}  authority.tsv"
)
(root / "sha256sums.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
PY
if BIRD_UBOOT_AUTHORITY_HOST_TEST=1 python3 \
	"$ROOT/kernel/rocknix/verify-uboot-install-authority.py" \
	--allow-unreviewed-test-candidate "$TAMPERED_AUTHORITY" \
	>"$CASE_ROOT/toolchain-tamper.out" 2>"$CASE_ROOT/toolchain-tamper.err"; then
	fail 'semantically changed toolchain authority was accepted'
fi
grep -Fq 'external toolchain authority field changed: uboot-lto' \
	"$CASE_ROOT/toolchain-tamper.err" ||
	fail 'toolchain-authority rejection was not explicit'

# The raw transaction is authorized only while the locked card has a canonical
# selector and a complete, manifest-bound selected release. Every rejection
# below must occur before even one raw fixture byte changes.
SELECTOR=$BIRD/extlinux/extlinux.conf
RELEASE=$BIRD/bird-releases/v6.23-20260814-201218
SELECTED_RELEASE=$(python3 \
	"$ROOT/kernel/rocknix/verify-selected-bird-release.py" \
	--host-test "$BIRD") || fail 'valid selected-release fixture was rejected'
[ "$SELECTED_RELEASE" = v6.23-20260814-201218 ] ||
	fail 'selected-release verifier returned the wrong release ID'

cp "$SELECTOR" "$CASE_ROOT/selector.saved"
printf 'LABEL FALLBACK\n  LINUX /KERNEL\n' >"$SELECTOR"
expect_prewrite_rejection fallback-selector \
	'active BIRD selector or selected release failed verification'
reset_raw
cp "$RAW" "$CASE_ROOT/fallback-restore.raw-before"
if run_restore >"$CASE_ROOT/fallback-restore.out" \
	2>"$CASE_ROOT/fallback-restore.err"; then
	fail 'baseline recovery accepted a fallback selector'
fi
cmp "$RAW" "$CASE_ROOT/fallback-restore.raw-before" >/dev/null ||
	fail 'baseline recovery selector rejection changed raw bytes'
grep -Fq 'active BIRD selector or selected release failed verification' \
	"$CASE_ROOT/fallback-restore.err" ||
	fail 'baseline recovery selector rejection was not explicit'
cp "$CASE_ROOT/selector.saved" "$SELECTOR"

printf '%s\n' \
	'LABEL BIRD' \
	'  LINUX /bird-releases/unknown/KERNEL' \
	'  INITRD /bird-releases/unknown/bird-initramfs.cpio.gz' \
	'  FDT /bird-releases/unknown/dtb.img' \
	'  APPEND bird_release=unknown' >"$SELECTOR"
expect_prewrite_rejection unknown-selector \
	'active BIRD selector or selected release failed verification'
cp "$CASE_ROOT/selector.saved" "$SELECTOR"

cp "$RELEASE/deploy-manifest.tsv" "$CASE_ROOT/manifest.saved"
printf 'malformed manifest record\n' >>"$RELEASE/deploy-manifest.tsv"
expect_prewrite_rejection corrupt-manifest \
	'active BIRD selector or selected release failed verification'
cp "$CASE_ROOT/manifest.saved" "$RELEASE/deploy-manifest.tsv"

cp "$RELEASE/.complete" "$CASE_ROOT/complete.saved"
printf '%064d\n' 0 >"$RELEASE/.complete"
expect_prewrite_rejection corrupt-completion-marker \
	'active BIRD selector or selected release failed verification'
cp "$CASE_ROOT/complete.saved" "$RELEASE/.complete"

cp "$RELEASE/KERNEL" "$CASE_ROOT/kernel.saved"
printf 'payload corruption\n' >>"$RELEASE/KERNEL"
expect_prewrite_rejection corrupt-release-payload \
	'active BIRD selector or selected release failed verification'
cp "$CASE_ROOT/kernel.saved" "$RELEASE/KERNEL"

python3 "$ROOT/kernel/rocknix/verify-selected-bird-release.py" \
	--host-test "$BIRD" >/dev/null ||
	fail 'selected release did not verify after restoring rejection fixtures'

printf 'obsolete fallback\n' >"$BIRD/KERNEL.fallback"
expect_prewrite_rejection obsolete-fallback \
	'obsolete alternate-boot state remains'
rm -f "$BIRD/KERNEL.fallback"

cp "$DATA/Bird/namespace-v1.tsv" "$CASE_ROOT/namespace.saved"
printf 'revision\tbird-canonical-namespace-v1\nstate\tpending\n' \
	>"$DATA/Bird/namespace-v1.tsv"
expect_prewrite_rejection corrupt-namespace \
	'canonical namespace v1 is not committed'
cp "$CASE_ROOT/namespace.saved" "$DATA/Bird/namespace-v1.tsv"

python3 "$INVENTORY" "$BIRD" >"$CASE_ROOT/bird.before.tsv"
reset_raw
cp "$RAW" "$CASE_ROOT/raw.before"
cp "$RAW" "$CASE_ROOT/raw.expected"
"$GDD" if="$CANDIDATE" of="$CASE_ROOT/raw.expected" bs=64K \
	seek="$RAW_OFFSET" count="$UBOOT_BYTES" \
	iflag=count_bytes,fullblock oflag=seek_bytes conv=notrunc status=none

run_installer >"$CASE_ROOT/install.out"
cmp "$RAW" "$CASE_ROOT/raw.expected" >/dev/null ||
	fail 'installer changed bytes outside or failed to change the exact U-Boot range'
python3 "$INVENTORY" "$BIRD" >"$CASE_ROOT/bird.after.tsv"
cmp "$CASE_ROOT/bird.before.tsv" "$CASE_ROOT/bird.after.tsv" >/dev/null ||
	fail 'installer changed the mounted BIRD inventory'
grep -Fq 'raw bytes [8192,629241)' "$CASE_ROOT/install.out" ||
	fail 'installer report omits the exact raw mutation range'
grep -Fq 'p1, p5, p6, and BIRD-DATA were not write targets' \
	"$CASE_ROOT/install.out" || fail 'installer report omits partition boundary'

# A second invocation verifies the exact candidate and performs no write.
RAW_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_installer >"$CASE_ROOT/noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RAW_SHA" ] ||
	fail 'idempotent verification changed the raw fixture'
grep -Fq 'already installed' "$CASE_ROOT/noop.out" ||
	fail 'idempotent verification did not report its no-op'

# A killed green write can leave a slice that is neither exact baseline nor
# exact candidate. Normal install stays fail-closed; explicit host recovery
# reconstructs the pinned baseline prefix while writing only the U-Boot range.
reset_raw
cp "$RAW" "$CASE_ROOT/recovery.expected"
PARTIAL_BYTES=$((UBOOT_BYTES / 2))
"$GDD" if="$CANDIDATE" of="$RAW" bs=64K seek="$RAW_OFFSET" \
	count="$PARTIAL_BYTES" iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=notrunc status=none
python3 - "$RAW" $((RAW_OFFSET + UBOOT_BYTES - 1)) <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
offset = int(sys.argv[2])
with path.open("r+b") as image:
    image.seek(offset)
    original = image.read(1)
    assert len(original) == 1
    image.seek(offset)
    image.write(bytes((original[0] ^ 1,)))
PY
"$GDD" if="$RAW" of="$CASE_ROOT/recovery-current.bin" bs=64K \
	skip="$RAW_OFFSET" count="$UBOOT_BYTES" \
	iflag=skip_bytes,count_bytes,fullblock status=none
if cmp "$CASE_ROOT/recovery-current.bin" "$BASELINE" >/dev/null ||
	cmp "$CASE_ROOT/recovery-current.bin" "$CANDIDATE" >/dev/null; then
	fail 'partial-write recovery fixture is not an unknown U-Boot slice'
fi
cp "$RAW" "$CASE_ROOT/recovery.partial"
if run_installer >"$CASE_ROOT/partial-install.out" \
	2>"$CASE_ROOT/partial-install.err"; then
	fail 'normal green install accepted a partially written U-Boot'
fi
cmp "$RAW" "$CASE_ROOT/recovery.partial" >/dev/null ||
	fail 'normal install rejection changed the partial U-Boot fixture'
BASELINE_ONLY=$CASE_ROOT/baseline-only-authority
mkdir "$BASELINE_ONLY"
cp "$BASELINE" "$BASELINE_ONLY/shipping-baseline.bin"
cp "$RESTORE_ARTIFACTS/baseline-prefix-16m.bin" \
	"$BASELINE_ONLY/baseline-prefix-16m.bin"
run_restore "$BASELINE_ONLY" >"$CASE_ROOT/restore.out"
cmp "$RAW" "$CASE_ROOT/recovery.expected" >/dev/null ||
	fail 'explicit recovery did not restore the exact accepted baseline card bytes'
grep -Fq 'raw bytes [8192,629265)' "$CASE_ROOT/restore.out" ||
	fail 'baseline recovery report omits the exact bounded write range'
grep -Fq 'Shipping baseline U-Boot restored' "$CASE_ROOT/restore.out" ||
	fail 'baseline recovery did not report verified completion'

# Recovery is also idempotent once the complete accepted baseline is present.
RECOVERED_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_restore >"$CASE_ROOT/restore-noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RECOVERED_SHA" ] ||
	fail 'baseline recovery no-op changed the raw fixture'
grep -Fq 'already restored' "$CASE_ROOT/restore-noop.out" ||
	fail 'baseline recovery no-op was not explicit'

# A normal recovery-path failure reasserts and verifies the accepted baseline,
# never the torn preimage that prompted recovery.
cp "$CASE_ROOT/recovery.partial" "$RAW"
if run_restore_failpoint after-write "$BASELINE_ONLY" \
	>"$CASE_ROOT/restore-failure.out" 2>"$CASE_ROOT/restore-failure.err"; then
	fail 'injected baseline-recovery failure unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/recovery.expected" >/dev/null ||
	fail 'failed recovery did not leave the exact accepted baseline prefix'
grep -Fq 'Exact accepted baseline 16 MiB prefix restored and verified' \
	"$CASE_ROOT/restore-failure.err" ||
	fail 'failed recovery did not explicitly verify its baseline repair'

cp "$CASE_ROOT/recovery.partial" "$RAW"
if run_restore_failpoint after-write-corrupt "$BASELINE_ONLY" \
	>"$CASE_ROOT/restore-corrupt.out" 2>"$CASE_ROOT/restore-corrupt.err"; then
	fail 'corrupt baseline-recovery readback unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/recovery.expected" >/dev/null ||
	fail 'corrupt recovery readback did not converge to the accepted baseline prefix'
grep -Fq 'Exact accepted baseline 16 MiB prefix restored and verified' \
	"$CASE_ROOT/restore-corrupt.err" ||
	fail 'corrupt recovery readback did not explicitly verify its baseline repair'

# The recovery authority is the complete sector span written by the action,
# including the 495-byte physical tail after the shorter logical image. Unknown
# bytes inside that span are repairable; the immediately following byte is not.
reset_raw
cp "$RAW" "$CASE_ROOT/restore-physical-tail.expected"
flip_raw_byte 629265
run_restore >"$CASE_ROOT/restore-physical-tail.out"
cmp "$RAW" "$CASE_ROOT/restore-physical-tail.expected" >/dev/null ||
	fail 'baseline recovery did not repair drift in its physical sector tail'

reset_raw
flip_raw_byte 629760
RESTORE_OUTSIDE_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_restore >"$CASE_ROOT/restore-outside-physical.out" \
	2>"$CASE_ROOT/restore-outside-physical.err"; then
	fail 'baseline recovery accepted drift immediately outside its physical span'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RESTORE_OUTSIDE_SHA" ] ||
	fail 'baseline outside-physical rejection changed raw bytes'
grep -Fq 'outside the recoverable U-Boot range' \
	"$CASE_ROOT/restore-outside-physical.err" ||
	fail 'baseline outside-physical rejection was not explicit'

reset_raw
cp "$RAW" "$CASE_ROOT/restore-tail-failpoint.expected"
flip_raw_byte 629759
if run_restore_failpoint after-write \
	>"$CASE_ROOT/restore-tail-failpoint.out" \
	2>"$CASE_ROOT/restore-tail-failpoint.err"; then
	fail 'tail-repair after-write failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/restore-tail-failpoint.expected" >/dev/null ||
	fail 'tail-repair after-write cleanup did not converge to the baseline'

flip_raw_byte 629759
if run_restore_failpoint after-write-corrupt \
	>"$CASE_ROOT/restore-tail-corrupt.out" \
	2>"$CASE_ROOT/restore-tail-corrupt.err"; then
	fail 'tail-repair corrupt-readback failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/restore-tail-failpoint.expected" >/dev/null ||
	fail 'tail-repair corrupt-readback cleanup did not converge to the baseline'

flip_raw_byte 629759
/bin/rm -f "$CASE_ROOT/recovery-unmount.tsv"
if run_restore_failpoint after-write-recovery-force-fallback \
	>"$CASE_ROOT/restore-force-fallback.out" \
	2>"$CASE_ROOT/restore-force-fallback.err"; then
	fail 'recovery force-fallback failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/restore-tail-failpoint.expected" >/dev/null ||
	fail 'force-fallback recovery did not converge to the exact baseline'
cmp "$CASE_ROOT/recovery-unmount.tsv" - <<'EOF' >/dev/null ||
ordinary-refused
force-succeeded
EOF
	fail 'host recovery did not prove ordinary-to-force unmount fallback'

# A normal failure immediately after the bounded write restores the complete
# original prefix and never touches the sentinel beyond it.
reset_raw
cp "$RAW" "$CASE_ROOT/raw.before-failure"
if run_failpoint after-write >"$CASE_ROOT/fail.out" 2>"$CASE_ROOT/fail.err"; then
	fail 'injected post-write failure unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/raw.before-failure" >/dev/null ||
	fail 'normal post-write failure did not restore the exact raw preimage'
grep -Fq 'Exact pre-transaction 16 MiB prefix restored and verified' \
	"$CASE_ROOT/fail.err" || fail 'restoration was not explicitly verified'

# A corrupted candidate readback takes the same verified restoration path.
reset_raw
cp "$RAW" "$CASE_ROOT/raw.before-corruption"
if run_failpoint after-write-corrupt \
	>"$CASE_ROOT/corrupt.out" 2>"$CASE_ROOT/corrupt.err"; then
	fail 'corrupt post-write readback unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/raw.before-corruption" >/dev/null ||
	fail 'corrupt post-write readback did not restore the exact raw preimage'

# Even if both externally supplied write artifacts drift after the candidate
# write, rollback uses the private raw preimage captured under the lock.
reset_raw
cp "$RAW" "$CASE_ROOT/raw.before-authority-drift"
cp "$ARTIFACTS/rocknix-baseline.bin" "$CASE_ROOT/baseline.saved"
cp "$ARTIFACTS/bird-uboot-green.bin" "$CASE_ROOT/candidate.saved"
if run_failpoint after-write-authority-drift \
	>"$CASE_ROOT/authority-drift.out" 2>"$CASE_ROOT/authority-drift.err"; then
	fail 'post-write authority drift unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/raw.before-authority-drift" >/dev/null ||
	fail 'authority drift prevented exact private-preimage restoration'
mv "$CASE_ROOT/baseline.saved" "$ARTIFACTS/rocknix-baseline.bin"
mv "$CASE_ROOT/candidate.saved" "$ARTIFACTS/bird-uboot-green.bin"

# Unknown active bootloader bytes and a changed candidate authority both fail
# before the first raw mutation.
reset_raw
printf '\001' | "$GDD" of="$RAW" bs=1 seek=700000 conv=notrunc status=none
UNKNOWN_GAP_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_installer >"$CASE_ROOT/unknown-gap.out" \
	2>"$CASE_ROOT/unknown-gap.err"; then
	fail 'unknown non-U-Boot boot-prefix bytes were accepted'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$UNKNOWN_GAP_SHA" ] ||
	fail 'unknown boot-prefix rejection changed the raw fixture'
grep -Fq 'complete current baseline 16 MiB prefix differs' \
	"$CASE_ROOT/unknown-gap.err" ||
	fail 'unknown boot-prefix rejection was not explicit'
if run_restore >"$CASE_ROOT/unknown-gap-restore.out" \
	2>"$CASE_ROOT/unknown-gap-restore.err"; then
	fail 'baseline recovery accepted drift outside the U-Boot range'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$UNKNOWN_GAP_SHA" ] ||
	fail 'recovery rejection changed the unknown-gap fixture'
grep -Fq 'current prefix differs from the accepted layout outside the recoverable U-Boot range' \
	"$CASE_ROOT/unknown-gap-restore.err" ||
	fail 'recovery outside-range rejection was not explicit'

reset_raw
"$GDD" if=/dev/zero of="$RAW" bs=1 seek=$((RAW_OFFSET + 4)) count=1 \
	conv=notrunc status=none
UNKNOWN_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_installer >"$CASE_ROOT/unknown.out" 2>"$CASE_ROOT/unknown.err"; then
	fail 'unknown active U-Boot bytes were accepted'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$UNKNOWN_SHA" ] ||
	fail 'unknown active U-Boot rejection changed the raw fixture'

reset_raw
cp "$ARTIFACTS/bird-uboot-green.bin" "$CASE_ROOT/candidate.saved"
printf 'tamper\n' >>"$ARTIFACTS/bird-uboot-green.bin"
RAW_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_installer >"$CASE_ROOT/tamper.out" 2>"$CASE_ROOT/tamper.err"; then
	fail 'changed candidate artifact was accepted'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$RAW_SHA" ] ||
	fail 'candidate-authority rejection changed the raw fixture'
mv "$CASE_ROOT/candidate.saved" "$ARTIFACTS/bird-uboot-green.bin"

# Recovery never accepts a self-authored or size-drifted baseline artifact.
reset_raw
cp "$RESTORE_ARTIFACTS/shipping-baseline.bin" "$CASE_ROOT/baseline.saved"
printf 'tamper\n' >>"$RESTORE_ARTIFACTS/shipping-baseline.bin"
BASELINE_TAMPER_RAW_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_restore >"$CASE_ROOT/baseline-tamper.out" \
	2>"$CASE_ROOT/baseline-tamper.err"; then
	fail 'changed shipping baseline oracle was accepted for recovery'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$BASELINE_TAMPER_RAW_SHA" ] ||
	fail 'baseline-oracle rejection changed the raw fixture'
grep -Fq 'shipping U-Boot baseline size changed' \
	"$CASE_ROOT/baseline-tamper.err" ||
	fail 'baseline-oracle rejection was not explicit'
mv "$CASE_ROOT/baseline.saved" "$RESTORE_ARTIFACTS/shipping-baseline.bin"

# The successor starts only from the exact reviewed full-U-Boot green prefix,
# writes its larger 1,214-sector span, is idempotent, and restores either its
# interrupted preimage or the complete shipping prefix without leaving its
# extra 24 logical bytes behind.
cp "$CASE_ROOT/green-prefix-oracle" "$RAW"
run_early_installer >"$CASE_ROOT/early-install.out"
cmp "$RAW" "$CASE_ROOT/early-prefix-oracle" >/dev/null ||
	fail 'early-green install did not produce its exact complete prefix'
grep -Fq 'raw bytes [8192,629265)' "$CASE_ROOT/early-install.out" ||
	fail 'early-green report omits the exact logical range'
grep -Fq 'sector-aligned [8192,629760)' "$CASE_ROOT/early-install.out" ||
	fail 'early-green report omits the exact physical range'
EARLY_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_early_installer >"$CASE_ROOT/early-noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$EARLY_SHA" ] ||
	fail 'early-green no-op changed the raw fixture'
grep -Fq 'already installed' "$CASE_ROOT/early-noop.out" ||
	fail 'early-green no-op was not explicit'

reset_raw
run_env_installer >"$CASE_ROOT/env-install.out"
[ "$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')" = "$TEST_ENV_PREFIX_SHA" ] ||
	fail 'nowhere-environment install did not produce its exact complete prefix'
grep -Fq 'Nowhere-environment U-Boot installed' "$CASE_ROOT/env-install.out" ||
	fail 'nowhere-environment completion was not explicit'
ENV_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_env_installer >"$CASE_ROOT/env-noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$ENV_SHA" ] ||
	fail 'nowhere-environment no-op changed the raw fixture'

run_direct_installer >"$CASE_ROOT/direct-install.out"
[ "$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')" = "$TEST_DIRECT_PREFIX_SHA" ] ||
	fail 'direct-extlinux install did not produce its exact complete prefix'
grep -Fq 'Direct-extlinux U-Boot installed' "$CASE_ROOT/direct-install.out" ||
	fail 'direct-extlinux completion was not explicit'
DIRECT_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_direct_installer >"$CASE_ROOT/direct-noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$DIRECT_SHA" ] ||
	fail 'direct-extlinux no-op changed the raw fixture'
grep -Fq 'already installed' "$CASE_ROOT/direct-noop.out" ||
	fail 'direct-extlinux no-op was not explicit'

# Full U-Boot historically zeroed its complete allocation arena so callers
# could receive clean memory without doing so themselves. The RG34XX-SP
# candidate changes only that full-U-Boot policy; its transaction must begin
# from the physically accepted direct-extlinux prefix, remain idempotent, and
# restore that exact prefix if any post-write check fails.
cp "$RAW" "$CASE_ROOT/no-heap-clear.direct-before"
cp "$RAW" "$CASE_ROOT/no-heap-clear.expected"
"$GDD" if="$NO_HEAP_CLEAR_ARTIFACTS/no-heap-clear.bin" \
	of="$CASE_ROOT/no-heap-clear.expected" bs=64K seek="$RAW_OFFSET" \
	count="$NO_HEAP_CLEAR_UBOOT_BYTES" iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=notrunc status=none
run_no_heap_clear_installer >"$CASE_ROOT/no-heap-clear-install.out"
cmp "$RAW" "$CASE_ROOT/no-heap-clear.expected" >/dev/null ||
	fail 'no-heap-clear install changed bytes outside or missed its exact target'
grep -Fq 'raw bytes [8192,628937)' "$CASE_ROOT/no-heap-clear-install.out" ||
	fail 'no-heap-clear report omits the exact logical range'
grep -Fq 'sector-aligned [8192,629248)' \
	"$CASE_ROOT/no-heap-clear-install.out" ||
	fail 'no-heap-clear report omits the exact physical range'
grep -Fq 'No-heap-clear U-Boot installed' \
	"$CASE_ROOT/no-heap-clear-install.out" ||
	fail 'no-heap-clear completion was not explicit'
NO_HEAP_CLEAR_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_no_heap_clear_installer >"$CASE_ROOT/no-heap-clear-noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$NO_HEAP_CLEAR_SHA" ] ||
	fail 'no-heap-clear no-op changed the raw fixture'
grep -Fq 'already installed' "$CASE_ROOT/no-heap-clear-noop.out" ||
	fail 'no-heap-clear no-op was not explicit'

cp "$CASE_ROOT/no-heap-clear.direct-before" "$RAW"
if run_no_heap_clear_failpoint after-write \
	>"$CASE_ROOT/no-heap-clear-failure.out" \
	2>"$CASE_ROOT/no-heap-clear-failure.err"; then
	fail 'injected no-heap-clear failure unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/no-heap-clear.direct-before" >/dev/null ||
	fail 'failed no-heap-clear transaction did not restore the exact direct base'
grep -Fq 'Exact pre-transaction 16 MiB prefix restored and verified' \
	"$CASE_ROOT/no-heap-clear-failure.err" ||
	fail 'failed no-heap-clear transaction did not verify direct-base recovery'

reset_raw
run_env_installer >"$CASE_ROOT/no-heap-clear-wrong-base-setup.out"
NO_HEAP_CLEAR_WRONG_BASE_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_no_heap_clear_installer >"$CASE_ROOT/no-heap-clear-wrong-base.out" \
	2>"$CASE_ROOT/no-heap-clear-wrong-base.err"; then
	fail 'no-heap-clear install accepted the environment-only predecessor'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = \
	"$NO_HEAP_CLEAR_WRONG_BASE_SHA" ] ||
	fail 'no-heap-clear predecessor rejection changed the raw fixture'
grep -Fq 'current raw U-Boot is not the exact accepted direct-extlinux base' \
	"$CASE_ROOT/no-heap-clear-wrong-base.err" ||
	fail 'no-heap-clear predecessor rejection was not explicit'

cp "$CASE_ROOT/no-heap-clear.direct-before" "$RAW"
if run_no_heap_clear_failpoint after-write-authority-drift \
	>"$CASE_ROOT/no-heap-clear-drift.out" \
	2>"$CASE_ROOT/no-heap-clear-drift.err"; then
	fail 'no-heap-clear authority-drift failure unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/no-heap-clear.direct-before" >/dev/null ||
	fail 'private no-heap-clear snapshot did not restore the exact direct base'
grep -Fq 'Exact pre-transaction 16 MiB prefix restored and verified' \
	"$CASE_ROOT/no-heap-clear-drift.err" ||
	fail 'private no-heap-clear snapshot recovery was not explicit'

# The device-specific successful-path image removes generic network/bootstd
# code and the serial abort delay from full U-Boot. Its shorter image starts
# only from the exact accepted no-heap-clear prefix, writes the minimum 1,088
# sectors, and retains/restores the predecessor bytes beyond its FIT boundary.
cp "$CASE_ROOT/no-heap-clear.expected" "$RAW"
cp "$RAW" "$CASE_ROOT/fast-init.no-heap-clear-before"
cp "$RAW" "$CASE_ROOT/fast-init.expected"
"$GDD" if="$FAST_INIT_ARTIFACTS/fast-init.bin" \
	of="$CASE_ROOT/fast-init.expected" bs=64K seek="$RAW_OFFSET" \
	count="$FAST_INIT_UBOOT_BYTES" iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=notrunc status=none
run_fast_init_installer >"$CASE_ROOT/fast-init-install.out"
cmp "$RAW" "$CASE_ROOT/fast-init.expected" >/dev/null ||
	fail 'fast-init install changed bytes outside or missed its exact target'
[ "$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock status=none |
	shasum -a 256 | awk '{print $1}')" = "$TEST_FAST_INIT_PREFIX_SHA" ] ||
	fail 'fast-init install did not produce its authority-bound complete prefix'
grep -Fq 'raw bytes [8192,565169)' "$CASE_ROOT/fast-init-install.out" ||
	fail 'fast-init report omits the exact logical range'
grep -Fq 'sector-aligned [8192,565248)' \
	"$CASE_ROOT/fast-init-install.out" ||
	fail 'fast-init report omits the exact physical range'
grep -Fq 'bytes [565169,565248) are preserved' \
	"$CASE_ROOT/fast-init-install.out" ||
	fail 'fast-init report omits the preserved sector tail'
grep -Fq 'Fast-init U-Boot installed' "$CASE_ROOT/fast-init-install.out" ||
	fail 'fast-init completion was not explicit'
FAST_INIT_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_fast_init_installer >"$CASE_ROOT/fast-init-noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$FAST_INIT_SHA" ] ||
	fail 'fast-init no-op changed the raw fixture'
grep -Fq 'already installed' "$CASE_ROOT/fast-init-noop.out" ||
	fail 'fast-init no-op was not explicit'

cp "$CASE_ROOT/fast-init.no-heap-clear-before" "$RAW"
if run_fast_init_failpoint after-write \
	>"$CASE_ROOT/fast-init-failure.out" \
	2>"$CASE_ROOT/fast-init-failure.err"; then
	fail 'injected fast-init failure unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/fast-init.no-heap-clear-before" >/dev/null ||
	fail 'failed fast-init transaction did not restore the exact no-heap-clear base'
grep -Fq 'Exact pre-transaction 16 MiB prefix restored and verified' \
	"$CASE_ROOT/fast-init-failure.err" ||
	fail 'failed fast-init transaction did not verify predecessor recovery'

cp "$CASE_ROOT/no-heap-clear.direct-before" "$RAW"
FAST_INIT_WRONG_BASE_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_fast_init_installer >"$CASE_ROOT/fast-init-wrong-base.out" \
	2>"$CASE_ROOT/fast-init-wrong-base.err"; then
	fail 'fast-init install accepted the direct-extlinux predecessor'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = \
	"$FAST_INIT_WRONG_BASE_SHA" ] ||
	fail 'fast-init predecessor rejection changed the raw fixture'
grep -Fq 'current raw U-Boot is not the exact accepted no-heap-clear base' \
	"$CASE_ROOT/fast-init-wrong-base.err" ||
	fail 'fast-init predecessor rejection was not explicit'

cp "$CASE_ROOT/fast-init.no-heap-clear-before" "$RAW"
if run_fast_init_failpoint after-write-authority-drift \
	>"$CASE_ROOT/fast-init-drift.out" \
	2>"$CASE_ROOT/fast-init-drift.err"; then
	fail 'fast-init authority-drift failure unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/fast-init.no-heap-clear-before" >/dev/null ||
	fail 'private fast-init snapshot did not restore the exact no-heap-clear base'
grep -Fq 'Exact pre-transaction 16 MiB prefix restored and verified' \
	"$CASE_ROOT/fast-init-drift.err" ||
	fail 'private fast-init snapshot recovery was not explicit'

# Generic U-Boot relocates the initramfs and DTB so arbitrary layouts receive
# safely allocated final copies. This RG34XX-SP successor compiles the accepted
# fixed in-place policy and must begin only from the exact reviewed fast-init
# prefix while retaining the same minimal 1,088-sector transaction boundary.
cp "$CASE_ROOT/fast-init.expected" "$RAW"
cp "$RAW" "$CASE_ROOT/inplace-handoff.fast-init-before"
cp "$RAW" "$CASE_ROOT/inplace-handoff.expected"
"$GDD" if="$INPLACE_HANDOFF_ARTIFACTS/inplace-handoff.bin" \
	of="$CASE_ROOT/inplace-handoff.expected" bs=64K seek="$RAW_OFFSET" \
	count="$INPLACE_HANDOFF_UBOOT_BYTES" iflag=count_bytes,fullblock oflag=seek_bytes \
	conv=notrunc status=none
run_inplace_handoff_installer >"$CASE_ROOT/inplace-handoff-install.out"
cmp "$RAW" "$CASE_ROOT/inplace-handoff.expected" >/dev/null ||
	fail 'in-place-handoff install changed bytes outside or missed its exact target'
[ "$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock status=none |
	shasum -a 256 | awk '{print $1}')" = "$TEST_INPLACE_HANDOFF_PREFIX_SHA" ] ||
	fail 'in-place-handoff install did not produce its authority-bound complete prefix'
grep -Fq 'raw bytes [8192,565169)' "$CASE_ROOT/inplace-handoff-install.out" ||
	fail 'in-place-handoff report omits the exact logical range'
grep -Fq 'sector-aligned [8192,565248)' \
	"$CASE_ROOT/inplace-handoff-install.out" ||
	fail 'in-place-handoff report omits the exact physical range'
grep -Fq 'bytes [565169,565248) are preserved' \
	"$CASE_ROOT/inplace-handoff-install.out" ||
	fail 'in-place-handoff report omits the preserved sector tail'
grep -Fq 'In-place-handoff U-Boot installed' \
	"$CASE_ROOT/inplace-handoff-install.out" ||
	fail 'in-place-handoff completion was not explicit'
INPLACE_HANDOFF_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_inplace_handoff_installer >"$CASE_ROOT/inplace-handoff-noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$INPLACE_HANDOFF_SHA" ] ||
	fail 'in-place-handoff no-op changed the raw fixture'
grep -Fq 'already installed' "$CASE_ROOT/inplace-handoff-noop.out" ||
	fail 'in-place-handoff no-op was not explicit'

cp "$CASE_ROOT/inplace-handoff.fast-init-before" "$RAW"
if run_inplace_handoff_failpoint after-write \
	>"$CASE_ROOT/inplace-handoff-failure.out" \
	2>"$CASE_ROOT/inplace-handoff-failure.err"; then
	fail 'injected in-place-handoff failure unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/inplace-handoff.fast-init-before" >/dev/null ||
	fail 'failed in-place-handoff transaction did not restore the exact fast-init base'
grep -Fq 'Exact pre-transaction 16 MiB prefix restored and verified' \
	"$CASE_ROOT/inplace-handoff-failure.err" ||
	fail 'failed in-place-handoff transaction did not verify predecessor recovery'

cp "$CASE_ROOT/fast-init.no-heap-clear-before" "$RAW"
INPLACE_HANDOFF_WRONG_BASE_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_inplace_handoff_installer >"$CASE_ROOT/inplace-handoff-wrong-base.out" \
	2>"$CASE_ROOT/inplace-handoff-wrong-base.err"; then
	fail 'in-place-handoff install accepted the no-heap-clear predecessor'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = \
	"$INPLACE_HANDOFF_WRONG_BASE_SHA" ] ||
	fail 'in-place-handoff predecessor rejection changed the raw fixture'
grep -Fq 'current raw U-Boot is not the exact accepted fast-init base' \
	"$CASE_ROOT/inplace-handoff-wrong-base.err" ||
	fail 'in-place-handoff predecessor rejection was not explicit'

cp "$CASE_ROOT/inplace-handoff.fast-init-before" "$RAW"
if run_inplace_handoff_failpoint after-write-authority-drift \
	>"$CASE_ROOT/inplace-handoff-drift.out" \
	2>"$CASE_ROOT/inplace-handoff-drift.err"; then
	fail 'in-place-handoff authority-drift failure unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/inplace-handoff.fast-init-before" >/dev/null ||
	fail 'private in-place-handoff snapshot did not restore the exact fast-init base'
grep -Fq 'Exact pre-transaction 16 MiB prefix restored and verified' \
	"$CASE_ROOT/inplace-handoff-drift.err" ||
	fail 'private in-place-handoff snapshot recovery was not explicit'

# Bootstage timestamps were previously kept out of every production candidate,
# because even diagnostic instrumentation changes timing and must never inherit
# successor authority. This action is therefore a temporary, exactly reversible
# measurement transaction from the accepted in-place handoff only.
if [ "$LZ4_PAIR_AVAILABLE" -eq 1 ]; then
	cp "$CASE_ROOT/inplace-handoff.expected" "$RAW"
	cp "$RAW" "$CASE_ROOT/lz4-pair.inplace-before"
	cp "$RAW" "$CASE_ROOT/lz4-pair.expected"
	"$GDD" if="$LZ4_PAIR_ARTIFACTS/lz4-pair.bin" \
		of="$CASE_ROOT/lz4-pair.expected" bs=64K seek="$RAW_OFFSET" \
		count="$INPLACE_HANDOFF_UBOOT_BYTES" iflag=count_bytes,fullblock \
		oflag=seek_bytes conv=notrunc status=none
	run_lz4_pair_installer >"$CASE_ROOT/lz4-pair-install.out"
	cmp "$RAW" "$CASE_ROOT/lz4-pair.expected" >/dev/null ||
		fail 'LZ4-pair install changed bytes outside or missed its exact target'
	[ "$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" \
		iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')" = \
		"$TEST_LZ4_PAIR_PREFIX_SHA" ] ||
		fail 'LZ4-pair install did not produce its reviewed complete prefix'
	grep -Fq 'raw bytes [8192,565169)' "$CASE_ROOT/lz4-pair-install.out" ||
		fail 'LZ4-pair report omits its exact logical range'
	grep -Fq 'sector-aligned [8192,565248)' "$CASE_ROOT/lz4-pair-install.out" ||
		fail 'LZ4-pair report omits its exact physical range'
	grep -Fq 'Uninstrumented LZ4-paired U-Boot installed' \
		"$CASE_ROOT/lz4-pair-install.out" ||
		fail 'LZ4-pair completion is not explicit'

	cp "$RAW" "$CASE_ROOT/lz4-pair.noop-before"
	run_lz4_pair_installer >"$CASE_ROOT/lz4-pair-noop.out"
	cmp "$RAW" "$CASE_ROOT/lz4-pair.noop-before" >/dev/null ||
		fail 'LZ4-pair no-op changed raw bytes'
	grep -Fq 'already installed' "$CASE_ROOT/lz4-pair-noop.out" ||
		fail 'LZ4-pair no-op was not explicit'

	cp "$CASE_ROOT/fast-init.expected" "$RAW"
	cp "$RAW" "$CASE_ROOT/lz4-pair.wrong-before"
	if run_lz4_pair_installer >"$CASE_ROOT/lz4-pair-wrong.out" \
		2>"$CASE_ROOT/lz4-pair-wrong.err"; then
		fail 'LZ4-pair install accepted the wrong predecessor'
	fi
	cmp "$RAW" "$CASE_ROOT/lz4-pair.wrong-before" >/dev/null ||
		fail 'LZ4-pair predecessor rejection changed raw bytes'
	grep -Fq 'not the exact accepted in-place-handoff base' \
		"$CASE_ROOT/lz4-pair-wrong.err" ||
		fail 'LZ4-pair predecessor rejection was not explicit'

	cp "$CASE_ROOT/lz4-pair.inplace-before" "$RAW"
	if run_lz4_pair_failpoint after-write >"$CASE_ROOT/lz4-pair-failure.out" \
		2>"$CASE_ROOT/lz4-pair-failure.err"; then
		fail 'LZ4-pair after-write failpoint unexpectedly succeeded'
	fi
	cmp "$RAW" "$CASE_ROOT/lz4-pair.inplace-before" >/dev/null ||
		fail 'LZ4-pair failure did not restore its exact predecessor'

	cp "$CASE_ROOT/lz4-pair.expected" "$RAW"
	run_lz4_pair_restore >"$CASE_ROOT/lz4-pair-restore.out"
	cmp "$RAW" "$CASE_ROOT/lz4-pair.inplace-before" >/dev/null ||
		fail 'LZ4-pair restore did not reproduce exact in-place U-Boot'
	grep -Fq 'restored from LZ4 pair' "$CASE_ROOT/lz4-pair-restore.out" ||
		fail 'LZ4-pair restore completion is not explicit'

	cp "$CASE_ROOT/lz4-pair.expected" "$RAW"
	flip_raw_byte $((RAW_OFFSET + INPLACE_HANDOFF_UBOOT_BYTES + 8))
	run_lz4_pair_restore >"$CASE_ROOT/lz4-pair-tail-restore.out"
	cmp "$RAW" "$CASE_ROOT/lz4-pair.inplace-before" >/dev/null ||
		fail 'LZ4-pair physical-tail recovery did not converge'

	cp "$CASE_ROOT/lz4-pair.expected" "$RAW"
	flip_raw_byte 565248
	cp "$RAW" "$CASE_ROOT/lz4-pair-outside-before"
	if run_lz4_pair_restore >"$CASE_ROOT/lz4-pair-outside.out" \
		2>"$CASE_ROOT/lz4-pair-outside.err"; then
		fail 'LZ4-pair restore accepted drift outside its physical span'
	fi
	cmp "$RAW" "$CASE_ROOT/lz4-pair-outside-before" >/dev/null ||
		fail 'LZ4-pair outside-span rejection changed raw bytes'
	grep -Fq 'outside the LZ4-pair recovery span' \
		"$CASE_ROOT/lz4-pair-outside.err" ||
		fail 'LZ4-pair outside-span rejection was not explicit'
fi

# The parser boundary advances only from the exact accepted LZ4 pair. Its
# shorter logical payload gets a correspondingly shorter sector-aligned write,
# while explicit recovery covers the complete predecessor span.
"$GDD" if="$SIMPLE_PARSER_ARTIFACTS/lz4-base-prefix-16m.bin" of="$RAW" \
	bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock \
	conv=notrunc status=none
cp "$RAW" "$CASE_ROOT/simple-parser.lz4-before"
cp "$RAW" "$CASE_ROOT/simple-parser.expected"
"$GDD" if="$SIMPLE_PARSER_ARTIFACTS/simple-parser.bin" \
	of="$CASE_ROOT/simple-parser.expected" bs=64K seek="$RAW_OFFSET" \
	count="$SIMPLE_PARSER_UBOOT_BYTES" iflag=count_bytes,fullblock \
	oflag=seek_bytes conv=notrunc status=none
run_simple_parser_installer >"$CASE_ROOT/simple-parser-install.out"
cmp "$RAW" "$CASE_ROOT/simple-parser.expected" >/dev/null ||
	fail 'simple-parser install changed bytes outside or missed its exact target'
[ "$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')" = \
	"$TEST_SIMPLE_PARSER_PREFIX_SHA" ] ||
	fail 'simple-parser install did not produce its reviewed complete prefix'
grep -Fq 'raw bytes [8192,526561)' "$CASE_ROOT/simple-parser-install.out" ||
	fail 'simple-parser report omits its exact logical range'
grep -Fq 'sector-aligned [8192,526848)' "$CASE_ROOT/simple-parser-install.out" ||
	fail 'simple-parser report omits its exact physical range'
grep -Fq 'Fixed-path simple-parser U-Boot installed' \
	"$CASE_ROOT/simple-parser-install.out" ||
	fail 'simple-parser completion is not explicit'

cp "$RAW" "$CASE_ROOT/simple-parser.noop-before"
run_simple_parser_installer >"$CASE_ROOT/simple-parser-noop.out"
cmp "$RAW" "$CASE_ROOT/simple-parser.noop-before" >/dev/null ||
	fail 'simple-parser no-op changed raw bytes'
grep -Fq 'already installed' "$CASE_ROOT/simple-parser-noop.out" ||
	fail 'simple-parser no-op was not explicit'

cp "$CASE_ROOT/inplace-handoff.expected" "$RAW"
cp "$RAW" "$CASE_ROOT/simple-parser.wrong-before"
if run_simple_parser_installer >"$CASE_ROOT/simple-parser-wrong.out" \
	2>"$CASE_ROOT/simple-parser-wrong.err"; then
	fail 'simple-parser install accepted the wrong predecessor'
fi
cmp "$RAW" "$CASE_ROOT/simple-parser.wrong-before" >/dev/null ||
	fail 'simple-parser predecessor rejection changed raw bytes'
grep -Fq 'not the exact accepted LZ4-pair base' \
	"$CASE_ROOT/simple-parser-wrong.err" ||
	fail 'simple-parser predecessor rejection was not explicit'

cp "$CASE_ROOT/simple-parser.lz4-before" "$RAW"
if run_simple_parser_failpoint after-write \
	>"$CASE_ROOT/simple-parser-failure.out" \
	2>"$CASE_ROOT/simple-parser-failure.err"; then
	fail 'simple-parser after-write failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/simple-parser.lz4-before" >/dev/null ||
	fail 'simple-parser failure did not restore the exact LZ4 predecessor'

cp "$CASE_ROOT/simple-parser.expected" "$RAW"
run_simple_parser_restore >"$CASE_ROOT/simple-parser-restore.out"
cmp "$RAW" "$CASE_ROOT/simple-parser.lz4-before" >/dev/null ||
	fail 'simple-parser restore did not reproduce the exact LZ4 pair'
grep -Fq 'restored from simple parser' "$CASE_ROOT/simple-parser-restore.out" ||
	fail 'simple-parser restore completion is not explicit'

cp "$CASE_ROOT/simple-parser.expected" "$RAW"
flip_raw_byte $((RAW_OFFSET + SIMPLE_PARSER_UBOOT_BYTES + 8))
run_simple_parser_restore >"$CASE_ROOT/simple-parser-tail-restore.out"
cmp "$RAW" "$CASE_ROOT/simple-parser.lz4-before" >/dev/null ||
	fail 'simple-parser physical-tail recovery did not converge'

cp "$CASE_ROOT/simple-parser.expected" "$RAW"
flip_raw_byte 565248
cp "$RAW" "$CASE_ROOT/simple-parser-outside-before"
if run_simple_parser_restore >"$CASE_ROOT/simple-parser-outside.out" \
	2>"$CASE_ROOT/simple-parser-outside.err"; then
	fail 'simple-parser restore accepted drift outside its physical span'
fi
cmp "$RAW" "$CASE_ROOT/simple-parser-outside-before" >/dev/null ||
	fail 'simple-parser outside-span rejection changed raw bytes'
grep -Fq 'outside the simple-parser recovery span' \
	"$CASE_ROOT/simple-parser-outside.err" ||
	fail 'simple-parser outside-span rejection was not explicit'

# The read-path boundary advances only from the exact accepted simple parser.
# It writes the smaller fixed MBR/FAT image while explicit recovery covers the
# complete larger predecessor span, including retired bytes and sector tail.
"$GDD" if="$FIXED_READ_PATH_ARTIFACTS/simple-parser-base-prefix-16m.bin" of="$RAW" \
	bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock \
	conv=notrunc status=none
cp "$RAW" "$CASE_ROOT/fixed-read-path.simple-before"
cp "$RAW" "$CASE_ROOT/fixed-read-path.expected"
"$GDD" if="$FIXED_READ_PATH_ARTIFACTS/fixed-read-path.bin" \
	of="$CASE_ROOT/fixed-read-path.expected" bs=64K seek="$RAW_OFFSET" \
	count="$FIXED_READ_PATH_UBOOT_BYTES" iflag=count_bytes,fullblock \
	oflag=seek_bytes conv=notrunc status=none
run_fixed_read_path_installer >"$CASE_ROOT/fixed-read-path-install.out"
cmp "$RAW" "$CASE_ROOT/fixed-read-path.expected" >/dev/null ||
	fail 'fixed-read-path install changed bytes outside or missed its exact target'
[ "$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')" = \
	"$TEST_FIXED_READ_PATH_PREFIX_SHA" ] ||
	fail 'fixed-read-path install did not produce its reviewed complete prefix'
grep -Fq 'raw bytes [8192,486225)' "$CASE_ROOT/fixed-read-path-install.out" ||
	fail 'fixed-read-path report omits its exact logical range'
grep -Fq 'sector-aligned [8192,486400)' \
	"$CASE_ROOT/fixed-read-path-install.out" ||
	fail 'fixed-read-path report omits its exact physical range'
grep -Fq 'Fixed MBR/FAT read-path U-Boot installed' \
	"$CASE_ROOT/fixed-read-path-install.out" ||
	fail 'fixed-read-path completion is not explicit'

cp "$RAW" "$CASE_ROOT/fixed-read-path.noop-before"
run_fixed_read_path_installer >"$CASE_ROOT/fixed-read-path-noop.out"
cmp "$RAW" "$CASE_ROOT/fixed-read-path.noop-before" >/dev/null ||
	fail 'fixed-read-path no-op changed raw bytes'
grep -Fq 'already installed' "$CASE_ROOT/fixed-read-path-noop.out" ||
	fail 'fixed-read-path no-op was not explicit'

cp "$CASE_ROOT/inplace-handoff.expected" "$RAW"
cp "$RAW" "$CASE_ROOT/fixed-read-path.wrong-before"
if run_fixed_read_path_installer >"$CASE_ROOT/fixed-read-path-wrong.out" \
	2>"$CASE_ROOT/fixed-read-path-wrong.err"; then
	fail 'fixed-read-path install accepted the wrong predecessor'
fi
cmp "$RAW" "$CASE_ROOT/fixed-read-path.wrong-before" >/dev/null ||
	fail 'fixed-read-path predecessor rejection changed raw bytes'
grep -Fq 'not the exact accepted simple-parser base' \
	"$CASE_ROOT/fixed-read-path-wrong.err" ||
	fail 'fixed-read-path predecessor rejection was not explicit'

cp "$CASE_ROOT/fixed-read-path.simple-before" "$RAW"
if run_fixed_read_path_failpoint after-write \
	>"$CASE_ROOT/fixed-read-path-failure.out" \
	2>"$CASE_ROOT/fixed-read-path-failure.err"; then
	fail 'fixed-read-path after-write failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/fixed-read-path.simple-before" >/dev/null ||
	fail 'fixed-read-path failure did not restore the exact simple-parser predecessor'

cp "$CASE_ROOT/fixed-read-path.expected" "$RAW"
run_fixed_read_path_restore >"$CASE_ROOT/fixed-read-path-restore.out"
cmp "$RAW" "$CASE_ROOT/fixed-read-path.simple-before" >/dev/null ||
	fail 'fixed-read-path restore did not reproduce the exact simple parser'
grep -Fq 'restored from fixed read path' \
	"$CASE_ROOT/fixed-read-path-restore.out" ||
	fail 'fixed-read-path restore completion is not explicit'

cp "$CASE_ROOT/fixed-read-path.expected" "$RAW"
flip_raw_byte $((RAW_OFFSET + FIXED_READ_PATH_UBOOT_BYTES + 1024))
run_fixed_read_path_restore >"$CASE_ROOT/fixed-read-path-tail-restore.out"
cmp "$RAW" "$CASE_ROOT/fixed-read-path.simple-before" >/dev/null ||
	fail 'fixed-read-path retired-byte recovery did not converge'

cp "$CASE_ROOT/fixed-read-path.expected" "$RAW"
flip_raw_byte 526848
cp "$RAW" "$CASE_ROOT/fixed-read-path-outside-before"
if run_fixed_read_path_restore >"$CASE_ROOT/fixed-read-path-outside.out" \
	2>"$CASE_ROOT/fixed-read-path-outside.err"; then
	fail 'fixed-read-path restore accepted drift outside its physical span'
fi
cmp "$RAW" "$CASE_ROOT/fixed-read-path-outside-before" >/dev/null ||
	fail 'fixed-read-path outside-span rejection changed raw bytes'
grep -Fq 'outside the fixed-read-path recovery span' \
	"$CASE_ROOT/fixed-read-path-outside.err" ||
	fail 'fixed-read-path outside-span rejection was not explicit'

# The command closure advances only from the exact accepted fixed read path.
# Its smaller full-U-Boot image retains sysboot/extlinux/booti while recovery
# covers the complete larger predecessor span and sector tail.
"$GDD" if="$FIXED_COMMAND_CLOSURE_ARTIFACTS/fixed-read-path-base-prefix-16m.bin" \
	of="$RAW" bs=4M count="$PREFIX_BYTES" iflag=count_bytes,fullblock \
	conv=notrunc status=none
cp "$RAW" "$CASE_ROOT/fixed-command-closure.fixed-before"
cp "$RAW" "$CASE_ROOT/fixed-command-closure.expected"
"$GDD" if="$FIXED_COMMAND_CLOSURE_ARTIFACTS/fixed-command-closure.bin" \
	of="$CASE_ROOT/fixed-command-closure.expected" bs=64K seek="$RAW_OFFSET" \
	count="$FIXED_COMMAND_CLOSURE_UBOOT_BYTES" iflag=count_bytes,fullblock \
	oflag=seek_bytes conv=notrunc status=none
run_fixed_command_closure_installer >"$CASE_ROOT/fixed-command-closure-install.out"
cmp "$RAW" "$CASE_ROOT/fixed-command-closure.expected" >/dev/null ||
	fail 'fixed-command-closure install changed bytes outside or missed its exact target'
[ "$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')" = \
	"$TEST_FIXED_COMMAND_CLOSURE_PREFIX_SHA" ] ||
	fail 'fixed-command-closure install did not produce its reviewed complete prefix'
grep -Fq 'raw bytes [8192,420169)' \
	"$CASE_ROOT/fixed-command-closure-install.out" ||
	fail 'fixed-command-closure report omits its exact logical range'
grep -Fq 'sector-aligned [8192,420352)' \
	"$CASE_ROOT/fixed-command-closure-install.out" ||
	fail 'fixed-command-closure report omits its exact physical range'
grep -Fq 'Fixed command-closure U-Boot installed' \
	"$CASE_ROOT/fixed-command-closure-install.out" ||
	fail 'fixed-command-closure completion is not explicit'

cp "$RAW" "$CASE_ROOT/fixed-command-closure.noop-before"
run_fixed_command_closure_installer >"$CASE_ROOT/fixed-command-closure-noop.out"
cmp "$RAW" "$CASE_ROOT/fixed-command-closure.noop-before" >/dev/null ||
	fail 'fixed-command-closure no-op changed raw bytes'
grep -Fq 'already installed' "$CASE_ROOT/fixed-command-closure-noop.out" ||
	fail 'fixed-command-closure no-op was not explicit'

cp "$CASE_ROOT/inplace-handoff.expected" "$RAW"
cp "$RAW" "$CASE_ROOT/fixed-command-closure.wrong-before"
if run_fixed_command_closure_installer \
	>"$CASE_ROOT/fixed-command-closure-wrong.out" \
	2>"$CASE_ROOT/fixed-command-closure-wrong.err"; then
	fail 'fixed-command-closure install accepted the wrong predecessor'
fi
cmp "$RAW" "$CASE_ROOT/fixed-command-closure.wrong-before" >/dev/null ||
	fail 'fixed-command-closure predecessor rejection changed raw bytes'
grep -Fq 'not the exact accepted fixed-read-path base' \
	"$CASE_ROOT/fixed-command-closure-wrong.err" ||
	fail 'fixed-command-closure predecessor rejection was not explicit'

cp "$CASE_ROOT/fixed-command-closure.fixed-before" "$RAW"
if run_fixed_command_closure_failpoint after-write \
	>"$CASE_ROOT/fixed-command-closure-failure.out" \
	2>"$CASE_ROOT/fixed-command-closure-failure.err"; then
	fail 'fixed-command-closure after-write failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/fixed-command-closure.fixed-before" >/dev/null ||
	fail 'fixed-command-closure failure did not restore the exact fixed-read-path predecessor'

cp "$CASE_ROOT/fixed-command-closure.expected" "$RAW"
run_fixed_command_closure_restore >"$CASE_ROOT/fixed-command-closure-restore.out"
cmp "$RAW" "$CASE_ROOT/fixed-command-closure.fixed-before" >/dev/null ||
	fail 'fixed-command-closure restore did not reproduce the exact fixed read path'
grep -Fq 'restored from command closure' \
	"$CASE_ROOT/fixed-command-closure-restore.out" ||
	fail 'fixed-command-closure restore completion is not explicit'

cp "$CASE_ROOT/fixed-command-closure.expected" "$RAW"
flip_raw_byte $((RAW_OFFSET + FIXED_COMMAND_CLOSURE_UBOOT_BYTES + 1024))
run_fixed_command_closure_restore \
	>"$CASE_ROOT/fixed-command-closure-tail-restore.out"
cmp "$RAW" "$CASE_ROOT/fixed-command-closure.fixed-before" >/dev/null ||
	fail 'fixed-command-closure retired-byte recovery did not converge'

cp "$CASE_ROOT/fixed-command-closure.expected" "$RAW"
flip_raw_byte 486400
cp "$RAW" "$CASE_ROOT/fixed-command-closure-outside-before"
if run_fixed_command_closure_restore \
	>"$CASE_ROOT/fixed-command-closure-outside.out" \
	2>"$CASE_ROOT/fixed-command-closure-outside.err"; then
	fail 'fixed-command-closure restore accepted drift outside its physical span'
fi
cmp "$RAW" "$CASE_ROOT/fixed-command-closure-outside-before" >/dev/null ||
	fail 'fixed-command-closure outside-span rejection changed raw bytes'
grep -Fq 'outside the fixed-command-closure recovery span' \
	"$CASE_ROOT/fixed-command-closure-outside.err" ||
	fail 'fixed-command-closure outside-span rejection was not explicit'

cp "$CASE_ROOT/inplace-handoff.expected" "$RAW"
cp "$RAW" "$CASE_ROOT/bootstage-fdt.inplace-before"
cp "$RAW" "$CASE_ROOT/bootstage-fdt.expected"
"$GDD" if="$BOOTSTAGE_FDT_ARTIFACTS/bird-uboot-bootstage-fdt.bin" \
	of="$CASE_ROOT/bootstage-fdt.expected" bs=64K seek="$RAW_OFFSET" \
	count="$BOOTSTAGE_FDT_UBOOT_BYTES" iflag=count_bytes,fullblock \
	oflag=seek_bytes conv=notrunc status=none
run_bootstage_fdt_installer >"$CASE_ROOT/bootstage-fdt-install.out"
cmp "$RAW" "$CASE_ROOT/bootstage-fdt.expected" >/dev/null ||
	fail 'bootstage-FDT install changed bytes outside or missed its exact target'
[ "$("$GDD" if="$RAW" bs=4M count="$PREFIX_BYTES" \
	iflag=count_bytes,fullblock status=none | shasum -a 256 | awk '{print $1}')" = \
	"$TEST_BOOTSTAGE_FDT_PREFIX_SHA" ] ||
	fail 'bootstage-FDT install did not produce its reviewed complete prefix'
grep -Fq 'raw bytes [8192,569265)' "$CASE_ROOT/bootstage-fdt-install.out" ||
	fail 'bootstage-FDT report omits the exact logical range'
grep -Fq 'sector-aligned [8192,569344)' \
	"$CASE_ROOT/bootstage-fdt-install.out" ||
	fail 'bootstage-FDT report omits the exact physical range'
grep -Fq 'bytes [569265,569344) are preserved' \
	"$CASE_ROOT/bootstage-fdt-install.out" ||
	fail 'bootstage-FDT report omits its 79-byte preserved sector tail'
grep -Fq 'Temporary measurement-only bootstage-FDT U-Boot installed' \
	"$CASE_ROOT/bootstage-fdt-install.out" ||
	fail 'bootstage-FDT completion does not retain its temporary classification'
grep -Fq 'never a production successor' "$CASE_ROOT/bootstage-fdt-install.out" ||
	fail 'bootstage-FDT completion does not disclaim production succession'

BOOTSTAGE_FDT_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_bootstage_fdt_installer >"$CASE_ROOT/bootstage-fdt-noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$BOOTSTAGE_FDT_SHA" ] ||
	fail 'bootstage-FDT no-op changed the raw fixture'
grep -Fq 'already installed' "$CASE_ROOT/bootstage-fdt-noop.out" ||
	fail 'bootstage-FDT no-op was not explicit'

cp "$CASE_ROOT/fast-init.expected" "$RAW"
BOOTSTAGE_WRONG_BASE_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_bootstage_fdt_installer >"$CASE_ROOT/bootstage-wrong-base.out" \
	2>"$CASE_ROOT/bootstage-wrong-base.err"; then
	fail 'bootstage-FDT install accepted the fast-init predecessor'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = \
	"$BOOTSTAGE_WRONG_BASE_SHA" ] ||
	fail 'bootstage-FDT predecessor rejection changed raw bytes'
grep -Fq 'current raw U-Boot is not the exact accepted in-place-handoff base' \
	"$CASE_ROOT/bootstage-wrong-base.err" ||
	fail 'bootstage-FDT predecessor rejection was not explicit'

cp "$CASE_ROOT/bootstage-fdt.inplace-before" "$RAW"
if run_bootstage_fdt_failpoint after-write \
	>"$CASE_ROOT/bootstage-failure.out" \
	2>"$CASE_ROOT/bootstage-failure.err"; then
	fail 'bootstage-FDT after-write failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/bootstage-fdt.inplace-before" >/dev/null ||
	fail 'bootstage-FDT after-write cleanup did not restore the in-place base'

if run_bootstage_fdt_failpoint after-write-corrupt \
	>"$CASE_ROOT/bootstage-corrupt.out" \
	2>"$CASE_ROOT/bootstage-corrupt.err"; then
	fail 'bootstage-FDT corrupt-readback failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/bootstage-fdt.inplace-before" >/dev/null ||
	fail 'bootstage-FDT corrupt-readback cleanup did not restore the in-place base'

cp "$BOOTSTAGE_FDT_ARTIFACTS/inplace-base-combined.bin" \
	"$CASE_ROOT/bootstage-inplace-base.saved"
cp "$BOOTSTAGE_FDT_ARTIFACTS/bird-uboot-bootstage-fdt.bin" \
	"$CASE_ROOT/bootstage-candidate.saved"
if run_bootstage_fdt_failpoint after-write-authority-drift \
	>"$CASE_ROOT/bootstage-drift.out" \
	2>"$CASE_ROOT/bootstage-drift.err"; then
	fail 'bootstage-FDT authority-drift failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/bootstage-fdt.inplace-before" >/dev/null ||
	fail 'private bootstage-FDT snapshot did not restore the in-place base'
mv "$CASE_ROOT/bootstage-inplace-base.saved" \
	"$BOOTSTAGE_FDT_ARTIFACTS/inplace-base-combined.bin"
mv "$CASE_ROOT/bootstage-candidate.saved" \
	"$BOOTSTAGE_FDT_ARTIFACTS/bird-uboot-bootstage-fdt.bin"

BOOT_DIAGNOSTICS_REQUEST=$DATA/Bird/boot-diagnostics.request
/bin/rm -f "$BOOT_DIAGNOSTICS_REQUEST"
cp "$RAW" "$CASE_ROOT/bootstage-marker.raw-before"
if run_bootstage_fdt_installer >"$CASE_ROOT/bootstage-marker-absent.out" \
	2>"$CASE_ROOT/bootstage-marker-absent.err"; then
	fail 'bootstage-FDT install accepted an absent diagnostics request'
fi
cmp "$RAW" "$CASE_ROOT/bootstage-marker.raw-before" >/dev/null ||
	fail 'absent diagnostics-request rejection changed raw bytes'
grep -Fq 'pre-armed regular zero-byte diagnostics request' \
	"$CASE_ROOT/bootstage-marker-absent.err" ||
	fail 'absent diagnostics-request rejection was not explicit'

mkdir "$BOOT_DIAGNOSTICS_REQUEST"
if run_bootstage_fdt_installer >"$CASE_ROOT/bootstage-marker-directory.out" \
	2>"$CASE_ROOT/bootstage-marker-directory.err"; then
	fail 'bootstage-FDT install accepted a nonregular diagnostics request'
fi
cmp "$RAW" "$CASE_ROOT/bootstage-marker.raw-before" >/dev/null ||
	fail 'nonregular diagnostics-request rejection changed raw bytes'
rmdir "$BOOT_DIAGNOSTICS_REQUEST"
ln -s namespace-v1.tsv "$BOOT_DIAGNOSTICS_REQUEST"
if run_bootstage_fdt_installer >"$CASE_ROOT/bootstage-marker-symlink.out" \
	2>"$CASE_ROOT/bootstage-marker-symlink.err"; then
	fail 'bootstage-FDT install accepted a symlinked diagnostics request'
fi
cmp "$RAW" "$CASE_ROOT/bootstage-marker.raw-before" >/dev/null ||
	fail 'symlinked diagnostics-request rejection changed raw bytes'
unlink "$BOOT_DIAGNOSTICS_REQUEST"
: >"$BOOT_DIAGNOSTICS_REQUEST"

if run_bootstage_fdt_failpoint after-write-diagnostics-marker-tamper \
	>"$CASE_ROOT/bootstage-marker-tamper.out" \
	2>"$CASE_ROOT/bootstage-marker-tamper.err"; then
	fail 'bootstage-FDT install accepted post-write diagnostics-request tampering'
fi
cmp "$RAW" "$CASE_ROOT/bootstage-fdt.inplace-before" >/dev/null ||
	fail 'diagnostics-request tampering did not roll raw bytes back exactly'
grep -Fq 'diagnostics request changed across raw installation' \
	"$CASE_ROOT/bootstage-marker-tamper.err" ||
	fail 'post-write diagnostics-request tampering was not explicit'
: >"$BOOT_DIAGNOSTICS_REQUEST"

# Restoration is a direct recovery authority, not another successor. It does
# not depend on a capture request and accepts torn bytes only within the exact
# physical span previously written by the measurement action.
cp "$CASE_ROOT/bootstage-fdt.expected" "$RAW"
/bin/rm -f "$BOOT_DIAGNOSTICS_REQUEST"
run_inplace_handoff_restore >"$CASE_ROOT/inplace-restore.out"
cmp "$RAW" "$CASE_ROOT/bootstage-fdt.inplace-before" >/dev/null ||
	fail 'direct in-place restore did not reproduce the accepted complete prefix'
grep -Fq 'raw bytes [8192,565169)' "$CASE_ROOT/inplace-restore.out" ||
	fail 'direct in-place restore omits its exact logical target range'
grep -Fq 'sector-aligned [8192,569344)' "$CASE_ROOT/inplace-restore.out" ||
	fail 'direct in-place restore omits its exact physical recovery span'
grep -Fq 'Accepted in-place-handoff U-Boot restored' \
	"$CASE_ROOT/inplace-restore.out" ||
	fail 'direct in-place restore completion was not explicit'

INPLACE_RESTORED_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
run_inplace_handoff_restore >"$CASE_ROOT/inplace-restore-noop.out"
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = "$INPLACE_RESTORED_SHA" ] ||
	fail 'direct in-place restore no-op changed raw bytes'
grep -Fq 'already restored' "$CASE_ROOT/inplace-restore-noop.out" ||
	fail 'direct in-place restore no-op was not explicit'

flip_raw_byte 569343
run_inplace_handoff_restore >"$CASE_ROOT/inplace-restore-tail.out"
cmp "$RAW" "$CASE_ROOT/bootstage-fdt.inplace-before" >/dev/null ||
	fail 'direct in-place restore did not repair its physical sector tail'

flip_raw_byte 569344
INPLACE_RESTORE_OUTSIDE_SHA=$(shasum -a 256 "$RAW" | awk '{print $1}')
if run_inplace_handoff_restore >"$CASE_ROOT/inplace-restore-outside.out" \
	2>"$CASE_ROOT/inplace-restore-outside.err"; then
	fail 'direct in-place restore accepted drift outside its physical span'
fi
[ "$(shasum -a 256 "$RAW" | awk '{print $1}')" = \
	"$INPLACE_RESTORE_OUTSIDE_SHA" ] ||
	fail 'direct in-place outside-span rejection changed raw bytes'
grep -Fq 'outside the in-place recovery span' \
	"$CASE_ROOT/inplace-restore-outside.err" ||
	fail 'direct in-place outside-span rejection was not explicit'

cp "$CASE_ROOT/bootstage-fdt.inplace-before" "$RAW"
flip_raw_byte 569343
if run_inplace_handoff_restore_failpoint after-write \
	>"$CASE_ROOT/inplace-restore-failure.out" \
	2>"$CASE_ROOT/inplace-restore-failure.err"; then
	fail 'direct in-place restore after-write failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/bootstage-fdt.inplace-before" >/dev/null ||
	fail 'failed direct in-place restore did not converge to its accepted prefix'

flip_raw_byte 569343
if run_inplace_handoff_restore_failpoint after-write-corrupt \
	>"$CASE_ROOT/inplace-restore-corrupt.out" \
	2>"$CASE_ROOT/inplace-restore-corrupt.err"; then
	fail 'direct in-place corrupt-readback failpoint unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/bootstage-fdt.inplace-before" >/dev/null ||
	fail 'corrupt direct in-place readback did not converge to its accepted prefix'
: >"$BOOT_DIAGNOSTICS_REQUEST"

cp "$CASE_ROOT/green-prefix-oracle" "$RAW"
if run_early_failpoint after-write >"$CASE_ROOT/early-failure.out" \
	2>"$CASE_ROOT/early-failure.err"; then
	fail 'injected early-green failure unexpectedly succeeded'
fi
cmp "$RAW" "$CASE_ROOT/green-prefix-oracle" >/dev/null ||
	fail 'failed early-green transaction did not restore the exact green base'

cp "$CASE_ROOT/early-prefix-oracle" "$RAW"
run_restore >"$CASE_ROOT/early-restore.out"
cp "$RAW" "$CASE_ROOT/early-restored-baseline"
reset_raw
cmp "$RAW" "$CASE_ROOT/early-restored-baseline" >/dev/null ||
	fail 'baseline restore from early-green did not reproduce the accepted prefix'

# Card-geometry drift and unsafe BIRD nodes are also rejected pre-write.
cp "$DEVICE_INFO" "$CASE_ROOT/device.saved.tsv"
sed -i '' 's/134217728 Bytes (134217728 Bytes)/134217729 Bytes (134217729 Bytes)/' \
	"$DEVICE_INFO"
if run_installer >"$CASE_ROOT/geometry.out" 2>"$CASE_ROOT/geometry.err"; then
	fail 'wrong BIRD geometry was accepted'
fi
mv "$CASE_ROOT/device.saved.tsv" "$DEVICE_INFO"

ln -s extlinux/extlinux.conf "$BIRD/unsafe-link"
if run_installer >"$CASE_ROOT/symlink.out" 2>"$CASE_ROOT/symlink.err"; then
	fail 'unsafe BIRD symlink was accepted'
fi
unlink "$BIRD/unsafe-link"

# A lexical traversal and a symlinked raw fixture cannot escape the explicit
# owned temporary root, even in host-test mode.
TRAVERSAL_RAW=$CASE_ROOT/../bird-uboot-traversal-$$.img
cp "$RAW" "$TRAVERSAL_RAW"
if BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT \
	BIRD=$BIRD DATA=$DATA BIRD_DEVICE_INFO=$DEVICE_INFO \
	BIRD_TEST_RAW_DISK=$TRAVERSAL_RAW \
	BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
	BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA GDD=$RAW_GDD \
	sh "$INSTALLER" "/dev/$WHOLE" --install-green "$ARTIFACTS" \
	>"$CASE_ROOT/traversal.out" 2>"$CASE_ROOT/traversal.err"; then
	fail 'host-test path traversal was accepted'
fi
/bin/rm -f "$TRAVERSAL_RAW"

ln -s "$RAW" "$CASE_ROOT/raw-link"
if BIRD_UBOOT_HOST_TEST_MODE=1 BIRD_TEST_ROOT=$CASE_ROOT \
	BIRD=$BIRD DATA=$DATA BIRD_DEVICE_INFO=$DEVICE_INFO \
	BIRD_TEST_RAW_DISK=$CASE_ROOT/raw-link \
	BIRD_TEST_BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA \
	BIRD_TEST_GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA GDD=$RAW_GDD \
	sh "$INSTALLER" "/dev/$WHOLE" --install-green "$ARTIFACTS" \
	>"$CASE_ROOT/raw-link.out" 2>"$CASE_ROOT/raw-link.err"; then
	fail 'symlinked host-test raw fixture was accepted'
fi
unlink "$CASE_ROOT/raw-link"

find "$BIRD" "$DATA" -name '._*' ! -name '._extlinux' -print | grep -q . &&
	fail 'U-Boot installer produced AppleDouble sidecars'

printf 'PASS: bounded mainline U-Boot installer host gate\n'
