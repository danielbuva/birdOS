#!/usr/bin/env python3
"""Boundary tests for birdOS's shared catalogue-path contract."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = ROOT / "generate-launcher-catalog.py"
SPEC = importlib.util.spec_from_file_location("bird_catalog_generator", SOURCE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {SOURCE}")
CATALOG = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CATALOG
SPEC.loader.exec_module(CATALOG)


class CatalogPathContractTests(unittest.TestCase):
    def path_of_bytes(self, size: int) -> str:
        prefix = "/mnt/mmc/"
        self.assertLessEqual(len(prefix), size)
        return prefix + "a" * (size - len(prefix))

    def test_supported_boundaries(self) -> None:
        for size in (511, 512, 513, 1024, 4085):
            path = self.path_of_bytes(size)
            self.assertEqual(
                CATALOG.checked_catalog_path(path, f"{size}-byte test"), path
            )

    def test_first_unsupported_length(self) -> None:
        with self.assertRaisesRegex(SystemExit, "4086 UTF-8 bytes"):
            CATALOG.checked_catalog_path(self.path_of_bytes(4086), "oversized test")

    def test_protocol_and_control_bytes_are_rejected(self) -> None:
        for byte in ("\n", "\r", "\t", "\x01", "\x1f", "\x7f"):
            with self.subTest(byte=ord(byte)):
                with self.assertRaises(SystemExit):
                    CATALOG.checked_catalog_path(
                        f"/mnt/mmc/ROMS/test{byte}name.zip", "control-byte test"
                    )

    def test_limit_is_emitted_for_the_launcher(self) -> None:
        rendered = CATALOG.render([], [])
        self.assertIn("#define CATALOG_PATH_MAX_BYTES 4085U", rendered)


if __name__ == "__main__":
    unittest.main()
