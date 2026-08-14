#!/usr/bin/env python3
"""Verify and seal repeated RG34XX-SP U-Boot no-heap-clear builds.

The accepted direct-extlinux authority is the immutable base.  Candidate
identities are deliberately computed from two isolated builds and marked
pending until they have been reviewed and pinned; this module never invents a
hash for a build that has not happened yet.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import struct


ROOT = pathlib.Path(__file__).resolve().parents[2]
DIRECT_VERIFIER_PATH = ROOT / "kernel/rocknix/verify-uboot-direct-extlinux-build.py"
STATUS_VERIFIER_PATH = ROOT / "kernel/rocknix/verify-uboot-status-led-build.py"

SCHEMA = "bird-uboot-no-heap-clear-authority-v1"
TWO_PASS_SCHEMA = "bird-uboot-no-heap-clear-two-pass-v1"
REVIEW_STATE = "candidate-hashes-pending"
ROCKNIX_RELEASE = "20260701"
ROCKNIX_COMMIT = "3e4ee5852e6ca5ea73a38369d2639fad2262648b"
UBOOT_VERSION = "v2026.01"
DEFCONFIG_NAME = "anbernic_rg35xx_h700_lpddr4_defconfig"
NO_CLEAR_DEFCONFIG_SHA256 = (
    "74d6dc38c098657e081877f321470455556ae385e1642e36151d32da2faa9bc1"
)
DIRECT_AUTHORITY_SHA256 = (
    "8f15f4e647f1aecd6266df3861aeb5a2534db26a3b6280801d0bd4efbd99ce09"
)
DIRECT_COMBINED_SHA256 = (
    "cd99dd9edaad868e460b256729c2e0f5a20a606a2a33e4015d93c42159da1191"
)
DIRECT_CONFIG_SHA256 = (
    "3e1eac486c6e9aa1f73f44e0ee63fde72171bd7b7e6b75a5fa09869b96f64f9b"
)
DIRECT_UBOOT_SHA256 = (
    "222123612cf81b7d8e9c0098295c78048a546ce2249f7252c80f623b1f001cb6"
)
DIRECT_FIT_SHA256 = (
    "958488fc380b9441d3b0c78cc6c04ffc46c19a0c9c4692428f9c1acc1124aa53"
)
DIRECT_SPL_SHA256 = (
    "0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c"
)
DIRECT_DTB_SHA256 = (
    "ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589"
)
BASELINE_PREFIX_SHA256 = (
    "fa35109b0b710ffe58dcb541d26349617f77d9213d25867dc328e666c3435774"
)
BL31_SHA256 = "431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673"
BL31_BYTES = 41065
RAW_OFFSET = 8192
SPL_REGION_BYTES = 40960
BASELINE_PREFIX_BYTES = 16 * 1024 * 1024
BOOT_COMMAND = (
    b'mmc dev 0; sysboot mmc 0:1 any ${scriptaddr} /extlinux/extlinux.conf'
)

REVIEWED_CANDIDATE_IDENTITIES: dict[str, str | int] = {
    "candidate-bytes": 620745,
    "candidate-sha256": "38ace6d738fed727fdd2274b510c3e18105b2c71f7b1d908dece357e31d1365c",
    "candidate-fit-bytes": 579785,
    "candidate-fit-sha256": "991d29c7201afceea7e18e5bc03707c8308306ba2cf67f16a1d48f95c2d14a7b",
    "candidate-uboot-bytes": 500936,
    "candidate-uboot-sha256": "d1ad2598283dac0913c5d49c5d3ccec7b21f9b14226038561c7334afff48fba4",
    "candidate-config-sha256": "57c109fd8a753cecf14c3afd60de1b6e778772975fa905dba1eda9b27230b23a",
    "full-prefix-sha256": "ea1afbf3186945e562aa0844d7ab6d1b027be9cfafe225a0e4c0745ffc50b305",
}

REQUIRED_ARTIFACTS = (
    "u-boot-sunxi-with-spl.bin",
    "u-boot.itb",
    "u-boot-nodtb.bin",
    "u-boot.dtb",
    "spl/sunxi-spl.bin",
    "build.config",
)
BUILD_NAMES = ("no-clear-a", "no-clear-b")
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
    "base-direct.bin",
    "baseline-prefix-16m.bin",
    "bird-uboot-no-heap-clear.bin",
    "bl31.bin",
    "direct-base-authority.tsv",
    "direct-base-combined.bin",
    "direct-base.config",
    "direct-base.itb",
    "direct-base-uboot.bin",
    "direct-base-control.dtb",
    "direct-base-spl.bin",
    "no-heap-clear.itb",
    "no-heap-clear-uboot.bin",
    "no-heap-clear-control.dtb",
    "no-heap-clear-spl.bin",
    "no-heap-clear.config",
    "no-heap-clear.bin",
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


def direct_verifier():
    return load_module("bird_direct_verifier", DIRECT_VERIFIER_PATH)


def status_verifier():
    return load_module("bird_status_verifier", STATUS_VERIFIER_PATH)


def config_map(data: bytes) -> dict[bytes, bytes]:
    result: dict[bytes, bytes] = {}
    for line in data.splitlines():
        if line.startswith(b"CONFIG_"):
            key, value = line.split(b"=", 1)
            if key in result:
                fail(f"duplicate resolved config symbol: {key.decode()}")
            result[key] = value
        elif line.startswith(b"# CONFIG_") and line.endswith(b" is not set"):
            key = line[2:-11]
            if key in result:
                fail(f"duplicate resolved config symbol: {key.decode()}")
            result[key] = b"n"
    return result


def verify_config_delta(base: bytes, candidate: bytes) -> None:
    before, after = config_map(base), config_map(candidate)
    changed = {
        key: (before.get(key), after.get(key))
        for key in before.keys() | after.keys()
        if before.get(key) != after.get(key)
    }
    expected = {b"CONFIG_SYS_MALLOC_CLEAR_ON_INIT": (b"y", b"n")}
    if changed != expected:
        fail("resolved config changed outside full-U-Boot heap clearing")
    fixed = {
        b"CONFIG_SYS_MALLOC_LEN": b"0x4020000",
        b"CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT": b"y",
        b"CONFIG_LTO": b"n",
        b"CONFIG_BOOTCOMMAND": b'"' + BOOT_COMMAND + b'"',
        b"CONFIG_ENV_IS_NOWHERE": b"y",
        b"CONFIG_ENV_IS_IN_FAT": b"n",
    }
    for key, expected_value in fixed.items():
        if after.get(key) != expected_value:
            fail(f"required no-heap-clear config changed: {key.decode()}")


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
            fail(f"no-heap-clear build is not reproducible: {name} differs")


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
    if not REVIEWED_CANDIDATE_IDENTITIES:
        return
    if identity != REVIEWED_CANDIDATE_IDENTITIES:
        fail("reviewed no-heap-clear candidate identity changed")


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
    combined = first["u-boot-sunxi-with-spl.bin"]
    if combined == base_files["combined"]:
        fail("no-heap-clear candidate is byte-identical to its direct base")
    if first["u-boot-nodtb.bin"] == base_files["uboot"]:
        fail("no-heap-clear candidate did not alter full U-Boot")
    if first["spl/sunxi-spl.bin"] != base_files["spl"]:
        fail("no-heap-clear candidate altered the SPL")
    if first["u-boot.dtb"] != base_files["dtb"]:
        fail("no-heap-clear candidate altered the control FDT")
    verify_config_delta(base_files["config"], first["build.config"])
    verify_fit_scope(base_files["fit"], first["u-boot.itb"])
    status = status_verifier()
    status.verify_fit(
        first["u-boot.itb"], first["u-boot-nodtb.bin"], bl31, first["u-boot.dtb"]
    )
    status.verify_toolchain_authority(toolchain)


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
    direct = direct_verifier()
    direct.verify_output(base)
    direct_authority = file_bytes(base / "authority.tsv")
    if sha256(direct_authority) != DIRECT_AUTHORITY_SHA256:
        fail("accepted direct-extlinux authority record changed")

    base_files = {
        "combined": file_bytes(base / "direct-extlinux.bin"),
        "config": file_bytes(base / "direct-a.config"),
        "fit": file_bytes(base / "direct-extlinux.itb"),
        "uboot": file_bytes(base / "direct-extlinux-uboot.bin"),
        "dtb": file_bytes(base / "direct-extlinux.dtb"),
        "spl": file_bytes(base / "direct-extlinux-spl.bin"),
        "prefix": file_bytes(base / "baseline-prefix-16m.bin"),
    }
    expected_hashes = {
        "combined": DIRECT_COMBINED_SHA256,
        "config": DIRECT_CONFIG_SHA256,
        "fit": DIRECT_FIT_SHA256,
        "uboot": DIRECT_UBOOT_SHA256,
        "dtb": DIRECT_DTB_SHA256,
        "spl": DIRECT_SPL_SHA256,
        "prefix": BASELINE_PREFIX_SHA256,
    }
    for name, expected in expected_hashes.items():
        if sha256(base_files[name]) != expected:
            fail(f"accepted direct-extlinux {name} changed")
    if len(base_files["prefix"]) != BASELINE_PREFIX_BYTES:
        fail("accepted baseline prefix size changed")

    bl31 = file_bytes(bl31_path)
    if len(bl31) != BL31_BYTES or sha256(bl31) != BL31_SHA256:
        fail("pinned BL31 authority changed")
    toolchain = file_bytes(toolchain_path)
    first, second = load_build(build_a), load_build(build_b)
    validate_candidate(first, second, base_files, bl31, toolchain)

    full_prefix = bytearray(base_files["prefix"])
    combined = first["u-boot-sunxi-with-spl.bin"]
    end = RAW_OFFSET + len(combined)
    if end > len(full_prefix):
        fail("candidate exceeds the verified raw prefix")
    full_prefix[RAW_OFFSET:end] = combined
    identity = candidate_identity(first, bytes(full_prefix))
    verify_review_state(identity)
    review_state = "reviewed" if REVIEWED_CANDIDATE_IDENTITIES else REVIEW_STATE

    builds = {"no-clear-a": first, "no-clear-b": second}
    published = {
        "base-direct.bin": base_files["combined"],
        "baseline-prefix-16m.bin": base_files["prefix"],
        "bird-uboot-no-heap-clear.bin": combined,
        "bl31.bin": bl31,
        "direct-base-authority.tsv": direct_authority,
        "direct-base-combined.bin": base_files["combined"],
        "direct-base.config": base_files["config"],
        "direct-base.itb": base_files["fit"],
        "direct-base-uboot.bin": base_files["uboot"],
        "direct-base-control.dtb": base_files["dtb"],
        "direct-base-spl.bin": base_files["spl"],
        "no-heap-clear.itb": first["u-boot.itb"],
        "no-heap-clear-uboot.bin": first["u-boot-nodtb.bin"],
        "no-heap-clear-control.dtb": first["u-boot.dtb"],
        "no-heap-clear-spl.bin": first["spl/sunxi-spl.bin"],
        "no-heap-clear.config": first["build.config"],
        "no-heap-clear.bin": combined,
        "shipping-baseline.bin": file_bytes(base / "shipping-baseline.bin"),
        "toolchain-authority.tsv": toolchain,
        "two-pass-inventory.tsv": build_inventory(builds),
    }
    published.update(pass_files("no-clear-a", first))
    published.update(pass_files("no-clear-b", second))
    authority = authority_bytes(
        [
            ("schema", SCHEMA),
            ("review-state", review_state),
            ("rocknix-release", ROCKNIX_RELEASE),
            ("rocknix-commit", ROCKNIX_COMMIT),
            ("uboot-version", UBOOT_VERSION),
            ("defconfig", DEFCONFIG_NAME),
            ("no-clear-defconfig-sha256", NO_CLEAR_DEFCONFIG_SHA256),
            ("direct-authority-sha256", DIRECT_AUTHORITY_SHA256),
            ("direct-combined-sha256", DIRECT_COMBINED_SHA256),
            ("direct-config-sha256", DIRECT_CONFIG_SHA256),
            *identity.items(),
            ("spl-sha256", sha256(first["spl/sunxi-spl.bin"])),
            ("control-fdt-sha256", sha256(first["u-boot.dtb"])),
            ("bl31-sha256", sha256(bl31)),
            ("full-uboot-heap-bytes-not-cleared", 0x4020000),
            ("spl-heap-clear-preserved", "yes"),
            ("resolved-config-only-heap-clear-diff", "yes"),
            ("candidate-repeat-byte-identical", "yes"),
            ("spl-byte-identical-to-direct", "yes"),
            ("control-fdt-byte-identical-to-direct", "yes"),
            ("bl31-byte-identical", "yes"),
        ]
    )
    published["authority.tsv"] = authority

    output.mkdir(mode=0o755)
    for name, data in published.items():
        with (output / name).open("xb") as destination:
            destination.write(data)
    with (output / "sha256sums.txt").open("x", encoding="ascii", newline="") as sums:
        for name, data in sorted(published.items()):
            sums.write(f"{sha256(data)}  {name}\n")


def verify_output(directory: pathlib.Path) -> None:
    if directory.is_symlink() or not directory.is_dir():
        fail("no-heap-clear authority is missing or unsafe")
    found = tuple(sorted(path.name for path in directory.iterdir()))
    if found != tuple(sorted(PUBLISHED)):
        fail("no-heap-clear authority inventory changed")
    expected = sorted(name for name in PUBLISHED if name != "sha256sums.txt")
    lines = file_bytes(directory / "sha256sums.txt").decode("ascii").splitlines()
    if len(lines) != len(expected):
        fail("no-heap-clear checksum inventory changed")
    for line, name in zip(lines, expected):
        if line != f"{sha256(file_bytes(directory / name))}  {name}":
            fail(f"no-heap-clear checksum changed: {name}")

    authority = parse_authority(file_bytes(directory / "authority.tsv"))
    required = {
        "schema": SCHEMA,
        "review-state": "reviewed" if REVIEWED_CANDIDATE_IDENTITIES else REVIEW_STATE,
        "rocknix-release": ROCKNIX_RELEASE,
        "rocknix-commit": ROCKNIX_COMMIT,
        "uboot-version": UBOOT_VERSION,
        "defconfig": DEFCONFIG_NAME,
        "no-clear-defconfig-sha256": NO_CLEAR_DEFCONFIG_SHA256,
        "direct-authority-sha256": DIRECT_AUTHORITY_SHA256,
        "direct-combined-sha256": DIRECT_COMBINED_SHA256,
        "direct-config-sha256": DIRECT_CONFIG_SHA256,
        "spl-sha256": DIRECT_SPL_SHA256,
        "control-fdt-sha256": DIRECT_DTB_SHA256,
        "bl31-sha256": BL31_SHA256,
        "full-uboot-heap-bytes-not-cleared": str(0x4020000),
        "spl-heap-clear-preserved": "yes",
        "resolved-config-only-heap-clear-diff": "yes",
        "candidate-repeat-byte-identical": "yes",
        "spl-byte-identical-to-direct": "yes",
        "control-fdt-byte-identical-to-direct": "yes",
        "bl31-byte-identical": "yes",
    }
    for key, value in required.items():
        if authority.get(key) != value:
            fail(f"no-heap-clear authority field changed: {key}")

    first = {
        "u-boot-sunxi-with-spl.bin": file_bytes(directory / "no-clear-a-combined.bin"),
        "u-boot.itb": file_bytes(directory / "no-clear-a.itb"),
        "u-boot-nodtb.bin": file_bytes(directory / "no-clear-a-uboot.bin"),
        "u-boot.dtb": file_bytes(directory / "no-clear-a-control.dtb"),
        "spl/sunxi-spl.bin": file_bytes(directory / "no-clear-a-spl.bin"),
        "build.config": file_bytes(directory / "no-clear-a.config"),
    }
    second = {
        "u-boot-sunxi-with-spl.bin": file_bytes(directory / "no-clear-b-combined.bin"),
        "u-boot.itb": file_bytes(directory / "no-clear-b.itb"),
        "u-boot-nodtb.bin": file_bytes(directory / "no-clear-b-uboot.bin"),
        "u-boot.dtb": file_bytes(directory / "no-clear-b-control.dtb"),
        "spl/sunxi-spl.bin": file_bytes(directory / "no-clear-b-spl.bin"),
        "build.config": file_bytes(directory / "no-clear-b.config"),
    }
    for build in (first, second):
        verify_combined(
            build["u-boot-sunxi-with-spl.bin"],
            build["spl/sunxi-spl.bin"],
            build["u-boot.itb"],
        )
    base_files = {
        "combined": file_bytes(directory / "direct-base-combined.bin"),
        "config": file_bytes(directory / "direct-base.config"),
        "fit": file_bytes(directory / "direct-base.itb"),
        "uboot": file_bytes(directory / "direct-base-uboot.bin"),
        "dtb": file_bytes(directory / "direct-base-control.dtb"),
        "spl": file_bytes(directory / "direct-base-spl.bin"),
    }
    if sha256(file_bytes(directory / "direct-base-authority.tsv")) != DIRECT_AUTHORITY_SHA256:
        fail("retained direct authority changed")
    for name, expected_hash in {
        "combined": DIRECT_COMBINED_SHA256,
        "config": DIRECT_CONFIG_SHA256,
        "fit": DIRECT_FIT_SHA256,
        "uboot": DIRECT_UBOOT_SHA256,
        "dtb": DIRECT_DTB_SHA256,
        "spl": DIRECT_SPL_SHA256,
    }.items():
        if sha256(base_files[name]) != expected_hash:
            fail(f"retained direct {name} base changed")
    bl31 = file_bytes(directory / "bl31.bin")
    if len(bl31) != BL31_BYTES or sha256(bl31) != BL31_SHA256:
        fail("retained BL31 changed")
    toolchain = file_bytes(directory / "toolchain-authority.tsv")
    validate_candidate(first, second, base_files, bl31, toolchain)
    canonical = file_bytes(directory / "bird-uboot-no-heap-clear.bin")
    if canonical != first["u-boot-sunxi-with-spl.bin"]:
        fail("canonical no-heap-clear candidate differs from retained passes")
    if file_bytes(directory / "no-heap-clear.bin") != canonical:
        fail("installer no-heap-clear candidate differs from retained passes")
    if file_bytes(directory / "base-direct.bin") != base_files["combined"]:
        fail("installer direct base differs from retained base")
    shipping = file_bytes(directory / "shipping-baseline.bin")
    if sha256(shipping) != "42c01f4524b45cba7c239cd940fc4e71eed7545901da201f27fed2193b7fdf45":
        fail("retained shipping baseline changed")
    for filename, artifact in (
        ("no-heap-clear.itb", "u-boot.itb"),
        ("no-heap-clear-uboot.bin", "u-boot-nodtb.bin"),
        ("no-heap-clear-control.dtb", "u-boot.dtb"),
        ("no-heap-clear-spl.bin", "spl/sunxi-spl.bin"),
        ("no-heap-clear.config", "build.config"),
    ):
        if file_bytes(directory / filename) != first[artifact]:
            fail(f"canonical no-heap-clear component changed: {filename}")
    prefix = file_bytes(directory / "baseline-prefix-16m.bin")
    if len(prefix) != BASELINE_PREFIX_BYTES or sha256(prefix) != BASELINE_PREFIX_SHA256:
        fail("retained baseline prefix changed")
    full_prefix = bytearray(prefix)
    full_prefix[RAW_OFFSET:RAW_OFFSET + len(canonical)] = canonical
    identity = candidate_identity(first, bytes(full_prefix))
    verify_review_state(identity)
    for key, value in identity.items():
        if authority.get(key) != str(value):
            fail(f"candidate identity field changed: {key}")
    if file_bytes(directory / "two-pass-inventory.tsv") != build_inventory(
        {"no-clear-a": first, "no-clear-b": second}
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
        print(f"U-Boot no-heap-clear authority: VERIFIED ({state})")
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
