#!/usr/bin/env python3
"""Enable the reviewed RG34XX-SP red-off/green-on LED pair in sunxi SPL."""

from __future__ import annotations

import hashlib
import os
import pathlib
import sys


INPUT_SHA256 = "cea8a54adaf9c55b22c767361bdc79aab4972b931df762b330d6359d73844295"
OUTPUT_SHA256 = "fb38cee9d1c83c3bd81782f134959bbc10c180a932f7eee80c2ab5bff5c81168"
ADDITION = (
    b"CONFIG_SPL_DRIVERS_MISC=y\n"
    b"CONFIG_LED_STATUS1=y\n"
    b"CONFIG_LED_STATUS_BIT1=267\n"
    b"CONFIG_LED_STATUS_STATE1=0\n"
)


def transform(source: bytes) -> bytes:
    """Return the exact green U-Boot config with early green-on/red-off."""
    if hashlib.sha256(source).hexdigest() != INPUT_SHA256:
        raise ValueError("green U-Boot defconfig identity changed")
    required = (
        b"CONFIG_MACH_SUN50I_H616=y\n",
        b"CONFIG_SPL=y\n",
        b"CONFIG_LED_STATUS_BIT=268\n",
        b"CONFIG_LED_STATUS_STATE=2\n",
    )
    for anchor in required:
        if source.count(anchor) != 1:
            raise ValueError(f"required defconfig anchor changed: {anchor!r}")
    forbidden = (
        b"CONFIG_SPL_DRIVERS_MISC=",
        b"# CONFIG_SPL_DRIVERS_MISC",
        b"CONFIG_LED_STATUS1=",
        b"CONFIG_LED_STATUS_BIT1=",
        b"CONFIG_LED_STATUS_STATE1=",
    )
    if any(anchor in source for anchor in forbidden):
        raise ValueError("an alternate SPL or secondary-LED policy already exists")
    result = source + ADDITION
    if hashlib.sha256(result).hexdigest() != OUTPUT_SHA256:
        raise ValueError("early LED defconfig output identity changed")
    return result


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} INPUT_DEFCONFIG OUTPUT_DEFCONFIG", file=sys.stderr)
        return 2
    source_path = pathlib.Path(sys.argv[1])
    output_path = pathlib.Path(sys.argv[2])
    if source_path.is_symlink() or not source_path.is_file():
        raise SystemExit("input defconfig is missing or unsafe")
    if output_path.exists() or output_path.is_symlink():
        raise SystemExit("output defconfig already exists")
    result = transform(source_path.read_bytes())
    descriptor = os.open(
        output_path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
        0o600,
    )
    try:
        os.write(descriptor, result)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
