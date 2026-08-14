#!/usr/bin/env python3
"""Verify and seal repeated birdOS fixed-extlinux U-Boot builds."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib


ROOT = pathlib.Path(__file__).resolve().parents[2]
ENV_VERIFIER_PATH = ROOT / "kernel/rocknix/verify-uboot-environment-nowhere-build.py"
BASE_SHA = "970b5c485b0468e60c894ed39a0fbf786a3633d92e852a1f4005091b40d887e7"
CANDIDATE_SHA = "cd99dd9edaad868e460b256729c2e0f5a20a606a2a33e4015d93c42159da1191"
UBOOT_SHA = "222123612cf81b7d8e9c0098295c78048a546ce2249f7252c80f623b1f001cb6"
CONFIG_SHA = "3e1eac486c6e9aa1f73f44e0ee63fde72171bd7b7e6b75a5fa09869b96f64f9b"
SPL_SHA = "0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c"
DTB_SHA = "ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589"
PREFIX_SHA = "f81187878bbe491dabaf1a4f5fda051d4edabbcb476681d1323d73557e3072ff"
CANDIDATE_BYTES = 620745
SPL_BYTES = 40960
DIRECT = b"mmc dev 0; sysboot mmc 0:1 any ${scriptaddr} /extlinux/extlinux.conf"
FILES = ("u-boot-sunxi-with-spl.bin", "sunxi-spl.bin", "u-boot-nodtb.bin", "u-boot.dtb", "u-boot.itb", "build.config")
PUBLISHED = (
    "authority.tsv", "base-env.bin", "baseline-prefix-16m.bin", "direct-a.bin",
    "direct-a.config", "direct-b.bin", "direct-b.config", "direct-extlinux.bin",
    "direct-extlinux.itb", "direct-extlinux-spl.bin", "direct-extlinux-uboot.bin",
    "direct-extlinux.dtb", "shipping-baseline.bin", "sha256sums.txt",
)


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def read(path: pathlib.Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail(f"missing or unsafe artifact: {path}")
    return path.read_bytes()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_env_verifier():
    spec = importlib.util.spec_from_file_location("bird_env_verify", ENV_VERIFIER_PATH)
    if spec is None or spec.loader is None:
        fail("could not load environment verifier")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def load_build(directory: pathlib.Path) -> dict[str, bytes]:
    return {name: read(directory / name) for name in FILES}


def verify_output(directory: pathlib.Path) -> None:
    if directory.is_symlink() or not directory.is_dir(): fail("direct authority is missing or unsafe")
    if tuple(sorted(p.name for p in directory.iterdir())) != tuple(sorted(PUBLISHED)): fail("direct authority inventory changed")
    expected = sorted(n for n in PUBLISHED if n != "sha256sums.txt")
    lines = read(directory / "sha256sums.txt").decode("ascii").splitlines()
    if len(lines) != len(expected): fail("direct checksum inventory changed")
    for line, name in zip(lines, expected):
        if line != f"{sha(read(directory / name))}  {name}": fail(f"direct checksum changed: {name}")
    candidate = read(directory / "direct-extlinux.bin")
    if candidate != read(directory / "direct-a.bin") or candidate != read(directory / "direct-b.bin"): fail("retained direct builds differ")
    if len(candidate) != CANDIDATE_BYTES or sha(candidate) != CANDIDATE_SHA: fail("reviewed direct candidate changed")


def verify(a: pathlib.Path, b: pathlib.Path, base: pathlib.Path, output: pathlib.Path) -> None:
    if output.exists() or output.is_symlink(): fail("refusing to replace direct authority")
    env = load_env_verifier(); env.verify_output(base)
    base_combined = read(base / "env-nowhere.bin"); baseline_prefix = read(base / "baseline-prefix-16m.bin")
    shipping_baseline = read(base / "shipping-baseline.bin")
    base_config = read(base / "env-a.config")
    if sha(base_combined) != BASE_SHA: fail("accepted environment base changed")
    first, second = load_build(a), load_build(b)
    if first != second: fail("direct builds are not byte-identical")
    combined, spl, uboot, dtb, fit, config = (first[n] for n in FILES)
    if len(combined) != CANDIDATE_BYTES or sha(combined) != CANDIDATE_SHA: fail("direct combined identity changed")
    if sha(uboot) != UBOOT_SHA or sha(config) != CONFIG_SHA: fail("direct U-Boot or config changed")
    if sha(spl) != SPL_SHA or sha(dtb) != DTB_SHA: fail("direct candidate changed SPL or DTB")
    if combined[:SPL_BYTES] != spl or combined[SPL_BYTES:] != fit: fail("direct component binding changed")
    before = set(base_config.splitlines()); after = set(config.splitlines())
    removed = {line for line in before - after if line.startswith(b"CONFIG_BOOTCOMMAND=")}
    added = {line for line in after - before if line.startswith(b"CONFIG_BOOTCOMMAND=")}
    if removed != {b'CONFIG_BOOTCOMMAND="run distro_bootcmd"'} or added != {b'CONFIG_BOOTCOMMAND="' + DIRECT + b'"'}:
        fail("direct resolved config delta changed")
    if (before - after) != removed or (after - before) != added: fail("direct config changed outside BOOTCOMMAND")
    if b"bootcmd=" + DIRECT + b"\0" not in uboot: fail("direct compiled boot command is missing")
    expected_prefix = bytearray(baseline_prefix); expected_prefix[8192:8192 + len(combined)] = combined
    if sha(expected_prefix) != PREFIX_SHA: fail("direct full-prefix result changed")
    output.mkdir(mode=0o755)
    published = {
        "base-env.bin": base_combined, "baseline-prefix-16m.bin": baseline_prefix,
        "shipping-baseline.bin": shipping_baseline,
        "direct-a.bin": combined, "direct-b.bin": second["u-boot-sunxi-with-spl.bin"],
        "direct-a.config": config, "direct-b.config": second["build.config"],
        "direct-extlinux.bin": combined, "direct-extlinux.itb": fit,
        "direct-extlinux-spl.bin": spl, "direct-extlinux-uboot.bin": uboot,
        "direct-extlinux.dtb": dtb,
    }
    authority = ("schema\tbird-uboot-direct-extlinux-authority-v1\n" f"base-sha256\t{BASE_SHA}\ncombined-bytes\t{CANDIDATE_BYTES}\n" f"combined-sha256\t{CANDIDATE_SHA}\nuboot-sha256\t{UBOOT_SHA}\n" f"config-sha256\t{CONFIG_SHA}\nfull-prefix-sha256\t{PREFIX_SHA}\n" "boot-command\tmmc0p1-direct-sysboot\nrepeat-byte-identical\tyes\n").encode("ascii")
    published["authority.tsv"] = authority
    for name, data in published.items(): (output / name).write_bytes(data)
    (output / "sha256sums.txt").write_text("".join(f"{sha(data)}  {name}\n" for name, data in sorted(published.items())), encoding="ascii")


def main() -> None:
    p = argparse.ArgumentParser(); p.add_argument("--build-a", type=pathlib.Path); p.add_argument("--build-b", type=pathlib.Path); p.add_argument("--base-authority", type=pathlib.Path); p.add_argument("--output", type=pathlib.Path); p.add_argument("--verify-output", type=pathlib.Path); a = p.parse_args()
    if a.verify_output:
        if any((a.build_a, a.build_b, a.base_authority, a.output)): fail("verify-output cannot be combined")
        verify_output(a.verify_output); print("U-Boot direct-extlinux authority: VERIFIED"); return
    if not all((a.build_a, a.build_b, a.base_authority, a.output)): fail("publication inputs are incomplete")
    verify(a.build_a, a.build_b, a.base_authority, a.output)


if __name__ == "__main__": main()
