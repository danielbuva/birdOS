#!/usr/bin/env python3
"""Generate the launcher-aligned 720x480 U-Boot frame-zero BMP."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


WIDTH = 720
HEIGHT = 480

BACKGROUND = (10, 14, 20)
PANEL = (19, 26, 36)
ACCENT_IDLE = (48, 58, 70)
PRIMARY = (244, 246, 248)
MUTED = (139, 151, 166)

FONT = {
    " ": (0, 0, 0, 0, 0, 0, 0),
    "-": (0, 0, 0, 31, 0, 0, 0),
    "/": (1, 2, 4, 8, 16, 0, 0),
    "0": (14, 17, 19, 21, 25, 17, 14),
    "1": (4, 12, 4, 4, 4, 4, 14),
    "2": (14, 17, 1, 2, 4, 8, 31),
    "3": (30, 1, 1, 14, 1, 1, 30),
    "4": (2, 6, 10, 18, 31, 2, 2),
    "5": (31, 16, 16, 30, 1, 1, 30),
    "6": (14, 16, 16, 30, 17, 17, 14),
    "7": (31, 1, 2, 4, 8, 8, 8),
    "8": (14, 17, 17, 14, 17, 17, 14),
    "9": (14, 17, 17, 15, 1, 1, 14),
    "A": (14, 17, 17, 31, 17, 17, 17),
    "B": (30, 17, 17, 30, 17, 17, 30),
    "C": (14, 17, 16, 16, 16, 17, 14),
    "D": (30, 17, 17, 17, 17, 17, 30),
    "E": (31, 16, 16, 30, 16, 16, 31),
    "F": (31, 16, 16, 30, 16, 16, 16),
    "G": (14, 17, 16, 23, 17, 17, 15),
    "H": (17, 17, 17, 31, 17, 17, 17),
    "I": (14, 4, 4, 4, 4, 4, 14),
    "J": (7, 2, 2, 2, 2, 18, 12),
    "K": (17, 18, 20, 24, 20, 18, 17),
    "L": (16, 16, 16, 16, 16, 16, 31),
    "M": (17, 27, 21, 21, 17, 17, 17),
    "N": (17, 25, 21, 19, 17, 17, 17),
    "O": (14, 17, 17, 17, 17, 17, 14),
    "P": (30, 17, 17, 30, 16, 16, 16),
    "Q": (14, 17, 17, 17, 21, 18, 13),
    "R": (30, 17, 17, 30, 20, 18, 17),
    "S": (15, 16, 16, 14, 1, 1, 30),
    "T": (31, 4, 4, 4, 4, 4, 4),
    "U": (17, 17, 17, 17, 17, 17, 14),
    "V": (17, 17, 17, 17, 17, 10, 4),
    "W": (17, 17, 17, 21, 21, 21, 10),
    "X": (17, 17, 10, 4, 10, 17, 17),
    "Y": (17, 17, 10, 4, 4, 4, 4),
    "Z": (31, 1, 2, 4, 8, 16, 31),
}


def rectangle(
    pixels: bytearray, x: int, y: int, width: int, height: int, colour: tuple[int, int, int]
) -> None:
    red, green, blue = colour
    row = bytes((blue, green, red)) * width
    for screen_y in range(y, y + height):
        if screen_y < 0 or screen_y >= HEIGHT:
            continue
        start = screen_y * WIDTH * 3 + x * 3
        pixels[start : start + len(row)] = row


def draw_text(
    pixels: bytearray, x: int, y: int, text: str, scale: int, colour: tuple[int, int, int]
) -> None:
    for character in text:
        rows = FONT.get(character)
        if rows is None:
            raise ValueError(f"unsupported launcher glyph: {character!r}")
        for glyph_y, bits in enumerate(rows):
            for glyph_x in range(5):
                if bits & (1 << (4 - glyph_x)):
                    rectangle(
                        pixels,
                        x + glyph_x * scale,
                        y + glyph_y * scale,
                        scale,
                        scale,
                        colour,
                    )
        x += 6 * scale


def bitmap_header(pixel_size: int) -> bytes:
    file_size = 14 + 124 + pixel_size
    file_header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, 138)
    dib = bytearray(124)
    struct.pack_into(
        "<IiiHHIIiiII",
        dib,
        0,
        124,
        WIDTH,
        HEIGHT,
        1,
        24,
        0,
        pixel_size,
        0,
        0,
        0,
        0,
    )
    struct.pack_into("<IIII", dib, 40, 0x00FF0000, 0x0000FF00, 0x000000FF, 0)
    struct.pack_into("<I", dib, 56, 0x73524742)  # LCS_sRGB
    struct.pack_into("<I", dib, 108, 4)  # LCS_GM_IMAGES
    return file_header + dib


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()

    pixels = bytearray(bytes((BACKGROUND[2], BACKGROUND[1], BACKGROUND[0])) * WIDTH * HEIGHT)
    rectangle(pixels, 0, 0, WIDTH, 92, PANEL)
    rectangle(pixels, 32, 86, 656, 3, ACCENT_IDLE)
    draw_text(pixels, 32, 22, "BIRDOS // RG34-SP", 4, PRIMARY)
    draw_text(pixels, 34, 62, "BESPOKE CONSOLE", 2, MUTED)

    # BMP stores positive-height images bottom-up. Each 720x24-bit row is
    # already a multiple of four bytes, so no row padding is required.
    stride = WIDTH * 3
    bottom_up = b"".join(
        pixels[y * stride : (y + 1) * stride] for y in range(HEIGHT - 1, -1, -1)
    )
    output = bitmap_header(len(bottom_up)) + bottom_up
    if len(output) != 1_036_938:
        raise SystemExit(f"error: unexpected BMP size {len(output)}")
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_bytes(output)
    print(f"generated {arguments.output}: {len(output)} bytes")


if __name__ == "__main__":
    main()
