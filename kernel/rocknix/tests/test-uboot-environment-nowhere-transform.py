#!/usr/bin/env python3
"""Host contracts for the isolated U-Boot nowhere-environment transform."""

from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-environment-nowhere.py"

GREEN_DDR4_DEFCONFIG = b"""CONFIG_ARM=y
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

PINNED_UBOOT_FILES = {
    "arch/arm/Kconfig": "0023dcdc63eef1c94cbe03449649d96e7a2dc585ae59f026dd88d54a0b28416a",
    "boot/Kconfig": "f37b8c429f663834ce032f3ae354260c96cc6a00ac8c0ace51c7fa1a249a8062",
    "cmd/Kconfig": "7ef1928259e2ee805b365beed3e25c1145b9c121c758ddefffc38f68982c6a75",
    "drivers/mmc/Kconfig": "5d945aafbba9d657d8885ff24f39d398caed54e6277b741669b9a7f883cc6784",
    "env/Kconfig": "5ddbf1af7d1651e3969820d9e54f5e6456c140ac1faa327734a8f9cf963c304a",
    "env/Makefile": "273a62c4e2c8724cc510fc8fbc9261dda4968c6ed363b4ef2fd0a9824ae0c71a",
    "env/fat.c": "d91bde9a4cecfeeb397c326440f0703480df3039d7e25a8f7a356bc7da7beeda",
    "env/nowhere.c": "05518d0d3bbba3ce68082c48aaceb3f9ec35890ec48a1964686c19ad68b52359",
    "fs/fat/Kconfig": "f668fbe8f94933d63ee616e939ded1726e173d793a927e7788baa4533abe5899",
    "board/sunxi/board.c": "3dd7a998c141605030b6aa63b50e8fa18fb8ee54a01cd61cd160d7ed46b7089b",
    "include/env_default.h": "95b92ce40032d31cb5da67e7415e1ed9cbaf99d4dc620a7c0ad313d5b7119e01",
    "include/config_distro_bootcmd.h": (
        "85fa628abdce85e287021e5cbfe0f17092ab9aaed3692abbe3f7cd99ae5cd0db"
    ),
    "include/configs/sunxi-common.h": (
        "301d6c8db012d13918fee5cbf4251fdffd67c55b25d483a423b502c4a2240701"
    ),
}

PINNED_KCONFIG_HOST_FILES = {
    "scripts/kconfig/conf.c": (
        "20e89aa762c1ef02a526318a406d75fed91212bee94a69167cf56329515885d2"
    ),
    "scripts/kconfig/zconf.y": (
        "c8681edf42e4b600ddb3fd98431a776cdd5a49bd2c455d4e0ee7b82c03704be0"
    ),
    "scripts/kconfig/zconf.l": (
        "62413ba0b6b5a0972993a277c6b7045bc5764dc0b7b3dbaf3849fcb1dc842e0d"
    ),
    "scripts/kconfig/kconf_id.c": (
        "a8fbd8e3855c7c81f69b35e278ade8df12c8a80cde9c8941b6e7ab0ec0914f0a"
    ),
    "scripts/kconfig/util.c": (
        "d5340d4d939671852b6c0e012ac69aa052df387761f20d0ed2ceaa64d905d682"
    ),
    "scripts/kconfig/confdata.c": (
        "f40aaa3bcd0bf9042426c7841cb258a17561cc83799c649edc32681a0a2ce26a"
    ),
    "scripts/kconfig/expr.c": (
        "12d4b1b2f5b22de12ce0f3473a3fb74670d2db7b4888d95ae749538948f44524"
    ),
    "scripts/kconfig/symbol.c": (
        "0301d7ccd3c374d318dbd982f3e5655bbded8ace66bee7446cbeaef9d99f508e"
    ),
    "scripts/kconfig/menu.c": (
        "57a025e7afcd8be90aebd20cd1095d0e2c75878c343a512dfda4117852a24ac8"
    ),
    "scripts/kconfig/preprocess.c": (
        "83b39497c37efcb399622be3dc4493c09071fb502c04684164120ab01479025f"
    ),
    "scripts/kconfig/lkc.h": (
        "4ab18ef4c23d5740c0dca4ef10a7f1918fa0b091e363c96433e2d4b09e578bc2"
    ),
    "scripts/kconfig/expr.h": (
        "6f2db72e7384b187a64625e0c9bf01868fc67265686f170bb99bdf9b0b61a9d7"
    ),
    "scripts/kconfig/list.h": (
        "6ccdf5c23838c15288da60e35f37dd5de1557e677f05c64601a668ddf0042702"
    ),
    "scripts/kconfig/lkc_proto.h": (
        "347b9cd9bd433573ff283405feae32e43a4ff2d959a3b52b10d45300e6361417"
    ),
}


def load_transform():
    spec = importlib.util.spec_from_file_location("bird_uboot_env_nowhere", TRANSFORM)
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
        raise AssertionError("changed U-Boot environment authority was accepted")


def file_sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dotconfig(path: pathlib.Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if line.startswith("CONFIG_"):
            name, value = line.split("=", 1)
            result[name] = value
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            result[line[2:-11]] = "n"
    return result


def build_kconfig_conf(uboot: pathlib.Path, output: pathlib.Path) -> pathlib.Path:
    source = uboot / "scripts/kconfig"
    output.mkdir()
    subprocess.run(
        [
            "flex",
            f"-o{output / 'zconf.lex.c'}",
            "-L",
            str(source / "zconf.l"),
        ],
        check=True,
    )
    subprocess.run(
        [
            "bison",
            f"-o{output / 'zconf.tab.c'}",
            "-t",
            "-l",
            str(source / "zconf.y"),
        ],
        check=True,
    )
    conf = output / "conf"
    subprocess.run(
        [
            "clang",
            "-Wno-deprecated-non-prototype",
            "-I",
            str(source),
            str(source / "conf.c"),
            str(output / "zconf.tab.c"),
            "-o",
            str(conf),
        ],
        check=True,
    )
    return conf


def configure(
    uboot: pathlib.Path,
    conf: pathlib.Path,
    output: pathlib.Path,
    defconfig: pathlib.Path,
) -> dict[str, str]:
    output.mkdir()
    environment = os.environ.copy()
    environment.update(
        {
            "ARCH": "arm",
            "CC": "clang",
            "HOSTCC": "clang",
            "KCONFIG_CONFIG": str(output / ".config"),
            "srctree": str(uboot),
        }
    )
    completed = subprocess.run(
        [
            str(conf),
            f"--defconfig={defconfig}",
            str(uboot / "Kconfig"),
        ],
        check=True,
        cwd=output,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert completed.stderr == ""
    return dotconfig(output / ".config")


def assert_pinned_policy_source(uboot: pathlib.Path) -> None:
    authority = PINNED_UBOOT_FILES | PINNED_KCONFIG_HOST_FILES
    for relative, expected in authority.items():
        path = uboot / relative
        assert path.is_file() and not path.is_symlink(), path
        assert file_sha256(path) == expected, path

    kconfig = (uboot / "env/Kconfig").read_text()
    assert kconfig.count("default y if ARCH_SUNXI && MMC") == 1
    assert kconfig.count("select ENV_IS_NOWHERE") == 1
    assert kconfig.count('default "uboot.env"') == 1
    assert "default y if ENV_IS_NOWHERE" in kconfig
    assert (
        "def_bool y if !ENV_IS_IN_EEPROM && !ENV_IS_IN_EXT4 && \\\n"
        "\t\t     !ENV_IS_IN_FAT && !ENV_IS_IN_FLASH"
    ) in kconfig

    sunxi = (uboot / "board/sunxi/board.c").read_text()
    assert sunxi.count("return ENVL_NOWHERE;") == 1
    assert sunxi.count("return ENVL_FAT;") == 3
    assert "/* NOWHERE is exclusive, no other option can be defined. */" in sunxi

    makefile = (uboot / "env/Makefile").read_text()
    assert "obj-$(CONFIG_$(PHASE_)ENV_IS_NOWHERE) += nowhere.o" in makefile
    assert "obj-$(CONFIG_$(PHASE_)ENV_IS_IN_FAT) += fat.o" in makefile
    fat = (uboot / "env/fat.c").read_text()
    assert fat.count("file_fat_read(CONFIG_ENV_FAT_FILE") == 2
    assert "file_fat_write(file" in fat
    nowhere = (uboot / "env/nowhere.c").read_text()
    assert "env_set_default(NULL, 0);" in nowhere
    assert ".save" not in nowhere

    arm = (uboot / "arch/arm/Kconfig").read_text()
    assert "select CMD_MMC if MMC" in arm
    assert "imply DISTRO_DEFAULTS" in arm
    assert "imply FAT_WRITE" in arm
    mmc = (uboot / "drivers/mmc/Kconfig").read_text()
    assert (
        "config MMC_SUNXI\n"
        '\tbool "Allwinner sunxi SD/MMC Host Controller support"'
    ) in mmc
    assert "depends on ARCH_SUNXI\n\tdefault y" in mmc
    boot = (uboot / "boot/Kconfig").read_text()
    assert "select CMD_EXT4\n\tselect CMD_FAT" in boot
    assert "select CMD_SYSBOOT" in boot
    assert (
        "config BOOTMETH_EXTLINUX\n"
        '\tbool "Bootdev support for extlinux boot"'
    ) in boot

    # Neither storage backend symbol contributes bytes to the sunxi compiled
    # default environment. Its boot commands and variables therefore remain
    # byte-for-byte inputs to the same pinned env_default.h expansion.
    sunxi_defaults = (uboot / "include/configs/sunxi-common.h").read_text()
    assert "CFG_EXTRA_ENV_SETTINGS" in sunxi_defaults
    assert "BOOTENV" in sunxi_defaults
    assert "CONFIG_ENV_IS_IN_FAT" not in sunxi_defaults
    assert "CONFIG_ENV_IS_NOWHERE" not in sunxi_defaults
    generic_defaults = (uboot / "include/env_default.h").read_text()
    assert "CONFIG_ENV_IS_IN_FAT" not in generic_defaults
    assert "CONFIG_ENV_IS_NOWHERE" not in generic_defaults
    distro_defaults = (uboot / "include/config_distro_bootcmd.h").read_text()
    assert "CONFIG_ENV_IS_IN_FAT" not in distro_defaults
    assert "CONFIG_ENV_IS_NOWHERE" not in distro_defaults


def main() -> None:
    module = load_transform()
    assert module.ROCKNIX_COMMIT == "3e4ee5852e6ca5ea73a38369d2639fad2262648b"
    assert module.ROCKNIX_PACKAGE.endswith("/u-boot-DDR4")
    assert module.DEFCONFIG_NAME == "anbernic_rg35xx_h700_lpddr4_defconfig"
    assert module.sha256(GREEN_DDR4_DEFCONFIG) == module.BASE_SHA256

    result = module.transform(GREEN_DDR4_DEFCONFIG)
    assert module.sha256(result) == module.NOWHERE_SHA256
    assert result == GREEN_DDR4_DEFCONFIG + module.FAT_ENV_DISABLE
    assert result.count(module.FAT_ENV_DISABLE) == 1
    assert b"CONFIG_ENV_IS_NOWHERE" not in result
    assert b"uboot.env" not in result

    expect_rejected(
        module,
        GREEN_DDR4_DEFCONFIG.replace(b"CONFIG_BOOTDELAY=0", b"CONFIG_BOOTDELAY=1"),
        "defconfig authority changed",
    )
    expect_rejected(module, result, "anchor is already present")
    expect_rejected(
        module,
        GREEN_DDR4_DEFCONFIG + b"CONFIG_ENV_IS_NOWHERE=y\n",
        "policy authority is ambiguous",
    )
    expect_rejected(
        module,
        GREEN_DDR4_DEFCONFIG + b'CONFIG_ENV_FAT_FILE="uboot.env"\n',
        "policy authority is ambiguous",
    )

    with tempfile.TemporaryDirectory(prefix="bird-uboot-env-test-") as directory:
        temporary = pathlib.Path(directory)
        source = temporary / "green.defconfig"
        output = temporary / "nowhere.defconfig"
        source.write_bytes(GREEN_DDR4_DEFCONFIG)
        subprocess.run(
            [sys.executable, str(TRANSFORM), str(source), str(output)], check=True
        )
        assert source.read_bytes() == GREEN_DDR4_DEFCONFIG
        assert output.read_bytes() == result
        duplicate = subprocess.run(
            [sys.executable, str(TRANSFORM), str(source), str(output)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert duplicate.returncode != 0
        assert "refusing to replace output" in duplicate.stderr

        rocknix = pathlib.Path(
            os.environ.get(
                "ROCKNIX_SOURCE",
                str(pathlib.Path.home() / "rocknix-distribution-20260701"),
            )
        )
        uboot = (
            rocknix
            / "build.ROCKNIX-H700.aarch64/build/u-boot-DDR4-v2026.01"
        )
        if uboot.is_dir():
            assert_pinned_policy_source(uboot)
            conf = build_kconfig_conf(uboot, temporary / "kconfig-host")
            baseline_config = configure(
                uboot,
                conf,
                temporary / "base-o",
                source,
            )
            candidate_config = configure(
                uboot,
                conf,
                temporary / "candidate-o",
                output,
            )

            # Persistent environment policy changes. U-Boot proper now uses
            # the compiled default rather than reading uboot.env.
            assert baseline_config["CONFIG_ENV_IS_IN_FAT"] == "y"
            assert baseline_config.get("CONFIG_ENV_IS_NOWHERE", "n") == "n"
            assert candidate_config["CONFIG_ENV_IS_IN_FAT"] == "n"
            assert candidate_config["CONFIG_ENV_IS_DEFAULT"] == "y"
            assert candidate_config["CONFIG_ENV_IS_NOWHERE"] == "y"
            assert candidate_config.get("CONFIG_ENV_FAT_FILE", "n") == "n"
            assert candidate_config.get("CONFIG_ENV_FAT_INTERFACE", "n") == "n"
            assert baseline_config.get("CONFIG_SPL_ENV_SUPPORT", "n") == "n"
            assert candidate_config.get("CONFIG_SPL_ENV_SUPPORT", "n") == "n"

            # The backend switch must not remove the ordinary FAT/MMC/extlinux
            # boot path or alter any config symbol consumed by the compiled
            # sunxi default environment.
            preserved = (
                "CONFIG_MMC",
                "CONFIG_MMC_SUNXI",
                "CONFIG_CMD_MMC",
                "CONFIG_FS_FAT",
                "CONFIG_FAT_WRITE",
                "CONFIG_CMD_FAT",
                "CONFIG_CMD_SYSBOOT",
                "CONFIG_BOOTMETH_EXTLINUX",
                "CONFIG_CMD_EXT4",
                "CONFIG_CMD_SAVEENV",
            )
            for name in preserved:
                assert baseline_config[name] == "y", name
                assert candidate_config[name] == baseline_config[name], name

            environment_inputs = (
                "CONFIG_BOOTCOMMAND",
                "CONFIG_BOOTDELAY",
                "CONFIG_BAUDRATE",
                "CONFIG_DEFAULT_DEVICE_TREE",
                "CONFIG_SYS_LOAD_ADDR",
                "CONFIG_DISTRO_DEFAULTS",
                "CONFIG_CMD_DHCP",
                "CONFIG_CMD_PXE",
                "CONFIG_USB_STORAGE",
                "CONFIG_VIDEO",
                "CONFIG_ARM64",
            )
            for name in environment_inputs:
                assert (
                    candidate_config.get(name, "n")
                    == baseline_config.get(name, "n")
                ), name

            changed = {
                name
                for name in baseline_config.keys() | candidate_config.keys()
                if baseline_config.get(name, "n")
                != candidate_config.get(name, "n")
            }
            assert changed == {
                "CONFIG_ENV_IS_IN_FAT",
                "CONFIG_ENV_IS_DEFAULT",
                "CONFIG_ENV_IS_NOWHERE",
                "CONFIG_ENV_FAT_INTERFACE",
                "CONFIG_ENV_FAT_DEVICE_AND_PART",
                "CONFIG_ENV_FAT_FILE",
                "CONFIG_ENV_MMC_DEVICE_INDEX",
                "CONFIG_ENV_MMC_EMMC_HW_PARTITION",
            }, sorted(changed)

            # No active ROCKNIX H700 recipe produces or installs a persistent
            # environment file; the only selected artifact is the combined
            # SPL/U-Boot binary.  Keep this explicit so a later producer cannot
            # silently invalidate the candidate's successful-path premise.
            if (rocknix / ".git").is_dir():
                active_paths = (
                    "projects/ROCKNIX/devices/H700/packages/u-boot-DDR4/package.mk",
                    "projects/ROCKNIX/devices/H700/packages/u-boot/package.mk",
                    "projects/ROCKNIX/devices/H700/bootloader/update.sh",
                )
                active = b"".join(
                    subprocess.run(
                        [
                            "git",
                            "-C",
                            str(rocknix),
                            "show",
                            f"{module.ROCKNIX_COMMIT}:{path}",
                        ],
                        check=True,
                        stdout=subprocess.PIPE,
                    ).stdout
                    for path in active_paths
                )
                assert b"uboot.env" not in active
                assert b"saveenv" not in active
                assert b"fw_setenv" not in active
                assert active.count(b"u-boot-sunxi-with-spl.bin") == 4

    print("U-Boot nowhere-environment transform tests: PASS")


if __name__ == "__main__":
    main()
