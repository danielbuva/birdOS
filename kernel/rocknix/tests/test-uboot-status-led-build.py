#!/usr/bin/env python3
"""Host contracts for the non-deploying Stage 10 U-Boot builder."""

from __future__ import annotations

import importlib.util
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
BUILDER = ROOT / "kernel/rocknix/build-uboot-status-led.sh"
VERIFIER = ROOT / "kernel/rocknix/verify-uboot-status-led-build.py"
ORACLE = (
    ROOT
    / "kernel/work/rocknix-system-exact-20260701/usr/share/bootloader"
    / "H700_DDR4_u-boot-sunxi-with-spl.bin"
)
ORACLE_BL31 = ORACLE.with_name("bl31.bin")


def load_verifier():
    spec = importlib.util.spec_from_file_location("bird_uboot_verifier", VERIFIER)
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
        raise AssertionError("invalid U-Boot authority was accepted")


def write_build(
    root: pathlib.Path,
    combined: bytes,
    fit: bytes,
    uboot: bytes,
    control_fdt: bytes,
    spl: bytes,
    config: bytes,
) -> None:
    (root / "spl").mkdir(parents=True)
    (root / "u-boot-sunxi-with-spl.bin").write_bytes(combined)
    (root / "u-boot.itb").write_bytes(fit)
    (root / "u-boot-nodtb.bin").write_bytes(uboot)
    (root / "u-boot.dtb").write_bytes(control_fdt)
    (root / "spl/sunxi-spl.bin").write_bytes(spl)
    (root / "build.config").write_bytes(config)


def fake_toolchain_authority(module) -> str:
    digest = "1" * 64
    tools = [
        f"bin/{module.TARGET_TRIPLET}-{suffix}"
        for suffix in (
            "gcc",
            "gcc-15.2.0",
            "ld",
            "as",
            "ar",
            "nm",
            "strip",
            "objcopy",
            "objdump",
            "readelf",
        )
    ] + [
        "bin/ccache",
        "bin/host-gcc",
        "bin/host-g++",
        "bin/make",
        "bin/python",
        "bin/python3",
    ]
    lines = [
        f"schema\t{module.TOOLCHAIN_SCHEMA}",
        f"docker-image\t{module.DOCKER_IMAGE}",
        f"target-triplet\t{module.TARGET_TRIPLET}",
        "gcc-version\t15.2.0",
        f"gcc-package-path\t{module.GCC_PACKAGE_PATH}",
        f"gcc-package-sha256\t{module.GCC_PACKAGE_SHA256}",
        f"gcc-source-sha256\t{module.GCC_SOURCE_SHA256}",
        "uboot-lto\tdisabled",
        f"cross-compiler-invocation\tbin/ccache\tbin/{module.TARGET_TRIPLET}-gcc-15.2.0",
        "host-compiler-invocation\tbin/ccache\t/usr/bin/gcc",
        "host-cxx-wrapper-authority\tbin/host-g++\tbin/ccache\t/usr/bin/g++",
        f"host-compiler-resolved\t/usr/bin/gcc-actual\t{digest}",
        f"host-cxx-resolved\t/usr/bin/g++-actual\t{digest}",
    ]
    for tool in tools:
        lines.append(f"tool-entry-file\t{tool}\t{digest}")
        lines.append(f"tool-resolved\t{tool}\t{tool}\t{digest}")
    lines.extend(
        (
            f"compiler-internal-file\tcc1\tlibexec/gcc/cc1\t{digest}",
            f"compiler-internal-file\tlibgcc\tlib/gcc/libgcc.a\t{digest}",
            f"compiler-internal-tree\tinclude\tlib/gcc/include\t32\t4096\t{digest}\tno-symlinks-special-nodes",
        )
    )
    return "\n".join(lines) + "\n"


