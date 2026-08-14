#!/usr/bin/env python3
"""Focused host gate for the RG34XX-SP in-place initrd/DTB handoff."""

from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[3]
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-inplace-handoff.py"
SOURCE = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/projects/ROCKNIX/devices/H700/"
    "packages/u-boot-DDR4/sources/configs/"
    "anbernic_rg35xx_h700_lpddr4_defconfig"
)
UBOOT = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/build.ROCKNIX-H700.aarch64/"
    "build/u-boot-DDR4-v2026.01"
)
FAST_CONFIG = ROOT / "kernel/work/bird-uboot-fast-init-20260701/fast-init.config"
FAST_UBOOT = ROOT / "kernel/work/bird-uboot-fast-init-20260701/fast-init-uboot.bin"
EXTLINUX = pathlib.Path("/Volumes/BIRD/extlinux/extlinux.conf")
RELEASE = pathlib.Path("/Volumes/BIRD/bird-releases/dev-current")

PINNED_SOURCE_FILES = {
    "Makefile": "1aa8709966a310f6bb69aae4630d0234201a7ef369c8e1ec102b8c05197cbf17",
    "env/Kconfig": "5ddbf1af7d1651e3969820d9e54f5e6456c140ac1faa327734a8f9cf963c304a",
    "include/env_default.h": "95b92ce40032d31cb5da67e7415e1ed9cbaf99d4dc620a7c0ad313d5b7119e01",
    "include/configs/sunxi-common.h": "301d6c8db012d13918fee5cbf4251fdffd67c55b25d483a423b502c4a2240701",
    "boot/image-board.c": "43589f6afd12edc3a013a6248b3d78c8989d41c641a96fc319ced608be057fec",
    "boot/image-fdt.c": "61d5940f4de57028a54fc4160b4c2c7296530d39f5ae97c0ecf90af2ce3459c0",
    "boot/pxe_utils.c": "2c60a9b5e92c844089783e9431a97d2b50282339a4069c7bfa4773251f997580",
    "boot/Kconfig": "f37b8c429f663834ce032f3ae354260c96cc6a00ac8c0ace51c7fa1a249a8062",
}

# Exact accepted dev-current files which extlinux loads at these fixed
# Allwinner ARM64 default-environment addresses.
KERNEL_BYTES = 30_926_856
KERNEL_SHA256 = "cad7ad8437d0a7de0d819846b12fdf83078f5878313704d0de79274431ec9d64"
INITRD_BYTES = 603_487
INITRD_SHA256 = "0403ec2d90fbf0b2b3f6704a317049c9b8596b0bf2ebe2b26ef353f9f3cb4c71"
DTB_BYTES = 49_010
DTB_SHA256 = "f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31"
EXTLINUX_BYTES = 279
EXTLINUX_SHA256 = "3402bbf8cf1a3f968ad4df3837182ccae059408d1bfd55dc396bf4b10b1f5152"
FAST_CONFIG_SHA256 = "34d359c61ede0bb54361b5f092cc9fa77fafdd3ed10aeee932622e290ad68971"
FAST_UBOOT_BYTES = 437_168
FAST_UBOOT_SHA256 = "9d557ccc6efb40b4e4f3daeea648f51ae313d6bec9c342d41abf4b8fdefbeb89"

KERNEL_ADDR = 0x4008_0000
FDT_ADDR = 0x4FA0_0000
FDT_PAD = 0x3000
SCRIPT_ADDR = 0x4FC0_0000
PXE_ADDR = 0x4FD0_0000
OVERLAY_ADDR = 0x4FE0_0000
INITRD_ADDR = 0x4FF0_0000
MINIMUM_DRAM_END = 0x6000_0000  # sunxi ARM64 contract: at least 512 MiB


def load(name: str, path: pathlib.Path):
    specification = importlib.util.spec_from_file_location(name, path)
    assert specification is not None and specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def exact_file(path: pathlib.Path, size: int, sha256: str) -> bytes:
    assert path.is_file() and not path.is_symlink(), path
    data = path.read_bytes()
    assert len(data) == size, path
    assert digest(data) == sha256, path
    return data


