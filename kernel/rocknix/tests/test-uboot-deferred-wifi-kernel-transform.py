#!/usr/bin/env python3
"""Focused exact-bound tests for the deferred-Wi-Fi kernel consumer."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import tarfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-deferred-wifi-kernel.py"
SOURCE = (
    pathlib.Path.home()
    / "rocknix-distribution-20260701/sources/u-boot-DDR4/u-boot-DDR4-v2026.01.tar.gz"
)


def load_transform():
    spec = importlib.util.spec_from_file_location("bird_deferred_wifi_bound", TRANSFORM)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    module = load_transform()
    assert module.LZ4_KERNEL_BYTES == 17_565_074
    assert module.LZ4_KERNEL_SIZE_HEX == "0x10c0592"
    assert int(module.LZ4_KERNEL_SIZE_HEX, 16) == module.LZ4_KERNEL_BYTES
    assert len(module.OLD_LIMIT) == len(module.NEW_LIMIT)

    try:
        module.transform(b"unreviewed")
    except SystemExit as error:
        assert "authority changed" in str(error)
    else:
        raise AssertionError("unreviewed source was accepted")

    if SOURCE.is_file():
        with tarfile.open(SOURCE) as archive:
            handle = archive.extractfile(
                "u-boot-2026.01/include/configs/sunxi-common.h"
            )
            assert handle is not None
            source = handle.read()
        result = module.transform(source)
        assert result.count(module.NEW_LIMIT) == 1
        assert module.OLD_LIMIT not in result
        try:
            module.transform(result)
        except SystemExit as error:
            assert "authority changed" in str(error)
        else:
            raise AssertionError("already transformed source was accepted")

    print("U-Boot deferred-Wi-Fi kernel-bound tests: PASS")


if __name__ == "__main__":
    main()
