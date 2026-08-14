#!/usr/bin/env python3
"""Focused host contract for the isolated exact LZ4 KERNEL candidate."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
VERIFIER = ROOT / "kernel/rocknix/verify-lz4-kernel-candidate.py"
BUILDER = ROOT / "kernel/rocknix/build-lz4-kernel-candidate.sh"
KERNEL = ROOT / "kernel/work/rocknix-source-irq-buttons/build/Image"
LZ4 = pathlib.Path("/opt/homebrew/Cellar/lz4/1.10.0/bin/lz4")
UBOOT_SOURCE = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/sources/u-boot-DDR4/"
    "u-boot-DDR4-v2026.01.tar.gz"
)
UBOOT_CONFIG = (
    ROOT
    / "kernel/work/bird-uboot-inplace-handoff-20260701/inplace-handoff.config"
)
UBOOT_BINARY = (
    ROOT
    / "kernel/work/bird-uboot-inplace-handoff-20260701/inplace-handoff-uboot.bin"
)


def load_verifier():
    name = "bird_lz4_verify"
    specification = importlib.util.spec_from_file_location(name, VERIFIER)
    assert specification is not None and specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


def main() -> None:
    verifier = load_verifier()
    assert verifier.xxh32(b"") == 0x02CC5D05
    assert verifier.xxh32(b"123456789") == 0x937BAD67
    assert verifier.xxh32(b"birdOS") == 0x2E1C919F

    required = (KERNEL, LZ4, UBOOT_SOURCE, UBOOT_CONFIG, UBOOT_BINARY)
    if not all(path.is_file() for path in required):
        print("SKIP: exact host LZ4/U-Boot/kernel authorities are unavailable")
        return
    with tempfile.TemporaryDirectory() as temporary:
        output = pathlib.Path(temporary) / "candidate"
        environment = os.environ.copy()
        environment["OUTPUT"] = str(output)
        subprocess.run((str(BUILDER),), check=True, env=environment, capture_output=True)
        built = output / "KERNEL.lz4"
        assert built.stat().st_size == verifier.CANDIDATE_BYTES
        assert verifier.sha256_bytes(built.read_bytes()) == verifier.CANDIDATE_SHA256
        frame, address = verifier.verify(
            KERNEL, built, UBOOT_SOURCE, UBOOT_CONFIG, UBOOT_BINARY
        )
        assert frame.output == KERNEL.read_bytes()
        assert frame.blocks == 8
        assert address.kernel_input_end < address.decompression_addr
        assert address.decompression_output_end < address.fdt_addr
        assert address.exact_decompression_limit_end < address.fdt_addr
        assert address.current_decompression_limit_end > address.fdt_addr

        accepted_uboot = UBOOT_BINARY.read_bytes()
        old = b"kernel_comp_size=0xb000000\0"
        new = b"kernel_comp_size=0x10c080b\0"
        assert accepted_uboot.count(old) == 1 and new not in accepted_uboot
        paired_uboot = pathlib.Path(temporary) / "paired-u-boot.bin"
        paired_uboot.write_bytes(accepted_uboot.replace(old, new))
        assert verifier.sha256_bytes(paired_uboot.read_bytes()) == (
            verifier.PAIRED_UBOOT_BINARY_SHA256
        )
        paired_frame, paired_address = verifier.verify(
            KERNEL, built, UBOOT_SOURCE, UBOOT_CONFIG, paired_uboot
        )
        assert paired_frame.output == KERNEL.read_bytes()
        assert paired_address.current_kernel_comp_size == verifier.CANDIDATE_BYTES
        assert paired_address.current_decompression_limit_end < paired_address.fdt_addr
        paired_validation = verifier.format_validation(paired_frame, paired_address)
        assert "paired-uboot\tyes\n" in paired_validation
        assert "deployment-requires-exact-comp-size\tno\n" in paired_validation
        authority = (output / "authority.tsv").read_text()
        assert "deployment-authority\tnone-host-candidate-only\n" in authority
        assert "deployment-requires-exact-kernel-comp-size\t0x10c080b\n" in authority
        assert "card-write\tnone\n" in authority

        data = built.read_bytes()
        for corrupted in (
            b"bad!" + data[4:],
            data[:4] + bytes((data[4] & ~0x20,)) + data[5:],
            data[:-1],
            data + b"trailing",
        ):
            try:
                verifier.parse_lz4_frame(corrupted)
            except verifier.VerificationError:
                pass
            else:
                raise AssertionError("corrupt/incompatible LZ4 frame was accepted")

        wrong_kernel = pathlib.Path(temporary) / "wrong.Image"
        wrong_kernel.write_bytes(b"not the accepted kernel")
        rejected_environment = {
            **environment,
            "OUTPUT": str(pathlib.Path(temporary) / "rejected"),
            "KERNEL": str(wrong_kernel),
        }
        rejected = subprocess.run(
            (str(BUILDER),),
            env=rejected_environment,
            text=True,
            capture_output=True,
        )
        assert rejected.returncode != 0
        assert "checksum mismatch" in rejected.stderr
    print("LZ4 KERNEL candidate tests: PASS")


if __name__ == "__main__":
    main()