def reject(function, diagnostic: str) -> None:
    try:
        function()
    except SystemExit as error:
        assert diagnostic in str(error), str(error)
    else:
        raise AssertionError("changed in-place handoff authority was accepted")


def parse_config(data: bytes) -> dict[bytes, bytes]:
    values: dict[bytes, bytes] = {}
    for line in data.splitlines():
        if line.startswith(b"CONFIG_"):
            key, value = line.split(b"=", 1)
            values[key] = value
        elif line.startswith(b"# CONFIG_") and line.endswith(b" is not set"):
            values[line[2:-11]] = b"n"
    return values


def accepted_fast_defconfig() -> bytes:
    env = load(
        "bird_inplace_env",
        ROOT / "kernel/rocknix/transform-uboot-environment-nowhere.py",
    )
    direct = load(
        "bird_inplace_direct",
        ROOT / "kernel/rocknix/transform-uboot-direct-extlinux.py",
    )
    no_clear = load(
        "bird_inplace_no_clear",
        ROOT / "kernel/rocknix/transform-uboot-no-heap-clear.py",
    )
    fast = load(
        "bird_inplace_fast",
        ROOT / "kernel/rocknix/transform-uboot-fast-init.py",
    )
    return fast.transform(no_clear.transform(direct.transform(env.transform(SOURCE.read_bytes()))))


def verify_source_semantics() -> None:
    for relative, expected in PINNED_SOURCE_FILES.items():
        assert digest((UBOOT / relative).read_bytes()) == expected, relative

    makefile = (UBOOT / "Makefile").read_bytes()
    kconfig = (UBOOT / "env/Kconfig").read_bytes()
    defaults = (UBOOT / "include/env_default.h").read_bytes()
    sunxi = (UBOOT / "include/configs/sunxi-common.h").read_bytes()
    initrd = (UBOOT / "boot/image-board.c").read_bytes()
    fdt = (UBOOT / "boot/image-fdt.c").read_bytes()
    pxe = (UBOOT / "boot/pxe_utils.c").read_bytes()

    # CONFIG_ENV_SOURCE_FILE selects one board/sunxi/*.env, env2string turns
    # it into CONFIG_EXTRA_ENV_TEXT, and env_default compiles it before the
    # unchanged sunxi CFG_EXTRA_ENV_SETTINGS.
    for anchor in (
        b"ENV_DIR := $(srctree)/board/$(BOARDDIR)",
        b'ENV_SOURCE_FILE := $(CONFIG_ENV_SOURCE_FILE:"%"=%)',
        b"ENV_FILE_CFG := $(ENV_DIR)/$(ENV_SOURCE_FILE).env",
        b"ENV_FILE := $(if $(ENV_SOURCE_FILE),$(ENV_FILE_CFG),$(wildcard $(ENV_FILE_BOARD)))",
        b"awk -f $(srctree)/scripts/env2string.awk $< >$@",
    ):
        assert makefile.count(anchor) == 1, anchor
    assert b"board/<vendor>/<board>/<CONFIG_ENV_SOURCE_FILE>.env" in kconfig
    assert defaults.index(b"CONFIG_EXTRA_ENV_TEXT") < defaults.index(
        b"CFG_EXTRA_ENV_SETTINGS"
    )
    assert sunxi.count(b"CFG_EXTRA_ENV_SETTINGS") == 1
    assert b"fdt_high=" not in sunxi and b"initrd_high=" not in sunxi

    # All-ones is the explicit in-place value for both 64-bit consumers. The
    # loaded ranges are still reserved through LMB; the initrd is not copied,
    # and FDT total size grows in its existing padded destination.
    for anchor in (
        b' s = env_get("initrd_high");'.strip(),
        b"if (initrd_high == ~0)",
        b"initrd_copy_to_ram = 0;",
        b"*initrd_start = rd_data;",
        b"LMB_MEM_ALLOC_ADDR",
    ):
        assert anchor in initrd, anchor
    for anchor in (
        b'fdt_high = env_get("fdt_high");',
        b"if (high_addr == ~0UL)",
        b"of_start = fdt_blob;",
        b"disable_relocation = 1;",
        b"fdt_set_totalsize(of_start, of_len);",
    ):
        assert anchor in fdt, anchor
    for anchor in (
        b'get_relfile_envaddr(ctx, label->initrd, "ramdisk_addr_r"',
        b'bootm_argv[3] = env_get("fdt_addr_r");',
    ):
        assert anchor in pxe, anchor


