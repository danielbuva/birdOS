#!/usr/bin/env python3
"""Generate the birdOS RG34XX-SP launcher's embedded library catalogue."""

from __future__ import annotations

import argparse
import pathlib
import unicodedata
from dataclasses import dataclass


@dataclass(frozen=True)
class System:
    directory: str
    name: str
    extensions: tuple[str, ...]
    launcher: str
    core: str


@dataclass(frozen=True)
class MediaKind:
    directory: str
    extensions: tuple[str, ...]
    launcher: str
    core: str


@dataclass(frozen=True)
class MediaEntry:
    name: str
    path: str
    relative: str


@dataclass(frozen=True)
class MediaCategory:
    kind: MediaKind
    name: str
    entries: tuple[MediaEntry, ...]


# These provider labels are retained as catalogue metadata for compatibility
# with older indexes. The active birdOS ROCKNIX dispatcher derives its fixed
# platform/emulator/core tuple from the canonical content path rather than
# trusting these historical provider strings.
SYSTEMS = (
    System("A2600", "ATARI 2600", (".a26", ".bin", ".zip"), "RETROARCH", "stella2014_libretro.so"),
    System("ATOMISWAVE", "ATOMISWAVE", (".zip",), "RETROARCH", "flycastvl_libretro.so"),
    System("CPS1", "CAPCOM CPS I", (".zip",), "RETROARCH", "km_fbneo_xtreme_amped_libretro.so"),
    System("CPS2", "CAPCOM CPS II", (".zip",), "RETROARCH", "km_fbneo_xtreme_amped_libretro.so"),
    System("CPS3", "CAPCOM CPS III", (".zip",), "RETROARCH", "km_fbneo_xtreme_amped_libretro.so"),
    System("DOS", "DOS", (".zip", ".dosz", ".cue", ".iso"), "RETROARCH", "dosbox_pure_libretro.so"),
    System("DREAMCAST", "DREAMCAST", (".chd", ".cdi", ".gdi", ".cue"), "RETROARCH", "flycastvl_libretro.so"),
    System("FBNEO", "FINALBURN NEO", (".zip",), "RETROARCH", "km_fbneo_xtreme_amped_libretro.so"),
    System("FC", "NES FAMICOM", (".zip", ".nes", ".fds"), "RETROARCH", "fceumm_libretro.so"),
    System("GB", "GAME BOY", (".zip", ".gb"), "RETROARCH", "gambatte_libretro.so"),
    System("GBA", "GAME BOY ADVANCE", (".zip", ".gba"), "RETROARCH", "mgba_libretro.so"),
    System("GBC", "GAME BOY COLOR", (".zip", ".gbc"), "RETROARCH", "gambatte_libretro.so"),
    System("GG", "GAME GEAR", (".zip", ".gg"), "RETROARCH", "picodrive_libretro.so"),
    System("GW", "GAME AND WATCH", (".mgw",), "RETROARCH", "gw_libretro.so"),
    System("HBMAME", "HBMAME", (".zip",), "RETROARCH", "km_fbneo_xtreme_amped_libretro.so"),
    System("MAME", "MAME", (".zip",), "RETROARCH", "km_fbneo_xtreme_amped_libretro.so"),
    System("MD", "MEGA DRIVE", (".zip", ".md", ".bin", ".gen"), "RETROARCH", "genesis_plus_gx_libretro.so"),
    System("MSX", "MSX", (".zip", ".rom", ".dsk", ".cas"), "RETROARCH", "bluemsx_libretro.so"),
    System("N64", "NINTENDO 64", (".zip", ".z64", ".n64", ".v64"), "RETROARCH", "mupen64plus_next_libretro.so"),
    System("NAOMI", "NAOMI", (".zip",), "RETROARCH", "flycastvl_libretro.so"),
    System("NDS", "NINTENDO DS", (".nds", ".zip"), "DRASTIC", "ext-drastic"),
    System("OPENBOR", "OPENBOR", (".pak",), "OPENBOR", "ext-openbor7530"),
    System("PCE", "PC ENGINE", (".zip", ".pce"), "RETROARCH", "mednafen_pce_fast_libretro.so"),
    System("PICO", "PICO-8", (".zip", ".p8", ".png"), "RETROARCH", "fake08_libretro.so"),
    System("PSP", "PSP", (".cso", ".iso", ".pbp"), "PPSSPP", "ext-ppsspp"),
    System("Ports", "PORTS", (".sh",), "PORTMASTER", "external"),
    System("SNES", "SNES", (".zip", ".sfc", ".smc", ".fig", ".bs"), "RETROARCH", "snes9x_libretro.so"),
)

