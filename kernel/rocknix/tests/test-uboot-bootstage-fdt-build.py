#!/usr/bin/env python3
"""Focused host contracts for the bootstage-FDT measurement authority."""

from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
BUILDER = ROOT / "kernel/rocknix/build-uboot-bootstage-fdt.sh"
VERIFIER = ROOT / "kernel/rocknix/verify-uboot-bootstage-fdt-build.py"
TRANSFORM = ROOT / "kernel/rocknix/transform-uboot-bootstage-fdt.py"
BASE = ROOT / "kernel/work/bird-uboot-inplace-handoff-20260701"
BL31 = BASE / "bl31.bin"
TOOLCHAIN_AUTHORITY = BASE / "toolchain-authority.tsv"

TRANSFORM_SHA256 = (
    "ffc16982dcd4288070d942d8b8442dcf0fd9e588768c40c5cb48fc9fe8290743"
)
TRANSFORM_INPUT_SHA256 = (
    "0254301f87e2222f04c67a34e5351bce16ebaac712bd96cc096f76027d9ded13"
)
TRANSFORM_RESULT_SHA256 = (
    "ba2ab6692aff37a163324e34717649780099ec0ec9cb57e7941b58f286788cc9"
)
ACCEPTED_PREFIX_SHA256 = (
    "c168640be0e3b0fc3899853d71aabc0c3b3e65fdf230b19782ff40ff19f001dd"
)


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
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
        raise AssertionError("invalid bootstage-FDT authority was accepted")


def write_build(
    directory: pathlib.Path,
    combined: bytes,
    fit: bytes,
    uboot: bytes,
    dtb: bytes,
    generated_unused_spl: bytes,
    packaged_accepted_spl: bytes,
    config: bytes,
) -> None:
    directory.mkdir(parents=True)
    (directory / "u-boot-sunxi-with-spl.bin").write_bytes(combined)
    (directory / "u-boot.itb").write_bytes(fit)
    (directory / "u-boot-nodtb.bin").write_bytes(uboot)
    (directory / "u-boot.dtb").write_bytes(dtb)
    (directory / "generated-unused-spl.bin").write_bytes(generated_unused_spl)
    (directory / "packaged-accepted-spl.bin").write_bytes(packaged_accepted_spl)
    (directory / "build.config").write_bytes(config)


def config_key(line: bytes) -> bytes | None:
    if line.startswith(b"CONFIG_"):
        return line.split(b"=", 1)[0]
    if line.startswith(b"# CONFIG_") and line.endswith(b" is not set"):
        return line[2:-11]
    return None


def make_candidate_config(module, base: bytes) -> bytes:
    disabled = {
        b"CONFIG_BOOTSTAGE_REPORT",
        b"CONFIG_CMD_BOOTSTAGE",
        b"CONFIG_SPL_BOOTSTAGE",
        b"CONFIG_BOOTSTAGE_STASH",
    }
    replaced = set(module.EXPECTED_CONFIG_DELTA) | disabled
    lines = [line for line in base.splitlines() if config_key(line) not in replaced]
    lines.extend(
        (
            b"CONFIG_BOOTSTAGE=y",
            b"CONFIG_BOOTSTAGE_RECORD_COUNT=50",
            b"# CONFIG_BOOTSTAGE_REPORT is not set",
            b"CONFIG_BOOTSTAGE_FDT=y",
            b"# CONFIG_BOOTSTAGE_STASH is not set",
            b"# CONFIG_SPL_BOOTSTAGE is not set",
            b"# CONFIG_CMD_BOOTSTAGE is not set",
        )
    )
    result = b"\n".join(lines) + b"\n"
    module.verify_config_delta(base, result)
    return result


