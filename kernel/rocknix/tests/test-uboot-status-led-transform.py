#!/usr/bin/env python3
"""Host contracts for the fixed RG34XX-SP U-Boot green status LED."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-status-led.py"

UPSTREAM_DDR4_DEFCONFIG = b"""CONFIG_ARM=y
CONFIG_ARCH_SUNXI=y
CONFIG_DEFAULT_DEVICE_TREE="allwinner/sun50i-h700-anbernic-rg35xx-2024"
CONFIG_SPL=y
CONFIG_DRAM_SUNXI_DX_ODT=0x08080808
CONFIG_DRAM_SUNXI_DX_DRI=0x0e0e0e0e
CONFIG_DRAM_SUNXI_CA_DRI=0x0e0e
CONFIG_DRAM_SUNXI_ODT_EN=0x7887bbbb
CONFIG_DRAM_SUNXI_TPR2=0x1
CONFIG_DRAM_SUNXI_TPR6=0x40808080
CONFIG_DRAM_SUNXI_TPR10=0x402f6633
CONFIG_DRAM_SUNXI_TPR11=0x1b1f1e1c
CONFIG_DRAM_SUNXI_TPR12=0x06060606
CONFIG_DRAM_SUNXI_PHY_ADDR_MAP_1=y
CONFIG_MACH_SUN50I_H616=y
CONFIG_SUNXI_DRAM_H616_LPDDR4=y
CONFIG_DRAM_CLK=672
CONFIG_R_I2C_ENABLE=y
CONFIG_SPL_I2C=y
CONFIG_SPL_SYS_I2C_LEGACY=y
CONFIG_SYS_I2C_MVTWSI=y
CONFIG_SYS_I2C_SLAVE=0x7f
CONFIG_SYS_I2C_SPEED=400000
CONFIG_REGULATOR_AXP=y
CONFIG_AXP717_POWER=y
CONFIG_AXP_DCDC2_VOLT=940
CONFIG_AXP_DCDC3_VOLT=1100
CONFIG_EFI_LOADER=n
CONFIG_BOOTDELAY=0
CONFIG_LED_STATUS=y
CONFIG_LED_STATUS_GPIO=y
CONFIG_LED_STATUS0=y
CONFIG_LED_STATUS_BIT=267
CONFIG_LED_STATUS_STATE=2
"""


def load_transform():
    spec = importlib.util.spec_from_file_location("bird_uboot_status_led", TRANSFORM)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_rejected(module, source: bytes, diagnostic: str) -> None:
    try:
        module.transform(source)
    except SystemExit as error:
        assert diagnostic in str(error), str(error)
    else:
        raise AssertionError("changed U-Boot source authority was accepted")


def main() -> None:
    module = load_transform()
    assert module.ROCKNIX_COMMIT == "3e4ee5852e6ca5ea73a38369d2639fad2262648b"
    assert module.ROCKNIX_PACKAGE.endswith("/u-boot-DDR4")
    assert module.DEFCONFIG_NAME == "anbernic_rg35xx_h700_lpddr4_defconfig"
    assert module.sha256(UPSTREAM_DDR4_DEFCONFIG) == module.UPSTREAM_SHA256

    result = module.transform(UPSTREAM_DDR4_DEFCONFIG)
    assert module.sha256(result) == module.GREEN_SHA256
    assert result.count(b"CONFIG_LED_STATUS_BIT=268\n") == 1
    assert b"CONFIG_LED_STATUS_BIT=267\n" not in result
    assert len(result) == len(UPSTREAM_DDR4_DEFCONFIG)
    differences = [
        (index, before, after)
        for index, (before, after) in enumerate(zip(UPSTREAM_DDR4_DEFCONFIG, result))
        if before != after
    ]
    assert len(differences) == 1
    assert differences[0][1:] == (ord("7"), ord("8"))

    expect_rejected(
        module,
        UPSTREAM_DDR4_DEFCONFIG.replace(b"CONFIG_BOOTDELAY=0", b"CONFIG_BOOTDELAY=1"),
        "defconfig authority changed",
    )
    expect_rejected(module, result, "anchor authority changed")
    expect_rejected(
        module,
        UPSTREAM_DDR4_DEFCONFIG + module.RED_STATUS_LED,
        "anchor authority changed",
    )
    expect_rejected(
        module,
        UPSTREAM_DDR4_DEFCONFIG.replace(module.RED_STATUS_LED, b""),
        "anchor authority changed",
    )

    with tempfile.TemporaryDirectory(prefix="bird-uboot-led-test-") as directory:
        temporary = pathlib.Path(directory)
        source = temporary / module.DEFCONFIG_NAME
        output = temporary / "green.defconfig"
        source.write_bytes(UPSTREAM_DDR4_DEFCONFIG)
        subprocess.run(
            [sys.executable, str(TRANSFORM), str(source), str(output)], check=True
        )
        assert source.read_bytes() == UPSTREAM_DDR4_DEFCONFIG
        assert output.read_bytes() == result
        duplicate = subprocess.run(
            [sys.executable, str(TRANSFORM), str(source), str(output)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert duplicate.returncode != 0
        assert "refusing to replace output" in duplicate.stderr

    # If the sparse ROCKNIX source checkout is available, prove that the exact
    # pinned release commit still supplies both the package recipe and defconfig
    # this transform was reviewed against. The checkout itself remains untouched.
    rocknix = pathlib.Path(
        os.environ.get(
            "ROCKNIX_SOURCE",
            str(pathlib.Path.home() / "rocknix-distribution-20260701"),
        )
    )
    if (rocknix / ".git").is_dir():
        defconfig_path = (
            f"{module.ROCKNIX_PACKAGE}/sources/configs/{module.DEFCONFIG_NAME}"
        )
        pinned = subprocess.run(
            ["git", "-C", str(rocknix), "show", f"{module.ROCKNIX_COMMIT}:{defconfig_path}"],
            check=True,
            stdout=subprocess.PIPE,
        ).stdout
        assert pinned == UPSTREAM_DDR4_DEFCONFIG
        package = subprocess.run(
            [
                "git",
                "-C",
                str(rocknix),
                "show",
                f"{module.ROCKNIX_COMMIT}:{module.ROCKNIX_PACKAGE}/package.mk",
            ],
            check=True,
            stdout=subprocess.PIPE,
        ).stdout
        assert b'PKG_VERSION="v2026.01"\n' in package
        assert (
            b'PKG_UBOOT_CONFIG="anbernic_rg35xx_h700_lpddr4_defconfig"\n'
            in package
        )
        assert b'PKG_BL31="$(get_build_dir atf)/build/sun50i_h616/release/bl31.bin"\n' in package

    print("U-Boot status LED transform tests: PASS")


if __name__ == "__main__":
    main()
