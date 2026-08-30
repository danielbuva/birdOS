#!/usr/bin/env python3
"""Generate the launcher-aligned 720x480 U-Boot frame-zero BMP."""

from __future__ import annotations

import argparse
import binascii
import hashlib
import os
import struct
import tempfile
import zlib
from pathlib import Path


WIDTH = 720
HEIGHT = 480

# Exact wallpaper regions that remain visible after the launcher paints its
# fixed opaque chrome. Rows are padded to an even pixel count so every region
# and every row remains naturally aligned for paired AArch64 loads.
STATIC_BASE_REGIONS = (
    (0, 0, 720, 36),
    (0, 36, 160, 40),
    (560, 36, 160, 40),
    (0, 76, 720, 28),
    (0, 104, 160, 288),
    (560, 104, 160, 288),
    (0, 392, 163, 3),
    (560, 392, 160, 3),
    (0, 395, 720, 85),
)
STATIC_BASE_BYTES = sum(
    ((width + (width & 1)) * 4) * height
    for _, _, width, height in STATIC_BASE_REGIONS
)

TOP_BAR_X = 160
TOP_BAR_Y = 36
TOP_BAR_WIDTH = 400
TOP_BAR_HEIGHT = 40
SIDEBAR_X = 160
SIDEBAR_Y = 104
SIDEBAR_WIDTH = 32
CONTENT_X = SIDEBAR_X + SIDEBAR_WIDTH
CONTENT_Y = SIDEBAR_Y
CONTENT_WIDTH = 368
CONTENT_HEIGHT = 288
DIVIDER_WIDTH = 10

CREAM = (239, 226, 217)
BURGUNDY = (36, 10, 18)
BURGUNDY_EDGE = (55, 18, 29)
SHADOW = (15, 8, 12)
MASK64 = (1 << 64) - 1
BACKDROP_SHA256 = "3fdea84fe0c149378db32d1849e55b3fede22c74a613544810be880f48fdb9d3"

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


