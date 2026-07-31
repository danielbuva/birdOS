#!/usr/bin/env python3
"""Boundary tests for birdOS's exact PortMaster provider manifest."""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import pathlib
import stat
import sys
import tarfile
import tempfile
import unittest
import zipfile
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = ROOT / "generate-portmaster-provider-manifest.py"
MANIFEST = ROOT / "kernel/rocknix/stock-root/portmaster-provider.manifest.tsv"
SPEC = importlib.util.spec_from_file_location("bird_portmaster_generator", SOURCE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {SOURCE}")
GENERATOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = GENERATOR
SPEC.loader.exec_module(GENERATOR)

REVISION = "2026.07.28-1212"
SOURCE_URL = (
    "https://github.com/PortsMaster/PortMaster-GUI/releases/download/"
    f"{REVISION}/PortMaster.zip"
)
PRODUCTION_MANIFEST_SHA256 = (
    "5ee5703c8b16d89055c7e72124ec04be7245e6bb90af6aeb1f0ed0f6c4263b9a"
)
PRODUCTION_CHECKPOINT = (
    f"bird-portmaster-v3:{REVISION}:{PRODUCTION_MANIFEST_SHA256}"
)


def unix_zip_info(name: str, mode: int = stat.S_IFREG | 0o644) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, (2026, 7, 28, 12, 12, 0))
    info.create_system = 3
    info.external_attr = mode << 16
    info.compress_type = zipfile.ZIP_STORED
    return info


def zip_bytes(entries: list[tuple[str, bytes, int]]) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        for name, payload, mode in entries:
            archive.writestr(unix_zip_info(name, mode), payload)
    return output.getvalue()


def noto_archive_bytes() -> bytes:
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:xz") as archive:
        for index, name in enumerate(
            (
                "NotoSansHK-Regular.ttf",
                "NotoSansJP-Regular.ttf",
                "NotoSansKR-Regular.ttf",
                "NotoSansSC-Regular.ttf",
                "NotoSansTC-Regular.ttf",
            )
        ):
            payload = f"font-{index}\n".encode()
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            info.mode = 0o644
            info.mtime = 0
            archive.addfile(info, io.BytesIO(payload))
    return output.getvalue()


def synthetic_provider_archive(revision: str = REVISION) -> bytes:
    nested = zip_bytes(
        [
            (
                "pylibs/resources/NotoSans.tar.xz",
                noto_archive_bytes(),
                stat.S_IFREG | 0o644,
            ),
            (
                "pylibs/resources/DejaVuSans.ttf",
                b"dejavu\n",
                stat.S_IFREG | 0o644,
            ),
            (
                "pylibs/Folder Name/module file.py",
                b"value = 1\n",
                stat.S_IFREG | 0o644,
            ),
            ("exlibs/helper.py", b"pass\n", stat.S_IFREG | 0o644),
        ]
    )
    return zip_bytes(
        [
            (
                "PortMaster/version",
                f"{revision}\n".encode(),
                stat.S_IFREG | 0o644,
            ),
            (
                "PortMaster/pylibs.zip",
                nested,
                stat.S_IFREG | 0o644,
            ),
            (
                "PortMaster/Folder Name/file name.txt",
                b"spaces are canonical\n",
                stat.S_IFREG | 0o644,
            ),
        ]
    )


class PortMasterZipContractTests(unittest.TestCase):
    def validate_member(
        self, name: str, mode: int = stat.S_IFREG | 0o644
    ) -> None:
        archive_bytes = zip_bytes([(name, b"payload", mode)])
        with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
            GENERATOR.validate_zip_members(
                archive, "synthetic PortMaster", ("PortMaster",)
            )

    def test_canonical_ascii_spaces_are_accepted(self) -> None:
        path = "PortMaster/Folder Name/file name.txt"
        self.assertTrue(GENERATOR.safe_relative(path))
        self.validate_member(path)

    def test_noncanonical_paths_are_rejected(self) -> None:
        paths = (
            "PortMaster\\backslash.txt",
            "PortMaster/control\nbyte.txt",
            "PortMaster/control\x1fbyte.txt",
            "PortMaster//repeated.txt",
            "PortMaster/./dot.txt",
            "PortMaster/../parent.txt",
            "PortMaster/ leading.txt",
            "PortMaster/trailing.txt ",
            "PortMaster/nested/ leading.txt",
            "PortMaster/nested/trailing.txt ",
        )
        for path in paths:
            with self.subTest(path=repr(path)):
                self.assertFalse(GENERATOR.safe_relative(path))
                with self.assertRaisesRegex(ValueError, "unsafe path"):
                    self.validate_member(path)

    def test_symlinks_and_special_members_are_rejected(self) -> None:
        for mode in (stat.S_IFLNK | 0o777, stat.S_IFIFO | 0o600):
            with self.subTest(mode=oct(mode)):
                with self.assertRaisesRegex(
                    ValueError, "symlink or special member"
                ):
                    self.validate_member("PortMaster/provider-node", mode)

    def test_unknown_zip_roots_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown root"):
            self.validate_member("Unexpected/file.txt")

    def test_build_manifest_accepts_canonical_spaced_entries(self) -> None:
        files, optional_files = GENERATOR.build_manifest(
            synthetic_provider_archive(), REVISION
        )
        self.assertIn("Folder Name/file name.txt", files)
        self.assertIn("pylibs/Folder Name/module file.py", files)
        self.assertEqual(set(optional_files), {"pylibs.zip"})


