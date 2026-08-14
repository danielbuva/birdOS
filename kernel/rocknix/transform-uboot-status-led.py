#!/usr/bin/env python3
"""Apply the reviewed RG34XX-SP DDR4 U-Boot status-LED policy change."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


ROCKNIX_COMMIT = "3e4ee5852e6ca5ea73a38369d2639fad2262648b"
ROCKNIX_PACKAGE = "projects/ROCKNIX/devices/H700/packages/u-boot-DDR4"
DEFCONFIG_NAME = "anbernic_rg35xx_h700_lpddr4_defconfig"
UPSTREAM_SHA256 = "24013855fefbe911cf664301940e8b6b514e4961ed414f324dae491f56d6bfe4"
GREEN_SHA256 = "cea8a54adaf9c55b22c767361bdc79aab4972b931df762b330d6359d73844295"

RED_STATUS_LED = b"CONFIG_LED_STATUS_BIT=267\n"
GREEN_STATUS_LED = b"CONFIG_LED_STATUS_BIT=268\n"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    """Return the pinned DDR4 defconfig with only PI11/red changed to PI12/green."""

    red_count = source.count(RED_STATUS_LED)
    green_count = source.count(GREEN_STATUS_LED)
    if red_count != 1 or green_count != 0:
        raise SystemExit(
            "U-Boot DDR4 status-LED anchor authority changed "
            f"(red={red_count}, green={green_count})"
        )
    source_digest = sha256(source)
    if source_digest != UPSTREAM_SHA256:
        raise SystemExit(
            "U-Boot DDR4 defconfig authority changed "
            f"(expected {UPSTREAM_SHA256}, found {source_digest})"
        )

    transformed = source.replace(RED_STATUS_LED, GREEN_STATUS_LED)
    if len(transformed) != len(source):
        raise SystemExit("U-Boot DDR4 status-LED transform changed defconfig size")
    transformed_digest = sha256(transformed)
    if transformed_digest != GREEN_SHA256:
        raise SystemExit(
            "U-Boot DDR4 green-LED result changed "
            f"(expected {GREEN_SHA256}, found {transformed_digest})"
        )
    return transformed


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Copy the pinned ROCKNIX H700 DDR4 U-Boot defconfig while changing "
            "only status GPIO 267/PI11 red to GPIO 268/PI12 green."
        )
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit(f"unsafe or missing U-Boot DDR4 defconfig: {args.source}")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit(f"refusing to replace output: {args.output}")
    if args.source.resolve() == args.output.resolve():
        raise SystemExit("U-Boot DDR4 source and output must be different paths")

    transformed = transform(args.source.read_bytes())
    with args.output.open("xb") as output:
        output.write(transformed)


if __name__ == "__main__":
    main()
