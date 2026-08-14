#!/usr/bin/env python3
"""Disable persistent FAT environment storage in the installed Stage 10 config."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


ROCKNIX_COMMIT = "3e4ee5852e6ca5ea73a38369d2639fad2262648b"
ROCKNIX_PACKAGE = "projects/ROCKNIX/devices/H700/packages/u-boot-DDR4"
DEFCONFIG_NAME = "anbernic_rg35xx_h700_lpddr4_defconfig"
BASE_SHA256 = "24013855fefbe911cf664301940e8b6b514e4961ed414f324dae491f56d6bfe4"
NOWHERE_SHA256 = "1bfd8861e74dea0534cd83037d0277ad8d0b46850d4c9e32726dcdeb76267a63"

# ARCH_SUNXI && MMC defaults ENV_IS_IN_FAT to y.  Explicitly disabling that
# one policy lets ENV_IS_DEFAULT select ENV_IS_NOWHERE.  General FAT and MMC
# boot support remain independently selected by the H700 boot configuration.
FAT_ENV_DISABLE = b"# CONFIG_ENV_IS_IN_FAT is not set\n"
POLICY_PREFIX = b"CONFIG_ENV_IS_"
PERSISTENT_FILENAME = b"uboot.env"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    """Return the pinned installed defconfig with only FAT persistence disabled."""

    if source.count(FAT_ENV_DISABLE) != 0:
        raise SystemExit("U-Boot environment policy anchor is already present")
    if POLICY_PREFIX in source or PERSISTENT_FILENAME in source:
        raise SystemExit("U-Boot environment policy authority is ambiguous")
    source_digest = sha256(source)
    if source_digest != BASE_SHA256:
        raise SystemExit(
            "installed U-Boot defconfig authority changed "
            f"(expected {BASE_SHA256}, found {source_digest})"
        )
    if not source.endswith(b"CONFIG_LED_STATUS_STATE=2\n"):
        raise SystemExit("installed U-Boot defconfig terminal anchor changed")

    transformed = source + FAT_ENV_DISABLE
    if transformed[:-len(FAT_ENV_DISABLE)] != source:
        raise SystemExit("U-Boot environment transform changed existing defconfig bytes")
    transformed_digest = sha256(transformed)
    if transformed_digest != NOWHERE_SHA256:
        raise SystemExit(
            "U-Boot nowhere-environment result changed "
            f"(expected {NOWHERE_SHA256}, found {transformed_digest})"
        )
    return transformed


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Copy the installed H700 DDR4 U-Boot defconfig while disabling "
            "only its default persistent FAT environment backend."
        )
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit(f"unsafe or missing installed U-Boot defconfig: {args.source}")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit(f"refusing to replace output: {args.output}")
    if args.source.resolve() == args.output.resolve():
        raise SystemExit("installed U-Boot source and output must be different paths")

    transformed = transform(args.source.read_bytes())
    with args.output.open("xb") as output:
        output.write(transformed)


if __name__ == "__main__":
    main()
