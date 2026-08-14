#!/usr/bin/env python3
"""Verify and publish the RG34XX-SP bootstage-FDT measurement build.

Why before: the physically accepted in-place handoff authority deliberately
contained no timing instrumentation, and the first measurement verifier
assumed SPL_BOOTSTAGE=n made the generated SPL byte-identical to that base.
Why change: raw CONFIG_BOOTSTAGE adds gd->bootstage and shifts cyclic_list in
the generated SPL. This host-only verifier packages the exact accepted SPL,
retains the reproducible generated-but-unused SPL as evidence, and seals an
exact three-symbol full-U-Boot diagnostic delta.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import struct


ROOT = pathlib.Path(__file__).resolve().parents[2]
INPLACE_VERIFIER_PATH = ROOT / "kernel/rocknix/verify-uboot-inplace-handoff-build.py"
STATUS_VERIFIER_PATH = ROOT / "kernel/rocknix/verify-uboot-status-led-build.py"

SCHEMA = "bird-uboot-bootstage-fdt-authority-v2"
TWO_PASS_SCHEMA = "bird-uboot-bootstage-fdt-two-pass-v2"
PUBLICATION = "measurement-only"
DEPLOYMENT_AUTHORITY = "no"
REVIEW_STATE = "candidate-hashes-pending"
ROCKNIX_RELEASE = "20260701"
ROCKNIX_COMMIT = "3e4ee5852e6ca5ea73a38369d2639fad2262648b"
UBOOT_VERSION = "v2026.01"
DEFCONFIG_NAME = "anbernic_rg35xx_h700_lpddr4_defconfig"
BOOTSTAGE_TRANSFORM_SHA256 = (
    "ffc16982dcd4288070d942d8b8442dcf0fd9e588768c40c5cb48fc9fe8290743"
)
BOOTSTAGE_DEFCONFIG_SHA256 = (
    "ba2ab6692aff37a163324e34717649780099ec0ec9cb57e7941b58f286788cc9"
)
INPLACE_AUTHORITY_SHA256 = (
    "bc6296164aab24516b11ed77ee7f9f992932a9a55d3e17b1abf7d8681ec5ba33"
)
INPLACE_COMBINED_SHA256 = (
    "7423ffeda197645b6b774c83fcebcbefef47bd7eaa6f087c71ab339750af4e91"
)
INPLACE_FIT_SHA256 = (
    "c11d9b780c4c78940590ee17965550aa3eca7e7d0d04fdb37b4c9869b2418bf4"
)
INPLACE_UBOOT_SHA256 = (
    "cff9a9ca1bd7db20a3a136fec655d7120481afa8a837930266a9962ab2dec578"
)
INPLACE_CONFIG_SHA256 = (
    "77f2bee66adc542e3475594c4727933607f76c2adf72e6428e0e57cadb6de762"
)
INPLACE_SPL_SHA256 = (
    "0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c"
)
INPLACE_DTB_SHA256 = (
    "ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589"
)
ACCEPTED_PREFIX_SHA256 = (
    "c168640be0e3b0fc3899853d71aabc0c3b3e65fdf230b19782ff40ff19f001dd"
)
BL31_SHA256 = "431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673"
TOOLCHAIN_AUTHORITY_SHA256 = (
    "78ce9836240e264c933dac577348a01c56f2d8359d084439aa9aab6204733631"
)
ENVIRONMENT_FILENAME = "bird-rg34xx-sp-handoff.env"
ENVIRONMENT_SHA256 = (
    "335b569a6f63acab13d20bccb843b5d6d979b7141ede3a5a5a2647b59ec132ce"
)
ENVIRONMENT = (
    b"fdt_high=ffffffffffffffff\n"
    b"initrd_high=ffffffffffffffff\n"
)
RAW_OFFSET = 8192
SPL_REGION_BYTES = 40960
PREFIX_BYTES = 16 * 1024 * 1024

EXPECTED_CONFIG_DELTA: dict[bytes, tuple[bytes, bytes]] = {
    b"CONFIG_BOOTSTAGE": (b"n", b"y"),
    b"CONFIG_BOOTSTAGE_FDT": (b"n", b"y"),
    b"CONFIG_BOOTSTAGE_RECORD_COUNT": (b"n", b"50"),
}
if len(EXPECTED_CONFIG_DELTA) != 3:
    raise RuntimeError("bootstage-FDT config authority is not three symbols")

# The exact two-pass artifact received an independent binary/FIT/prefix review.
# Review does not make it deployable: publication remains measurement-only and
# deployment-authority remains no.
REVIEWED_CANDIDATE_IDENTITIES: dict[str, str | int] = {
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

REQUIRED_ARTIFACTS = (
    "u-boot-sunxi-with-spl.bin",
    "u-boot.itb",
    "u-boot-nodtb.bin",
    "u-boot.dtb",
    "generated-unused-spl.bin",
    "packaged-accepted-spl.bin",
    "build.config",
)
BUILD_NAMES = ("bootstage-fdt-a", "bootstage-fdt-b")
PASS_SUFFIXES = (
    "-combined.bin",
    ".itb",
    "-uboot.bin",
    "-control.dtb",
    "-generated-unused-spl.bin",
    "-packaged-accepted-spl.bin",
    ".config",
)
PUBLISHED = (
    "accepted-inplace-prefix-16m.bin",
    "authority.tsv",
    "bird-rg34xx-sp-handoff.env",
    "bird-uboot-bootstage-fdt.bin",
    "bl31.bin",
    "bootstage-fdt-prefix-16m.bin",
    "bootstage-fdt.bin",
    "bootstage-fdt.itb",
    "bootstage-fdt-uboot.bin",
    "bootstage-fdt-control.dtb",
    "bootstage-fdt-generated-unused-spl.bin",
    "bootstage-fdt-packaged-accepted-spl.bin",
    "bootstage-fdt.config",
    "inplace-base-authority.tsv",
    "inplace-base-combined.bin",
    "inplace-base.itb",
    "inplace-base-uboot.bin",
    "inplace-base-control.dtb",
    "inplace-base-spl.bin",
    "inplace-base.config",
    *(f"{build}{suffix}" for build in BUILD_NAMES for suffix in PASS_SUFFIXES),
    "sha256sums.txt",
    "toolchain-authority.tsv",
    "two-pass-inventory.tsv",
)


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_bytes(path: pathlib.Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail(f"unsafe or missing artifact: {path}")
    return path.read_bytes()


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        fail(f"could not load {name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def inplace_verifier():
    return load_module("bird_inplace_verifier_bootstage", INPLACE_VERIFIER_PATH)


def status_verifier():
    return load_module("bird_status_verifier_bootstage", STATUS_VERIFIER_PATH)


def config_map(data: bytes) -> dict[bytes, bytes]:
    result: dict[bytes, bytes] = {}
    for line in data.splitlines():
        if line.startswith(b"CONFIG_"):
            key, value = line.split(b"=", 1)
        elif line.startswith(b"# CONFIG_") and line.endswith(b" is not set"):
            key, value = line[2:-11], b"n"
        else:
            continue
        if key in result:
            fail(f"duplicate resolved config symbol: {key.decode()}")
        result[key] = value
    return result


def verify_config_delta(base: bytes, candidate: bytes) -> None:
    before, after = config_map(base), config_map(candidate)
    changed = {
        key: (before.get(key, b"n"), after.get(key, b"n"))
        for key in before.keys() | after.keys()
        if before.get(key, b"n") != after.get(key, b"n")
    }
    if changed != EXPECTED_CONFIG_DELTA:
        fail("resolved GCC config is not the exact bootstage-FDT delta")
    fixed = {
        b"CONFIG_BOOTSTAGE": b"y",
        b"CONFIG_BOOTSTAGE_FDT": b"y",
        b"CONFIG_BOOTSTAGE_RECORD_COUNT": b"50",
        b"CONFIG_BOOTSTAGE_REPORT": b"n",
        b"CONFIG_CMD_BOOTSTAGE": b"n",
        b"CONFIG_SPL_BOOTSTAGE": b"n",
        b"CONFIG_BOOTSTAGE_STASH": b"n",
        b"CONFIG_ENV_SOURCE_FILE": b'"bird-rg34xx-sp-handoff"',
        b"CONFIG_ENV_IS_NOWHERE": b"y",
        b"CONFIG_ENV_IS_IN_FAT": b"n",
        b"CONFIG_BOOTDELAY": b"-2",
        b"CONFIG_NO_NET": b"y",
        b"CONFIG_NET": b"n",
        b"CONFIG_BOOTSTD": b"n",
        b"CONFIG_SYS_MALLOC_CLEAR_ON_INIT": b"n",
        b"CONFIG_SPL_SYS_MALLOC_CLEAR_ON_INIT": b"y",
    }
    for key, expected in fixed.items():
        if after.get(key, b"n") != expected:
            fail(f"required bootstage-FDT config changed: {key.decode()}")


def verify_combined(combined: bytes, spl: bytes, fit: bytes) -> None:
    inplace_verifier().verify_combined(combined, spl, fit)


def verify_standalone_spl(spl: bytes, role: str) -> None:
    if len(spl) != SPL_REGION_BYTES:
        fail(f"{role} SPL is not the exact fixed-region size")
    if spl[4:12] != b"eGON.BT0":
        fail(f"{role} SPL lacks the Allwinner signature")
    if struct.unpack_from("<I", spl, 0x10)[0] != SPL_REGION_BYTES:
        fail(f"{role} SPL fixed-region length changed")


def load_build(directory: pathlib.Path) -> dict[str, bytes]:
    return {name: file_bytes(directory / name) for name in REQUIRED_ARTIFACTS}


def assert_builds_equal(first: dict[str, bytes], second: dict[str, bytes]) -> None:
    for name in REQUIRED_ARTIFACTS:
        if first[name] != second[name]:
            fail(f"bootstage-FDT build is not reproducible: {name} differs")


def verify_fit_scope(base_fit: bytes, candidate_fit: bytes) -> None:
    parser = status_verifier()
    before, after = parser.parse_fit(base_fit), parser.parse_fit(candidate_fit)
    if set(before) != set(after):
        fail("candidate FIT node inventory changed")
    for node in before:
        old, new = dict(before[node]), dict(after[node])
        if node == "/images/uboot":
            old.pop("data", None)
            new.pop("data", None)
        if old != new:
            fail(f"candidate FIT changed outside its U-Boot data: {node}")


def candidate_identity(build: dict[str, bytes], prefix: bytes) -> dict[str, str | int]:
    return {
        "candidate-bytes": len(build["u-boot-sunxi-with-spl.bin"]),
        "candidate-sha256": sha256(build["u-boot-sunxi-with-spl.bin"]),
        "candidate-fit-bytes": len(build["u-boot.itb"]),
        "candidate-fit-sha256": sha256(build["u-boot.itb"]),
        "candidate-uboot-bytes": len(build["u-boot-nodtb.bin"]),
        "candidate-uboot-sha256": sha256(build["u-boot-nodtb.bin"]),
        "candidate-config-sha256": sha256(build["build.config"]),
        "generated-unused-spl-bytes": len(build["generated-unused-spl.bin"]),
        "generated-unused-spl-sha256": sha256(build["generated-unused-spl.bin"]),
        "packaged-accepted-spl-bytes": len(build["packaged-accepted-spl.bin"]),
        "packaged-accepted-spl-sha256": sha256(
            build["packaged-accepted-spl.bin"]
        ),
        "full-prefix-sha256": sha256(prefix),
    }


def verify_review_state(identity: dict[str, str | int]) -> None:
    if REVIEWED_CANDIDATE_IDENTITIES and identity != REVIEWED_CANDIDATE_IDENTITIES:
        fail("reviewed bootstage-FDT candidate identity changed")


def validate_candidate(
    first: dict[str, bytes],
    second: dict[str, bytes],
    base_files: dict[str, bytes],
    bl31: bytes,
    toolchain: bytes,
) -> None:
    for build in (first, second):
        verify_standalone_spl(build["generated-unused-spl.bin"], "generated-unused")
        verify_standalone_spl(build["packaged-accepted-spl.bin"], "packaged-accepted")
        verify_combined(
            build["u-boot-sunxi-with-spl.bin"],
            build["packaged-accepted-spl.bin"],
            build["u-boot.itb"],
        )
    assert_builds_equal(first, second)
    if first["u-boot-sunxi-with-spl.bin"] == base_files["combined"]:
        fail("bootstage-FDT candidate is byte-identical to its accepted base")
    if first["u-boot-nodtb.bin"] == base_files["uboot"]:
        fail("bootstage-FDT candidate did not alter full U-Boot")
    packaged_spl = first["packaged-accepted-spl.bin"]
    generated_spl = first["generated-unused-spl.bin"]
    if packaged_spl != base_files["spl"] or sha256(packaged_spl) != INPLACE_SPL_SHA256:
        fail("bootstage-FDT packaged SPL is not the exact accepted SPL")
    if generated_spl == packaged_spl:
        fail("bootstage-FDT generated-unused SPL did not retain the expected drift")
    expected_combined = (
        packaged_spl
        + bytes(SPL_REGION_BYTES - len(packaged_spl))
        + first["u-boot.itb"]
    )
    if first["u-boot-sunxi-with-spl.bin"] != expected_combined:
        fail("bootstage-FDT combined image is not accepted SPL plus candidate FIT")
    if first["u-boot.dtb"] != base_files["dtb"]:
        fail("bootstage-FDT candidate altered the control FDT")
    verify_config_delta(base_files["config"], first["build.config"])
    verify_fit_scope(base_files["fit"], first["u-boot.itb"])
    status_verifier().verify_fit(
        first["u-boot.itb"], first["u-boot-nodtb.bin"], bl31, first["u-boot.dtb"]
    )
    status_verifier().verify_toolchain_authority(toolchain)


def load_base(base: pathlib.Path) -> tuple[dict[str, bytes], bytes, bytes, bytes, bytes]:
    inplace_verifier().verify_output(base)
    authority = file_bytes(base / "authority.tsv")
    if sha256(authority) != INPLACE_AUTHORITY_SHA256:
        fail("accepted in-place authority changed")
    files = {
        "combined": file_bytes(base / "inplace-handoff.bin"),
        "fit": file_bytes(base / "inplace-handoff.itb"),
        "uboot": file_bytes(base / "inplace-handoff-uboot.bin"),
        "dtb": file_bytes(base / "inplace-handoff-control.dtb"),
        "spl": file_bytes(base / "inplace-handoff-spl.bin"),
        "config": file_bytes(base / "inplace-handoff.config"),
    }
    expected = {
        "combined": INPLACE_COMBINED_SHA256,
        "fit": INPLACE_FIT_SHA256,
        "uboot": INPLACE_UBOOT_SHA256,
        "dtb": INPLACE_DTB_SHA256,
        "spl": INPLACE_SPL_SHA256,
        "config": INPLACE_CONFIG_SHA256,
    }
    for name, digest in expected.items():
        if sha256(files[name]) != digest:
            fail(f"accepted in-place {name} changed")
    environment = file_bytes(base / ENVIRONMENT_FILENAME)
    if environment != ENVIRONMENT or sha256(environment) != ENVIRONMENT_SHA256:
        fail("accepted in-place environment changed")
    base_prefix = bytearray(file_bytes(base / "base-fast-init-prefix-16m.bin"))
    if len(base_prefix) != PREFIX_BYTES:
        fail("accepted prefix source size changed")
    base_prefix[RAW_OFFSET:RAW_OFFSET + len(files["combined"])] = files["combined"]
    if sha256(base_prefix) != ACCEPTED_PREFIX_SHA256:
        fail("accepted in-place prefix reconstruction changed")
    return files, authority, environment, bytes(base_prefix), file_bytes(base / "bl31.bin")


def pass_files(name: str, build: dict[str, bytes]) -> dict[str, bytes]:
    return {
        f"{name}-combined.bin": build["u-boot-sunxi-with-spl.bin"],
        f"{name}.itb": build["u-boot.itb"],
        f"{name}-uboot.bin": build["u-boot-nodtb.bin"],
        f"{name}-control.dtb": build["u-boot.dtb"],
        f"{name}-generated-unused-spl.bin": build["generated-unused-spl.bin"],
        f"{name}-packaged-accepted-spl.bin": build[
            "packaged-accepted-spl.bin"
        ],
        f"{name}.config": build["build.config"],
    }


def build_inventory(builds: dict[str, dict[str, bytes]]) -> bytes:
    lines = [f"schema\t{TWO_PASS_SCHEMA}"]
    for name in BUILD_NAMES:
        for artifact in REQUIRED_ARTIFACTS:
            data = builds[name][artifact]
            lines.append(f"artifact\t{name}\t{artifact}\t{len(data)}\t{sha256(data)}")
    return ("\n".join(lines) + "\n").encode("ascii")


def authority_bytes(rows: list[tuple[str, str | int]]) -> bytes:
    lines = []
    for key, value in rows:
        rendered = str(value)
        if not key or not rendered or "\t" in key + rendered or "\n" in key + rendered:
            fail("unsafe authority value")
        lines.append(f"{key}\t{rendered}")
    return ("\n".join(lines) + "\n").encode("ascii")


def parse_authority(data: bytes) -> dict[str, str]:
    try:
        lines = data.decode("ascii").splitlines()
    except UnicodeDecodeError:
        fail("authority is not ASCII")
    if not data.endswith(b"\n"):
        fail("authority lacks a final newline")
    result: dict[str, str] = {}
    for line in lines:
        fields = line.split("\t")
        if len(fields) != 2 or not all(fields) or fields[0] in result:
            fail("authority row is malformed or duplicated")
        result[fields[0]] = fields[1]
    return result


def publish(
    build_a: pathlib.Path,
    build_b: pathlib.Path,
    base: pathlib.Path,
    bl31_path: pathlib.Path,
    toolchain_path: pathlib.Path,
    output: pathlib.Path,
) -> None:
    if output.exists() or output.is_symlink():
        fail(f"refusing to replace result directory: {output}")
    base_files, base_authority, environment, accepted_prefix, retained_bl31 = load_base(base)
    bl31 = file_bytes(bl31_path)
    if sha256(bl31) != BL31_SHA256 or bl31 != retained_bl31:
        fail("pinned BL31 differs from accepted in-place base")
    toolchain = file_bytes(toolchain_path)
    retained_toolchain = file_bytes(base / "toolchain-authority.tsv")
    if sha256(toolchain) != TOOLCHAIN_AUTHORITY_SHA256 or toolchain != retained_toolchain:
        fail("pinned toolchain differs from accepted in-place base")
    first, second = load_build(build_a), load_build(build_b)
    validate_candidate(first, second, base_files, bl31, toolchain)
    candidate_prefix = bytearray(accepted_prefix)
    combined = first["u-boot-sunxi-with-spl.bin"]
    end = RAW_OFFSET + len(combined)
    if end > PREFIX_BYTES:
        fail("candidate exceeds accepted prefix")
    candidate_prefix[RAW_OFFSET:end] = combined
    identity = candidate_identity(first, bytes(candidate_prefix))
    verify_review_state(identity)
    builds = dict(zip(BUILD_NAMES, (first, second)))
    published = {
        "accepted-inplace-prefix-16m.bin": accepted_prefix,
        "bird-rg34xx-sp-handoff.env": environment,
        "bird-uboot-bootstage-fdt.bin": combined,
        "bl31.bin": bl31,
        "bootstage-fdt-prefix-16m.bin": bytes(candidate_prefix),
        "bootstage-fdt.bin": combined,
        "bootstage-fdt.itb": first["u-boot.itb"],
        "bootstage-fdt-uboot.bin": first["u-boot-nodtb.bin"],
        "bootstage-fdt-control.dtb": first["u-boot.dtb"],
        "bootstage-fdt-generated-unused-spl.bin": first[
            "generated-unused-spl.bin"
        ],
        "bootstage-fdt-packaged-accepted-spl.bin": first[
            "packaged-accepted-spl.bin"
        ],
        "bootstage-fdt.config": first["build.config"],
        "inplace-base-authority.tsv": base_authority,
        "inplace-base-combined.bin": base_files["combined"],
        "inplace-base.itb": base_files["fit"],
        "inplace-base-uboot.bin": base_files["uboot"],
        "inplace-base-control.dtb": base_files["dtb"],
        "inplace-base-spl.bin": base_files["spl"],
        "inplace-base.config": base_files["config"],
        "toolchain-authority.tsv": toolchain,
        "two-pass-inventory.tsv": build_inventory(builds),
    }
    published.update(pass_files(BUILD_NAMES[0], first))
    published.update(pass_files(BUILD_NAMES[1], second))
    published["authority.tsv"] = authority_bytes([
        ("schema", SCHEMA),
        ("review-state", REVIEW_STATE if not REVIEWED_CANDIDATE_IDENTITIES else "reviewed"),
        ("publication", PUBLICATION),
        ("measurement-only", "yes"),
        ("deployment-authority", DEPLOYMENT_AUTHORITY),
        ("rocknix-release", ROCKNIX_RELEASE),
        ("rocknix-commit", ROCKNIX_COMMIT),
        ("uboot-version", UBOOT_VERSION),
        ("defconfig", DEFCONFIG_NAME),
        ("bootstage-defconfig-sha256", BOOTSTAGE_DEFCONFIG_SHA256),
        ("bootstage-transform-sha256", BOOTSTAGE_TRANSFORM_SHA256),
        ("inplace-authority-sha256", INPLACE_AUTHORITY_SHA256),
        ("accepted-inplace-prefix-sha256", ACCEPTED_PREFIX_SHA256),
        ("environment-sha256", ENVIRONMENT_SHA256),
        *identity.items(),
        ("packaged-spl-source", "accepted-inplace-exact"),
        ("generated-spl-role", "build-evidence-unused"),
        (
            "generated-spl-difference-reason",
            "raw-CONFIG_BOOTSTAGE-adds-gd-bootstage-shifts-cyclic_list",
        ),
        ("control-fdt-sha256", sha256(first["u-boot.dtb"])),
        ("bl31-sha256", sha256(bl31)),
        ("resolved-gcc-config-delta-symbols", 3),
        ("bootstage-built", "yes"),
        ("bootstage-fdt-built", "yes"),
        ("bootstage-record-count", 50),
        ("bootstage-report-built", "no"),
        ("bootstage-command-built", "no"),
        ("spl-bootstage-built", "no"),
        ("bootstage-stash-built", "no"),
        ("spl-to-uboot-bootstage-handoff", "no"),
        ("candidate-repeat-byte-identical", "yes"),
        ("generated-spl-repeat-byte-identical", "yes"),
        ("packaged-spl-repeat-byte-identical", "yes"),
        ("environment-byte-identical-to-base", "yes"),
        ("packaged-spl-byte-identical-to-base", "yes"),
        ("generated-spl-byte-identical-to-packaged", "no"),
        ("generated-spl-used-in-combined", "no"),
        ("packaged-spl-used-in-combined", "yes"),
        ("combined-spl-region-bytes", SPL_REGION_BYTES),
        ("combined-layout", "accepted-spl-zero-pad-40960-plus-candidate-fit"),
        ("control-fdt-byte-identical-to-base", "yes"),
        ("bl31-byte-identical-to-base", "yes"),
        ("fit-change-scope", "uboot-data-only"),
    ])
    output.mkdir(mode=0o755)
    for name, data in published.items():
        with (output / name).open("xb") as destination:
            destination.write(data)
    with (output / "sha256sums.txt").open("x", encoding="ascii", newline="") as sums:
        for name, data in sorted(published.items()):
            sums.write(f"{sha256(data)}  {name}\n")


def verify_output(directory: pathlib.Path) -> None:
    if directory.is_symlink() or not directory.is_dir():
        fail("bootstage-FDT authority is missing or unsafe")
    if tuple(sorted(path.name for path in directory.iterdir())) != tuple(sorted(PUBLISHED)):
        fail("bootstage-FDT authority inventory changed")
    expected = sorted(name for name in PUBLISHED if name != "sha256sums.txt")
    lines = file_bytes(directory / "sha256sums.txt").decode("ascii").splitlines()
    if len(lines) != len(expected):
        fail("bootstage-FDT checksum inventory changed")
    for line, name in zip(lines, expected):
        if line != f"{sha256(file_bytes(directory / name))}  {name}":
            fail(f"bootstage-FDT checksum changed: {name}")
    authority = parse_authority(file_bytes(directory / "authority.tsv"))
    required = {
        "schema": SCHEMA,
        "review-state": REVIEW_STATE if not REVIEWED_CANDIDATE_IDENTITIES else "reviewed",
        "publication": PUBLICATION,
        "measurement-only": "yes",
        "deployment-authority": DEPLOYMENT_AUTHORITY,
        "bootstage-defconfig-sha256": BOOTSTAGE_DEFCONFIG_SHA256,
        "bootstage-transform-sha256": BOOTSTAGE_TRANSFORM_SHA256,
        "inplace-authority-sha256": INPLACE_AUTHORITY_SHA256,
        "accepted-inplace-prefix-sha256": ACCEPTED_PREFIX_SHA256,
        "environment-sha256": ENVIRONMENT_SHA256,
        "packaged-accepted-spl-sha256": INPLACE_SPL_SHA256,
        "packaged-accepted-spl-bytes": str(SPL_REGION_BYTES),
        "packaged-spl-source": "accepted-inplace-exact",
        "generated-spl-role": "build-evidence-unused",
        "generated-spl-difference-reason": (
            "raw-CONFIG_BOOTSTAGE-adds-gd-bootstage-shifts-cyclic_list"
        ),
        "control-fdt-sha256": INPLACE_DTB_SHA256,
        "bl31-sha256": BL31_SHA256,
        "resolved-gcc-config-delta-symbols": "3",
        "bootstage-built": "yes",
        "bootstage-fdt-built": "yes",
        "bootstage-record-count": "50",
        "bootstage-report-built": "no",
        "bootstage-command-built": "no",
        "spl-bootstage-built": "no",
        "bootstage-stash-built": "no",
        "spl-to-uboot-bootstage-handoff": "no",
        "candidate-repeat-byte-identical": "yes",
        "generated-spl-repeat-byte-identical": "yes",
        "packaged-spl-repeat-byte-identical": "yes",
        "environment-byte-identical-to-base": "yes",
        "packaged-spl-byte-identical-to-base": "yes",
        "generated-spl-byte-identical-to-packaged": "no",
        "generated-spl-used-in-combined": "no",
        "packaged-spl-used-in-combined": "yes",
        "combined-spl-region-bytes": str(SPL_REGION_BYTES),
        "combined-layout": "accepted-spl-zero-pad-40960-plus-candidate-fit",
        "control-fdt-byte-identical-to-base": "yes",
        "bl31-byte-identical-to-base": "yes",
        "fit-change-scope": "uboot-data-only",
    }
    for key, value in required.items():
        if authority.get(key) != value:
            fail(f"bootstage-FDT authority field changed: {key}")
    first = {
        "u-boot-sunxi-with-spl.bin": file_bytes(directory / "bootstage-fdt-a-combined.bin"),
        "u-boot.itb": file_bytes(directory / "bootstage-fdt-a.itb"),
        "u-boot-nodtb.bin": file_bytes(directory / "bootstage-fdt-a-uboot.bin"),
        "u-boot.dtb": file_bytes(directory / "bootstage-fdt-a-control.dtb"),
        "generated-unused-spl.bin": file_bytes(
            directory / "bootstage-fdt-a-generated-unused-spl.bin"
        ),
        "packaged-accepted-spl.bin": file_bytes(
            directory / "bootstage-fdt-a-packaged-accepted-spl.bin"
        ),
        "build.config": file_bytes(directory / "bootstage-fdt-a.config"),
    }
    second = {
        "u-boot-sunxi-with-spl.bin": file_bytes(directory / "bootstage-fdt-b-combined.bin"),
        "u-boot.itb": file_bytes(directory / "bootstage-fdt-b.itb"),
        "u-boot-nodtb.bin": file_bytes(directory / "bootstage-fdt-b-uboot.bin"),
        "u-boot.dtb": file_bytes(directory / "bootstage-fdt-b-control.dtb"),
        "generated-unused-spl.bin": file_bytes(
            directory / "bootstage-fdt-b-generated-unused-spl.bin"
        ),
        "packaged-accepted-spl.bin": file_bytes(
            directory / "bootstage-fdt-b-packaged-accepted-spl.bin"
        ),
        "build.config": file_bytes(directory / "bootstage-fdt-b.config"),
    }
    base_files = {
        "combined": file_bytes(directory / "inplace-base-combined.bin"),
        "fit": file_bytes(directory / "inplace-base.itb"),
        "uboot": file_bytes(directory / "inplace-base-uboot.bin"),
        "dtb": file_bytes(directory / "inplace-base-control.dtb"),
        "spl": file_bytes(directory / "inplace-base-spl.bin"),
        "config": file_bytes(directory / "inplace-base.config"),
    }
    for name, digest in {
        "combined": INPLACE_COMBINED_SHA256,
        "fit": INPLACE_FIT_SHA256,
        "uboot": INPLACE_UBOOT_SHA256,
        "dtb": INPLACE_DTB_SHA256,
        "spl": INPLACE_SPL_SHA256,
        "config": INPLACE_CONFIG_SHA256,
    }.items():
        if sha256(base_files[name]) != digest:
            fail(f"retained accepted in-place {name} changed")
    bl31 = file_bytes(directory / "bl31.bin")
    toolchain = file_bytes(directory / "toolchain-authority.tsv")
    if sha256(bl31) != BL31_SHA256 or sha256(toolchain) != TOOLCHAIN_AUTHORITY_SHA256:
        fail("retained firmware/toolchain authority changed")
    validate_candidate(first, second, base_files, bl31, toolchain)
    accepted_prefix = file_bytes(directory / "accepted-inplace-prefix-16m.bin")
    if len(accepted_prefix) != PREFIX_BYTES or sha256(accepted_prefix) != ACCEPTED_PREFIX_SHA256:
        fail("retained accepted in-place prefix changed")
    canonical = first["u-boot-sunxi-with-spl.bin"]
    candidate_prefix = bytearray(accepted_prefix)
    candidate_prefix[RAW_OFFSET:RAW_OFFSET + len(canonical)] = canonical
    if file_bytes(directory / "bootstage-fdt-prefix-16m.bin") != bytes(candidate_prefix):
        fail("bootstage-FDT candidate prefix changed")
    identity = candidate_identity(first, bytes(candidate_prefix))
    verify_review_state(identity)
    for key, value in identity.items():
        if authority.get(key) != str(value):
            fail(f"candidate identity field changed: {key}")
    aliases = {
        "bird-uboot-bootstage-fdt.bin": canonical,
        "bootstage-fdt.bin": canonical,
        "bootstage-fdt.itb": first["u-boot.itb"],
        "bootstage-fdt-uboot.bin": first["u-boot-nodtb.bin"],
        "bootstage-fdt-control.dtb": first["u-boot.dtb"],
        "bootstage-fdt-generated-unused-spl.bin": first[
            "generated-unused-spl.bin"
        ],
        "bootstage-fdt-packaged-accepted-spl.bin": first[
            "packaged-accepted-spl.bin"
        ],
        "bootstage-fdt.config": first["build.config"],
        ENVIRONMENT_FILENAME: ENVIRONMENT,
    }
    for name, expected_data in aliases.items():
        if file_bytes(directory / name) != expected_data:
            fail(f"canonical bootstage-FDT component changed: {name}")
    if file_bytes(directory / "inplace-base-authority.tsv") == b"" or sha256(
        file_bytes(directory / "inplace-base-authority.tsv")
    ) != INPLACE_AUTHORITY_SHA256:
        fail("retained accepted in-place authority changed")
    if file_bytes(directory / "two-pass-inventory.tsv") != build_inventory(
        dict(zip(BUILD_NAMES, (first, second)))
    ):
        fail("two-pass inventory changed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-a", type=pathlib.Path)
    parser.add_argument("--build-b", type=pathlib.Path)
    parser.add_argument("--base-authority", type=pathlib.Path)
    parser.add_argument("--bl31", type=pathlib.Path)
    parser.add_argument("--toolchain-authority", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--verify-output", type=pathlib.Path)
    args = parser.parse_args()
    if args.verify_output:
        if any((args.build_a, args.build_b, args.base_authority, args.bl31, args.toolchain_authority, args.output)):
            fail("--verify-output cannot be combined with publication inputs")
        verify_output(args.verify_output)
        state = "reviewed" if REVIEWED_CANDIDATE_IDENTITIES else "hashes pending"
        print(f"U-Boot bootstage-FDT authority: VERIFIED ({state}; measurement only)")
        return
    if not all((args.build_a, args.build_b, args.base_authority, args.bl31, args.toolchain_authority, args.output)):
        fail("publication requires two builds, exact accepted base, BL31, toolchain, and output")
    publish(args.build_a, args.build_b, args.base_authority, args.bl31, args.toolchain_authority, args.output)


if __name__ == "__main__":
    main()
