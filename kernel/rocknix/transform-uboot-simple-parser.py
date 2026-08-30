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
RESULT_SHA256 = "743fa795fef9bea6e20b95cf18686982a87d46806eba253dbbe0d77a6850d28e"
POLICY = (
    b"# CONFIG_DISTRO_DEFAULTS is not set\n"
    # Preserve the exact generic-boot closure selected by DISTRO_DEFAULTS.
    # These are deliberately retained here; later subsystem subtraction must
    # cross its own independently reviewable build and hardware boundary.
    b"CONFIG_ENV_VARS_UBOOT_CONFIG=y\n"
    b"CONFIG_PXE_UTILS=y\n"
    b"CONFIG_SUPPORT_RAW_INITRD=y\n"
    b"CONFIG_USE_BOOTCOMMAND=y\n"
    b"CONFIG_MENU=y\n"
    b"CONFIG_CMD_PART=y\n"
    b"CONFIG_CMD_SYSBOOT=y\n"
    b"CONFIG_CMD_EXT2=y\n"
    b"CONFIG_CMD_EXT4=y\n"
    b"CONFIG_CMD_FAT=y\n"
    b"CONFIG_CMD_FS_GENERIC=y\n"
    b"CONFIG_DOS_PARTITION=y\n"
    b"CONFIG_ISO_PARTITION=y\n"
    b"CONFIG_FS_EXT4=y\n"
    b"CONFIG_FS_FAT=y\n"
    b"CONFIG_FAT_WRITE=y\n"
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
