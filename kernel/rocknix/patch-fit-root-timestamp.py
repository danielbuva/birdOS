#!/usr/bin/env python3
"""Patch exactly the root FIT timestamp data bytes, in place."""

from __future__ import annotations

import os
import pathlib
import stat
import struct
import sys


FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9
FDT_HEADER_BYTES = 40
UINT32_MAX = (1 << 32) - 1


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def parse_epoch(text: str, label: str) -> int:
    if not text or not text.isascii() or not text.isdecimal():
        fail(f"{label} must be an unsigned decimal 32-bit epoch")
    value = int(text, 10)
    if value > UINT32_MAX:
        fail(f"{label} must be an unsigned decimal 32-bit epoch")
    return value


def _checked_end(offset: int, size: int, total: int, label: str) -> int:
    if offset > total or size > total - offset:
        fail(f"FIT {label} exceeds artifact bounds")
    return offset + size


def find_root_timestamp(blob: bytes) -> int:
    """Return the data offset of the sole four-byte root timestamp property."""

    if len(blob) < FDT_HEADER_BYTES:
        fail("FIT is shorter than its header")
    (
        magic,
        total_size,
        structure_offset,
        strings_offset,
        reserve_offset,
        version,
        last_compatible_version,
        _boot_cpu,
        strings_size,
        structure_size,
    ) = struct.unpack_from(">10I", blob)
    if magic != FDT_MAGIC:
        fail("FIT magic is invalid")
    if total_size != len(blob):
        fail(f"FIT size is not exact ({total_size} != {len(blob)})")
    if version != 17 or last_compatible_version != 2:
        fail("FIT version authority changed")
    if reserve_offset < FDT_HEADER_BYTES or reserve_offset % 8:
        fail("FIT reserve-map offset is invalid")
    if structure_offset < reserve_offset + 16 or structure_offset % 4:
        fail("FIT structure offset is invalid")
    structure_end = _checked_end(
        structure_offset, structure_size, len(blob), "structure table"
    )
    strings_end = _checked_end(
        strings_offset, strings_size, len(blob), "string table"
    )
    if structure_end > strings_offset:
        fail("FIT structure and string tables overlap")

    reserve_position = reserve_offset
    while True:
        if reserve_position + 16 > structure_offset:
            fail("FIT reserve map is unterminated")
        address, size = struct.unpack_from(">QQ", blob, reserve_position)
        reserve_position += 16
        if address == 0 and size == 0:
            break
    if any(blob[reserve_position:structure_offset]):
        fail("FIT reserve-map padding is not zero")
    if any(blob[structure_end:strings_offset]):
        fail("FIT structure padding is not zero")
    if any(blob[strings_end:]):
        fail("FIT trailing padding is not zero")

    strings = blob[strings_offset:strings_end]
    stack: list[str] = []
    nodes: set[str] = set()
    properties: dict[str, set[str]] = {}
    position = structure_offset
    root_closed = False
    saw_end = False
    timestamp_offset: int | None = None

    while position < structure_end:
        if position + 4 > structure_end:
            fail("truncated FIT structure token")
        token = struct.unpack_from(">I", blob, position)[0]
        position += 4
        if token == FDT_BEGIN_NODE:
            if root_closed:
                fail("FIT contains a node after the root node")
            try:
                name_end = blob.index(0, position, structure_end)
            except ValueError:
                fail("unterminated FIT node name")
            try:
                name = blob[position:name_end].decode("ascii")
            except UnicodeDecodeError:
                fail("non-ASCII FIT node name")
            position = (name_end + 4) & ~3
            if not stack:
                if nodes or name:
                    fail("FIT root node is malformed")
            elif not name or "/" in name:
                fail("FIT child node name is malformed")
            stack.append(name)
            path = "/" + "/".join(part for part in stack if part)
            if path in nodes:
                fail(f"duplicate FIT node: {path}")
            nodes.add(path)
            properties[path] = set()
        elif token == FDT_END_NODE:
            if not stack:
                fail("unbalanced FIT end-node token")
            stack.pop()
            if not stack:
                root_closed = True
        elif token == FDT_PROP:
            if not stack or position + 8 > structure_end:
                fail("malformed FIT property token")
            length, name_offset = struct.unpack_from(">II", blob, position)
            position += 8
            if name_offset >= len(strings):
                fail("FIT property name offset is invalid")
            try:
                name_end = strings.index(0, name_offset)
            except ValueError:
                fail("unterminated FIT property name")
            try:
                name = strings[name_offset:name_end].decode("ascii")
            except UnicodeDecodeError:
                fail("non-ASCII FIT property name")
            if not name:
                fail("empty FIT property name")
            value_end = _checked_end(position, length, structure_end, "property")
            padded_end = (value_end + 3) & ~3
            if padded_end > structure_end:
                fail("FIT property padding exceeds structure bounds")
            path = "/" + "/".join(part for part in stack if part)
            if name in properties[path]:
                fail(f"duplicate FIT property: {path}:{name}")
            properties[path].add(name)
            if name == "timestamp":
                if path != "/":
                    fail(f"FIT timestamp property is not root-level: {path}")
                if length != 4:
                    fail("FIT root timestamp property is not four bytes")
                timestamp_offset = position
            position = padded_end
        elif token == FDT_NOP:
            continue
        elif token == FDT_END:
            if not root_closed or stack:
                fail("FIT structure ended before the root node closed")
            saw_end = True
            break
        else:
            fail(f"unknown FIT structure token: {token}")

    if not saw_end:
        fail("FIT structure is missing its end token")
    if any(blob[position:structure_end]):
        fail("FIT structure tail is not zero")
    if timestamp_offset is None:
        fail("FIT root timestamp property is missing")
    return timestamp_offset


