#!/usr/bin/env python3
"""Focused host contracts for the RG34XX-SP fast-init U-Boot authority."""

from __future__ import annotations

import importlib.util
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
BUILDER = ROOT / "kernel/rocknix/build-uboot-fast-init.sh"
VERIFIER = ROOT / "kernel/rocknix/verify-uboot-fast-init-build.py"
BASE = ROOT / "kernel/work/bird-uboot-no-heap-clear-20260701"
BL31 = BASE / "bl31.bin"
TOOLCHAIN_AUTHORITY = BASE / "toolchain-authority.tsv"


def load_verifier():
    spec = importlib.util.spec_from_file_location("bird_fast_init_verifier", VERIFIER)
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
        raise AssertionError("invalid fast-init authority was accepted")


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


def config_key(line: bytes) -> bytes | None:
    if line.startswith(b"CONFIG_"):
        return line.split(b"=", 1)[0]
    if line.startswith(b"# CONFIG_") and line.endswith(b" is not set"):
        return line[2:-11]
    return None


def make_candidate_config(module, base: bytes) -> bytes:
    lines = [
        line
        for line in base.splitlines()
        if config_key(line) not in module.EXPECTED_CONFIG_DELTA
    ]
    lines.extend(
        (
            b'CONFIG_BOOTCOMMAND="' + module.FAST_BOOT_COMMAND + b'"',
            b"CONFIG_BOOTDELAY=-2",
            b"CONFIG_NO_NET=y",
            b"# CONFIG_BOOTSTD is not set",
            b"# CONFIG_NET is not set",
            b"# CONFIG_REGEX is not set",
            b"# CONFIG_SPL_CRC8 is not set",
        )
    )
    result = b"\n".join(lines) + b"\n"
    module.verify_config_delta(base, result)
    return result


def make_candidate_uboot(module, base: bytes) -> bytes:
    old_boot = b"bootcmd=" + module.OLD_BOOT_COMMAND + b"\0"
    new_boot = b"bootcmd=" + module.FAST_BOOT_COMMAND + b"\0"
    assert len(new_boot) < len(old_boot) and base.count(old_boot) == 1
    result = bytearray(base)
    offset = base.index(old_boot)
    result[offset:offset + len(old_boot)] = new_boot.ljust(len(old_boot), b"\0")

    old_delay = b"bootdelay=0\0"
    new_delay = b"bootdelay=-2\0"
    assert len(new_delay) == len(old_delay) + 1 and base.count(old_delay) == 1
    offset = base.index(old_delay)
    result[offset:offset + len(old_delay)] = new_delay[:-1]
    result[offset + len(old_delay)] = 0
    result = bytes(result)
    assert result.count(new_boot) == 1 and old_boot not in result
    assert result.count(new_delay) == 1 and old_delay not in result
    return result


def static_contract(module) -> None:
    source = BUILDER.read_text(encoding="utf-8")
    assert source.startswith("#!/bin/sh\n")
    assert "set -eu\n" in source
    assert "host artifact builder with no deployment mode" in source
    assert module.ROCKNIX_COMMIT in source
    assert module.FAST_DEFCONFIG_SHA256 in source
    assert module.BASE_AUTHORITY_SHA256 in source
    assert module.BL31_SHA256 in source
    assert module.TOOLCHAIN_AUTHORITY_SHA256 in source
    assert "SOURCE_DATE_EPOCH=1782880730" in source
    assert "FIT_DATE_EPOCH=1782880744" in source
    assert "transform-uboot-environment-nowhere.py" in source
    assert "transform-uboot-direct-extlinux.py" in source
    assert "transform-uboot-no-heap-clear.py" in source
    assert "transform-uboot-fast-init.py" in source
    assert "verify-uboot-no-heap-clear-build.py" in source
    assert "verify-uboot-fast-init-build.py" in source
    assert "for BUILD_NAME in fast-init-a fast-init-b" in source
    assert "--network none" in source
    assert "--read-only" in source
    assert '"$WORK/input:/input:ro"' in source
    assert '"$TOOLCHAIN:$CONTAINER_TOOLCHAIN:ro"' in source
    assert "export CCACHE_DISABLE=1" in source
    assert 'grep -Fqx "CONFIG_BOOTDELAY=-2"' in source
    assert 'CONFIG_BOOTCOMMAND=\"sysboot mmc 0:1 fat ${scriptaddr}' in source
    assert 'grep -Fqx "CONFIG_NO_NET=y"' in source
    assert 'grep -Fqx "# CONFIG_BOOTSTD is not set"' in source
    assert 'grep -Fqx "# CONFIG_SYS_MALLOC_CLEAR_ON_INIT is not set"' in source
    assert 'grep -Fqx "CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT=y"' in source
    assert "patch-fit-root-timestamp.py u-boot.itb" in source
    assert "tools/mkimage -F" not in source
    assert "/dev/rdisk" not in source
    assert "/dev/disk" not in source
    assert "diskutil" not in source
    assert "sudo " not in source

    assert len(module.EXPECTED_CONFIG_DELTA) == 42
    assert module.REVIEWED_CANDIDATE_IDENTITIES == {
        "candidate-bytes": 556977,
        "candidate-sha256": "4afc68bd2a7fdaacc212683a1a268380c07775d18cf12025285778221e986081",
        "candidate-fit-bytes": 516017,
        "candidate-fit-sha256": "d827586fefa78cc12dba89b3912f1a428b5218415c62dc8308c24a252a0eaea9",
        "candidate-uboot-bytes": 437168,
        "candidate-uboot-sha256": "9d557ccc6efb40b4e4f3daeea648f51ae313d6bec9c342d41abf4b8fdefbeb89",
        "candidate-config-sha256": "34d359c61ede0bb54361b5f092cc9fa77fafdd3ed10aeee932622e290ad68971",
        "full-prefix-sha256": "172ca1a500603ea371a17bee1b6a7632ba17e4991a400f57cee0b2231e75bdeb",
    }
    assert module.EXPECTED_CONFIG_DELTA[b"CONFIG_BOOTDELAY"] == (b"0", b"-2")
    assert module.EXPECTED_CONFIG_DELTA[b"CONFIG_NO_NET"] == (b"n", b"y")
    assert module.EXPECTED_CONFIG_DELTA[b"CONFIG_BOOTCOMMAND"] == (
        b'"' + module.OLD_BOOT_COMMAND + b'"',
        b'"' + module.FAST_BOOT_COMMAND + b'"',
    )
    for build in module.BUILD_NAMES:
        for suffix in module.PASS_SUFFIXES:
            assert f"{build}{suffix}" in module.PUBLISHED


