#!/usr/bin/env python3
"""Focused host contracts for the RG34XX-SP inplace-handoff U-Boot authority."""

from __future__ import annotations

import importlib.util
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
BUILDER = ROOT / "kernel/rocknix/build-uboot-inplace-handoff.sh"
VERIFIER = ROOT / "kernel/rocknix/verify-uboot-inplace-handoff-build.py"
BASE = ROOT / "kernel/work/bird-uboot-fast-init-20260701"
BL31 = BASE / "bl31.bin"
TOOLCHAIN_AUTHORITY = BASE / "toolchain-authority.tsv"


def load_verifier():
    spec = importlib.util.spec_from_file_location("bird_inplace_handoff_verifier", VERIFIER)
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
        raise AssertionError("invalid inplace-handoff authority was accepted")


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
    lines.append(b'CONFIG_ENV_SOURCE_FILE="bird-rg34xx-sp-handoff"')
    result = b"\n".join(lines) + b"\n"
    module.verify_config_delta(base, result)
    return result


def make_candidate_uboot(module, base: bytes) -> bytes:
    entries = (
        b"fdt_high=ffffffffffffffff\0"
        b"initrd_high=ffffffffffffffff\0"
    )
    assert b"fdt_high=" not in base and b"initrd_high=" not in base
    hole = b"\0" * len(entries)
    offset = base.find(hole)
    assert offset >= 0
    result = base[:offset] + entries + base[offset + len(entries):]
    assert len(result) == len(base)
    assert result.count(b"fdt_high=ffffffffffffffff\0") == 1
    assert result.count(b"initrd_high=ffffffffffffffff\0") == 1
    return result


def static_contract(module) -> None:
    source = BUILDER.read_text(encoding="utf-8")
    assert source.startswith("#!/bin/sh\n")
    assert "set -eu\n" in source
    assert "host artifact builder with no deployment mode" in source
    assert module.ROCKNIX_COMMIT in source
    assert module.INPLACE_DEFCONFIG_SHA256 in source
    assert module.BASE_AUTHORITY_SHA256 in source
    assert module.BL31_SHA256 in source
    assert module.TOOLCHAIN_AUTHORITY_SHA256 in source
    assert "SOURCE_DATE_EPOCH=1782880730" in source
    assert "FIT_DATE_EPOCH=1782880744" in source
    assert "transform-uboot-environment-nowhere.py" in source
    assert "transform-uboot-direct-extlinux.py" in source
    assert "transform-uboot-no-heap-clear.py" in source
    assert "transform-uboot-fast-init.py" in source
    assert "transform-uboot-inplace-handoff.py" in source
    assert "verify-uboot-fast-init-build.py" in source
    assert "verify-uboot-inplace-handoff-build.py" in source
    assert "for BUILD_NAME in inplace-handoff-a inplace-handoff-b" in source
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
    assert 'CONFIG_ENV_SOURCE_FILE="bird-rg34xx-sp-handoff"' in source
    assert "fdt_high=ffffffffffffffff" in source
    assert "initrd_high=ffffffffffffffff" in source
    assert "patch-fit-root-timestamp.py u-boot.itb" in source
    assert "tools/mkimage -F" not in source
    assert "/dev/rdisk" not in source
    assert "/dev/disk" not in source
    assert "diskutil" not in source
    assert "sudo " not in source

    assert module.EXPECTED_CONFIG_DELTA == {
        b"CONFIG_ENV_SOURCE_FILE": (b'""', b'"bird-rg34xx-sp-handoff"')
    }
    assert module.REVIEWED_CANDIDATE_IDENTITIES == {
        "candidate-bytes": 556977,
        "candidate-sha256": "7423ffeda197645b6b774c83fcebcbefef47bd7eaa6f087c71ab339750af4e91",
        "candidate-fit-bytes": 516017,
        "candidate-fit-sha256": "c11d9b780c4c78940590ee17965550aa3eca7e7d0d04fdb37b4c9869b2418bf4",
        "candidate-uboot-bytes": 437168,
        "candidate-uboot-sha256": "cff9a9ca1bd7db20a3a136fec655d7120481afa8a837930266a9962ab2dec578",
        "candidate-config-sha256": "77f2bee66adc542e3475594c4727933607f76c2adf72e6428e0e57cadb6de762",
        "full-prefix-sha256": "c168640be0e3b0fc3899853d71aabc0c3b3e65fdf230b19782ff40ff19f001dd",
    }
    assert module.ENVIRONMENT == (
        b"fdt_high=ffffffffffffffff\n"
        b"initrd_high=ffffffffffffffff\n"
    )
    for build in module.BUILD_NAMES:
        for suffix in module.PASS_SUFFIXES:
            assert f"{build}{suffix}" in module.PUBLISHED


