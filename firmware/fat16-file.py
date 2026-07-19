#!/usr/bin/env python3
"""Extract or replace a fixed-size file in the muOS FAT16 boot resource.

The boot-resource BPB declares a 128 MiB volume even though the GPT partition
contains only its first 32 MiB.  This tool follows the FAT cluster chain
directly, so it can safely operate on the exact 32 MiB partition payload.  A
replacement never rewrites allocation tables, directory entries or timestamps.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import struct
from pathlib import Path


class FatError(RuntimeError):
    pass


class Fat16:
    def __init__(self, image: bytearray):
        self.image = image
        if len(image) < 512 or image[510:512] != b"\x55\xaa":
            raise FatError("input does not have a valid DOS boot-sector signature")

        self.bytes_per_sector = struct.unpack_from("<H", image, 11)[0]
        self.sectors_per_cluster = image[13]
        self.reserved_sectors = struct.unpack_from("<H", image, 14)[0]
        self.fat_count = image[16]
        self.root_entries = struct.unpack_from("<H", image, 17)[0]
        self.sectors_per_fat = struct.unpack_from("<H", image, 22)[0]

        if self.bytes_per_sector not in (512, 1024, 2048, 4096):
            raise FatError(f"unsupported bytes per sector: {self.bytes_per_sector}")
        if not self.sectors_per_cluster or self.sectors_per_cluster & (self.sectors_per_cluster - 1):
            raise FatError(f"invalid sectors per cluster: {self.sectors_per_cluster}")
        if not self.reserved_sectors or self.fat_count not in (1, 2) or not self.sectors_per_fat:
            raise FatError("invalid FAT16 BPB geometry")

        self.cluster_size = self.bytes_per_sector * self.sectors_per_cluster
        self.fat_offset = self.reserved_sectors * self.bytes_per_sector
        self.root_offset = (
            self.reserved_sectors + self.fat_count * self.sectors_per_fat
        ) * self.bytes_per_sector
        self.root_size = self.root_entries * 32
        root_sectors = (self.root_size + self.bytes_per_sector - 1) // self.bytes_per_sector
        self.data_offset = (
            self.reserved_sectors + self.fat_count * self.sectors_per_fat + root_sectors
        ) * self.bytes_per_sector

        if self.data_offset > len(image):
            raise FatError("FAT metadata extends beyond the supplied partition payload")

    @staticmethod
    def _short_name(entry: bytes) -> str:
        base = entry[0:8].decode("ascii", "strict").rstrip()
        extension = entry[8:11].decode("ascii", "strict").rstrip()
        return base if not extension else f"{base}.{extension}"

    def _entries(self, offset: int, size: int):
        end = offset + size
        if end > len(self.image):
            raise FatError("directory extends beyond the supplied partition payload")
        for position in range(offset, end, 32):
            entry = self.image[position : position + 32]
            if entry[0] == 0x00:
                break
            if entry[0] == 0xE5 or entry[11] == 0x0F or entry[11] & 0x08:
                continue
            yield position, entry

    def _fat_next(self, cluster: int) -> int:
        position = self.fat_offset + cluster * 2
        if position + 2 > len(self.image):
            raise FatError("cluster FAT entry is outside the supplied partition payload")
        return struct.unpack_from("<H", self.image, position)[0]

    def _chain(self, first_cluster: int):
        if first_cluster < 2:
            raise FatError(f"invalid first cluster: {first_cluster}")
        cluster = first_cluster
        seen: set[int] = set()
        while True:
            if cluster in seen:
                raise FatError("loop in FAT cluster chain")
            if cluster < 2 or cluster >= 0xFFF0:
                raise FatError(f"invalid data cluster: 0x{cluster:04x}")
            seen.add(cluster)
            yield cluster
            following = self._fat_next(cluster)
            if following >= 0xFFF8:
                return
            if following == 0xFFF7 or following < 2:
                raise FatError(f"invalid next cluster: 0x{following:04x}")
            cluster = following

    def _cluster_offset(self, cluster: int) -> int:
        offset = self.data_offset + (cluster - 2) * self.cluster_size
        if offset + self.cluster_size > len(self.image):
            raise FatError(
                f"cluster {cluster} is outside the available 32 MiB partition payload"
            )
        return offset

    def _directory_entries(self, first_cluster: int):
        for cluster in self._chain(first_cluster):
            offset = self._cluster_offset(cluster)
            yield from self._entries(offset, self.cluster_size)

    def find(self, pathname: str) -> tuple[int, int, int]:
        parts = [part for part in pathname.replace("\\", "/").split("/") if part]
        if not parts:
            raise FatError("empty FAT path")

        entries = self._entries(self.root_offset, self.root_size)
        for index, wanted in enumerate(parts):
            wanted_upper = wanted.upper()
            match = None
            for entry_offset, entry in entries:
                if self._short_name(entry).upper() == wanted_upper:
                    match = (entry_offset, entry)
                    break
            if match is None:
                raise FatError(f"FAT path component not found: {wanted}")

            entry_offset, entry = match
            attributes = entry[11]
            first_cluster = struct.unpack_from("<H", entry, 26)[0]
            file_size = struct.unpack_from("<I", entry, 28)[0]
            is_last = index == len(parts) - 1
            if is_last:
                if attributes & 0x10:
                    raise FatError(f"FAT path is a directory: {pathname}")
                return entry_offset, first_cluster, file_size
            if not attributes & 0x10:
                raise FatError(f"intermediate FAT path is not a directory: {wanted}")
            entries = self._directory_entries(first_cluster)

        raise AssertionError("unreachable")

    def read_file(self, pathname: str) -> bytes:
        _, first_cluster, file_size = self.find(pathname)
        remaining = file_size
        output = bytearray()
        for cluster in self._chain(first_cluster):
            if not remaining:
                break
            count = min(remaining, self.cluster_size)
            offset = self._cluster_offset(cluster)
            output.extend(self.image[offset : offset + count])
            remaining -= count
        if remaining:
            raise FatError("cluster chain ended before the recorded file size")
        return bytes(output)

    def replace_file(self, pathname: str, replacement: bytes) -> int:
        _, first_cluster, file_size = self.find(pathname)
        if len(replacement) != file_size:
            raise FatError(
                f"replacement is {len(replacement)} bytes; {pathname} must remain {file_size} bytes"
            )

        remaining = len(replacement)
        source_offset = 0
        changed = 0
        for cluster in self._chain(first_cluster):
            if not remaining:
                break
            count = min(remaining, self.cluster_size)
            image_offset = self._cluster_offset(cluster)
            before = self.image[image_offset : image_offset + count]
            after = replacement[source_offset : source_offset + count]
            changed += sum(left != right for left, right in zip(before, after))
            self.image[image_offset : image_offset + count] = after
            source_offset += count
            remaining -= count
        if remaining:
            raise FatError("cluster chain ended before the replacement was complete")
        return changed


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    extract = subparsers.add_parser("extract", help="extract one FAT16 file")
    extract.add_argument("image", type=Path)
    extract.add_argument("fat_path")
    extract.add_argument("output", type=Path)

    replace = subparsers.add_parser("replace", help="replace one same-size FAT16 file")
    replace.add_argument("image", type=Path)
    replace.add_argument("fat_path")
    replace.add_argument("replacement", type=Path)
    replace.add_argument("output", type=Path)

    arguments = parser.parse_args()
    raw = bytearray(arguments.image.read_bytes())
    filesystem = Fat16(raw)

    if arguments.command == "extract":
        payload = filesystem.read_file(arguments.fat_path)
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_bytes(payload)
        print(
            f"extracted {arguments.fat_path}: {len(payload)} bytes sha256={sha256(payload)}"
        )
        return

    replacement = arguments.replacement.read_bytes()
    changed = filesystem.replace_file(arguments.fat_path, replacement)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_bytes(raw)
    print(
        f"replaced {arguments.fat_path}: changed_bytes={changed} "
        f"image_sha256={sha256(raw)}"
    )


if __name__ == "__main__":
    try:
        main()
    except (FatError, OSError, UnicodeError, struct.error) as error:
        raise SystemExit(f"error: {error}") from error