# Media is indexed on the Mac alongside games and compiled into the launcher.
# The active dispatcher routes LISTEN/WATCH through the pinned ROCKNIX MPV
# provider and EPUB/PDF through the installed fixed KOReader PortMaster app;
# stored labels remain inventory metadata, not launch authority.
MEDIA_KINDS = (
    MediaKind(
        "LISTEN",
        (".aac", ".flac", ".m3u", ".m3u8", ".m4a", ".mp3", ".ogg", ".opus", ".wav"),
        "MPV",
        "ext-mpv-general",
    ),
    MediaKind("READ", (".epub", ".pdf"), "KOREADER", "ext-koreader"),
    MediaKind(
        "WATCH",
        (".avi", ".m2ts", ".m4v", ".mkv", ".mov", ".mp4", ".mpeg", ".mpg", ".ts", ".webm"),
        "MPV",
        "ext-mpv-general",
    ),
)

IGNORED_DIRECTORY_NAMES = frozenset(("imgs", "images"))

# Linux accepts at most 4095 pathname bytes excluding the terminating NUL.
# The active runtime rewrites the eight-byte /mnt/mmc catalogue root to the
# eighteen-byte /storage/bird-data root, so reserve those ten expansion bytes.
# This value is emitted into catalog.generated.h and is therefore also the
# launch-request and favorites-file contract used by the freestanding launcher.
CATALOG_PATH_MAX_BYTES = 4085
CATALOG_ENTRY_INDEX_CAPACITY = 1 << 16
CATALOG_U8_INDEX_CAPACITY = 1 << 8
CATALOG_U32_MAX = (1 << 32) - 1
CATALOG_STRING_POOL_MAX_BYTES = (1 << 32) - 1


def checked_catalog_path(value: str, source: str) -> str:
    """Return *value* when it is safe for every launcher path protocol."""

    encoded = value.encode("utf-8")
    if b"\n" in encoded or b"\r" in encoded:
        raise SystemExit(
            f"{source}: catalog path contains a line delimiter and cannot be "
            f"represented by the launch/favorites protocol: {value!r}"
        )
    control = next((byte for byte in encoded if byte < 0x20 or byte == 0x7F), None)
    if control is not None:
        raise SystemExit(
            f"{source}: catalog path contains unsupported control byte "
            f"0x{control:02x}: {value!r}"
        )
    if len(encoded) > CATALOG_PATH_MAX_BYTES:
        raise SystemExit(
            f"{source}: catalog path is {len(encoded)} UTF-8 bytes; maximum is "
            f"{CATALOG_PATH_MAX_BYTES}: {value!r}"
        )
    return value


def checked_game_entry_count(count: int) -> int:
    """Return *count* when every game entry can be named by a u16 index."""

    if count > CATALOG_ENTRY_INDEX_CAPACITY:
        raise SystemExit(
            f"catalog contains {count} game entries; maximum for the u16 "
            f"path lookup index is {CATALOG_ENTRY_INDEX_CAPACITY}"
        )
    return count


def checked_u8_index_count(count: int, label: str) -> int:
    """Return *count* when its zero-based indexes fit in generated u8 data."""

    if count > CATALOG_U8_INDEX_CAPACITY:
        raise SystemExit(
            f"catalog contains {count} {label}; maximum for a u8 index is "
            f"{CATALOG_U8_INDEX_CAPACITY}"
        )
    return count


def checked_u32_count(count: int, label: str) -> int:
    """Return *count* when it fits in a generated u32 range field."""

    if count > CATALOG_U32_MAX:
        raise SystemExit(
            f"catalog contains {count} {label}; maximum for a u32 count is "
            f"{CATALOG_U32_MAX}"
        )
    return count