def test_static_contract(module) -> None:
    source = BUILDER.read_text(encoding="utf-8")
    assert source.startswith("#!/bin/sh\n")
    assert "set -eu\n" in source
    assert module.ROCKNIX_COMMIT in source
    assert module.SOURCE_TARBALL_SHA256 in source
    assert module.PACKAGE_MK_SHA256 in source
    assert module.PACKAGE_PATCH_SHA256 in source
    assert module.GCC_PACKAGE_SHA256 in source
    assert module.GCC_SOURCE_SHA256 in source
    assert module.UPSTREAM_DEFCONFIG_SHA256 in source
    assert module.GREEN_DEFCONFIG_SHA256 in source
    assert module.SHIPPING_COMBINED_SHA256 in source
    assert module.BL31_SHA256 in source
    assert module.DOCKER_IMAGE in source
    assert f"SOURCE_DATE_EPOCH={module.SOURCE_DATE_EPOCH}\n" in source
    assert "FIT_TIMESTAMP_PATCHER=" in source
    assert 'require_file "$FIT_TIMESTAMP_PATCHER"' in source
    assert 'cp -fp "$FIT_TIMESTAMP_PATCHER"' in source
    assert (
        "python3 /input/patch-fit-root-timestamp.py "
        "u-boot.itb 1782880730 1782880744"
    ) in source
    assert "tools/mkimage -F -t u-boot.itb" not in source
    assert 'test "$(wc -c < u-boot-sunxi-with-spl.bin)" -gt 40960' in source
    assert (
        "dd if=u-boot-sunxi-with-spl.bin of=u-boot.itb "
        "bs=40960 skip=1 status=none"
    ) in source
    assert "cp spl/sunxi-spl.bin u-boot-sunxi-with-spl.bin" in source
    assert "truncate -s 40960 u-boot-sunxi-with-spl.bin" in source
    assert "cat u-boot.itb >> u-boot-sunxi-with-spl.bin" in source
    assert "--network none" in source
    assert "--read-only" in source
    assert '"$TOOLCHAIN:$CONTAINER_TOOLCHAIN:ro"' in source
    assert '"$WORK/input:/input:ro"' in source
    assert "export CCACHE_DISABLE=1" in source
    assert "export HOME=/tmp/home" in source
    assert "-dumpfullversion -dumpversion" in source
    assert '"$TOOLCHAIN_VERSION" = 15.2.0' in source
    assert "toolchain input resolves outside its read-only tree" in source
    wrong_target = "".join(("aarch64", "-", "none", "-", "elf"))
    assert wrong_target not in source
    assert source.count("aarch64-rocknix-linux-gnu-gcc-15.2.0") >= 3
    for suffix in ("ld", "as", "ar", "nm", "strip", "objcopy", "objdump", "readelf"):
        assert f"bin/aarch64-rocknix-linux-gnu-{suffix}" in source
    assert source.count("bin/ccache") >= 4
    assert "bin/host-g++" in source
    assert "bin/python" in source
    assert "EXPECTED_CROSS_WRAPPER=" in source
    assert "EXPECTED_HOST_WRAPPER=" in source
    assert "cross-compiler-invocation\\tbin/ccache" in source
    assert "host-compiler-invocation\\tbin/ccache" in source
    assert "host-cxx-wrapper-authority\\tbin/host-g++" in source
    assert "compiler-internal-file\\tcc1" in source
    assert "compiler-internal-file\\tlibgcc" in source
    assert "compiler-internal-tree\\tinclude" in source
    assert 'grep -Fqx "# CONFIG_LTO is not set" .config' in source
    assert "tool-entry-symlink\\t%s\\t%s" in source
    assert "tool-entry-file\\t%s\\t%s" in source
    assert "tool-resolved\\t%s\\t%s\\t%s" in source
    assert "baseline-a baseline-b green-a green-b" in source
    assert "verify-uboot-status-led-build.py" in source

    verifier_source = VERIFIER.read_text(encoding="utf-8")
    assert "four-pass-inventory.tsv" in verifier_source
    for build_name in module.BUILD_NAMES:
        assert f'"{build_name}-combined.bin"' in verifier_source
        assert f'"{build_name}.config"' in verifier_source

    # This builder cannot address or mutate removable media. The only dd-like
    # text is inside hashes/words, never an executable deployment operation.
    forbidden = ("sudo ", "diskutil", "/dev/rdisk", "/dev/disk", " dd ")
    for needle in forbidden:
        assert needle not in source, needle


