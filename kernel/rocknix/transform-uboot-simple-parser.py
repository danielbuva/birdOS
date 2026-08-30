#!/usr/bin/env python3
"""Remove the unused interactive shell from the fixed RG34XX-SP boot path.

Why before: sunxi implies U-Boot's generic distro defaults, which select the
BusyBox-derived hush shell plus interactive editing, completion, tracing and
long help. Why change: birdOS has an uninterruptible one-command boot policy;
U-Boot's simple parser still expands ``${scriptaddr}``, invokes ``sysboot``,
and supports the extlinux handoff without the general shell.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "0254301f87e2222f04c67a34e5351bce16ebaac712bd96cc096f76027d9ded13"
RESULT_SHA256 = "b7ff71e0b8e40a5bbd55de96b73a8dac86279cdee58e72a54b9be0d6eee1dfc7"
POLICY = (
    b"# CONFIG_DISTRO_DEFAULTS is not set\n"
    b"# CONFIG_HUSH_PARSER is not set\n"
    b"# CONFIG_CMDLINE_EDITING is not set\n"
    b"# CONFIG_AUTO_COMPLETE is not set\n"
    b"# CONFIG_SYS_LONGHELP is not set\n"
    b"# CONFIG_SYS_XTRACE is not set\n"
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit("accepted in-place-handoff defconfig authority changed")
    for entry in POLICY.splitlines(keepends=True):
        if entry in source:
            raise SystemExit("simple-parser policy is already present")
    result = source + POLICY
    if sha256(result) != RESULT_SHA256:
        raise SystemExit("simple-parser result identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing in-place-handoff defconfig")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace simple-parser output")
    with args.output.open("xb") as output:
        output.write(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