def checked_string_pool_size(size: int) -> int:
    """Return *size* when every generated string offset fits in a u32."""

    if size > CATALOG_STRING_POOL_MAX_BYTES:
        raise SystemExit(
            f"catalog string pool is {size} bytes; maximum for u32 offsets is "
            f"{CATALOG_STRING_POOL_MAX_BYTES}"
        )
    return size


class CatalogStringPool:
    """Deterministic exact-string interning for generated static catalogue data."""

    def __init__(self) -> None:
        self.data = bytearray()
        self.offsets: dict[bytes, int] = {}
        self.values: list[bytes] = []

    def intern(self, value: str, source: str) -> int:
        encoded = value.encode("utf-8")
        if b"\0" in encoded:
            raise SystemExit(f"{source}: catalog string contains an embedded NUL")
        existing = self.offsets.get(encoded)
        if existing is not None:
            return existing
        offset = len(self.data)
        checked_string_pool_size(offset + len(encoded) + 1)
        self.offsets[encoded] = offset
        self.values.append(encoded)
        self.data.extend(encoded)
        self.data.append(0)
        return offset

    @property
    def size(self) -> int:
        # Empty synthetic catalogues still emit one addressable NUL byte so
        # the generated C array remains valid on every supported compiler.
        return max(1, len(self.data))


def build_catalog_entry_path_order(
    systems: list[tuple[System, list[tuple[str, str, str]]]],
    media_categories: list[MediaCategory],
) -> list[int]:
    """Validate canonical path identity and return game indexes in byte order."""

    game_paths = [
        path
        for _system, entries in systems
        for _name, path, _relative in entries
    ]
    checked_game_entry_count(len(game_paths))

    seen: dict[str, str] = {}
    for game_index, path in enumerate(game_paths):
        source = f"game catalog entry {game_index}"
        checked_catalog_path(path, source)
        previous = seen.get(path)
        if previous is not None:
            raise SystemExit(
                f"duplicate canonical catalog path {path!r}: {previous} and {source}"
            )
        seen[path] = source

    for category_index, category in enumerate(media_categories):
        for entry_index, entry in enumerate(category.entries):
            source = f"media catalog entry {category_index}:{entry_index}"
            checked_catalog_path(entry.path, source)
            previous = seen.get(entry.path)
            if previous is not None:
                raise SystemExit(
                    f"duplicate canonical catalog path {entry.path!r}: "
                    f"{previous} and {source}"
                )
            seen[entry.path] = source

    return sorted(
        range(len(game_paths)),
        key=lambda index: game_paths[index].encode("utf-8"),
    )


def c_bytes(encoded: bytes) -> str:
    output: list[str] = ['"']
    for byte in encoded:
        if byte == 34:
            output.append(r'\"')
        elif byte == 92:
            output.append(r"\\")
        elif byte == 63:
            # Escaping every question mark prevents any valid filename from
            # forming a C trigraph across generated source characters.
            output.append(r"\077")
        elif 32 <= byte <= 126:
            output.append(chr(byte))
        else:
            output.append(f"\\{byte:03o}")
    output.append('"')
    return "".join(output)
def display_name(path: pathlib.Path) -> str:
    normalized = unicodedata.normalize("NFKD", path.stem)
    ascii_name = normalized.encode("ascii", "ignore").decode("ascii").upper()
    return " ".join(ascii_name.split()) or "UNTITLED"


def is_hidden_or_artwork(relative: pathlib.Path) -> bool:
    return any(
        part.startswith(".") or part.startswith("._") or part.casefold() in IGNORED_DIRECTORY_NAMES
        for part in relative.parts
    )