def static_contract(module, transform) -> None:
    source = BUILDER.read_text(encoding="utf-8")
    assert source.startswith("#!/bin/sh\n")
    assert "set -eu\n" in source
    assert "without" in source
    assert "adding a deployment or media-write path" in source
    assert "measurement-only" in source
    assert module.ROCKNIX_COMMIT in source
    assert TRANSFORM_SHA256 in source
    assert TRANSFORM_INPUT_SHA256 in source
    assert TRANSFORM_RESULT_SHA256 in source
    assert module.INPLACE_AUTHORITY_SHA256 in source
    assert module.INPLACE_SPL_SHA256 in source
    assert module.INPLACE_DTB_SHA256 in source
    assert module.BL31_SHA256 in source
    assert module.TOOLCHAIN_AUTHORITY_SHA256 in source
    assert module.BOOTSTAGE_TRANSFORM_SHA256 == TRANSFORM_SHA256
    assert module.BOOTSTAGE_DEFCONFIG_SHA256 == TRANSFORM_RESULT_SHA256
    assert hashlib.sha256(TRANSFORM.read_bytes()).hexdigest() == TRANSFORM_SHA256
    assert transform.SOURCE_SHA256 == TRANSFORM_INPUT_SHA256
    assert transform.RESULT_SHA256 == TRANSFORM_RESULT_SHA256
    assert "transform-uboot-environment-nowhere.py" in source
    assert "transform-uboot-direct-extlinux.py" in source
    assert "transform-uboot-no-heap-clear.py" in source
    assert "transform-uboot-fast-init.py" in source
    assert "transform-uboot-inplace-handoff.py" in source
    assert "transform-uboot-bootstage-fdt.py" in source
    assert source.count(
        '"$PYTHON" "$DIRECT_TRANSFORM" \\\n'
        '\t"$WORK/input/env.defconfig" "$WORK/input/direct.defconfig"'
    ) == 1
    assert source.count(
        '\t"$WORK/input/env.defconfig" "$WORK/input/direct.defconfig"'
    ) == 1
    assert "verify-uboot-inplace-handoff-build.py" in source
    assert "verify-uboot-bootstage-fdt-build.py" in source
    assert 'cp -fp "$BASE/inplace-handoff-spl.bin" ' in source
    assert '"$WORK/input/accepted-inplace-spl.bin"' in source
    assert (
        'require_hash "$WORK/input/accepted-inplace-spl.bin" "$INPLACE_SPL_SHA"'
        in source
    )
    assert "cp spl/sunxi-spl.bin generated-unused-spl.bin" in source
    assert (
        "cp /input/accepted-inplace-spl.bin packaged-accepted-spl.bin" in source
    )
    assert "! cmp -s generated-unused-spl.bin packaged-accepted-spl.bin" in source
    assert "cp packaged-accepted-spl.bin u-boot-sunxi-with-spl.bin" in source
    assert "cp spl/sunxi-spl.bin u-boot-sunxi-with-spl.bin" not in source
    assert "generated-unused-spl.bin packaged-accepted-spl.bin" in source
    assert "for BUILD_NAME in bootstage-fdt-a bootstage-fdt-b" in source
    assert "--network none" in source
    assert "--read-only" in source
    assert '"$WORK/input:/input:ro"' in source
    assert '"$TOOLCHAIN:$CONTAINER_TOOLCHAIN:ro"' in source
    assert "export CCACHE_DISABLE=1" in source
    for line in (
        "CONFIG_BOOTSTAGE=y",
        "CONFIG_BOOTSTAGE_FDT=y",
        "CONFIG_BOOTSTAGE_RECORD_COUNT=50",
        "# CONFIG_BOOTSTAGE_REPORT is not set",
        "# CONFIG_CMD_BOOTSTAGE is not set",
        "# CONFIG_SPL_BOOTSTAGE is not set",
        "# CONFIG_BOOTSTAGE_STASH is not set",
    ):
        assert f'grep -Fqx "{line}"' in source
    assert 'CONFIG_ENV_SOURCE_FILE="bird-rg34xx-sp-handoff"' in source
    assert "patch-fit-root-timestamp.py u-boot.itb" in source
    assert "tools/mkimage -F" not in source
    for forbidden in (
        "/dev/rdisk",
        "/dev/disk",
        "/Volumes/",
        "diskutil",
        "sudo ",
        "mac-install-bird-uboot",
    ):
        assert forbidden not in source, forbidden

    assert module.BUILD_NAMES == ("bootstage-fdt-a", "bootstage-fdt-b")
    assert module.SCHEMA == "bird-uboot-bootstage-fdt-authority-v2"
    assert module.TWO_PASS_SCHEMA == "bird-uboot-bootstage-fdt-two-pass-v2"
    assert module.PUBLICATION == "measurement-only"
    assert module.DEPLOYMENT_AUTHORITY == "no"
    assert module.REVIEW_STATE == "candidate-hashes-pending"
    assert module.REVIEWED_CANDIDATE_IDENTITIES == {
        "candidate-bytes": 561073,
        "candidate-sha256": (
            "0b22418db35ee591870ccd652d4aaa3d0a50bd216e600f7b8ca0c4052e2e8e83"
        ),
        "candidate-fit-bytes": 520113,
        "candidate-fit-sha256": (
            "5aa07ccfd8483a274d5dfc03815744db5ff57112728b79ad70c30a54e20bb129"
        ),
        "candidate-uboot-bytes": 441264,
        "candidate-uboot-sha256": (
            "a30040f3c134303dc66d06babec4df9c8e8aa70ef5e59832993fbf7f721b39a5"
        ),
        "candidate-config-sha256": (
            "a0ce37450f93265ef98d5997b4990ac819f9e89887d741f53fbfea7387158a86"
        ),
        "generated-unused-spl-bytes": 40960,
        "generated-unused-spl-sha256": (
            "74f924e5fea4043aae52134bbca44623d7a126d5b35b8fb1a3208dfc0938c9e1"
        ),
        "packaged-accepted-spl-bytes": 40960,
        "packaged-accepted-spl-sha256": (
            "0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c"
        ),
        "full-prefix-sha256": (
            "c1dadb6b43782ac25b8be6ea168cbad7c2e435da49207210213be68701f7f94b"
        ),
    }
    assert module.EXPECTED_CONFIG_DELTA == {
        b"CONFIG_BOOTSTAGE": (b"n", b"y"),
        b"CONFIG_BOOTSTAGE_FDT": (b"n", b"y"),
        b"CONFIG_BOOTSTAGE_RECORD_COUNT": (b"n", b"50"),
    }
    assert module.ACCEPTED_PREFIX_SHA256 == ACCEPTED_PREFIX_SHA256
    assert module.ENVIRONMENT == (
        b"fdt_high=ffffffffffffffff\n"
        b"initrd_high=ffffffffffffffff\n"
    )
    for build_name in module.BUILD_NAMES:
        for suffix in module.PASS_SUFFIXES:
            assert f"{build_name}{suffix}" in module.PUBLISHED
    assert "bootstage-fdt-generated-unused-spl.bin" in module.PUBLISHED
    assert "bootstage-fdt-packaged-accepted-spl.bin" in module.PUBLISHED
    assert "bootstage-fdt-spl.bin" not in module.PUBLISHED


