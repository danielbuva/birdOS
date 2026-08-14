#!/usr/bin/env python3
"""Focused host contracts for the no-heap-clear U-Boot build authority."""

from __future__ import annotations

import importlib.util
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
BUILDER = ROOT / "kernel/rocknix/build-uboot-no-heap-clear.sh"
VERIFIER = ROOT / "kernel/rocknix/verify-uboot-no-heap-clear-build.py"
BASE = ROOT / "kernel/work/bird-uboot-direct-extlinux-20260701"
BL31 = (
    ROOT
    / "kernel/work/rocknix-system-exact-20260701/usr/share/bootloader/bl31.bin"
)
TOOLCHAIN_AUTHORITY = (
    ROOT / "kernel/work/bird-uboot-green-20260701/toolchain-authority.tsv"
)


def load_verifier():
    spec = importlib.util.spec_from_file_location("bird_no_clear_verifier", VERIFIER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_rejected(function, diagnostic: str) -> None:
    try:
        function()
    except SystemExit as error:
        assert diagnostic in str(error), str(error)
    else:
        raise AssertionError("invalid no-heap-clear authority was accepted")


def write_build(
    directory: pathlib.Path,
    combined: bytes,
    fit: bytes,
    uboot: bytes,
    dtb: bytes,
    spl: bytes,
    config: bytes,
) -> None:
    (directory / "spl").mkdir(parents=True)
    (directory / "u-boot-sunxi-with-spl.bin").write_bytes(combined)
    (directory / "u-boot.itb").write_bytes(fit)
    (directory / "u-boot-nodtb.bin").write_bytes(uboot)
    (directory / "u-boot.dtb").write_bytes(dtb)
    (directory / "spl/sunxi-spl.bin").write_bytes(spl)
    (directory / "build.config").write_bytes(config)


def static_contract(module) -> None:
    source = BUILDER.read_text(encoding="utf-8")
    assert source.startswith("#!/bin/sh\n")
    assert "set -eu\n" in source
    assert "no deployment mode" in source
    assert module.ROCKNIX_COMMIT in source
    assert module.NO_CLEAR_DEFCONFIG_SHA256 in source
    assert module.DIRECT_AUTHORITY_SHA256 in source
    assert module.BL31_SHA256 in source
    assert "transform-uboot-environment-nowhere.py" in source
    assert "transform-uboot-direct-extlinux.py" in source
    assert "transform-uboot-no-heap-clear.py" in source
    assert "verify-uboot-direct-extlinux-build.py" in source
    assert "verify-uboot-no-heap-clear-build.py" in source
    assert "for BUILD_NAME in no-clear-a no-clear-b" in source
    assert "--network none" in source
    assert "--read-only" in source
    assert '"$WORK/input:/input:ro"' in source
    assert '"$TOOLCHAIN:$CONTAINER_TOOLCHAIN:ro"' in source
    assert "export CCACHE_DISABLE=1" in source
    assert 'grep -Fqx "# CONFIG_SYS_MALLOC_CLEAR_ON_INIT is not set"' in source
    assert 'grep -Fqx "CONFIG_SYS_MALLOC_LEN=0x4020000"' in source
    assert 'grep -Fqx "CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT=y"' in source
    assert "patch-fit-root-timestamp.py u-boot.itb" in source
    assert "tools/mkimage -F" not in source
    assert "/dev/rdisk" not in source
    assert "/dev/disk" not in source
    assert "diskutil" not in source
    assert "sudo " not in source

    verifier = VERIFIER.read_text(encoding="utf-8")
    assert "candidate-hashes-pending" in verifier
    assert module.REVIEWED_CANDIDATE_IDENTITIES == {
        "candidate-bytes": 620745,
        "candidate-sha256": "38ace6d738fed727fdd2274b510c3e18105b2c71f7b1d908dece357e31d1365c",
        "candidate-fit-bytes": 579785,
        "candidate-fit-sha256": "991d29c7201afceea7e18e5bc03707c8308306ba2cf67f16a1d48f95c2d14a7b",
        "candidate-uboot-bytes": 500936,
        "candidate-uboot-sha256": "d1ad2598283dac0913c5d49c5d3ccec7b21f9b14226038561c7334afff48fba4",
        "candidate-config-sha256": "57c109fd8a753cecf14c3afd60de1b6e778772975fa905dba1eda9b27230b23a",
        "full-prefix-sha256": "ea1afbf3186945e562aa0844d7ab6d1b027be9cfafe225a0e4c0745ffc50b305",
    }
    for build in module.BUILD_NAMES:
        for suffix in module.PASS_SUFFIXES:
            assert f"{build}{suffix}" in module.PUBLISHED


def fixture_contract(module) -> None:
    required = (BASE / "direct-extlinux.bin", BL31, TOOLCHAIN_AUTHORITY)
    if not all(path.is_file() for path in required):
        return
    base_combined = (BASE / "direct-extlinux.bin").read_bytes()
    base_fit = (BASE / "direct-extlinux.itb").read_bytes()
    base_uboot = (BASE / "direct-extlinux-uboot.bin").read_bytes()
    base_dtb = (BASE / "direct-extlinux.dtb").read_bytes()
    base_spl = (BASE / "direct-extlinux-spl.bin").read_bytes()
    base_config = (BASE / "direct-a.config").read_bytes()
    assert module.sha256(base_combined) == module.DIRECT_COMBINED_SHA256
    assert module.sha256(base_uboot) == module.DIRECT_UBOOT_SHA256
    assert module.sha256(base_spl) == module.DIRECT_SPL_SHA256
    assert module.sha256(base_dtb) == module.DIRECT_DTB_SHA256

    changed_uboot = bytearray(base_uboot)
    changed_uboot[100] ^= 1
    changed_uboot = bytes(changed_uboot)
    offset = base_fit.find(base_uboot)
    assert offset >= 0 and base_fit.find(base_uboot, offset + 1) == -1
    changed_fit = bytearray(base_fit)
    changed_fit[offset + 100] ^= 1
    changed_fit = bytes(changed_fit)
    changed_combined = base_combined[: module.SPL_REGION_BYTES] + changed_fit
    changed_config = base_config.replace(
        b"CONFIG_SYS_MALLOC_CLEAR_ON_INIT=y\n",
        b"# CONFIG_SYS_MALLOC_CLEAR_ON_INIT is not set\n",
    )
    assert changed_config != base_config
    module.verify_config_delta(base_config, changed_config)

    reviewed = module.REVIEWED_CANDIDATE_IDENTITIES
    module.REVIEWED_CANDIDATE_IDENTITIES = {}
    with tempfile.TemporaryDirectory(prefix="bird-no-clear-build-test-") as temporary:
        root = pathlib.Path(temporary)
        build_a, build_b = root / "a", root / "b"
        for build in (build_a, build_b):
            write_build(
                build,
                changed_combined,
                changed_fit,
                changed_uboot,
                base_dtb,
                base_spl,
                changed_config,
            )
        output = root / "authority"
        module.publish(build_a, build_b, BASE, BL31, TOOLCHAIN_AUTHORITY, output)
        module.verify_output(output)
        authority = module.parse_authority((output / "authority.tsv").read_bytes())
        assert authority["review-state"] == module.REVIEW_STATE
        assert authority["candidate-repeat-byte-identical"] == "yes"
        assert authority["spl-heap-clear-preserved"] == "yes"
        assert (output / "no-heap-clear.bin").read_bytes() == changed_combined
        assert (output / "base-direct.bin").read_bytes() == base_combined
        assert (output / "shipping-baseline.bin").read_bytes() == (
            BASE / "shipping-baseline.bin"
        ).read_bytes()
        assert (output / "no-clear-a-uboot.bin").read_bytes() == changed_uboot
        assert (output / "no-clear-b-uboot.bin").read_bytes() == changed_uboot

        bad_b = root / "bad-b"
        write_build(
            bad_b,
            changed_combined,
            changed_fit,
            changed_uboot,
            base_dtb,
            base_spl,
            changed_config + b"# drift\n",
        )
        expect_rejected(
            lambda: module.publish(
                build_a,
                bad_b,
                BASE,
                BL31,
                TOOLCHAIN_AUTHORITY,
                root / "bad-repeat-output",
            ),
            "not reproducible: build.config differs",
        )

        drift_fit = bytearray(changed_fit)
        description = drift_fit.find(b"Configuration to load")
        assert description >= 0
        drift_fit[description] ^= 1
        drift_fit = bytes(drift_fit)
        drift_build = root / "drift"
        write_build(
            drift_build,
            base_combined[: module.SPL_REGION_BYTES] + drift_fit,
            drift_fit,
            changed_uboot,
            base_dtb,
            base_spl,
            changed_config,
        )
        expect_rejected(
            lambda: module.publish(
                drift_build,
                drift_build,
                BASE,
                BL31,
                TOOLCHAIN_AUTHORITY,
                root / "bad-scope-output",
            ),
            "FIT changed outside its U-Boot data",
        )

        sums = output / "sha256sums.txt"
        sums.write_bytes(sums.read_bytes().replace(b"authority.tsv", b"authority.tsx"))
        expect_rejected(
            lambda: module.verify_output(output),
            "no-heap-clear checksum changed",
        )
    module.REVIEWED_CANDIDATE_IDENTITIES = reviewed


def main() -> None:
    module = load_verifier()
    static_contract(module)
    fixture_contract(module)
    print("U-Boot no-heap-clear build tests: PASS")


if __name__ == "__main__":
    main()
