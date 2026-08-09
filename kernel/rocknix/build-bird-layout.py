#!/usr/bin/env python3
"""Write and verify Bird's fixed MBR/EBR records in a boot-prefix image."""

from __future__ import annotations

import argparse
import pathlib
import struct
from typing import NamedTuple


SECTOR_BYTES = 512
TOTAL_SECTORS = 1_000_144_896
FAT_START = 32_768
ROOT_START = 319_488
ROOT_SECTORS = 16_777_216
DATA_START = 17_096_704
DATA_SECTORS = 983_048_189
PREFIX_BYTES = ROOT_START * SECTOR_BYTES


class Layout(NamedTuple):
    name: str
    fat_sectors: int
    extended_start: int
    second_ebr: int


LEGACY_128 = Layout("legacy-128", 262_144, 294_912, 296_960)
EXPANDED_138 = Layout("expanded-138", 282_624, 315_392, 317_440)
LAYOUTS = {layout.name: layout for layout in (LEGACY_128, EXPANDED_138)}

# Preserve the original module constants for callers which import this file.
FAT_SECTORS = LEGACY_128.fat_sectors
EXTENDED_START = LEGACY_128.extended_start
SECOND_EBR = LEGACY_128.second_ebr


def assert_layout(layout: Layout) -> None:
    fat_end = FAT_START + layout.fat_sectors
    root_end = ROOT_START + ROOT_SECTORS
    data_end = DATA_START + DATA_SECTORS

    assert 0 < FAT_START < fat_end, "FAT geometry is empty or reversed"
    assert fat_end == layout.extended_start, (
        "FAT must end exactly where the extended partition begins"
    )
    assert layout.extended_start < layout.second_ebr, (
        "the second EBR must follow the extended partition's first EBR"
    )
    assert layout.second_ebr < ROOT_START, (
        "both EBRs must precede p5 without overlapping it"
    )
    assert ROOT_START < root_end == DATA_START, (
        "p5 must be non-empty and end exactly where p6 begins"
    )
    assert DATA_START < data_end == TOTAL_SECTORS - 3, (
        "p6 must be non-empty and retain the fixed trailing sectors"
    )


for _layout in LAYOUTS.values():
    assert_layout(_layout)


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


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="write Bird's fixed MBR/EBR partition records"
    )
    parser.add_argument(
        "--layout",
        choices=tuple(LAYOUTS),
        default=LEGACY_128.name,
        help="partition geometry to write (default: %(default)s)",
    )
    parser.add_argument("prefix_image", type=pathlib.Path)
    return parser.parse_args(argv)


def write_layout(image_path: pathlib.Path, layout: Layout) -> None:
    assert_layout(layout)
    if image_path.stat().st_size != PREFIX_BYTES:
        raise SystemExit(
            f"prefix must end exactly at p5: {PREFIX_BYTES} bytes"
        )

    extended_sectors = TOTAL_SECTORS - layout.extended_start
    second_ebr_relative = layout.second_ebr - layout.extended_start
    second_chain_sectors = TOTAL_SECTORS - layout.second_ebr

    with image_path.open("r+b") as image:
        original_mbr = bytearray(image.read(SECTOR_BYTES))
        if original_mbr[510:512] != b"\x55\xaa":
            raise SystemExit("reference boot prefix has no MBR signature")
        original_mbr[446:510] = b"\x00" * 64
        original_mbr[446:462] = entry(
            0x0C, FAT_START, layout.fat_sectors
        )
        original_mbr[494:510] = entry(
            0x0F, layout.extended_start, extended_sectors
        )
        image.seek(0)
        image.write(original_mbr)

        first_ebr = sector_with_entries(
            entry(
                0x83, ROOT_START - layout.extended_start, ROOT_SECTORS
            ),
            entry(0x0F, second_ebr_relative, second_chain_sectors),
        )
        image.seek(layout.extended_start * SECTOR_BYTES)
        image.write(first_ebr)

        second_ebr = sector_with_entries(
            entry(0x07, DATA_START - layout.second_ebr, DATA_SECTORS)
        )
        image.seek(layout.second_ebr * SECTOR_BYTES)
        image.write(second_ebr)
        image.flush()

    with image_path.open("rb") as image:
        mbr = image.read(SECTOR_BYTES)
        image.seek(layout.extended_start * SECTOR_BYTES)
        first_ebr = image.read(SECTOR_BYTES)
        image.seek(layout.second_ebr * SECTOR_BYTES)
        second_ebr = image.read(SECTOR_BYTES)

    assert read_entry(mbr, 0) == (
        0x0C, FAT_START, layout.fat_sectors
    )
    assert read_entry(mbr, 1) == (0, 0, 0)
    assert read_entry(mbr, 2) == (0, 0, 0)
    assert read_entry(mbr, 3) == (
        0x0F, layout.extended_start, extended_sectors
    )
    assert read_entry(first_ebr, 0) == (
        0x83, ROOT_START - layout.extended_start, ROOT_SECTORS
    )
    assert read_entry(first_ebr, 1) == (
        0x0F, second_ebr_relative, second_chain_sectors
    )
    assert read_entry(second_ebr, 0) == (
        0x07, DATA_START - layout.second_ebr, DATA_SECTORS
    )

    print(f"p1 fat32 start={FAT_START} sectors={layout.fat_sectors}")
    print(
        f"p4 extended start={layout.extended_start} "
        f"sectors={extended_sectors}"
    )
    print(f"p5 root start={ROOT_START} sectors={ROOT_SECTORS}")
    print(f"p6 data start={DATA_START} sectors={DATA_SECTORS}")
    print(f"prefix bytes={PREFIX_BYTES}")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    write_layout(args.prefix_image, LAYOUTS[args.layout])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