def fixture_contract(module) -> None:
    required = (BASE / "fast-init.bin", BL31, TOOLCHAIN_AUTHORITY)
    if not all(path.is_file() for path in required):
        return
    base_combined = (BASE / "fast-init.bin").read_bytes()
    base_fit = (BASE / "fast-init.itb").read_bytes()
    base_uboot = (BASE / "fast-init-uboot.bin").read_bytes()
    base_dtb = (BASE / "fast-init-control.dtb").read_bytes()
    base_spl = (BASE / "fast-init-spl.bin").read_bytes()
    base_config = (BASE / "fast-init.config").read_bytes()
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
    with tempfile.TemporaryDirectory(prefix="bird-inplace-handoff-build-test-") as temporary:
        root = pathlib.Path(temporary)
        environment = root / module.ENVIRONMENT_FILENAME
        environment.write_bytes(module.ENVIRONMENT)
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
        module.publish(
            build_a, build_b, BASE, BL31, TOOLCHAIN_AUTHORITY, environment, output
        )
        module.verify_output(output)
        authority = module.parse_authority((output / "authority.tsv").read_bytes())
        assert authority["review-state"] == module.REVIEW_STATE
        assert authority["resolved-gcc-config-delta-symbols"] == "1"
        assert authority["candidate-repeat-byte-identical"] == "yes"
        assert authority["fit-change-scope"] == "uboot-data-only"
        assert (output / "inplace-handoff.bin").read_bytes() == changed_combined
        assert (output / "base-fast-init.bin").read_bytes() == base_combined
        assert (output / "inplace-handoff-a-uboot.bin").read_bytes() == changed_uboot
        assert (output / "inplace-handoff-b-uboot.bin").read_bytes() == changed_uboot
        assert module.sha256(
            (output / "base-fast-init-prefix-16m.bin").read_bytes()
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
                environment,
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
                environment,
                root / "bad-config-output",
            ),
            "exact one-symbol in-place-handoff delta",
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
                environment,
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
                environment,
                root / "bad-spl-output",
            ),
            "altered the SPL",
        )

        bad_environment = root / "bad.env"
        bad_environment.write_bytes(module.ENVIRONMENT + b"drift=1\n")
        expect_rejected(
            lambda: module.publish(
                build_a,
                build_b,
                BASE,
                BL31,
                TOOLCHAIN_AUTHORITY,
                bad_environment,
                root / "bad-environment-output",
            ),
            "environment authority changed",
        )

        sums = output / "sha256sums.txt"
        sums.write_bytes(sums.read_bytes().replace(b"authority.tsv", b"authority.tsx"))
        expect_rejected(
            lambda: module.verify_output(output),
            "in-place-handoff checksum changed",
        )
    module.REVIEWED_CANDIDATE_IDENTITIES = reviewed


def main() -> None:
    module = load_verifier()
    static_contract(module)
    fixture_contract(module)
    print("U-Boot inplace-handoff build tests: PASS")


if __name__ == "__main__":
    main()
