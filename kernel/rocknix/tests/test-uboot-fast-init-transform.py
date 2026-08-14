#!/usr/bin/env python3
"""Focused source gate for the fixed RG34XX-SP U-Boot initialization path."""

from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/projects/ROCKNIX/devices/H700/"
    "packages/u-boot-DDR4/sources/configs/anbernic_rg35xx_h700_lpddr4_defconfig"
)


def load(name: str):
    path = ROOT / f"kernel/rocknix/{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    env = load("transform-uboot-environment-nowhere")
    direct = load("transform-uboot-direct-extlinux")
    no_clear = load("transform-uboot-no-heap-clear")
    fast = load("transform-uboot-fast-init")
    if not SOURCE.is_file():
        print("U-Boot fast-init transform tests: PASS (pinned source unavailable)")
        return

    source = no_clear.transform(direct.transform(env.transform(SOURCE.read_bytes())))
    result = fast.transform(source)
    assert hashlib.sha256(result).hexdigest() == fast.RESULT_SHA256
    assert result.count(b"CONFIG_BOOTDELAY=-2\n") == 1
    assert b"CONFIG_BOOTDELAY=0\n" not in result
    assert result.count(fast.NEW_BOOT) == 1 and fast.OLD_BOOT not in result
    assert result.endswith(fast.POLICY)
    assert b"CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT=y\n" in result
    assert b"# CONFIG_SYS_MALLOC_CLEAR_ON_INIT is not set\n" in result
    assert b"CONFIG_NO_NET=y\n" in result
    assert b"# CONFIG_BOOTSTD is not set\n" in result
    assert b"# CONFIG_ENV_IS_IN_FAT is not set\n" in result

    for mutation in (
        source + b"# drift\n",
        source.replace(fast.OLD_DELAY, b"CONFIG_BOOTDELAY=1\n"),
        source.replace(fast.OLD_BOOT, fast.NEW_BOOT),
    ):
        try:
            fast.transform(mutation)
        except SystemExit:
            pass
        else:
            raise AssertionError("changed fast-init authority was accepted")

    with tempfile.TemporaryDirectory() as directory:
        source_path = pathlib.Path(directory) / "source"
        output_path = pathlib.Path(directory) / "output"
        source_path.write_bytes(source)
        output_path.write_bytes(result)
        assert source_path.read_bytes() == source
        assert output_path.read_bytes() == result

    uboot = pathlib.Path(
        "/Users/dani/rocknix-distribution-20260701/build.ROCKNIX-H700.aarch64/"
        "build/u-boot-DDR4-v2026.01"
    )
    if uboot.is_dir():
        helper_path = ROOT / "kernel/rocknix/tests/test-uboot-environment-nowhere-transform.py"
        spec = importlib.util.spec_from_file_location("bird_env_test_helpers_fast", helper_path)
        assert spec and spec.loader
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        with tempfile.TemporaryDirectory(prefix="bird-uboot-fast-init-") as directory:
            temporary = pathlib.Path(directory)
            conf = helper.build_kconfig_conf(uboot, temporary / "host")
            source_path = temporary / "source.defconfig"
            result_path = temporary / "result.defconfig"
            source_path.write_bytes(source)
            result_path.write_bytes(result)
            before = helper.configure(uboot, conf, temporary / "before", source_path)
            after = helper.configure(uboot, conf, temporary / "after", result_path)
            changed = {
                key: (before.get(key, "n"), after.get(key, "n"))
                for key in before.keys() | after.keys()
                if before.get(key, "n") != after.get(key, "n")
            }
            expected_changed = {
                "CONFIG_ARP_TIMEOUT", "CONFIG_BOOTCOMMAND", "CONFIG_BOOTDELAY",
                "CONFIG_BOOTDEV_ETH", "CONFIG_BOOTMETH_EXTLINUX",
                "CONFIG_BOOTMETH_EXTLINUX_PXE", "CONFIG_BOOTMETH_GLOBAL",
                "CONFIG_BOOTMETH_VBE", "CONFIG_BOOTMETH_VBE_REQUEST",
                "CONFIG_BOOTMETH_VBE_SIMPLE", "CONFIG_BOOTMETH_VBE_SIMPLE_OS",
                "CONFIG_BOOTP_BOOTPATH", "CONFIG_BOOTP_DNS",
                "CONFIG_BOOTP_GATEWAY", "CONFIG_BOOTP_HOSTNAME",
                "CONFIG_BOOTP_MAX_ROOT_PATH_LEN", "CONFIG_BOOTP_PXE",
                "CONFIG_BOOTP_PXE_DHCP_OPTION", "CONFIG_BOOTP_SUBNETMASK",
                "CONFIG_BOOTP_VCI_STRING", "CONFIG_BOOTSTD",
                "CONFIG_CMD_BOOTFLOW", "CONFIG_CMD_BOOTP", "CONFIG_CMD_DHCP",
                "CONFIG_CMD_MII", "CONFIG_CMD_NET", "CONFIG_CMD_PING",
                "CONFIG_CMD_PXE", "CONFIG_CMD_TFTPBOOT",
                "CONFIG_DHCP_PXE_CLIENTARCH", "CONFIG_DM_ETH", "CONFIG_EVENT",
                "CONFIG_NET", "CONFIG_NETDEVICES", "CONFIG_NET_RETRY_COUNT",
                "CONFIG_NET_TFTP_VARS", "CONFIG_NO_NET", "CONFIG_REGEX",
                "CONFIG_SERVERIP_FROM_PROXYDHCP_DELAY_MS", "CONFIG_SPL_CRC8",
                "CONFIG_TFTP_BLOCKSIZE", "CONFIG_TFTP_WINDOWSIZE",
            }
            assert set(changed) == expected_changed
            assert after["CONFIG_BOOTDELAY"] == "-2"
            assert after["CONFIG_BOOTCOMMAND"] == '"sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux.conf"'
            assert after["CONFIG_NO_NET"] == "y"
            for removed in (
                "CONFIG_NET", "CONFIG_CMD_DHCP", "CONFIG_CMD_PXE",
                "CONFIG_CMD_TFTPBOOT", "CONFIG_DM_ETH", "CONFIG_BOOTDEV_ETH",
                "CONFIG_BOOTSTD", "CONFIG_CMD_BOOTFLOW",
            ):
                assert after.get(removed, "n") == "n", removed
            for retained in (
                "CONFIG_CMD_SYSBOOT", "CONFIG_PXE_UTILS", "CONFIG_MENU",
                "CONFIG_FS_FAT", "CONFIG_MMC", "CONFIG_MMC_SUNXI",
                "CONFIG_CMD_BOOTI", "CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT",
            ):
                assert after[retained] == "y", retained
            assert after["CONFIG_SYS_MALLOC_CLEAR_ON_INIT"] == "n"

    print("U-Boot fast-init transform tests: PASS")


if __name__ == "__main__":
    main()
