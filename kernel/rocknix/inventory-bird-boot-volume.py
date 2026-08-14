#!/usr/bin/env python3
"""Emit a deterministic inventory of birdOS-owned BIRD volume bytes."""

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


def ignored_name(name: str) -> bool:
    """Match exactly the host metadata the BIRD builders already ignore."""

    return name.startswith("._") or name in IGNORED_NAMES


def hash_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(HASH_CHUNK_BYTES):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(root: pathlib.Path) -> list[InventoryEntry]:
    root = pathlib.Path(root)
    root_mode = root.lstat().st_mode
    if stat.S_ISLNK(root_mode):
        raise ValueError(f"BIRD root is a symlink: {root}")
    if not stat.S_ISDIR(root_mode):
        raise ValueError(f"BIRD root is not a directory: {root}")

    entries: list[InventoryEntry] = []

    def visit(directory: pathlib.Path, relative_directory: pathlib.PurePath) -> None:
        with os.scandir(directory) as children:
            ordered = sorted(children, key=lambda child: os.fsencode(child.name))
            for child in ordered:
                relative = relative_directory / child.name
                relative_text = relative.as_posix()
                mode = child.stat(follow_symlinks=False).st_mode

                if any(character in relative_text for character in "\t\r\n"):
                    raise ValueError(
                        f"TSV-unsafe path rejected in BIRD: {relative_text!r}"
                    )
                if stat.S_ISLNK(mode):
                    raise ValueError(f"symlink rejected in BIRD: {relative_text}")
                if not stat.S_ISDIR(mode) and not stat.S_ISREG(mode):
                    raise ValueError(
                        f"special node rejected in BIRD: {relative_text}"
                    )
                if ignored_name(child.name):
                    continue

                child_path = pathlib.Path(child.path)
                if stat.S_ISDIR(mode):
                    entries.append(InventoryEntry(relative_text, "dir", 0, "-"))
                    visit(child_path, relative)
                else:
                    child_size = child.stat(follow_symlinks=False).st_size
                    entries.append(
                        InventoryEntry(
                            relative_text,
                            "file",
                            child_size,
                            hash_file(child_path),
                        )
                    )

    visit(root, pathlib.PurePath())
    return sorted(entries, key=lambda item: os.fsencode(item.path))


def render_inventory(root: pathlib.Path) -> bytes:
    lines = [entry.line() for entry in inventory(root)]
    return (("\n".join(lines) + "\n") if lines else "").encode(
        "utf-8", "surrogateescape"
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="inventory birdOS-owned BIRD bytes while ignoring macOS metadata"
    )
    parser.add_argument("root", type=pathlib.Path)
    args = parser.parse_args()
    try:
        output = render_inventory(args.root)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    sys.stdout.buffer.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
