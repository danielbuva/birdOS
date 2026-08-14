#!/usr/bin/env python3
"""Verify and publish the fixed RG34XX-SP green-status-LED U-Boot build."""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path


SCHEMA = "bird-uboot-status-led-authority-v1"
FOUR_PASS_SCHEMA = "bird-uboot-four-pass-inventory-v1"
ROCKNIX_RELEASE = "20260701"
ROCKNIX_COMMIT = "3e4ee5852e6ca5ea73a38369d2639fad2262648b"
UBOOT_VERSION = "v2026.01"
PACKAGE_PATH = "projects/ROCKNIX/devices/H700/packages/u-boot-DDR4"
GCC_PACKAGE_PATH = "projects/ROCKNIX/packages/lang/gcc/package.mk"
DEFCONFIG_NAME = "anbernic_rg35xx_h700_lpddr4_defconfig"
SOURCE_TARBALL_SHA256 = (
    "03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654"
)
PACKAGE_MK_SHA256 = (
    "07c3e190986d1c8f875b92465684a53329efde0427ace9425fe164c2e8ae0f7b"
)
PACKAGE_PATCH_SHA256 = (
    "596674be315fbb74f670cf04639f10ea2b5629fd9eb72d944084a04cd0e5fab5"
)
GCC_PACKAGE_SHA256 = (
    "f1416c2f83be951ef2de9320369f05d6296ee171c822ada6491e91c9f53d7ffc"
)
GCC_SOURCE_SHA256 = (
    "438fd996826b0c82485a29da03a72d71d6e3541a83ec702df4271f6fe025d24e"
)
UPSTREAM_DEFCONFIG_SHA256 = (
    "24013855fefbe911cf664301940e8b6b514e4961ed414f324dae491f56d6bfe4"
)
GREEN_DEFCONFIG_SHA256 = (
    "cea8a54adaf9c55b22c767361bdc79aab4972b931df762b330d6359d73844295"
)
DOCKER_IMAGE = (
    "ghcr.io/rocknix/rocknix-build@"
    "sha256:a360f7280ff4b87f2614dd6085336df287c3bc6f2fccd87c7f5673f5cef1daed"
)
TOOLCHAIN_SCHEMA = "bird-rocknix-uboot-toolchain-v1"
TARGET_TRIPLET = "aarch64-rocknix-linux-gnu"
SOURCE_DATE_EPOCH = 1782880730
FIT_DATE_EPOCH = 1782880744
RAW_OFFSET = 8192
SPL_REGION_BYTES = 40960
FIT_BYTES = 580089
COMBINED_BYTES = SPL_REGION_BYTES + FIT_BYTES
SHIPPING_COMBINED_SHA256 = (
    "42c01f4524b45cba7c239cd940fc4e71eed7545901da201f27fed2193b7fdf45"
)
BL31_BYTES = 41065
BL31_SHA256 = "431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673"

FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9

