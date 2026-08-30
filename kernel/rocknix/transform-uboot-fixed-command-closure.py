#!/usr/bin/env python3
"""Keep only the fixed RG34XX-SP U-Boot boot-command surface.

Why before: the fixed-read-path boundary deliberately retained the generic
U-Boot command surface so its hardware gate isolated storage resolution only.
Why change: birdOS autoboot uses one uninterruptible sysboot/extlinux/booti
chain; interactive debugging, mutation, alternate-image, and manual-load
commands are unreachable and need not be compiled into full U-Boot.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "84a062534a8b61012be20e299b5817374670ac17f54e37f0e5c4c075cb3ee26c"
RESULT_SHA256 = "f0fdbcf89aa47e4ec4372c63fc0bd7457d4c4f42a04476e7489a6ffb9245074a"
POLICY = (
    b"# CONFIG_CMD_BDI is not set\n"
    b"# CONFIG_CMD_CONSOLE is not set\n"
    b"# CONFIG_CMD_HELP is not set\n"
    b"# CONFIG_CMD_BOOTD is not set\n"
    b"# CONFIG_CMD_BOOTM is not set\n"
    b"# CONFIG_CMD_ELF is not set\n"
    b"# CONFIG_CMD_FDT is not set\n"
    b"# CONFIG_CMD_GO is not set\n"
    b"# CONFIG_CMD_RUN is not set\n"
    b"# CONFIG_CMD_IMI is not set\n"
    b"# CONFIG_CMD_XIMG is not set\n"
    b"# CONFIG_CMD_EXPORTENV is not set\n"
    b"# CONFIG_CMD_IMPORTENV is not set\n"
    b"# CONFIG_CMD_EDITENV is not set\n"
    b"# CONFIG_CMD_SAVEENV is not set\n"
    b"# CONFIG_CMD_ENV_EXISTS is not set\n"
    b"# CONFIG_CMD_CRC32 is not set\n"
    b"# CONFIG_CMD_MEMORY is not set\n"
    b"# CONFIG_CMD_LZMADEC is not set\n"
    b"# CONFIG_CMD_UNLZ4 is not set\n"
    b"# CONFIG_CMD_UNZIP is not set\n"
    b"CONFIG_LZ4=y\n"
    b"# CONFIG_CMD_BIND is not set\n"
    b"# CONFIG_CMD_DM is not set\n"
    b"# CONFIG_CMD_LOADB is not set\n"
    b"# CONFIG_CMD_LOADS is not set\n"
    b"# CONFIG_CMD_PINMUX is not set\n"
    b"# CONFIG_CMD_ECHO is not set\n"
    b"# CONFIG_CMD_ITEST is not set\n"
    b"# CONFIG_CMD_SOURCE is not set\n"
    b"# CONFIG_CMD_SETEXPR is not set\n"
    b"# CONFIG_CMD_BLOCK_CACHE is not set\n"
    b"# CONFIG_CMD_SLEEP is not set\n"
    b"# CONFIG_CMD_CYCLIC is not set\n"
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit("accepted fixed-read-path defconfig authority changed")
    for entry in POLICY.splitlines(keepends=True):
        if entry in source:
            raise SystemExit("fixed-command-closure policy is already present")
    result = source + POLICY
    if sha256(result) != RESULT_SHA256:
        raise SystemExit("fixed-command-closure result identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing fixed-read-path defconfig")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace fixed-command-closure output")
    with args.output.open("xb") as output:
        output.write(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
