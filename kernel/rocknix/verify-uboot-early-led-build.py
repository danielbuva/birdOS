#!/usr/bin/env python3
"""Verify and seal two identical RG34XX-SP early green/red-off U-Boot builds."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE_VERIFIER_PATH = ROOT / "kernel/rocknix/verify-uboot-status-led-build.py"
INSTALL_VERIFIER = ROOT / "kernel/rocknix/verify-uboot-install-authority.py"

BASE_COMBINED_SHA = "080ae5fde3476addb5aa74f03a021aa4fbaa5deccb0964227c0fc91fe657b584"
CANDIDATE_COMBINED_SHA = "ac55433c1b39363b6665d3de0bb949f25ee067a7863ac149fc07b885e14b5c82"
CANDIDATE_SPL_SHA = "c9e0982fb0aaced7ef658bd8c89a822009e9e3b1bb570720ba8ac4e6e125c8a0"
CANDIDATE_UBOOT_SHA = "3c68d8b2d938f26bacadae6f32fdc3026ca5015bc0954ea1a4720fa5e67d3b04"
CANDIDATE_CONFIG_SHA = "8ac42a460a867af4caa23aa3f12a79d4a8444b50cfab7d37b1dbe9bb16bb9928"
CONTROL_DTB_SHA = "ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589"
BASELINE_PREFIX_SHA = "fa35109b0b710ffe58dcb541d26349617f77d9213d25867dc328e666c3435774"
BASELINE_PREFIX_BYTES = 16 * 1024 * 1024
CANDIDATE_BYTES = 621073
SPL_BYTES = 40960
SPL_NONZERO_END = 37275
FIT_BYTES = CANDIDATE_BYTES - SPL_BYTES
FILES = (
    "u-boot-sunxi-with-spl.bin",
    "sunxi-spl.bin",
    "u-boot-nodtb.bin",
    "u-boot.dtb",
    "build.config",
)
PUBLISHED_FILES = (
    "authority.tsv",
    "baseline-prefix-16m.bin",
    "base-green.bin",
    "early-a.bin",
    "early-a.config",
    "early-b.bin",
    "early-b.config",
    "early-control.dtb",
    "early-green.bin",
    "early-spl.bin",
    "early-uboot.bin",
    "early.itb",
    "shipping-baseline.bin",
    "sha256sums.txt",
)


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read(path: pathlib.Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail(f"missing or unsafe build artifact: {path}")
    return path.read_bytes()


def load_base_verifier():
    spec = importlib.util.spec_from_file_location("bird_uboot_base_verify", BASE_VERIFIER_PATH)
    if spec is None or spec.loader is None:
        fail("could not load base U-Boot verifier")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_build(directory: pathlib.Path) -> dict[str, bytes]:
    return {name: read(directory / name) for name in FILES}


def verify_published(directory: pathlib.Path) -> None:
    if directory.is_symlink() or not directory.is_dir():
        fail("early-LED authority directory is missing or unsafe")
    names = tuple(sorted(path.name for path in directory.iterdir()))
    if names != tuple(sorted(PUBLISHED_FILES)):
        fail("early-LED published file inventory changed")
    sums = read(directory / "sha256sums.txt").decode("ascii").splitlines()
    expected_names = tuple(sorted(name for name in PUBLISHED_FILES if name != "sha256sums.txt"))
    if len(sums) != len(expected_names):
        fail("early-LED checksum inventory changed")
    for line, name in zip(sums, expected_names):
        fields = line.split("  ")
        if fields != [sha(read(directory / name)), name]:
            fail(f"early-LED checksum changed: {name}")
    combined = read(directory / "early-green.bin")
    if sha(read(directory / "base-green.bin")) != BASE_COMBINED_SHA:
        fail("early-LED reviewed base identity changed")
    if combined != read(directory / "early-a.bin") or combined != read(directory / "early-b.bin"):
        fail("early-LED retained candidate builds differ")
    if len(combined) != CANDIDATE_BYTES or sha(combined) != CANDIDATE_COMBINED_SHA:
        fail("early-LED reviewed combined identity changed")
    if read(directory / "early-a.config") != read(directory / "early-b.config"):
        fail("early-LED retained configs differ")
    if sha(read(directory / "early-a.config")) != CANDIDATE_CONFIG_SHA:
        fail("early-LED reviewed config identity changed")
    if sha(read(directory / "early-spl.bin")) != CANDIDATE_SPL_SHA:
        fail("early-LED reviewed SPL identity changed")
    if sha(read(directory / "early-uboot.bin")) != CANDIDATE_UBOOT_SHA:
        fail("early-LED reviewed U-Boot identity changed")
    if sha(read(directory / "early-control.dtb")) != CONTROL_DTB_SHA:
        fail("early-LED reviewed control FDT identity changed")
    baseline_prefix = read(directory / "baseline-prefix-16m.bin")
    if len(baseline_prefix) != BASELINE_PREFIX_BYTES or sha(baseline_prefix) != BASELINE_PREFIX_SHA:
        fail("early-LED accepted baseline prefix identity changed")
    shipping_baseline = read(directory / "shipping-baseline.bin")
    if sha(shipping_baseline) != "42c01f4524b45cba7c239cd940fc4e71eed7545901da201f27fed2193b7fdf45":
        fail("early-LED shipping baseline identity changed")
    if shipping_baseline != baseline_prefix[8192 : 8192 + len(shipping_baseline)]:
        fail("early-LED shipping baseline is not bound to the accepted prefix")
    if combined[:SPL_BYTES] != read(directory / "early-spl.bin"):
        fail("early-LED reviewed SPL binding changed")
    if combined[SPL_BYTES:] != read(directory / "early.itb"):
        fail("early-LED reviewed FIT binding changed")


def verify(
    build_a: pathlib.Path,
    build_b: pathlib.Path,
    base_authority: pathlib.Path,
    baseline_prefix_path: pathlib.Path,
    output: pathlib.Path,
) -> None:
    if output.exists() or output.is_symlink():
        fail("refusing to replace early-LED authority output")
    subprocess.run(
        ["python3", str(INSTALL_VERIFIER), str(base_authority)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    base_combined = read(base_authority / "bird-uboot-green.bin")
    shipping_baseline = read(base_authority / "rocknix-baseline.bin")
    baseline_prefix = read(baseline_prefix_path)
    if len(baseline_prefix) != BASELINE_PREFIX_BYTES or sha(baseline_prefix) != BASELINE_PREFIX_SHA:
        fail("accepted baseline 16 MiB prefix identity changed")
    if baseline_prefix[8192 : 8192 + len(shipping_baseline)] != shipping_baseline:
        fail("shipping baseline is not embedded in the accepted prefix")
    base_uboot = read(base_authority / "green-uboot.bin")
    base_fit = read(base_authority / "green.itb")
    base_config = read(base_authority / "green-a.config")
    bl31 = read(base_authority / "bl31.bin")
    if sha(base_combined) != BASE_COMBINED_SHA:
        fail("reviewed full-U-Boot green base identity changed")

    first = load_build(build_a)
    second = load_build(build_b)
    if first != second:
        fail("early-LED isolated builds are not byte-identical")
    combined = first["u-boot-sunxi-with-spl.bin"]
    spl = first["sunxi-spl.bin"]
    uboot = first["u-boot-nodtb.bin"]
    control = first["u-boot.dtb"]
    config = first["build.config"]
    if len(combined) != CANDIDATE_BYTES or sha(combined) != CANDIDATE_COMBINED_SHA:
        fail("early-LED combined artifact identity changed")
    if len(spl) != SPL_BYTES or sha(spl) != CANDIDATE_SPL_SHA:
        fail("early-LED SPL identity changed")
    if sha(uboot) != CANDIDATE_UBOOT_SHA or sha(config) != CANDIDATE_CONFIG_SHA:
        fail("early-LED full-U-Boot or config identity changed")
    if sha(control) != CONTROL_DTB_SHA:
        fail("early-LED control FDT changed")
    if combined[:SPL_BYTES] != spl or combined[4:12] != b"eGON.BT0":
        fail("early-LED combined image does not contain its exact SPL")
    if int.from_bytes(combined[16:20], "little") != SPL_BYTES:
        fail("early-LED SPL header length changed")
    nonzero_end = max(index for index, value in enumerate(spl) if value) + 1
    if nonzero_end != SPL_NONZERO_END or any(spl[nonzero_end:]):
        fail("early-LED SPL reserve boundary changed")
    if b"gpio_led\0" not in spl or b"failed requesting GPIO%lu!\n\0" not in spl:
        fail("early-LED SPL lacks the status-LED GPIO implementation")

    expected_removed = {
        b"# CONFIG_LED_STATUS1 is not set",
        b"# CONFIG_SPL_DRIVERS_MISC is not set",
    }
    expected_added = {
        b"CONFIG_LED_STATUS1=y",
        b"CONFIG_LED_STATUS_BIT1=267",
        b"CONFIG_LED_STATUS_FREQ1=2",
        b"CONFIG_LED_STATUS_STATE1=0",
        b"CONFIG_SPL_DRIVERS_MISC=y",
    }
    base_lines = set(base_config.splitlines())
    candidate_lines = set(config.splitlines())
    if base_lines - candidate_lines != expected_removed:
        fail("early-LED resolved config removes unknown policy")
    if candidate_lines - base_lines != expected_added:
        fail("early-LED resolved config adds unknown policy")
    if b"CONFIG_LED_STATUS_BIT=268\n" not in config or b"CONFIG_LED_STATUS_STATE=2\n" not in config:
        fail("early-LED primary green policy changed")

    verifier = load_base_verifier()
    candidate_fit = combined[SPL_BYTES:]
    if len(candidate_fit) != FIT_BYTES:
        fail("early-LED FIT length changed")
    verifier.verify_fit(candidate_fit, uboot, bl31, control)
    base_nodes = verifier.parse_fit(base_fit)
    candidate_nodes = verifier.parse_fit(candidate_fit)
    if set(base_nodes) != set(candidate_nodes):
        fail("early-LED FIT node inventory changed")
    for node in base_nodes:
        before = dict(base_nodes[node])
        after = dict(candidate_nodes[node])
        if node == "/images/uboot":
            if before.pop("data", None) != base_uboot or after.pop("data", None) != uboot:
                fail("early-LED FIT U-Boot payload binding changed")
        if before != after:
            fail(f"early-LED FIT changed outside U-Boot data: {node}")

    output.mkdir(mode=0o755)
    published = {
        "base-green.bin": base_combined,
        "baseline-prefix-16m.bin": baseline_prefix,
        "shipping-baseline.bin": shipping_baseline,
        "early-green.bin": combined,
        "early-a.bin": combined,
        "early-b.bin": second["u-boot-sunxi-with-spl.bin"],
        "early-a.config": config,
        "early-b.config": second["build.config"],
        "early-spl.bin": spl,
        "early-uboot.bin": uboot,
        "early-control.dtb": control,
        "early.itb": candidate_fit,
    }
    for name, data in published.items():
        (output / name).write_bytes(data)
    authority = (
        "schema\tbird-uboot-early-led-authority-v1\n"
        f"base-candidate-sha256\t{BASE_COMBINED_SHA}\n"
        f"candidate-bytes\t{CANDIDATE_BYTES}\n"
        f"candidate-sha256\t{CANDIDATE_COMBINED_SHA}\n"
        f"spl-bytes\t{SPL_BYTES}\n"
        f"spl-sha256\t{CANDIDATE_SPL_SHA}\n"
        f"spl-nonzero-end\t{SPL_NONZERO_END}\n"
        f"spl-zero-reserve-bytes\t{SPL_BYTES - SPL_NONZERO_END}\n"
        f"candidate-uboot-sha256\t{CANDIDATE_UBOOT_SHA}\n"
        f"control-fdt-sha256\t{CONTROL_DTB_SHA}\n"
        f"candidate-config-sha256\t{CANDIDATE_CONFIG_SHA}\n"
        "early-led-policy\tPI12-green-on,PI11-red-off\n"
        "spl-led-hook\tCONFIG_SPL_DRIVERS_MISC\n"
        "repeat-byte-identical\tyes\n"
    ).encode("ascii")
    (output / "authority.tsv").write_bytes(authority)
    published["authority.tsv"] = authority
    sums = "".join(f"{sha(data)}  {name}\n" for name, data in sorted(published.items()))
    (output / "sha256sums.txt").write_text(sums, encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-a", type=pathlib.Path)
    parser.add_argument("--build-b", type=pathlib.Path)
    parser.add_argument("--base-authority", type=pathlib.Path)
    parser.add_argument("--baseline-prefix", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--verify-output", type=pathlib.Path)
    arguments = parser.parse_args()
    if arguments.verify_output is not None:
        if any(
            value is not None
            for value in (
                arguments.build_a,
                arguments.build_b,
                arguments.base_authority,
                arguments.baseline_prefix,
                arguments.output,
            )
        ):
            fail("--verify-output cannot be combined with build-publication arguments")
        verify_published(arguments.verify_output)
        print("Early-LED U-Boot authority: VERIFIED")
        return
    if any(
        value is None
        for value in (
            arguments.build_a,
            arguments.build_b,
            arguments.base_authority,
            arguments.baseline_prefix,
            arguments.output,
        )
    ):
        fail(
            "build publication requires --build-a, --build-b, --base-authority, "
            "--baseline-prefix, and --output"
        )
    verify(
        arguments.build_a,
        arguments.build_b,
        arguments.base_authority,
        arguments.baseline_prefix,
        arguments.output,
    )


if __name__ == "__main__":
    main()
