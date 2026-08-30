#!/usr/bin/env python3
"""Verify and publish the fixed RG34XX-SP simple-parser U-Boot authority."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import shutil
import struct
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE_DIR = ROOT / "kernel/work/bird-uboot-lz4-pair-20260813"
KERNEL_DIR = ROOT / "kernel/work/bird-kernel-lz4-irq-candidate-20260813"
SOURCE_TAR = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/sources/u-boot-DDR4/"
    "u-boot-DDR4-v2026.01.tar.gz"
)
INPLACE_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-inplace-handoff-build.py"
PAIR_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-lz4-pair-build.py"
LZ4_VERIFIER = ROOT / "kernel/rocknix/verify-lz4-kernel-candidate.py"
RAW_OFFSET = 8192
PREFIX_BYTES = 16 * 1024 * 1024
EXPECTED = {
    "combined": (518_369, "f6b7d3480f43e9c79c764cc55f40264d747151f93991fd614392bb3ae5bce058"),
    "fit": (477_409, "2fca5083c1c3fed9f184c5dd5c3c64098cbb540cd09b4c49ec025aa4ba5e99b0"),
    "uboot": (398_560, "47a352376e7b5358a036b97498599504be3b1cfac942738ea363fc50df78d1f2"),
    "config": (47_198, "f8b1ee67acee99f47cedda58be8b907e1f47917c7ba2cc7ade35363385d1ac65"),
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
BASE_COMBINED_SHA = "9f3d96da4126a6654187a3cddb9b0c038b251882aee9938e0b258d0bac94f35b"
BASE_PREFIX_SHA = "2e6680950a885cef607a9642c0133a8794d7407c7879ccb0fe9c153b6be45f56"
CANDIDATE_PREFIX_SHA = "8eba279a07bf9d6b9f058805169acef60c6cbb32404a608175e1b9f9bac1caff"
EXPECTED_DELTA = {
    "CONFIG_AUTO_COMPLETE": ("y", "n"),
    "CONFIG_BOOT_DEFAULTS": ("y", "n"),
    "CONFIG_BOOT_DEFAULTS_CMDS": ("y", "n"),
    "CONFIG_BOOT_DEFAULTS_FEATURES": ("y", "n"),
    "CONFIG_CMDLINE_EDITING": ("y", "n"),
    "CONFIG_DISTRO_DEFAULTS": ("y", "n"),
    "CONFIG_HUSH_OLD_PARSER": ("y", "n"),
    "CONFIG_HUSH_PARSER": ("y", "n"),
    "CONFIG_SYS_LONGHELP": ("y", "n"),
    "CONFIG_SYS_PROMPT_HUSH_PS2": ('"> "', "n"),
    "CONFIG_SYS_XTRACE": ("y", "n"),
}
PUBLISHED = {
    "authority.tsv",
    "simple-parser.bin",
    "simple-parser-prefix-16m.bin",
    "lz4-base.bin",
    "lz4-base-prefix-16m.bin",
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


def parse_config(data: bytes) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in data.decode().splitlines():
        if line.startswith("CONFIG_"):
            key, value = line.split("=", 1)
            result[key] = value
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            result[line[2:-11]] = "n"
    return result


def load_build(directory: pathlib.Path) -> dict[str, bytes]:
    build = {name: read(directory / relative) for name, relative in BUILD_FILES.items()}
    for name, (size, digest) in EXPECTED.items():
        if len(build[name]) != size or sha256(build[name]) != digest:
            fail(f"{directory.name} {name} identity changed")
    if build["combined"] != build["spl"] + build["fit"]:
        fail("combined artifact composition changed")
    if struct.unpack_from("<I", build["combined"], 0x10)[0] != len(build["spl"]):
        fail("fixed SPL region changed")
    return build


def verify_config(before_data: bytes, after_data: bytes) -> None:
    before, after = parse_config(before_data), parse_config(after_data)
    changed = {
        key: (before.get(key, "n"), after.get(key, "n"))
        for key in before.keys() | after.keys()
        if before.get(key, "n") != after.get(key, "n")
    }
    if changed != EXPECTED_DELTA:
        fail(f"resolved simple-parser config delta changed: {changed}")
    fixed = {
        "CONFIG_BOOTCOMMAND": '"sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux.conf"',
        "CONFIG_BOOTDELAY": "-2",
        "CONFIG_CMDLINE": "y",
        "CONFIG_CMD_SYSBOOT": "y",
        "CONFIG_PXE_UTILS": "y",
        "CONFIG_SUPPORT_RAW_INITRD": "y",
        "CONFIG_CMD_BOOTI": "y",
        "CONFIG_LZ4": "y",
        "CONFIG_FS_FAT": "y",
        "CONFIG_MMC": "y",
        "CONFIG_MMC_SUNXI": "y",
        "CONFIG_ENV_SOURCE_FILE": '"bird-rg34xx-sp-handoff"',
        "CONFIG_NO_NET": "y",
        "CONFIG_BOOTSTD": "n",
        "CONFIG_SYS_MALLOC_CLEAR_ON_INIT": "n",
        "CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT": "y",
    }
    for key, value in fixed.items():
        if after.get(key, "n") != value:
            fail(f"required simple-parser config changed: {key}")


def candidate_prefix(base_prefix: bytes, base: bytes, candidate: bytes) -> bytes:
    if len(base_prefix) != PREFIX_BYTES or sha256(base_prefix) != BASE_PREFIX_SHA:
        fail("accepted LZ4 predecessor prefix changed")
    if base_prefix[RAW_OFFSET:RAW_OFFSET + len(base)] != base:
        fail("accepted LZ4 predecessor bytes do not match its prefix")
    result = bytearray(base_prefix)
    result[RAW_OFFSET:RAW_OFFSET + len(candidate)] = candidate
    if sha256(result) != CANDIDATE_PREFIX_SHA:
        fail("simple-parser prefix reconstruction changed")
    return bytes(result)


def verify_builds(first: dict[str, bytes], second: dict[str, bytes]) -> bytes:
    if first != second:
        fail("isolated simple-parser builds are not byte-identical")
    pair = load_module("bird_simple_pair", PAIR_VERIFIER)
    inplace = load_module("bird_simple_inplace", INPLACE_VERIFIER)
    lz4 = load_module("bird_simple_lz4", LZ4_VERIFIER)
    pair.verify_output(BASE_DIR)
    base = read(BASE_DIR / "lz4-pair.bin")
    base_prefix = read(BASE_DIR / "lz4-pair-prefix-16m.bin")
    if sha256(base) != BASE_COMBINED_SHA:
        fail("accepted LZ4 predecessor identity changed")
    verify_config(read(BASE_DIR / "diagnostic/a/build.config"), first["config"])
    if first["spl"] != read(BASE_DIR / "diagnostic/a/spl.bin"):
        fail("accepted SPL changed")
    if first["dtb"] != read(BASE_DIR / "diagnostic/a/control.dtb"):
        fail("accepted control DTB changed")
    inplace.verify_fit_scope(read(BASE_DIR / "diagnostic/a/u-boot.itb"), first["fit"])
    kernel = lz4.read_exact_file(
        ROOT / "kernel/work/rocknix-source-irq-buttons/build/Image",
        lz4.KERNEL_BYTES,
        lz4.KERNEL_SHA256,
    )
    frame_data = lz4.read_exact_file(
        KERNEL_DIR / "KERNEL.lz4", lz4.CANDIDATE_BYTES, lz4.CANDIDATE_SHA256
    )
    lz4.verify_uboot_sources(SOURCE_TAR)
    frame = lz4.parse_lz4_frame(frame_data)
    if frame.output != kernel or frame.flags != 0x64 or frame.block_descriptor != 0x70:
        fail("accepted LZ4 frame contract changed")
    address = lz4.verify_address_layout(lz4.parse_environment(first["uboot"]))
    if address.current_kernel_comp_size != lz4.CANDIDATE_BYTES:
        fail("simple-parser U-Boot lost the exact LZ4 bound")
    for forbidden in (b"hush - the simple shell", b"xtrace"):
        if forbidden in first["uboot"]:
            fail("removed interactive parser text remains")
    return candidate_prefix(base_prefix, base, first["combined"])


def authority(prefix: bytes) -> bytes:
    rows = (
        ("schema", "bird-uboot-simple-parser-authority-v1"),
        ("review-state", "reviewed"),
        ("classification", "production-successor"),
        ("why-before", "sunxi-distro-defaults-select-interactive-hush"),
        ("why-change", "fixed-uninterruptible-sysboot-needs-simple-parser-only"),
        ("predecessor", "accepted-lz4-pair"),
        ("predecessor-sha256", BASE_COMBINED_SHA),
        ("predecessor-prefix-sha256", BASE_PREFIX_SHA),
        ("candidate-bytes", EXPECTED["combined"][0]),
        ("candidate-sha256", EXPECTED["combined"][1]),
        ("candidate-uboot-bytes", EXPECTED["uboot"][0]),
        ("candidate-uboot-sha256", EXPECTED["uboot"][1]),
        ("candidate-config-sha256", EXPECTED["config"][1]),
        ("candidate-prefix-sha256", sha256(prefix)),
        ("saved-combined-bytes", 38_608),
        ("spl-byte-identical", "yes"),
        ("control-dtb-byte-identical", "yes"),
        ("fit-difference-scope", "images-uboot-data-only"),
        ("repeat-byte-identical", "yes"),
        ("card-write", "none"),
    )
    return b"".join(f"{key}\t{value}\n".encode() for key, value in rows)


def publish(first: dict[str, bytes], prefix: bytes, output: pathlib.Path) -> None:
    if output.exists() or output.is_symlink():
        fail(f"refusing to replace output: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bird-simple-parser-", dir=output.parent) as temp:
        stage = pathlib.Path(temp) / "publication"
        stage.mkdir()
        files = {
            "authority.tsv": authority(prefix),
            "simple-parser.bin": first["combined"],
            "simple-parser-prefix-16m.bin": prefix,
            "lz4-base.bin": read(BASE_DIR / "lz4-pair.bin"),
            "lz4-base-prefix-16m.bin": read(BASE_DIR / "lz4-pair-prefix-16m.bin"),
            "build.config": first["config"],
            "u-boot.bin": first["uboot"],
            "spl.bin": first["spl"],
            "control.dtb": first["dtb"],
        }
        for name, data in files.items():
            (stage / name).write_bytes(data)
        checksums = b"".join(
            f"{sha256(read(stage / name))}  {name}\n".encode() for name in sorted(files)
        )
        (stage / "sha256sums.txt").write_bytes(checksums)
        verify_output(stage)
        stage.rename(output)


def verify_output(directory: pathlib.Path) -> None:
    if directory.is_symlink() or not directory.is_dir():
        fail(f"unsafe or missing authority directory: {directory}")
    if {path.name for path in directory.iterdir()} != PUBLISHED:
        fail("simple-parser authority inventory changed")
    rows = read(directory / "sha256sums.txt").decode().splitlines()
    expected_names = PUBLISHED - {"sha256sums.txt"}
    found: set[str] = set()
    for row in rows:
        fields = row.split("  ", 1)
        if len(fields) != 2 or fields[1] in found or fields[1] not in expected_names:
            fail("simple-parser checksum inventory is malformed")
        digest, name = fields
        if len(digest) != 64 or sha256(read(directory / name)) != digest:
            fail(f"simple-parser checksum mismatch: {name}")
        found.add(name)
    if found != expected_names:
        fail("simple-parser checksum inventory is incomplete")
    candidate = read(directory / "simple-parser.bin")
    prefix = read(directory / "simple-parser-prefix-16m.bin")
    base = read(directory / "lz4-base.bin")
    base_prefix = read(directory / "lz4-base-prefix-16m.bin")
    for name, data in (
        ("combined", candidate),
        ("uboot", read(directory / "u-boot.bin")),
        ("config", read(directory / "build.config")),
        ("spl", read(directory / "spl.bin")),
        ("dtb", read(directory / "control.dtb")),
    ):
        size, digest = EXPECTED[name]
        if len(data) != size or sha256(data) != digest:
            fail(f"published simple-parser {name} identity changed")
    if sha256(base) != BASE_COMBINED_SHA or sha256(base_prefix) != BASE_PREFIX_SHA:
        fail("published LZ4 predecessor authority changed")
    if candidate_prefix(base_prefix, base, candidate) != prefix:
        fail("published simple-parser prefix changed")
    verify_config(
        read(BASE_DIR / "diagnostic/a/build.config"), read(directory / "build.config")
    )
    if read(directory / "authority.tsv") != authority(prefix):
        fail("simple-parser authority record changed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-a", type=pathlib.Path)
    parser.add_argument("--build-b", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--verify-output", type=pathlib.Path)
    args = parser.parse_args()
    if args.verify_output is not None:
        if any(value is not None for value in (args.build_a, args.build_b, args.output)):
            fail("verify-output cannot be combined with build publication")
        verify_output(args.verify_output)
        print("U-Boot simple-parser authority: VERIFIED")
        return
    if any(value is None for value in (args.build_a, args.build_b, args.output)):
        fail("build-a, build-b and output are required for publication")
    first, second = load_build(args.build_a), load_build(args.build_b)
    prefix = verify_builds(first, second)
    publish(first, prefix, args.output)
    print("U-Boot simple-parser authority: VERIFIED")


if __name__ == "__main__":
    main()
