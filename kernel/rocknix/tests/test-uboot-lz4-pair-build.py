#!/usr/bin/env python3
"""Focused corruption gates for the uninstrumented U-Boot/LZ4 pair."""

from __future__ import annotations

import importlib.util
import pathlib
import shutil
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
VERIFIER = ROOT / "kernel/rocknix/verify-uboot-lz4-pair-build.py"
ARTIFACT = ROOT / "kernel/work/bird-uboot-lz4-pair-diagnostic-20260813"
PUBLICATION = ROOT / "kernel/work/bird-uboot-lz4-pair-20260813"


def load():
    spec = importlib.util.spec_from_file_location("bird_lz4_pair_build_test", VERIFIER)
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
    raise AssertionError("corrupt LZ4-paired U-Boot authority was accepted")


def main() -> None:
    verify = load()
    if not ARTIFACT.is_dir():
        print("U-Boot LZ4 pair build tests: PASS (pinned artifact unavailable)")
        return
    verify.verify(ARTIFACT)
    source = VERIFIER.read_text()
    assert "/dev/" not in source
    assert "diskutil" not in source
    if PUBLICATION.is_dir():
        verify.verify_output(PUBLICATION)

    with tempfile.TemporaryDirectory(prefix="bird-uboot-lz4-pair-test-") as temp:
        root = pathlib.Path(temp)

        corrupt = root / "combined"
        shutil.copytree(ARTIFACT, corrupt)
        path = corrupt / "a/combined.bin"
        data = bytearray(path.read_bytes())
        data[-1] ^= 1
        path.write_bytes(data)
        rejected(lambda: verify.verify(corrupt))

        mismatch = root / "repeat"
        shutil.copytree(ARTIFACT, mismatch)
        path = mismatch / "b/u-boot.bin"
        data = bytearray(path.read_bytes())
        data[100] ^= 1
        path.write_bytes(data)
        rejected(lambda: verify.verify(mismatch))

        authority = root / "authority"
        shutil.copytree(ARTIFACT, authority)
        path = authority / "authority.tsv"
        path.write_bytes(
            path.read_bytes().replace(
                b"deployment-authority\tno-diagnostic-only\n",
                b"deployment-authority\tproduction\n",
            )
        )
        rejected(lambda: verify.verify(authority))

        if PUBLICATION.is_dir():
            published = root / "published"
            shutil.copytree(PUBLICATION, published)
            path = published / "lz4-pair-prefix-16m.bin"
            data = bytearray(path.read_bytes())
            data[verify.RAW_OFFSET - 1] ^= 1
            path.write_bytes(data)
            rejected(lambda: verify.verify_output(published))

    print("U-Boot uninstrumented LZ4 pair build tests: PASS")


if __name__ == "__main__":
    main()
