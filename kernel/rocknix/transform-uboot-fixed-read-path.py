#!/usr/bin/env python3
"""Keep only the fixed RG34XX-SP partition/filesystem read path.

Why before: the parser boundary deliberately retained every generic storage
feature formerly selected by distro defaults so that its hardware gate isolated
only the shell change. Why change: birdOS always reads one extlinux file and its
payloads from partition 1 of the MBR-formatted BIRD FAT volume; it never writes
from U-Boot or uses filesystem, partition, Ext4, ISO, or GPT shell tooling.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "743fa795fef9bea6e20b95cf18686982a87d46806eba253dbbe0d77a6850d28e"
RESULT_SHA256 = "84a062534a8b61012be20e299b5817374670ac17f54e37f0e5c4c075cb3ee26c"
POLICY = (
    b"# CONFIG_CMD_PART is not set\n"
    b"# CONFIG_CMD_GPT is not set\n"
    b"# CONFIG_CMD_EXT2 is not set\n"
    b"# CONFIG_CMD_EXT4 is not set\n"
    b"# CONFIG_CMD_FAT is not set\n"
    b"# CONFIG_CMD_FS_GENERIC is not set\n"
    b"# CONFIG_ISO_PARTITION is not set\n"
    b"# CONFIG_EFI_PARTITION is not set\n"
    b"# CONFIG_PARTITION_UUIDS is not set\n"
    b"# CONFIG_FS_EXT4 is not set\n"
    b"# CONFIG_FAT_WRITE is not set\n"
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit("accepted simple-parser defconfig authority changed")
    for entry in POLICY.splitlines(keepends=True):
        if entry in source:
            raise SystemExit("fixed-read-path policy is already present")
    result = source + POLICY
    if sha256(result) != RESULT_SHA256:
        raise SystemExit("fixed-read-path result identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing simple-parser defconfig")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace fixed-read-path output")
    with args.output.open("xb") as output:
        output.write(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
