#!/usr/bin/env python3
"""Focused host gate for accepted-in-place bootstage-FDT instrumentation."""

from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/projects/ROCKNIX/devices/H700/"
    "packages/u-boot-DDR4/sources/configs/anbernic_rg35xx_h700_lpddr4_defconfig"
)
UBOOT = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/build.ROCKNIX-H700.aarch64/"
    "build/u-boot-DDR4-v2026.01"
)
PINNED_SOURCES = {
    "boot/Kconfig": "f37b8c429f663834ce032f3ae354260c96cc6a00ac8c0ace51c7fa1a249a8062",
    "cmd/Kconfig": "7ef1928259e2ee805b365beed3e25c1145b9c121c758ddefffc38f68982c6a75",
    "arch/arm/lib/bootm.c": "ace497930ed764ac7a0454afe3330863d49a8d6474e442b8864ddb0e81a22fc1",
    "common/bootstage.c": "4c1860e81641342e5a60950bf49b736efc5a4b64d28dac3d55ea13db1099433f",
    "common/board_f.c": "73ea2fac6c3f39e1fd850f7e893e83d7aaac4fa870d2895365db983a7c90171e",
    "common/board_r.c": "313c26479ea2b39aa03d2208e3c01304b26d3bb21fb1ffbdb769530cfcbbf24f",
    "common/main.c": "48af6a22ed5379bd82455d241428defd9e6701dfd43c243f2dd7c04c8a400a6a",
    "boot/bootm.c": "e80e262aeb5f59481719158d602060f787577c44775eda12af5ac855ae4fa830",
    "include/bootstage.h": "027d6fa60ab4326b35f4ac20a886047c788d7d29f93fca1a71b3b3dab97b04ef",
    "arch/arm/cpu/armv8/generic_timer.c": "19d6126cd452d668ee63861b10248d0ed82d1c4cbbcd3a1cda6067a12791ae9d",
}


def load(name: str):
    path = ROOT / f"kernel/rocknix/{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_rejected(module, source: bytes, diagnostic: str) -> None:
    try:
        module.transform(source)
    except SystemExit as error:
        assert diagnostic in str(error), str(error)
    else:
        raise AssertionError("changed bootstage-FDT authority was accepted")


def assert_pinned_bootstage_path() -> None:
    for relative, expected in PINNED_SOURCES.items():
        path = UBOOT / relative
        assert path.is_file() and not path.is_symlink(), path
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, path

    boot_kconfig = (UBOOT / "boot/Kconfig").read_text()
    assert "config BOOTSTAGE\n" in boot_kconfig
    assert "config BOOTSTAGE_REPORT\n" in boot_kconfig
    assert "config BOOTSTAGE_FDT\n" in boot_kconfig
    assert "depends on BOOTSTAGE" in boot_kconfig
    cmd_kconfig = (UBOOT / "cmd/Kconfig").read_text()
    assert "config CMD_BOOTSTAGE\n" in cmd_kconfig

    arm_bootm = (UBOOT / "arch/arm/lib/bootm.c").read_text()
    assert arm_bootm.count("bootstage_fdt_add_report();") == 1
    assert (
        "bootstage_mark_name(BOOTSTAGE_ID_BOOTM_HANDOFF, \"start_kernel\");\n"
        "#ifdef CONFIG_BOOTSTAGE_FDT\n"
        "\tbootstage_fdt_add_report();\n"
        "#endif"
    ) in arm_bootm
    bootstage = (UBOOT / "common/bootstage.c").read_text()
    assert bootstage.count('fdt_add_subnode(blob, 0, "bootstage")') == 1
    assert bootstage.count('fdt_setprop_cell(blob, node,') == 1
    assert bootstage.count("int bootstage_fdt_add_report(void)") == 1

    board_f = (UBOOT / "common/board_f.c").read_text()
    assert board_f.count(
        'bootstage_mark_name(BOOTSTAGE_ID_START_UBOOT_F, "board_init_f");'
    ) == 1
    board_r = (UBOOT / "common/board_r.c").read_text()
    assert board_r.count(
        'bootstage_mark_name(BOOTSTAGE_ID_START_UBOOT_R, "board_init_r");'
    ) == 1
    assert board_r.count("INITCALL(initr_malloc);") == 1
    assert board_r.index("INITCALL(initr_malloc);") < board_r.index(
        "INITCALL(initr_bootstage);"
    )
    main = (UBOOT / "common/main.c").read_text()
    assert main.count(
        'bootstage_mark_name(BOOTSTAGE_ID_MAIN_LOOP, "main_loop");'
    ) == 1
    bootm = (UBOOT / "boot/bootm.c").read_text()
    assert bootm.count(
        'bootstage_mark_name(BOOTSTAGE_ID_BOOTM_START, "bootm_start");'
    ) == 1
    # Why before: bootm_start was enough to prove the general bootm boundary.
    # Why change: the existing kernel-loaded mark names bootm_load_os and gives
    # the measurement a distinct, source-pinned end to kernel image loading.
    assert bootm.count("bootstage_mark(BOOTSTAGE_ID_KERNEL_LOADED);") == 1
    load_os_start = bootm.index("static int bootm_load_os(")
    load_os_end = bootm.index("\nulong bootm_disable_interrupts(", load_os_start)
    assert load_os_start < bootm.index(
        "bootstage_mark(BOOTSTAGE_ID_KERNEL_LOADED);", load_os_start
    ) < load_os_end
    bootstage_header = (UBOOT / "include/bootstage.h").read_text()
    assert (
        "#define bootstage_mark(id)\tbootstage_mark_name(id, __func__)"
        in bootstage_header
    )
    timer = (UBOOT / "arch/arm/cpu/armv8/generic_timer.c").read_text()
    assert timer.count("ulong timer_get_boot_us(void)") == 1
    assert (
        "u64 val = get_ticks() * 1000000;\n\n"
        "\treturn val / get_tbclk();"
    ) in timer
    assert 'asm volatile("mrs %0, cntpct_el0"' in timer


