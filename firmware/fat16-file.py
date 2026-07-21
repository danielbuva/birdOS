#!/usr/bin/env python3
"""Extract, replace, or add a file in the muOS FAT16 boot resource.

The boot-resource BPB declares a 128 MiB volume even though the GPT partition
contains only its first 32 MiB.  This tool follows the FAT cluster chain
directly, so it can safely operate on the exact 32 MiB partition payload.  A
same-size replacement never rewrites allocation tables, directory entries or
timestamps. Addition is root-only and deliberately constrained to a strict 8.3
name and clusters that physically exist in the supplied 32 MiB payload.
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
        return self._fat_value(0, cluster)

    def _fat_value(self, copy: int, cluster: int) -> int:
        position = (
            self.fat_offset
            + copy * self.sectors_per_fat * self.bytes_per_sector
            + cluster * 2
        )
        if position + 2 > len(self.image):
            raise FatError("cluster FAT entry is outside the supplied partition payload")
        return struct.unpack_from("<H", self.image, position)[0]

    def _set_fat_value(self, cluster: int, value: int) -> None:
        for copy in range(self.fat_count):
            position = (
                self.fat_offset
                + copy * self.sectors_per_fat * self.bytes_per_sector
                + cluster * 2
            )
            if position + 2 > len(self.image):
                raise FatError("cluster FAT entry is outside the supplied partition payload")
            struct.pack_into("<H", self.image, position, value)

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

    @staticmethod
    def _encode_root_short_name(pathname: str) -> bytes:
        if "/" in pathname or "\\" in pathname or pathname in ("", ".", ".."):
            raise FatError("added file must use one root-level 8.3 name")
        parts = pathname.upper().split(".")
        if len(parts) > 2 or not parts[0] or len(parts[0]) > 8:
            raise FatError("added file must use a valid root-level 8.3 name")
        extension = parts[1] if len(parts) == 2 else ""
        if len(extension) > 3:
            raise FatError("added file must use a valid root-level 8.3 name")
        allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        if any(character not in allowed for part in parts for character in part):
            raise FatError("added file name contains an unsupported character")
        return (parts[0].ljust(8) + extension.ljust(3)).encode("ascii")

    def _free_root_slot(self, short_name: bytes) -> int:
        free_slot = None
        end = self.root_offset + self.root_size
        if end > len(self.image):
            raise FatError("root directory extends beyond the supplied partition payload")
        for position in range(self.root_offset, end, 32):
            entry = self.image[position : position + 32]
            if entry[0] in (0x00, 0xE5):
                if free_slot is None:
                    free_slot = position
                if entry[0] == 0x00:
                    break
                continue
            if entry[11] != 0x0F and entry[0:11] == short_name:
                raise FatError("FAT root file already exists")
        if free_slot is None:
            raise FatError("FAT root directory has no free entry")
        return free_slot

    def _accessible_cluster_count(self) -> int:
        return (len(self.image) - self.data_offset) // self.cluster_size

    def _allocate_contiguous_clusters(self, count: int) -> list[int]:
        if count == 0:
            return []
        maximum = self._accessible_cluster_count() + 1
        run_start = 0
        run_length = 0
        for cluster in range(2, maximum + 1):
            is_free = all(
                self._fat_value(copy, cluster) == 0
                for copy in range(self.fat_count)
            )
            if is_free:
                if not run_length:
                    run_start = cluster
                run_length += 1
                if run_length == count:
                    return list(range(run_start, run_start + count))
            else:
                run_length = 0
        raise FatError(
            f"no physically accessible contiguous run of {count} free clusters"
        )

    def add_root_file(self, pathname: str, payload: bytes) -> tuple[int, int]:
        short_name = self._encode_root_short_name(pathname)
        directory_offset = self._free_root_slot(short_name)
        cluster_count = (len(payload) + self.cluster_size - 1) // self.cluster_size
        clusters = self._allocate_contiguous_clusters(cluster_count)

        for index, cluster in enumerate(clusters):
            following = clusters[index + 1] if index + 1 < len(clusters) else 0xFFFF
            self._set_fat_value(cluster, following)
            image_offset = self._cluster_offset(cluster)
            payload_offset = index * self.cluster_size
            chunk = payload[payload_offset : payload_offset + self.cluster_size]
            self.image[image_offset : image_offset + self.cluster_size] = \
                chunk.ljust(self.cluster_size, b"\0")

        entry = bytearray(32)
        entry[0:11] = short_name
        entry[11] = 0x20
        first_cluster = clusters[0] if clusters else 0
        struct.pack_into("<H", entry, 26, first_cluster)
        struct.pack_into("<I", entry, 28, len(payload))
        self.image[directory_offset : directory_offset + 32] = entry

        if self.read_file(pathname) != payload:
            raise FatError("new FAT file failed exact readback verification")
        return first_cluster, cluster_count


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

    add = subparsers.add_parser("add", help="add one root-level 8.3 FAT16 file")
    add.add_argument("image", type=Path)
    add.add_argument("fat_path")
    add.add_argument("payload", type=Path)
    add.add_argument("output", type=Path)

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

    if arguments.command == "replace":
        replacement = arguments.replacement.read_bytes()
        changed = filesystem.replace_file(arguments.fat_path, replacement)
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_bytes(raw)
        print(
            f"replaced {arguments.fat_path}: changed_bytes={changed} "
            f"image_sha256={sha256(raw)}"
        )
        return

    payload = arguments.payload.read_bytes()
    if len(raw) != 32 * 1024 * 1024:
        raise FatError(
            "addition requires the exact physical 32 MiB boot-resource payload"
        )
    first_cluster, cluster_count = filesystem.add_root_file(
        arguments.fat_path, payload
    )
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_bytes(raw)
    print(
        f"added {arguments.fat_path}: bytes={len(payload)} "
        f"first_cluster={first_cluster} clusters={cluster_count} "
        f"image_sha256={sha256(raw)}"
    )


if __name__ == "__main__":
    try:
        main()
    except (FatError, OSError, UnicodeError, struct.error) as error:
        raise SystemExit(f"error: {error}") from error
