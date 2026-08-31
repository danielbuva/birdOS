#!/usr/bin/env python3
"""Verify and publish the fixed RG34XX-SP deferred-Wi-Fi boot pair."""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE_VERIFIER = ROOT / "kernel/rocknix/verify-no-raid6-benchmark-pair-build.py"
SOURCE_AUTHORITY = (
    ROOT
    / "kernel/rocknix/source-kernel-irq-buttons-no-raid6-deferred-wifi-lz4.tsv"
)
KERNEL_A = ROOT / "kernel/work/rocknix-source-deferred-wifi-a/build/Image"
STAGE11_DIR = ROOT / "kernel/work/bird-no-raid6-benchmark-pair-20260830"
STAGE11_COMBINED_SHA256 = "5352c2f635b1f741c8d1fcfb647e9ce2ea570311cbd8b476944d71338654f2f0"
STAGE11_PREFIX_SHA256 = "c1a390a9c674029a21caf12eaec8d7b788dbe700b20cd7729276c9cf03214d32"
RAW_OFFSET = 8192
PREFIX_BYTES = 16 * 1024 * 1024
KERNEL_BYTES = 30_926_856
KERNEL_SHA256 = "efc9de3ca0ee03191f2df48ed87467f2a295537dd5ef09cf2932500b0a46f8e4"
LZ4_BYTES = 17_565_074
LZ4_SHA256 = "05f3b40c4d1c2b4255745b9814052b9e1d091f22f9bd1499a5841b41b24771bc"
CANDIDATE_PREFIX_SHA256 = "b1a27dda2742c8982be848aef35db1f8e340c0feb24aaeeca94028d10b02ae2d"
EXPECTED = {
    "combined": (411_977, "d0a9fcab2c7908c44febe1d387d99dc1916ff0d6b6dcb4a398c7df77a9a7a3e8"),
    "fit": (371_017, "54e0a0f0a42ce1641e4e7d062022972f823c295c4490536e66e172fda57fabff"),
    "uboot": (292_168, "a880618d10443eccdc6cb39b4758f32960b97ab19df5da5bca4b63691ce4dbcb"),
    "config": (46_812, "c608c2590d96a094da00ff8cc89ada4fe11c1c10ea673bcb4346f0ab7bc0a2e1"),
    "spl": (40_960, "0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c"),
    "dtb": (35_784, "ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589"),
}
EXPECTED_COMBINED_DIFF = {
    284_511: (ord("8"), ord("5")),
    284_512: (ord("0"), ord("9")),
    284_513: (ord("b"), ord("2")),
}
EXPECTED_STAGE11_DIFF = {
    284_511: (ord("6"), ord("5")),
    284_512: (ord("a"), ord("9")),
    284_513: (ord("0"), ord("2")),
}
PUBLISHED = {
    "authority.tsv",
    "deferred-wifi-pair.bin",
    "deferred-wifi-pair-prefix-16m.bin",
    "fixed-command-closure-base.bin",
    "fixed-command-closure-base-prefix-16m.bin",
    "stage11-no-raid6-benchmark.bin",
    "stage11-no-raid6-benchmark-prefix-16m.bin",
    "KERNEL.lz4",
    "source-kernel-irq-buttons-no-raid6-deferred-wifi-lz4.tsv",
    "build.config",
    "u-boot.bin",
    "spl.bin",
    "control.dtb",
    "sha256sums.txt",
}


def load_base():
    spec = importlib.util.spec_from_file_location("bird_pair_base", BASE_VERIFIER)
    if spec is None or spec.loader is None:
        raise SystemExit("error: could not load boot-pair base verifier")
    module = importlib.util.module_from_spec(spec)
    sys.modules["bird_pair_base"] = module
    spec.loader.exec_module(module)
    module.SOURCE_AUTHORITY = SOURCE_AUTHORITY
    module.KERNEL_BYTES = KERNEL_BYTES
    module.KERNEL_SHA256 = KERNEL_SHA256
    module.LZ4_BYTES = LZ4_BYTES
    module.LZ4_SHA256 = LZ4_SHA256
    module.CANDIDATE_PREFIX_SHA256 = CANDIDATE_PREFIX_SHA256
    module.EXPECTED = EXPECTED
    module.EXPECTED_COMBINED_DIFF = EXPECTED_COMBINED_DIFF
    return module