def atomic_write(path: Path, payload: bytes) -> None:
    """Replace one generated output without following an existing leaf symlink."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    try:
        os.fchmod(descriptor, 0o644)
        temporary = os.fdopen(descriptor, "wb")
        descriptor = -1
        with temporary:
            temporary.write(payload)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


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


def paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    corner_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= corner_distance:
        return left
    if above_distance <= corner_distance:
        return above
    return upper_left


def load_png_bgr(path: Path) -> bytearray:
    """Decode the pinned build-time RGB PNG without a runtime image dependency."""
    encoded = path.read_bytes()
    if hashlib.sha256(encoded).hexdigest() != BACKDROP_SHA256:
        raise SystemExit("error: launcher backdrop digest changed")
    if not encoded.startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit("error: launcher backdrop is not PNG")

    offset = 8
    compressed = bytearray()
    width = height = bit_depth = colour_type = interlace = -1
    while offset < len(encoded):
        if offset + 12 > len(encoded):
            raise SystemExit("error: truncated launcher backdrop chunk")
        length = struct.unpack_from(">I", encoded, offset)[0]
        chunk_type = encoded[offset + 4 : offset + 8]
        start = offset + 8
        end = start + length
        if end + 4 > len(encoded):
            raise SystemExit("error: truncated launcher backdrop payload")
        payload = encoded[start:end]
        expected_crc = struct.unpack_from(">I", encoded, end)[0]
        if binascii.crc32(chunk_type + payload) & 0xFFFFFFFF != expected_crc:
            raise SystemExit("error: launcher backdrop PNG checksum failed")
        if chunk_type == b"IHDR":
            width, height, bit_depth, colour_type, compression, filtering, interlace = (
                struct.unpack(">IIBBBBB", payload)
            )
            if compression or filtering:
                raise SystemExit("error: unsupported launcher backdrop PNG method")
        elif chunk_type == b"IDAT":
            compressed.extend(payload)
        elif chunk_type == b"IEND":
            break
        offset = end + 4

    if (width, height, bit_depth, colour_type, interlace) != (
        WIDTH, HEIGHT, 8, 2, 0
    ):
        raise SystemExit("error: launcher backdrop must be 720x480 RGB8 non-interlaced")
    try:
        filtered = zlib.decompress(bytes(compressed))
    except zlib.error as error:
        raise SystemExit(f"error: launcher backdrop decompression failed: {error}")

    bytes_per_pixel = 3
    row_bytes = width * bytes_per_pixel
    if len(filtered) != height * (row_bytes + 1):
        raise SystemExit("error: launcher backdrop scanline size changed")
    prior = bytearray(row_bytes)
    rgb = bytearray(width * height * bytes_per_pixel)
    source = 0
    target = 0
    for _ in range(height):
        filter_type = filtered[source]
        source += 1
        row = bytearray(filtered[source : source + row_bytes])
        source += row_bytes
        for index in range(row_bytes):
            left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            above = prior[index]
            upper_left = prior[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            if filter_type == 1:
                row[index] = (row[index] + left) & 0xFF
            elif filter_type == 2:
                row[index] = (row[index] + above) & 0xFF
            elif filter_type == 3:
                row[index] = (row[index] + ((left + above) >> 1)) & 0xFF
            elif filter_type == 4:
                row[index] = (row[index] + paeth(left, above, upper_left)) & 0xFF
            elif filter_type != 0:
                raise SystemExit("error: unsupported launcher backdrop PNG filter")
        rgb[target : target + row_bytes] = row
        target += row_bytes
        prior = row

    bgr = bytearray(len(rgb))
    for index in range(0, len(rgb), 3):
        bgr[index] = rgb[index + 2]
        bgr[index + 1] = rgb[index + 1]
        bgr[index + 2] = rgb[index]
    return bgr


def draw_menu_chrome(pixels: bytearray) -> None:
    rectangle(pixels, SIDEBAR_X + 3, SIDEBAR_Y + CONTENT_HEIGHT,
              SIDEBAR_WIDTH + CONTENT_WIDTH - 3, 3, SHADOW)
    rectangle(pixels, TOP_BAR_X, TOP_BAR_Y, TOP_BAR_WIDTH,
              TOP_BAR_HEIGHT, CREAM)
    rectangle(pixels, SIDEBAR_X, SIDEBAR_Y, SIDEBAR_WIDTH,
              CONTENT_HEIGHT, CREAM)
    rectangle(pixels, CONTENT_X, CONTENT_Y, CONTENT_WIDTH,
              CONTENT_HEIGHT, BURGUNDY)
    rectangle(pixels, CONTENT_X, CONTENT_Y, DIVIDER_WIDTH, CONTENT_HEIGHT,
              BURGUNDY_EDGE)


def subtract_menu_chrome(pixels: bytearray) -> None:
    """Zero wallpaper pixels that are always replaced by opaque launcher UI."""
    rectangle(pixels, TOP_BAR_X, TOP_BAR_Y, TOP_BAR_WIDTH,
              TOP_BAR_HEIGHT, (0, 0, 0))
    rectangle(pixels, SIDEBAR_X, SIDEBAR_Y,
              SIDEBAR_WIDTH + CONTENT_WIDTH, CONTENT_HEIGHT, (0, 0, 0))
    rectangle(pixels, SIDEBAR_X + 3, SIDEBAR_Y + CONTENT_HEIGHT,
              SIDEBAR_WIDTH + CONTENT_WIDTH - 3, 3, (0, 0, 0))


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


def framebuffer_visible_fingerprint(pixels: bytes) -> tuple[int, int]:
    """Match bird-launcher's visible-RGB fingerprint for one XRGB page."""
    xrgb = bytearray()
    for offset in range(0, len(pixels), 3):
        xrgb.extend(pixels[offset : offset + 3])
        xrgb.append(0)

    visible_a = 1469598103934665603
    visible_b = 0x9E3779B97F4A7C15
    pair_offset = 0
    region_lines = (95, HEIGHT - 95 - 66, 66)
    region_seeds = (
        (0x243F6A8885A308D3, 0x082EFA98EC4E6C89),
        (0x13198A2E03707344, 0x452821E638D01377),
        (0xA4093822299F31D0, 0xBE5466CF34E90C6C),
    )
    for lines, (region_a, region_b) in zip(region_lines, region_seeds):
        for _ in range(lines * (WIDTH // 2)):
            physical = int.from_bytes(xrgb[pair_offset : pair_offset + 8], "little")
            pair_offset += 8
            visible = physical & 0x00FFFFFF00FFFFFF
            region_a = ((region_a ^ visible) * 1099511628211) & MASK64
            region_b = (region_b + visible) & MASK64
            region_b = (region_b + (region_b << 10)) & MASK64
            region_b ^= region_b >> 6
        region_b = (region_b + (region_b << 3)) & MASK64
        region_b ^= region_b >> 11
        region_b = (region_b + (region_b << 15)) & MASK64
        visible_a = ((visible_a ^ region_a) * 1099511628211) & MASK64
        visible_a = ((visible_a ^ region_b) * 1099511628211) & MASK64
        visible_b = (visible_b + region_a) & MASK64
        visible_b = (visible_b + (visible_b << 10)) & MASK64
        visible_b ^= visible_b >> 6
        visible_b = (visible_b + region_b) & MASK64
        visible_b = (visible_b + (visible_b << 10)) & MASK64
        visible_b ^= visible_b >> 6
    visible_b = (visible_b + (visible_b << 3)) & MASK64
    visible_b ^= visible_b >> 11
    visible_b = (visible_b + (visible_b << 15)) & MASK64
    return visible_a, visible_b


def pack_static_base(xrgb: bytes) -> bytes:
    """Pack the nine fixed XRGB wallpaper regions in screen order."""
    packed = bytearray()
    stride = WIDTH * 4
    for x, y, width, height in STATIC_BASE_REGIONS:
        row_bytes = width * 4
        packed_stride = (width + (width & 1)) * 4
        for row in range(height):
            start = (y + row) * stride + x * 4
            packed.extend(xrgb[start : start + row_bytes])
            if packed_stride != row_bytes:
                packed.extend(b"\0" * (packed_stride - row_bytes))
    if len(packed) != STATIC_BASE_BYTES:
        raise SystemExit(f"error: unexpected static base size {len(packed)}")
    return bytes(packed)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--contract", type=Path)
    parser.add_argument("--xrgb-output", type=Path)
    parser.add_argument("--static-base-output", type=Path)
    parser.add_argument(
        "--early-static-asset-bytes",
        type=int,
        choices=(0, STATIC_BASE_BYTES),
        default=0,
    )
    parser.add_argument(
        "--backdrop",
        type=Path,
        default=Path(__file__).resolve().parent / "assets/bird-launcher-backdrop.png",
    )
    arguments = parser.parse_args()

    wallpaper = load_png_bgr(arguments.backdrop)
    pixels = bytearray(wallpaper)
    draw_menu_chrome(pixels)

    raw_wallpaper = bytearray(wallpaper)
    subtract_menu_chrome(raw_wallpaper)
    xrgb = bytearray(WIDTH * HEIGHT * 4)
    for source in range(0, len(raw_wallpaper), 3):
        target = (source // 3) * 4
        xrgb[target : target + 3] = raw_wallpaper[source : source + 3]
    if arguments.xrgb_output:
        atomic_write(arguments.xrgb_output, bytes(xrgb))
    static_base = pack_static_base(bytes(xrgb))
    if arguments.static_base_output:
        atomic_write(arguments.static_base_output, static_base)

    # BMP stores positive-height images bottom-up. Each 720x24-bit row is
    # already a multiple of four bytes, so no row padding is required.
    stride = WIDTH * 3
    bottom_up = b"".join(
        pixels[y * stride : (y + 1) * stride] for y in range(HEIGHT - 1, -1, -1)
    )
    output = bitmap_header(len(bottom_up)) + bottom_up
    if len(output) != 1_036_938:
        raise SystemExit(f"error: unexpected BMP size {len(output)}")
    atomic_write(arguments.output, output)
    if arguments.contract:
        visible_a, visible_b = framebuffer_visible_fingerprint(bytes(pixels))
        asset_sha = hashlib.sha256(output).hexdigest()
        contract = (
            "schema\tbird-boot-frame-v4\n"
            f"backdrop-sha256\t{BACKDROP_SHA256}\n"
            f"asset-sha256\t{asset_sha}\n"
            f"asset-bytes\t{len(output)}\n"
            f"logical-pixels\t{WIDTH * HEIGHT}\n"
            f"visible-framebuffer-bytes\t{WIDTH * HEIGHT * 3}\n"
            "framebuffer-pages\t1\n"
            f"physical-framebuffer-bytes\t{WIDTH * HEIGHT * 4}\n"
            f"raw-resolution\t{WIDTH}x{HEIGHT}\n"
            "raw-pixel-format\tXRGB8888\n"
            "raw-memory-channel-order\tB,G,R,X\n"
            f"raw-stride\t{WIDTH * 4}\n"
            "raw-orientation\ttop-down\n"
            "raw-page-offset\t0:0\n"
            "raw-subtracted-regions\ttop-bar,menu-container,menu-shadow\n"
            "static-base-layout\tfixed-visible-regions-v1\n"
            f"visible-hash-a\t{visible_a:016x}\n"
            f"visible-hash-b\t{visible_b:016x}\n"
            f"early-static-asset-bytes\t{arguments.early_static_asset_bytes}\n"
            f"final-root-static-asset-bytes\t{len(static_base)}\n"
            "final-root-static-asset-sha256\t"
            f"{hashlib.sha256(static_base).hexdigest()}\n"
        )
        atomic_write(arguments.contract, contract.encode("ascii"))
    print(f"generated {arguments.output}: {len(output)} bytes")


if __name__ == "__main__":
    main()
