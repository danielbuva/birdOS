#!/usr/bin/env python3
"""Verify the complete host authority consumed by the raw U-Boot installer."""

from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import re
import stat
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
BUILD_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-status-led-build.py"

# These identities were promoted only after two isolated baseline builds were
# byte-identical to shipping, two isolated green builds were byte-identical to
# each other, and the retained four-pass evidence received independent review.
REVIEWED_CANDIDATE_SHA256 = (
    "080ae5fde3476addb5aa74f03a021aa4fbaa5deccb0964227c0fc91fe657b584"
)
REVIEWED_CANDIDATE_UBOOT_SHA256 = (
    "c60605e6a533404d5eb66549e4905152c42ff937de8cc922a1b8b8b7eac3ff56"
)
REVIEWED_DIFFERENCE = {
    "changed-bytes": "1",
    "changed-runs": "1",
    "first-changed-offset": "488836",
    "last-changed-offset": "488836",
}

EXPECTED_FILES = (
    "authority.tsv",
    "baseline-a-combined.bin",
    "baseline-a.config",
    "baseline-b-combined.bin",
    "baseline-b.config",
    "baseline-control.dtb",
    "baseline-uboot.bin",
    "baseline.itb",
    "bird-uboot-green.bin",
    "bl31.bin",
    "four-pass-inventory.tsv",
    "green-a-combined.bin",
    "green-a.config",
    "green-b-combined.bin",
    "green-b.config",
    "green-control.dtb",
    "green-uboot.bin",
    "green.itb",
    "sha256sums.txt",
    "rocknix-baseline.bin",
    "spl.bin",
    "toolchain-authority.tsv",
)
SUMMED_FILES = tuple(name for name in EXPECTED_FILES if name != "sha256sums.txt")

FIELD_ORDER = (
    "schema",
    "rocknix-release",
    "rocknix-commit",
    "uboot-version",
    "package-path",
    "gcc-package-path",
    "defconfig",
    "source-tarball-sha256",
    "package-mk-sha256",
    "package-patch-sha256",
    "gcc-package-sha256",
    "gcc-source-sha256",
    "upstream-defconfig-sha256",
    "green-defconfig-sha256",
    "docker-image",
    "source-date-epoch",
    "fit-date-epoch",
    "raw-offset",
    "spl-region-bytes",
    "fit-bytes",
    "bl31-bytes",
    "bl31-sha256",
    "baseline-bytes",
    "baseline-sha256",
    "candidate-bytes",
    "candidate-sha256",
    "spl-sha256",
    "control-fdt-sha256",
    "baseline-uboot-sha256",
    "candidate-uboot-sha256",
    "changed-bytes",
    "changed-runs",
    "first-changed-offset",
    "last-changed-offset",
    "baseline-repeat-byte-identical",
    "candidate-repeat-byte-identical",
    "shipping-baseline-byte-identical",
    "spl-byte-identical",
    "bl31-byte-identical",
    "control-fdt-byte-identical",
    "uboot-lto",
    "build-config-only-status-gpio-diff",
)

PARITY_FIELDS = (
    "baseline-repeat-byte-identical",
    "candidate-repeat-byte-identical",
    "shipping-baseline-byte-identical",
    "spl-byte-identical",
    "bl31-byte-identical",
    "control-fdt-byte-identical",
)

RETAINED_FOUR_PASS_FILES = {
    ("baseline-a", "u-boot-sunxi-with-spl.bin"): "baseline-a-combined.bin",
    ("baseline-b", "u-boot-sunxi-with-spl.bin"): "baseline-b-combined.bin",
    ("green-a", "u-boot-sunxi-with-spl.bin"): "green-a-combined.bin",
    ("green-b", "u-boot-sunxi-with-spl.bin"): "green-b-combined.bin",
    ("baseline-a", "build.config"): "baseline-a.config",
    ("baseline-b", "build.config"): "baseline-b.config",
    ("green-a", "build.config"): "green-a.config",
    ("green-b", "build.config"): "green-b.config",
}