def fixture_contract(module) -> None:
    required = (BASE / "inplace-handoff.bin", BL31, TOOLCHAIN_AUTHORITY)
    if not all(path.is_file() for path in required):
        return

    base_combined = (BASE / "inplace-handoff.bin").read_bytes()
    base_fit = (BASE / "inplace-handoff.itb").read_bytes()
    base_uboot = (BASE / "inplace-handoff-uboot.bin").read_bytes()
    base_dtb = (BASE / "inplace-handoff-control.dtb").read_bytes()
    base_spl = (BASE / "inplace-handoff-spl.bin").read_bytes()
    base_config = (BASE / "inplace-handoff.config").read_bytes()
    base_environment = (BASE / module.ENVIRONMENT_FILENAME).read_bytes()
    assert (
        module.sha256((BASE / "authority.tsv").read_bytes())
        == module.INPLACE_AUTHORITY_SHA256
    )
    assert module.sha256(base_combined) == module.INPLACE_COMBINED_SHA256
    assert module.sha256(base_fit) == module.INPLACE_FIT_SHA256
    assert module.sha256(base_uboot) == module.INPLACE_UBOOT_SHA256
    assert module.sha256(base_spl) == module.INPLACE_SPL_SHA256
    assert module.sha256(base_dtb) == module.INPLACE_DTB_SHA256
    assert module.sha256(BL31.read_bytes()) == module.BL31_SHA256
    assert base_environment == module.ENVIRONMENT
    assert module.sha256(base_environment) == module.ENVIRONMENT_SHA256

    changed_uboot = bytearray(base_uboot)
    changed_uboot[100] ^= 1
    changed_uboot = bytes(changed_uboot)
    offset = base_fit.find(base_uboot)
    assert offset >= 0 and base_fit.find(base_uboot, offset + 1) == -1
    changed_fit = bytearray(base_fit)
    changed_fit[offset + 100] ^= 1
    changed_fit = bytes(changed_fit)
    changed_combined = base_combined[: module.SPL_REGION_BYTES] + changed_fit
    generated_spl = bytearray(base_spl)
    generated_spl[-1] ^= 1
    generated_spl = bytes(generated_spl)
    assert generated_spl != base_spl
    changed_config = make_candidate_config(module, base_config)
    resolved = module.config_map(changed_config)
    assert {
        key: resolved.get(key, b"n")
        for key in (
            b"CONFIG_BOOTSTAGE_REPORT",
            b"CONFIG_CMD_BOOTSTAGE",
            b"CONFIG_SPL_BOOTSTAGE",
            b"CONFIG_BOOTSTAGE_STASH",
        )
    } == {
        b"CONFIG_BOOTSTAGE_REPORT": b"n",
        b"CONFIG_CMD_BOOTSTAGE": b"n",
        b"CONFIG_SPL_BOOTSTAGE": b"n",
        b"CONFIG_BOOTSTAGE_STASH": b"n",
    }

    reviewed = module.REVIEWED_CANDIDATE_IDENTITIES
    module.REVIEWED_CANDIDATE_IDENTITIES = {}
    try:
        with tempfile.TemporaryDirectory(
            prefix="bird-bootstage-fdt-build-test-"
        ) as temporary:
            root = pathlib.Path(temporary)
            build_a, build_b = root / "a", root / "b"
            for build in (build_a, build_b):
                write_build(
                    build,
                    changed_combined,
                    changed_fit,
                    changed_uboot,
                    base_dtb,
                    generated_spl,
                    base_spl,
                    changed_config,
                )
            output = root / "authority"
            module.publish(
                build_a, build_b, BASE, BL31, TOOLCHAIN_AUTHORITY, output
            )
            module.verify_output(output)
            authority = module.parse_authority(
                (output / "authority.tsv").read_bytes()
            )
            assert authority["review-state"] == "candidate-hashes-pending"
            assert authority["publication"] == "measurement-only"
            assert authority["measurement-only"] == "yes"
            assert authority["deployment-authority"] == "no"
            assert authority["accepted-inplace-prefix-sha256"] == (
                ACCEPTED_PREFIX_SHA256
            )
            assert authority["resolved-gcc-config-delta-symbols"] == "3"
            assert authority["bootstage-built"] == "yes"
            assert authority["bootstage-fdt-built"] == "yes"
            assert authority["bootstage-record-count"] == "50"
            assert authority["candidate-repeat-byte-identical"] == "yes"
            assert authority["fit-change-scope"] == "uboot-data-only"
            assert authority["environment-byte-identical-to-base"] == "yes"
            assert authority["packaged-spl-source"] == "accepted-inplace-exact"
            assert authority["generated-spl-role"] == "build-evidence-unused"
            assert authority["generated-spl-difference-reason"] == (
                "raw-CONFIG_BOOTSTAGE-adds-gd-bootstage-shifts-cyclic_list"
            )
            assert authority["packaged-spl-byte-identical-to-base"] == "yes"
            assert authority["generated-spl-byte-identical-to-packaged"] == "no"
            assert authority["generated-spl-repeat-byte-identical"] == "yes"
            assert authority["packaged-spl-repeat-byte-identical"] == "yes"
            assert authority["generated-spl-used-in-combined"] == "no"
            assert authority["packaged-spl-used-in-combined"] == "yes"
            assert authority["generated-unused-spl-bytes"] == str(len(generated_spl))
            assert authority["generated-unused-spl-sha256"] == module.sha256(
                generated_spl
            )
            assert authority["packaged-accepted-spl-bytes"] == str(len(base_spl))
            assert authority["packaged-accepted-spl-sha256"] == (
                module.INPLACE_SPL_SHA256
            )
            assert authority["combined-spl-region-bytes"] == "40960"
            assert authority["combined-layout"] == (
                "accepted-spl-zero-pad-40960-plus-candidate-fit"
            )
            assert authority["control-fdt-byte-identical-to-base"] == "yes"
            assert authority["bl31-byte-identical-to-base"] == "yes"
            for key in (
                "bootstage-report-built",
                "bootstage-command-built",
                "spl-bootstage-built",
                "bootstage-stash-built",
                "spl-to-uboot-bootstage-handoff",
            ):
                assert authority[key] == "no"
            assert (output / "bootstage-fdt.bin").read_bytes() == changed_combined
            assert (output / "inplace-base-combined.bin").read_bytes() == base_combined
            assert (output / "bootstage-fdt-a-uboot.bin").read_bytes() == changed_uboot
            assert (output / "bootstage-fdt-b-uboot.bin").read_bytes() == changed_uboot
            assert (
                output / "bootstage-fdt-generated-unused-spl.bin"
            ).read_bytes() == generated_spl
            assert (
                output / "bootstage-fdt-packaged-accepted-spl.bin"
            ).read_bytes() == base_spl
            assert (output / "bootstage-fdt-control.dtb").read_bytes() == base_dtb
            assert (output / "bl31.bin").read_bytes() == BL31.read_bytes()
            assert (output / module.ENVIRONMENT_FILENAME).read_bytes() == module.ENVIRONMENT
            accepted_prefix = (
                output / "accepted-inplace-prefix-16m.bin"
            ).read_bytes()
            assert module.sha256(accepted_prefix) == ACCEPTED_PREFIX_SHA256
            expected_candidate_prefix = bytearray(accepted_prefix)
            start = module.RAW_OFFSET
            expected_candidate_prefix[start:start + len(changed_combined)] = (
                changed_combined
            )
            assert (output / "bootstage-fdt-prefix-16m.bin").read_bytes() == bytes(
                expected_candidate_prefix
            )

            bad_b = root / "bad-b"
            write_build(
                bad_b,
                changed_combined,
                changed_fit,
                changed_uboot,
                base_dtb,
                generated_spl,
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

            generated_mismatch = bytearray(generated_spl)
            generated_mismatch[-2] ^= 1
            generated_mismatch_build = root / "generated-mismatch"
            write_build(
                generated_mismatch_build,
                changed_combined,
                changed_fit,
                changed_uboot,
                base_dtb,
                bytes(generated_mismatch),
                base_spl,
                changed_config,
            )
            expect_rejected(
                lambda: module.publish(
                    build_a,
                    generated_mismatch_build,
                    BASE,
                    BL31,
                    TOOLCHAIN_AUTHORITY,
                    root / "generated-mismatch-output",
                ),
                "not reproducible: generated-unused-spl.bin differs",
            )

            missing_generated_build = root / "missing-generated"
            write_build(
                missing_generated_build,
                changed_combined,
                changed_fit,
                changed_uboot,
                base_dtb,
                generated_spl,
                base_spl,
                changed_config,
            )
            (missing_generated_build / "generated-unused-spl.bin").unlink()
            expect_rejected(
                lambda: module.publish(
                    missing_generated_build,
                    missing_generated_build,
                    BASE,
                    BL31,
                    TOOLCHAIN_AUTHORITY,
                    root / "missing-generated-output",
                ),
                "unsafe or missing artifact",
            )

            generated_used_build = root / "generated-used"
            write_build(
                generated_used_build,
                generated_spl + changed_fit,
                changed_fit,
                changed_uboot,
                base_dtb,
                generated_spl,
                base_spl,
                changed_config,
            )
            expect_rejected(
                lambda: module.publish(
                    generated_used_build,
                    generated_used_build,
                    BASE,
                    BL31,
                    TOOLCHAIN_AUTHORITY,
                    root / "generated-used-output",
                ),
                "combined image does not begin with its SPL",
            )

            missing_expected_drift_build = root / "missing-expected-drift"
            write_build(
                missing_expected_drift_build,
                changed_combined,
                changed_fit,
                changed_uboot,
                base_dtb,
                base_spl,
                base_spl,
                changed_config,
            )
            expect_rejected(
                lambda: module.publish(
                    missing_expected_drift_build,
                    missing_expected_drift_build,
                    BASE,
                    BL31,
                    TOOLCHAIN_AUTHORITY,
                    root / "missing-expected-drift-output",
                ),
                "generated-unused SPL did not retain the expected drift",
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
                generated_spl,
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
                "exact bootstage-FDT delta",
            )

            for symbol in (b"CONFIG_SPL_BOOTSTAGE", b"CONFIG_BOOTSTAGE_STASH"):
                disabled_line = b"# " + symbol + b" is not set\n"
                enabled_line = symbol + b"=y\n"
                forbidden_config = changed_config.replace(
                    disabled_line, enabled_line
                )
                assert forbidden_config != changed_config
                forbidden_build = root / ("bad-" + symbol.decode().lower())
                write_build(
                    forbidden_build,
                    changed_combined,
                    changed_fit,
                    changed_uboot,
                    base_dtb,
                    generated_spl,
                    base_spl,
                    forbidden_config,
                )
                expect_rejected(
                    lambda build=forbidden_build, name=symbol.decode(): module.publish(
                        build,
                        build,
                        BASE,
                        BL31,
                        TOOLCHAIN_AUTHORITY,
                        root / ("bad-" + name.lower() + "-output"),
                    ),
                    "exact bootstage-FDT delta",
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
                generated_spl,
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
            bad_spl_build = root / "bad-spl"
            write_build(
                bad_spl_build,
                bad_spl + changed_combined[len(bad_spl):],
                changed_fit,
                changed_uboot,
                base_dtb,
                generated_spl,
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
                "packaged SPL is not the exact accepted SPL",
            )

            bad_dtb = bytearray(base_dtb)
            bad_dtb[-1] ^= 1
            bad_dtb_build = root / "bad-dtb"
            write_build(
                bad_dtb_build,
                changed_combined,
                changed_fit,
                changed_uboot,
                bytes(bad_dtb),
                generated_spl,
                base_spl,
                changed_config,
            )
            expect_rejected(
                lambda: module.publish(
                    bad_dtb_build,
                    bad_dtb_build,
                    BASE,
                    BL31,
                    TOOLCHAIN_AUTHORITY,
                    root / "bad-dtb-output",
                ),
                "altered the control FDT",
            )

            bad_bl31 = root / "bad-bl31.bin"
            changed_bl31 = bytearray(BL31.read_bytes())
            changed_bl31[-1] ^= 1
            bad_bl31.write_bytes(changed_bl31)
            expect_rejected(
                lambda: module.publish(
                    build_a,
                    build_b,
                    BASE,
                    bad_bl31,
                    TOOLCHAIN_AUTHORITY,
                    root / "bad-bl31-output",
                ),
                "BL31",
            )

            generated_evidence_path = (
                output / "bootstage-fdt-generated-unused-spl.bin"
            )
            generated_evidence = generated_evidence_path.read_bytes()
            tampered_generated_evidence = bytearray(generated_evidence)
            tampered_generated_evidence[-1] ^= 1
            generated_evidence_path.write_bytes(tampered_generated_evidence)
            expect_rejected(
                lambda: module.verify_output(output),
                "checksum changed: bootstage-fdt-generated-unused-spl.bin",
            )
            generated_evidence_path.write_bytes(generated_evidence)
            module.verify_output(output)

            authority_path = output / "authority.tsv"
            authority_data = bytearray(authority_path.read_bytes())
            authority_data[0] ^= 1
            authority_path.write_bytes(authority_data)
            expect_rejected(
                lambda: module.verify_output(output),
                "checksum changed",
            )
    finally:
        module.REVIEWED_CANDIDATE_IDENTITIES = reviewed


def main() -> None:
    module = load("bird_bootstage_fdt_verifier", VERIFIER)
    transform = load("bird_bootstage_fdt_transform", TRANSFORM)
    static_contract(module, transform)
    fixture_contract(module)
    print("U-Boot bootstage-FDT build tests: PASS")


if __name__ == "__main__":
    main()
