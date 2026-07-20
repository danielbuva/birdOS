#!/usr/bin/env python3
"""Normalize host-dependent identity fields in a newc CPIO archive."""

from __future__ import annotations

import os
import sys
from pathlib import Path


HEADER_SIZE = 110


def field(data: bytearray, offset: int, start: int) -> int:
    return int(data[offset + start : offset + start + 8], 16)


def align4(value: int) -> int:
    return (value + 3) & ~3


def normalize(path: Path) -> None:
    data = bytearray(path.read_bytes())
    offset = 0
    next_inode = 1
    inode_map: dict[tuple[int, int, int], int] = {}

    while True:
        if offset + HEADER_SIZE > len(data):
            raise ValueError(f"truncated newc header at byte {offset}")
        if data[offset : offset + 6] not in (b"070701", b"070702"):
            raise ValueError(f"invalid newc magic at byte {offset}")

        original_inode = field(data, offset, 6)
        device_major = field(data, offset, 62)
        device_minor = field(data, offset, 70)
        file_size = field(data, offset, 54)
        name_size = field(data, offset, 94)
        if name_size < 1:
            raise ValueError(f"invalid newc name length at byte {offset}")

        name_start = offset + HEADER_SIZE
        name_end = name_start + name_size
        if name_end > len(data) or data[name_end - 1] != 0:
            raise ValueError(f"invalid newc name at byte {offset}")
        name = bytes(data[name_start : name_end - 1])

        identity = (device_major, device_minor, original_inode)
        canonical_inode = inode_map.get(identity)
        if canonical_inode is None:
            canonical_inode = next_inode
            inode_map[identity] = canonical_inode
            next_inode += 1

        data[offset + 6 : offset + 14] = f"{canonical_inode:08x}".encode()
        # c_devmajor/c_devminor identify the host filesystem containing the
        # archived inode. Device-node identity lives in c_rdevmajor/minor and
        # is deliberately left untouched.
        data[offset + 62 : offset + 78] = b"0000000000000000"

        data_start = align4(name_end)
        next_offset = align4(data_start + file_size)
        if next_offset > len(data):
            raise ValueError(f"truncated newc payload for {name!r}")
        if name == b"TRAILER!!!":
            break
        offset = next_offset

    temporary = path.with_name(f".{path.name}.normalized-{os.getpid()}")
    temporary.write_bytes(data)
    os.replace(temporary, path)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} ARCHIVE.cpio", file=sys.stderr)
        return 2
    try:
        normalize(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
