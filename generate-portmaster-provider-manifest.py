#!/usr/bin/env python3
"""Generate birdOS's offline PortMaster managed-provider manifest.

The input must be one exact, explicitly selected upstream release archive.
Deployment never follows the mutable ``latest`` URL.  Runtime-owned adapters,
downloaded port metadata/runtimes, logs, caches and user autoinstall content are
excluded deliberately; all remaining provider code and the expanded nested
Python payload are content-addressed.
"""

from __future__ import annotations

import argparse
import hashlib
import io
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
import zipfile


SCHEMA = "bird-portmaster-provider-v1"
REVISION_RE = re.compile(r"[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]{4}")
SOURCE_URL_PREFIX = (
    "https://github.com/PortsMaster/PortMaster-GUI/releases/download/"
)
SAFE_PATH_RE = re.compile(r"[A-Za-z0-9._ -]+(?:/[A-Za-z0-9._ -]+)*")
NOTO_FONT_NAMES = {
    "NotoSansHK-Regular.ttf",
    "NotoSansJP-Regular.ttf",
    "NotoSansKR-Regular.ttf",
    "NotoSansSC-Regular.ttf",
    "NotoSansTC-Regular.ttf",
}
OUTER_EXCLUDED_FILES = {
    "control.txt",
    "gamecontrollerdb.txt",
    "oga_controls",
    "oga_controls_settings.txt",
    "post-install",
    "resources/do_init",
    "tasksetter",
}
EXCLUDED_PREFIXES = (
    ".Backup/",
    "autoinstall/",
    "config/",
    "controller_layout/",
    "libs/",
    "runtimes/",
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_relative(path: str) -> bool:
    return SAFE_PATH_RE.fullmatch(path) is not None and all(
        part not in ("", ".", "..") and part == part.strip()
        for part in path.split("/")
    )


def excluded(path: str) -> bool:
    return (
        path in OUTER_EXCLUDED_FILES
        or path.startswith(EXCLUDED_PREFIXES)
    )


def validate_zip_members(
    archive: zipfile.ZipFile, label: str, required_roots: tuple[str, ...]
) -> list[zipfile.ZipInfo]:
    infos = archive.infolist()
    names = [info.filename for info in infos]
    if len(names) != len(set(names)):
        raise ValueError(f"{label} archive has duplicate paths")
    for info in infos:
        if info.flag_bits & 1:
            raise ValueError(f"{label} archive has an encrypted member")
        name = info.filename[:-1] if info.is_dir() else info.filename
        if not safe_relative(name):
            raise ValueError(f"{label} archive has an unsafe path: {info.filename!r}")
        if not any(
            name == root or name.startswith(f"{root}/")
            for root in required_roots
        ):
            raise ValueError(f"{label} archive member has an unknown root")
        mode = (info.external_attr >> 16) & 0xFFFF
        if info.create_system != 3:
            raise ValueError(f"{label} archive member lacks Unix type metadata")
        if info.is_dir():
            if not stat.S_ISDIR(mode):
                raise ValueError(f"{label} directory type metadata is inconsistent")
        elif not stat.S_ISREG(mode):
            raise ValueError(f"{label} archive contains a symlink or special member")
        if "/__pycache__/" in f"/{name}/" or name.endswith(".pyc"):
            raise ValueError(f"{label} archive contains executable Python cache bytes")
    return infos


def add_file(files: dict[str, tuple[int, str]], path: str, data: bytes) -> None:
    if not safe_relative(path):
        raise ValueError(f"unsafe archive path: {path!r}")
    record = (len(data), sha256(data))
    previous = files.setdefault(path, record)
    if previous != record:
        raise ValueError(f"generated provider path has conflicting bytes: {path}")


def build_manifest(
    archive: bytes, revision: str
) -> tuple[dict[str, tuple[int, str]], dict[str, tuple[int, str]]]:
    files: dict[str, tuple[int, str]] = {}
    with zipfile.ZipFile(io.BytesIO(archive)) as outer:
        infos = validate_zip_members(outer, "outer PortMaster", ("PortMaster",))
        version = outer.read("PortMaster/version")
        if version != f"{revision}\n".encode():
            raise ValueError("outer PortMaster version does not match requested revision")
        nested_archive = outer.read("PortMaster/pylibs.zip")
        for info in infos:
            name = info.filename
            if info.is_dir():
                continue
            relative = name.removeprefix("PortMaster/")
            if relative == "pylibs.zip":
                continue
            if excluded(relative):
                continue
            add_file(files, relative, outer.read(name))

    noto_fonts: dict[str, bytes] = {}
    with zipfile.ZipFile(io.BytesIO(nested_archive)) as nested:
        infos = validate_zip_members(
            nested, "nested PortMaster Python", ("pylibs", "exlibs")
        )
        for info in infos:
            name = info.filename
            if info.is_dir():
                continue
            if name == "pylibs/resources/NotoSans.tar.xz":
                noto = nested.read(name)
                with tarfile.open(fileobj=io.BytesIO(noto), mode="r:xz") as fonts:
                    members = fonts.getmembers()
                    if len(members) != 5 or not all(
                        member.isfile() for member in members
                    ):
                        raise ValueError("NotoSans payload does not contain five fonts")
                    for member in members:
                        basename = PurePosixPath(member.name).name
                        if (
                            basename != member.name
                            or not safe_relative(basename)
                            or not basename.endswith(".ttf")
                            or basename in noto_fonts
                        ):
                            raise ValueError("unsafe NotoSans payload member")
                        stream = fonts.extractfile(member)
                        if stream is None:
                            raise ValueError("NotoSans payload member is unreadable")
                        noto_fonts[basename] = stream.read()
                    if set(noto_fonts) != NOTO_FONT_NAMES:
                        raise ValueError("NotoSans payload has the wrong fixed font set")
                continue
            if excluded(name):
                continue
            add_file(files, name, nested.read(name))

    for basename, data in sorted(noto_fonts.items()):
        add_file(files, f"pylibs/resources/{basename}", data)
        add_file(files, f"resources/{basename}", data)
    dejavu = files["pylibs/resources/DejaVuSans.ttf"]
    files["resources/DejaVuSans.ttf"] = dejavu
    nested_md5 = hashlib.md5(nested_archive).hexdigest().encode()  # upstream format
    add_file(files, "pylibs.zip.md5", nested_md5)
    optional_files = {"pylibs.zip": (len(nested_archive), sha256(nested_archive))}
    return files, optional_files


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--archive-sha256", required=True)
    parser.add_argument("--archive-md5", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if REVISION_RE.fullmatch(args.revision) is None:
        raise SystemExit("PortMaster revision is malformed")
    expected_source_url = (
        f"{SOURCE_URL_PREFIX}{args.revision}/PortMaster.zip"
    )
    if args.source_url != expected_source_url:
        raise SystemExit(
            "PortMaster source URL does not match the explicit pinned revision"
        )
    if re.fullmatch(r"[0-9a-f]{64}", args.archive_sha256) is None:
        raise SystemExit("PortMaster archive SHA-256 is malformed")
    if re.fullmatch(r"[0-9a-f]{32}", args.archive_md5) is None:
        raise SystemExit("PortMaster archive MD5 is malformed")
    archive = args.archive.read_bytes()
    digest = sha256(archive)
    if digest != args.archive_sha256:
        raise SystemExit("PortMaster archive SHA-256 differs from the pinned value")
    if hashlib.md5(archive).hexdigest() != args.archive_md5:  # provenance only
        raise SystemExit("PortMaster archive MD5 differs from upstream metadata")
    files, optional_files = build_manifest(archive, args.revision)
    lines = [
        f"schema\t{SCHEMA}",
        f"revision\t{args.revision}",
        f"source-url\t{args.source_url}",
        f"archive\t{len(archive)}\t{digest}\t{args.archive_md5}",
    ]
    lines.extend(
        f"file\t{path}\t{size}\t{file_sha}"
        for path, (size, file_sha) in sorted(files.items())
    )
    lines.extend(
        f"optional-file\t{path}\t{size}\t{file_sha}"
        for path, (size, file_sha) in sorted(optional_files.items())
    )
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(
        f"generated {args.output}: revision={args.revision} files={len(files)} "
        f"archive_sha256={digest}"
    )


if __name__ == "__main__":
    main()