def fixture_contract(module) -> None:
    required = (BASE / "no-heap-clear.bin", BL31, TOOLCHAIN_AUTHORITY)
    if not all(path.is_file() for path in required):
        return
    base_combined = (BASE / "no-heap-clear.bin").read_bytes()
    base_fit = (BASE / "no-heap-clear.itb").read_bytes()
    base_uboot = (BASE / "no-heap-clear-uboot.bin").read_bytes()
    base_dtb = (BASE / "no-heap-clear-control.dtb").read_bytes()
    base_spl = (BASE / "no-heap-clear-spl.bin").read_bytes()
    base_config = (BASE / "no-heap-clear.config").read_bytes()
    assert module.sha256(base_combined) == module.BASE_COMBINED_SHA256
    assert module.sha256(base_uboot) == module.BASE_UBOOT_SHA256
    assert module.sha256(base_spl) == module.BASE_SPL_SHA256
    assert module.sha256(base_dtb) == module.BASE_DTB_SHA256

    changed_uboot = make_candidate_uboot(module, base_uboot)
    offset = base_fit.find(base_uboot)
    assert offset >= 0 and base_fit.find(base_uboot, offset + 1) == -1
    changed_fit = base_fit[:offset] + changed_uboot + base_fit[offset + len(base_uboot):]
    changed_combined = base_combined[: module.SPL_REGION_BYTES] + changed_fit
    changed_config = make_candidate_config(module, base_config)

    reviewed = module.REVIEWED_CANDIDATE_IDENTITIES
    module.REVIEWED_CANDIDATE_IDENTITIES = {}
    with tempfile.TemporaryDirectory(prefix="bird-fast-init-build-test-") as temporary:
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
        assert authority["resolved-gcc-config-delta-symbols"] == "42"
        assert authority["candidate-repeat-byte-identical"] == "yes"
        assert authority["fit-change-scope"] == "uboot-data-only"
        assert (output / "fast-init.bin").read_bytes() == changed_combined
        assert (output / "base-no-heap-clear.bin").read_bytes() == base_combined
        assert (output / "fast-init-a-uboot.bin").read_bytes() == changed_uboot
        assert (output / "fast-init-b-uboot.bin").read_bytes() == changed_uboot
        assert module.sha256(
            (output / "base-no-heap-clear-prefix-16m.bin").read_bytes()
        ) == module.BASE_FULL_PREFIX_SHA256

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

        bad_config = changed_config.replace(
            b"CONFIG_MMC=y\n", b"# CONFIG_MMC is not set\n"
        )
        bad_config_build = root / "bad-config"
        write_build(
            bad_config_build,
            changed_combined,
            changed_fit,
            changed_uboot,
            base_dtb,
            base_spl,
            bad_config,
        )
        expect_rejected(
            lambda: module.publish(
                bad_config_build,
                bad_config_build,
                BASE,
                BL31,
                TOOLCHAIN_AUTHORITY,
                root / "bad-config-output",
            ),
            "exact 42-symbol fast-init delta",
        )

        drift_fit = bytearray(changed_fit)
        description = drift_fit.find(b"Configuration to load")
        assert description >= 0
        drift_fit[description] ^= 1
        drift_fit = bytes(drift_fit)
        drift_build = root / "drift-fit"
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

        bad_spl = bytearray(base_spl)
        bad_spl[-1] ^= 1
        bad_spl = bytes(bad_spl)
        bad_spl_combined = bad_spl + changed_combined[len(bad_spl):]
        bad_spl_build = root / "bad-spl"
        write_build(
            bad_spl_build,
            bad_spl_combined,
            changed_fit,
            changed_uboot,
            base_dtb,
            bad_spl,
            changed_config,
        )
        expect_rejected(
            lambda: module.publish(
                bad_spl_build,
                bad_spl_build,
                BASE,
                BL31,
                TOOLCHAIN_AUTHORITY,
                root / "bad-spl-output",
            ),
            "altered the SPL",
        )

        sums = output / "sha256sums.txt"
        sums.write_bytes(sums.read_bytes().replace(b"authority.tsv", b"authority.tsx"))
        expect_rejected(
            lambda: module.verify_output(output),
            "fast-init checksum changed",
        )
    module.REVIEWED_CANDIDATE_IDENTITIES = reviewed


def main() -> None:
    module = load_verifier()
    static_contract(module)
    fixture_contract(module)
    print("U-Boot fast-init build tests: PASS")


if __name__ == "__main__":
    main()
