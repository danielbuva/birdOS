#!/usr/bin/env python3
"""Stop clearing the 64 MiB full-U-Boot heap while preserving SPL policy."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "784d76e328d1c1821a655176ecb805f10408f0b04f130acbb1b0e7ba38a6645a"
RESULT_SHA256 = "74d6dc38c098657e081877f321470455556ae385e1642e36151d32da2faa9bc1"
POLICY = (
    b"# CONFIG_SYS_MALLOC_CLEAR_ON_INIT is not set\n"
    b"CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT=y\n"
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit("accepted direct-extlinux defconfig authority changed")
    if b"SYS_MALLOC_CLEAR_ON_INIT" in source:
        raise SystemExit("heap-clear authority is ambiguous")
    result = source + POLICY
    if sha256(result) != RESULT_SHA256:
        raise SystemExit("no-heap-clear result identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing direct-extlinux defconfig")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace no-heap-clear output")
    with args.output.open("xb") as output:
        output.write(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
