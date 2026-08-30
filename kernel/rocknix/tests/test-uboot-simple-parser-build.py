#!/usr/bin/env python3
"""Focused authority and corruption gates for fixed-path simple-parser U-Boot."""

from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import shutil
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
VERIFIER = ROOT / "kernel/rocknix/verify-uboot-simple-parser-build.py"
BUILDER = ROOT / "kernel/rocknix/build-uboot-simple-parser.sh"
PUBLICATION = ROOT / "kernel/work/bird-uboot-simple-parser-20260829"


def load():
    spec = importlib.util.spec_from_file_location("bird_simple_parser_build_test", VERIFIER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def rejected(function) -> None:
    try:
        function()
    except SystemExit:
        return
    raise AssertionError("corrupt simple-parser U-Boot authority was accepted")


def refresh_checksum(directory: pathlib.Path, name: str) -> None:
    rows = (directory / "sha256sums.txt").read_text().splitlines()
    digest = hashlib.sha256((directory / name).read_bytes()).hexdigest()
    (directory / "sha256sums.txt").write_text(
        "\n".join(digest + "  " + name if row.endswith("  " + name) else row for row in rows)
        + "\n"
    )


def main() -> None:
    verify = load()
    verifier_source = VERIFIER.read_text()
    builder_source = BUILDER.read_text()
    for source in (verifier_source, builder_source):
        assert "/dev/disk" not in source
        assert "diskutil" not in source
        assert "sudo" not in source
    assert "--network none" in builder_source
    assert "--read-only" in builder_source
    assert "for PASS in a b" in builder_source

    if not PUBLICATION.is_dir():
        print("U-Boot simple-parser build tests: PASS (pinned authority unavailable)")
        return
    verify.verify_output(PUBLICATION)

    with tempfile.TemporaryDirectory(prefix="bird-uboot-simple-parser-build-") as temp:
        root = pathlib.Path(temp)

        candidate = root / "candidate"
        shutil.copytree(PUBLICATION, candidate)
        path = candidate / "simple-parser.bin"
        data = bytearray(path.read_bytes())
        data[-1] ^= 1
        path.write_bytes(data)
        refresh_checksum(candidate, path.name)
        rejected(lambda: verify.verify_output(candidate))

        prefix = root / "prefix"
        shutil.copytree(PUBLICATION, prefix)
        path = prefix / "simple-parser-prefix-16m.bin"
        data = bytearray(path.read_bytes())
        data[verify.RAW_OFFSET - 1] ^= 1
        path.write_bytes(data)
        refresh_checksum(prefix, path.name)
        rejected(lambda: verify.verify_output(prefix))

        authority = root / "authority"
        shutil.copytree(PUBLICATION, authority)
        path = authority / "authority.tsv"
        path.write_bytes(
            path.read_bytes().replace(
                b"classification\tproduction-successor\n",
                b"classification\tmeasurement-only\n",
            )
        )
        refresh_checksum(authority, path.name)
        rejected(lambda: verify.verify_output(authority))

        config = root / "config"
        shutil.copytree(PUBLICATION, config)
        path = config / "build.config"
        path.write_bytes(
            path.read_bytes().replace(
                b"CONFIG_CMD_SYSBOOT=y\n", b"# CONFIG_CMD_SYSBOOT is not set\n"
            )
        )
        refresh_checksum(config, path.name)
        rejected(lambda: verify.verify_output(config))

    print("U-Boot simple-parser build tests: PASS")


if __name__ == "__main__":
    main()
