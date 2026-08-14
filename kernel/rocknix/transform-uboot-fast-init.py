#!/usr/bin/env python3
"""Specialize the accepted RG34XX-SP U-Boot successful initialization path."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "74d6dc38c098657e081877f321470455556ae385e1642e36151d32da2faa9bc1"
RESULT_SHA256 = "f0b0c44e54c28675fddc2d92243ff0b35d475a07b2c196af053294fa38e90922"
OLD_DELAY = b"CONFIG_BOOTDELAY=0\n"
NEW_DELAY = b"CONFIG_BOOTDELAY=-2\n"
OLD_BOOT = b'CONFIG_BOOTCOMMAND="mmc dev 0; sysboot mmc 0:1 any ${scriptaddr} /extlinux/extlinux.conf"\n'
NEW_BOOT = b'CONFIG_BOOTCOMMAND="sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux.conf"\n'
POLICY = (
    b"CONFIG_NO_NET=y\n"
    b"# CONFIG_BOOTSTD is not set\n"
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit("accepted no-heap-clear defconfig authority changed")
    if source.count(OLD_DELAY) != 1 or source.count(OLD_BOOT) != 1:
        raise SystemExit("fast-init replacement authority is ambiguous")
    for entry in POLICY.splitlines(keepends=True):
        if entry in source:
            raise SystemExit("fast-init policy is already present")

    result = source.replace(OLD_DELAY, NEW_DELAY).replace(OLD_BOOT, NEW_BOOT) + POLICY
    if sha256(result) != RESULT_SHA256:
        raise SystemExit("fast-init result identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing no-heap-clear defconfig")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace fast-init output")
    with args.output.open("xb") as output:
        output.write(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
