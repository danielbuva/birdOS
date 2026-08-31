#!/usr/bin/env python3
"""Bind RG34XX-SP U-Boot to the exact deferred-Wi-Fi LZ4 frame.

Why before: the accepted Stage 11 U-Boot reads the exact 17,565,344-byte
fixed-RAID6 kernel frame. Why change: deferring the fixed Wi-Fi SDIO power wait
changes the kernel identity and shortens its frame by 270 bytes, so its
immutable consumer needs a new exact bound without widening the read.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "301d6c8db012d13918fee5cbf4251fdffd67c55b25d483a423b502c4a2240701"
RESULT_SHA256 = "62eeb13ccf359db68c32ca568c9062ca9709c58325b41d057c5036fae7962683"
LZ4_KERNEL_BYTES = 17_565_074
LZ4_KERNEL_SIZE_HEX = "0x10c0592"
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
        raise SystemExit("deferred-Wi-Fi sunxi layout identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing sunxi-common.h authority")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace deferred-Wi-Fi header output")
    with args.output.open("xb") as output:
        output.write(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
