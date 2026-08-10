#!/usr/bin/env python3
"""Emit a deterministic, metadata-complete inventory of a Linux root tree."""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def safe_text(value: str, label: str) -> str:
    if "\t" in value or "\n" in value or "\r" in value or "\0" in value:
        fail(f"unsafe {label}")
    return value


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def xattr_digest(path: Path) -> str:
    try:
        names = sorted(os.listxattr(path, follow_symlinks=False))
    except (AttributeError, OSError):
        names = []
    digest = hashlib.sha256()
    for name in names:
        safe_text(name, "xattr name")
        try:
            value = os.getxattr(path, name, follow_symlinks=False)
        except OSError as exc:
            fail(f"cannot read xattr {name!r} on {path}: {exc}")
        digest.update(name.encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
        digest.update(value)
        digest.update(b"\0")
    return digest.hexdigest() if names else "-"


def classify(mode: int) -> str:
    if stat.S_ISREG(mode):
        return "file"
    if stat.S_ISDIR(mode):
        return "dir"
    if stat.S_ISLNK(mode):
        return "symlink"
    if stat.S_ISBLK(mode):
        return "block"
    if stat.S_ISCHR(mode):
        return "char"
    if stat.S_ISFIFO(mode):
        return "fifo"
    if stat.S_ISSOCK(mode):
        return "socket"
    fail(f"unknown node type: {mode:o}")
    return ""


def collect(root: Path) -> list[tuple[str, Path, os.stat_result]]:
    records: list[tuple[str, Path, os.stat_result]] = []
    pending = [root]
    while pending:
        directory = pending.pop()
        try:
            entries = sorted(os.scandir(directory), key=lambda entry: os.fsencode(entry.name))
        except OSError as exc:
            fail(f"cannot scan {directory}: {exc}")
        child_dirs: list[Path] = []
        for entry in entries:
            path = Path(entry.path)
            relative = os.fsdecode(os.path.relpath(os.fsencode(path), os.fsencode(root)))
            relative = safe_text(relative, "path")
            try:
                metadata = path.lstat()
            except OSError as exc:
                fail(f"cannot stat {relative}: {exc}")
            records.append((relative, path, metadata))
            if stat.S_ISDIR(metadata.st_mode):
                child_dirs.append(path)
        pending.extend(reversed(child_dirs))
    records.sort(key=lambda record: os.fsencode(record[0]))
    return records


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root")
    args = parser.parse_args()

    root = Path(args.root)
    if root.is_symlink() or not root.is_dir():
        fail("root must be a non-symlink directory")
    records = collect(root)

    hardlinks: dict[tuple[int, int], list[str]] = {}
    for relative, _path, metadata in records:
        if stat.S_ISREG(metadata.st_mode) and metadata.st_nlink > 1:
            hardlinks.setdefault((metadata.st_dev, metadata.st_ino), []).append(relative)
    hardlink_authority = {
        key: min(paths, key=os.fsencode) for key, paths in hardlinks.items()
    }

    print("path\ttype\tmode\tuid\tgid\tmtime_ns\tsize\tcontent\thardlink\txattrs")
    for relative, path, metadata in records:
        node_type = classify(metadata.st_mode)
        content = "-"
        size = metadata.st_size
        if node_type == "file":
            content = file_sha256(path)
        elif node_type == "symlink":
            content = safe_text(os.readlink(path), "symlink target")
        elif node_type in {"block", "char"}:
            content = f"{os.major(metadata.st_rdev)}:{os.minor(metadata.st_rdev)}"
        hardlink = "-"
        key = (metadata.st_dev, metadata.st_ino)
        if key in hardlink_authority:
            hardlink = hardlink_authority[key]
        fields = (
            relative,
            node_type,
            f"{stat.S_IMODE(metadata.st_mode):04o}",
            str(metadata.st_uid),
            str(metadata.st_gid),
            str(metadata.st_mtime_ns),
            str(size),
            content,
            hardlink,
            xattr_digest(path),
        )
        print("\t".join(fields))
    return 0


if __name__ == "__main__":
    sys.exit(main())