class PortMasterGeneratorIdentityTests(unittest.TestCase):
    def generator_args(
        self,
        archive: pathlib.Path,
        output: pathlib.Path,
        revision: str = REVISION,
        source_url: str = SOURCE_URL,
    ) -> list[str]:
        payload = archive.read_bytes()
        return [
            str(SOURCE),
            str(archive),
            str(output),
            "--revision",
            revision,
            "--source-url",
            source_url,
            "--archive-sha256",
            hashlib.sha256(payload).hexdigest(),
            "--archive-md5",
            hashlib.md5(payload).hexdigest(),
        ]

    def test_exact_revision_and_source_url_generate_deterministically(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            archive = root / "PortMaster.zip"
            first = root / "first.tsv"
            second = root / "second.tsv"
            archive.write_bytes(synthetic_provider_archive())

            for output in (first, second):
                with mock.patch.object(
                    sys, "argv", self.generator_args(archive, output)
                ), contextlib.redirect_stdout(io.StringIO()):
                    GENERATOR.main()

            self.assertEqual(first.read_bytes(), second.read_bytes())
            text = first.read_text(encoding="utf-8")
            self.assertIn(f"revision\t{REVISION}\n", text)
            self.assertIn(f"source-url\t{SOURCE_URL}\n", text)
            self.assertEqual(text.count("optional-file\tpylibs.zip\t"), 1)

    def test_malformed_revision_and_nonexact_source_url_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            archive = root / "PortMaster.zip"
            output = root / "manifest.tsv"
            archive.write_bytes(synthetic_provider_archive())

            with mock.patch.object(
                sys,
                "argv",
                self.generator_args(
                    archive, output, revision="2026-07-28", source_url=SOURCE_URL
                ),
            ), self.assertRaisesRegex(SystemExit, "revision is malformed"):
                GENERATOR.main()

            mutable_url = (
                "https://github.com/PortsMaster/PortMaster-GUI/releases/"
                "latest/download/PortMaster.zip"
            )
            with mock.patch.object(
                sys,
                "argv",
                self.generator_args(archive, output, source_url=mutable_url),
            ), self.assertRaisesRegex(SystemExit, "explicit pinned revision"):
                GENERATOR.main()


class ProductionManifestContractTests(unittest.TestCase):
    def test_checked_in_manifest_is_canonical_and_content_addressed(self) -> None:
        payload = MANIFEST.read_bytes()
        self.assertTrue(payload.endswith(b"\n"))
        self.assertNotIn(b"\r", payload)
        self.assertEqual(
            hashlib.sha256(payload).hexdigest(), PRODUCTION_MANIFEST_SHA256
        )

        lines = payload.decode("ascii").splitlines()
        self.assertEqual(lines[0], f"schema\t{GENERATOR.SCHEMA}")
        self.assertEqual(lines[1], f"revision\t{REVISION}")
        self.assertEqual(lines[2], f"source-url\t{SOURCE_URL}")
        self.assertRegex(
            lines[3], r"^archive\t[0-9]+\t[0-9a-f]{64}\t[0-9a-f]{32}$"
        )

        records = [line.split("\t") for line in lines[4:]]
        self.assertTrue(records)
        self.assertTrue(all(len(record) == 4 for record in records))
        file_records = [record for record in records if record[0] == "file"]
        optional_records = [
            record for record in records if record[0] == "optional-file"
        ]
        self.assertEqual(records, file_records + optional_records)
        self.assertEqual(
            optional_records,
            [
                [
                    "optional-file",
                    "pylibs.zip",
                    "11287432",
                    "a38eabc5139dba7bb2906ee7ba7944f399227dda5c39590dad8e8ec3afe04f43",
                ]
            ],
        )

        paths = [record[1] for record in records]
        self.assertEqual(len(paths), len(set(paths)))
        self.assertEqual(
            [record[1] for record in file_records],
            sorted(record[1] for record in file_records),
        )
        self.assertEqual(
            [record[1] for record in optional_records],
            sorted(record[1] for record in optional_records),
        )
        for kind, path, size, digest in records:
            with self.subTest(path=path):
                self.assertIn(kind, ("file", "optional-file"))
                self.assertTrue(GENERATOR.safe_relative(path))
                self.assertRegex(size, r"^[0-9]+$")
                self.assertRegex(digest, r"^[0-9a-f]{64}$")

        checkpoint = f"bird-portmaster-v3:{REVISION}:{hashlib.sha256(payload).hexdigest()}"
        self.assertEqual(checkpoint, PRODUCTION_CHECKPOINT)


if __name__ == "__main__":
    unittest.main()
