#!/usr/bin/env python3
"""Validate the fixed RG34XX-SP namespace migration contract."""

from __future__ import annotations

import pathlib
import sys


EXPECTED = {
    "runtime": ("/run/muos", "/run/bird", "replace"),
    "state": ("/storage/bird-data/MUOS/Bird", "/storage/bird-data/Bird", "fresh-retain-legacy"),
    "persistence": ("/storage/.config/bird", "/storage/bird-data/Bird/state", "copy-files-retain-legacy"),
    "games": ("/mnt/mmc/ROMS", "/storage/roms", "direct-catalog"),
    "media": ("/mnt/mmc/MEDIA", "/storage/media", "direct-catalog"),
    "bios": ("/storage/bird-data/MUOS/bios", "/storage/roms/bios", "copy-verify-retain-legacy"),
    "ports": ("/mnt/mmc/ROMS/Ports", "/storage/roms/ports", "direct-provider"),
    "logs": ("/storage/bird-data/MUOS/Bird/log", "/storage/bird-data/Bird/log", "fresh-retain-legacy"),
    "boot-state": ("/storage/bird-data/MUOS/Bird/boot-state", "/storage/bird-data/Bird/boot-state", "fresh-retain-legacy"),
    "external-runtime": ("/storage/bird-data/MUOS/runtime", "/storage/bird-data/MUOS/runtime", "pinned-external-until-image"),
}


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> None:
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).with_name("canonical-namespace-v1.tsv")
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "schema\tbird-canonical-namespace-v1":
        fail("canonical namespace schema changed")
    actual: dict[str, tuple[str, str, str]] = {}
    destinations: dict[str, str] = {}
    for number, line in enumerate(lines[1:], 2):
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 4:
            fail(f"line {number}: expected four tab-separated fields")
        kind, legacy, canonical, policy = fields
        if kind in actual:
            fail(f"line {number}: duplicate kind {kind}")
        if not legacy.startswith("/") or not canonical.startswith("/"):
            fail(f"line {number}: paths must be absolute")
        if ".." in pathlib.PurePosixPath(legacy).parts or ".." in pathlib.PurePosixPath(canonical).parts:
            fail(f"line {number}: traversal component rejected")
        if canonical in destinations and policy != "pinned-external-until-image":
            fail(f"line {number}: destination also owned by {destinations[canonical]}")
        destinations[canonical] = kind
        actual[kind] = (legacy, canonical, policy)
    if actual != EXPECTED:
        missing = sorted(set(EXPECTED) - set(actual))
        extra = sorted(set(actual) - set(EXPECTED))
        changed = sorted(k for k in set(actual) & set(EXPECTED) if actual[k] != EXPECTED[k])
        fail(f"canonical namespace contract mismatch missing={missing} extra={extra} changed={changed}")
    for kind, (legacy, canonical, policy) in actual.items():
        if legacy == canonical and policy != "pinned-external-until-image":
            fail(f"{kind}: reverse/no-op mapping is not an explicit external input")
        if canonical.startswith("/run/") and canonical != "/run/bird":
            fail(f"{kind}: noncanonical runtime root")
        if canonical.startswith("/storage/") and not canonical.startswith(("/storage/roms", "/storage/media", "/storage/bird-data/Bird", "/storage/bird-data/MUOS/runtime")):
            fail(f"{kind}: noncanonical storage root")


if __name__ == "__main__":
    main()
