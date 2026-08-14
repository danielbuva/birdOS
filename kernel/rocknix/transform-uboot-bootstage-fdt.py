#!/usr/bin/env python3
"""Instrument the accepted in-place U-Boot through the Linux device tree.

Why before: bootstage preparation originally predated acceptance of the
in-place initrd/DTB handoff, so accepted fast-init was its correct base.
Why change: the measurement build must now inherit the physically accepted
in-place policy and its exact board environment selection without reopening
either handoff decision.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


SOURCE_SHA256 = "0254301f87e2222f04c67a34e5351bce16ebaac712bd96cc096f76027d9ded13"
RESULT_SHA256 = "ba2ab6692aff37a163324e34717649780099ec0ec9cb57e7941b58f286788cc9"
ENV_SELECTION = b'CONFIG_ENV_SOURCE_FILE="bird-rg34xx-sp-handoff"\n'
POLICY = (
    b"CONFIG_BOOTSTAGE=y\n"
    b"CONFIG_BOOTSTAGE_FDT=y\n"
    b"# CONFIG_BOOTSTAGE_REPORT is not set\n"
    b"# CONFIG_CMD_BOOTSTAGE is not set\n"
    b"# CONFIG_SPL_BOOTSTAGE is not set\n"
    b"# CONFIG_BOOTSTAGE_STASH is not set\n"
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> bytes:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit("accepted in-place handoff defconfig authority changed")
    if source.count(b"CONFIG_ENV_SOURCE_FILE=") != 1 or source.count(ENV_SELECTION) != 1:
        raise SystemExit("accepted in-place handoff environment authority changed")
    if b"BOOTSTAGE" in source:
        raise SystemExit("bootstage policy authority is ambiguous")

    result = source + POLICY
    if sha256(result) != RESULT_SHA256:
        raise SystemExit("bootstage-FDT result identity changed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing in-place handoff defconfig")
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("refusing to replace bootstage-FDT output")
    with args.output.open("xb") as output:
        output.write(transform(args.source.read_bytes()))


if __name__ == "__main__":
    main()