BASE = load_base()


def authority(prefix: bytes) -> bytes:
    rows = (
        ("schema", "bird-deferred-wifi-boot-pair-v1"),
        ("review-state", "reviewed-host-candidate"),
        ("classification", "production-successor"),
        ("why-before", "mmc-prescan-synchronously-powered-fixed-wifi-sdio"),
        ("why-change", "move-retained-200ms-power-sequence-to-queued-mmc-rescan"),
        ("predecessor", "accepted-stage11-no-raid6-benchmark-pair"),
        ("predecessor-sha256", STAGE11_COMBINED_SHA256),
        ("predecessor-prefix-sha256", STAGE11_PREFIX_SHA256),
        ("candidate-sha256", EXPECTED["combined"][1]),
        ("candidate-prefix-sha256", BASE.sha256(prefix)),
        ("uboot-changed-byte-count", "3"),
        ("uboot-change", "kernel_comp_size:0x10c06a0-to-0x10c0592-only"),
        ("resolved-config-byte-identical", "yes"),
        ("spl-byte-identical", "yes"),
        ("control-dtb-byte-identical", "yes"),
        ("kernel-sha256", KERNEL_SHA256),
        ("kernel-bytes", str(KERNEL_BYTES)),
        ("lz4-sha256", LZ4_SHA256),
        ("lz4-bytes", str(LZ4_BYTES)),
        ("producer-roundtrip", "exact"),
        ("kernel-comp-size", "0x10c0592"),
        ("repeat-byte-identical", "yes"),
        ("card-write", "none"),
        ("hardware-result", "pending"),
    )
    return b"".join(f"{key}\t{value}\n".encode() for key, value in rows)


def publish(build: dict[str, bytes], frame: bytes, prefix: bytes, output: pathlib.Path) -> None:
    if output.exists() or output.is_symlink():
        BASE.fail(f"refusing to replace output: {output}")
    with tempfile.TemporaryDirectory(prefix=".bird-deferred-wifi-pair-", dir=output.parent) as temp:
        stage = pathlib.Path(temp) / "publication"
        stage.mkdir()
        files = {
            "authority.tsv": authority(prefix),
            "deferred-wifi-pair.bin": build["combined"],
            "deferred-wifi-pair-prefix-16m.bin": prefix,
            "fixed-command-closure-base.bin": BASE.read(BASE.BASE_DIR / "fixed-command-closure.bin"),
            "fixed-command-closure-base-prefix-16m.bin": BASE.read(BASE.BASE_DIR / "fixed-command-closure-prefix-16m.bin"),
            "stage11-no-raid6-benchmark.bin": BASE.read(STAGE11_DIR / "no-raid6-benchmark-pair.bin"),
            "stage11-no-raid6-benchmark-prefix-16m.bin": BASE.read(STAGE11_DIR / "no-raid6-benchmark-pair-prefix-16m.bin"),
            "KERNEL.lz4": frame,
            SOURCE_AUTHORITY.name: BASE.read(SOURCE_AUTHORITY),
            "build.config": build["config"],
            "u-boot.bin": build["uboot"],
            "spl.bin": build["spl"],
            "control.dtb": build["dtb"],
        }
        for name, data in files.items():
            (stage / name).write_bytes(data)
        (stage / "sha256sums.txt").write_bytes(
            b"".join(
                f"{BASE.sha256(data)}  {name}\n".encode()
                for name, data in sorted(files.items())
            )
        )
        verify_output(stage)
        stage.rename(output)


def verify_stage11_successor(combined: bytes) -> None:
    predecessor = BASE.read(STAGE11_DIR / "no-raid6-benchmark-pair.bin")
    BASE.exact(
        predecessor,
        EXPECTED["combined"][0],
        STAGE11_COMBINED_SHA256,
        "accepted Stage 11 U-Boot",
    )
    prefix = BASE.read(STAGE11_DIR / "no-raid6-benchmark-pair-prefix-16m.bin")
    BASE.exact(prefix, PREFIX_BYTES, STAGE11_PREFIX_SHA256, "accepted Stage 11 prefix")
    differences = {
        index: (before, after)
        for index, (before, after) in enumerate(zip(predecessor, combined))
        if before != after
    }
    if len(predecessor) != len(combined) or differences != EXPECTED_STAGE11_DIFF:
        BASE.fail(f"U-Boot changed outside the exact Stage 11 bound: {differences}")


