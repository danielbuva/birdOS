#!/usr/bin/env python3
"""Install a fixed-size ext4 p2 into a cloned ROCKNIX MBR image."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import struct


SECTOR = 512
MBR_BYTES = 512
P2_ENTRY = 446 + 16
EXPECTED_START_LBA = 4_227_072
EXPECTED_OLD_SECTORS = 65_536
FIXED_SECTORS = 524_288
FIXED_BYTES = FIXED_SECTORS * SECTOR


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("storage", type=Path)
    args = parser.parse_args()

    if args.storage.stat().st_size != FIXED_BYTES:
        fail(f"storage image must be exactly {FIXED_BYTES} bytes")

    with args.image.open("r+b", buffering=0) as image:
        mbr = bytearray(image.read(MBR_BYTES))
        if len(mbr) != MBR_BYTES or mbr[510:512] != b"\x55\xaa":
            fail("missing MBR signature")
        if mbr[P2_ENTRY + 4] != 0x83:
            fail("partition 2 is not Linux type 0x83")
        start_lba, old_sectors = struct.unpack_from("<II", mbr, P2_ENTRY + 8)
        if start_lba != EXPECTED_START_LBA:
            fail(f"unexpected partition 2 start: {start_lba}")
        if old_sectors not in (EXPECTED_OLD_SECTORS, FIXED_SECTORS):
            fail(f"unexpected partition 2 size: {old_sectors}")

        struct.pack_into("<I", mbr, P2_ENTRY + 12, FIXED_SECTORS)
        final_bytes = (start_lba + FIXED_SECTORS) * SECTOR
        image.truncate(final_bytes)
        image.seek(0)
        image.write(mbr)
        image.seek(start_lba * SECTOR)
        with args.storage.open("rb", buffering=0) as storage:
            while chunk := storage.read(4 * 1024 * 1024):
                image.write(chunk)
        image.flush()
        os.fsync(image.fileno())

    print(f"installed fixed {FIXED_BYTES}-byte storage partition")
    print(f"candidate bytes: {final_bytes}")


if __name__ == "__main__":
    main()
