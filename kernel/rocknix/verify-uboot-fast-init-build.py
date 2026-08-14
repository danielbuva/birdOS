#!/usr/bin/env python3
"""Verify and seal repeated RG34XX-SP U-Boot fast-init builds.

The reviewed no-heap-clear authority is the immutable base.  The candidate
identity is recorded from two isolated builds but deliberately remains
unpinned until the real artifacts have been independently reviewed.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import struct


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE_VERIFIER_PATH = ROOT / "kernel/rocknix/verify-uboot-no-heap-clear-build.py"
STATUS_VERIFIER_PATH = ROOT / "kernel/rocknix/verify-uboot-status-led-build.py"

SCHEMA = "bird-uboot-fast-init-authority-v1"
TWO_PASS_SCHEMA = "bird-uboot-fast-init-two-pass-v1"
REVIEW_STATE = "candidate-hashes-pending"
ROCKNIX_RELEASE = "20260701"
ROCKNIX_COMMIT = "3e4ee5852e6ca5ea73a38369d2639fad2262648b"
UBOOT_VERSION = "v2026.01"
DEFCONFIG_NAME = "anbernic_rg35xx_h700_lpddr4_defconfig"
FAST_DEFCONFIG_SHA256 = (
    "f0b0c44e54c28675fddc2d92243ff0b35d475a07b2c196af053294fa38e90922"
)
BASE_AUTHORITY_SHA256 = (
    "cc8a83dcda26c6067ac603bbe31497be79e9836667a5e789c0ded423fe6178de"
)
BASE_COMBINED_SHA256 = (
    "38ace6d738fed727fdd2274b510c3e18105b2c71f7b1d908dece357e31d1365c"
)
BASE_CONFIG_SHA256 = (
    "57c109fd8a753cecf14c3afd60de1b6e778772975fa905dba1eda9b27230b23a"
)
BASE_UBOOT_SHA256 = (
    "d1ad2598283dac0913c5d49c5d3ccec7b21f9b14226038561c7334afff48fba4"
)
BASE_FIT_SHA256 = (
    "991d29c7201afceea7e18e5bc03707c8308306ba2cf67f16a1d48f95c2d14a7b"
)
BASE_SPL_SHA256 = (
    "0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c"
)
BASE_DTB_SHA256 = (
    "ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589"
)
BASE_FULL_PREFIX_SHA256 = (
    "ea1afbf3186945e562aa0844d7ab6d1b027be9cfafe225a0e4c0745ffc50b305"
)
BASELINE_PREFIX_SHA256 = (
    "fa35109b0b710ffe58dcb541d26349617f77d9213d25867dc328e666c3435774"
)
BL31_SHA256 = "431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673"
TOOLCHAIN_AUTHORITY_SHA256 = (
    "78ce9836240e264c933dac577348a01c56f2d8359d084439aa9aab6204733631"
)
SHIPPING_BASELINE_SHA256 = (
    "42c01f4524b45cba7c239cd940fc4e71eed7545901da201f27fed2193b7fdf45"
)
BL31_BYTES = 41065
RAW_OFFSET = 8192
SPL_REGION_BYTES = 40960
PREFIX_BYTES = 16 * 1024 * 1024
OLD_BOOT_COMMAND = (
    b"mmc dev 0; sysboot mmc 0:1 any ${scriptaddr} /extlinux/extlinux.conf"
)
FAST_BOOT_COMMAND = (
    b"sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux.conf"
)

# These are the exact semantic .config differences produced under the pinned
# GCC 15.2.0 build.  An inactive symbol is normalized to ``n`` whether Kconfig
# prints an explicit "is not set" line or omits the dependency-hidden symbol.
EXPECTED_CONFIG_DELTA: dict[bytes, tuple[bytes, bytes]] = {
    b"CONFIG_ARP_TIMEOUT": (b"5000", b"n"),
    b"CONFIG_BOOTCOMMAND": (b'"' + OLD_BOOT_COMMAND + b'"', b'"' + FAST_BOOT_COMMAND + b'"'),
    b"CONFIG_BOOTDELAY": (b"0", b"-2"),
    b"CONFIG_BOOTDEV_ETH": (b"y", b"n"),
    b"CONFIG_BOOTMETH_EXTLINUX": (b"y", b"n"),
    b"CONFIG_BOOTMETH_EXTLINUX_PXE": (b"y", b"n"),
    b"CONFIG_BOOTMETH_GLOBAL": (b"y", b"n"),
    b"CONFIG_BOOTMETH_VBE": (b"y", b"n"),
    b"CONFIG_BOOTMETH_VBE_REQUEST": (b"y", b"n"),
    b"CONFIG_BOOTMETH_VBE_SIMPLE": (b"y", b"n"),
    b"CONFIG_BOOTMETH_VBE_SIMPLE_OS": (b"y", b"n"),
    b"CONFIG_BOOTP_BOOTPATH": (b"y", b"n"),
    b"CONFIG_BOOTP_DNS": (b"y", b"n"),
    b"CONFIG_BOOTP_GATEWAY": (b"y", b"n"),
    b"CONFIG_BOOTP_HOSTNAME": (b"y", b"n"),
    b"CONFIG_BOOTP_MAX_ROOT_PATH_LEN": (b"64", b"n"),
    b"CONFIG_BOOTP_PXE": (b"y", b"n"),
    b"CONFIG_BOOTP_PXE_DHCP_OPTION": (b"y", b"n"),
    b"CONFIG_BOOTP_SUBNETMASK": (b"y", b"n"),
    b"CONFIG_BOOTP_VCI_STRING": (b'"U-Boot.armv8"', b"n"),
    b"CONFIG_BOOTSTD": (b"y", b"n"),
    b"CONFIG_CMD_BOOTFLOW": (b"y", b"n"),
    b"CONFIG_CMD_BOOTP": (b"y", b"n"),
    b"CONFIG_CMD_DHCP": (b"y", b"n"),
    b"CONFIG_CMD_MII": (b"y", b"n"),
    b"CONFIG_CMD_NET": (b"y", b"n"),
    b"CONFIG_CMD_PING": (b"y", b"n"),
    b"CONFIG_CMD_PXE": (b"y", b"n"),
    b"CONFIG_CMD_TFTPBOOT": (b"y", b"n"),
    b"CONFIG_DHCP_PXE_CLIENTARCH": (b"0x16", b"n"),
    b"CONFIG_DM_ETH": (b"y", b"n"),
    b"CONFIG_EVENT": (b"y", b"n"),
    b"CONFIG_NET": (b"y", b"n"),
    b"CONFIG_NETDEVICES": (b"y", b"n"),
    b"CONFIG_NET_RETRY_COUNT": (b"5", b"n"),
    b"CONFIG_NET_TFTP_VARS": (b"y", b"n"),
    b"CONFIG_NO_NET": (b"n", b"y"),
    b"CONFIG_REGEX": (b"y", b"n"),
    b"CONFIG_SERVERIP_FROM_PROXYDHCP_DELAY_MS": (b"100", b"n"),
    b"CONFIG_SPL_CRC8": (b"y", b"n"),
    b"CONFIG_TFTP_BLOCKSIZE": (b"1468", b"n"),
    b"CONFIG_TFTP_WINDOWSIZE": (b"1", b"n"),
}
if len(EXPECTED_CONFIG_DELTA) != 42:
    raise RuntimeError("fast-init resolved config authority is not 42 symbols")

# Frozen only after two isolated real builds and an independent artifact review.
REVIEWED_CANDIDATE_IDENTITIES: dict[str, str | int] = {
    "candidate-bytes": 556977,
    "candidate-sha256": "4afc68bd2a7fdaacc212683a1a268380c07775d18cf12025285778221e986081",
    "candidate-fit-bytes": 516017,
    "candidate-fit-sha256": "d827586fefa78cc12dba89b3912f1a428b5218415c62dc8308c24a252a0eaea9",
    "candidate-uboot-bytes": 437168,
    "candidate-uboot-sha256": "9d557ccc6efb40b4e4f3daeea648f51ae313d6bec9c342d41abf4b8fdefbeb89",
    "candidate-config-sha256": "34d359c61ede0bb54361b5f092cc9fa77fafdd3ed10aeee932622e290ad68971",
    "full-prefix-sha256": "172ca1a500603ea371a17bee1b6a7632ba17e4991a400f57cee0b2231e75bdeb",
}

REQUIRED_ARTIFACTS = (
    "u-boot-sunxi-with-spl.bin",
    "u-boot.itb",
    "u-boot-nodtb.bin",
    "u-boot.dtb",
    "spl/sunxi-spl.bin",
    "build.config",
)
BUILD_NAMES = ("fast-init-a", "fast-init-b")
PASS_SUFFIXES = (
    "-combined.bin",
    ".itb",
    "-uboot.bin",
    "-control.dtb",
    "-spl.bin",
    ".config",
)
PUBLISHED = (
    "authority.tsv",
    "base-no-heap-clear.bin",
    "base-no-heap-clear-prefix-16m.bin",
    "baseline-prefix-16m.bin",
    "bird-uboot-fast-init.bin",
    "bl31.bin",
    "fast-init.itb",
    "fast-init-uboot.bin",
    "fast-init-control.dtb",
    "fast-init-spl.bin",
    "fast-init.config",
    "fast-init.bin",
    "no-heap-clear-base-authority.tsv",
    "no-heap-clear-base-combined.bin",
    "no-heap-clear-base.config",
    "no-heap-clear-base.itb",
    "no-heap-clear-base-uboot.bin",
    "no-heap-clear-base-control.dtb",
    "no-heap-clear-base-spl.bin",
    "shipping-baseline.bin",
    *(f"{build}{suffix}" for build in BUILD_NAMES for suffix in PASS_SUFFIXES),
    "sha256sums.txt",
    "toolchain-authority.tsv",
    "two-pass-inventory.tsv",
)


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_bytes(path: pathlib.Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail(f"unsafe or missing artifact: {path}")
    return path.read_bytes()


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        fail(f"could not load {name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def base_verifier():
    return load_module("bird_no_heap_clear_verifier", BASE_VERIFIER_PATH)


def status_verifier():
    return load_module("bird_status_verifier_fast_init", STATUS_VERIFIER_PATH)


def config_map(data: bytes) -> dict[bytes, bytes]:
    result: dict[bytes, bytes] = {}
    for line in data.splitlines():
        if line.startswith(b"CONFIG_"):
            key, value = line.split(b"=", 1)
        elif line.startswith(b"# CONFIG_") and line.endswith(b" is not set"):
            key, value = line[2:-11], b"n"
        else:
            continue
        if key in result:
            fail(f"duplicate resolved config symbol: {key.decode()}")
        result[key] = value
    return result


def verify_config_delta(base: bytes, candidate: bytes) -> None:
    before, after = config_map(base), config_map(candidate)
    changed = {
        key: (before.get(key, b"n"), after.get(key, b"n"))
        for key in before.keys() | after.keys()
        if before.get(key, b"n") != after.get(key, b"n")
    }
    if changed != EXPECTED_CONFIG_DELTA:
        fail("resolved GCC config is not the exact 42-symbol fast-init delta")
    fixed = {
        b"CONFIG_CC_IS_GCC": b"y",
        b"CONFIG_CC_IS_CLANG": b"n",
        b"CONFIG_GCC_VERSION": b"150200",
        b"CONFIG_CLANG_VERSION": b"0",
        b"CONFIG_ARM64_CRC32": b"y",
        b"CONFIG_SYS_MALLOC_CLEAR_ON_INIT": b"n",
        b"CONFIG_SYS_MALLOC_LEN": b"0x4020000",
        b"CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT": b"y",
        b"CONFIG_ENV_IS_NOWHERE": b"y",
        b"CONFIG_ENV_IS_IN_FAT": b"n",
        b"CONFIG_CMD_SYSBOOT": b"y",
        b"CONFIG_PXE_UTILS": b"y",
        b"CONFIG_MENU": b"y",
        b"CONFIG_FS_FAT": b"y",
        b"CONFIG_MMC": b"y",
        b"CONFIG_MMC_SUNXI": b"y",
        b"CONFIG_CMD_BOOTI": b"y",
    }
    for key, expected in fixed.items():
        if after.get(key, b"n") != expected:
            fail(f"required fast-init config changed: {key.decode()}")


def verify_combined(combined: bytes, spl: bytes, fit: bytes) -> None:
    if len(combined) <= SPL_REGION_BYTES:
        fail("candidate combined image has no FIT payload")
    if combined[4:12] != b"eGON.BT0":
        fail("candidate lacks the Allwinner SPL signature")
    if struct.unpack_from("<I", combined, 0x10)[0] != SPL_REGION_BYTES:
        fail("candidate SPL fixed-region length changed")
    if len(spl) > SPL_REGION_BYTES or combined[: len(spl)] != spl:
        fail("candidate combined image does not begin with its SPL")
    if any(combined[len(spl):SPL_REGION_BYTES]):
        fail("candidate SPL-to-FIT padding is not zero")
    if combined[SPL_REGION_BYTES:] != fit:
        fail("candidate combined image does not end at its exact FIT boundary")


def load_build(directory: pathlib.Path) -> dict[str, bytes]:
    result = {name: file_bytes(directory / name) for name in REQUIRED_ARTIFACTS}
    verify_combined(
        result["u-boot-sunxi-with-spl.bin"],
        result["spl/sunxi-spl.bin"],
        result["u-boot.itb"],
    )
    return result


def assert_builds_equal(first: dict[str, bytes], second: dict[str, bytes]) -> None:
    if tuple(first) != REQUIRED_ARTIFACTS or tuple(second) != REQUIRED_ARTIFACTS:
        fail("two-pass artifact inventory changed")
    for name in REQUIRED_ARTIFACTS:
        if first[name] != second[name]:
            fail(f"fast-init build is not reproducible: {name} differs")


def verify_fit_scope(base_fit: bytes, candidate_fit: bytes) -> None:
    parser = status_verifier()
    before, after = parser.parse_fit(base_fit), parser.parse_fit(candidate_fit)
    if set(before) != set(after):
        fail("candidate FIT node inventory changed")
    for node in before:
        old, new = dict(before[node]), dict(after[node])
        if node == "/images/uboot":
            old.pop("data", None)
            new.pop("data", None)
        if old != new:
            fail(f"candidate FIT changed outside its U-Boot data: {node}")


def build_inventory(builds: dict[str, dict[str, bytes]]) -> bytes:
    if tuple(builds) != BUILD_NAMES:
        fail("two-pass build order changed")
    lines = [f"schema\t{TWO_PASS_SCHEMA}"]
    for build_name in BUILD_NAMES:
        build = builds[build_name]
        if tuple(build) != REQUIRED_ARTIFACTS:
            fail(f"{build_name} artifact order changed")
        for artifact_name in REQUIRED_ARTIFACTS:
            data = build[artifact_name]
            lines.append(
                f"artifact\t{build_name}\t{artifact_name}\t"
                f"{len(data)}\t{sha256(data)}"
            )
    return ("\n".join(lines) + "\n").encode("ascii")


def parse_authority(data: bytes) -> dict[str, str]:
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        fail("authority is not ASCII")
    if not text.endswith("\n"):
        fail("authority lacks a final newline")
    result: dict[str, str] = {}
    for line in text.splitlines():
        fields = line.split("\t")
        if len(fields) != 2 or not all(fields) or fields[0] in result:
            fail("authority row is malformed or duplicated")
        result[fields[0]] = fields[1]
    return result


def authority_bytes(rows: list[tuple[str, str | int]]) -> bytes:
    lines: list[str] = []
    for key, value in rows:
        rendered = str(value)
        if not key or not rendered or "\t" in key + rendered or "\n" in key + rendered:
            fail("unsafe authority value")
        lines.append(f"{key}\t{rendered}")
    return ("\n".join(lines) + "\n").encode("ascii")


def candidate_identity(build: dict[str, bytes], full_prefix: bytes) -> dict[str, str | int]:
    return {
        "candidate-bytes": len(build["u-boot-sunxi-with-spl.bin"]),
        "candidate-sha256": sha256(build["u-boot-sunxi-with-spl.bin"]),
        "candidate-fit-bytes": len(build["u-boot.itb"]),
        "candidate-fit-sha256": sha256(build["u-boot.itb"]),
        "candidate-uboot-bytes": len(build["u-boot-nodtb.bin"]),
        "candidate-uboot-sha256": sha256(build["u-boot-nodtb.bin"]),
        "candidate-config-sha256": sha256(build["build.config"]),
        "full-prefix-sha256": sha256(full_prefix),
    }


def verify_review_state(identity: dict[str, str | int]) -> None:
    if REVIEWED_CANDIDATE_IDENTITIES and identity != REVIEWED_CANDIDATE_IDENTITIES:
        fail("reviewed fast-init candidate identity changed")


def pass_files(build_name: str, build: dict[str, bytes]) -> dict[str, bytes]:
    return {
        f"{build_name}-combined.bin": build["u-boot-sunxi-with-spl.bin"],
        f"{build_name}.itb": build["u-boot.itb"],
        f"{build_name}-uboot.bin": build["u-boot-nodtb.bin"],
        f"{build_name}-control.dtb": build["u-boot.dtb"],
        f"{build_name}-spl.bin": build["spl/sunxi-spl.bin"],
        f"{build_name}.config": build["build.config"],
    }


def validate_candidate(
    first: dict[str, bytes],
    second: dict[str, bytes],
    base_files: dict[str, bytes],
    bl31: bytes,
    toolchain: bytes,
) -> None:
    assert_builds_equal(first, second)
    if first["u-boot-sunxi-with-spl.bin"] == base_files["combined"]:
        fail("fast-init candidate is byte-identical to its no-heap-clear base")
    uboot = first["u-boot-nodtb.bin"]
    if uboot == base_files["uboot"]:
        fail("fast-init candidate did not alter full U-Boot")
    if first["spl/sunxi-spl.bin"] != base_files["spl"]:
        fail("fast-init candidate altered the SPL")
    if first["u-boot.dtb"] != base_files["dtb"]:
        fail("fast-init candidate altered the control FDT")
    verify_config_delta(base_files["config"], first["build.config"])
    new_boot = b"bootcmd=" + FAST_BOOT_COMMAND + b"\0"
    old_boot = b"bootcmd=" + OLD_BOOT_COMMAND + b"\0"
    if uboot.count(new_boot) != 1 or old_boot in uboot:
        fail("compiled fast-init boot command is not exact")
    if uboot.count(b"bootdelay=-2\0") != 1 or b"bootdelay=0\0" in uboot:
        fail("compiled no-delay autoboot policy is not exact")
    verify_fit_scope(base_files["fit"], first["u-boot.itb"])
    status = status_verifier()
    status.verify_fit(
        first["u-boot.itb"], uboot, bl31, first["u-boot.dtb"]
    )
    status.verify_toolchain_authority(toolchain)


def load_base(
    base: pathlib.Path,
) -> tuple[dict[str, bytes], bytes, bytes, bytes, bytes, bytes, bytes]:
    verifier = base_verifier()
    verifier.verify_output(base)
    authority = file_bytes(base / "authority.tsv")
    if sha256(authority) != BASE_AUTHORITY_SHA256:
        fail("reviewed no-heap-clear authority record changed")
    files = {
        "combined": file_bytes(base / "no-heap-clear.bin"),
        "config": file_bytes(base / "no-heap-clear.config"),
        "fit": file_bytes(base / "no-heap-clear.itb"),
        "uboot": file_bytes(base / "no-heap-clear-uboot.bin"),
        "dtb": file_bytes(base / "no-heap-clear-control.dtb"),
        "spl": file_bytes(base / "no-heap-clear-spl.bin"),
    }
    expected = {
        "combined": BASE_COMBINED_SHA256,
        "config": BASE_CONFIG_SHA256,
        "fit": BASE_FIT_SHA256,
        "uboot": BASE_UBOOT_SHA256,
        "dtb": BASE_DTB_SHA256,
        "spl": BASE_SPL_SHA256,
    }
    for name, digest in expected.items():
        if sha256(files[name]) != digest:
            fail(f"reviewed no-heap-clear {name} changed")
    baseline_prefix = file_bytes(base / "baseline-prefix-16m.bin")
    if len(baseline_prefix) != PREFIX_BYTES or sha256(baseline_prefix) != BASELINE_PREFIX_SHA256:
        fail("reviewed baseline prefix changed")
    base_prefix = bytearray(baseline_prefix)
    base_prefix[RAW_OFFSET:RAW_OFFSET + len(files["combined"])] = files["combined"]
    if sha256(base_prefix) != BASE_FULL_PREFIX_SHA256:
        fail("reviewed no-heap-clear full prefix changed")
    shipping = file_bytes(base / "shipping-baseline.bin")
    if sha256(shipping) != SHIPPING_BASELINE_SHA256:
        fail("reviewed shipping baseline changed")
    retained_bl31 = file_bytes(base / "bl31.bin")
    retained_toolchain = file_bytes(base / "toolchain-authority.tsv")
    return files, authority, baseline_prefix, bytes(base_prefix), shipping, retained_bl31, retained_toolchain


def publish(
    build_a: pathlib.Path,
    build_b: pathlib.Path,
    base: pathlib.Path,
    bl31_path: pathlib.Path,
    toolchain_path: pathlib.Path,
    output: pathlib.Path,
) -> None:
    if output.exists() or output.is_symlink():
        fail(f"refusing to replace result directory: {output}")
    (
        base_files,
        base_authority,
        baseline_prefix,
        base_prefix,
        shipping,
        retained_bl31,
        retained_toolchain,
    ) = load_base(base)
    bl31 = file_bytes(bl31_path)
    if len(bl31) != BL31_BYTES or sha256(bl31) != BL31_SHA256 or bl31 != retained_bl31:
        fail("pinned BL31 differs from the no-heap-clear base")
    toolchain = file_bytes(toolchain_path)
    if sha256(toolchain) != TOOLCHAIN_AUTHORITY_SHA256 or toolchain != retained_toolchain:
        fail("pinned toolchain differs from the no-heap-clear base")
    first, second = load_build(build_a), load_build(build_b)
    validate_candidate(first, second, base_files, bl31, toolchain)

    candidate_prefix = bytearray(base_prefix)
    combined = first["u-boot-sunxi-with-spl.bin"]
    end = RAW_OFFSET + len(combined)
    if end > len(candidate_prefix):
        fail("candidate exceeds the reviewed raw prefix")
    candidate_prefix[RAW_OFFSET:end] = combined
    identity = candidate_identity(first, bytes(candidate_prefix))
    verify_review_state(identity)
    review_state = "reviewed" if REVIEWED_CANDIDATE_IDENTITIES else REVIEW_STATE

    builds = {"fast-init-a": first, "fast-init-b": second}
    published = {
        "base-no-heap-clear.bin": base_files["combined"],
        "base-no-heap-clear-prefix-16m.bin": base_prefix,
        "baseline-prefix-16m.bin": baseline_prefix,
        "bird-uboot-fast-init.bin": combined,
        "bl31.bin": bl31,
        "fast-init.itb": first["u-boot.itb"],
        "fast-init-uboot.bin": first["u-boot-nodtb.bin"],
        "fast-init-control.dtb": first["u-boot.dtb"],
        "fast-init-spl.bin": first["spl/sunxi-spl.bin"],
        "fast-init.config": first["build.config"],
        "fast-init.bin": combined,
        "no-heap-clear-base-authority.tsv": base_authority,
        "no-heap-clear-base-combined.bin": base_files["combined"],
        "no-heap-clear-base.config": base_files["config"],
        "no-heap-clear-base.itb": base_files["fit"],
        "no-heap-clear-base-uboot.bin": base_files["uboot"],
        "no-heap-clear-base-control.dtb": base_files["dtb"],
        "no-heap-clear-base-spl.bin": base_files["spl"],
        "shipping-baseline.bin": shipping,
        "toolchain-authority.tsv": toolchain,
        "two-pass-inventory.tsv": build_inventory(builds),
    }
    published.update(pass_files("fast-init-a", first))
    published.update(pass_files("fast-init-b", second))
    published["authority.tsv"] = authority_bytes(
        [
            ("schema", SCHEMA),
            ("review-state", review_state),
            ("rocknix-release", ROCKNIX_RELEASE),
            ("rocknix-commit", ROCKNIX_COMMIT),
            ("uboot-version", UBOOT_VERSION),
            ("defconfig", DEFCONFIG_NAME),
            ("fast-defconfig-sha256", FAST_DEFCONFIG_SHA256),
            ("no-heap-clear-authority-sha256", BASE_AUTHORITY_SHA256),
            ("no-heap-clear-combined-sha256", BASE_COMBINED_SHA256),
            ("no-heap-clear-config-sha256", BASE_CONFIG_SHA256),
            *identity.items(),
            ("spl-sha256", sha256(first["spl/sunxi-spl.bin"])),
            ("control-fdt-sha256", sha256(first["u-boot.dtb"])),
            ("bl31-sha256", sha256(bl31)),
            ("resolved-gcc-config-delta-symbols", len(EXPECTED_CONFIG_DELTA)),
            ("boot-delay", -2),
            ("boot-command", "fixed-mmc0p1-fat-sysboot"),
            ("network-stack-built", "no"),
            ("bootstd-built", "no"),
            ("no-heap-clear-preserved", "yes"),
            ("candidate-repeat-byte-identical", "yes"),
            ("spl-byte-identical-to-base", "yes"),
            ("control-fdt-byte-identical-to-base", "yes"),
            ("bl31-byte-identical-to-base", "yes"),
            ("fit-change-scope", "uboot-data-only"),
        ]
    )

    output.mkdir(mode=0o755)
    for name, data in published.items():
        with (output / name).open("xb") as destination:
            destination.write(data)
    with (output / "sha256sums.txt").open("x", encoding="ascii", newline="") as sums:
        for name, data in sorted(published.items()):
            sums.write(f"{sha256(data)}  {name}\n")


def verify_output(directory: pathlib.Path) -> None:
    if directory.is_symlink() or not directory.is_dir():
        fail("fast-init authority is missing or unsafe")
    if tuple(sorted(path.name for path in directory.iterdir())) != tuple(sorted(PUBLISHED)):
        fail("fast-init authority inventory changed")
    expected = sorted(name for name in PUBLISHED if name != "sha256sums.txt")
    lines = file_bytes(directory / "sha256sums.txt").decode("ascii").splitlines()
    if len(lines) != len(expected):
        fail("fast-init checksum inventory changed")
    for line, name in zip(lines, expected):
        if line != f"{sha256(file_bytes(directory / name))}  {name}":
            fail(f"fast-init checksum changed: {name}")

    authority = parse_authority(file_bytes(directory / "authority.tsv"))
    required = {
        "schema": SCHEMA,
        "review-state": "reviewed" if REVIEWED_CANDIDATE_IDENTITIES else REVIEW_STATE,
        "rocknix-release": ROCKNIX_RELEASE,
        "rocknix-commit": ROCKNIX_COMMIT,
        "uboot-version": UBOOT_VERSION,
        "defconfig": DEFCONFIG_NAME,
        "fast-defconfig-sha256": FAST_DEFCONFIG_SHA256,
        "no-heap-clear-authority-sha256": BASE_AUTHORITY_SHA256,
        "no-heap-clear-combined-sha256": BASE_COMBINED_SHA256,
        "no-heap-clear-config-sha256": BASE_CONFIG_SHA256,
        "spl-sha256": BASE_SPL_SHA256,
        "control-fdt-sha256": BASE_DTB_SHA256,
        "bl31-sha256": BL31_SHA256,
        "resolved-gcc-config-delta-symbols": "42",
        "boot-delay": "-2",
        "boot-command": "fixed-mmc0p1-fat-sysboot",
        "network-stack-built": "no",
        "bootstd-built": "no",
        "no-heap-clear-preserved": "yes",
        "candidate-repeat-byte-identical": "yes",
        "spl-byte-identical-to-base": "yes",
        "control-fdt-byte-identical-to-base": "yes",
        "bl31-byte-identical-to-base": "yes",
        "fit-change-scope": "uboot-data-only",
    }
    for key, value in required.items():
        if authority.get(key) != value:
            fail(f"fast-init authority field changed: {key}")

    first = {
        "u-boot-sunxi-with-spl.bin": file_bytes(directory / "fast-init-a-combined.bin"),
        "u-boot.itb": file_bytes(directory / "fast-init-a.itb"),
        "u-boot-nodtb.bin": file_bytes(directory / "fast-init-a-uboot.bin"),
        "u-boot.dtb": file_bytes(directory / "fast-init-a-control.dtb"),
        "spl/sunxi-spl.bin": file_bytes(directory / "fast-init-a-spl.bin"),
        "build.config": file_bytes(directory / "fast-init-a.config"),
    }
    second = {
        "u-boot-sunxi-with-spl.bin": file_bytes(directory / "fast-init-b-combined.bin"),
        "u-boot.itb": file_bytes(directory / "fast-init-b.itb"),
        "u-boot-nodtb.bin": file_bytes(directory / "fast-init-b-uboot.bin"),
        "u-boot.dtb": file_bytes(directory / "fast-init-b-control.dtb"),
        "spl/sunxi-spl.bin": file_bytes(directory / "fast-init-b-spl.bin"),
        "build.config": file_bytes(directory / "fast-init-b.config"),
    }
    base_files = {
        "combined": file_bytes(directory / "no-heap-clear-base-combined.bin"),
        "config": file_bytes(directory / "no-heap-clear-base.config"),
        "fit": file_bytes(directory / "no-heap-clear-base.itb"),
        "uboot": file_bytes(directory / "no-heap-clear-base-uboot.bin"),
        "dtb": file_bytes(directory / "no-heap-clear-base-control.dtb"),
        "spl": file_bytes(directory / "no-heap-clear-base-spl.bin"),
    }
    if sha256(file_bytes(directory / "no-heap-clear-base-authority.tsv")) != BASE_AUTHORITY_SHA256:
        fail("retained no-heap-clear authority changed")
    for name, digest in {
        "combined": BASE_COMBINED_SHA256,
        "config": BASE_CONFIG_SHA256,
        "fit": BASE_FIT_SHA256,
        "uboot": BASE_UBOOT_SHA256,
        "dtb": BASE_DTB_SHA256,
        "spl": BASE_SPL_SHA256,
    }.items():
        if sha256(base_files[name]) != digest:
            fail(f"retained no-heap-clear {name} changed")
    bl31 = file_bytes(directory / "bl31.bin")
    toolchain = file_bytes(directory / "toolchain-authority.tsv")
    if len(bl31) != BL31_BYTES or sha256(bl31) != BL31_SHA256:
        fail("retained BL31 changed")
    if sha256(toolchain) != TOOLCHAIN_AUTHORITY_SHA256:
        fail("retained toolchain authority changed")
    validate_candidate(first, second, base_files, bl31, toolchain)

    canonical = file_bytes(directory / "bird-uboot-fast-init.bin")
    if canonical != first["u-boot-sunxi-with-spl.bin"]:
        fail("canonical fast-init candidate differs from retained passes")
    if file_bytes(directory / "fast-init.bin") != canonical:
        fail("installer fast-init candidate differs from retained passes")
    if file_bytes(directory / "base-no-heap-clear.bin") != base_files["combined"]:
        fail("installer no-heap-clear base differs from retained base")
    for filename, artifact in (
        ("fast-init.itb", "u-boot.itb"),
        ("fast-init-uboot.bin", "u-boot-nodtb.bin"),
        ("fast-init-control.dtb", "u-boot.dtb"),
        ("fast-init-spl.bin", "spl/sunxi-spl.bin"),
        ("fast-init.config", "build.config"),
    ):
        if file_bytes(directory / filename) != first[artifact]:
            fail(f"canonical fast-init component changed: {filename}")

    baseline_prefix = file_bytes(directory / "baseline-prefix-16m.bin")
    base_prefix = file_bytes(directory / "base-no-heap-clear-prefix-16m.bin")
    if len(baseline_prefix) != PREFIX_BYTES or sha256(baseline_prefix) != BASELINE_PREFIX_SHA256:
        fail("retained baseline prefix changed")
    expected_base_prefix = bytearray(baseline_prefix)
    expected_base_prefix[RAW_OFFSET:RAW_OFFSET + len(base_files["combined"])] = base_files["combined"]
    if base_prefix != bytes(expected_base_prefix) or sha256(base_prefix) != BASE_FULL_PREFIX_SHA256:
        fail("retained no-heap-clear full prefix changed")
    candidate_prefix = bytearray(base_prefix)
    candidate_prefix[RAW_OFFSET:RAW_OFFSET + len(canonical)] = canonical
    identity = candidate_identity(first, bytes(candidate_prefix))
    verify_review_state(identity)
    for key, value in identity.items():
        if authority.get(key) != str(value):
            fail(f"candidate identity field changed: {key}")
    if file_bytes(directory / "shipping-baseline.bin") == b"" or sha256(
        file_bytes(directory / "shipping-baseline.bin")
    ) != SHIPPING_BASELINE_SHA256:
        fail("retained shipping baseline changed")
    if file_bytes(directory / "two-pass-inventory.tsv") != build_inventory(
        {"fast-init-a": first, "fast-init-b": second}
    ):
        fail("two-pass inventory changed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-a", type=pathlib.Path)
    parser.add_argument("--build-b", type=pathlib.Path)
    parser.add_argument("--base-authority", type=pathlib.Path)
    parser.add_argument("--bl31", type=pathlib.Path)
    parser.add_argument("--toolchain-authority", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--verify-output", type=pathlib.Path)
    args = parser.parse_args()
    if args.verify_output:
        if any(
            (
                args.build_a,
                args.build_b,
                args.base_authority,
                args.bl31,
                args.toolchain_authority,
                args.output,
            )
        ):
            fail("--verify-output cannot be combined with publication inputs")
        verify_output(args.verify_output)
        state = "reviewed" if REVIEWED_CANDIDATE_IDENTITIES else "hashes pending"
        print(f"U-Boot fast-init authority: VERIFIED ({state})")
        return
    if not all(
        (
            args.build_a,
            args.build_b,
            args.base_authority,
            args.bl31,
            args.toolchain_authority,
            args.output,
        )
    ):
        fail("publication requires two builds, exact base, BL31, toolchain, and output")
    publish(
        args.build_a,
        args.build_b,
        args.base_authority,
        args.bl31,
        args.toolchain_authority,
        args.output,
    )


if __name__ == "__main__":
    main()
