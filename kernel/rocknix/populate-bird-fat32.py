#!/usr/bin/env python3
"""Populate a new FAT32 image without mounting it or adding host metadata."""

from __future__ import annotations

import pathlib
import struct
import sys


FIXED_DATE = ((2026 - 1980) << 9) | (7 << 5) | 1
FIXED_TIME = (4 << 11) | (53 << 5)
EOC = 0x0FFFFFFF


def short_checksum(name: bytes) -> int:
    value = 0
    for byte in name:
        value = ((value & 1) << 7) + (value >> 1) + byte
        value &= 0xFF
    return value


def lfn_entry(name: str, short_name: bytes) -> bytes:
    units = list(name.encode("utf-16le"))
    characters = [units[index] | (units[index + 1] << 8)
                  for index in range(0, len(units), 2)]
    if len(characters) > 13:
        raise ValueError("single-entry FAT long name exceeds 13 characters")
    if len(characters) < 13:
        characters.append(0)
    characters.extend([0xFFFF] * (13 - len(characters)))

    result = bytearray(32)
    result[0] = 0x41
    result[1:11] = struct.pack("<5H", *characters[0:5])
    result[11] = 0x0F
    result[12] = 0
    result[13] = short_checksum(short_name)
    result[14:26] = struct.pack("<6H", *characters[5:11])
    result[26:28] = b"\x00\x00"
    result[28:32] = struct.pack("<2H", *characters[11:13])
    return bytes(result)


def short_entry(name: bytes, attributes: int, cluster: int, size: int,
                lowercase_flags: int = 0) -> bytes:
    if len(name) != 11:
        raise ValueError("FAT short name must be exactly 11 bytes")
    result = bytearray(32)
    result[0:11] = name
    result[11] = attributes
    result[12] = lowercase_flags
    struct.pack_into("<H", result, 14, FIXED_TIME)
    struct.pack_into("<H", result, 16, FIXED_DATE)
    struct.pack_into("<H", result, 18, FIXED_DATE)
    struct.pack_into("<H", result, 20, cluster >> 16)
    struct.pack_into("<H", result, 22, FIXED_TIME)
    struct.pack_into("<H", result, 24, FIXED_DATE)
    struct.pack_into("<H", result, 26, cluster & 0xFFFF)
    struct.pack_into("<I", result, 28, size)
    return bytes(result)


def main() -> int:
    if len(sys.argv) != 5:
        print(f"usage: {sys.argv[0]} FAT_IMAGE KERNEL DTB EXTLINUX_CONF",
              file=sys.stderr)
        return 2

    image_path, kernel_path, dtb_path, config_path = map(pathlib.Path,
                                                         sys.argv[1:])
    payloads = [path.read_bytes()
                for path in (kernel_path, dtb_path, config_path)]

    with image_path.open("r+b") as image:
        boot = image.read(512)
        if boot[510:512] != b"\x55\xaa":
            raise SystemExit("FAT image has no boot signature")
        bytes_per_sector = struct.unpack_from("<H", boot, 11)[0]
        sectors_per_cluster = boot[13]
        reserved_sectors = struct.unpack_from("<H", boot, 14)[0]
        fat_count = boot[16]
        total_sectors = struct.unpack_from("<I", boot, 32)[0]
        fat_sectors = struct.unpack_from("<I", boot, 36)[0]
        root_cluster = struct.unpack_from("<I", boot, 44)[0]
        fsinfo_sector = struct.unpack_from("<H", boot, 48)[0]
        backup_sector = struct.unpack_from("<H", boot, 50)[0]

        if bytes_per_sector != 512 or root_cluster != 2:
            raise SystemExit("unexpected FAT32 geometry")
        cluster_bytes = bytes_per_sector * sectors_per_cluster
        data_sector = reserved_sectors + fat_count * fat_sectors
        cluster_count = (total_sectors - data_sector) // sectors_per_cluster

        next_cluster = 3
        chains: list[list[int]] = []
        for payload in payloads:
            length = max(1, (len(payload) + cluster_bytes - 1) // cluster_bytes)
            chain = list(range(next_cluster, next_cluster + length))
            chains.append(chain)
            next_cluster += length
        extlinux_cluster = next_cluster
        next_cluster += 1
        if next_cluster > cluster_count + 2:
            raise SystemExit("payloads do not fit in FAT image")

        def cluster_offset(cluster: int) -> int:
            sector = data_sector + (cluster - 2) * sectors_per_cluster
            return sector * bytes_per_sector

        fat = bytearray(fat_sectors * bytes_per_sector)
        image.seek(reserved_sectors * bytes_per_sector)
        original_fat = image.read(len(fat))
        fat[0:8] = original_fat[0:8]

        def set_fat(cluster: int, value: int) -> None:
            struct.pack_into("<I", fat, cluster * 4, value & 0x0FFFFFFF)

        set_fat(root_cluster, EOC)
        for chain in chains:
            for index, cluster in enumerate(chain):
                set_fat(cluster, chain[index + 1]
                        if index + 1 < len(chain) else EOC)
        set_fat(extlinux_cluster, EOC)
        for index in range(fat_count):
            image.seek((reserved_sectors + index * fat_sectors) *
                       bytes_per_sector)
            image.write(fat)

        for payload, chain in zip(payloads, chains):
            for index, cluster in enumerate(chain):
                chunk = payload[index * cluster_bytes:
                                (index + 1) * cluster_bytes]
                image.seek(cluster_offset(cluster))
                image.write(chunk.ljust(cluster_bytes, b"\x00"))

        root = bytearray(cluster_bytes)
        root_entries = [
            short_entry(b"BIRD       ", 0x08, 0, 0),
            short_entry(b"KERNEL     ", 0x20, chains[0][0], len(payloads[0])),
            short_entry(b"DTB     IMG", 0x20, chains[1][0], len(payloads[1]), 0x18),
            short_entry(b"EXTLINUX   ", 0x10, extlinux_cluster, 0, 0x08),
        ]
        root[0:len(root_entries) * 32] = b"".join(root_entries)
        image.seek(cluster_offset(root_cluster))
        image.write(root)

        config_short = b"EXTLIN~1CON"
        extlinux = bytearray(cluster_bytes)
        extlinux_entries = [
            short_entry(b".          ", 0x10, extlinux_cluster, 0),
            short_entry(b"..         ", 0x10, 0, 0),
            lfn_entry("extlinux.conf", config_short),
            short_entry(config_short, 0x20, chains[2][0], len(payloads[2])),
        ]
        extlinux[0:len(extlinux_entries) * 32] = b"".join(extlinux_entries)
        image.seek(cluster_offset(extlinux_cluster))
        image.write(extlinux)

        used_clusters = 1 + sum(len(chain) for chain in chains) + 1
        free_clusters = cluster_count - used_clusters
        for sector in (fsinfo_sector, backup_sector + fsinfo_sector):
            image.seek(sector * bytes_per_sector)
            info = bytearray(image.read(bytes_per_sector))
            if (info[0:4] == b"RRaA" and
                    info[484:488] == b"rrAa"):
                struct.pack_into("<I", info, 488, free_clusters)
                struct.pack_into("<I", info, 492, next_cluster)
                image.seek(sector * bytes_per_sector)
                image.write(info)
        image.flush()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