def discover(
    rom_root: pathlib.Path, manifest: pathlib.Path | None
) -> list[tuple[System, list[tuple[str, str, str]]]]:
    requested: set[str] | None = None
    if manifest:
        requested = {
            line.strip()
            for line in manifest.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }

    systems: list[tuple[System, list[tuple[str, str, str]]]] = []
    for system in SYSTEMS:
        system_root = rom_root / system.directory
        entries: list[tuple[str, str, str]] = []
        if system_root.is_dir():
            # PortMaster's native layout keeps each game's data and its own
            # helper scripts beside the top-level launchers. Only the latter
            # are menu entries; ROM systems may still use nested directories.
            candidates = (
                system_root.iterdir()
                if system.directory == "Ports"
                else system_root.rglob("*")
            )
            for path in candidates:
                if not path.is_file():
                    continue
                relative_path = path.relative_to(rom_root)
                if is_hidden_or_artwork(relative_path):
                    continue
                if path.suffix.lower() not in system.extensions:
                    continue
                relative = relative_path.as_posix()
                if requested is not None and relative not in requested:
                    continue
                catalog_path = checked_catalog_path(
                    f"/mnt/mmc/ROMS/{relative}", f"game entry {relative!r}"
                )
                entries.append((display_name(path), catalog_path, relative))
        entries.sort(key=lambda entry: (entry[0], entry[1]))
        if entries:
            systems.append((system, entries))

    if requested is not None:
        discovered = {
            relative
            for _system, entries in systems
            for _display, _path, relative in entries
        }
        missing = sorted(requested - discovered)
        if missing:
            raise SystemExit("manifest entries missing or unsupported:\n" + "\n".join(missing))
    return systems


