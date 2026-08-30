#!/usr/bin/env python3
"""Focused host contract for the fixed RG34XX-SP U-Boot command closure."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import tarfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/projects/ROCKNIX/devices/H700/"
    "packages/u-boot-DDR4/sources/configs/anbernic_rg35xx_h700_lpddr4_defconfig"
)
UBOOT_SOURCE = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/sources/u-boot-DDR4/"
    "u-boot-DDR4-v2026.01.tar.gz"
)


def load(name: str):
    path = ROOT / f"kernel/rocknix/{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def rejected(function) -> None:
    try:
        function()
    except SystemExit:
        return
    raise AssertionError("changed fixed-command-closure authority was accepted")


def archive_bytes(archive: tarfile.TarFile, name: str) -> bytes:
    member = archive.extractfile(f"u-boot-2026.01/{name}")
    assert member is not None
    return member.read()


def main() -> None:
    env = load("transform-uboot-environment-nowhere")
    direct = load("transform-uboot-direct-extlinux")
    no_clear = load("transform-uboot-no-heap-clear")
    fast = load("transform-uboot-fast-init")
    inplace = load("transform-uboot-inplace-handoff")
    simple = load("transform-uboot-simple-parser")
    fixed = load("transform-uboot-fixed-read-path")
    closure = load("transform-uboot-fixed-command-closure")

    if not SOURCE.is_file():
        print("U-Boot fixed-command-closure transform tests: PASS (pinned source unavailable)")
        return
    source = fast.transform(no_clear.transform(direct.transform(env.transform(SOURCE.read_bytes()))))
    inplace_config, environment = inplace.transform(source)
    assert environment == inplace.ENVIRONMENT
    simple_config = simple.transform(inplace_config)
    before = fixed.transform(simple_config)
    result = closure.transform(before)
    assert closure.sha256(before) == closure.SOURCE_SHA256
    assert closure.sha256(result) == closure.RESULT_SHA256
    assert result.endswith(closure.POLICY)

    for mutation in (
        before + b"# drift\n",
        before + closure.POLICY,
        before.replace(b"CONFIG_NO_NET=y\n", b"# CONFIG_NO_NET is not set\n"),
    ):
        rejected(lambda mutation=mutation: closure.transform(mutation))

    for retained in (
        b'CONFIG_BOOTCOMMAND="sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux.conf"\n',
        b"CONFIG_CMD_SYSBOOT=y\n",
        b"CONFIG_FS_FAT=y\n",
        b"CONFIG_DOS_PARTITION=y\n",
        b"CONFIG_SUPPORT_RAW_INITRD=y\n",
        b"CONFIG_LZ4=y\n",
    ):
        assert result.count(retained) == 1

    if UBOOT_SOURCE.is_file():
        with tarfile.open(UBOOT_SOURCE, "r:gz") as archive:
            command_kconfig = archive_bytes(archive, "cmd/Kconfig")
        assert b"config CMD_SYSBOOT\n\tbool \"sysboot\"\n\tselect PXE_UTILS" in command_kconfig
        assert b"config CMD_BOOTI" in command_kconfig
        assert b"select LIB_BOOTI" in command_kconfig
        assert b"select LIB_BOOTM" in command_kconfig
        assert b"config BOOTM_LINUX" in command_kconfig
        assert b"depends on CMD_BOOTM || CMD_BOOTZ || CMD_BOOTI" in command_kconfig

    print("U-Boot fixed-command-closure transform tests: PASS")


if __name__ == "__main__":
    main()
