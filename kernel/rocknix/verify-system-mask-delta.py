#!/usr/bin/env python3
"""Verify that a hermetic SYSTEM policy changed only declared mask targets."""

from __future__ import annotations

import pathlib
import sys


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def read_inventory(path: pathlib.Path) -> dict[str, list[str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].split("\t")[:2] != ["path", "type"]:
        fail(f"malformed inventory: {path}")
    records: dict[str, list[str]] = {}
    for line in lines[1:]:
        fields = line.split("\t")
        if len(fields) != 10 or not fields[0] or fields[0] in records:
            fail(f"malformed inventory record: {path}")
        records[fields[0]] = fields
    return records


def read_masks(path: pathlib.Path) -> set[str]:
    masks: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) != 2 or fields[0] != "mask" or fields[1] in masks:
            fail("malformed or duplicate mask policy")
        target = fields[1]
        parts = pathlib.PurePosixPath(target).parts
        if not parts or target.startswith("/") or any(part in ("", ".", "..") for part in parts):
            fail("unsafe mask policy path")
        masks.add(target)
    if not masks:
        fail("empty mask policy")
    return masks


def main() -> None:
    if len(sys.argv) != 4:
        fail("usage: verify-system-mask-delta.py BEFORE AFTER MASKS")
    before = read_inventory(pathlib.Path(sys.argv[1]))
    after = read_inventory(pathlib.Path(sys.argv[2]))
    masks = read_masks(pathlib.Path(sys.argv[3]))
    changed = {path for path in before.keys() | after.keys() if before.get(path) != after.get(path)}
    if changed != masks:
        fail(f"mask policy changed unexpected paths: {sorted(changed ^ masks)}")
    for target in masks:
        fields = after.get(target)
        if fields is None or fields[1] != "symlink" or fields[2:5] != ["0777", "0", "0"]:
            fail(f"mask target has wrong identity: {target}")
        if fields[6] != "9" or fields[7] != "/dev/null":
            fail(f"mask target does not resolve to /dev/null: {target}")
    print(f"verified-mask-targets\t{len(masks)}")


if __name__ == "__main__":
    main()
