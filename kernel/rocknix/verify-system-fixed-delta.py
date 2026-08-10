#!/usr/bin/env python3
"""Verify the exact masks and fixed files baked into a hermetic SYSTEM."""

from __future__ import annotations

import pathlib
import sys


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def safe_relative(value: str, label: str) -> None:
    parts = pathlib.PurePosixPath(value).parts
    if (
        not parts
        or value.startswith("/")
        or any(part in ("", ".", "..") for part in parts)
        or any(char in value for char in "\t\r\n\0")
    ):
        fail(f"unsafe {label}")


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
        safe_relative(fields[1], "mask target")
        masks.add(fields[1])
    if not masks:
        fail("empty mask policy")
    return masks


def read_overrides(path: pathlib.Path) -> dict[str, tuple[str, str, str]]:
    overrides: dict[str, tuple[str, str, str]] = {}
    sources: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) != 5 or fields[0] != "file":
            fail("malformed fixed-file policy")
        source, target, mode, digest = fields[1:]
        safe_relative(source, "override source")
        safe_relative(target, "override target")
        if "/" in source or source in sources or target in overrides:
            fail("duplicate or nested override source/target")
        if mode != "0644" or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            fail("invalid override mode or digest")
        sources.add(source)
        overrides[target] = (source, mode, digest)
    if not overrides:
        fail("empty fixed-file policy")
    return overrides


def main() -> None:
    if len(sys.argv) != 5:
        fail("usage: verify-system-fixed-delta.py BEFORE AFTER MASKS OVERRIDES")
    before = read_inventory(pathlib.Path(sys.argv[1]))
    after = read_inventory(pathlib.Path(sys.argv[2]))
    masks = read_masks(pathlib.Path(sys.argv[3]))
    overrides = read_overrides(pathlib.Path(sys.argv[4]))
    if masks & overrides.keys():
        fail("mask and fixed-file targets overlap")
    expected = masks | overrides.keys()
    changed = {path for path in before.keys() | after.keys() if before.get(path) != after.get(path)}
    if changed != expected:
        fail(f"fixed policy changed unexpected paths: {sorted(changed ^ expected)}")
    for target in masks:
        fields = after.get(target)
        if fields is None or fields[1] != "symlink" or fields[2:5] != ["0777", "0", "0"]:
            fail(f"mask target has wrong identity: {target}")
        if fields[6] != "9" or fields[7] != "/dev/null":
            fail(f"mask target does not resolve to /dev/null: {target}")
    for target, (_source, mode, digest) in overrides.items():
        fields = after.get(target)
        if fields is None or fields[1] != "file" or fields[2:5] != [mode, "0", "0"]:
            fail(f"fixed-file target has wrong identity: {target}")
        if fields[7] != digest or fields[8:] != ["-", "-"]:
            fail(f"fixed-file target has wrong content or metadata: {target}")
    print(f"verified-mask-targets\t{len(masks)}")
    print(f"verified-fixed-file-targets\t{len(overrides)}")


if __name__ == "__main__":
    main()
