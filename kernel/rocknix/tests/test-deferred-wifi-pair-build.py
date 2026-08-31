#!/usr/bin/env python3
"""Identity and corruption gates for the deferred-Wi-Fi boot pair."""

from __future__ import annotations

import importlib.util
import pathlib
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
VERIFIER = ROOT / "kernel/rocknix/verify-deferred-wifi-pair-build.py"
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-deferred-wifi-kernel.py"
BUILDER = ROOT / "kernel/rocknix/build-no-raid6-benchmark-pair.sh"
INSTALLER = ROOT / "firmware/mac-install-no-raid6-benchmark-pair.sh"
PUBLICATION = ROOT / "kernel/work/bird-deferred-wifi-pair-20260830-v3"


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


def corrupt(path: pathlib.Path) -> None:
    data = bytearray(path.read_bytes())
    data[0] ^= 1
    path.write_bytes(data)


def main() -> None:
    transform = load("bird_deferred_wifi_transform", TRANSFORM)
    assert transform.LZ4_KERNEL_BYTES == 17_565_074
    assert transform.LZ4_KERNEL_SIZE_HEX == "0x10c0592"

    verifier = load("bird_deferred_wifi_verifier", VERIFIER)
    assert verifier.EXPECTED_STAGE11_DIFF == {
        284_511: (ord("6"), ord("5")),
        284_512: (ord("a"), ord("9")),
        284_513: (ord("0"), ord("2")),
    }
    assert verifier.KERNEL_SHA256 == (
        "efc9de3ca0ee03191f2df48ed87467f2a295537dd5ef09cf2932500b0a46f8e4"
    )
    assert verifier.LZ4_SHA256 == (
        "05f3b40c4d1c2b4255745b9814052b9e1d091f22f9bd1499a5841b41b24771bc"
    )

    builder = BUILDER.read_text(encoding="utf-8")
    for required in (
        "BIRD_BOOT_PAIR_PROFILE",
        "deferred-wifi)",
        "rocknix-source-deferred-wifi-a/build/Image",
        "transform-uboot-deferred-wifi-kernel.py",
        "verify-deferred-wifi-pair-build.py",
        'require_hash "$KERNEL_A" "$KERNEL_SHA"',
        'require_hash "$BOUND_TRANSFORM" "$BOUND_TRANSFORM_SHA"',
        'require_hash "$VERIFIER" "$VERIFIER_SHA"',
    ):
        assert required in builder
    for forbidden in ("diskutil", "/dev/disk", "/dev/rdisk", "mac-install"):
        assert forbidden not in builder

    installer = INSTALLER.read_text(encoding="utf-8")
    for required in (
        "BIRD_BOOT_PAIR_PROFILE",
        "deferred-wifi)",
        "--restore-stage11",
        "stage11-no-raid6-benchmark-prefix-16m.bin",
        "deferred-wifi-pair-prefix-16m.bin",
        "stage11-no-raid6-benchmark.bin",
        "deferred-wifi-pair.bin",
        "SECTOR_INDEX=571",
        'of="/dev/r${WHOLE}"',
        "recover_original",
    ):
        assert required in installer
    for forbidden in ("/Volumes/BIRD/KERNEL", "s1", "s5", "s6"):
        assert forbidden not in installer

    if not PUBLICATION.is_dir():
        print("Deferred-Wi-Fi pair tests: PASS (publication unavailable)")
        return
    subprocess.run(
        [sys.executable, str(VERIFIER), "--verify-output", str(PUBLICATION)],
        check=True,
    )
    with tempfile.TemporaryDirectory(prefix="bird-deferred-wifi-pair-test-") as temp:
        root = pathlib.Path(temp)
        cases = (
            ("candidate", "deferred-wifi-pair.bin"),
            ("prefix", "deferred-wifi-pair-prefix-16m.bin"),
            ("kernel", "KERNEL.lz4"),
            (
                "source-authority",
                "source-kernel-irq-buttons-no-raid6-deferred-wifi-lz4.tsv",
            ),
        )
        for label, name in cases:
            candidate = root / label
            shutil.copytree(PUBLICATION, candidate)
            corrupt(candidate / name)
            rejected(candidate, "checksum mismatch")
    print("Deferred-Wi-Fi pair tests: PASS")


if __name__ == "__main__":
    main()