A_CANONICAL_FILES = {
    ("baseline-a", "u-boot-sunxi-with-spl.bin"): "rocknix-baseline.bin",
    ("baseline-a", "u-boot.itb"): "baseline.itb",
    ("baseline-a", "u-boot-nodtb.bin"): "baseline-uboot.bin",
    ("baseline-a", "u-boot.dtb"): "baseline-control.dtb",
    ("baseline-a", "spl/sunxi-spl.bin"): "spl.bin",
    ("baseline-a", "build.config"): "baseline-a.config",
    ("green-a", "u-boot-sunxi-with-spl.bin"): "bird-uboot-green.bin",
    ("green-a", "u-boot.itb"): "green.itb",
    ("green-a", "u-boot-nodtb.bin"): "green-uboot.bin",
    ("green-a", "u-boot.dtb"): "green-control.dtb",
    ("green-a", "spl/sunxi-spl.bin"): "spl.bin",
    ("green-a", "build.config"): "green-a.config",
}


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_regular(path: pathlib.Path) -> bytes:
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        fail(f"unsafe or missing U-Boot authority artifact: {path.name}")
    return path.read_bytes()


def load_build_verifier():
    spec = importlib.util.spec_from_file_location("bird_uboot_build", BUILD_VERIFIER)
    if spec is None or spec.loader is None:
        fail("could not load the U-Boot build verifier")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_authority(path: pathlib.Path) -> dict[str, str]:
    raw = read_regular(path)
    if not raw.endswith(b"\n") or b"\r" in raw or b"\0" in raw:
        fail("U-Boot authority is not canonical TSV")
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeDecodeError:
        fail("U-Boot authority is not UTF-8")
    if len(lines) != len(FIELD_ORDER):
        fail("U-Boot authority field count changed")
    rows: list[tuple[str, str]] = []
    for line in lines:
        fields = line.split("\t")
        if len(fields) != 2 or not fields[1]:
            fail("U-Boot authority contains a malformed field")
        rows.append((fields[0], fields[1]))
    if tuple(key for key, _value in rows) != FIELD_ORDER:
        fail("U-Boot authority has unknown, duplicate, or reordered fields")
    return dict(rows)


def require_values(
    values: dict[str, str], verifier, allow_unreviewed_test_candidate: bool
) -> None:
    expected = {
        "schema": verifier.SCHEMA,
        "rocknix-release": verifier.ROCKNIX_RELEASE,
        "rocknix-commit": verifier.ROCKNIX_COMMIT,
        "uboot-version": verifier.UBOOT_VERSION,
        "package-path": verifier.PACKAGE_PATH,
        "gcc-package-path": verifier.GCC_PACKAGE_PATH,
        "defconfig": verifier.DEFCONFIG_NAME,
        "source-tarball-sha256": verifier.SOURCE_TARBALL_SHA256,
        "package-mk-sha256": verifier.PACKAGE_MK_SHA256,
        "package-patch-sha256": verifier.PACKAGE_PATCH_SHA256,
        "gcc-package-sha256": verifier.GCC_PACKAGE_SHA256,
        "gcc-source-sha256": verifier.GCC_SOURCE_SHA256,
        "upstream-defconfig-sha256": verifier.UPSTREAM_DEFCONFIG_SHA256,
        "green-defconfig-sha256": verifier.GREEN_DEFCONFIG_SHA256,
        "docker-image": verifier.DOCKER_IMAGE,
        "source-date-epoch": str(verifier.SOURCE_DATE_EPOCH),
        "fit-date-epoch": str(verifier.FIT_DATE_EPOCH),
        "raw-offset": str(verifier.RAW_OFFSET),
        "spl-region-bytes": str(verifier.SPL_REGION_BYTES),
        "fit-bytes": str(verifier.FIT_BYTES),
        "bl31-bytes": str(verifier.BL31_BYTES),
        "bl31-sha256": verifier.BL31_SHA256,
        "baseline-bytes": str(verifier.COMBINED_BYTES),
        "baseline-sha256": verifier.SHIPPING_COMBINED_SHA256,
        "candidate-bytes": str(verifier.COMBINED_BYTES),
        "uboot-lto": "disabled",
        "build-config-only-status-gpio-diff": "yes",
    }
    for key, value in expected.items():
        if values[key] != value:
            fail(f"U-Boot authority field changed: {key}")
    for key in (
        "candidate-sha256",
        "spl-sha256",
        "control-fdt-sha256",
        "baseline-uboot-sha256",
        "candidate-uboot-sha256",
    ):
        if not re.fullmatch(r"[0-9a-f]{64}", values[key]):
            fail(f"U-Boot authority digest is malformed: {key}")
    for key in PARITY_FIELDS:
        if values[key] != "yes":
            fail(f"U-Boot parity prerequisite is not satisfied: {key}")
    if not allow_unreviewed_test_candidate:
        if (
            REVIEWED_CANDIDATE_SHA256 == "pending"
            or REVIEWED_CANDIDATE_UBOOT_SHA256 == "pending"
            or "pending" in REVIEWED_DIFFERENCE.values()
        ):
            fail("reviewed green U-Boot result identity has not been promoted")
        if values["candidate-sha256"] != REVIEWED_CANDIDATE_SHA256:
            fail("green U-Boot candidate is not the reviewed result")
        if values["candidate-uboot-sha256"] != REVIEWED_CANDIDATE_UBOOT_SHA256:
            fail("green U-Boot proper is not the reviewed result")
        for key, expected in REVIEWED_DIFFERENCE.items():
            if values[key] != expected:
                fail(f"green U-Boot difference is not reviewed: {key}")


