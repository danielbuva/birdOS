#!/usr/bin/env python3
"""Focused host tests for BIRD FAT capacity geometry and source inventory."""

from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
LAYOUT_SOURCE = ROOT / "kernel/rocknix/build-bird-layout.py"
INVENTORY_SOURCE = ROOT / "kernel/rocknix/inventory-bird-fat-source.py"


def load_source(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


LAYOUT = load_source("bird_capacity_layout", LAYOUT_SOURCE)
INVENTORY = load_source("bird_fat_source_inventory", INVENTORY_SOURCE)


class BirdLayoutTests(unittest.TestCase):
    def make_prefix(self, path: pathlib.Path) -> None:
        with path.open("wb") as image:
            image.truncate(LAYOUT.PREFIX_BYTES)
            image.seek(510)
            image.write(b"\x55\xaa")

    def run_layout(
        self, path: pathlib.Path, layout_name: str | None = None
    ) -> subprocess.CompletedProcess[str]:
        command = [sys.executable, str(LAYOUT_SOURCE)]
        if layout_name is not None:
            command.extend(("--layout", layout_name))
        command.append(str(path))
        result = subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def read_sector(self, path: pathlib.Path, sector: int) -> bytes:
        with path.open("rb") as image:
            image.seek(sector * LAYOUT.SECTOR_BYTES)
            return image.read(LAYOUT.SECTOR_BYTES)

    def test_legacy_default_preserves_current_output_and_geometry(self) -> None:
        with tempfile.TemporaryDirectory(prefix="bird-layout-legacy-") as temp:
            image = pathlib.Path(temp) / "prefix.img"
            self.make_prefix(image)
            result = self.run_layout(image)

            self.assertEqual(
                result.stdout,
                "p1 fat32 start=32768 sectors=262144\n"
                "p4 extended start=294912 sectors=999849984\n"
                "p5 root start=319488 sectors=16777216\n"
                "p6 data start=17096704 sectors=983048189\n"
                "prefix bytes=163577856\n",
            )
            mbr = self.read_sector(image, 0)
            self.assertEqual(
                LAYOUT.read_entry(mbr, 0), (0x0C, 32_768, 262_144)
            )
            self.assertEqual(
                LAYOUT.read_entry(mbr, 3),
                (0x0F, 294_912, 999_849_984),
            )

    def test_both_variants_keep_p5_and_p6_geometry_unchanged(self) -> None:
        expected_layouts = {
            "legacy-128": (262_144, 294_912, 296_960),
            "expanded-138": (282_624, 315_392, 317_440),
        }
        logical_geometry: dict[str, tuple[tuple[int, int], tuple[int, int]]] = {}
        with tempfile.TemporaryDirectory(prefix="bird-layouts-") as temp:
            temporary = pathlib.Path(temp)
            for name, layout in LAYOUT.LAYOUTS.items():
                with self.subTest(layout=name):
                    self.assertEqual(
                        (
                            layout.fat_sectors,
                            layout.extended_start,
                            layout.second_ebr,
                        ),
                        expected_layouts[name],
                    )
                    image = temporary / f"{name}.img"
                    self.make_prefix(image)
                    result = self.run_layout(image, name)
                    mbr = self.read_sector(image, 0)
                    first_ebr = self.read_sector(image, layout.extended_start)
                    second_ebr = self.read_sector(image, layout.second_ebr)
                    p5_type, p5_relative, p5_sectors = LAYOUT.read_entry(
                        first_ebr, 0
                    )
                    p6_type, p6_relative, p6_sectors = LAYOUT.read_entry(
                        second_ebr, 0
                    )

                    self.assertEqual(
                        layout.extended_start + p5_relative,
                        LAYOUT.ROOT_START,
                    )
                    self.assertEqual(
                        layout.second_ebr + p6_relative,
                        LAYOUT.DATA_START,
                    )
                    self.assertEqual(
                        LAYOUT.read_entry(mbr, 0),
                        (0x0C, LAYOUT.FAT_START, layout.fat_sectors),
                    )
                    self.assertEqual(
                        LAYOUT.read_entry(mbr, 3),
                        (
                            0x0F,
                            layout.extended_start,
                            LAYOUT.TOTAL_SECTORS - layout.extended_start,
                        ),
                    )
                    self.assertIn(
                        f"p1 fat32 start=32768 sectors={layout.fat_sectors}\n",
                        result.stdout,
                    )
                    logical_geometry[name] = (
                        (p5_type, p5_sectors),
                        (p6_type, p6_sectors),
                    )

            self.assertEqual(
                logical_geometry["legacy-128"],
                logical_geometry["expanded-138"],
            )
            self.assertEqual(
                logical_geometry["legacy-128"],
                ((0x83, 16_777_216), (0x07, 983_048_189)),
            )

    def test_geometry_assertions_reject_overlap_and_bad_ebr_order(self) -> None:
        overlapping = LAYOUT.EXPANDED_138._replace(extended_start=315_391)
        with self.assertRaisesRegex(AssertionError, "FAT must end exactly"):
            LAYOUT.assert_layout(overlapping)

        reversed_ebrs = LAYOUT.EXPANDED_138._replace(second_ebr=315_392)
        with self.assertRaisesRegex(AssertionError, "second EBR must follow"):
            LAYOUT.assert_layout(reversed_ebrs)


class BirdFatSourceInventoryTests(unittest.TestCase):
    CONTENT = {
        ".Spotlight-V100.keep": b"not the exact ignored name\n",
        ".Trashes-keep": b"not the exact ignored name\n",
        ".fseventsd-extra": b"not the exact ignored name\n",
        "alpha/file.txt": b"alpha\n",
        "z-last.bin": b"\x00\xffbird\n",
    }

    def populate(self, root: pathlib.Path, reverse: bool) -> None:
        operations = [
            ("dir", "empty", b""),
            *(
                ("file", path, content)
                for path, content in self.CONTENT.items()
            ),
            ("file", "._root-sidecar", b"ignored\n"),
            ("file", ".DS_Store", b"ignored\n"),
            ("file", "alpha/._file.txt", b"ignored\n"),
            ("file", ".Spotlight-V100/index", b"ignored\n"),
            ("file", ".Trashes/item", b"ignored\n"),
            ("file", ".fseventsd/log", b"ignored\n"),
        ]
        if reverse:
            operations.reverse()
        for kind, relative, content in operations:
            path = root / relative
            if kind == "dir":
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)

    def expected_inventory(self) -> bytes:
        entries = ["alpha\tdir\t0\t-", "empty\tdir\t0\t-"]
        for path, content in self.CONTENT.items():
            digest = hashlib.sha256(content).hexdigest()
            entries.append(f"{path}\tfile\t{len(content)}\t{digest}")
        entries.sort(key=os.fsencode)
        return ("\n".join(entries) + "\n").encode()

    def run_inventory(self, root: pathlib.Path) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            [sys.executable, str(INVENTORY_SOURCE), str(root)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_inventory_is_deterministic_and_ignores_only_named_metadata(self) -> None:
        with tempfile.TemporaryDirectory(prefix="bird-fat-inventory-") as temp:
            temporary = pathlib.Path(temp)
            first = temporary / "first"
            second = temporary / "second"
            first.mkdir()
            second.mkdir()
            self.populate(first, reverse=False)
            self.populate(second, reverse=True)

            first_result = self.run_inventory(first)
            second_result = self.run_inventory(second)
            self.assertEqual(first_result.returncode, 0, first_result.stderr)
            self.assertEqual(second_result.returncode, 0, second_result.stderr)
            self.assertEqual(first_result.stdout, second_result.stdout)
            self.assertEqual(first_result.stdout, self.expected_inventory())
            self.assertEqual(
                first_result.stdout, INVENTORY.render_inventory(first)
            )
            self.assertNotIn(b"._root-sidecar", first_result.stdout)
            self.assertNotIn(b".DS_Store", first_result.stdout)
            self.assertNotIn(b".Spotlight-V100/index", first_result.stdout)
            self.assertNotIn(b".Trashes/item", first_result.stdout)
            self.assertNotIn(b".fseventsd/log", first_result.stdout)

    def test_symlink_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="bird-fat-symlink-") as temp:
            root = pathlib.Path(temp)
            (root / "target").write_bytes(b"target\n")
            (root / "link").symlink_to("target")
            result = self.run_inventory(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"symlink rejected in FAT source: link", result.stderr)

    @unittest.skipUnless(hasattr(os, "mkfifo"), "host has no FIFO support")
    def test_special_node_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="bird-fat-special-") as temp:
            root = pathlib.Path(temp)
            os.mkfifo(root / "pipe")
            result = self.run_inventory(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"special node rejected in FAT source: pipe", result.stderr)

    def test_tsv_unsafe_paths_are_rejected(self) -> None:
        for character in ("\t", "\n", "\r"):
            with self.subTest(character=repr(character)), tempfile.TemporaryDirectory(
                prefix="bird-fat-unsafe-path-"
            ) as temp:
                root = pathlib.Path(temp)
                (root / f"unsafe{character}name").write_bytes(b"unsafe\n")
                result = self.run_inventory(root)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"TSV-unsafe path rejected", result.stderr)


if __name__ == "__main__":
    unittest.main()
