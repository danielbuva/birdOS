#!/usr/bin/env python3
"""Bind RG34XX-SP U-Boot to the exact accepted birdOS LZ4 KERNEL frame.

This transforms only the Allwinner ARM64 compressed-kernel input bound.  It
does not create a deployable U-Boot image and cannot write a card.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "301d6c8db012d13918fee5cbf4251fdffd67c55b25d483a423b502c4a2240701"
RESULT_SHA256 = "f3a2598263c50efbff8d728dd24eaf0c15a70f97e3856afc47aa8021071fde37"
LZ4_KERNEL_BYTES = 17_565_707
LZ4_KERNEL_SIZE_HEX = "0x10c080b"
OLD_LIMIT = b"#define KERNEL_COMP_SIZE  __stringify(0xb000000)\n"
NEW_LIMIT = (
    f"#define KERNEL_COMP_SIZE  __stringify({LZ4_KERNEL_SIZE_HEX})\n".encode()
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit("accepted sunxi compressed-kernel layout authority changed")
    if source.count(OLD_LIMIT) != 1 or NEW_LIMIT in source:
        raise SystemExit("compressed-kernel limit replacement authority is ambiguous")
    if int(LZ4_KERNEL_SIZE_HEX, 16) != LZ4_KERNEL_BYTES:
        raise SystemExit("LZ4 KERNEL byte authority and hexadecimal limit differ")
    if len(OLD_LIMIT) != len(NEW_LIMIT):
        raise SystemExit("compressed-kernel environment layout would shift")

    result = source.replace(OLD_LIMIT, NEW_LIMIT)
    if sha256(result) != RESULT_SHA256:
        raise SystemExit("LZ4-paired sunxi layout identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing sunxi-common.h authority")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace LZ4-paired header output")
    with args.output.open("xb") as output:
        output.write(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