def verify_sums(root: pathlib.Path) -> dict[str, bytes]:
    actual_names = tuple(sorted(path.name for path in root.iterdir()))
    if actual_names != tuple(sorted(EXPECTED_FILES)):
        fail("U-Boot authority artifact inventory changed")
    artifacts = {name: read_regular(root / name) for name in EXPECTED_FILES}
    try:
        lines = artifacts["sha256sums.txt"].decode("ascii").splitlines()
    except UnicodeDecodeError:
        fail("U-Boot checksum list is not ASCII")
    # The publisher lists the fixed binary inventory first, then appends the
    # authority after it has been written. Preserve that exact canonical order.
    expected_lines = [
        f"{sha256(artifacts[name])}  {name}"
        for name in sorted(name for name in SUMMED_FILES if name != "authority.tsv")
    ]
    expected_lines.append(
        f"{sha256(artifacts['authority.tsv'])}  authority.tsv"
    )
    if lines != expected_lines or not artifacts["sha256sums.txt"].endswith(b"\n"):
        fail("U-Boot checksum list is incomplete, reordered, or mismatched")
    return artifacts


def verify_four_pass_inventory(artifacts: dict[str, bytes], verifier) -> None:
    """Recheck retained outputs and every fixed per-pass build digest."""

    raw = artifacts["four-pass-inventory.tsv"]
    if not raw.endswith(b"\n") or b"\r" in raw or b"\0" in raw:
        fail("U-Boot four-pass inventory is not canonical TSV")
    try:
        lines = raw.decode("ascii").splitlines()
    except UnicodeDecodeError:
        fail("U-Boot four-pass inventory is not ASCII")
    if not lines or lines[0] != f"schema\t{verifier.FOUR_PASS_SCHEMA}":
        fail("U-Boot four-pass inventory schema changed")

    expected_keys = [
        (build_name, artifact_name)
        for build_name in verifier.BUILD_NAMES
        for artifact_name in verifier.REQUIRED_ARTIFACTS
    ]
    if len(lines) != 1 + len(expected_keys):
        fail("U-Boot four-pass inventory field count changed")
    inventory: dict[tuple[str, str], tuple[int, str]] = {}
    for line, expected_key in zip(lines[1:], expected_keys):
        fields = line.split("\t")
        if len(fields) != 5 or fields[:3] != ["artifact", *expected_key]:
            fail("U-Boot four-pass inventory is unknown, duplicate, or reordered")
        size_text, digest = fields[3:]
        if (
            not size_text.isascii()
            or not size_text.isdigit()
            or str(int(size_text)) != size_text
            or int(size_text) <= 0
            or not re.fullmatch(r"[0-9a-f]{64}", digest)
        ):
            fail("U-Boot four-pass inventory value is malformed")
        inventory[expected_key] = (int(size_text), digest)

    def require_file(key: tuple[str, str], file_name: str) -> None:
        data = artifacts[file_name]
        expected_size, expected_digest = inventory[key]
        if len(data) != expected_size or sha256(data) != expected_digest:
            fail(f"U-Boot four-pass retained artifact differs from inventory: {file_name}")

    for key, file_name in RETAINED_FOUR_PASS_FILES.items():
        require_file(key, file_name)
    for key, file_name in A_CANONICAL_FILES.items():
        require_file(key, file_name)

    for flavor in ("baseline", "green"):
        for artifact_name in verifier.REQUIRED_ARTIFACTS:
            if inventory[(f"{flavor}-a", artifact_name)] != inventory[
                (f"{flavor}-b", artifact_name)
            ]:
                fail(f"U-Boot {flavor} per-pass inventory is not reproducible")

    if artifacts["baseline-a-combined.bin"] != artifacts["baseline-b-combined.bin"]:
        fail("retained baseline combined builds are not byte-identical")
    if artifacts["green-a-combined.bin"] != artifacts["green-b-combined.bin"]:
        fail("retained green combined builds are not byte-identical")
    if artifacts["baseline-a-combined.bin"] != artifacts["rocknix-baseline.bin"]:
        fail("retained baseline build differs from the shipping oracle")
    if artifacts["green-a-combined.bin"] != artifacts["bird-uboot-green.bin"]:
        fail("retained green build differs from the install candidate")
    if artifacts["baseline-a.config"] != artifacts["baseline-b.config"]:
        fail("retained baseline configs are not byte-identical")
    if artifacts["green-a.config"] != artifacts["green-b.config"]:
        fail("retained green configs are not byte-identical")
    verifier.verify_build_configs(
        artifacts["baseline-a.config"], artifacts["green-a.config"]
    )