def render(
    systems: list[tuple[System, list[tuple[str, str, str]]]],
    media_categories: list[MediaCategory],
) -> str:
    path_order = build_catalog_entry_path_order(systems, media_categories)
    total = len(path_order)
    media_total = sum(len(category.entries) for category in media_categories)
    checked_u8_index_count(len(systems), "systems")
    checked_u8_index_count(len(media_categories), "media categories")
    checked_u32_count(media_total, "media entries")
    section_ranges: dict[str, tuple[int, int]] = {}
    section_cursor = 0
    for kind in MEDIA_KINDS:
        count = sum(
            1
            for category in media_categories
            if category.kind.directory == kind.directory
        )
        section_ranges[kind.directory] = (section_cursor, count)
        section_cursor += count

    launch_constants = {
        "RETROARCH": "CATALOG_LAUNCH_RETROARCH",
        "PPSSPP": "CATALOG_LAUNCH_PPSSPP",
        "PORTMASTER": "CATALOG_LAUNCH_PORTMASTER",
        "DRASTIC": "CATALOG_LAUNCH_DRASTIC",
        "OPENBOR": "CATALOG_LAUNCH_OPENBOR",
    }
    media_launch_constants = {
        "MPV": "CATALOG_LAUNCH_MPV",
        "KOREADER": "CATALOG_LAUNCH_KOREADER",
    }

    pool = CatalogStringPool()
    system_name_offsets: list[int] = []
    system_core_offsets: list[int] = []
    system_firsts: list[int] = []
    system_counts: list[int] = []
    system_launch_kinds: list[str] = []
    entry_name_offsets: list[int] = []
    entry_path_offsets: list[int] = []
    entry_systems: list[int] = []
    media_category_name_offsets: list[int] = []
    media_category_core_offsets: list[int] = []
    media_category_firsts: list[int] = []
    media_category_counts: list[int] = []
    media_category_sections: list[str] = []
    media_category_launch_kinds: list[str] = []
    media_entry_name_offsets: list[int] = []
    media_entry_path_offsets: list[int] = []
    media_entry_categories: list[int] = []

    first = 0
    for system_index, (system, entries) in enumerate(systems):
        system_name_offsets.append(
            pool.intern(system.name, f"system {system_index} name")
        )
        system_core_offsets.append(
            pool.intern(system.core, f"system {system_index} core")
        )
        system_firsts.append(first)
        system_counts.append(len(entries))
        system_launch_kinds.append(launch_constants[system.launcher])
        first += len(entries)

    # Keep each system's records in presentation order. In particular, all
    # system labels precede the much larger game corpus, avoiding first-menu
    # page scattering while retaining name/path proximity for launch handoff.
    for system_index, (_system, entries) in enumerate(systems):
        for entry_index, (name, path, _relative) in enumerate(entries):
            entry_name_offsets.append(
                pool.intern(name, f"game entry {system_index}:{entry_index} name")
            )
            entry_path_offsets.append(
                pool.intern(path, f"game entry {system_index}:{entry_index} path")
            )
            entry_systems.append(system_index)

    media_first = 0
    for category_index, category in enumerate(media_categories):
        media_category_name_offsets.append(
            pool.intern(category.name, f"media category {category_index} name")
        )
        media_category_core_offsets.append(
            pool.intern(category.kind.core, f"media category {category_index} core")
        )
        media_category_firsts.append(media_first)
        media_category_counts.append(len(category.entries))
        media_category_sections.append(
            f"CATALOG_MEDIA_SECTION_{category.kind.directory}"
        )
        media_category_launch_kinds.append(
            media_launch_constants[category.kind.launcher]
        )
        media_first += len(category.entries)

    for category_index, category in enumerate(media_categories):
        for entry_index, entry in enumerate(category.entries):
            media_entry_name_offsets.append(
                pool.intern(
                    entry.name,
                    f"media entry {category_index}:{entry_index} name",
                )
            )
            media_entry_path_offsets.append(
                pool.intern(
                    entry.path,
                    f"media entry {category_index}:{entry_index} path",
                )
            )
            media_entry_categories.append(category_index)

    # These are the exact bytes emitted by the fixed-width arrays below. The
    # pool is reported separately because it is immutable string data, while
    # the path-order table remains a distinct binary-search index budget.
    record_bytes = (
        len(system_name_offsets) * 4
        + len(system_core_offsets) * 4
        + len(system_firsts) * 4
        + len(system_counts) * 4
        + len(system_launch_kinds)
        + len(entry_name_offsets) * 4
        + len(entry_path_offsets) * 4
        + len(entry_systems)
        + len(media_category_name_offsets) * 4
        + len(media_category_core_offsets) * 4
        + len(media_category_firsts) * 4
        + len(media_category_counts) * 4
        + len(media_category_sections)
        + len(media_category_launch_kinds)
        + len(media_entry_name_offsets) * 4
        + len(media_entry_path_offsets) * 4
        + len(media_entry_categories)
    )
    path_order_bytes = len(path_order) * 2
    metadata_bytes = record_bytes + path_order_bytes

    lines = [
        "/* Generated by generate-launcher-catalog.py; do not edit manually. */",
        "#ifndef BIRD_CATALOG_GENERATED_H",
        "#define BIRD_CATALOG_GENERATED_H",
        "",
        "#define CATALOG_LAUNCH_NONE 0",
        "#define CATALOG_LAUNCH_RETROARCH 1",
        "#define CATALOG_LAUNCH_PPSSPP 2",
        "#define CATALOG_LAUNCH_PORTMASTER 3",
        "#define CATALOG_LAUNCH_DRASTIC 4",
        "#define CATALOG_LAUNCH_OPENBOR 5",
        "#define CATALOG_LAUNCH_MPV 6",
        "#define CATALOG_LAUNCH_KOREADER 7",
        "#define CATALOG_MEDIA_SECTION_LISTEN 1",
        "#define CATALOG_MEDIA_SECTION_READ 2",
        "#define CATALOG_MEDIA_SECTION_WATCH 3",
        f"#define CATALOG_SYSTEM_COUNT {len(systems)}U",
        f"#define CATALOG_ENTRY_COUNT {total}U",
        f"#define CATALOG_MEDIA_CATEGORY_COUNT {len(media_categories)}U",
        f"#define CATALOG_MEDIA_ENTRY_COUNT {media_total}U",
        f"#define CATALOG_PATH_MAX_BYTES {CATALOG_PATH_MAX_BYTES}U",
        f"#define CATALOG_STRING_POOL_BYTES {pool.size}UL",
        f"#define CATALOG_RECORD_BYTES {record_bytes}UL",
        f"#define CATALOG_PATH_ORDER_BYTES {path_order_bytes}UL",
        f"#define CATALOG_METADATA_BYTES {metadata_bytes}UL",
        "#define CATALOG_STATIC_BYTES \\",
        "    (0UL + CATALOG_STRING_POOL_BYTES + CATALOG_METADATA_BYTES)",
        f"#define CATALOG_LISTEN_CATEGORY_FIRST {section_ranges['LISTEN'][0]}U",
        f"#define CATALOG_LISTEN_CATEGORY_COUNT {section_ranges['LISTEN'][1]}U",
        f"#define CATALOG_READ_CATEGORY_FIRST {section_ranges['READ'][0]}U",
        f"#define CATALOG_READ_CATEGORY_COUNT {section_ranges['READ'][1]}U",
        f"#define CATALOG_WATCH_CATEGORY_FIRST {section_ranges['WATCH'][0]}U",
        f"#define CATALOG_WATCH_CATEGORY_COUNT {section_ranges['WATCH'][1]}U",
        "",
        "/* Exact UTF-8 strings are interned once. Accessors return stable",
        " * pointers directly into this immutable, NUL-terminated pool. */",
        "static const char catalog_string_pool[CATALOG_STRING_POOL_BYTES] =",
    ]

    if pool.values:
        for index, value in enumerate(pool.values):
            # Interior literals carry an explicit terminator. The final C
            # literal supplies its implicit terminator, making sizeof(pool)
            # exactly CATALOG_STRING_POOL_BYTES without a spare byte.
            encoded = value if index + 1 == len(pool.values) else value + b"\0"
            suffix = ";" if index + 1 == len(pool.values) else ""
            lines.append(f"    {c_bytes(encoded)}{suffix}")
    else:
        lines.append(f"    {c_bytes(bytes((0,)))};")

    def append_array(
        c_type: str,
        name: str,
        bound: str,
        values: list[int] | list[str],
    ) -> None:
        lines.extend(["", f"static const {c_type} {name}[{bound}] = {{"])
        for value in values:
            lines.append(f"    {value}U," if isinstance(value, int) else f"    {value},")
        lines.append("};")

    append_array(
        "u32", "catalog_system_name_offsets", "CATALOG_SYSTEM_COUNT", system_name_offsets
    )
    append_array(
        "u32", "catalog_system_core_offsets", "CATALOG_SYSTEM_COUNT", system_core_offsets
    )
    append_array("u32", "catalog_system_firsts", "CATALOG_SYSTEM_COUNT", system_firsts)
    append_array("u32", "catalog_system_counts", "CATALOG_SYSTEM_COUNT", system_counts)
    append_array(
        "u8", "catalog_system_launch_kinds", "CATALOG_SYSTEM_COUNT", system_launch_kinds
    )
    append_array(
        "u32", "catalog_entry_name_offsets", "CATALOG_ENTRY_COUNT", entry_name_offsets
    )
    append_array(
        "u32", "catalog_entry_path_offsets", "CATALOG_ENTRY_COUNT", entry_path_offsets
    )
    append_array("u8", "catalog_entry_systems", "CATALOG_ENTRY_COUNT", entry_systems)

    lines.extend(
        [
            "",
            "/* XOR with the ordinal to recover the path-sorted game index. "
            "The permutation is mostly identity, so this keeps the fixed u16 "
            "table while making the early initramfs substantially more "
            "compressible. */",
        ]
    )
    append_array(
        "u16",
        "catalog_entry_path_order_xor",
        "CATALOG_ENTRY_COUNT",
        [entry_index ^ ordinal for ordinal, entry_index in enumerate(path_order)],
    )
    append_array(
        "u32",
        "catalog_media_category_name_offsets",
        "CATALOG_MEDIA_CATEGORY_COUNT",
        media_category_name_offsets,
    )
    append_array(
        "u32",
        "catalog_media_category_core_offsets",
        "CATALOG_MEDIA_CATEGORY_COUNT",
        media_category_core_offsets,
    )
    append_array(
        "u32",
        "catalog_media_category_firsts",
        "CATALOG_MEDIA_CATEGORY_COUNT",
        media_category_firsts,
    )
    append_array(
        "u32",
        "catalog_media_category_counts",
        "CATALOG_MEDIA_CATEGORY_COUNT",
        media_category_counts,
    )
    append_array(
        "u8",
        "catalog_media_category_sections",
        "CATALOG_MEDIA_CATEGORY_COUNT",
        media_category_sections,
    )
    append_array(
        "u8",
        "catalog_media_category_launch_kinds",
        "CATALOG_MEDIA_CATEGORY_COUNT",
        media_category_launch_kinds,
    )
    append_array(
        "u32",
        "catalog_media_entry_name_offsets",
        "CATALOG_MEDIA_ENTRY_COUNT",
        media_entry_name_offsets,
    )
    append_array(
        "u32",
        "catalog_media_entry_path_offsets",
        "CATALOG_MEDIA_ENTRY_COUNT",
        media_entry_path_offsets,
    )
    append_array(
        "u8",
        "catalog_media_entry_categories",
        "CATALOG_MEDIA_ENTRY_COUNT",
        media_entry_categories,
    )

    lines.extend(["", "#endif", ""])
    return "\n".join(lines)