def test_shipping_fixture(module) -> None:
    if not ORACLE.is_file() or not ORACLE_BL31.is_file():
        return
    shipping = ORACLE.read_bytes()
    bl31 = ORACLE_BL31.read_bytes()
    assert len(shipping) == module.COMBINED_BYTES
    assert module.sha256(shipping) == module.SHIPPING_COMBINED_SHA256
    assert len(bl31) == module.BL31_BYTES
    assert module.sha256(bl31) == module.BL31_SHA256

    spl = shipping[: module.SPL_REGION_BYTES]
    fit = shipping[module.SPL_REGION_BYTES :]
    properties = module.parse_fit(fit)
    uboot = properties["/images/uboot"]["data"]
    control_fdt = properties["/images/fdt-1"]["data"]
    module.verify_combined(shipping, spl, fit)
    module.verify_fit(fit, uboot, bl31, control_fdt)

    # Model a deterministic one-byte U-Boot code change. Updating the matching
    # FIT data proves that the publisher checks internal component binding,
    # while the unchanged SPL, BL31 and control FDT prove its parity gates.
    changed_uboot = bytearray(uboot)
    changed_uboot[100] ^= 1
    changed_uboot = bytes(changed_uboot)
    uboot_offset = fit.find(uboot)
    assert uboot_offset >= 0
    assert fit.find(uboot, uboot_offset + 1) == -1
    changed_fit = bytearray(fit)
    changed_fit[uboot_offset + 100] ^= 1
    changed_fit = bytes(changed_fit)
    changed_combined = spl + changed_fit
    baseline_config = b"# CONFIG_LTO is not set\nCONFIG_LED_STATUS_BIT=267\n"
    green_config = baseline_config.replace(b"=267\n", b"=268\n")
    module.verify_build_configs(baseline_config, green_config)
    module.verify_fit(changed_fit, changed_uboot, bl31, control_fdt)
    baseline_scope = {
        "u-boot-nodtb.bin": uboot,
        "u-boot.itb": fit,
    }
    green_scope = {
        "u-boot-nodtb.bin": changed_uboot,
        "u-boot.itb": changed_fit,
    }
    module.verify_green_scope(baseline_scope, green_scope)
    out_of_scope_fit = bytearray(changed_fit)
    description_offset = changed_fit.find(b"Configuration to load")
    assert description_offset >= 0
    out_of_scope_fit[description_offset] ^= 1
    expect_rejected(
        lambda: module.verify_green_scope(
            baseline_scope,
            green_scope | {"u-boot.itb": bytes(out_of_scope_fit)},
        ),
        "altered bytes outside the FIT U-Boot payload",
    )

    with tempfile.TemporaryDirectory(prefix="bird-uboot-build-test-") as directory:
        temporary = pathlib.Path(directory)
        baseline_a = temporary / "baseline-a"
        baseline_b = temporary / "baseline-b"
        green_a = temporary / "green-a"
        green_b = temporary / "green-b"
        for path in (baseline_a, baseline_b):
            write_build(
                path, shipping, fit, uboot, control_fdt, spl, baseline_config
            )
        for path in (green_a, green_b):
            write_build(
                path,
                changed_combined,
                changed_fit,
                changed_uboot,
                control_fdt,
                spl,
                green_config,
            )
        toolchain = temporary / "toolchain.tsv"
        toolchain.write_text(fake_toolchain_authority(module), encoding="utf-8")
        output = temporary / "published"
        module.publish(
            baseline_a,
            baseline_b,
            green_a,
            green_b,
            ORACLE,
            ORACLE_BL31,
            toolchain,
            output,
        )
        assert (output / "rocknix-baseline.bin").read_bytes() == shipping
        assert (output / "bird-uboot-green.bin").read_bytes() == changed_combined
        for build_name in ("baseline-a", "baseline-b"):
            assert (output / f"{build_name}-combined.bin").read_bytes() == shipping
            assert (output / f"{build_name}.config").read_bytes() == baseline_config
        for build_name in ("green-a", "green-b"):
            assert (output / f"{build_name}-combined.bin").read_bytes() == changed_combined
            assert (output / f"{build_name}.config").read_bytes() == green_config
        inventory = (output / "four-pass-inventory.tsv").read_text(
            encoding="ascii"
        ).splitlines()
        assert inventory[0] == f"schema\t{module.FOUR_PASS_SCHEMA}"
        assert len(inventory) == 1 + len(module.BUILD_NAMES) * len(
            module.REQUIRED_ARTIFACTS
        )
        expected_keys = [
            (build_name, artifact_name)
            for build_name in module.BUILD_NAMES
            for artifact_name in module.REQUIRED_ARTIFACTS
        ]
        for line, expected_key in zip(inventory[1:], expected_keys):
            record, build_name, artifact_name, size, digest = line.split("\t")
            assert (record, build_name, artifact_name) == ("artifact", *expected_key)
            built = {
                "baseline-a": baseline_a,
                "baseline-b": baseline_b,
                "green-a": green_a,
                "green-b": green_b,
            }[build_name] / artifact_name
            data = built.read_bytes()
            assert size == str(len(data))
            assert digest == module.sha256(data)
        authority = dict(
            line.split("\t", 1)
            for line in (output / "authority.tsv").read_text().splitlines()
        )
        assert authority["schema"] == module.SCHEMA
        assert authority["raw-offset"] == str(module.RAW_OFFSET)
        assert authority["baseline-sha256"] == module.SHIPPING_COMBINED_SHA256
        assert authority["candidate-sha256"] == module.sha256(changed_combined)
        assert authority["shipping-baseline-byte-identical"] == "yes"
        assert authority["spl-byte-identical"] == "yes"
        assert authority["bl31-byte-identical"] == "yes"
        assert authority["control-fdt-byte-identical"] == "yes"

        changed_baseline = bytearray(shipping)
        changed_baseline[100] ^= 1
        (baseline_a / "u-boot-sunxi-with-spl.bin").write_bytes(changed_baseline)
        changed_spl = bytearray(spl)
        changed_spl[100] ^= 1
        (baseline_a / "spl/sunxi-spl.bin").write_bytes(changed_spl)
        expect_rejected(
            lambda: module.publish(
                baseline_a,
                baseline_b,
                green_a,
                green_b,
                ORACLE,
                ORACLE_BL31,
                toolchain,
                temporary / "rejected",
            ),
            "baseline build is not reproducible",
        )

    expect_rejected(
        lambda: module.parse_fit(fit[:-1]),
        "FIT size is not exact",
    )
    expect_rejected(
        lambda: module.verify_combined(shipping[:-1], spl, fit),
        "combined U-Boot size changed",
    )


def main() -> None:
    module = load_verifier()
    test_static_contract(module)
    test_shipping_fixture(module)
    print("U-Boot status LED build tests: PASS")


if __name__ == "__main__":
    main()