def verify(root: pathlib.Path, allow_unreviewed_test_candidate: bool = False) -> None:
    root_mode = root.lstat().st_mode
    if stat.S_ISLNK(root_mode) or not stat.S_ISDIR(root_mode):
        fail("U-Boot build authority directory is missing or unsafe")

    verifier = load_build_verifier()
    artifacts = verify_sums(root)
    values = parse_authority(root / "authority.tsv")
    require_values(values, verifier, allow_unreviewed_test_candidate)
    verifier.verify_toolchain_authority(artifacts["toolchain-authority.tsv"])
    verify_four_pass_inventory(artifacts, verifier)

    baseline = artifacts["rocknix-baseline.bin"]
    candidate = artifacts["bird-uboot-green.bin"]
    spl = artifacts["spl.bin"]
    bl31 = artifacts["bl31.bin"]
    baseline_control = artifacts["baseline-control.dtb"]
    green_control = artifacts["green-control.dtb"]
    baseline_uboot = artifacts["baseline-uboot.bin"]
    green_uboot = artifacts["green-uboot.bin"]

    if sha256(baseline) != values["baseline-sha256"]:
        fail("shipping U-Boot baseline digest changed")
    if sha256(candidate) != values["candidate-sha256"]:
        fail("green U-Boot candidate digest changed")
    if sha256(spl) != values["spl-sha256"]:
        fail("U-Boot SPL digest changed")
    if sha256(bl31) != values["bl31-sha256"]:
        fail("U-Boot BL31 digest changed")
    if baseline_control != green_control or sha256(baseline_control) != values[
        "control-fdt-sha256"
    ]:
        fail("U-Boot control FDT parity changed")
    if sha256(baseline_uboot) != values["baseline-uboot-sha256"]:
        fail("rebuilt baseline U-Boot digest changed")
    if sha256(green_uboot) != values["candidate-uboot-sha256"]:
        fail("green U-Boot proper digest changed")

    verifier.verify_combined(baseline, spl, artifacts["baseline.itb"])
    verifier.verify_combined(candidate, spl, artifacts["green.itb"])
    verifier.verify_fit(
        artifacts["baseline.itb"], baseline_uboot, bl31, baseline_control
    )
    verifier.verify_fit(artifacts["green.itb"], green_uboot, bl31, green_control)
    verifier.verify_green_scope(
        {"u-boot-nodtb.bin": baseline_uboot, "u-boot.itb": artifacts["baseline.itb"]},
        {"u-boot-nodtb.bin": green_uboot, "u-boot.itb": artifacts["green.itb"]},
    )
    if baseline[: verifier.SPL_REGION_BYTES] != candidate[: verifier.SPL_REGION_BYTES]:
        fail("green U-Boot candidate changed the SPL region")

    summary = verifier.difference_summary(baseline, candidate)
    for key, value in summary.items():
        if values[key] != str(value):
            fail(f"U-Boot candidate difference authority changed: {key}")


def main() -> int:
    allow_unreviewed_test_candidate = False
    arguments = sys.argv[1:]
    if arguments[:1] == ["--allow-unreviewed-test-candidate"]:
        allow_unreviewed_test_candidate = True
        arguments = arguments[1:]
    if len(arguments) != 1:
        print(
            f"usage: {sys.argv[0]} [--allow-unreviewed-test-candidate] "
            "UBOOT_BUILD_DIRECTORY",
            file=sys.stderr,
        )
        return 2
    if allow_unreviewed_test_candidate and os.environ.get(
        "BIRD_UBOOT_AUTHORITY_HOST_TEST"
    ) != "1":
        print("error: unreviewed U-Boot authority requires host-test mode", file=sys.stderr)
        return 1
    try:
        verify(
            pathlib.Path(arguments[0]),
            allow_unreviewed_test_candidate=allow_unreviewed_test_candidate,
        )
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print("U-Boot install authority: VERIFIED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