def patch_file(path: pathlib.Path, expected_old: int, replacement: int) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        fail(f"FIT input is missing: {path}")
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        fail(f"FIT input is not a regular non-symlink file: {path}")

    flags = os.O_RDWR
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        fail(f"cannot open FIT input: {error}")
    try:
        opened = os.fstat(descriptor)
        if not stat.S_ISREG(opened.st_mode):
            fail("opened FIT input is not a regular file")
        if (opened.st_dev, opened.st_ino) != (metadata.st_dev, metadata.st_ino):
            fail("FIT input changed while it was opened")
        blob = os.pread(descriptor, opened.st_size + 1, 0)
        if len(blob) != opened.st_size:
            fail("FIT input changed while it was read")
        timestamp_offset = find_root_timestamp(blob)
        current = struct.unpack_from(">I", blob, timestamp_offset)[0]
        if current != expected_old:
            fail(
                "FIT root timestamp does not match expected current value "
                f"({current} != {expected_old})"
            )

        replacement_bytes = struct.pack(">I", replacement)
        written = os.pwrite(descriptor, replacement_bytes, timestamp_offset)
        if written != len(replacement_bytes):
            fail("short write while patching FIT root timestamp")
        os.fsync(descriptor)

        expected = bytearray(blob)
        expected[timestamp_offset : timestamp_offset + 4] = replacement_bytes
        verified = os.pread(descriptor, len(blob) + 1, 0)
        if verified != expected:
            fail("FIT changed outside the root timestamp data bytes")
        if os.fstat(descriptor).st_size != len(blob):
            fail("FIT size changed while patching its root timestamp")
    finally:
        os.close(descriptor)


def main(argv: list[str]) -> None:
    if len(argv) != 4:
        fail(
            "usage: patch-fit-root-timestamp.py FIT EXPECTED_OLD_EPOCH "
            "NEW_EPOCH"
        )
    expected_old = parse_epoch(argv[2], "expected old epoch")
    replacement = parse_epoch(argv[3], "replacement epoch")
    patch_file(pathlib.Path(argv[1]), expected_old, replacement)


if __name__ == "__main__":
    main(sys.argv)
