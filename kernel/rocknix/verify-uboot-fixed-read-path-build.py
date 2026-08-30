#!/usr/bin/env python3
"""Verify and publish the RG34XX-SP fixed-read-path U-Boot authority."""

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
BASE_DIR = ROOT / "kernel/work/bird-uboot-simple-parser-20260829"
KERNEL_DIR = ROOT / "kernel/work/bird-kernel-lz4-irq-candidate-20260813"
SOURCE_TAR = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/sources/u-boot-DDR4/"
    "u-boot-DDR4-v2026.01.tar.gz"
)
INPLACE_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-inplace-handoff-build.py"
PAIR_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-simple-parser-build.py"
LZ4_VERIFIER = ROOT / "kernel/rocknix/verify-lz4-kernel-candidate.py"
RAW_OFFSET = 8192
PREFIX_BYTES = 16 * 1024 * 1024
EXPECTED = {
    "combined": (478_033, "bd571d050143b3643af577a006f553e7b5b25d7a97a8584c20d67d459122f914"),
    "fit": (437_073, "2030a59a22e9f7d1866e66ac96dd172034e84a32075816603fc24c5b2a16ef0b"),
    "uboot": (358_224, "dfe6f562301a586e8f0e7dc1c2607dc054356ebd28c5f2ebc706dc9994913e42"),
    "config": (46_995, "8efb9080751be44fdb87526d31969d8b0c5f775662470be1f0ea84f77fb850df"),
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
BASE_COMBINED_SHA = "f6b7d3480f43e9c79c764cc55f40264d747151f93991fd614392bb3ae5bce058"
BASE_PREFIX_SHA = "8eba279a07bf9d6b9f058805169acef60c6cbb32404a608175e1b9f9bac1caff"
CANDIDATE_PREFIX_SHA = "7826608f5257f751bd05a45cfcf1d8fdedd1a6381350e1af2c437b947aa4df72"
EXPECTED_DELTA = {
    "CONFIG_CMD_EXT2": ("y", "n"),
    "CONFIG_CMD_EXT4": ("y", "n"),
    "CONFIG_CMD_FAT": ("y", "n"),
    "CONFIG_CMD_FS_GENERIC": ("y", "n"),
    "CONFIG_CMD_GPT": ("y", "n"),
    "CONFIG_CMD_PART": ("y", "n"),
    "CONFIG_CMD_RANDOM": ("y", "n"),
    "CONFIG_EFI_PARTITION": ("y", "n"),
    "CONFIG_EFI_PARTITION_ENTRIES_NUMBERS": ("56", "n"),
    "CONFIG_EFI_PARTITION_ENTRIES_OFF": ("0", "n"),
    "CONFIG_FAT_WRITE": ("y", "n"),
    "CONFIG_FS_EXT4": ("y", "n"),
    "CONFIG_ISO_PARTITION": ("y", "n"),
    "CONFIG_LIB_RAND": ("y", "n"),
    "CONFIG_LIB_UUID": ("y", "n"),
    "CONFIG_PARTITION_UUIDS": ("y", "n"),
    "CONFIG_RANDOM_UUID": ("y", "n"),
}
PUBLISHED = {
    "authority.tsv",
    "fixed-read-path.bin",
    "fixed-read-path-prefix-16m.bin",
    "simple-parser-base.bin",
    "simple-parser-base-prefix-16m.bin",
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
        fail(f"resolved fixed-read-path config delta changed: {changed}")
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
        "CONFIG_DOS_PARTITION": "y",
        "CONFIG_MMC": "y",
        "CONFIG_MMC_SUNXI": "y",
        "CONFIG_ENV_SOURCE_FILE": '"bird-rg34xx-sp-handoff"',
        "CONFIG_NO_NET": "y",
        "CONFIG_BOOTSTD": "n",
        "CONFIG_SYS_MALLOC_CLEAR_ON_INIT": "n",
        "CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT": "y",
        "CONFIG_CMD_PART": "n",
        "CONFIG_CMD_GPT": "n",
        "CONFIG_CMD_EXT2": "n",
        "CONFIG_CMD_EXT4": "n",
        "CONFIG_CMD_FAT": "n",
        "CONFIG_CMD_FS_GENERIC": "n",
        "CONFIG_ISO_PARTITION": "n",
        "CONFIG_EFI_PARTITION": "n",
        "CONFIG_FS_EXT4": "n",
        "CONFIG_FAT_WRITE": "n",
    }
    for key, value in fixed.items():
        if after.get(key, "n") != value:
            fail(f"required fixed-read-path config changed: {key}")


def candidate_prefix(base_prefix: bytes, base: bytes, candidate: bytes) -> bytes:
    if len(base_prefix) != PREFIX_BYTES or sha256(base_prefix) != BASE_PREFIX_SHA:
        fail("accepted simple-parser predecessor prefix changed")
    if base_prefix[RAW_OFFSET:RAW_OFFSET + len(base)] != base:
        fail("accepted simple-parser predecessor bytes do not match its prefix")
    result = bytearray(base_prefix)
    result[RAW_OFFSET:RAW_OFFSET + len(candidate)] = candidate
    if sha256(result) != CANDIDATE_PREFIX_SHA:
        fail("fixed-read-path prefix reconstruction changed")
    return bytes(result)


def verify_builds(first: dict[str, bytes], second: dict[str, bytes]) -> bytes:
    if first != second:
        fail("isolated fixed-read-path builds are not byte-identical")
    pair = load_module("bird_simple_pair", PAIR_VERIFIER)
    inplace = load_module("bird_simple_inplace", INPLACE_VERIFIER)
    lz4 = load_module("bird_simple_lz4", LZ4_VERIFIER)
    pair.verify_output(BASE_DIR)
    base = read(BASE_DIR / "simple-parser.bin")
    base_prefix = read(BASE_DIR / "simple-parser-prefix-16m.bin")
    if sha256(base) != BASE_COMBINED_SHA:
        fail("accepted simple-parser predecessor identity changed")
    verify_config(read(BASE_DIR / "build.config"), first["config"])
    if first["spl"] != read(BASE_DIR / "spl.bin"):
        fail("accepted SPL changed")
    if first["dtb"] != read(BASE_DIR / "control.dtb"):
        fail("accepted control DTB changed")
    inplace.verify_fit_scope(base[len(first["spl"]):], first["fit"])
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
        fail("fixed-read-path U-Boot lost the exact LZ4 bound")
    for forbidden in (b"hush - the simple shell", b"xtrace"):
        if forbidden in first["uboot"]:
            fail("removed interactive parser text remains")
    return candidate_prefix(base_prefix, base, first["combined"])


def authority(prefix: bytes) -> bytes:
    rows = (
        ("schema", "bird-uboot-fixed-read-path-authority-v1"),
        ("review-state", "reviewed"),
        ("classification", "production-successor"),
        ("why-before", "parser-gate-retained-generic-storage-closure"),
        ("why-change", "fixed-uninterruptible-sysboot-needs-fixed-read-path-only"),
        ("predecessor", "accepted-simple-parser"),
        ("predecessor-sha256", BASE_COMBINED_SHA),
        ("predecessor-prefix-sha256", BASE_PREFIX_SHA),
        ("candidate-bytes", EXPECTED["combined"][0]),
        ("candidate-sha256", EXPECTED["combined"][1]),
        ("candidate-uboot-bytes", EXPECTED["uboot"][0]),
        ("candidate-uboot-sha256", EXPECTED["uboot"][1]),
        ("candidate-config-sha256", EXPECTED["config"][1]),
        ("candidate-prefix-sha256", sha256(prefix)),
        ("saved-combined-bytes", 40_336),
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
    with tempfile.TemporaryDirectory(prefix=".bird-fixed-read-path-", dir=output.parent) as temp:
        stage = pathlib.Path(temp) / "publication"
        stage.mkdir()
        files = {
            "authority.tsv": authority(prefix),
            "fixed-read-path.bin": first["combined"],
            "fixed-read-path-prefix-16m.bin": prefix,
            "simple-parser-base.bin": read(BASE_DIR / "simple-parser.bin"),
            "simple-parser-base-prefix-16m.bin": read(
                BASE_DIR / "simple-parser-prefix-16m.bin"
            ),
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
        fail("fixed-read-path authority inventory changed")
    rows = read(directory / "sha256sums.txt").decode().splitlines()
    expected_names = PUBLISHED - {"sha256sums.txt"}
    found: set[str] = set()
    for row in rows:
        fields = row.split("  ", 1)
        if len(fields) != 2 or fields[1] in found or fields[1] not in expected_names:
            fail("fixed-read-path checksum inventory is malformed")
        digest, name = fields
        if len(digest) != 64 or sha256(read(directory / name)) != digest:
            fail(f"fixed-read-path checksum mismatch: {name}")
        found.add(name)
    if found != expected_names:
        fail("fixed-read-path checksum inventory is incomplete")
    candidate = read(directory / "fixed-read-path.bin")
    prefix = read(directory / "fixed-read-path-prefix-16m.bin")
    base = read(directory / "simple-parser-base.bin")
    base_prefix = read(directory / "simple-parser-base-prefix-16m.bin")
    for name, data in (
        ("combined", candidate),
        ("uboot", read(directory / "u-boot.bin")),
        ("config", read(directory / "build.config")),
        ("spl", read(directory / "spl.bin")),
        ("dtb", read(directory / "control.dtb")),
    ):
        size, digest = EXPECTED[name]
        if len(data) != size or sha256(data) != digest:
            fail(f"published fixed-read-path {name} identity changed")
    if sha256(base) != BASE_COMBINED_SHA or sha256(base_prefix) != BASE_PREFIX_SHA:
        fail("published simple-parser predecessor authority changed")
    if candidate_prefix(base_prefix, base, candidate) != prefix:
        fail("published fixed-read-path prefix changed")
    verify_config(
        read(BASE_DIR / "build.config"), read(directory / "build.config")
    )
    if read(directory / "authority.tsv") != authority(prefix):
        fail("fixed-read-path authority record changed")


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
        print("U-Boot fixed-read-path authority: VERIFIED")
        return
    if any(value is None for value in (args.build_a, args.build_b, args.output)):
        fail("build-a, build-b and output are required for publication")
    first, second = load_build(args.build_a), load_build(args.build_b)
    prefix = verify_builds(first, second)
    publish(first, prefix, args.output)
    print("U-Boot fixed-read-path authority: VERIFIED")


if __name__ == "__main__":
    main()