def verify_output(directory: pathlib.Path) -> None:
    if directory.is_symlink() or not directory.is_dir():
        BASE.fail(f"unsafe or missing authority directory: {directory}")
    if {path.name for path in directory.iterdir()} != PUBLISHED:
        BASE.fail("boot-pair authority inventory changed")
    rows = BASE.read(directory / "sha256sums.txt").decode().splitlines()
    expected_files = PUBLISHED - {"sha256sums.txt"}
    found = set()
    for row in rows:
        fields = row.split("  ", 1)
        if len(fields) != 2 or fields[1] in found or fields[1] not in expected_files:
            BASE.fail("boot-pair checksum inventory is malformed")
        if len(fields[0]) != 64 or BASE.sha256(BASE.read(directory / fields[1])) != fields[0]:
            BASE.fail(f"boot-pair checksum mismatch: {fields[1]}")
        found.add(fields[1])
    if found != expected_files:
        BASE.fail("boot-pair checksum inventory is incomplete")
    combined = BASE.read(directory / "deferred-wifi-pair.bin")
    build = {
        "combined": combined,
        "fit": combined[EXPECTED["spl"][0] :],
        "uboot": BASE.read(directory / "u-boot.bin"),
        "config": BASE.read(directory / "build.config"),
        "spl": BASE.read(directory / "spl.bin"),
        "dtb": BASE.read(directory / "control.dtb"),
    }
    for name, (size, digest) in EXPECTED.items():
        BASE.exact(build[name], size, digest, f"published {name}")
    verify_stage11_successor(build["combined"])
    _, prefix = BASE.verify_exact_successor(build)
    if BASE.read(directory / "deferred-wifi-pair-prefix-16m.bin") != prefix:
        BASE.fail("published candidate prefix changed")
    if BASE.read(directory / SOURCE_AUTHORITY.name) != BASE.read(SOURCE_AUTHORITY):
        BASE.fail("published source-kernel authority changed")
    BASE.verify_kernel_pair(KERNEL_A.read_bytes(), BASE.read(directory / "KERNEL.lz4"), build["uboot"])
    if BASE.read(directory / "authority.tsv") != authority(prefix):
        BASE.fail("published boot-pair authority record changed")


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
        if any(
            getattr(args, name) is not None
            for name in ("build_a", "build_b", "kernel_a", "kernel_b", "lz4_a", "lz4_b", "output")
        ):
            BASE.fail("verify-output cannot be combined with publication arguments")
        verify_output(args.verify_output)
        print("Deferred-Wi-Fi boot pair: VERIFIED")
        return
    values = (
        args.build_a,
        args.build_b,
        args.kernel_a,
        args.kernel_b,
        args.lz4_a,
        args.lz4_b,
        args.output,
    )
    if any(value is None for value in values):
        BASE.fail("both builds, kernels, LZ4 frames and output are required")
    first, second = BASE.load_build(args.build_a), BASE.load_build(args.build_b)
    if first != second:
        BASE.fail("isolated U-Boot builds are not byte-identical")
    verify_stage11_successor(first["combined"])
    kernel_a, kernel_b = BASE.read(args.kernel_a), BASE.read(args.kernel_b)
    frame_a, frame_b = BASE.read(args.lz4_a), BASE.read(args.lz4_b)
    if kernel_a != kernel_b or frame_a != frame_b:
        BASE.fail("isolated kernel or LZ4 outputs are not byte-identical")
    _, prefix = BASE.verify_exact_successor(first)
    BASE.verify_kernel_pair(kernel_a, frame_a, first["uboot"])
    publish(first, frame_a, prefix, args.output)
    print(f"Deferred-Wi-Fi boot pair: VERIFIED AND PUBLISHED to {args.output}")


if __name__ == "__main__":
    main()
