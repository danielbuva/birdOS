#!/usr/bin/env python3
"""Prove that a SYSTEM candidate changes only the pinned kernel module tree."""

from __future__ import annotations

import csv
import sys
from pathlib import Path


PREFIX = "usr/lib/kernel-overlays/base/"


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def read_inventory(path: Path) -> dict[str, tuple[str, ...]]:
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.reader(stream, delimiter="\t"))
    if not rows or rows[0] != [
        "path", "type", "mode", "uid", "gid", "mtime_ns", "size",
        "content", "hardlink", "xattrs",
    ]:
        fail(f"invalid inventory header: {path}")
    records: dict[str, tuple[str, ...]] = {}
    for row in rows[1:]:
        if len(row) != 10 or not row[0] or row[0] in records:
            fail(f"invalid inventory record: {path}")
        records[row[0]] = tuple(row[1:])
    return records


def main() -> int:
    if len(sys.argv) != 4:
        fail("usage: verify-source-kernel-system-delta.py INPUT POLICY MODULES")
    before = read_inventory(Path(sys.argv[1]))
    after = read_inventory(Path(sys.argv[2]))
    modules = read_inventory(Path(sys.argv[3]))

    expected_modules = {
        PREFIX + path: record for path, record in modules.items()
        if path.startswith("lib/modules/7.0.11")
    }
    changed = sorted(path for path in set(before) | set(after)
                     if before.get(path) != after.get(path))
    if not changed:
        fail("source module policy changed no nodes")
    outside = [path for path in changed if not path.startswith(PREFIX + "lib/modules/7.0.11")]
    if outside:
        fail(f"source module policy changed outside module tree: {outside[0]}")

    actual_modules = {
        path: record for path, record in after.items()
        if path.startswith(PREFIX + "lib/modules/7.0.11")
    }
    if actual_modules != expected_modules:
        missing = sorted(set(expected_modules) - set(actual_modules))
        extra = sorted(set(actual_modules) - set(expected_modules))
        mismatched = sorted(
            path for path in set(expected_modules) & set(actual_modules)
            if expected_modules[path] != actual_modules[path]
        )
        detail = (missing or extra or mismatched or ["unknown"])[0]
        fail(f"installed source module inventory mismatch: {detail}")

    unchanged = [
        path for path in set(before) | set(after)
        if not path.startswith(PREFIX + "lib/modules/7.0.11")
        and before.get(path) != after.get(path)
    ]
    if unchanged:
        fail(f"unrelated SYSTEM node changed: {sorted(unchanged)[0]}")

    print(f"verified-source-module-nodes\t{len(actual_modules)}")
    print(f"verified-changed-nodes\t{len(changed)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
