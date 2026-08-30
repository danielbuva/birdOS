#!/usr/bin/env python3
"""Focused identity and corruption gates for the Stage 11 boot pair."""

from __future__ import annotations

import importlib.util
import pathlib
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
VERIFIER = ROOT / "kernel/rocknix/verify-no-raid6-benchmark-pair-build.py"
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-no-raid6-benchmark-kernel.py"
BUILDER = ROOT / "kernel/rocknix/build-no-raid6-benchmark-pair.sh"
INSTALLER = ROOT / "firmware/mac-install-no-raid6-benchmark-pair.sh"
PUBLICATION = ROOT / "kernel/work/bird-no-raid6-benchmark-pair-20260830"


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def rejected(directory: pathlib.Path, expected: str) -> None:
    result = subprocess.run(
        [sys.executable, str(VERIFIER), "--verify-output", str(directory)],
        text=True,
        capture_output=True,
    )
    assert result.returncode != 0, "corrupt boot-pair authority was accepted"
    assert expected in result.stderr, result.stderr


def corrupt(path: pathlib.Path, offset: int = 0) -> None:
    data = bytearray(path.read_bytes())
    data[offset] ^= 1
    path.write_bytes(data)


def main() -> None:
    transform = load("bird_no_raid6_transform", TRANSFORM)
    source = bytes.fromhex("00") * 16
    try:
        transform.transform(source)
    except SystemExit as error:
        assert "authority changed" in str(error)
    else:
        raise AssertionError("transform accepted an unreviewed source")
    assert transform.LZ4_KERNEL_BYTES == 17_565_344
    assert transform.LZ4_KERNEL_SIZE_HEX == "0x10c06a0"

    builder = BUILDER.read_text()
    assert "media-write" in builder
    assert "bird-rocknix-uboot-20260701" in builder
    assert "--network none" in builder
    assert "--read-only" in builder
    assert "verify-no-raid6-benchmark-pair-build.py" in builder
    for forbidden in ("diskutil", "/dev/disk", "/dev/rdisk", "mac-install-bird-uboot"):
        assert forbidden not in builder

    installer = INSTALLER.read_text()
    for required in (
        "SECTOR_BYTES=512",
        "SECTOR_INDEX=571",
        "SECTOR_OFFSET=292352",
        "validate_stock_root_card_identity",
        "bird_require_safe_removable_device",
        "bird_card_lock_acquire",
        "recover_original",
        'cp -R "$AUTHORITY" "$VERIFY_WORK/authority"',
        "snapshotted boot-pair authority verification failed",
        "before-prefix.bin",
        "after-prefix.bin",
        "bird-before.tsv",
        "bird-after.tsv",
    ):
        assert required in installer
    assert 'of="/dev/r${WHOLE}"' in installer
    assert "seek=\"$SECTOR_INDEX\" count=1" in installer
    for forbidden in ("s1", "s5", "s6", "/Volumes/BIRD/KERNEL", "rm -rf /Volumes"):
        assert forbidden not in installer

    if not PUBLICATION.is_dir():
        print("No-RAID6-benchmark pair tests: PASS (publication unavailable)")
        return
    subprocess.run(
        [sys.executable, str(VERIFIER), "--verify-output", str(PUBLICATION)],
        check=True,
    )
    with tempfile.TemporaryDirectory(prefix="bird-no-raid6-pair-test-") as temp:
        root = pathlib.Path(temp)
        cases = (
            ("candidate", "no-raid6-benchmark-pair.bin", "checksum mismatch"),
            ("prefix", "no-raid6-benchmark-pair-prefix-16m.bin", "checksum mismatch"),
            ("kernel", "KERNEL.lz4", "checksum mismatch"),
            (
                "source-authority",
                "source-kernel-irq-buttons-no-raid6-benchmark-lz4.tsv",
                "checksum mismatch",
            ),
        )
        for label, name, expected in cases:
            candidate = root / label
            shutil.copytree(PUBLICATION, candidate)
            corrupt(candidate / name)
            rejected(candidate, expected)
    print("No-RAID6-benchmark pair tests: PASS")


if __name__ == "__main__":
    main()
