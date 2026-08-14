#!/usr/bin/env python3
"""Focused source gate for the RG34XX-SP SPL LED policy."""

from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import subprocess
import sys
import tarfile
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-early-led.py"
GREEN_TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-status-led.py"
PINNED_DEFCONFIG = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/projects/ROCKNIX/devices/H700/"
    "packages/u-boot-DDR4/sources/configs/"
    "anbernic_rg35xx_h700_lpddr4_defconfig"
)
PINNED_SOURCE = pathlib.Path(
    "/Users/dani/rocknix-distribution-20260701/sources/u-boot-DDR4/"
    "u-boot-DDR4-v2026.01.tar.gz"
)
PINNED_SOURCE_FILES = {
    "board/sunxi/board.c": "3dd7a998c141605030b6aa63b50e8fa18fb8ee54a01cd61cd160d7ed46b7089b",
    "drivers/misc/status_led.c": "54160261725ec192f73f006c3cb4436eb91f8609a6c9d0773bdbcf5d619621e1",
    "drivers/misc/gpio_led.c": "dec6597c9162069d21c986b0b94a29c208eac1b3637cac7c56fd396cd4ca3aa7",
    "drivers/gpio/sunxi_gpio.c": "46f292c1ab19055513d672fe972231b95952e73fef44db0fbfec11422bd243e4",
    "drivers/led/Kconfig": "3ee2e4dabf633a111f4069170ac388a730b39d5640408fffd8b57e0c526f8669",
}


def load(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def must_reject(module, source: bytes) -> None:
    try:
        module.transform(source)
    except ValueError:
        return
    raise AssertionError("unsafe early-LED input was accepted")


def main() -> None:
    early = load(TRANSFORM, "bird_uboot_early_led")
    green = load(GREEN_TRANSFORM, "bird_uboot_green_led")
    if not PINNED_DEFCONFIG.is_file():
        print("SKIP: pinned ROCKNIX U-Boot defconfig is unavailable")
        return
    baseline = PINNED_DEFCONFIG.read_bytes()
    green_config = green.transform(baseline)
    result = early.transform(green_config)
    assert hashlib.sha256(green_config).hexdigest() == early.INPUT_SHA256
    assert hashlib.sha256(result).hexdigest() == early.OUTPUT_SHA256
    assert result[: len(green_config)] == green_config
    assert result[len(green_config) :] == early.ADDITION
    assert result.count(b"CONFIG_LED_STATUS_BIT=268\n") == 1
    assert result.count(b"CONFIG_LED_STATUS_STATE=2\n") == 1
    assert result.count(b"CONFIG_SPL_DRIVERS_MISC=y\n") == 1
    assert result.count(b"CONFIG_LED_STATUS1=y\n") == 1
    assert result.count(b"CONFIG_LED_STATUS_BIT1=267\n") == 1
    assert result.count(b"CONFIG_LED_STATUS_STATE1=0\n") == 1

    must_reject(early, green_config + b"# drift\n")
    must_reject(early, result)
    must_reject(
        early,
        green_config.replace(
            b"CONFIG_LED_STATUS_BIT=268\n", b"CONFIG_LED_STATUS_BIT=267\n"
        ),
    )

    with tempfile.TemporaryDirectory() as directory:
        target = pathlib.Path(directory) / "early.defconfig"
        source = pathlib.Path(directory) / "green.defconfig"
        source.write_bytes(green_config)
        subprocess.run(
            [sys.executable, str(TRANSFORM), str(source), str(target)], check=True
        )
        assert target.read_bytes() == result
        rejected = subprocess.run(
            [sys.executable, str(TRANSFORM), str(source), str(target)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert rejected.returncode != 0
        assert "already exists" in rejected.stderr

    if PINNED_SOURCE.is_file():
        with tarfile.open(PINNED_SOURCE, "r:gz") as archive:
            bodies: dict[str, bytes] = {}
            for relative, expected_sha in PINNED_SOURCE_FILES.items():
                member = archive.getmember(f"u-boot-2026.01/{relative}")
                extracted = archive.extractfile(member)
                assert extracted is not None
                body = extracted.read()
                assert hashlib.sha256(body).hexdigest() == expected_sha
                bodies[relative] = body
        board = bodies["board/sunxi/board.c"]
        status = bodies["drivers/misc/status_led.c"]
        gpio_led = bodies["drivers/misc/gpio_led.c"]
        gpio = bodies["drivers/gpio/sunxi_gpio.c"]
        kconfig = bodies["drivers/led/Kconfig"]
        assert b"if (IS_ENABLED(CONFIG_SPL_DRIVERS_MISC))\n\t\tstatus_led_init();" in board
        assert b"for (i = 0, ld = led_dev; i < MAX_LED_DEV; i++, ld++)" in status
        assert b"gpio_value = (state == CONFIG_LED_STATUS_ON);" in gpio_led
        assert b"gpio_direction_output(mask, gpio_value);" in gpio_led
        assert b"sunxi_gpio_set_cfgpin(gpio, SUNXI_GPIO_OUTPUT);" in gpio
        assert b'config LED_STATUS_STATE1' in kconfig
        assert b'default LED_STATUS_OFF' in kconfig
    else:
        print("SKIP: pinned U-Boot source archive is unavailable")

    print("PASS: exact U-Boot SPL green-on/red-off transform")


if __name__ == "__main__":
    main()