def verify_compiled_environment(
    helper, base_defconfig: bytes, candidate_defconfig: bytes, environment: bytes
) -> None:
    with tempfile.TemporaryDirectory(prefix="bird-inplace-kconfig-") as directory:
        temporary = pathlib.Path(directory)
        conf = helper.build_kconfig_conf(UBOOT, temporary / "host")
        before_path = temporary / "before.defconfig"
        after_path = temporary / "after.defconfig"
        before_path.write_bytes(base_defconfig)
        after_path.write_bytes(candidate_defconfig)
        before = helper.configure(UBOOT, conf, temporary / "before", before_path)
        after = helper.configure(UBOOT, conf, temporary / "after", after_path)
        changed = {
            key: (before.get(key, "n"), after.get(key, "n"))
            for key in before.keys() | after.keys()
            if before.get(key, "n") != after.get(key, "n")
        }
        assert changed == {
            "CONFIG_ENV_SOURCE_FILE": ('""', '"bird-rg34xx-sp-handoff"')
        }
        assert after["CONFIG_ENV_IS_NOWHERE"] == "y"
        assert after["CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE"] == "n"
        assert after["CONFIG_DEFAULT_ENV_IS_RW"] == "n"

        generated = subprocess.run(
            ["awk", "-f", str(UBOOT / "scripts/env2string.awk")],
            input=environment,
            check=True,
            stdout=subprocess.PIPE,
        ).stdout
        assert generated == (
            b'#define CONFIG_EXTRA_ENV_TEXT "'
            b'initrd_high=ffffffffffffffff\\0'
            b'fdt_high=ffffffffffffffff\\0"\n'
        )


def verify_exact_layout() -> None:
    kernel = exact_file(RELEASE / "KERNEL", KERNEL_BYTES, KERNEL_SHA256)
    initrd = exact_file(RELEASE / "bird-initramfs.cpio.gz", INITRD_BYTES, INITRD_SHA256)
    dtb = exact_file(RELEASE / "dtb.img", DTB_BYTES, DTB_SHA256)
    extlinux = exact_file(EXTLINUX, EXTLINUX_BYTES, EXTLINUX_SHA256)
    del kernel, initrd, dtb, extlinux
    selector = EXTLINUX.read_text()
    assert selector.count("LINUX /bird-releases/dev-current/KERNEL") == 1
    assert selector.count("INITRD /bird-releases/dev-current/bird-initramfs.cpio.gz") == 1
    assert selector.count("FDT /bird-releases/dev-current/dtb.img") == 1

    ranges = (
        ("kernel", KERNEL_ADDR, KERNEL_BYTES),
        ("fdt-with-pad", FDT_ADDR, DTB_BYTES + FDT_PAD),
        ("selector", SCRIPT_ADDR, EXTLINUX_BYTES),
        ("initrd", INITRD_ADDR, INITRD_BYTES),
    )
    for (_, start, size), (_, next_start, _) in zip(ranges, ranges[1:]):
        assert start + size < next_start
    assert FDT_ADDR + DTB_BYTES + FDT_PAD < SCRIPT_ADDR
    assert SCRIPT_ADDR + EXTLINUX_BYTES < PXE_ADDR < OVERLAY_ADDR < INITRD_ADDR
    assert INITRD_ADDR + INITRD_BYTES < MINIMUM_DRAM_END

    # Exact host-side traffic removed at handoff: one initrd memmove plus one
    # FDT open/copy sized to its configured padding. This is not device timing.
    assert INITRD_BYTES + DTB_BYTES + FDT_PAD == 664_785


