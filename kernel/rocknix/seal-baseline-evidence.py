#!/usr/bin/env python3
"""Seal a completed out-of-tree baseline artifact with a canonical inventory."""

from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import stat


ROOT = pathlib.Path(__file__).resolve().parents[2]


def digest(path: pathlib.Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=pathlib.Path)
    args = parser.parse_args()
    artifact = args.artifact.resolve()
    try:
        artifact.relative_to(ROOT)
    except ValueError:
        pass
    else:
        raise SystemExit("live measurement artifact must be sealed outside the repository")
    if not artifact.is_dir() or (artifact / "SEALED.sha256").exists():
        raise SystemExit("artifact is missing or already sealed")
    required = {
        "identity.tsv", "toolchain.tsv", "commands.tsv", "source.patch", "untracked.tsv",
        "boot-release.tsv", "boot-profile.tsv", "interaction-ui.tsv", "interaction-content.tsv",
        "idle-power.tsv", "suspend-power.tsv", "binary-sections.tsv", "memory.tsv", "notes.md",
        "build-flags.tsv", "environment.tsv", "external-inputs.tsv", "submodules.tsv",
        "host-gate.tsv", "hardware-gate.tsv", "card-instance.tsv",
    }
    present = {path.name for path in artifact.iterdir() if path.is_file()}
    missing = sorted(required - present)
    if missing:
        raise SystemExit(f"artifact is incomplete: {missing}")
    sample_files = {
        "boot-release.tsv", "boot-profile.tsv", "interaction-ui.tsv",
        "interaction-content.tsv", "idle-power.tsv", "suspend-power.tsv",
        "binary-sections.tsv", "memory.tsv",
    }
    empty_samples = sorted(
        name for name in sample_files
        if len((artifact / name).read_text(encoding="utf-8").splitlines()) < 2
    )
    if empty_samples:
        raise SystemExit(f"raw measurement files contain no samples: {empty_samples}")
    for path in artifact.iterdir():
        if path.is_file():
            path.chmod(0o444)
    inventory = artifact / "inventory.tsv"
    with inventory.open("x", encoding="utf-8", newline="\n") as output:
        output.write("path\ttype\tmode\tsize\tsha256\n")
        for path in sorted(artifact.rglob("*")):
            if path == inventory or path.name == "SEALED.sha256":
                continue
            info = path.lstat()
            if not stat.S_ISREG(info.st_mode):
                raise SystemExit(f"artifact contains a non-regular path: {path}")
            relative = path.relative_to(artifact).as_posix()
            output.write(f"{relative}\tfile\t{stat.S_IMODE(info.st_mode):04o}\t{info.st_size}\t{digest(path)}\n")
    root_digest = digest(inventory)
    (artifact / "SEALED.sha256").write_text(root_digest + "  inventory.tsv\n", encoding="ascii")
    inventory.chmod(0o444)
    (artifact / "SEALED.sha256").chmod(0o444)
    os.chmod(artifact, 0o555)
    print(root_digest)


if __name__ == "__main__":
    main()
