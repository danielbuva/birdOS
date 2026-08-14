#!/usr/bin/env python3
"""Focused contracts for the BIRD pre/post raw-install inventory."""

from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = ROOT / "kernel/rocknix/inventory-bird-boot-volume.py"


def load_inventory():
    spec = importlib.util.spec_from_file_location("bird_boot_inventory", SOURCE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_inventory(path: pathlib.Path) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [sys.executable, str(SOURCE), str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def main() -> None:
    module = load_inventory()
    with tempfile.TemporaryDirectory(prefix="bird-boot-inventory-test-") as temporary:
        root = pathlib.Path(temporary)
        (root / "bird-releases/dev-current/empty").mkdir(parents=True)
        payload = b"manifest bytes\n"
        manifest = root / "bird-releases/dev-current/deploy-manifest.tsv"
        manifest.write_bytes(payload)
        (root / "._bird-releases").write_bytes(b"ignored AppleDouble\n")
        (root / ".DS_Store").write_bytes(b"ignored\n")
        (root / ".Spotlight-V100").mkdir()
        (root / ".Spotlight-V100/index").write_bytes(b"ignored\n")
        (root / ".hidden-product").write_bytes(b"retained\n")

        first = run_inventory(root)
        assert first.returncode == 0, first.stderr
        assert first.stdout == module.render_inventory(root)
        assert b"._bird-releases" not in first.stdout
        assert b".DS_Store" not in first.stdout
        assert b".Spotlight-V100" not in first.stdout
        assert b".hidden-product\tfile" in first.stdout
        assert (
            hashlib.sha256(payload).hexdigest().encode("ascii") in first.stdout
        )

        order_root = root / "order"
        order_root.mkdir()
        for name in ("z", "a", "middle"):
            (order_root / name).write_text(name, encoding="ascii")
        lines = module.render_inventory(order_root).splitlines()
        assert lines == sorted(lines, key=os.fsencode)

        link = root / "unsafe-link"
        link.symlink_to(manifest)
        rejected = run_inventory(root)
        assert rejected.returncode != 0
        assert b"symlink rejected in BIRD: unsafe-link" in rejected.stderr

    print("BIRD boot-volume inventory tests: PASS")


if __name__ == "__main__":
    main()
