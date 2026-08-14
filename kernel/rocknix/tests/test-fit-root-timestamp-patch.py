#!/usr/bin/env python3
"""Focused contracts for the exact in-place FIT root-timestamp patcher."""

from __future__ import annotations

import importlib.util
import pathlib
import stat
import struct
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
PATCHER = ROOT / "kernel/rocknix/patch-fit-root-timestamp.py"
SHIPPING = (
    ROOT
    / "kernel/work/rocknix-system-exact-20260701/usr/share/bootloader"
    / "H700_DDR4_u-boot-sunxi-with-spl.bin"
)
SPL_REGION_BYTES = 40960
SHIPPING_FIT_EPOCH = 1782880744


def load_patcher():
    spec = importlib.util.spec_from_file_location("bird_fit_timestamp_patcher", PATCHER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def align4(data: bytes) -> bytes:
    return data + b"\0" * ((-len(data)) & 3)


def make_fit(
    root_timestamps: tuple[bytes, ...] = (struct.pack(">I", 0x11223344),),
    child_timestamp: bytes | None = None,
) -> bytes:
    strings = b"timestamp\0description\0"
    timestamp_name = 0
    description_name = len(b"timestamp\0")

    def begin_node(name: str) -> bytes:
        return struct.pack(">I", 1) + align4(name.encode("ascii") + b"\0")

    def prop(name_offset: int, value: bytes) -> bytes:
        return (
            struct.pack(">III", 3, len(value), name_offset)
            + align4(value)
        )

    structure = begin_node("")
    for timestamp in root_timestamps:
        structure += prop(timestamp_name, timestamp)
    structure += prop(description_name, b"test FIT\0")
    if child_timestamp is not None:
        structure += begin_node("images")
        structure += prop(timestamp_name, child_timestamp)
        structure += struct.pack(">I", 2)
    structure += struct.pack(">II", 2, 9)

    reserve_offset = 40
    reserve_map = b"\0" * 16
    structure_offset = reserve_offset + len(reserve_map)
    strings_offset = structure_offset + len(structure)
    trailing = b"\0" * 12
    total_size = strings_offset + len(strings) + len(trailing)
    header = struct.pack(
        ">10I",
        0xD00DFEED,
        total_size,
        structure_offset,
        strings_offset,
        reserve_offset,
        17,
        2,
        0,
        len(strings),
        len(structure),
    )
    return header + reserve_map + structure + strings + trailing


def expect_rejected(function, diagnostic: str) -> None:
    try:
        function()
    except SystemExit as error:
        assert diagnostic in str(error), str(error)
    else:
        raise AssertionError("invalid FIT timestamp patch was accepted")


def test_exact_patch(module) -> None:
    old = 0x11223344
    replacement = 0xA1B2C3D4
    original = make_fit()
    offset = module.find_root_timestamp(original)
    assert original[offset : offset + 4] == struct.pack(">I", old)

    with tempfile.TemporaryDirectory(prefix="bird-fit-timestamp-test-") as directory:
        path = pathlib.Path(directory) / "u-boot.itb"
        path.write_bytes(original)
        path.chmod(0o640)
        module.patch_file(path, old, replacement)
        changed = path.read_bytes()
        assert len(changed) == len(original)
        assert stat.S_IMODE(path.stat().st_mode) == 0o640
        assert changed[:offset] == original[:offset]
        assert changed[offset : offset + 4] == struct.pack(">I", replacement)
        assert changed[offset + 4 :] == original[offset + 4 :]

        module.patch_file(path, replacement, old)
        assert path.read_bytes() == original


def test_fail_closed(module) -> None:
    valid = make_fit()
    duplicate = make_fit(
        root_timestamps=(struct.pack(">I", 1), struct.pack(">I", 2))
    )
    non_root = make_fit(child_timestamp=struct.pack(">I", 2))
    wrong_size = make_fit(root_timestamps=(b"12345678",))
    missing = make_fit(root_timestamps=())

    expect_rejected(
        lambda: module.find_root_timestamp(valid[:-1]),
        "FIT size is not exact",
    )
    expect_rejected(
        lambda: module.find_root_timestamp(duplicate),
        "duplicate FIT property: /:timestamp",
    )
    expect_rejected(
        lambda: module.find_root_timestamp(non_root),
        "FIT timestamp property is not root-level",
    )
    expect_rejected(
        lambda: module.find_root_timestamp(wrong_size),
        "FIT root timestamp property is not four bytes",
    )
    expect_rejected(
        lambda: module.find_root_timestamp(missing),
        "FIT root timestamp property is missing",
    )
    expect_rejected(
        lambda: module.parse_epoch("-1", "epoch"),
        "unsigned decimal 32-bit epoch",
    )
    expect_rejected(
        lambda: module.parse_epoch(str(1 << 32), "epoch"),
        "unsigned decimal 32-bit epoch",
    )

    with tempfile.TemporaryDirectory(prefix="bird-fit-timestamp-test-") as directory:
        path = pathlib.Path(directory) / "u-boot.itb"
        path.write_bytes(valid)
        expect_rejected(
            lambda: module.patch_file(path, 0x11223345, 0x55667788),
            "does not match expected current value",
        )
        assert path.read_bytes() == valid

        path.write_bytes(duplicate)
        expect_rejected(
            lambda: module.patch_file(path, 1, 2),
            "duplicate FIT property",
        )
        assert path.read_bytes() == duplicate


def test_real_shipping_round_trip(module) -> bool:
    if not SHIPPING.is_file():
        return False
    combined = SHIPPING.read_bytes()
    shipping_fit = combined[SPL_REGION_BYTES:]
    offset = module.find_root_timestamp(shipping_fit)
    assert struct.unpack_from(">I", shipping_fit, offset)[0] == SHIPPING_FIT_EPOCH

    with tempfile.TemporaryDirectory(prefix="bird-shipping-fit-test-") as directory:
        path = pathlib.Path(directory) / "shipping.itb"
        path.write_bytes(shipping_fit)
        alternate = 0x12345678
        module.patch_file(path, SHIPPING_FIT_EPOCH, alternate)
        changed = path.read_bytes()
        assert len(changed) == len(shipping_fit)
        assert changed[:offset] == shipping_fit[:offset]
        assert changed[offset + 4 :] == shipping_fit[offset + 4 :]
        module.patch_file(path, alternate, SHIPPING_FIT_EPOCH)
        assert path.read_bytes() == shipping_fit
    return True


def main() -> None:
    module = load_patcher()
    test_exact_patch(module)
    test_fail_closed(module)
    shipping_ran = test_real_shipping_round_trip(module)
    suffix = " (real shipping FIT round trip verified)" if shipping_ran else ""
    print(f"FIT root timestamp patch tests: PASS{suffix}")


if __name__ == "__main__":
    main()
