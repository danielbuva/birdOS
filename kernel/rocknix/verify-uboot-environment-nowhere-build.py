#!/usr/bin/env python3
"""Verify and seal repeated H700 U-Boot builds without a FAT environment."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE_VERIFIER_PATH = ROOT / "kernel/rocknix/verify-uboot-status-led-build.py"
INSTALL_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-install-authority.py"
BASE_SHA = "42c01f4524b45cba7c239cd940fc4e71eed7545901da201f27fed2193b7fdf45"
CANDIDATE_SHA = "970b5c485b0468e60c894ed39a0fbf786a3633d92e852a1f4005091b40d887e7"
UBOOT_SHA = "6cb86fd7b51844693456be5db25baa7108966a5e667301f2c60b7a5f1c474f63"
CONFIG_SHA = "e42a351095e439cb4713b82916acb92f4d0315dd32647781e83b834c5b9c0a15"
SPL_SHA = "0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c"
DTB_SHA = "ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589"
PREFIX_SHA = "eceb7bcf3f8831b7a7cbb90859ea47bdf67c0cf87650a17977e225c4a43a54f2"
CANDIDATE_BYTES = 620745
SPL_BYTES = 40960
FILES = ("u-boot-sunxi-with-spl.bin", "sunxi-spl.bin", "u-boot-nodtb.bin", "u-boot.dtb", "u-boot.itb", "build.config")
PUBLISHED = (
    "authority.tsv", "base-shipping.bin", "baseline-prefix-16m.bin", "env-a.bin",
    "env-a.config", "env-b.bin", "env-b.config", "env-nowhere.bin",
    "env-nowhere.itb", "env-nowhere-spl.bin", "env-nowhere-uboot.bin",
    "env-nowhere.dtb", "shipping-baseline.bin", "sha256sums.txt",
)


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def read(path: pathlib.Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail(f"missing or unsafe artifact: {path}")
    return path.read_bytes()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_base_verifier():
    spec = importlib.util.spec_from_file_location("bird_base_verify", BASE_VERIFIER_PATH)
    if spec is None or spec.loader is None:
        fail("could not load early-LED verifier")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_build(directory: pathlib.Path) -> dict[str, bytes]:
    return {name: read(directory / name) for name in FILES}


def verify_output(directory: pathlib.Path) -> None:
    if directory.is_symlink() or not directory.is_dir():
        fail("environment authority directory is missing or unsafe")
    if tuple(sorted(p.name for p in directory.iterdir())) != tuple(sorted(PUBLISHED)):
        fail("environment authority file inventory changed")
    expected = sorted(name for name in PUBLISHED if name != "sha256sums.txt")
    lines = read(directory / "sha256sums.txt").decode("ascii").splitlines()
    if len(lines) != len(expected):
        fail("environment checksum inventory changed")
    for line, name in zip(lines, expected):
        if line != f"{sha(read(directory / name))}  {name}":
            fail(f"environment checksum changed: {name}")
    candidate = read(directory / "env-nowhere.bin")
    if candidate != read(directory / "env-a.bin") or candidate != read(directory / "env-b.bin"):
        fail("retained environment candidate builds differ")
    if len(candidate) != CANDIDATE_BYTES or sha(candidate) != CANDIDATE_SHA:
        fail("reviewed environment candidate identity changed")
    if sha(read(directory / "env-nowhere-uboot.bin")) != UBOOT_SHA:
        fail("reviewed environment U-Boot identity changed")
    if sha(read(directory / "env-nowhere-spl.bin")) != SPL_SHA or sha(read(directory / "env-nowhere.dtb")) != DTB_SHA:
        fail("reviewed environment fixed component changed")


def verify(build_a: pathlib.Path, build_b: pathlib.Path, base: pathlib.Path, baseline_prefix_path: pathlib.Path, output: pathlib.Path) -> None:
    if output.exists() or output.is_symlink():
        fail("refusing to replace environment authority output")
    subprocess.run(["python3", str(INSTALL_VERIFIER), str(base)], check=True, stdout=subprocess.DEVNULL)
    base_combined = read(base / "rocknix-baseline.bin")
    base_config = read(base / "baseline-a.config")
    baseline_prefix = read(baseline_prefix_path)
    shipping_baseline = read(base / "rocknix-baseline.bin")
    if sha(base_combined) != BASE_SHA:
        fail("shipping base identity changed")
    first, second = load_build(build_a), load_build(build_b)
    if first != second:
        fail("environment builds are not byte-identical")
    combined = first["u-boot-sunxi-with-spl.bin"]
    spl, uboot, dtb, fit, config = (first[n] for n in FILES[1:])
    if len(combined) != CANDIDATE_BYTES or sha(combined) != CANDIDATE_SHA:
        fail("environment combined identity changed")
    if sha(uboot) != UBOOT_SHA or sha(config) != CONFIG_SHA:
        fail("environment U-Boot or config identity changed")
    if sha(spl) != SPL_SHA or sha(dtb) != DTB_SHA:
        fail("environment candidate changed SPL or control DTB")
    if combined[:SPL_BYTES] != spl or combined[SPL_BYTES:] != fit:
        fail("environment combined component binding changed")

    def config_map(data: bytes) -> dict[bytes, bytes]:
        result = {}
        for line in data.splitlines():
            if line.startswith(b"CONFIG_"):
                key, value = line.split(b"=", 1); result[key] = value
            elif line.startswith(b"# CONFIG_") and line.endswith(b" is not set"):
                result[line[2:-11]] = b"n"
        return result

    before, after = config_map(base_config), config_map(config)
    changed = {key: (before.get(key), after.get(key)) for key in before.keys() | after.keys() if before.get(key) != after.get(key)}
    expected = {
        b"CONFIG_ENV_IS_IN_FAT": (b"y", b"n"), b"CONFIG_ENV_IS_NOWHERE": (b"n", b"y"),
        b"CONFIG_ENV_IS_DEFAULT": (None, b"y"), b"CONFIG_ENV_FAT_DEVICE_AND_PART": (b'":auto"', None),
        b"CONFIG_ENV_FAT_FILE": (b'"uboot.env"', None), b"CONFIG_ENV_FAT_INTERFACE": (b'"mmc"', None),
        b"CONFIG_ENV_MMC_DEVICE_INDEX": (b"0", None), b"CONFIG_ENV_MMC_EMMC_HW_PARTITION": (b"0", None),
    }
    if changed != expected:
        fail("environment resolved config delta changed")
    for key in (b"CONFIG_MMC", b"CONFIG_MMC_SUNXI", b"CONFIG_FS_FAT", b"CONFIG_CMD_FAT", b"CONFIG_CMD_SYSBOOT"):
        if after.get(key) != b"y":
            fail(f"required extlinux storage policy changed: {key.decode()}")
    if b"uboot.env\0" in uboot or b"Saving Environment to %s" in uboot:
        fail("persistent FAT environment code remains in candidate")

    base_module = load_base_verifier()
    base_fit = base_combined[SPL_BYTES:]
    base_nodes, candidate_nodes = base_module.parse_fit(base_fit), base_module.parse_fit(fit)
    if set(base_nodes) != set(candidate_nodes):
        fail("environment FIT node inventory changed")
    for node in base_nodes:
        old, new = dict(base_nodes[node]), dict(candidate_nodes[node])
        if node == "/images/uboot":
            old.pop("data", None); new.pop("data", None)
        if old != new:
            fail(f"environment FIT changed outside U-Boot data: {node}")
    expected_prefix = bytearray(baseline_prefix)
    expected_prefix[8192:8192 + len(combined)] = combined
    if sha(expected_prefix) != PREFIX_SHA:
        fail("environment full-prefix result changed")

    output.mkdir(mode=0o755)
    published = {
        "base-shipping.bin": base_combined, "baseline-prefix-16m.bin": baseline_prefix,
        "shipping-baseline.bin": shipping_baseline,
        "env-a.bin": combined, "env-b.bin": second["u-boot-sunxi-with-spl.bin"],
        "env-a.config": config, "env-b.config": second["build.config"],
        "env-nowhere.bin": combined, "env-nowhere.itb": fit,
        "env-nowhere-spl.bin": spl, "env-nowhere-uboot.bin": uboot,
        "env-nowhere.dtb": dtb,
    }
    authority = (
        "schema\tbird-uboot-env-nowhere-authority-v1\n"
        f"base-sha256\t{BASE_SHA}\ncombined-bytes\t{CANDIDATE_BYTES}\ncombined-sha256\t{CANDIDATE_SHA}\n"
        f"uboot-sha256\t{UBOOT_SHA}\nconfig-sha256\t{CONFIG_SHA}\nfull-prefix-sha256\t{PREFIX_SHA}\n"
        "environment-backend\tnowhere\nrepeat-byte-identical\tyes\n"
    ).encode("ascii")
    published["authority.tsv"] = authority
    for name, data in published.items():
        (output / name).write_bytes(data)
    (output / "sha256sums.txt").write_text("".join(f"{sha(data)}  {name}\n" for name, data in sorted(published.items())), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-a", type=pathlib.Path)
    parser.add_argument("--build-b", type=pathlib.Path)
    parser.add_argument("--base-authority", type=pathlib.Path)
    parser.add_argument("--baseline-prefix", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--verify-output", type=pathlib.Path)
    args = parser.parse_args()
    if args.verify_output:
        if any((args.build_a, args.build_b, args.base_authority, args.baseline_prefix, args.output)):
            fail("--verify-output cannot be combined with publication inputs")
        verify_output(args.verify_output); print("U-Boot nowhere-environment authority: VERIFIED"); return
    if not all((args.build_a, args.build_b, args.base_authority, args.baseline_prefix, args.output)):
        fail("publication requires both builds, base authority, baseline prefix, and output")
    verify(args.build_a, args.build_b, args.base_authority, args.baseline_prefix, args.output)


if __name__ == "__main__":
    main()