def main() -> None:
    env = load("transform-uboot-environment-nowhere")
    direct = load("transform-uboot-direct-extlinux")
    no_clear = load("transform-uboot-no-heap-clear")
    fast = load("transform-uboot-fast-init")
    handoff = load("transform-uboot-inplace-handoff")
    bootstage = load("transform-uboot-bootstage-fdt")
    if not SOURCE.is_file():
        print("U-Boot bootstage-FDT transform tests: PASS (pinned source unavailable)")
        return

    fast_source = fast.transform(
        no_clear.transform(direct.transform(env.transform(SOURCE.read_bytes())))
    )
    source, environment = handoff.transform(fast_source)
    assert handoff.sha256(source) == handoff.RESULT_SHA256
    assert handoff.sha256(environment) == handoff.ENV_SHA256
    assert environment == handoff.ENVIRONMENT
    assert source.count(handoff.ENV_SELECTION) == 1
    assert source.count(bootstage.ENV_SELECTION) == 1
    result = bootstage.transform(source)
    assert result == source + bootstage.POLICY
    assert bootstage.sha256(result) == bootstage.RESULT_SHA256
    for line in bootstage.POLICY.splitlines(keepends=True):
        assert result.count(line) == 1, line
    assert result.count(bootstage.ENV_SELECTION) == 1
    expect_rejected(bootstage, source + b"# drift\n", "defconfig authority changed")
    expect_rejected(
        bootstage,
        source.replace(bootstage.ENV_SELECTION, b'CONFIG_ENV_SOURCE_FILE="other"\n'),
        "defconfig authority changed",
    )

    with tempfile.TemporaryDirectory(prefix="bird-uboot-bootstage-") as directory:
        temporary = pathlib.Path(directory)
        source_path = temporary / "source.defconfig"
        result_path = temporary / "result.defconfig"
        source_path.write_bytes(source)
        subprocess.run(
            [sys.executable, str(bootstage.__file__), str(source_path), str(result_path)],
            check=True,
        )
        assert source_path.read_bytes() == source
        assert result_path.read_bytes() == result
        duplicate = subprocess.run(
            [sys.executable, str(bootstage.__file__), str(source_path), str(result_path)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert duplicate.returncode != 0
        assert "refusing to replace bootstage-FDT output" in duplicate.stderr

        if UBOOT.is_dir():
            assert_pinned_bootstage_path()
            helper_path = (
                ROOT
                / "kernel/rocknix/tests/test-uboot-environment-nowhere-transform.py"
            )
            spec = importlib.util.spec_from_file_location(
                "bird_env_test_helpers_bootstage", helper_path
            )
            assert spec and spec.loader
            helper = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(helper)
            conf = helper.build_kconfig_conf(UBOOT, temporary / "kconfig-host")
            before = helper.configure(
                UBOOT, conf, temporary / "before", source_path
            )
            after = helper.configure(
                UBOOT, conf, temporary / "after", result_path
            )
            changed = {
                key
                for key in before.keys() | after.keys()
                if before.get(key, "n") != after.get(key, "n")
            }
            assert changed == {
                "CONFIG_BOOTSTAGE",
                "CONFIG_BOOTSTAGE_FDT",
                "CONFIG_BOOTSTAGE_RECORD_COUNT",
            }, changed
            assert before.get("CONFIG_BOOTSTAGE", "n") == "n"
            assert after["CONFIG_BOOTSTAGE"] == "y"
            assert after["CONFIG_BOOTSTAGE_FDT"] == "y"
            assert after["CONFIG_BOOTSTAGE_RECORD_COUNT"] == "50"
            assert before["CONFIG_ENV_SOURCE_FILE"] == '"bird-rg34xx-sp-handoff"'
            assert after["CONFIG_ENV_SOURCE_FILE"] == before["CONFIG_ENV_SOURCE_FILE"]
            for disabled in (
                "CONFIG_BOOTSTAGE_REPORT",
                "CONFIG_CMD_BOOTSTAGE",
                "CONFIG_SPL_BOOTSTAGE",
                "CONFIG_BOOTSTAGE_STASH",
            ):
                assert before.get(disabled, "n") == "n", disabled
                assert after.get(disabled, "n") == "n", disabled

    print("U-Boot bootstage-FDT transform tests: PASS")


if __name__ == "__main__":
    main()
