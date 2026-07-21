#!/usr/bin/env python3
"""Write and verify Bird's fixed MBR/EBR records in a boot-prefix image."""

from __future__ import annotations

import pathlib
import struct
import sys


SECTOR_BYTES = 512
TOTAL_SECTORS = 1_000_144_896
FAT_START = 32_768
FAT_SECTORS = 262_144
EXTENDED_START = 294_912
SECOND_EBR = 296_960
ROOT_START = 319_488
ROOT_SECTORS = 16_777_216
DATA_START = 17_096_704
DATA_SECTORS = 983_048_189
PREFIX_BYTES = ROOT_START * SECTOR_BYTES


def entry(partition_type: int, start: int, sectors: int) -> bytes:
    if not 0 <= start <= 0xFFFFFFFF:
        raise ValueError(f"partition start outside MBR range: {start}")
    if not 0 <= sectors <= 0xFFFFFFFF:
        raise ValueError(f"partition size outside MBR range: {sectors}")
    # CHS is deliberately saturated; every consumer in this chain uses LBA.
    return struct.pack(
        "<B3sB3sII", 0, b"\xfe\xff\xff", partition_type,
        b"\xfe\xff\xff", start, sectors
    )


def sector_with_entries(*entries: bytes) -> bytes:
    if len(entries) > 4:
        raise ValueError("an MBR sector can contain at most four entries")
    sector = bytearray(SECTOR_BYTES)
    for index, value in enumerate(entries):
        if len(value) != 16:
            raise ValueError("partition entry is not 16 bytes")
        offset = 446 + index * 16
        sector[offset:offset + 16] = value
    sector[510:512] = b"\x55\xaa"
    return bytes(sector)


def read_entry(sector: bytes, index: int) -> tuple[int, int, int]:
    offset = 446 + index * 16
    _, _, partition_type, _, start, sectors = struct.unpack(
        "<B3sB3sII", sector[offset:offset + 16]
    )
    return partition_type, start, sectors


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} PREFIX_IMAGE", file=sys.stderr)
        return 2

    image_path = pathlib.Path(sys.argv[1])
    if image_path.stat().st_size != PREFIX_BYTES:
        raise SystemExit(
            f"prefix must end exactly at p5: {PREFIX_BYTES} bytes"
        )

    extended_sectors = TOTAL_SECTORS - EXTENDED_START
    second_ebr_relative = SECOND_EBR - EXTENDED_START
    second_chain_sectors = TOTAL_SECTORS - SECOND_EBR

    with image_path.open("r+b") as image:
        original_mbr = bytearray(image.read(SECTOR_BYTES))
        if original_mbr[510:512] != b"\x55\xaa":
            raise SystemExit("reference boot prefix has no MBR signature")
        original_mbr[446:510] = b"\x00" * 64
        original_mbr[446:462] = entry(0x0C, FAT_START, FAT_SECTORS)
        original_mbr[494:510] = entry(
            0x0F, EXTENDED_START, extended_sectors
        )
        image.seek(0)
        image.write(original_mbr)

        first_ebr = sector_with_entries(
            entry(0x83, ROOT_START - EXTENDED_START, ROOT_SECTORS),
            entry(0x0F, second_ebr_relative, second_chain_sectors),
        )
        image.seek(EXTENDED_START * SECTOR_BYTES)
        image.write(first_ebr)

        second_ebr = sector_with_entries(
            entry(0x07, DATA_START - SECOND_EBR, DATA_SECTORS)
        )
        image.seek(SECOND_EBR * SECTOR_BYTES)
        image.write(second_ebr)
        image.flush()

    with image_path.open("rb") as image:
        mbr = image.read(SECTOR_BYTES)
        image.seek(EXTENDED_START * SECTOR_BYTES)
        first_ebr = image.read(SECTOR_BYTES)
        image.seek(SECOND_EBR * SECTOR_BYTES)
        second_ebr = image.read(SECTOR_BYTES)

    assert read_entry(mbr, 0) == (0x0C, FAT_START, FAT_SECTORS)
    assert read_entry(mbr, 1) == (0, 0, 0)
    assert read_entry(mbr, 2) == (0, 0, 0)
    assert read_entry(mbr, 3) == (0x0F, EXTENDED_START, extended_sectors)
    assert read_entry(first_ebr, 0) == (
        0x83, ROOT_START - EXTENDED_START, ROOT_SECTORS
    )
    assert read_entry(first_ebr, 1) == (
        0x0F, second_ebr_relative, second_chain_sectors
    )
    assert read_entry(second_ebr, 0) == (
        0x07, DATA_START - SECOND_EBR, DATA_SECTORS
    )
    assert ROOT_START + ROOT_SECTORS == DATA_START
    assert DATA_START + DATA_SECTORS == TOTAL_SECTORS - 3

    print(f"p1 fat32 start={FAT_START} sectors={FAT_SECTORS}")
    print(f"p4 extended start={EXTENDED_START} sectors={extended_sectors}")
    print(f"p5 root start={ROOT_START} sectors={ROOT_SECTORS}")
    print(f"p6 data start={DATA_START} sectors={DATA_SECTORS}")
    print(f"prefix bytes={PREFIX_BYTES}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
