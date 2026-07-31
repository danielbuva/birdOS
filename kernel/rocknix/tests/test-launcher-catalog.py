#!/usr/bin/env python3
"""Boundary tests for birdOS's shared catalogue-path contract."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import tempfile
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


class CatalogPathLookupTests(unittest.TestCase):
    system = CATALOG.System(
        "TEST", "TEST", (".zip",), "RETROARCH", "test_libretro.so"
    )

    def systems_with_paths(
        self, paths: tuple[str, ...]
    ) -> list[tuple[object, list[tuple[str, str, str]]]]:
        return [
            (
                self.system,
                [
                    (f"ENTRY {index}", path, f"entry-{index}.zip")
                    for index, path in enumerate(paths)
                ],
            )
        ]

    def test_duplicate_game_path_is_rejected(self) -> None:
        path = "/mnt/mmc/ROMS/TEST/duplicate.zip"
        with self.assertRaisesRegex(SystemExit, "duplicate canonical catalog path"):
            CATALOG.render(self.systems_with_paths((path, path)), [])

    def test_duplicate_path_across_game_and_media_is_rejected(self) -> None:
        path = "/mnt/mmc/shared-path.zip"
        kind = CATALOG.MediaKind("LISTEN", (".zip",), "MPV", "ext-mpv-general")
        media = [
            CATALOG.MediaCategory(
                kind,
                "ALL",
                (CATALOG.MediaEntry("DUPLICATE", path, "LISTEN/duplicate.zip"),),
            )
        ]
        with self.assertRaisesRegex(SystemExit, "duplicate canonical catalog path"):
            CATALOG.render(self.systems_with_paths((path,)), media)

    def test_game_path_order_uses_utf8_bytes(self) -> None:
        systems = self.systems_with_paths(
            (
                "/mnt/mmc/ROMS/TEST/z.zip",
                "/mnt/mmc/ROMS/TEST/a.zip",
                "/mnt/mmc/ROMS/TEST/é.zip",
            )
        )
        self.assertEqual(CATALOG.build_catalog_entry_path_order(systems, []), [1, 0, 2])
        rendered = CATALOG.render(systems, [])
        self.assertIn(
            "static const u16 "
            "catalog_entry_path_order_xor[CATALOG_ENTRY_COUNT] = {\n"
            "    1U,\n"
            "    1U,\n"
            "    0U,\n"
            "};",
            rendered,
        )

    def test_u16_game_entry_count_boundary(self) -> None:
        self.assertEqual(CATALOG.checked_game_entry_count(65536), 65536)
        with self.assertRaisesRegex(SystemExit, "65537 game entries"):
            CATALOG.checked_game_entry_count(65537)


class MediaCatalogTests(unittest.TestCase):
    def test_read_discovers_only_epub_and_pdf_for_koreader(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            media_root = pathlib.Path(directory)
            read_root = media_root / "READ"
            read_root.mkdir()
            (read_root / "Book One.epub").write_bytes(b"epub")
            (read_root / "Paper.PDF").write_bytes(b"pdf")
            (read_root / "notes.txt").write_bytes(b"text")
            (read_root / "._Book One.epub").write_bytes(b"appledouble")
            hidden = read_root / ".sources"
            hidden.mkdir()
            (hidden / "hidden.pdf").write_bytes(b"hidden")

            categories = CATALOG.discover_media(media_root)
            read_categories = [
                category
                for category in categories
                if category.kind.directory == "READ"
            ]

            self.assertEqual(len(read_categories), 1)
            category = read_categories[0]
            self.assertEqual(category.name, "ALL")
            self.assertEqual(category.kind.launcher, "KOREADER")
            self.assertEqual(category.kind.core, "ext-koreader")
            self.assertEqual(
                [entry.relative for entry in category.entries],
                ["READ/Book One.epub", "READ/Paper.PDF"],
            )

            rendered = CATALOG.render([], categories)
            self.assertIn("#define CATALOG_LAUNCH_KOREADER 7", rendered)
            self.assertIn("CATALOG_LAUNCH_KOREADER", rendered)
            self.assertIn("#define CATALOG_READ_CATEGORY_COUNT 1U", rendered)
            self.assertIn("#define CATALOG_MEDIA_ENTRY_COUNT 2U", rendered)


class CompactCatalogRepresentationTests(unittest.TestCase):
    def test_string_pool_is_exact_deterministic_and_deduplicated(self) -> None:
        pool = CATALOG.CatalogStringPool()
        first = pool.intern('SHARED "NAME" \\ PATH', "first")
        duplicate = pool.intern('SHARED "NAME" \\ PATH', "duplicate")
        utf8 = pool.intern("CAFÉ", "utf8")

        self.assertEqual(first, duplicate)
        self.assertEqual(
            bytes(pool.data),
            b'SHARED "NAME" \\ PATH\0CAF\xc3\x89\0',
        )
        self.assertEqual(utf8, len(b'SHARED "NAME" \\ PATH\0'))
        self.assertEqual(pool.size, len(pool.data))

    def test_compact_render_has_stable_offsets_and_no_pointer_tables(self) -> None:
        system = CATALOG.System(
            "TEST", "TEST SYSTEM", (".zip",), "RETROARCH", "shared-core"
        )
        kind = CATALOG.MediaKind(
            "LISTEN", (".mp3",), "MPV", "shared-core"
        )
        systems = [
            (
                system,
                [
                    (
                        'QUOTED "GAME" \\ É',
                        "/mnt/mmc/ROMS/TEST/game.zip",
                        "TEST/game.zip",
                    )
                ],
            )
        ]
        media = [
            CATALOG.MediaCategory(
                kind,
                "ALL",
                (
                    CATALOG.MediaEntry(
                        "TRACK",
                        "/mnt/mmc/MEDIA/LISTEN/track.mp3",
                        "LISTEN/track.mp3",
                    ),
                ),
            )
        ]

        rendered = CATALOG.render(systems, media)
        self.assertEqual(rendered, CATALOG.render(systems, media))
        self.assertNotIn("const char *", rendered)
        self.assertNotIn("struct catalog_entry", rendered)
        self.assertIn("static const char catalog_string_pool", rendered)
        self.assertIn("static const u32 catalog_entry_name_offsets", rendered)
        self.assertIn("static const u8 catalog_entry_systems", rendered)
        self.assertIn("#define CATALOG_RECORD_BYTES 53UL", rendered)
        self.assertIn("#define CATALOG_PATH_ORDER_BYTES 2UL", rendered)
        # The repeated core is interned once even though both logical records
        # retain stable pointers to it through their independent offsets.
        self.assertEqual(rendered.count('"shared-core\\000"'), 1)

    def test_narrow_index_and_pool_capacity_boundaries(self) -> None:
        self.assertEqual(CATALOG.checked_u8_index_count(256, "systems"), 256)
        with self.assertRaisesRegex(SystemExit, "257 systems"):
            CATALOG.checked_u8_index_count(257, "systems")
        self.assertEqual(
            CATALOG.checked_string_pool_size((1 << 32) - 1),
            (1 << 32) - 1,
        )
        with self.assertRaisesRegex(SystemExit, "4294967296 bytes"):
            CATALOG.checked_string_pool_size(1 << 32)
        self.assertEqual(
            CATALOG.checked_u32_count((1 << 32) - 1, "media entries"),
            (1 << 32) - 1,
        )
        with self.assertRaisesRegex(SystemExit, "4294967296 media entries"):
            CATALOG.checked_u32_count(1 << 32, "media entries")

    def test_c_emission_escapes_trigraph_sequences(self) -> None:
        self.assertEqual(
            CATALOG.c_bytes(b"question??/mark??=value"),
            r'"question\077\077/mark\077\077=value"',
        )
        self.assertNotIn("??/", CATALOG.c_bytes(b"question??/mark"))

    def test_embedded_nul_is_rejected_before_c_emission(self) -> None:
        pool = CATALOG.CatalogStringPool()
        with self.assertRaisesRegex(SystemExit, "embedded NUL"):
            pool.intern("invalid\0name", "synthetic")


if __name__ == "__main__":
    unittest.main()
