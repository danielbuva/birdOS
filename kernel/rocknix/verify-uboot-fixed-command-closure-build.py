#!/usr/bin/env python3
"""Verify and publish the RG34XX-SP fixed-command-closure U-Boot authority."""

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
BASE_DIR = ROOT / "kernel/work/bird-uboot-fixed-read-path-20260829"
KERNEL_DIR = ROOT / "kernel/work/bird-kernel-lz4-irq-candidate-20260813"
SOURCE_TAR = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/sources/u-boot-DDR4/"
    "u-boot-DDR4-v2026.01.tar.gz"
)
INPLACE_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-inplace-handoff-build.py"
BASE_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-fixed-read-path-build.py"
LZ4_VERIFIER = ROOT / "kernel/rocknix/verify-lz4-kernel-candidate.py"
RAW_OFFSET = 8192
PREFIX_BYTES = 16 * 1024 * 1024
EXPECTED = {
    "combined": (411_977, "918d9b8a0dd89ffb291a866eefa630c796ea7e3199ba92ce9664e6a72500161f"),
    "fit": (371_017, "c4bf054bd312717f137167bc4e15711b09dddaf2996caa6d1aac321a6fa662b3"),
    "uboot": (292_168, "f5687e2c971db0b59d051465b78f3763c08e94d74ecc9a8249b484639cbf9a9a"),
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
BASE_COMBINED_SHA = "bd571d050143b3643af577a006f553e7b5b25d7a97a8584c20d67d459122f914"
BASE_PREFIX_SHA = "7826608f5257f751bd05a45cfcf1d8fdedd1a6381350e1af2c437b947aa4df72"
CANDIDATE_PREFIX_SHA = "c156973946fd1f1fcb581eeb669abb638ce554cf16356db60428ba1ebb3a9c1b"
EXPECTED_DELTA = {
    "CONFIG_BOOTM_ELF": ("y", "n"),
    "CONFIG_BOOTM_NETBSD": ("y", "n"),
    "CONFIG_BOOTM_PLAN9": ("y", "n"),
    "CONFIG_BOOTM_RTEMS": ("y", "n"),
    "CONFIG_BOOTM_VXWORKS": ("y", "n"),
    "CONFIG_CMD_BDI": ("y", "n"),
    "CONFIG_CMD_BIND": ("y", "n"),
    "CONFIG_CMD_BLOCK_CACHE": ("y", "n"),
    "CONFIG_CMD_BOOTD": ("y", "n"),
    "CONFIG_CMD_BOOTM": ("y", "n"),
    "CONFIG_CMD_CONSOLE": ("y", "n"),
    "CONFIG_CMD_CRC32": ("y", "n"),
    "CONFIG_CMD_CYCLIC": ("y", "n"),
    "CONFIG_CMD_DM": ("y", "n"),
    "CONFIG_CMD_ECHO": ("y", "n"),
    "CONFIG_CMD_EDITENV": ("y", "n"),
    "CONFIG_CMD_ELF": ("y", "n"),
    "CONFIG_CMD_ELF_BOOTVX": ("y", "n"),
    "CONFIG_CMD_ENV_EXISTS": ("y", "n"),
    "CONFIG_CMD_EXPORTENV": ("y", "n"),
    "CONFIG_CMD_FDT": ("y", "n"),
    "CONFIG_CMD_GO": ("y", "n"),
    "CONFIG_CMD_HELP": ("y", "n"),
    "CONFIG_CMD_IMI": ("y", "n"),
    "CONFIG_CMD_IMPORTENV": ("y", "n"),
    "CONFIG_CMD_ITEST": ("y", "n"),
    "CONFIG_CMD_LOADB": ("y", "n"),
    "CONFIG_CMD_LOADS": ("y", "n"),
    "CONFIG_CMD_LZMADEC": ("y", "n"),
    "CONFIG_CMD_MEMORY": ("y", "n"),
    "CONFIG_CMD_PINMUX": ("y", "n"),
    "CONFIG_CMD_RUN": ("y", "n"),
    "CONFIG_CMD_SAVEENV": ("y", "n"),
    "CONFIG_CMD_SETEXPR": ("y", "n"),
    "CONFIG_CMD_SLEEP": ("y", "n"),
    "CONFIG_CMD_SOURCE": ("y", "n"),
    "CONFIG_CMD_UNLZ4": ("y", "n"),
    "CONFIG_CMD_UNZIP": ("y", "n"),
    "CONFIG_CMD_XIMG": ("y", "n"),
    "CONFIG_LIB_ELF": ("y", "n"),
    "CONFIG_LZMA": ("y", "n"),
    "CONFIG_SAVEENV": ("y", "n"),
    "CONFIG_SYS_XIMG_LEN": ("0x800000", "n"),
    "CONFIG_VPL_LZMA": ("y", "n"),
}
PUBLISHED = {
    "authority.tsv",
    "fixed-command-closure.bin",
    "fixed-command-closure-prefix-16m.bin",
    "fixed-read-path-base.bin",
    "fixed-read-path-base-prefix-16m.bin",
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
        fail(f"resolved fixed-command-closure config delta changed: {changed}")
    fixed = {
        "CONFIG_BOOTCOMMAND": '"sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux.conf"',
        "CONFIG_BOOTDELAY": "-2",
        "CONFIG_CMDLINE": "y",
        "CONFIG_CMD_SYSBOOT": "y",
        "CONFIG_PXE_UTILS": "y",
        "CONFIG_SUPPORT_RAW_INITRD": "y",
        "CONFIG_CMD_BOOTI": "y",
        "CONFIG_LIB_BOOTI": "y",
        "CONFIG_LIB_BOOTM": "y",
        "CONFIG_BOOTM_LINUX": "y",
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
        "CONFIG_CMD_BOOTM": "n",
        "CONFIG_CMD_MEMORY": "n",
        "CONFIG_CMD_SAVEENV": "n",
        "CONFIG_CMD_UNLZ4": "n",
    }
    for key, value in fixed.items():
        if after.get(key, "n") != value:
            fail(f"required fixed-command-closure config changed: {key}")


def candidate_prefix(base_prefix: bytes, base: bytes, candidate: bytes) -> bytes:
    if len(base_prefix) != PREFIX_BYTES or sha256(base_prefix) != BASE_PREFIX_SHA:
        fail("accepted fixed-read-path predecessor prefix changed")
    if base_prefix[RAW_OFFSET:RAW_OFFSET + len(base)] != base:
        fail("accepted fixed-read-path predecessor bytes do not match its prefix")
    result = bytearray(base_prefix)
    result[RAW_OFFSET:RAW_OFFSET + len(candidate)] = candidate
    if sha256(result) != CANDIDATE_PREFIX_SHA:
        fail("fixed-command-closure prefix reconstruction changed")
    return bytes(result)


def verify_builds(first: dict[str, bytes], second: dict[str, bytes]) -> bytes:
    if first != second:
        fail("isolated fixed-command-closure builds are not byte-identical")
    base_verifier = load_module("bird_fixed_read_path", BASE_VERIFIER)
    inplace = load_module("bird_simple_inplace", INPLACE_VERIFIER)
    lz4 = load_module("bird_simple_lz4", LZ4_VERIFIER)
    base_verifier.verify_output(BASE_DIR)
    base = read(BASE_DIR / "fixed-read-path.bin")
    base_prefix = read(BASE_DIR / "fixed-read-path-prefix-16m.bin")
    if sha256(base) != BASE_COMBINED_SHA:
        fail("accepted fixed-read-path predecessor identity changed")
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
        fail("fixed-command-closure U-Boot lost the exact LZ4 bound")
    for forbidden in (b"hush - the simple shell", b"xtrace"):
        if forbidden in first["uboot"]:
            fail("removed interactive parser text remains")
    return candidate_prefix(base_prefix, base, first["combined"])


def authority(prefix: bytes) -> bytes:
    rows = (
        ("schema", "bird-uboot-fixed-command-closure-authority-v1"),
        ("review-state", "reviewed"),
        ("classification", "production-successor"),
        ("why-before", "fixed-read-path-gate-retained-generic-command-surface"),
        ("why-change", "fixed-autoboot-needs-sysboot-extlinux-booti-only"),
        ("predecessor", "accepted-fixed-read-path"),
        ("predecessor-sha256", BASE_COMBINED_SHA),
        ("predecessor-prefix-sha256", BASE_PREFIX_SHA),
        ("candidate-bytes", EXPECTED["combined"][0]),
        ("candidate-sha256", EXPECTED["combined"][1]),
        ("candidate-uboot-bytes", EXPECTED["uboot"][0]),
        ("candidate-uboot-sha256", EXPECTED["uboot"][1]),
        ("candidate-config-sha256", EXPECTED["config"][1]),
        ("candidate-prefix-sha256", sha256(prefix)),
        ("saved-combined-bytes", 66_056),
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
    with tempfile.TemporaryDirectory(prefix=".bird-fixed-command-closure-", dir=output.parent) as temp:
        stage = pathlib.Path(temp) / "publication"
        stage.mkdir()
        files = {
            "authority.tsv": authority(prefix),
            "fixed-command-closure.bin": first["combined"],
            "fixed-command-closure-prefix-16m.bin": prefix,
            "fixed-read-path-base.bin": read(BASE_DIR / "fixed-read-path.bin"),
            "fixed-read-path-base-prefix-16m.bin": read(
                BASE_DIR / "fixed-read-path-prefix-16m.bin"
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
        fail("fixed-command-closure authority inventory changed")
    rows = read(directory / "sha256sums.txt").decode().splitlines()
    expected_names = PUBLISHED - {"sha256sums.txt"}
    found: set[str] = set()
    for row in rows:
        fields = row.split("  ", 1)
        if len(fields) != 2 or fields[1] in found or fields[1] not in expected_names:
            fail("fixed-command-closure checksum inventory is malformed")
        digest, name = fields
        if len(digest) != 64 or sha256(read(directory / name)) != digest:
            fail(f"fixed-command-closure checksum mismatch: {name}")
        found.add(name)
    if found != expected_names:
        fail("fixed-command-closure checksum inventory is incomplete")
    candidate = read(directory / "fixed-command-closure.bin")
    prefix = read(directory / "fixed-command-closure-prefix-16m.bin")
    base = read(directory / "fixed-read-path-base.bin")
    base_prefix = read(directory / "fixed-read-path-base-prefix-16m.bin")
    for name, data in (
        ("combined", candidate),
        ("uboot", read(directory / "u-boot.bin")),
        ("config", read(directory / "build.config")),
        ("spl", read(directory / "spl.bin")),
        ("dtb", read(directory / "control.dtb")),
    ):
        size, digest = EXPECTED[name]
        if len(data) != size or sha256(data) != digest:
            fail(f"published fixed-command-closure {name} identity changed")
    if sha256(base) != BASE_COMBINED_SHA or sha256(base_prefix) != BASE_PREFIX_SHA:
        fail("published fixed-read-path predecessor authority changed")
    if candidate_prefix(base_prefix, base, candidate) != prefix:
        fail("published fixed-command-closure prefix changed")
    verify_config(
        read(BASE_DIR / "build.config"), read(directory / "build.config")
    )
    if read(directory / "authority.tsv") != authority(prefix):
        fail("fixed-command-closure authority record changed")


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
        print("U-Boot fixed-command-closure authority: VERIFIED")
        return
    if any(value is None for value in (args.build_a, args.build_b, args.output)):
        fail("build-a, build-b and output are required for publication")
    first, second = load_build(args.build_a), load_build(args.build_b)
    prefix = verify_builds(first, second)
    publish(first, prefix, args.output)
    print("U-Boot fixed-command-closure authority: VERIFIED")


if __name__ == "__main__":
    main()
