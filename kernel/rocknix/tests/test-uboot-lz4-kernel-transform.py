#!/usr/bin/env python3
"""Focused host contract for the exact U-Boot/LZ4 KERNEL pairing."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import tarfile
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-lz4-kernel.py"
LZ4_VERIFIER = ROOT / "kernel/rocknix/verify-lz4-kernel-candidate.py"
UBOOT_SOURCE = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/sources/u-boot-DDR4/"
    "u-boot-DDR4-v2026.01.tar.gz"
)
INPLACE_UBOOT = (
    ROOT
    / "kernel/work/bird-uboot-inplace-handoff-20260701/inplace-handoff-uboot.bin"
)
LZ4_KERNEL = ROOT / "kernel/work/bird-kernel-lz4-irq-candidate-20260813/KERNEL.lz4"
HEADER_MEMBER = "u-boot-2026.01/include/configs/sunxi-common.h"


def load(name: str, path: pathlib.Path):
    specification = importlib.util.spec_from_file_location(name, path)
    assert specification is not None and specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


def expect_rejected(function) -> None:
    try:
        function()
    except SystemExit:
        pass
    else:
        raise AssertionError("changed LZ4 pairing authority was accepted")


def main() -> None:
    pair = load("bird_uboot_lz4_pair", TRANSFORM)
    lz4 = load("bird_lz4_pair_verifier", LZ4_VERIFIER)
    assert pair.LZ4_KERNEL_BYTES == lz4.CANDIDATE_BYTES
    assert pair.LZ4_KERNEL_SIZE_HEX == f"0x{lz4.CANDIDATE_BYTES:x}"
    assert len(pair.OLD_LIMIT) == len(pair.NEW_LIMIT)

    if not UBOOT_SOURCE.is_file():
        print("U-Boot LZ4 KERNEL transform tests: PASS (pinned source unavailable)")
        return
    with tarfile.open(UBOOT_SOURCE, "r:gz") as archive:
        member = archive.extractfile(HEADER_MEMBER)
        assert member is not None
        source = member.read()
    result = pair.transform(source)
    assert pair.sha256(source) == pair.SOURCE_SHA256
    assert pair.sha256(result) == pair.RESULT_SHA256
    assert result.count(pair.NEW_LIMIT) == 1
    assert pair.OLD_LIMIT not in result

    for mutation in (
        source + b"/* drift */\n",
        source.replace(pair.OLD_LIMIT, pair.NEW_LIMIT),
        source.replace(b"#define FDT_ADDR_R", b"#define BIRD_FDT_ADDR_R", 1),
    ):
        expect_rejected(lambda mutation=mutation: pair.transform(mutation))

    with tempfile.TemporaryDirectory(prefix="bird-uboot-lz4-transform-") as temporary:
        temporary_path = pathlib.Path(temporary)
        source_path = temporary_path / "sunxi-common.h"
        output_path = temporary_path / "sunxi-common.lz4.h"
        source_path.write_bytes(source)
        with output_path.open("xb") as output:
            output.write(pair.transform(source_path.read_bytes()))
        assert output_path.read_bytes() == result

    if INPLACE_UBOOT.is_file() and LZ4_KERNEL.is_file():
        inplace = INPLACE_UBOOT.read_bytes()
        old = b"kernel_comp_size=0xb000000\0"
        new = b"kernel_comp_size=" + pair.LZ4_KERNEL_SIZE_HEX.encode() + b"\0"
        assert len(old) == len(new)
        assert inplace.count(old) == 1 and new not in inplace
        paired = inplace.replace(old, new)
        assert len(paired) == len(inplace)
        environment = lz4.parse_environment(paired)
        assert environment["kernel_comp_size"] == lz4.CANDIDATE_BYTES
        address = lz4.verify_address_layout(environment)
        assert address.exact_decompression_limit_end < address.fdt_addr
        assert address.current_decompression_limit_end == address.exact_decompression_limit_end
        assert address.fdt_addr - address.current_decompression_limit_end == 19_378_066

    print("U-Boot LZ4 KERNEL transform tests: PASS")


if __name__ == "__main__":
    main()