def discover_media(media_root: pathlib.Path | None) -> list[MediaCategory]:
    categories: list[MediaCategory] = []
    if media_root is None or not media_root.is_dir():
        return categories
    for kind in MEDIA_KINDS:
        root = media_root / kind.directory
        if not root.is_dir():
            continue
        grouped: dict[str, list[MediaEntry]] = {}
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            relative_to_media = path.relative_to(media_root)
            if is_hidden_or_artwork(relative_to_media):
                continue
            if path.suffix.lower() not in kind.extensions:
                continue
            relative_to_kind = path.relative_to(root)
            category_name = (
                display_name(pathlib.Path(relative_to_kind.parts[0]))
                if len(relative_to_kind.parts) > 1
                else "ALL"
            )
            relative = relative_to_media.as_posix()
            catalog_path = checked_catalog_path(
                f"/mnt/mmc/MEDIA/{relative}", f"media entry {relative!r}"
            )
            grouped.setdefault(category_name, []).append(
                MediaEntry(
                    display_name(path),
                    catalog_path,
                    relative,
                )
            )
        for category_name in sorted(grouped):
            entries = tuple(
                sorted(grouped[category_name], key=lambda entry: (entry.name, entry.path))
            )
            categories.append(MediaCategory(kind, category_name, entries))
    return categories


