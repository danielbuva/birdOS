#!/usr/bin/env python3
"""Verify the exact host-only LZ4 candidate against birdOS and U-Boot.

Why before: the first proof used direct-extlinux because it was then the
physically accepted U-Boot consumer. Why change: in-place handoff is now the
accepted boundary, so this verifier binds the unchanged frame to its exact
config and full-U-Boot bytes. It intentionally has no deployment path.
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import struct
import tarfile
from dataclasses import dataclass


KERNEL_BYTES = 30_926_856
KERNEL_SHA256 = "cad7ad8437d0a7de0d819846b12fdf83078f5878313704d0de79274431ec9d64"
CANDIDATE_BYTES = 17_565_707
CANDIDATE_SHA256 = "a7321d2a79b18e81f114aefd9bb7509ba70d5e56b562a345ea5ca66dbf11262a"
UBOOT_SOURCE_SHA256 = "03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654"
UBOOT_CONFIG_SHA256 = "77f2bee66adc542e3475594c4727933607f76c2adf72e6428e0e57cadb6de762"
UBOOT_BINARY_SHA256 = "cff9a9ca1bd7db20a3a136fec655d7120481afa8a837930266a9962ab2dec578"
PAIRED_UBOOT_BINARY_SHA256 = (
    "35cd4f8d50568f7bdae89fe01ce851b80276c4a44c18138de553872456523f9e"
)
UBOOT_BINARY_BYTES = 437_168
UBOOT_MEMBERS = {
    "u-boot-2026.01/lib/lz4.c":
        "01670ab77447f119826efca6728f56026eafb075be621d79c4a8b9685a260862",
    "u-boot-2026.01/lib/lz4_wrapper.c":
        "a252d79509a30e0e47d8cd431453705fee69c94a69e466ff5b3346722c716ddf",
    "u-boot-2026.01/cmd/booti.c":
        "2156fb294b21c3f6363d63c3409c1cd9af5e77b46b575a774018742d0a3b2a5a",
    "u-boot-2026.01/boot/pxe_utils.c":
        "2c60a9b5e92c844089783e9431a97d2b50282339a4069c7bfa4773251f997580",
    "u-boot-2026.01/include/configs/sunxi-common.h":
        "301d6c8db012d13918fee5cbf4251fdffd67c55b25d483a423b502c4a2240701",
}

LZ4_MAGIC = 0x184D2204
XXH_PRIME32_1 = 0x9E3779B1
XXH_PRIME32_2 = 0x85EBCA77
XXH_PRIME32_3 = 0xC2B2AE3D
XXH_PRIME32_4 = 0x27D4EB2F
XXH_PRIME32_5 = 0x165667B1
MASK32 = 0xFFFFFFFF


class VerificationError(ValueError):
    """The candidate or one of its pinned authorities is invalid."""


@dataclass(frozen=True)
class FrameInfo:
    flags: int
    block_descriptor: int
    blocks: int
    compressed_block_bytes: int
    output: bytes


@dataclass(frozen=True)
class AddressInfo:
    kernel_addr: int
    kernel_input_end: int
    kernel_output_end: int
    decompression_addr: int
    decompression_output_end: int
    exact_decompression_limit_end: int
    current_decompression_limit_end: int
    fdt_addr: int
    script_addr: int
    pxe_addr: int
    overlay_addr: int
    ramdisk_addr: int
    current_kernel_comp_size: int


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_exact_file(path: pathlib.Path, expected_size: int, expected_sha: str) -> bytes:
    if not path.is_file() or path.is_symlink():
        raise VerificationError(f"unsafe or missing regular file: {path}")
    data = path.read_bytes()
    if len(data) != expected_size:
        raise VerificationError(
            f"byte count changed for {path}: {len(data)} != {expected_size}"
        )
    actual = sha256_bytes(data)
    if actual != expected_sha:
        raise VerificationError(f"checksum changed for {path}: {actual}")
    return data


def rotl32(value: int, count: int) -> int:
    return ((value << count) | (value >> (32 - count))) & MASK32


def xxh32(data: bytes, seed: int = 0) -> int:
    """Small independent XXH32 implementation for LZ4 frame checksums."""

    def round32(accumulator: int, lane: int) -> int:
        accumulator = (accumulator + lane * XXH_PRIME32_2) & MASK32
        accumulator = rotl32(accumulator, 13)
        return (accumulator * XXH_PRIME32_1) & MASK32

    cursor = 0
    length = len(data)
    if length >= 16:
        lane1 = (seed + XXH_PRIME32_1 + XXH_PRIME32_2) & MASK32
        lane2 = (seed + XXH_PRIME32_2) & MASK32
        lane3 = seed & MASK32
        lane4 = (seed - XXH_PRIME32_1) & MASK32
        limit = length - 16
        while cursor <= limit:
            lane1 = round32(lane1, struct.unpack_from("<I", data, cursor)[0])
            lane2 = round32(lane2, struct.unpack_from("<I", data, cursor + 4)[0])
            lane3 = round32(lane3, struct.unpack_from("<I", data, cursor + 8)[0])
            lane4 = round32(lane4, struct.unpack_from("<I", data, cursor + 12)[0])
            cursor += 16
        result = (
            rotl32(lane1, 1)
            + rotl32(lane2, 7)
            + rotl32(lane3, 12)
            + rotl32(lane4, 18)
        ) & MASK32
    else:
        result = (seed + XXH_PRIME32_5) & MASK32

    result = (result + length) & MASK32
    while cursor + 4 <= length:
        lane = struct.unpack_from("<I", data, cursor)[0]
        result = (result + lane * XXH_PRIME32_3) & MASK32
        result = (rotl32(result, 17) * XXH_PRIME32_4) & MASK32
        cursor += 4
    while cursor < length:
        result = (result + data[cursor] * XXH_PRIME32_5) & MASK32
        result = (rotl32(result, 11) * XXH_PRIME32_1) & MASK32
        cursor += 1

    result ^= result >> 15
    result = (result * XXH_PRIME32_2) & MASK32
    result ^= result >> 13
    result = (result * XXH_PRIME32_3) & MASK32
    result ^= result >> 16
    return result & MASK32


def _extended_length(block: bytes, cursor: int, initial: int) -> tuple[int, int]:
    length = initial
    if initial != 15:
        return length, cursor
    while True:
        if cursor >= len(block):
            raise VerificationError("truncated LZ4 extended length")
        extension = block[cursor]
        cursor += 1
        length += extension
        if extension != 255:
            return length, cursor


def decode_lz4_block(block: bytes, maximum_output: int) -> bytes:
    """Decode one independent raw LZ4 block with strict bounds checks."""

    cursor = 0
    output = bytearray()
    while cursor < len(block):
        token = block[cursor]
        cursor += 1
        literal_length, cursor = _extended_length(block, cursor, token >> 4)
        literal_end = cursor + literal_length
        if literal_end > len(block):
            raise VerificationError("LZ4 literal exceeds its block")
        if len(output) + literal_length > maximum_output:
            raise VerificationError("LZ4 literal exceeds the advertised block output")
        output.extend(block[cursor:literal_end])
        cursor = literal_end
        if cursor == len(block):
            break
        if cursor + 2 > len(block):
            raise VerificationError("truncated LZ4 match offset")
        offset = struct.unpack_from("<H", block, cursor)[0]
        cursor += 2
        if offset == 0 or offset > len(output):
            raise VerificationError("invalid LZ4 match offset")
        match_length, cursor = _extended_length(block, cursor, token & 0x0F)
        match_length += 4
        if len(output) + match_length > maximum_output:
            raise VerificationError("LZ4 match exceeds the advertised block output")
        match_cursor = len(output) - offset
        remaining = match_length
        while remaining:
            available = len(output) - match_cursor
            if available <= 0:
                raise VerificationError("invalid overlapping LZ4 match")
            take = min(remaining, available)
            output.extend(output[match_cursor:match_cursor + take])
            remaining -= take
    return bytes(output)


def parse_lz4_frame(frame: bytes) -> FrameInfo:
    """Parse and independently decode the U-Boot-compatible LZ4 frame."""

    if len(frame) < 11:
        raise VerificationError("LZ4 frame is too short")
    if struct.unpack_from("<I", frame, 0)[0] != LZ4_MAGIC:
        raise VerificationError("not a modern LZ4 frame")
    cursor = 4
    flags = frame[cursor]
    block_descriptor = frame[cursor + 1]
    cursor += 2
    if ((flags >> 6) & 0x03) != 1:
        raise VerificationError("unsupported LZ4 frame version")
    if not flags & 0x20:
        raise VerificationError("U-Boot requires independent LZ4 blocks")
    if flags & 0x03:
        raise VerificationError("U-Boot rejects LZ4 reserved/dictionary flags")
    if block_descriptor & 0x8F:
        raise VerificationError("invalid LZ4 block descriptor")
    block_code = (block_descriptor >> 4) & 0x07
    block_maximums = {4: 64 << 10, 5: 256 << 10, 6: 1 << 20, 7: 4 << 20}
    if block_code not in block_maximums:
        raise VerificationError("unsupported LZ4 maximum block size")
    block_maximum = block_maximums[block_code]

    descriptor = bytearray((flags, block_descriptor))
    declared_content_size = None
    if flags & 0x08:
        if cursor + 8 > len(frame):
            raise VerificationError("truncated LZ4 content size")
        declared_content_size = struct.unpack_from("<Q", frame, cursor)[0]
        descriptor.extend(frame[cursor:cursor + 8])
        cursor += 8
    header_checksum = frame[cursor]
    cursor += 1
    if ((xxh32(bytes(descriptor)) >> 8) & 0xFF) != header_checksum:
        raise VerificationError("LZ4 frame header checksum mismatch")

    output = bytearray()
    blocks = 0
    compressed_block_bytes = 0
    while True:
        if cursor + 4 > len(frame):
            raise VerificationError("missing LZ4 end marker")
        block_header = struct.unpack_from("<I", frame, cursor)[0]
        cursor += 4
        if block_header == 0:
            break
        raw_block = bool(block_header & 0x80000000)
        block_size = block_header & 0x7FFFFFFF
        if block_size == 0 or block_size > block_maximum:
            raise VerificationError("invalid LZ4 block size")
        block_end = cursor + block_size
        if block_end > len(frame):
            raise VerificationError("LZ4 block exceeds frame")
        block = frame[cursor:block_end]
        cursor = block_end
        compressed_block_bytes += block_size
        if raw_block:
            decoded = block
        else:
            decoded = decode_lz4_block(block, block_maximum)
        if len(decoded) > block_maximum:
            raise VerificationError("decoded LZ4 block exceeds its maximum")
        output.extend(decoded)
        blocks += 1
        if flags & 0x10:
            if cursor + 4 > len(frame):
                raise VerificationError("truncated LZ4 block checksum")
            expected = struct.unpack_from("<I", frame, cursor)[0]
            cursor += 4
            if xxh32(block) != expected:
                raise VerificationError("LZ4 block checksum mismatch")

    if flags & 0x04:
        if cursor + 4 > len(frame):
            raise VerificationError("truncated LZ4 content checksum")
        expected = struct.unpack_from("<I", frame, cursor)[0]
        cursor += 4
        if xxh32(bytes(output)) != expected:
            raise VerificationError("LZ4 content checksum mismatch")
    if cursor != len(frame):
        raise VerificationError("trailing data or a second LZ4 frame is not accepted")
    if declared_content_size is not None and declared_content_size != len(output):
        raise VerificationError("LZ4 declared content size mismatch")
    if blocks == 0:
        raise VerificationError("empty LZ4 frame")
    return FrameInfo(
        flags=flags,
        block_descriptor=block_descriptor,
        blocks=blocks,
        compressed_block_bytes=compressed_block_bytes,
        output=bytes(output),
    )


def verify_uboot_sources(source_tar: pathlib.Path) -> dict[str, bytes]:
    source_data = read_exact_file(source_tar, source_tar.stat().st_size, UBOOT_SOURCE_SHA256)
    del source_data
    members: dict[str, bytes] = {}
    with tarfile.open(source_tar, "r:gz") as archive:
        for name, expected_sha in UBOOT_MEMBERS.items():
            extracted = archive.extractfile(name)
            if extracted is None:
                raise VerificationError(f"U-Boot source member missing: {name}")
            data = extracted.read()
            if sha256_bytes(data) != expected_sha:
                raise VerificationError(f"U-Boot source member changed: {name}")
            members[name] = data

    wrapper = members["u-boot-2026.01/lib/lz4_wrapper.c"]
    booti = members["u-boot-2026.01/cmd/booti.c"]
    pxe = members["u-boot-2026.01/boot/pxe_utils.c"]
    for required in (
        b"magic != LZ4F_MAGIC || version != 1",
        b"if (!independent_blocks)",
        b"ret = LZ4_decompress_generic",
    ):
        if required not in wrapper:
            raise VerificationError("U-Boot LZ4 consumer contract changed")
    for required in (
        b"ctype = image_decomp_type(temp, 2);",
        b'dest = env_get_ulong("kernel_comp_addr_r", 16, 0);',
        b'decomp_len = comp_len * 10;',
        b"ret = image_decomp(ctype, 0, ld, IH_TYPE_KERNEL,",
    ):
        if required not in booti:
            raise VerificationError("U-Boot booti compressed-Image contract changed")
    if b"} else if (IS_ENABLED(CONFIG_CMD_BOOTI)) {" not in pxe:
        raise VerificationError("U-Boot extlinux-to-booti handoff changed")
    return members


def parse_environment(binary: bytes) -> dict[str, int]:
    names = (
        "kernel_addr_r",
        "kernel_comp_addr_r",
        "kernel_comp_size",
        "fdt_addr_r",
        "scriptaddr",
        "pxefile_addr_r",
        "fdtoverlay_addr_r",
        "ramdisk_addr_r",
    )
    values: dict[str, int] = {}
    for name in names:
        marker = (name + "=").encode("ascii")
        matches = []
        cursor = 0
        while True:
            found = binary.find(marker, cursor)
            if found < 0:
                break
            end = binary.find(b"\0", found)
            if end < 0:
                raise VerificationError(f"unterminated U-Boot environment value: {name}")
            raw = binary[found + len(marker):end]
            try:
                matches.append(int(raw, 16))
            except ValueError as error:
                raise VerificationError(f"invalid U-Boot environment value: {name}") from error
            cursor = end + 1
        unique = set(matches)
        if len(unique) != 1:
            raise VerificationError(f"ambiguous or missing U-Boot environment value: {name}")
        values[name] = unique.pop()
    return values


def verify_address_layout(environment: dict[str, int]) -> AddressInfo:
    kernel = environment["kernel_addr_r"]
    decompression = environment["kernel_comp_addr_r"]
    fdt = environment["fdt_addr_r"]
    script = environment["scriptaddr"]
    pxe = environment["pxefile_addr_r"]
    overlay = environment["fdtoverlay_addr_r"]
    ramdisk = environment["ramdisk_addr_r"]
    current_size = environment["kernel_comp_size"]
    kernel_input_end = kernel + CANDIDATE_BYTES
    kernel_output_end = kernel + KERNEL_BYTES
    decompression_output_end = decompression + KERNEL_BYTES
    exact_limit_end = decompression + CANDIDATE_BYTES * 10
    current_limit_end = decompression + current_size * 10
    if not (kernel_input_end < decompression):
        raise VerificationError("compressed KERNEL overlaps its decompression destination")
    if not (kernel_output_end < decompression):
        raise VerificationError("final uncompressed Image overlaps its decompression source")
    if not (decompression_output_end < fdt):
        raise VerificationError("decompressed Image overlaps the DTB load address")
    if not (exact_limit_end < fdt):
        raise VerificationError("exact ten-times decompression guard overlaps the DTB")
    if not (fdt < script < pxe < overlay < ramdisk):
        raise VerificationError("accepted U-Boot load-address ordering changed")
    if current_size < CANDIDATE_BYTES:
        raise VerificationError("accepted U-Boot cannot hold the compressed candidate")
    return AddressInfo(
        kernel_addr=kernel,
        kernel_input_end=kernel_input_end,
        kernel_output_end=kernel_output_end,
        decompression_addr=decompression,
        decompression_output_end=decompression_output_end,
        exact_decompression_limit_end=exact_limit_end,
        current_decompression_limit_end=current_limit_end,
        fdt_addr=fdt,
        script_addr=script,
        pxe_addr=pxe,
        overlay_addr=overlay,
        ramdisk_addr=ramdisk,
        current_kernel_comp_size=current_size,
    )


def verify(
    kernel_path: pathlib.Path,
    candidate_path: pathlib.Path,
    uboot_source: pathlib.Path,
    uboot_config: pathlib.Path,
    uboot_binary: pathlib.Path,
) -> tuple[FrameInfo, AddressInfo]:
    kernel = read_exact_file(kernel_path, KERNEL_BYTES, KERNEL_SHA256)
    candidate = read_exact_file(candidate_path, CANDIDATE_BYTES, CANDIDATE_SHA256)
    verify_uboot_sources(uboot_source)
    config = read_exact_file(
        uboot_config, uboot_config.stat().st_size, UBOOT_CONFIG_SHA256
    )
    for line in (
        b"CONFIG_ARM64=y\n",
        b"CONFIG_CMD_BOOTI=y\n",
        b"CONFIG_LZ4=y\n",
        b"CONFIG_SYS_BOOTM_LEN=0x8000000\n",
    ):
        if line not in config:
            raise VerificationError(f"required accepted U-Boot config missing: {line!r}")
    if not uboot_binary.is_file() or uboot_binary.is_symlink():
        raise VerificationError(f"unsafe or missing regular file: {uboot_binary}")
    binary = uboot_binary.read_bytes()
    if len(binary) != UBOOT_BINARY_BYTES:
        raise VerificationError("accepted or paired U-Boot byte count changed")
    binary_sha = sha256_bytes(binary)
    if binary_sha not in {UBOOT_BINARY_SHA256, PAIRED_UBOOT_BINARY_SHA256}:
        raise VerificationError(f"checksum changed for {uboot_binary}: {binary_sha}")
    frame = parse_lz4_frame(candidate)
    if frame.output != kernel:
        raise VerificationError("independent LZ4 decode differs from the accepted IRQ Image")
    if frame.flags != 0x64 or frame.block_descriptor != 0x70:
        raise VerificationError("candidate LZ4 frame options changed")
    if frame.blocks != 8:
        raise VerificationError("candidate LZ4 block inventory changed")
    address = verify_address_layout(parse_environment(binary))
    if binary_sha == PAIRED_UBOOT_BINARY_SHA256:
        if address.current_kernel_comp_size != CANDIDATE_BYTES:
            raise VerificationError("paired U-Boot does not use the exact LZ4 bound")
    elif address.current_kernel_comp_size == CANDIDATE_BYTES:
        raise VerificationError("accepted U-Boot unexpectedly claims the paired bound")
    return frame, address


def format_validation(frame: FrameInfo, address: AddressInfo) -> str:
    rows = (
        ("schema", "bird-lz4-kernel-validation-v1"),
        ("kernel-bytes", str(KERNEL_BYTES)),
        ("kernel-sha256", KERNEL_SHA256),
        ("candidate-bytes", str(CANDIDATE_BYTES)),
        ("candidate-sha256", CANDIDATE_SHA256),
        ("saved-bytes", str(KERNEL_BYTES - CANDIDATE_BYTES)),
        ("saved-percent", "43.2024"),
        ("frame-flags", f"0x{frame.flags:02x}"),
        ("frame-block-descriptor", f"0x{frame.block_descriptor:02x}"),
        ("frame-blocks", str(frame.blocks)),
        ("frame-independent-decode", "exact"),
        ("kernel-load-range", f"0x{address.kernel_addr:x}-0x{address.kernel_input_end:x}"),
        ("kernel-final-range", f"0x{address.kernel_addr:x}-0x{address.kernel_output_end:x}"),
        (
            "decompression-output-range",
            f"0x{address.decompression_addr:x}-0x{address.decompression_output_end:x}",
        ),
        ("fdt-load-address", f"0x{address.fdt_addr:x}"),
        ("current-kernel-comp-size", f"0x{address.current_kernel_comp_size:x}"),
        ("exact-kernel-comp-size", f"0x{CANDIDATE_BYTES:x}"),
        (
            "paired-uboot",
            "yes" if address.current_kernel_comp_size == CANDIDATE_BYTES else "no",
        ),
        (
            "exact-ten-times-limit-end",
            f"0x{address.exact_decompression_limit_end:x}",
        ),
        (
            "current-ten-times-limit-end",
            f"0x{address.current_decompression_limit_end:x}",
        ),
        (
            "deployment-requires-exact-comp-size",
            "no" if address.current_kernel_comp_size == CANDIDATE_BYTES else "yes",
        ),
        ("card-write", "none"),
    )
    return "".join(f"{key}\t{value}\n" for key, value in rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("kernel", type=pathlib.Path)
    parser.add_argument("candidate", type=pathlib.Path)
    parser.add_argument("uboot_source", type=pathlib.Path)
    parser.add_argument("uboot_config", type=pathlib.Path)
    parser.add_argument("uboot_binary", type=pathlib.Path)
    arguments = parser.parse_args()
    try:
        frame, address = verify(
            arguments.kernel,
            arguments.candidate,
            arguments.uboot_source,
            arguments.uboot_config,
            arguments.uboot_binary,
        )
    except (OSError, tarfile.TarError, VerificationError) as error:
        raise SystemExit(f"error: {error}") from error
    print(format_validation(frame, address), end="")


if __name__ == "__main__":
    main()
