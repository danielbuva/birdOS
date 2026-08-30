#!/usr/bin/env python3
"""Verify and publish the fixed RG34XX-SP no-RAID6-benchmark boot pair."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE_DIR = ROOT / "kernel/work/bird-uboot-fixed-command-closure-20260829"
BASE_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-fixed-command-closure-build.py"
LZ4_VERIFIER = ROOT / "kernel/rocknix/verify-lz4-kernel-candidate.py"
SOURCE_AUTHORITY = (
    ROOT / "kernel/rocknix/source-kernel-irq-buttons-no-raid6-benchmark-lz4.tsv"
)
RAW_OFFSET = 8192
PREFIX_BYTES = 16 * 1024 * 1024
KERNEL_BYTES = 30_926_856
KERNEL_SHA256 = "b1d5eba80c2a9b07d4c99057fa9817403bd5de4e8f1dfc4cfcc5064443b6386e"
LZ4_BYTES = 17_565_344
LZ4_SHA256 = "2fb550062d3fbd69b433f0aa79d892b8b3a55ee048cf861874b90289a932d77a"
BASE_COMBINED_SHA256 = "918d9b8a0dd89ffb291a866eefa630c796ea7e3199ba92ce9664e6a72500161f"
BASE_PREFIX_SHA256 = "c156973946fd1f1fcb581eeb669abb638ce554cf16356db60428ba1ebb3a9c1b"
CANDIDATE_PREFIX_SHA256 = "c1a390a9c674029a21caf12eaec8d7b788dbe700b20cd7729276c9cf03214d32"
EXPECTED = {
    "combined": (411_977, "5352c2f635b1f741c8d1fcfb647e9ce2ea570311cbd8b476944d71338654f2f0"),
    "fit": (371_017, "5da14e0e4b59b517a443072cf2e0f159ac01b2fe4929a79f2677d0a390e37db9"),
    "uboot": (292_168, "c1bff84f48afc104cae6fe2aa972add5b4550adc0379cda37ffcad759fad3fce"),
    "config": (46_812, "c608c2590d96a094da00ff8cc89ada4fe11c1c10ea673bcb4346f0ab7bc0a2e1"),
    "spl": (40_960, "0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c"),
    "dtb": (35_784, "ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589"),
}
BUILD_FILES = {
    "combined": "u-boot-sunxi-with-spl.bin",
    "fit": "u-boot.itb",
    "uboot": "u-boot-nodtb.bin",
    "config": "build.config",
    "spl": "spl/sunxi-spl.bin",
    "dtb": "u-boot.dtb",
}
EXPECTED_COMBINED_DIFF = {
    284_511: (ord("8"), ord("6")),
    284_512: (ord("0"), ord("a")),
    284_513: (ord("b"), ord("0")),
}
PUBLISHED = {
    "authority.tsv",
    "no-raid6-benchmark-pair.bin",
    "no-raid6-benchmark-pair-prefix-16m.bin",
    "fixed-command-closure-base.bin",
    "fixed-command-closure-base-prefix-16m.bin",
    "KERNEL.lz4",
    "source-kernel-irq-buttons-no-raid6-benchmark-lz4.tsv",
    "build.config",
    "u-boot.bin",
    "spl.bin",
    "control.dtb",
    "sha256sums.txt",
}


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read(path: pathlib.Path) -> bytes:
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


def exact(data: bytes, size: int, digest: str, label: str) -> None:
    if len(data) != size or sha256(data) != digest:
        fail(f"{label} identity changed")


def load_build(directory: pathlib.Path) -> dict[str, bytes]:
    result = {name: read(directory / path) for name, path in BUILD_FILES.items()}
    for name, (size, digest) in EXPECTED.items():
        exact(result[name], size, digest, f"{directory.name} {name}")
    if result["combined"] != result["spl"] + result["fit"]:
        fail("combined U-Boot composition changed")
    return result


def verify_exact_successor(build: dict[str, bytes]) -> tuple[bytes, bytes]:
    base_verifier = load_module("bird_fixed_command_base", BASE_VERIFIER)
    base_verifier.verify_output(BASE_DIR)
    base = read(BASE_DIR / "fixed-command-closure.bin")
    base_prefix = read(BASE_DIR / "fixed-command-closure-prefix-16m.bin")
    if sha256(base) != BASE_COMBINED_SHA256 or sha256(base_prefix) != BASE_PREFIX_SHA256:
        fail("accepted fixed-command-closure predecessor changed")
    if build["config"] != read(BASE_DIR / "build.config"):
        fail("resolved U-Boot config changed")
    if build["spl"] != read(BASE_DIR / "spl.bin"):
        fail("accepted SPL changed")
    if build["dtb"] != read(BASE_DIR / "control.dtb"):
        fail("accepted control DTB changed")
    differences = {
        index: (before, after)
        for index, (before, after) in enumerate(zip(base, build["combined"]))
        if before != after
    }
    if len(base) != len(build["combined"]) or differences != EXPECTED_COMBINED_DIFF:
        fail(f"U-Boot successor changed outside the exact bound: {differences}")
    result = bytearray(base_prefix)
    if len(result) != PREFIX_BYTES or result[RAW_OFFSET:RAW_OFFSET + len(base)] != base:
        fail("accepted U-Boot prefix composition changed")
    result[RAW_OFFSET:RAW_OFFSET + len(build["combined"])] = build["combined"]
    if sha256(result) != CANDIDATE_PREFIX_SHA256:
        fail("candidate U-Boot prefix reconstruction changed")
    return base, bytes(result)


def verify_kernel_pair(kernel: bytes, frame: bytes, uboot: bytes) -> None:
    exact(kernel, KERNEL_BYTES, KERNEL_SHA256, "no-RAID6-benchmark Image")
    exact(frame, LZ4_BYTES, LZ4_SHA256, "no-RAID6-benchmark LZ4 frame")
    lz4 = load_module("bird_no_raid6_lz4", LZ4_VERIFIER)
    parsed = lz4.parse_lz4_frame(frame)
    if parsed.output != kernel or parsed.flags != 0x64 or parsed.block_descriptor != 0x70:
        fail("LZ4 frame contract or decoded Image changed")
    environment = lz4.parse_environment(uboot)
    if environment["kernel_comp_size"] != LZ4_BYTES:
        fail("U-Boot compressed-kernel bound is not exact")
    kernel_end = environment["kernel_addr_r"] + LZ4_BYTES
    output_end = environment["kernel_comp_addr_r"] + KERNEL_BYTES
    guard_end = environment["kernel_comp_addr_r"] + LZ4_BYTES * 10
    if not kernel_end < environment["kernel_comp_addr_r"]:
        fail("compressed kernel overlaps its output address")
    if not output_end < environment["fdt_addr_r"] or not guard_end < environment["fdt_addr_r"]:
        fail("kernel output or decompression guard overlaps the DTB")


def authority(prefix: bytes) -> bytes:
    rows = (
        ("schema", "bird-no-raid6-benchmark-boot-pair-v1"),
        ("review-state", "reviewed-host-candidate"),
        ("classification", "production-successor"),
        ("why-before", "generic-kernel-benchmarked-raid6-pq-for-variable-hardware"),
        ("why-change", "fixed-rg34xx-sp-selects-neonx8-after-about-510ms-of-boot-benchmarking"),
        ("predecessor", "accepted-fixed-command-closure"),
        ("predecessor-sha256", BASE_COMBINED_SHA256),
        ("predecessor-prefix-sha256", BASE_PREFIX_SHA256),
        ("candidate-sha256", EXPECTED["combined"][1]),
        ("candidate-prefix-sha256", sha256(prefix)),
        ("uboot-changed-byte-count", 3),
        ("uboot-change", "kernel_comp_size:0x10c080b-to-0x10c06a0-only"),
        ("resolved-config-byte-identical", "yes"),
        ("spl-byte-identical", "yes"),
        ("control-dtb-byte-identical", "yes"),
        ("kernel-sha256", KERNEL_SHA256),
        ("kernel-bytes", KERNEL_BYTES),
        ("lz4-sha256", LZ4_SHA256),
        ("lz4-bytes", LZ4_BYTES),
        ("producer-roundtrip", "exact"),
        ("kernel-comp-size", "0x10c06a0"),
        ("repeat-byte-identical", "yes"),
        ("card-write", "none"),
        ("hardware-result", "pending"),
    )
    return b"".join(f"{key}\t{value}\n".encode() for key, value in rows)


def publish(build: dict[str, bytes], frame: bytes, prefix: bytes, output: pathlib.Path) -> None:
    if output.exists() or output.is_symlink():
        fail(f"refusing to replace output: {output}")
    with tempfile.TemporaryDirectory(prefix=".bird-no-raid6-pair-", dir=output.parent) as temp:
        stage = pathlib.Path(temp) / "publication"
        stage.mkdir()
        files = {
            "authority.tsv": authority(prefix),
            "no-raid6-benchmark-pair.bin": build["combined"],
            "no-raid6-benchmark-pair-prefix-16m.bin": prefix,
            "fixed-command-closure-base.bin": read(BASE_DIR / "fixed-command-closure.bin"),
            "fixed-command-closure-base-prefix-16m.bin": read(BASE_DIR / "fixed-command-closure-prefix-16m.bin"),
            "KERNEL.lz4": frame,
            "source-kernel-irq-buttons-no-raid6-benchmark-lz4.tsv": read(SOURCE_AUTHORITY),
            "build.config": build["config"],
            "u-boot.bin": build["uboot"],
            "spl.bin": build["spl"],
            "control.dtb": build["dtb"],
        }
        for name, data in files.items():
            (stage / name).write_bytes(data)
        (stage / "sha256sums.txt").write_bytes(b"".join(
            f"{sha256(data)}  {name}\n".encode() for name, data in sorted(files.items())
        ))
        verify_output(stage)
        stage.rename(output)


def verify_output(directory: pathlib.Path) -> None:
    if directory.is_symlink() or not directory.is_dir():
        fail(f"unsafe or missing authority directory: {directory}")
    if {path.name for path in directory.iterdir()} != PUBLISHED:
        fail("boot-pair authority inventory changed")
    rows = read(directory / "sha256sums.txt").decode().splitlines()
    expected = PUBLISHED - {"sha256sums.txt"}
    found = set()
    for row in rows:
        fields = row.split("  ", 1)
        if len(fields) != 2 or fields[1] in found or fields[1] not in expected:
            fail("boot-pair checksum inventory is malformed")
        if len(fields[0]) != 64 or sha256(read(directory / fields[1])) != fields[0]:
            fail(f"boot-pair checksum mismatch: {fields[1]}")
        found.add(fields[1])
    if found != expected:
        fail("boot-pair checksum inventory is incomplete")
    build = {
        "combined": read(directory / "no-raid6-benchmark-pair.bin"),
        "fit": read(directory / "no-raid6-benchmark-pair.bin")[EXPECTED["spl"][0]:],
        "uboot": read(directory / "u-boot.bin"),
        "config": read(directory / "build.config"),
        "spl": read(directory / "spl.bin"),
        "dtb": read(directory / "control.dtb"),
    }
    for name, (size, digest) in EXPECTED.items():
        exact(build[name], size, digest, f"published {name}")
    _, prefix = verify_exact_successor(build)
    if read(directory / "no-raid6-benchmark-pair-prefix-16m.bin") != prefix:
        fail("published candidate prefix changed")
    if read(directory / "source-kernel-irq-buttons-no-raid6-benchmark-lz4.tsv") != read(SOURCE_AUTHORITY):
        fail("published source-kernel authority changed")
    verify_kernel_pair(
        read(ROOT / "kernel/work/rocknix-source-irq-buttons-no-raid6-benchmark-a/build/Image"),
        read(directory / "KERNEL.lz4"),
        build["uboot"],
    )
    if read(directory / "authority.tsv") != authority(prefix):
        fail("published boot-pair authority record changed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-a", type=pathlib.Path)
    parser.add_argument("--build-b", type=pathlib.Path)
    parser.add_argument("--kernel-a", type=pathlib.Path)
    parser.add_argument("--kernel-b", type=pathlib.Path)
    parser.add_argument("--lz4-a", type=pathlib.Path)
    parser.add_argument("--lz4-b", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--verify-output", type=pathlib.Path)
    args = parser.parse_args()
    if args.verify_output is not None:
        if any(getattr(args, name) is not None for name in ("build_a", "build_b", "kernel_a", "kernel_b", "lz4_a", "lz4_b", "output")):
            fail("verify-output cannot be combined with publication arguments")
        verify_output(args.verify_output)
        print("No-RAID6-benchmark boot pair: VERIFIED")
        return
    values = (args.build_a, args.build_b, args.kernel_a, args.kernel_b, args.lz4_a, args.lz4_b, args.output)
    if any(value is None for value in values):
        fail("both builds, kernels, LZ4 frames and output are required")
    first, second = load_build(args.build_a), load_build(args.build_b)
    if first != second:
        fail("isolated U-Boot builds are not byte-identical")
    kernel_a, kernel_b = read(args.kernel_a), read(args.kernel_b)
    frame_a, frame_b = read(args.lz4_a), read(args.lz4_b)
    if kernel_a != kernel_b or frame_a != frame_b:
        fail("isolated kernel or LZ4 outputs are not byte-identical")
    _, prefix = verify_exact_successor(first)
    verify_kernel_pair(kernel_a, frame_a, first["uboot"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    publish(first, frame_a, prefix, args.output)
    print("No-RAID6-benchmark boot pair: VERIFIED")


if __name__ == "__main__":
    main()