def render_inventory(
    systems: list[tuple[System, list[tuple[str, str, str]]]],
    media_categories: list[MediaCategory],
) -> str:
    lines = ["section\tcategory\tdisplay_name\trelative_path\tlauncher\tcore"]
    for system, entries in systems:
        for name, _absolute, relative in entries:
            lines.append(
                f"PLAY\t{system.name}\t{name}\tROMS/{relative}\t"
                f"{system.launcher}\t{system.core}"
            )
    for category in media_categories:
        for entry in category.entries:
            lines.append(
                f"{category.kind.directory}\t{category.name}\t{entry.name}\t"
                f"MEDIA/{entry.relative}\t{category.kind.launcher}\t{category.kind.core}"
            )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("rom_root", type=pathlib.Path)
    parser.add_argument("--manifest", type=pathlib.Path)
    parser.add_argument("--media-root", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path(__file__).parent / "launcher" / "catalog.generated.h",
    )
    parser.add_argument("--inventory-output", type=pathlib.Path)
    args = parser.parse_args()

    systems = discover(args.rom_root, args.manifest)
    if not systems:
        raise SystemExit(f"no supported ROMs found below {args.rom_root}")
    media_categories = discover_media(args.media_root)
    args.output.write_text(
        render(systems, media_categories), encoding="utf-8", newline="\n"
    )
    if args.inventory_output:
        args.inventory_output.write_text(
            render_inventory(systems, media_categories), encoding="utf-8", newline="\n"
        )

    game_total = sum(len(entries) for _system, entries in systems)
    print(
        f"generated {game_total} games across {len(systems)} systems: {args.output}"
    )
    for system, entries in systems:
        print(f"  {system.name}: {len(entries)}")
    if media_categories:
        for kind in MEDIA_KINDS:
            count = sum(
                len(category.entries)
                for category in media_categories
                if category.kind.directory == kind.directory
            )
            print(f"  {kind.directory}: {count}")


if __name__ == "__main__":
    main()
