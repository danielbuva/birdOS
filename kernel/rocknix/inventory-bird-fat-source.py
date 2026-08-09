#!/usr/bin/env python3
"""Emit a deterministic inventory for a source tree copied into BIRD FAT."""

from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import stat
import sys
from typing import NamedTuple


IGNORED_NAMES = frozenset(
    {".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd"}
)
HASH_CHUNK_BYTES = 1024 * 1024


class InventoryEntry(NamedTuple):
    path: str
    kind: str
    size: int
    digest: str

    def line(self) -> str:
        return f"{self.path}\t{self.kind}\t{self.size}\t{self.digest}"


def hash_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(HASH_CHUNK_BYTES):
            digest.update(chunk)
    return digest.hexdigest()


def ignored_name(name: str) -> bool:
    return name.startswith("._") or name in IGNORED_NAMES


def inventory(root: pathlib.Path) -> list[InventoryEntry]:
    root = pathlib.Path(root)
    root_mode = root.lstat().st_mode
    if stat.S_ISLNK(root_mode):
        raise ValueError(f"FAT source root is a symlink: {root}")
    if not stat.S_ISDIR(root_mode):
        raise ValueError(f"FAT source root is not a directory: {root}")

    entries: list[InventoryEntry] = []

    def visit(directory: pathlib.Path, relative_directory: pathlib.PurePath) -> None:
        with os.scandir(directory) as children:
            ordered_children = sorted(
                children, key=lambda child: os.fsencode(child.name)
            )
            for child in ordered_children:
                child_path = pathlib.Path(child.path)
                relative = relative_directory / child.name
                relative_text = relative.as_posix()
                child_info = child.stat(follow_symlinks=False)
                mode = child_info.st_mode

                if any(character in relative_text for character in "\t\r\n"):
                    raise ValueError(
                        f"TSV-unsafe path rejected in FAT source: "
                        f"{relative_text!r}"
                    )

                if stat.S_ISLNK(mode):
                    raise ValueError(
                        f"symlink rejected in FAT source: {relative_text}"
                    )
                if not stat.S_ISDIR(mode) and not stat.S_ISREG(mode):
                    raise ValueError(
                        f"special node rejected in FAT source: {relative_text}"
                    )
                if ignored_name(child.name):
                    continue

                if stat.S_ISDIR(mode):
                    entries.append(
                        InventoryEntry(relative_text, "dir", 0, "-")
                    )
                    visit(child_path, relative)
                else:
                    entries.append(
                        InventoryEntry(
                            relative_text,
                            "file",
                            child_info.st_size,
                            hash_file(child_path),
                        )
                    )

    visit(root, pathlib.PurePath())
    return sorted(entries, key=lambda item: os.fsencode(item.path))


def render_inventory(root: pathlib.Path) -> bytes:
    lines = [entry.line() for entry in inventory(root)]
    if not lines:
        return b""
    return ("\n".join(lines) + "\n").encode("utf-8", "surrogateescape")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="inventory a directory tree intended for the BIRD FAT volume"
    )
    parser.add_argument("source", type=pathlib.Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        output = render_inventory(args.source)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    sys.stdout.buffer.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