def main() -> None:
    handoff = load("bird_inplace_handoff", TRANSFORM)
    if not SOURCE.is_file() or not UBOOT.is_dir():
        print("U-Boot in-place handoff transform tests: PASS (pinned source unavailable)")
        return

    source = accepted_fast_defconfig()
    assert digest(source) == handoff.SOURCE_SHA256
    result, environment = handoff.transform(source)
    assert digest(result) == handoff.RESULT_SHA256
    assert digest(environment) == handoff.ENV_SHA256
    assert result == source + handoff.ENV_SELECTION
    assert environment == handoff.ENVIRONMENT
    assert environment.splitlines() == [
        b"fdt_high=ffffffffffffffff",
        b"initrd_high=ffffffffffffffff",
    ]
    assert parse_config(result)[b"CONFIG_ENV_SOURCE_FILE"] == (
        b'"bird-rg34xx-sp-handoff"'
    )

    for mutation in (
        source + b"# drift\n",
        source + b'CONFIG_ENV_SOURCE_FILE="other"\n',
        source + b"fdt_high=ffffffffffffffff\n",
        result,
    ):
        reject(lambda mutation=mutation: handoff.transform(mutation), "authority")

    with tempfile.TemporaryDirectory(prefix="bird-inplace-transform-") as directory:
        temporary = pathlib.Path(directory)
        source_path = temporary / "fast.defconfig"
        config_path = temporary / "handoff.defconfig"
        env_path = temporary / handoff.ENV_FILENAME
        source_path.write_bytes(source)
        subprocess.run(
            [sys.executable, str(TRANSFORM), str(source_path), str(config_path), str(env_path)],
            check=True,
        )
        assert config_path.read_bytes() == result
        assert env_path.read_bytes() == environment
        duplicate = subprocess.run(
            [sys.executable, str(TRANSFORM), str(source_path), str(config_path), str(env_path)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert duplicate.returncode != 0
        assert "refusing to replace" in duplicate.stderr

        wrong_env = temporary / "wrong.env"
        reject(
            lambda: handoff._publish_pair(
                temporary / "wrong.defconfig", wrong_env, result, environment
            ),
            "must be named",
        )
        assert not (temporary / "wrong.defconfig").exists()
        assert not wrong_env.exists()

        failure_directory = temporary / "failed-pair"
        failure_directory.mkdir()
        failed_config = failure_directory / "failed.defconfig"
        failed_env = failure_directory / handoff.ENV_FILENAME
        real_link = os.link
        links = 0

        def fail_activation(source, destination):
            nonlocal links
            links += 1
            if links == 2:
                raise OSError("simulated activation failure")
            real_link(source, destination)

        try:
            with mock.patch.object(handoff.os, "link", side_effect=fail_activation):
                handoff._publish_pair(failed_config, failed_env, result, environment)
        except OSError as error:
            assert "simulated activation failure" in str(error)
        else:
            raise AssertionError("simulated paired-output failure was accepted")
        assert not failed_config.exists()
        assert not failed_env.exists()
        assert not list(failure_directory.glob(".*.bird-new.*"))

    verify_source_semantics()
    helper = load(
        "bird_inplace_helpers",
        ROOT / "kernel/rocknix/tests/test-uboot-environment-nowhere-transform.py",
    )
    verify_compiled_environment(helper, source, result, environment)

    exact_file(FAST_CONFIG, FAST_CONFIG.stat().st_size, FAST_CONFIG_SHA256)
    fast_binary = exact_file(FAST_UBOOT, FAST_UBOOT_BYTES, FAST_UBOOT_SHA256)
    assert fast_binary.count(b"fdt_high=") == 0
    assert fast_binary.count(b"initrd_high=") == 0
    verify_exact_layout()

    print("U-Boot in-place handoff transform tests: PASS")


if __name__ == "__main__":
    main()
