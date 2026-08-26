#!/usr/bin/env python3
"""Verify the exact uninstrumented RG34XX-SP U-Boot/LZ4 pair.

Why before: the accepted raw Image needed no decompression bound, so the
in-place U-Boot retained U-Boot's generic 176 MiB limit.  Why change: the exact
17,565,707-byte LZ4 frame permits a byte-exact bound with a 19,378,066-byte
margin before the fixed DTB buffer.  This verifier has no media-write path.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import shutil
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE_DIR = ROOT / "kernel/work/bird-uboot-inplace-handoff-20260701"
KERNEL_DIR = ROOT / "kernel/work/bird-kernel-lz4-irq-candidate-20260813"
SOURCE_TAR = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/sources/u-boot-DDR4/"
    "u-boot-DDR4-v2026.01.tar.gz"
)
BASE_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-inplace-handoff-build.py"
LZ4_VERIFIER = ROOT / "kernel/rocknix/verify-lz4-kernel-candidate.py"

EXPECTED = {
    "combined": (556_977, "9f3d96da4126a6654187a3cddb9b0c038b251882aee9938e0b258d0bac94f35b"),
    "fit": (516_017, "b8ab71d063425db880b534beb612e70c2e8c3b2d136f7837b10e3ef5536bcde0"),
    "uboot": (437_168, "35cd4f8d50568f7bdae89fe01ce851b80276c4a44c18138de553872456523f9e"),
    "config": (47_408, "77f2bee66adc542e3475594c4727933607f76c2adf72e6428e0e57cadb6de762"),
    "spl": (40_960, "0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c"),
    "dtb": (35_784, "ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589"),
}
BASE_COMBINED_SHA = "7423ffeda197645b6b774c83fcebcbefef47bd7eaa6f087c71ab339750af4e91"
BASE_UBOOT_SHA = "cff9a9ca1bd7db20a3a136fec655d7120481afa8a837930266a9962ab2dec578"
BASE_PREFIX_SHA = "c168640be0e3b0fc3899853d71aabc0c3b3e65fdf230b19782ff40ff19f001dd"
PAIR_PREFIX_SHA = "2e6680950a885cef607a9642c0133a8794d7407c7879ccb0fe9c153b6be45f56"
RAW_OFFSET = 8192
PREFIX_BYTES = 16 * 1024 * 1024
OLD = b"kernel_comp_size=0xb000000\0"
NEW = b"kernel_comp_size=0x10c080b\0"
BUILD_FILES = {
    "combined": "combined.bin",
    "fit": "u-boot.itb",
    "uboot": "u-boot.bin",
    "config": "build.config",
    "spl": "spl.bin",
    "dtb": "control.dtb",
}
PUBLISHED_FILES = (
    "authority.tsv",
    "inplace-base.bin",
    "inplace-base-prefix-16m.bin",
    "lz4-pair.bin",
    "lz4-pair-prefix-16m.bin",
    "KERNEL.lz4",
    "source-kernel-irq-buttons-lz4.tsv",
    "sha256sums.txt",
)


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def regular_bytes(path: pathlib.Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail(f"unsafe or missing file: {path}")
    return path.read_bytes()


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        fail(f"could not load verifier: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def load_build(directory: pathlib.Path) -> dict[str, bytes]:
    build = {key: regular_bytes(directory / name) for key, name in BUILD_FILES.items()}
    for key, (size, digest) in EXPECTED.items():
        if len(build[key]) != size or sha256(build[key]) != digest:
            fail(f"{directory.name} {key} identity changed")
    return build


def verify_manifest(directory: pathlib.Path) -> None:
    rows = regular_bytes(directory / "sha256sums.txt").decode().splitlines()
    expected_names = {
        f"{build}/{name}" for build in ("a", "b") for name in BUILD_FILES.values()
    } | {"authority.tsv"}
    found: set[str] = set()
    for row in rows:
        fields = row.split("  ", 1)
        if len(fields) != 2 or fields[1] in found:
            fail("LZ4 pair checksum inventory is malformed")
        digest, name = fields
        if name not in expected_names or len(digest) != 64:
            fail("LZ4 pair checksum inventory changed")
        if sha256(regular_bytes(directory / name)) != digest:
            fail(f"LZ4 pair checksum mismatch: {name}")
        found.add(name)
    if found != expected_names:
        fail("LZ4 pair checksum inventory is incomplete")


def reconstruct_prefix(base_combined: bytes, pair: bytes, baseline_prefix: bytes) -> bytes:
    if len(baseline_prefix) != PREFIX_BYTES:
        fail("baseline prefix size changed")
    accepted = bytearray(baseline_prefix)
    accepted[RAW_OFFSET:RAW_OFFSET + len(base_combined)] = base_combined
    if sha256(accepted) != BASE_PREFIX_SHA:
        fail("accepted in-place prefix reconstruction changed")
    result = bytearray(accepted)
    result[RAW_OFFSET:RAW_OFFSET + len(pair)] = pair
    if sha256(result) != PAIR_PREFIX_SHA:
        fail("LZ4 pair prefix reconstruction changed")
    if result[:RAW_OFFSET] != accepted[:RAW_OFFSET]:
        fail("LZ4 pair changed bytes before the raw U-Boot range")
    end = RAW_OFFSET + len(pair)
    if result[end:] != accepted[end:]:
        fail("LZ4 pair changed bytes after the raw U-Boot range")
    return bytes(result)


def verify(directory: pathlib.Path) -> None:
    verify_manifest(directory)
    authority = regular_bytes(directory / "authority.tsv")
    required_rows = (
        b"schema\tbird-uboot-lz4-pair-diagnostic-v1\n",
        b"review-state\tdiagnostic-linked-a-b\n",
        b"deployment-authority\tno-diagnostic-only\n",
        b"kernel-comp-size\t0x10c080b\n",
        b"repeat-byte-identical\tyes\n",
    )
    for row in required_rows:
        if authority.count(row) != 1:
            fail(f"LZ4 pair authority row changed: {row!r}")

    base = load_module("bird_inplace_pair_base", BASE_VERIFIER)
    lz4 = load_module("bird_lz4_pair_consumer", LZ4_VERIFIER)
    base.verify_output(BASE_DIR)
    first = load_build(directory / "a")
    second = load_build(directory / "b")
    if first != second:
        fail("isolated LZ4-paired U-Boot builds are not byte-identical")

    base_combined = regular_bytes(BASE_DIR / "bird-uboot-inplace-handoff.bin")
    base_fit = regular_bytes(BASE_DIR / "inplace-handoff.itb")
    base_uboot = regular_bytes(BASE_DIR / "inplace-handoff-uboot.bin")
    if sha256(base_combined) != BASE_COMBINED_SHA or sha256(base_uboot) != BASE_UBOOT_SHA:
        fail("reviewed in-place predecessor identity changed")
    if first["config"] != regular_bytes(BASE_DIR / "inplace-handoff.config"):
        fail("LZ4 pair changed the resolved U-Boot config")
    if first["spl"] != regular_bytes(BASE_DIR / "inplace-handoff-spl.bin"):
        fail("LZ4 pair changed the accepted SPL")
    if first["dtb"] != regular_bytes(BASE_DIR / "inplace-handoff-control.dtb"):
        fail("LZ4 pair changed the control DTB")
    if first["combined"] != first["spl"] + first["fit"]:
        fail("LZ4 pair combined image composition changed")
    base.verify_fit_scope(base_fit, first["fit"])
    if len(OLD) != len(NEW) or base_uboot.count(OLD) != 1 or NEW in base_uboot:
        fail("accepted decompression-bound authority is ambiguous")
    if first["uboot"] != base_uboot.replace(OLD, NEW):
        fail("LZ4-paired U-Boot differs outside the exact bound")

    lz4.verify(
        ROOT / "kernel/work/rocknix-source-irq-buttons/build/Image",
        KERNEL_DIR / "KERNEL.lz4",
        SOURCE_TAR,
        BASE_DIR / "inplace-handoff.config",
        directory / "a/u-boot.bin",
    )
    reconstruct_prefix(
        base_combined,
        first["combined"],
        regular_bytes(BASE_DIR / "base-fast-init-prefix-16m.bin"),
    )


def publication_authority(diagnostic_sha: str) -> bytes:
    rows = (
        ("schema", "bird-uboot-lz4-pair-authority-v1"),
        ("review-state", "reviewed"),
        ("classification", "production-successor"),
        ("why-before", "raw-kernel-needs-no-decompression-bound"),
        ("why-change", "exact-lz4-frame-permits-bounded-decompression"),
        ("predecessor", "accepted-inplace-handoff"),
        ("predecessor-sha256", BASE_COMBINED_SHA),
        ("predecessor-prefix-sha256", BASE_PREFIX_SHA),
        ("candidate-bytes", EXPECTED["combined"][0]),
        ("candidate-sha256", EXPECTED["combined"][1]),
        ("candidate-uboot-sha256", EXPECTED["uboot"][1]),
        ("candidate-config-sha256", EXPECTED["config"][1]),
        ("candidate-prefix-sha256", PAIR_PREFIX_SHA),
        ("lz4-kernel-bytes", 17_565_707),
        ("lz4-kernel-sha256", "a7321d2a79b18e81f114aefd9bb7509ba70d5e56b562a345ea5ca66dbf11262a"),
        ("kernel-comp-size", "0x10c080b"),
        ("guard-to-fdt-margin-bytes", 19_378_066),
        ("uboot-difference-bytes", 4),
        ("uboot-difference-scope", "kernel_comp_size-default-environment-only"),
        ("fit-difference-scope", "images-uboot-data-only"),
        ("spl-byte-identical", "yes"),
        ("config-byte-identical", "yes"),
        ("control-dtb-byte-identical", "yes"),
        ("repeat-byte-identical", "yes"),
        ("diagnostic-authority-sha256", diagnostic_sha),
        ("card-write", "none"),
    )
    return b"".join(f"{key}\t{value}\n".encode() for key, value in rows)


def inplace_prefix() -> bytes:
    base = regular_bytes(BASE_DIR / "bird-uboot-inplace-handoff.bin")
    prefix = bytearray(regular_bytes(BASE_DIR / "base-fast-init-prefix-16m.bin"))
    if len(prefix) != PREFIX_BYTES:
        fail("in-place predecessor prefix size changed")
    prefix[RAW_OFFSET:RAW_OFFSET + len(base)] = base
    if sha256(prefix) != BASE_PREFIX_SHA:
        fail("in-place predecessor prefix reconstruction changed")
    return bytes(prefix)


def write_checksums(directory: pathlib.Path) -> None:
    names = [name for name in PUBLISHED_FILES if name != "sha256sums.txt"]
    names.append("diagnostic/sha256sums.txt")
    names.append("diagnostic/authority.tsv")
    for build in ("a", "b"):
        names.extend(f"diagnostic/{build}/{name}" for name in BUILD_FILES.values())
    data = b"".join(
        f"{sha256(regular_bytes(directory / name))}  {name}\n".encode()
        for name in names
    )
    (directory / "sha256sums.txt").write_bytes(data)


def publish(diagnostic: pathlib.Path, output: pathlib.Path) -> None:
    verify(diagnostic)
    if output.exists() or output.is_symlink():
        fail(f"refusing to replace publication: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bird-lz4-pair-", dir=output.parent) as temp:
        stage = pathlib.Path(temp) / "publication"
        stage.mkdir()
        shutil.copytree(diagnostic, stage / "diagnostic")
        base = regular_bytes(BASE_DIR / "bird-uboot-inplace-handoff.bin")
        pair = regular_bytes(diagnostic / "a/combined.bin")
        prefix = inplace_prefix()
        pair_prefix = reconstruct_prefix(base, pair, prefix)
        files = {
            "authority.tsv": publication_authority(
                sha256(regular_bytes(diagnostic / "authority.tsv"))
            ),
            "inplace-base.bin": base,
            "inplace-base-prefix-16m.bin": prefix,
            "lz4-pair.bin": pair,
            "lz4-pair-prefix-16m.bin": pair_prefix,
            "KERNEL.lz4": regular_bytes(KERNEL_DIR / "KERNEL.lz4"),
            "source-kernel-irq-buttons-lz4.tsv": regular_bytes(
                ROOT / "kernel/rocknix/source-kernel-irq-buttons-lz4.tsv"
            ),
        }
        for name, data in files.items():
            (stage / name).write_bytes(data)
        write_checksums(stage)
        verify_output(stage)
        stage.rename(output)


def verify_output(directory: pathlib.Path) -> None:
    names = set(PUBLISHED_FILES) | {"diagnostic"}
    if {path.name for path in directory.iterdir()} != names:
        fail("published LZ4 pair file inventory changed")
    manifest = regular_bytes(directory / "sha256sums.txt").decode().splitlines()
    for row in manifest:
        digest, name = row.split("  ", 1)
        if sha256(regular_bytes(directory / name)) != digest:
            fail(f"published LZ4 pair checksum mismatch: {name}")
    verify(directory / "diagnostic")
    diagnostic_sha = sha256(regular_bytes(directory / "diagnostic/authority.tsv"))
    if regular_bytes(directory / "authority.tsv") != publication_authority(diagnostic_sha):
        fail("published LZ4 pair authority changed")
    base = regular_bytes(directory / "inplace-base.bin")
    if sha256(base) != BASE_COMBINED_SHA:
        fail("published LZ4 pair predecessor changed")
    prefix = regular_bytes(directory / "inplace-base-prefix-16m.bin")
    if sha256(prefix) != BASE_PREFIX_SHA:
        fail("published LZ4 pair predecessor prefix changed")
    pair = regular_bytes(directory / "lz4-pair.bin")
    if len(pair) != EXPECTED["combined"][0] or sha256(pair) != EXPECTED["combined"][1]:
        fail("published LZ4 pair candidate changed")
    expected_prefix = reconstruct_prefix(base, pair, prefix)
    if regular_bytes(directory / "lz4-pair-prefix-16m.bin") != expected_prefix:
        fail("published LZ4 pair target prefix changed")
    if sha256(regular_bytes(directory / "KERNEL.lz4")) != (
        "a7321d2a79b18e81f114aefd9bb7509ba70d5e56b562a345ea5ca66dbf11262a"
    ):
        fail("published LZ4 kernel changed")
    source_authority = regular_bytes(directory / "source-kernel-irq-buttons-lz4.tsv")
    if sha256(source_authority) != (
        "250be0f922339e423cc7e100d785747b16686873a5bea357b69825dc29434b3c"
    ):
        fail("published LZ4 source-kernel authority changed")


def main() -> None:
    parser = argparse.ArgumentParser()
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--verify-input", type=pathlib.Path)
    actions.add_argument("--verify-output", type=pathlib.Path)
    actions.add_argument("--publish", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    if args.verify_input is not None:
        if args.output is not None:
            fail("--output is valid only with --publish")
        verify(args.verify_input)
        print("U-Boot uninstrumented LZ4 pair authority: VERIFIED (two-pass diagnostic)")
    elif args.verify_output is not None:
        if args.output is not None:
            fail("--output is valid only with --publish")
        verify_output(args.verify_output)
        print("U-Boot uninstrumented LZ4 pair authority: VERIFIED (reviewed)")
    else:
        if args.output is None:
            fail("--publish requires --output")
        publish(args.publish, args.output)
        print(f"Published reviewed U-Boot LZ4 pair authority: {args.output}")


if __name__ == "__main__":
    main()