REQUIRED_ARTIFACTS = (
    "u-boot-sunxi-with-spl.bin",
    "u-boot.itb",
    "u-boot-nodtb.bin",
    "u-boot.dtb",
    "spl/sunxi-spl.bin",
    "build.config",
)
BUILD_NAMES = ("baseline-a", "baseline-b", "green-a", "green-b")


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_bytes(path: Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail(f"unsafe or missing build artifact: {path}")
    return path.read_bytes()


def c_string(data: bytes) -> str:
    if not data.endswith(b"\0") or b"\0" in data[:-1]:
        fail("malformed FIT string property")
    return data[:-1].decode("ascii")


def parse_fit(blob: bytes) -> dict[str, dict[str, bytes]]:
    """Return FIT/FDT properties indexed by absolute node path."""

    if len(blob) < 40:
        fail("FIT is shorter than its header")
    (
        magic,
        total_size,
        structure_offset,
        strings_offset,
        reserve_offset,
        version,
        last_compatible_version,
        _boot_cpu,
        strings_size,
        structure_size,
    ) = struct.unpack_from(">10I", blob)
    if magic != FDT_MAGIC:
        fail("FIT magic is invalid")
    if total_size != len(blob):
        fail(f"FIT size is not exact ({total_size} != {len(blob)})")
    if version != 17 or last_compatible_version != 2:
        fail("FIT version authority changed")
    if reserve_offset < 40:
        fail("FIT reserve-map offset is invalid")
    structure_end = structure_offset + structure_size
    strings_end = strings_offset + strings_size
    if structure_end > len(blob) or strings_end > len(blob):
        fail("FIT table exceeds artifact bounds")

    strings = blob[strings_offset:strings_end]
    properties: dict[str, dict[str, bytes]] = {}
    stack: list[str] = []
    position = structure_offset
    saw_end = False
    while position < structure_end:
        if position + 4 > structure_end:
            fail("truncated FIT structure token")
        token = struct.unpack_from(">I", blob, position)[0]
        position += 4
        if token == FDT_BEGIN_NODE:
            try:
                name_end = blob.index(0, position, structure_end)
            except ValueError:
                fail("unterminated FIT node name")
            try:
                name = blob[position:name_end].decode("ascii")
            except UnicodeDecodeError:
                fail("non-ASCII FIT node name")
            position = (name_end + 4) & ~3
            stack.append(name)
            path = "/" + "/".join(part for part in stack if part)
            if path in properties:
                fail(f"duplicate FIT node: {path}")
            properties[path] = {}
        elif token == FDT_END_NODE:
            if not stack:
                fail("unbalanced FIT end-node token")
            stack.pop()
        elif token == FDT_PROP:
            if not stack or position + 8 > structure_end:
                fail("malformed FIT property token")
            length, name_offset = struct.unpack_from(">II", blob, position)
            position += 8
            if name_offset >= len(strings):
                fail("FIT property name offset is invalid")
            try:
                property_end = strings.index(0, name_offset)
            except ValueError:
                fail("unterminated FIT property name")
            try:
                name = strings[name_offset:property_end].decode("ascii")
            except UnicodeDecodeError:
                fail("non-ASCII FIT property name")
            value_end = position + length
            if value_end > structure_end:
                fail("FIT property exceeds structure bounds")
            value = blob[position:value_end]
            position = (value_end + 3) & ~3
            path = "/" + "/".join(part for part in stack if part)
            if name in properties[path]:
                fail(f"duplicate FIT property: {path}:{name}")
            properties[path][name] = value
        elif token == FDT_NOP:
            continue
        elif token == FDT_END:
            saw_end = True
            break
        else:
            fail(f"unknown FIT structure token: {token}")
    if not saw_end or stack:
        fail("FIT structure is incomplete")
    return properties


def verify_fit(blob: bytes, uboot: bytes, bl31: bytes, control_fdt: bytes) -> None:
    properties = parse_fit(blob)
    expected_nodes = {"/", "/images", "/images/uboot", "/images/atf",
                      "/images/fdt-1", "/configurations",
                      "/configurations/config-1"}
    if set(properties) != expected_nodes:
        fail("FIT node inventory changed")

    uboot_node = properties["/images/uboot"]
    atf_node = properties["/images/atf"]
    fdt_node = properties["/images/fdt-1"]
    config = properties["/configurations/config-1"]
    if uboot_node.get("data") != uboot:
        fail("FIT U-Boot component differs from u-boot-nodtb.bin + u-boot.dtb")
    if atf_node.get("data") != bl31:
        fail("FIT ATF component differs from the pinned BL31")
    if fdt_node.get("data") != control_fdt:
        fail("FIT control FDT differs from u-boot.dtb")
    if c_string(uboot_node.get("type", b"")) != "standalone":
        fail("FIT U-Boot component type changed")
    if c_string(atf_node.get("type", b"")) != "firmware":
        fail("FIT ATF component type changed")
    if c_string(fdt_node.get("type", b"")) != "flat_dt":
        fail("FIT control-FDT component type changed")
    if c_string(config.get("firmware", b"")) != "atf":
        fail("FIT firmware selection changed")
    if c_string(config.get("loadables", b"")) != "uboot":
        fail("FIT U-Boot selection changed")
    if c_string(config.get("fdt", b"")) != "fdt-1":
        fail("FIT control-FDT selection changed")
    timestamp = properties["/"].get("timestamp")
    if timestamp != struct.pack(">I", FIT_DATE_EPOCH):
        found = int.from_bytes(timestamp or b"", "big")
        fail(f"FIT timestamp authority changed ({found} != {FIT_DATE_EPOCH})")


def verify_combined(combined: bytes, spl: bytes, fit: bytes) -> None:
    if len(combined) != COMBINED_BYTES:
        fail(f"combined U-Boot size changed ({len(combined)} != {COMBINED_BYTES})")
    if combined[4:12] != b"eGON.BT0":
        fail("combined U-Boot lacks the Allwinner SPL signature")
    if struct.unpack_from("<I", combined, 0x10)[0] != SPL_REGION_BYTES:
        fail("Allwinner SPL header length changed")
    if len(spl) > SPL_REGION_BYTES:
        fail("SPL exceeds its fixed region")
    if combined[: len(spl)] != spl:
        fail("combined U-Boot does not begin with the built SPL")
    if any(combined[len(spl):SPL_REGION_BYTES]):
        fail("SPL-to-FIT padding is not zero")
    if len(fit) != FIT_BYTES or combined[SPL_REGION_BYTES:] != fit:
        fail("combined U-Boot does not end at the exact FIT boundary")


def load_build(path: Path) -> dict[str, bytes]:
    artifacts = {name: file_bytes(path / name) for name in REQUIRED_ARTIFACTS}
    combined = artifacts["u-boot-sunxi-with-spl.bin"]
    fit = artifacts["u-boot.itb"]
    spl = artifacts["spl/sunxi-spl.bin"]
    verify_combined(combined, spl, fit)
    return artifacts


def assert_artifacts_equal(
    first: dict[str, bytes], second: dict[str, bytes], label: str
) -> None:
    if set(first) != set(second):
        fail(f"{label} artifact inventory differs")
    for name in first:
        if first[name] != second[name]:
            fail(f"{label} is not reproducible: {name} differs")


def verify_green_scope(
    baseline: dict[str, bytes], green: dict[str, bytes]
) -> None:
    """Require the candidate FIT to differ only in its U-Boot payload."""

    baseline_uboot = baseline["u-boot-nodtb.bin"]
    green_uboot = green["u-boot-nodtb.bin"]
    if len(baseline_uboot) != len(green_uboot):
        fail("green status-LED change altered the U-Boot payload size")
    if baseline_uboot == green_uboot:
        fail("green status-LED change did not alter the U-Boot payload")
    baseline_fit = baseline["u-boot.itb"]
    green_fit = green["u-boot.itb"]
    baseline_offset = baseline_fit.find(baseline_uboot)
    green_offset = green_fit.find(green_uboot)
    if baseline_offset < 0 or baseline_fit.find(baseline_uboot, baseline_offset + 1) >= 0:
        fail("baseline FIT U-Boot payload is not uniquely located")
    if green_offset < 0 or green_fit.find(green_uboot, green_offset + 1) >= 0:
        fail("green FIT U-Boot payload is not uniquely located")
    if baseline_offset != green_offset:
        fail("green status-LED change moved the FIT U-Boot payload")
    normalized = bytearray(green_fit)
    normalized[green_offset : green_offset + len(green_uboot)] = baseline_uboot
    if bytes(normalized) != baseline_fit:
        fail("green status-LED change altered bytes outside the FIT U-Boot payload")


def verify_build_configs(baseline: bytes, green: bytes) -> None:
    """Prove that LTO is off and the status GPIO is the only config delta."""

    lto_disabled = b"# CONFIG_LTO is not set\n"
    red = b"CONFIG_LED_STATUS_BIT=267\n"
    green_led = b"CONFIG_LED_STATUS_BIT=268\n"
    for label, config in (("baseline", baseline), ("green", green)):
        if config.count(lto_disabled) != 1 or b"CONFIG_LTO=y\n" in config:
            fail(f"{label} U-Boot LTO state changed")
    if baseline.count(red) != 1 or baseline.count(green_led) != 0:
        fail("baseline U-Boot status-LED config changed")
    if green.count(green_led) != 1 or green.count(red) != 0:
        fail("green U-Boot status-LED config changed")
    if baseline.replace(red, green_led) != green:
        fail("green U-Boot config differs outside the status GPIO")


def is_sha256(value: str) -> bool:
    return len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def verify_toolchain_authority(data: bytes) -> None:
    """Reject incomplete or ambiguous records of the bytes used to build."""

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        fail("external toolchain authority is not UTF-8")
    if not text.endswith("\n"):
        fail("external toolchain authority lacks a final newline")
    rows = [line.split("\t") for line in text.splitlines()]
    if not rows or any(not row or any(not field for field in row) for row in rows):
        fail("external toolchain authority contains an empty field")

    def exact(key: str, expected: tuple[str, ...]) -> None:
        found = [tuple(row[1:]) for row in rows if row[0] == key]
        if found != [expected]:
            fail(f"external toolchain authority field changed: {key}")

    exact("schema", (TOOLCHAIN_SCHEMA,))
    exact("docker-image", (DOCKER_IMAGE,))
    exact("target-triplet", (TARGET_TRIPLET,))
    exact("gcc-version", ("15.2.0",))
    exact("gcc-package-path", (GCC_PACKAGE_PATH,))
    exact("gcc-package-sha256", (GCC_PACKAGE_SHA256,))
    exact("gcc-source-sha256", (GCC_SOURCE_SHA256,))
    exact("uboot-lto", ("disabled",))
    exact(
        "cross-compiler-invocation",
        ("bin/ccache", f"bin/{TARGET_TRIPLET}-gcc-15.2.0"),
    )
    exact("host-compiler-invocation", ("bin/ccache", "/usr/bin/gcc"))
    exact(
        "host-cxx-wrapper-authority",
        ("bin/host-g++", "bin/ccache", "/usr/bin/g++"),
    )

    required_tools = {
        f"bin/{TARGET_TRIPLET}-{suffix}"
        for suffix in (
            "gcc",
            "gcc-15.2.0",
            "ld",
            "as",
            "ar",
            "nm",
            "strip",
            "objcopy",
            "objdump",
            "readelf",
        )
    } | {"bin/ccache", "bin/host-gcc", "bin/host-g++", "bin/make", "bin/python", "bin/python3"}
    entries: dict[str, tuple[str, ...]] = {}
    resolved: dict[str, tuple[str, str]] = {}
    for row in rows:
        if row[0] in ("tool-entry-file", "tool-entry-symlink"):
            if len(row) != 3 or row[1] in entries:
                fail("external toolchain entry inventory is malformed")
            if row[0] == "tool-entry-file" and not is_sha256(row[2]):
                fail("external toolchain entry hash is malformed")
            entries[row[1]] = (row[0], row[2])
        elif row[0] == "tool-resolved":
            if len(row) != 4 or row[1] in resolved or not is_sha256(row[3]):
                fail("external resolved-tool inventory is malformed")
            if row[2].startswith("/") or ".." in row[2].split("/"):
                fail("external resolved-tool path is unsafe")
            resolved[row[1]] = (row[2], row[3])
    if set(entries) != required_tools or set(resolved) != required_tools:
        fail("external toolchain executable inventory changed")

    for key in ("host-compiler-resolved", "host-cxx-resolved"):
        found = [row for row in rows if row[0] == key]
        if len(found) != 1 or len(found[0]) != 3:
            fail(f"external toolchain authority field changed: {key}")
        if not found[0][1].startswith("/usr/") or not is_sha256(found[0][2]):
            fail(f"external host compiler authority is malformed: {key}")

    internals = [row for row in rows if row[0] == "compiler-internal-file"]
    if len(internals) != 2 or {row[1] for row in internals} != {"cc1", "libgcc"}:
        fail("external compiler internal-file inventory changed")
    for row in internals:
        if len(row) != 4 or row[2].startswith("/") or not is_sha256(row[3]):
            fail("external compiler internal-file authority is malformed")
    trees = [row for row in rows if row[0] == "compiler-internal-tree"]
    if len(trees) != 1 or len(trees[0]) != 7 or trees[0][1] != "include":
        fail("external compiler include-tree inventory changed")
    tree = trees[0]
    if tree[2].startswith("/") or not tree[3].isdigit() or not tree[4].isdigit() or not is_sha256(tree[5]):
        fail("external compiler include-tree authority is malformed")
    if tree[6] != "no-symlinks-special-nodes":
        fail("external compiler include-tree policy changed")


def difference_summary(before: bytes, after: bytes) -> dict[str, int]:
    if len(before) != len(after):
        fail("cannot summarize a size-changing U-Boot candidate")
    positions = [index for index, pair in enumerate(zip(before, after)) if pair[0] != pair[1]]
    if not positions:
        fail("green U-Boot candidate is byte-identical to baseline")
    runs = 1 + sum(
        current != previous + 1
        for previous, current in zip(positions, positions[1:])
    )
    return {
        "changed-bytes": len(positions),
        "changed-runs": runs,
        "first-changed-offset": positions[0],
        "last-changed-offset": positions[-1],
    }


def write_tsv(path: Path, rows: list[tuple[str, str | int]]) -> None:
    with path.open("x", encoding="utf-8", newline="") as output:
        for key, value in rows:
            if "\t" in key or "\n" in key or "\t" in str(value) or "\n" in str(value):
                fail("unsafe manifest value")
            output.write(f"{key}\t{value}\n")


def four_pass_inventory(builds: dict[str, dict[str, bytes]]) -> bytes:
    """Seal every isolated build output in one canonical fixed-order record."""

    if tuple(builds) != BUILD_NAMES:
        fail("four-pass build inventory order changed")
    lines = [f"schema\t{FOUR_PASS_SCHEMA}"]
    for build_name in BUILD_NAMES:
        artifacts = builds[build_name]
        if tuple(artifacts) != REQUIRED_ARTIFACTS:
            fail(f"{build_name} artifact inventory order changed")
        for artifact_name in REQUIRED_ARTIFACTS:
            data = artifacts[artifact_name]
            lines.append(
                f"artifact\t{build_name}\t{artifact_name}\t"
                f"{len(data)}\t{sha256(data)}"
            )
    return ("\n".join(lines) + "\n").encode("ascii")


def publish(
    baseline_a_dir: Path,
    baseline_b_dir: Path,
    green_a_dir: Path,
    green_b_dir: Path,
    shipping_path: Path,
    bl31_path: Path,
    toolchain_authority: Path,
    output: Path,
) -> None:
    if output.exists() or output.is_symlink():
        fail(f"refusing to replace result directory: {output}")
    output.mkdir(mode=0o755)

    baseline_a = load_build(baseline_a_dir)
    baseline_b = load_build(baseline_b_dir)
    green_a = load_build(green_a_dir)
    green_b = load_build(green_b_dir)
    assert_artifacts_equal(baseline_a, baseline_b, "baseline build")
    assert_artifacts_equal(green_a, green_b, "green build")
    builds = {
        "baseline-a": baseline_a,
        "baseline-b": baseline_b,
        "green-a": green_a,
        "green-b": green_b,
    }

    shipping = file_bytes(shipping_path)
    if len(shipping) != COMBINED_BYTES or sha256(shipping) != SHIPPING_COMBINED_SHA256:
        fail("shipping combined U-Boot oracle changed")
    baseline = baseline_a["u-boot-sunxi-with-spl.bin"]
    candidate = green_a["u-boot-sunxi-with-spl.bin"]
    if baseline != shipping:
        fail("rebuilt baseline is not byte-identical to the shipping U-Boot")

    bl31 = file_bytes(bl31_path)
    if len(bl31) != BL31_BYTES or sha256(bl31) != BL31_SHA256:
        fail("pinned BL31 authority changed")
    for build in (baseline_a, green_a):
        uboot = build["u-boot-nodtb.bin"]
        verify_fit(build["u-boot.itb"], uboot, bl31, build["u-boot.dtb"])

    if baseline_a["spl/sunxi-spl.bin"] != green_a["spl/sunxi-spl.bin"]:
        fail("green status-LED change altered the SPL")
    if baseline_a["u-boot.dtb"] != green_a["u-boot.dtb"]:
        fail("green status-LED change altered the control FDT")
    verify_build_configs(baseline_a["build.config"], green_a["build.config"])
    verify_green_scope(baseline_a, green_a)
    summary = difference_summary(baseline, candidate)

    toolchain = file_bytes(toolchain_authority)
    verify_toolchain_authority(toolchain)

    published = {
        "rocknix-baseline.bin": shipping,
        "bird-uboot-green.bin": candidate,
        "baseline-a-combined.bin": baseline_a["u-boot-sunxi-with-spl.bin"],
        "baseline-b-combined.bin": baseline_b["u-boot-sunxi-with-spl.bin"],
        "green-a-combined.bin": green_a["u-boot-sunxi-with-spl.bin"],
        "green-b-combined.bin": green_b["u-boot-sunxi-with-spl.bin"],
        "baseline-a.config": baseline_a["build.config"],
        "baseline-b.config": baseline_b["build.config"],
        "green-a.config": green_a["build.config"],
        "green-b.config": green_b["build.config"],
        "four-pass-inventory.tsv": four_pass_inventory(builds),
        "spl.bin": baseline_a["spl/sunxi-spl.bin"],
        "bl31.bin": bl31,
        "baseline-control.dtb": baseline_a["u-boot.dtb"],
        "green-control.dtb": green_a["u-boot.dtb"],
        "baseline-uboot.bin": baseline_a["u-boot-nodtb.bin"],
        "green-uboot.bin": green_a["u-boot-nodtb.bin"],
        "baseline.itb": baseline_a["u-boot.itb"],
        "green.itb": green_a["u-boot.itb"],
        "toolchain-authority.tsv": toolchain,
    }
    for name, data in published.items():
        with (output / name).open("xb") as destination:
            destination.write(data)

    rows: list[tuple[str, str | int]] = [
        ("schema", SCHEMA),
        ("rocknix-release", ROCKNIX_RELEASE),
        ("rocknix-commit", ROCKNIX_COMMIT),
        ("uboot-version", UBOOT_VERSION),
        ("package-path", PACKAGE_PATH),
        ("gcc-package-path", GCC_PACKAGE_PATH),
        ("defconfig", DEFCONFIG_NAME),
        ("source-tarball-sha256", SOURCE_TARBALL_SHA256),
        ("package-mk-sha256", PACKAGE_MK_SHA256),
        ("package-patch-sha256", PACKAGE_PATCH_SHA256),
        ("gcc-package-sha256", GCC_PACKAGE_SHA256),
        ("gcc-source-sha256", GCC_SOURCE_SHA256),
        ("upstream-defconfig-sha256", UPSTREAM_DEFCONFIG_SHA256),
        ("green-defconfig-sha256", GREEN_DEFCONFIG_SHA256),
        ("docker-image", DOCKER_IMAGE),
        ("source-date-epoch", SOURCE_DATE_EPOCH),
        ("fit-date-epoch", FIT_DATE_EPOCH),
        ("raw-offset", RAW_OFFSET),
        ("spl-region-bytes", SPL_REGION_BYTES),
        ("fit-bytes", FIT_BYTES),
        ("bl31-bytes", len(bl31)),
        ("bl31-sha256", sha256(bl31)),
        ("baseline-bytes", len(baseline)),
        ("baseline-sha256", sha256(baseline)),
        ("candidate-bytes", len(candidate)),
        ("candidate-sha256", sha256(candidate)),
        ("spl-sha256", sha256(baseline_a["spl/sunxi-spl.bin"])),
        ("control-fdt-sha256", sha256(baseline_a["u-boot.dtb"])),
        ("baseline-uboot-sha256", sha256(baseline_a["u-boot-nodtb.bin"])),
        ("candidate-uboot-sha256", sha256(green_a["u-boot-nodtb.bin"])),
        *summary.items(),
        ("baseline-repeat-byte-identical", "yes"),
        ("candidate-repeat-byte-identical", "yes"),
        ("shipping-baseline-byte-identical", "yes"),
        ("spl-byte-identical", "yes"),
        ("bl31-byte-identical", "yes"),
        ("control-fdt-byte-identical", "yes"),
        ("uboot-lto", "disabled"),
        ("build-config-only-status-gpio-diff", "yes"),
    ]
    write_tsv(output / "authority.tsv", rows)

    with (output / "sha256sums.txt").open("x", encoding="utf-8", newline="") as sums:
        for name in sorted(published):
            sums.write(f"{sha256(published[name])}  {name}\n")
        authority = (output / "authority.tsv").read_bytes()
        sums.write(f"{sha256(authority)}  authority.tsv\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-a", type=Path, required=True)
    parser.add_argument("--baseline-b", type=Path, required=True)
    parser.add_argument("--green-a", type=Path, required=True)
    parser.add_argument("--green-b", type=Path, required=True)
    parser.add_argument("--shipping", type=Path, required=True)
    parser.add_argument("--bl31", type=Path, required=True)
    parser.add_argument("--toolchain-authority", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    publish(
        args.baseline_a,
        args.baseline_b,
        args.green_a,
        args.green_b,
        args.shipping,
        args.bl31,
        args.toolchain_authority,
        args.output,
    )


if __name__ == "__main__":
    main()
