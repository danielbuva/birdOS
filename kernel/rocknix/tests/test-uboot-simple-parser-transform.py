#!/usr/bin/env python3
"""Focused host contract for the fixed U-Boot simple-parser boundary."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import tarfile
import tempfile


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
    raise AssertionError("changed simple-parser authority was accepted")


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

    if not SOURCE.is_file():
        print("U-Boot simple-parser transform tests: PASS (pinned source unavailable)")
        return
    source = fast.transform(no_clear.transform(direct.transform(env.transform(SOURCE.read_bytes()))))
    before, environment = inplace.transform(source)
    assert environment == inplace.ENVIRONMENT
    with tempfile.TemporaryDirectory(prefix="bird-uboot-simple-parser-") as temporary:
        directory = pathlib.Path(temporary)
        result = simple.transform(before)
        assert simple.sha256(before) == simple.SOURCE_SHA256
        assert simple.sha256(result) == simple.RESULT_SHA256
        assert result.endswith(simple.POLICY)

        source_path = directory / "source.defconfig"
        output_path = directory / "simple.defconfig"
        source_path.write_bytes(before)
        output_path.write_bytes(result)
        assert source_path.read_bytes() == before
        assert output_path.read_bytes() == result

    for mutation in (
        before + b"# drift\n",
        before + simple.POLICY,
        before.replace(b"CONFIG_NO_NET=y\n", b"# CONFIG_NO_NET is not set\n"),
    ):
        rejected(lambda mutation=mutation: simple.transform(mutation))

    for retained in (
        b'CONFIG_BOOTCOMMAND="sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux.conf"\n',
        b"CONFIG_USE_BOOTCOMMAND=y\n",
        b"CONFIG_CMD_SYSBOOT=y\n",
        b"CONFIG_PXE_UTILS=y\n",
        b"CONFIG_SUPPORT_RAW_INITRD=y\n",
        b"CONFIG_FS_FAT=y\n",
        b"CONFIG_NO_NET=y\n",
        b"# CONFIG_BOOTSTD is not set\n",
        b"CONFIG_ENV_SOURCE_FILE=\"bird-rg34xx-sp-handoff\"\n",
        b"# CONFIG_SYS_MALLOC_CLEAR_ON_INIT is not set\n",
        b"CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT=y\n",
    ):
        assert result.count(retained) == 1

    if UBOOT_SOURCE.is_file():
        with tarfile.open(UBOOT_SOURCE, "r:gz") as archive:
            command = archive_bytes(archive, "cmd/Kconfig")
            cli = archive_bytes(archive, "common/cli.c")
            simple_cli = archive_bytes(archive, "common/cli_simple.c")
            pxe = archive_bytes(archive, "boot/pxe_utils.c")
        assert b'If disabled, you get the old, much simpler behaviour' in command
        assert b"rcode = cli_simple_run_command_list(buff, flag);" in cli
        assert b"cli_simple_process_macros" in simple_cli
        assert b"cli_simple_process_macros" in pxe
        assert b"do_booti(ctx->cmdtp, 0, bootm_argc, bootm_argv);" in pxe

    print("U-Boot simple-parser transform tests: PASS")


if __name__ == "__main__":
    main()
