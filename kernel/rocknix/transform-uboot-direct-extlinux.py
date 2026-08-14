#!/usr/bin/env python3
"""Bind the reviewed RG34XX-SP U-Boot config to birdOS extlinux on mmc0p1."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "1bfd8861e74dea0534cd83037d0277ad8d0b46850d4c9e32726dcdeb76267a63"
RESULT_SHA256 = "784d76e328d1c1821a655176ecb805f10408f0b04f130acbb1b0e7ba38a6645a"
DIRECT_BOOT = b'CONFIG_BOOTCOMMAND="mmc dev 0; sysboot mmc 0:1 any ${scriptaddr} /extlinux/extlinux.conf"\n'


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit("nowhere-environment defconfig authority changed")
    if b"CONFIG_BOOTCOMMAND" in source or b"extlinux/extlinux.conf" in source:
        raise SystemExit("direct-extlinux authority is ambiguous")
    if not source.endswith(b"# CONFIG_ENV_IS_IN_FAT is not set\n"):
        raise SystemExit("nowhere-environment terminal anchor changed")
    result = source + DIRECT_BOOT
    if sha256(result) != RESULT_SHA256:
        raise SystemExit("direct-extlinux result identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing nowhere-environment defconfig")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace direct-extlinux output")
    args.output.write_bytes(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
