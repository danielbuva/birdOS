#!/usr/bin/env python3
"""Create an unsealed birdOS baseline artifact outside the source tree."""

from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import platform
import plistlib
import shutil
import stat
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "launcher/catalog.generated.h"


def run(*command: str, check: bool = True) -> str:
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    if check and result.returncode:
        raise SystemExit(f"command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}")
    return result.stdout.rstrip("\n")


def digest(path: pathlib.Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def write_tsv(path: pathlib.Path, rows: list[tuple[object, ...]]) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as output:
        for row in rows:
            fields = [str(field) for field in row]
            if any("\t" in field or "\n" in field or "\r" in field for field in fields):
                raise SystemExit(f"unsafe TSV field for {path}: {fields!r}")
            output.write("\t".join(fields) + "\n")


def safe_field(value: str) -> str:
    return value.replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n")


def resolve_tool(candidate: str) -> pathlib.Path | None:
    if "/" in candidate:
        path = pathlib.Path(candidate)
        return path.resolve() if path.is_file() else None
    found = shutil.which(candidate)
    return pathlib.Path(found).resolve() if found else None


def first_version(path: pathlib.Path) -> str:
    for arguments in (["--version"], ["-V"], ["-h"]):
        output = run(str(path), *arguments, check=False)
        if output:
            return output.splitlines()[0][:240]
    return "unreported"


def catalog_number(name: str) -> str:
    prefix = f"#define {name} "
    for line in CATALOG.read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            return line[len(prefix):].removesuffix("U").removesuffix("UL")
    raise SystemExit(f"catalog macro missing: {name}")


def disk_info(path: str) -> dict[str, object] | None:
    result = subprocess.run(
        ["diskutil", "info", "-plist", path], cwd=ROOT,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
    )
    if result.returncode:
        return None
    return plistlib.loads(result.stdout)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--mode", choices=("release", "profile", "trace", "recovery"), required=True)
    parser.add_argument("--release-id", required=True)
    parser.add_argument("--command", action="append", default=[])
    parser.add_argument("--deploy-manifest", type=pathlib.Path)
    parser.add_argument("--build-output", type=pathlib.Path)
    parser.add_argument("--bird-volume", default="/Volumes/BIRD")
    parser.add_argument("--data-volume", default="/Volumes/BIRD-DATA")
    args = parser.parse_args()

    output = args.output.resolve()
    try:
        output.relative_to(ROOT)
    except ValueError:
        pass
    else:
        raise SystemExit("live measurement output must be outside the repository")
    output.mkdir(parents=True, exist_ok=False)

    head = run("git", "rev-parse", "HEAD")
    origin = run("git", "rev-parse", "origin/main")
    public_fields = run("git", "ls-remote", "origin", "refs/heads/main").split()
    public = public_fields[0] if public_fields else "unavailable"
    status = run("git", "status", "--porcelain=v1", "-uall")
    source_state = "clean" if not status else "dirty"
    branch = run("git", "branch", "--show-current") or "detached"
    upstream = run("git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}", check=False) or "none"
    upstream_sha = run("git", "rev-parse", "@{upstream}", check=False) or "none"
    submodules = run("git", "submodule", "status", "--recursive", check=False)
    diff = subprocess.run(
        ["git", "diff", "--binary", "HEAD", "--"], cwd=ROOT,
        stdout=subprocess.PIPE, check=True,
    ).stdout
    (output / "source.patch").write_bytes(diff)

    untracked_rows: list[tuple[object, ...]] = [("path", "type", "mode", "size", "sha256")]
    untracked = run("git", "ls-files", "--others", "--exclude-standard").splitlines()
    for relative in sorted(untracked):
        path = ROOT / relative
        info = path.lstat()
        kind = "file" if stat.S_ISREG(info.st_mode) else "symlink" if stat.S_ISLNK(info.st_mode) else "other"
        file_digest = digest(path) if kind == "file" else hashlib.sha256(os.readlink(path).encode()).hexdigest()
        untracked_rows.append((relative, kind, f"{stat.S_IMODE(info.st_mode):04o}", info.st_size, file_digest))
    write_tsv(output / "untracked.tsv", untracked_rows)
    submodule_rows: list[tuple[object, ...]] = [("state", "commit", "path", "description")]
    for line in submodules.splitlines():
        match = line and line[0]
        fields = line[1:].split(" ", 2) if match in {" ", "+", "-", "U"} else []
        if len(fields) >= 2:
            description = fields[2] if len(fields) == 3 else ""
            submodule_rows.append((match, fields[0], fields[1], safe_field(description)))
    write_tsv(output / "submodules.tsv", submodule_rows)

    bird_info = disk_info(args.bird_volume) if pathlib.Path("/usr/sbin/diskutil").exists() else None
    data_info = disk_info(args.data_volume) if pathlib.Path("/usr/sbin/diskutil").exists() else None
    card_rows: list[tuple[object, ...]] = [("scope", "key", "value")]
    if bird_info and data_info:
        whole = str(bird_info.get("ParentWholeDisk", "missing"))
        whole_info = disk_info(f"/dev/{whole}") or {}
        for scope, info in (("card", whole_info), ("boot", bird_info), ("data", data_info)):
            for key in (
                "DeviceIdentifier", "DeviceNode", "ParentWholeDisk", "Content",
                "FilesystemType", "VolumeName", "VolumeUUID", "Size",
                "PartitionMapPartitionOffset", "DeviceBlockSize", "BusProtocol",
                "RemovableMedia", "VirtualOrPhysical",
            ):
                if key in info:
                    card_rows.append((scope, key, safe_field(str(info[key]))))
    else:
        card_rows.append(("card", "status", "not-captured"))
    write_tsv(output / "card-instance.tsv", card_rows)

    dirty_input = status.encode() + b"\0" + diff + (output / "untracked.tsv").read_bytes()
    dirty_digest = hashlib.sha256(dirty_input).hexdigest()
    manifest_digest = digest(args.deploy_manifest.resolve()) if args.deploy_manifest else "pending"
    contract_digest = digest(ROOT / "bird-device-contract.tsv")
    catalog_digest = digest(CATALOG)
    write_tsv(output / "identity.tsv", [
        ("key", "value"),
        ("source-head", head),
        ("origin-main", origin),
        ("public-main", public),
        ("branch", branch),
        ("upstream", upstream),
        ("upstream-sha", upstream_sha),
        ("source-state", source_state),
        ("dirty-digest", dirty_digest),
        ("release-id", args.release_id),
        ("mode", args.mode),
        ("deploy-manifest-sha256", manifest_digest),
        ("device-contract-sha256", contract_digest),
        ("catalog-sha256", catalog_digest),
        ("catalog-revision", (ROOT / "launcher/catalog.revision").read_text().strip()),
        ("catalog-system-count", catalog_number("CATALOG_SYSTEM_COUNT")),
        ("catalog-game-count", catalog_number("CATALOG_ENTRY_COUNT")),
        ("catalog-media-category-count", catalog_number("CATALOG_MEDIA_CATEGORY_COUNT")),
        ("catalog-media-entry-count", catalog_number("CATALOG_MEDIA_ENTRY_COUNT")),
    ])

    environment_names = {
        "LANG", "LC_ALL", "LC_CTYPE", "TZ", "SOURCE_DATE_EPOCH", "ZERO_AR_DATE",
        "CLANG", "LLD", "READELF", "CPIO", "BIRD_LAUNCHER_PROFILE",
        "BIRD_TRACE_BOOT", "BIRD_RECOVERY_MODE",
    }
    environment_rows: list[tuple[object, ...]] = [("key", "value")]
    for name in sorted(environment_names):
        environment_rows.append((name, safe_field(os.environ.get(name, "unset"))))
    current_umask = os.umask(0)
    os.umask(current_umask)
    environment_rows.extend([
        ("umask", f"{current_umask:04o}"),
        ("timezone-runtime", safe_field(run("date", "+%Z%z", check=False) or "unreported")),
        ("platform", safe_field(platform.platform())),
        ("machine", platform.machine()),
        ("python", safe_field(platform.python_version())),
    ])
    write_tsv(output / "environment.tsv", environment_rows)

    tools = [
        os.environ.get("CLANG", "/opt/homebrew/opt/llvm/bin/clang"),
        os.environ.get("LLD", "/opt/homebrew/opt/lld/bin/ld.lld"),
        os.environ.get("READELF", "/opt/homebrew/opt/llvm/bin/llvm-readelf"),
        os.environ.get("CPIO", "cpio"), "gzip", "lz4", "zstd", "xz",
    ]
    tool_rows: list[tuple[object, ...]] = [("requested", "path", "sha256", "version")]
    for candidate in tools:
        path = resolve_tool(candidate)
        if path is None:
            tool_rows.append((candidate, "missing", "missing", "missing"))
        else:
            tool_rows.append((candidate, path, digest(path), first_version(path)))
    write_tsv(output / "toolchain.tsv", tool_rows)

    command_rows: list[tuple[object, ...]] = [("sequence", "cwd", "environment_sha256", "command")]
    environment_digest = digest(output / "environment.tsv")
    for sequence, command in enumerate(args.command, 1):
        command_rows.append((sequence, ROOT, environment_digest, safe_field(command)))
    write_tsv(output / "commands.tsv", command_rows)

    if args.build_output:
        build_flags = args.build_output.resolve() / "build/build-flags.tsv"
        if not build_flags.is_file() or build_flags.is_symlink():
            raise SystemExit(f"build flags are missing or unsafe: {build_flags}")
        (output / "build-flags.tsv").write_bytes(build_flags.read_bytes())
    else:
        write_tsv(output / "build-flags.tsv", [
            ("component", "mode", "flags"),
            ("pending", args.mode, "pending-build"),
        ])

    external_rows: list[tuple[object, ...]] = [
        ("path", "mode", "size", "sha256", "provenance")
    ]
    if args.deploy_manifest:
        for raw in args.deploy_manifest.resolve().read_text(encoding="utf-8").splitlines():
            fields = raw.split("\t")
            if fields and fields[0] == "input" and len(fields) == 6:
                external_rows.append(tuple(fields[1:]))
    write_tsv(output / "external-inputs.tsv", external_rows)

    sample_headers = {
        "boot-release.tsv": ("sample", "order", "power_origin_ns", "kernel_start_ns", "first_pixel_ns", "input_ready_ns", "usable_frame_ns", "storage_ready_ns", "application_ready_ns"),
        "boot-profile.tsv": ("sample", "metric", "value", "unit"),
        "interaction-ui.tsv": ("sample", "scenario", "electrical_edge_ns", "evdev_ns", "launcher_read_ns", "framebuffer_barrier_ns", "photon_change_ns"),
        "interaction-content.tsv": ("sample", "provider", "temperature", "a_edge_ns", "request_ns", "exec_ns", "usable_ns", "first_input_ns", "exit_ns", "bird_ready_ns"),
        "idle-power.tsv": ("sample", "state", "soc_percent", "battery_mv", "temperature_mc", "brightness_raw", "duration_s", "energy_j", "wakeups", "irqs"),
        "suspend-power.tsv": ("sample", "state", "soc_percent", "battery_mv", "temperature_mc", "duration_s", "energy_j", "resume_ready_ns", "restored_brightness_raw"),
        "binary-sections.tsv": ("mode", "binary", "section", "bytes"),
        "memory.tsv": ("sample", "milestone", "process", "pss_kib", "uss_kib", "rss_kib"),
    }
    for name, header in sample_headers.items():
        write_tsv(output / name, [header])
    write_tsv(output / "host-gate.tsv", [
        ("schema", "bird-gate-v1"),
        ("result", "PENDING"),
        ("check", "generated-contract", "PENDING"),
        ("check", "final-root-launcher", "PENDING"),
        ("check", "early-initramfs-launcher", "PENDING"),
        ("check", "launcher-catalog-storage-supervisor-build-suite", "PENDING"),
        ("check", "deployment-fallback-fault-injection", "PENDING"),
    ])
    write_tsv(output / "hardware-gate.tsv", [
        ("schema", "bird-gate-v1"),
        ("result", "PENDING"),
        ("check", "usable-menu-and-input", "PENDING"),
        ("check", "navigation-paging-and-actions", "PENDING"),
        ("check", "favorites-persistence", "PENDING"),
        ("check", "asynchronous-storage-and-one-pending-intent", "PENDING"),
        ("check", "provider-launch-input-return-and-recovery", "PENDING"),
        ("check", "offline-network-and-portmaster-boundary", "PENDING"),
        ("check", "battery-charging-brightness-controls", "PENDING"),
        ("check", "suspend-resume-and-shutdown", "PENDING"),
        ("check", "fallback-and-power-loss-recovery", "PENDING"),
        ("check", "boot-interaction-content-power-memory-samples", "PENDING"),
    ])
    (output / "notes.md").write_text(
        "# Baseline notes\n\nUnsealed acquisition artifact. Record anomalies and physical setup here.\n",
        encoding="utf-8", newline="\n",
    )
    print(output)


if __name__ == "__main__":
    main()
