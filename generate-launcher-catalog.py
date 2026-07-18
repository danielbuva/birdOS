#!/usr/bin/env python3
"""Generate Dani's fixed RG34XX-SP launcher's embedded library catalogue."""

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


# These assignments mirror the recommended MustardOS system definitions. All
# libretro systems use the already-proven lr-general.sh bridge; external
# systems keep their dedicated muOS wrappers.
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
    System("PICO", "SEGA PICO", (".zip", ".md", ".bin"), "RETROARCH", "picodrive_libretro.so"),
    System("PSP", "PSP", (".cso", ".iso", ".pbp"), "PPSSPP", "ext-ppsspp"),
    System("Ports", "PORTS", (".sh",), "PORTMASTER", "external"),
    System("SNES", "SNES", (".zip", ".sfc", ".smc", ".fig", ".bs"), "RETROARCH", "snes9x_libretro.so"),
)

IGNORED_DIRECTORY_NAMES = frozenset(("imgs", "images"))


def c_string(value: str) -> str:
    encoded = value.encode("utf-8")
    output: list[str] = ['"']
    for byte in encoded:
        if byte == 34:
            output.append(r'\"')
        elif byte == 92:
            output.append(r"\\")
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
            for path in system_root.rglob("*"):
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
                entries.append(
                    (display_name(path), f"/mnt/mmc/ROMS/{relative}", relative)
                )
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


def render(systems: list[tuple[System, list[tuple[str, str, str]]]]) -> str:
    total = sum(len(entries) for _system, entries in systems)
    lines = [
        "/* Generated by generate-launcher-catalog.py; do not edit manually. */",
        "#ifndef DANI_CATALOG_GENERATED_H",
        "#define DANI_CATALOG_GENERATED_H",
        "",
        "#define CATALOG_LAUNCH_RETROARCH 1",
        "#define CATALOG_LAUNCH_PPSSPP 2",
        "#define CATALOG_LAUNCH_PORTMASTER 3",
        "#define CATALOG_LAUNCH_DRASTIC 4",
        "#define CATALOG_LAUNCH_OPENBOR 5",
        f"#define CATALOG_SYSTEM_COUNT {len(systems)}U",
        f"#define CATALOG_ENTRY_COUNT {total}U",
        "",
        "struct catalog_system {",
        "    const char *name;",
        "    const char *core;",
        "    u32 first;",
        "    u32 count;",
        "    u8 launch_kind;",
        "};",
        "",
        "struct catalog_entry {",
        "    const char *name;",
        "    const char *path;",
        "    u16 system;",
        "};",
        "",
        "static const struct catalog_system catalog_systems[CATALOG_SYSTEM_COUNT] = {",
    ]

    first = 0
    launch_constants = {
        "RETROARCH": "CATALOG_LAUNCH_RETROARCH",
        "PPSSPP": "CATALOG_LAUNCH_PPSSPP",
        "PORTMASTER": "CATALOG_LAUNCH_PORTMASTER",
        "DRASTIC": "CATALOG_LAUNCH_DRASTIC",
        "OPENBOR": "CATALOG_LAUNCH_OPENBOR",
    }
    for system, entries in systems:
        lines.append(
            f"    {{{c_string(system.name)}, {c_string(system.core)}, {first}U, "
            f"{len(entries)}U, {launch_constants[system.launcher]}}},"
        )
        first += len(entries)

    lines.extend(
        [
            "};",
            "",
            "static const struct catalog_entry catalog_entries[CATALOG_ENTRY_COUNT] = {",
        ]
    )
    for system_index, (_system, entries) in enumerate(systems):
        for name, path, _relative in entries:
            lines.append(f"    {{{c_string(name)}, {c_string(path)}, {system_index}U}},")

    lines.extend(["};", "", "#endif", ""])
    return "\n".join(lines)


def media_inventory(media_root: pathlib.Path | None) -> list[tuple[str, str, str]]:
    entries: list[tuple[str, str, str]] = []
    if media_root is None or not media_root.is_dir():
        return entries
    for kind in ("LISTEN", "READ", "WATCH"):
        root = media_root / kind
        if not root.is_dir():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(media_root)
            if is_hidden_or_artwork(relative):
                continue
            entries.append((kind, display_name(path), relative.as_posix()))
    entries.sort(key=lambda entry: (entry[0], entry[1], entry[2]))
    return entries


def render_inventory(
    systems: list[tuple[System, list[tuple[str, str, str]]]],
    media: list[tuple[str, str, str]],
) -> str:
    lines = ["section\tcategory\tdisplay_name\trelative_path\tlauncher\tcore"]
    for system, entries in systems:
        for name, _absolute, relative in entries:
            lines.append(
                f"PLAY\t{system.name}\t{name}\tROMS/{relative}\t"
                f"{system.launcher}\t{system.core}"
            )
    for kind, name, relative in media:
        parts = relative.split("/")
        category = parts[1] if len(parts) > 2 else kind
        lines.append(
            f"{kind}\t{category}\t{name}\tMEDIA/{relative}\tPENDING\tPENDING"
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
    media = media_inventory(args.media_root)
    args.output.write_text(render(systems), encoding="utf-8", newline="\n")
    if args.inventory_output:
        args.inventory_output.write_text(
            render_inventory(systems, media), encoding="utf-8", newline="\n"
        )

    game_total = sum(len(entries) for _system, entries in systems)
    print(
        f"generated {game_total} games across {len(systems)} systems: {args.output}"
    )
    for system, entries in systems:
        print(f"  {system.name}: {len(entries)}")
    if media:
        for kind in ("LISTEN", "READ", "WATCH"):
            print(f"  {kind}: {sum(1 for entry in media if entry[0] == kind)}")


if __name__ == "__main__":
    main()
