#!/usr/bin/env python3
"""Focused contract for the fixed mmc0p1 birdOS extlinux boot command."""

from __future__ import annotations

import importlib.util
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-direct-extlinux.py"
ENV_TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-environment-nowhere.py"
SHIPPING = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/projects/ROCKNIX/devices/H700/"
    "packages/u-boot-DDR4/sources/configs/anbernic_rg35xx_h700_lpddr4_defconfig"
)


def load(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    direct = load(TRANSFORM, "bird_direct_extlinux")
    env = load(ENV_TRANSFORM, "bird_env_nowhere")
    if not SHIPPING.is_file():
        print("SKIP: pinned ROCKNIX defconfig is unavailable")
        return
    source = env.transform(SHIPPING.read_bytes())
    result = direct.transform(source)
    assert result == source + direct.DIRECT_BOOT
    assert direct.sha256(result) == direct.RESULT_SHA256
    assert result.count(b"CONFIG_BOOTCOMMAND=") == 1
    assert b"mmc dev 0; sysboot mmc 0:1 any ${scriptaddr} /extlinux/extlinux.conf" in result
    for forbidden in (b"pxe", b"dhcp", b"boot.scr", b"mmc 1", b"/boot/"):
        assert forbidden not in direct.DIRECT_BOOT
    try:
        direct.transform(source + b"# drift\n")
    except SystemExit as error:
        assert "authority changed" in str(error)
    else:
        raise AssertionError("changed direct-extlinux authority was accepted")
    with tempfile.TemporaryDirectory() as temporary:
        output = pathlib.Path(temporary) / "direct.defconfig"
        output.write_bytes(result)
        assert output.read_bytes() == result
    print("U-Boot direct-extlinux transform tests: PASS")


if __name__ == "__main__":
    main()
