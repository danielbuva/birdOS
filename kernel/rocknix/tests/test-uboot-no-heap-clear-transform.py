#!/usr/bin/env python3
"""Focused source gate for the full-U-Boot 64 MiB heap-clear removal."""

from __future__ import annotations

import importlib.util
import hashlib
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
    if not SOURCE.is_file():
        print("U-Boot no-heap-clear transform tests: PASS (pinned source unavailable)")
        return
    source = direct.transform(env.transform(SOURCE.read_bytes()))
    result = no_clear.transform(source)
    assert result == source + no_clear.POLICY
    assert no_clear.sha256(result) == no_clear.RESULT_SHA256
    assert result.count(b"# CONFIG_SYS_MALLOC_CLEAR_ON_INIT is not set\n") == 1
    assert result.count(b"CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT=y\n") == 1
    assert b"CONFIG_SYS_MALLOC_LEN" not in result
    try:
        no_clear.transform(source + b"# drift\n")
    except SystemExit:
        pass
    else:
        raise AssertionError("changed no-heap-clear authority was accepted")

    uboot = pathlib.Path(
        "/Users/dani/rocknix-distribution-20260701/build.ROCKNIX-H700.aarch64/"
        "build/u-boot-DDR4-v2026.01"
    )
    if uboot.is_dir():
        source_authority = {
            "Kconfig": "c319e5c9310d4f8b04adeb36f8e7549bad03f3ba89c01267757d5d327a752c37",
            "common/board_r.c": "313c26479ea2b39aa03d2208e3c01304b26d3bb21fb1ffbdb769530cfcbbf24f",
            "common/dlmalloc.c": "fdb20175ac2ef092fa4d0353c2c22dc0bdeedb263e2b457444a6be1cef4ae33d",
            "common/spl/spl.c": "e33ca169d641c4bb1a930e88f43e5cfa1e67992c4e94c9cf113a35f88202495f",
        }
        for relative, expected in source_authority.items():
            assert hashlib.sha256((uboot / relative).read_bytes()).hexdigest() == expected
        board_r = (uboot / "common/board_r.c").read_text(encoding="utf-8")
        dlmalloc = (uboot / "common/dlmalloc.c").read_text(encoding="utf-8")
        spl = (uboot / "common/spl/spl.c").read_text(encoding="utf-8")
        assert board_r.count("mem_malloc_init(start, TOTAL_MALLOC_LEN);") == 1
        assert dlmalloc.count("CONFIG_IS_ENABLED(SYS_MALLOC_CLEAR_ON_INIT)") == 3
        assert "memset((void *)mem_malloc_start, 0x0, size);" in dlmalloc
        assert "mem_malloc_init(SPL_SYS_MALLOC_START, SPL_SYS_MALLOC_SIZE);" in spl
        helper_path = ROOT / "kernel/rocknix/tests/test-uboot-environment-nowhere-transform.py"
        spec = importlib.util.spec_from_file_location("bird_env_test_helpers", helper_path)
        assert spec and spec.loader
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        with tempfile.TemporaryDirectory(prefix="bird-uboot-no-clear-") as directory:
            temporary = pathlib.Path(directory)
            conf = helper.build_kconfig_conf(uboot, temporary / "host")
            source_path = temporary / "source.defconfig"
            result_path = temporary / "result.defconfig"
            source_path.write_bytes(source)
            result_path.write_bytes(result)
            before = helper.configure(uboot, conf, temporary / "before", source_path)
            after = helper.configure(uboot, conf, temporary / "after", result_path)
            changed = {
                key for key in before.keys() | after.keys()
                if before.get(key, "n") != after.get(key, "n")
            }
            assert changed == {"CONFIG_SYS_MALLOC_CLEAR_ON_INIT"}
            assert before["CONFIG_SYS_MALLOC_CLEAR_ON_INIT"] == "y"
            assert after["CONFIG_SYS_MALLOC_CLEAR_ON_INIT"] == "n"
            assert before["CONFIG_SYS_MALLOC_LEN"] == after["CONFIG_SYS_MALLOC_LEN"] == "0x4020000"
            assert before["CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT"] == after["CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT"] == "y"
    print("U-Boot no-heap-clear transform tests: PASS")


if __name__ == "__main__":
    main()
