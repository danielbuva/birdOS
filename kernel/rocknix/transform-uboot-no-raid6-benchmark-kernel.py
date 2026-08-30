#!/usr/bin/env python3
"""Bind RG34XX-SP U-Boot to the exact no-RAID6-benchmark LZ4 frame.

Why before: the accepted fixed-command-closure U-Boot retained the exact
17,565,707-byte bound of the physically accepted IRQ-kernel LZ4 frame.
Why change: disabling the fixed device's boot-only RAID6 PQ benchmark changes
the compressed frame identity and shortens it by 363 bytes, so the immutable
consumer must use that exact new bound without widening its read.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "301d6c8db012d13918fee5cbf4251fdffd67c55b25d483a423b502c4a2240701"
RESULT_SHA256 = "f859807248a51e41e9ff3cb909403d14c981d3c0effe4671e785c53657c6663e"
LZ4_KERNEL_BYTES = 17_565_344
LZ4_KERNEL_SIZE_HEX = "0x10c06a0"
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
        raise SystemExit("no-RAID6-benchmark sunxi layout identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing sunxi-common.h authority")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace no-RAID6-benchmark header output")
    with args.output.open("xb") as output:
        output.write(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
