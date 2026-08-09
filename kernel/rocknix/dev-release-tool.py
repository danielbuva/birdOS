#!/usr/bin/env python3
"""Build and transactionally activate the mutable birdOS dev-current release."""

from __future__ import annotations

import argparse
import dataclasses
import errno
import gzip
import hashlib
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Iterable, Sequence


DEV_RELEASE = "dev-current"
DEV_STAGE_PREFIX = f".{DEV_RELEASE}.new."
DEV_CLEANUP_AUTHORITY = "bird-dev-cleanup.tsv"
DEV_CLEANUP_TEMP_PREFIX = f".{DEV_CLEANUP_AUTHORITY}.dev-new."
DEV_CLEANUP_AUTHORITY_SIDECAR = f"._{DEV_CLEANUP_AUTHORITY}"
DEV_CLEANUP_TEMP_SIDECAR_PREFIX = f"._{DEV_CLEANUP_TEMP_PREFIX}"
DEV_CLEANUP_SCHEMA = "bird-dev-cleanup-v1"
MAX_SELECTOR_BYTES = 16 * 1024
CLEANUP_PROTECTED_PATHS = (
    "extlinux/extlinux.previous.conf",
    "extlinux/extlinux.fallback.conf",
    "KERNEL.fallback",
    "dtb.img",
)
STATE_SCHEMA = "bird-dev-state-v2"
LEGACY_STATE_SCHEMA = "bird-dev-state-v1"
MANIFEST_SCHEMA = "bird-deploy-v1"
REQUIRED_HOST_TEST_SET = "bird-dev-host-gate-v1"
CANONICAL_BUILD_TOOLS = {
    "CLANG": "/opt/homebrew/opt/llvm/bin/clang",
    "LLD": "/opt/homebrew/opt/lld/bin/ld.lld",
    "READELF": "/opt/homebrew/opt/llvm/bin/llvm-readelf",
}
CATALOG_IGNORED_DIRECTORY_NAMES = frozenset(("imgs", "images"))
# This exact canonical-builder byte sequence is the reviewed shared-compiler
# extraction introduced with the dev workflow. It is permitted to bootstrap an
# uncommitted checkout; any later canonical-builder edit remains full-release
# work until it receives its own explicit mapping and focused validation.
SAFE_COMPAT_HELPER_EXTRACTION_SHA256 = "15f2d88c002025e256d2e221010b013ade2abb88ebd16936bd310ff7be072e4b"
EXPECTED_INPUTS = {
    "KERNEL",
    "KERNEL.fallback",
    "PortMaster.zip",
    "PortMaster/PortMaster.sh",
    "PortMaster/funcs.txt",
    "PortMaster/harbourmaster",
    "PortMaster/mod_ROCKNIX.txt",
    "PortMaster/pugwash",
    "ROCKNIX-STORAGE",
    "ROCKNIX-SYSTEM",
    "dtb.img",
    "initramfs/busybox",
    "initramfs/init",
    "rocknix-singleadc-joypad.ko",
    "usr/bin/autostart",
}
EARLY_INPUT_DIGESTS = {
    "initramfs/init": "3473415af0cf5df44e70259c3392817b1df421a12a617ec083ec018ff51dbc48",
    "initramfs/busybox": "5ee3d20d8ea5fd9b3ba5109da80599eaf46a5a337d9e40d4c67d28eef44d5dc8",
    "rocknix-singleadc-joypad.ko": "a8ac6cacfa89672fa08dec7fa02179bb108a4a2303fd5c1eb5834f916089b79b",
}

RUNTIME_FILES = (
    "090-ui_service",
    "999-export",
    "bird-autostart",
    "bird-journald.conf",
    "essway.service",
    "rocknix.target",
    "rocknix-automount.service",
    "rocknix-autostart.service",
    "rocknix-report-stats.service",
    "NetworkManager.service",
    "iwd.service",
    "systemd-resolved.service",
    "systemd-timesyncd.service",
    "systemd-rfkill.service",
    "bird-fixed-controls.service",
    "bird-powerstate.service",
    "supervisor.sh",
    "run-content.sh",
    "bird-mpv-player.sh",
    "prepare-ports.sh",
    "verify-portmaster-provider.sh",
    "fixed-storage.sh",
    "first-frame-prep.sh",
    "capture-boot-state.sh",
    "capture-requested-diagnostics.sh",
    "capture-stage5-state.sh",
    "capture-stage5-window-counters.sh",
    "capture-stage5-window.sh",
    "bird-network.sh",
    "bird-fixed-control-exit.sh",
    "bird-emergency-recover.sh",
    "bird-save-config.sh",
    "bird-save-config.service",
    "bird-suspend.sh",
    "bird-restore-suspend-policy.sh",
    "bird-volume.sh",
    "bird-control-osd.sh",
    "bird-fixed-sway.sh",
    "bird-fixed-platform.sh",
    "bird-fixed-logging.sh",
    "bird-fixed-pico8.sh",
    "bird-fixed-controller.sh",
    "bird-fixed-setup.sh",
    "bird-fixed-performance.sh",
    "bird-fixed-gpu-overclock.sh",
    "bird-fixed-rumble.sh",
    "bird-fixed-turbo.sh",
    "bird-controller-profile",
    "bird-swap.conf",
    "bird-suspend-policy.generated.sh",
    "bird-sleep.conf",
    "mpv-input.conf",
)

SCRIPT_RUNTIME_FILES = {
    name
    for name in RUNTIME_FILES
    if name.endswith(".sh") or name in {"090-ui_service", "999-export", "bird-autostart"}
}

GENERATED_DEVICE_PATHS = {
    "launcher/bird-device-contract.h",
    "kernel/rocknix/stock-root/bird-suspend-policy.generated.sh",
    "kernel/rocknix/stock-root/bird-sleep.conf",
    "kernel/rocknix/stock-root/bird-logind.conf",
}

KNOWN_STANDALONE_HOST_TESTS = {
    "test-application-contract.sh",
    "test-build-and-deploy.sh",
    "test-canonical-namespace.sh",
    "test-emergency-recovery.sh",
    "test-fixed-control-exit-publication.sh",
    "test-fixed-controller-profile.py",
    "test-fixed-controls-c.sh",
    "test-launcher-boot-frame.sh",
    "test-launcher-catalog.py",
    "test-launcher-runtime-c.sh",
    "test-mac-removable-device.sh",
    "test-mpv-controls-c.sh",
    "test-portmaster-provider-manifest.py",
    "test-post-flash-transactions.sh",
    "test-stage-zero-contract.py",
    "test-stock-root-brightness.sh",
    "test-stock-root-build-reproducibility.sh",
    "test-stock-root-content-scope.sh",
    "test-stock-root-fixed-autostart.sh",
    "test-stock-root-fixed-housekeeping.sh",
    "test-stock-root-fixed-platform.sh",
    "test-stock-root-fixed-storage.sh",
    "test-stock-root-fixed-sway.sh",
    "test-stock-root-fixed-performance.sh",
    "test-stock-root-fixed-setup.sh",
    "test-stock-root-media-audio-policy.sh",
    "test-stock-root-migration.sh",
    "test-stock-root-mount-storage.sh",
    "test-stock-root-mpv-controls.sh",
    "test-stock-root-prepare-ports.sh",
    "test-stock-root-rom-provider-map.sh",
    "test-stock-root-save-config.sh",
    "test-stock-root-stage5-snapshot.sh",
    "test-stock-root-supervisor.sh",
    "test-stock-root-suspend-policy.sh",
    "test-stock-root-unit-ordering.sh",
    "test-stock-root-updater.sh",
}
BROAD_PRODUCT_HOST_TESTS = frozenset(
    {
        *KNOWN_STANDALONE_HOST_TESTS,
        "test-bird-local-binary.sh",
        "test-dev-build-and-deploy.sh",
    }
)
HOST_HARNESS_RUNNERS = {
    "fixed-controls-host.c": "test-fixed-controls-c.sh",
    "launcher-runtime-host.c": "test-launcher-runtime-c.sh",
    "mpv-controls-host.c": "test-mpv-controls-c.sh",
}

COMPONENT_HOST_TESTS: dict[str, tuple[str, ...]] = {
    "launcher": ("test-bird-local-binary.sh", "test-launcher-runtime-c.sh"),
    "pidwait": ("test-bird-local-binary.sh", "test-stock-root-supervisor.sh"),
    "powerstate": ("test-bird-local-binary.sh", "test-stock-root-unit-ordering.sh"),
    "fixed-controls": (
        "test-bird-local-binary.sh",
        "test-fixed-controls-c.sh",
        "test-stock-root-unit-ordering.sh",
    ),
    "mpv-controls": (
        "test-bird-local-binary.sh",
        "test-mpv-controls-c.sh",
        "test-stock-root-mpv-controls.sh",
    ),
    "device-contract": ("test-stage-zero-contract.py",),
    "catalog": ("test-launcher-catalog.py", "test-stock-root-rom-provider-map.sh"),
    "boot-assets": ("test-launcher-boot-frame.sh", "test-launcher-runtime-c.sh"),
    "early-initramfs": (
        "test-bird-local-binary.sh",
        "test-post-flash-transactions.sh",
        "test-stock-root-brightness.sh",
        "test-stock-root-build-reproducibility.sh",
        "test-stock-root-mount-storage.sh",
    ),
    "selector": ("test-stock-root-build-reproducibility.sh",),
    "post-flash": ("test-post-flash-transactions.sh",),
    "mount-storage": (
        "test-stock-root-mount-storage.sh",
        "test-stock-root-unit-ordering.sh",
    ),
}

_UNIT_SERVICE_FILES = {
    "essway.service",
    "rocknix.target",
    "rocknix-automount.service",
    "rocknix-autostart.service",
    "rocknix-report-stats.service",
    "NetworkManager.service",
    "iwd.service",
    "systemd-resolved.service",
    "systemd-timesyncd.service",
    "systemd-rfkill.service",
    "bird-fixed-controls.service",
    "bird-powerstate.service",
    "bird-save-config.service",
}
for _name in _UNIT_SERVICE_FILES:
    COMPONENT_HOST_TESTS[f"runtime:{_name}"] = ("test-stock-root-unit-ordering.sh",)

COMPONENT_HOST_TESTS.update(
    {
        "runtime:090-ui_service": ("test-stock-root-fixed-setup.sh",),
        "runtime:999-export": (
            "test-application-contract.sh",
            "test-stock-root-content-scope.sh",
        ),
        "runtime:bird-autostart": ("test-stock-root-fixed-autostart.sh",),
        "runtime:bird-journald.conf": ("test-stock-root-mount-storage.sh",),
        "runtime:supervisor.sh": ("test-stock-root-supervisor.sh",),
        "runtime:run-content.sh": (
            "test-application-contract.sh",
            "test-stock-root-content-scope.sh",
            "test-stock-root-media-audio-policy.sh",
            "test-stock-root-mpv-controls.sh",
            "test-stock-root-rom-provider-map.sh",
        ),
        "runtime:bird-mpv-player.sh": (
            "test-stock-root-media-audio-policy.sh",
            "test-stock-root-mpv-controls.sh",
        ),
        "runtime:mpv-input.conf": (
            "test-stock-root-media-audio-policy.sh",
            "test-stock-root-mpv-controls.sh",
        ),
        "runtime:prepare-ports.sh": ("test-stock-root-prepare-ports.sh",),
        "runtime:verify-portmaster-provider.sh": (
            "test-build-and-deploy.sh",
            "test-stock-root-prepare-ports.sh",
        ),
        "runtime:fixed-storage.sh": (
            "test-stock-root-fixed-storage.sh",
            "test-stock-root-prepare-ports.sh",
        ),
        "runtime:first-frame-prep.sh": ("test-stock-root-unit-ordering.sh",),
        "runtime:capture-boot-state.sh": ("test-stock-root-unit-ordering.sh",),
        "runtime:capture-requested-diagnostics.sh": (
            "test-stock-root-stage5-snapshot.sh",
            "test-stock-root-unit-ordering.sh",
        ),
        "runtime:capture-stage5-state.sh": (
            "test-stock-root-stage5-snapshot.sh",
            "test-stock-root-unit-ordering.sh",
        ),
        "runtime:capture-stage5-window-counters.sh": (
            "test-stock-root-stage5-snapshot.sh",
            "test-stock-root-unit-ordering.sh",
        ),
        "runtime:capture-stage5-window.sh": (
            "test-stock-root-stage5-snapshot.sh",
            "test-stock-root-unit-ordering.sh",
        ),
        "runtime:bird-network.sh": ("test-stock-root-content-scope.sh",),
        "runtime:bird-fixed-control-exit.sh": (
            "test-fixed-control-exit-publication.sh",
            "test-stock-root-content-scope.sh",
        ),
        "runtime:bird-emergency-recover.sh": ("test-emergency-recovery.sh",),
        "runtime:bird-save-config.sh": ("test-stock-root-save-config.sh",),
        "runtime:bird-suspend.sh": (
            "test-stock-root-brightness.sh",
            "test-stock-root-unit-ordering.sh",
        ),
        "runtime:bird-restore-suspend-policy.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-suspend-policy.sh",
        ),
        "runtime:bird-volume.sh": ("test-stock-root-media-audio-policy.sh",),
        "runtime:bird-control-osd.sh": ("test-fixed-controls-c.sh",),
        "runtime:bird-fixed-sway.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-sway.sh",
        ),
        "runtime:bird-fixed-platform.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-platform.sh",
        ),
        "runtime:bird-fixed-logging.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-housekeeping.sh",
        ),
        "runtime:bird-fixed-pico8.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-housekeeping.sh",
        ),
        "runtime:bird-fixed-controller.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-setup.sh",
        ),
        "runtime:bird-fixed-setup.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-setup.sh",
        ),
        "runtime:bird-fixed-performance.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-performance.sh",
        ),
        "runtime:bird-fixed-gpu-overclock.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-performance.sh",
        ),
        "runtime:bird-fixed-rumble.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-performance.sh",
        ),
        "runtime:bird-fixed-turbo.sh": (
            "test-stock-root-fixed-autostart.sh",
            "test-stock-root-fixed-performance.sh",
        ),
        "runtime:bird-controller-profile": (
            "test-fixed-controller-profile.py",
            "test-stock-root-fixed-setup.sh",
        ),
        "runtime:bird-swap.conf": ("test-stock-root-mount-storage.sh",),
        "runtime:bird-suspend-policy.generated.sh": (
            "test-stage-zero-contract.py",
            "test-stock-root-mount-storage.sh",
        ),
        "runtime:bird-sleep.conf": (
            "test-stage-zero-contract.py",
            "test-stock-root-mount-storage.sh",
        ),
    }
)


class DevError(RuntimeError):
    """A deliberate fail-closed development workflow error."""


def fail(message: str) -> None:
    raise DevError(message)


def is_dev_release_id(value: str) -> bool:
    """Match the reserved release namespace as FAT will match it."""
    return value.lower() == DEV_RELEASE


def same_filesystem_entry(first: pathlib.Path, second: pathlib.Path) -> bool:
    """Treat one case-insensitive FAT entry as one path, not two aliases."""
    if first == second:
        return True
    try:
        return os.path.samefile(first, second)
    except (FileNotFoundError, OSError):
        return False


def reject_distinct_case_entries(
    parent: pathlib.Path,
    canonical: pathlib.Path,
    normalized_name: str,
    description: str,
) -> None:
    """Allow one differently cased FAT name, never two directory entries."""
    require_directory(parent, f"{description} parent")
    matches = [entry for entry in parent.iterdir() if entry.name.lower() == normalized_name]
    if len(matches) > 1:
        fail(f"multiple case aliases of {description} block cleanup: {matches}")
    if matches and not same_filesystem_entry(matches[0], canonical):
        fail(f"ambiguous case alias of {description} blocks cleanup: {matches[0]}")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(
    command: Sequence[str],
    *,
    cwd: pathlib.Path | None = None,
    env: dict[str, str] | None = None,
    capture: bool = False,
    umask: int = -1,
) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        check=False,
        umask=umask,
    )
    if result.returncode != 0:
        detail = ""
        if capture:
            detail = (result.stderr or result.stdout).decode("utf-8", "replace").strip()
        fail(f"command failed ({result.returncode}): {' '.join(command)}" + (f": {detail}" if detail else ""))
    return result


def safe_relative(value: str) -> str:
    if not value or value.startswith("/") or "\x00" in value or "\t" in value or "\n" in value:
        fail(f"unsafe manifest path: {value!r}")
    path = pathlib.PurePosixPath(value)
    if any(part in {"", ".", ".."} for part in path.parts):
        fail(f"unsafe manifest path: {value!r}")
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", value):
        fail(f"unsafe manifest path: {value!r}")
    return value


def require_regular(path: pathlib.Path, description: str) -> None:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        fail(f"{description} is missing: {path}")
    if not stat.S_ISREG(mode) or path.is_symlink():
        fail(f"{description} is not a safe regular file: {path}")


def require_directory(path: pathlib.Path, description: str) -> None:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        fail(f"{description} is missing: {path}")
    if not stat.S_ISDIR(mode) or path.is_symlink():
        fail(f"{description} is not a safe directory: {path}")


def fixed_directory_chain(root: pathlib.Path, parts: Sequence[str], *, create: bool) -> pathlib.Path:
    current = root
    require_directory(current, "fixed directory root")
    for part in parts:
        if not re.fullmatch(r"[A-Za-z0-9._-]+", part):
            fail(f"unsafe fixed directory component: {part!r}")
        current = current / part
        if current.exists() or current.is_symlink():
            require_directory(current, "fixed directory chain")
        elif create:
            current.mkdir(mode=0o755)
            fsync_directory(current.parent)
        else:
            return current
    return current


def optional_fixed_directory_chain(
    root: pathlib.Path,
    parts: Sequence[str],
) -> pathlib.Path | None:
    """Validate an existing exact chain without shortening a missing path."""
    current = root
    require_directory(current, "fixed directory root")
    for part in parts:
        if not re.fullmatch(r"[A-Za-z0-9._-]+", part):
            fail(f"unsafe fixed directory component: {part!r}")
        current = current / part
        if not current.exists() and not current.is_symlink():
            return None
        require_directory(current, "fixed directory chain")
    return current


def fsync_directory(path: pathlib.Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        try:
            os.fsync(descriptor)
        except OSError as error:
            if error.errno not in {errno.EINVAL, errno.ENOTSUP, errno.EBADF}:
                raise
            # FAT implementations on macOS may not support directory fsync.
            # A global sync is the strongest available fallback.
            os.sync()
    finally:
        os.close(descriptor)


def sync_storage() -> None:
    os.sync()


def remove_appledouble_sibling(path: pathlib.Path) -> None:
    """Remove the FAT sidecar macOS may create while replacing one file."""
    sidecar = path.with_name(f"._{path.name}")
    if not sidecar.exists() and not sidecar.is_symlink():
        return
    require_regular(sidecar, "atomic-write AppleDouble sidecar")
    sidecar.unlink()


def atomic_write(path: pathlib.Path, data: bytes, mode: int = 0o644) -> None:
    require_directory(path.parent, "atomic-write parent")
    temporary = path.parent / f".{path.name}.dev-new.{os.getpid()}"
    if temporary.exists() or temporary.is_symlink():
        fail(f"atomic temporary is occupied: {temporary}")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        view = memoryview(data)
        while view:
            written = os.write(descriptor, view)
            if written <= 0:
                fail(f"short write while publishing {path}")
            view = view[written:]
        os.fsync(descriptor)
    except BaseException:
        os.close(descriptor)
        temporary.unlink(missing_ok=True)
        remove_appledouble_sibling(temporary)
        raise
    else:
        os.close(descriptor)
    if temporary.read_bytes() != data:
        temporary.unlink(missing_ok=True)
        remove_appledouble_sibling(temporary)
        fail(f"atomic temporary verification failed: {path}")
    try:
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        remove_appledouble_sibling(temporary)
        raise
    remove_appledouble_sibling(temporary)
    remove_appledouble_sibling(path)
    fsync_directory(path.parent)
    if path.read_bytes() != data:
        fail(f"atomic publication verification failed: {path}")


def atomic_write_if_changed(path: pathlib.Path, data: bytes, mode: int = 0o644) -> bool:
    """Publish data atomically only when the destination bytes differ."""
    if path.exists() or path.is_symlink():
        require_regular(path, "atomic-write destination")
        if path.read_bytes() == data:
            return False
    atomic_write(path, data, mode)
    return True


def remove_appledouble(root: pathlib.Path) -> None:
    for path in sorted(root.rglob("._*"), reverse=True):
        if path.is_symlink() or not path.is_file():
            fail(f"unsafe AppleDouble path in dev release: {path}")
        path.unlink()


@dataclasses.dataclass(frozen=True)
class SourceIdentity:
    commit: str
    state: str
    inventory: dict[str, tuple[str, int, int, str]]
    inventory_bytes: bytes


def git_bytes(root: pathlib.Path, *arguments: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(root), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        fail(
            f"could not read source identity: git {' '.join(arguments)}: "
            f"{result.stderr.decode('utf-8', 'replace').strip()}"
        )
    return result.stdout


def inventory_entry(root: pathlib.Path, relative: str) -> tuple[str, int, int, str]:
    path = root / relative
    try:
        info = path.lstat()
    except FileNotFoundError:
        return ("missing", 0, 0, "-")
    mode = stat.S_IMODE(info.st_mode)
    if stat.S_ISREG(info.st_mode):
        return ("file", mode, info.st_size, sha256_file(path))
    if stat.S_ISLNK(info.st_mode):
        target = os.readlink(path).encode("utf-8", "surrogateescape")
        return ("symlink", mode, len(target), sha256_bytes(target))
    return ("special", mode, info.st_size, "-")


def capture_source_identity(root: pathlib.Path) -> SourceIdentity:
    commit = git_bytes(root, "rev-parse", "--verify", "HEAD").decode().strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        fail("source commit is not a full lowercase object ID")
    status = git_bytes(root, "status", "--porcelain", "--untracked-files=normal").decode(
        "utf-8", "surrogateescape"
    ).rstrip("\n")
    untracked = sorted(
        item
        for item in git_bytes(root, "ls-files", "--others", "--exclude-standard", "-z")
        .decode("utf-8", "surrogateescape")
        .split("\0")
        if item
    )
    fingerprint = bytearray((status + "\n").encode("utf-8", "surrogateescape"))
    fingerprint.extend(git_bytes(root, "diff", "--binary", "HEAD", "--"))
    for relative in untracked:
        kind, mode, size, digest = inventory_entry(root, relative)
        if kind == "file":
            fingerprint.extend(
                f"untracked\t{relative}\t{mode:o}\t{size}\t{digest}\n".encode(
                    "utf-8", "surrogateescape"
                )
            )
    state = "clean" if not status else f"dirty:{sha256_bytes(bytes(fingerprint))}"

    paths = set(
        item
        for item in git_bytes(root, "ls-files", "-c", "-o", "--exclude-standard", "-z")
        .decode("utf-8", "surrogateescape")
        .split("\0")
        if item
    )
    inventory = {relative: inventory_entry(root, relative) for relative in sorted(paths)}
    lines = ["schema\tbird-source-inventory-v1"]
    for relative, (kind, mode, size, digest) in inventory.items():
        lines.append(f"path\t{relative}\t{kind}\t{mode:o}\t{size}\t{digest}")
    inventory_bytes = ("\n".join(lines) + "\n").encode("utf-8", "surrogateescape")
    return SourceIdentity(commit, state, inventory, inventory_bytes)


def dirty_paths(root: pathlib.Path) -> set[str]:
    raw = git_bytes(root, "status", "--porcelain", "-z", "--untracked-files=all")
    records = raw.decode("utf-8", "surrogateescape").split("\0")
    paths: set[str] = set()
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if not record:
            continue
        if len(record) < 4:
            fail("could not parse source status")
        status = record[:2]
        paths.add(record[3:])
        if "R" in status or "C" in status:
            if index >= len(records) or not records[index]:
                fail("could not parse renamed source status")
            paths.add(records[index])
            index += 1
    return paths


def committed_paths_since(root: pathlib.Path, base_commit: str, head_commit: str) -> set[str]:
    if base_commit == head_commit:
        return set()
    exists = subprocess.run(
        ["git", "-C", str(root), "cat-file", "-e", f"{base_commit}^{{commit}}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if exists.returncode != 0:
        fail("base release source commit is unavailable locally; use the full release workflow")
    ancestor = subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor", base_commit, head_commit],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if ancestor.returncode != 0:
        fail("base release source commit is not an ancestor of HEAD; use the full release workflow")
    commits = [
        value
        for value in git_bytes(
            root,
            "rev-list",
            "--reverse",
            "--topo-order",
            f"{base_commit}..{head_commit}",
        )
        .decode("ascii")
        .splitlines()
        if value
    ]
    paths: set[str] = set()
    for commit in commits:
        # Inspect each commit rather than only the endpoint trees. This keeps a
        # production-boundary path authoritative even when a later commit
        # reverts its bytes. -m deliberately compares a merge result with every
        # parent; --no-renames deliberately reports both sides of a rename.
        raw = git_bytes(
            root,
            "diff-tree",
            "--root",
            "--no-commit-id",
            "--name-only",
            "-r",
            "-m",
            "--no-renames",
            "-z",
            commit,
        )
        paths.update(
            value
            for value in raw.decode("utf-8", "surrogateescape").split("\0")
            if value
        )
    return paths


def parse_inventory(data: bytes) -> dict[str, tuple[str, int, int, str]]:
    lines = data.decode("utf-8", "surrogateescape").splitlines()
    if not lines or lines[0] != "schema\tbird-source-inventory-v1":
        fail("saved source inventory has an invalid schema")
    result: dict[str, tuple[str, int, int, str]] = {}
    for line in lines[1:]:
        fields = line.split("\t")
        if len(fields) != 6 or fields[0] != "path" or fields[1] in result:
            fail("saved source inventory is malformed")
        try:
            mode = int(fields[3], 8)
            size = int(fields[4])
        except ValueError:
            fail("saved source inventory has invalid numeric fields")
        result[fields[1]] = (fields[2], mode, size, fields[5])
    return result


@dataclasses.dataclass
class Manifest:
    release: str
    source_commit: str
    source_state: str
    inputs: list[str]
    dirs: list[tuple[str, str]]
    files: list[tuple[str, str, int, str]]
    artifacts: dict[str, tuple[str, str]]

    @property
    def file_modes(self) -> dict[str, str]:
        return {path: mode for path, mode, _size, _digest in self.files}

    @property
    def input_digests(self) -> dict[str, str]:
        return {line.split("\t")[1]: line.split("\t")[4] for line in self.inputs}


def parse_manifest(path: pathlib.Path, expected_release: str | None = None) -> Manifest:
    require_regular(path, "deploy manifest")
    schema = release = policy = source = 0
    release_id = source_commit = source_state = ""
    inputs: list[str] = []
    input_names: set[str] = set()
    dirs: list[tuple[str, str]] = []
    files: list[tuple[str, str, int, str]] = []
    paths: set[str] = set()
    artifacts: dict[str, tuple[str, str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        kind = fields[0] if fields else ""
        if kind == "schema" and len(fields) == 2 and fields[1] == MANIFEST_SCHEMA:
            schema += 1
        elif kind == "release" and len(fields) == 2:
            release += 1
            release_id = fields[1]
        elif kind == "target-mode-policy" and fields == ["target-mode-policy", "fat-capability"]:
            policy += 1
        elif kind == "source-commit" and len(fields) == 3:
            source += 1
            source_commit, source_state = fields[1], fields[2]
        elif kind == "artifact" and len(fields) == 4:
            name, artifact_path, digest = fields[1:]
            if name not in {"device-contract", "catalog"} or name in artifacts:
                fail("deploy manifest has invalid artifact records")
            safe_relative(artifact_path)
            if not re.fullmatch(r"[0-9a-f]{64}", digest):
                fail("deploy manifest has an invalid artifact digest")
            artifacts[name] = (artifact_path, digest)
        elif kind == "input" and len(fields) == 6:
            name = safe_relative(fields[1])
            if name in input_names or not re.fullmatch(r"[0-7]{3}", fields[2]):
                fail("deploy manifest has invalid input records")
            if not fields[3].isdigit() or not re.fullmatch(r"[0-9a-f]{64}", fields[4]) or not fields[5]:
                fail("deploy manifest has invalid input records")
            input_names.add(name)
            inputs.append(line)
        elif kind == "dir" and len(fields) == 3:
            relative = safe_relative(fields[1])
            if relative in paths or not re.fullmatch(r"[0-7]{3}", fields[2]):
                fail("deploy manifest has invalid directory records")
            paths.add(relative)
            dirs.append((relative, fields[2]))
        elif kind == "file" and len(fields) == 5:
            relative = safe_relative(fields[1])
            if relative in paths or not re.fullmatch(r"[0-7]{3}", fields[2]):
                fail("deploy manifest has invalid file records")
            if not fields[3].isdigit() or not re.fullmatch(r"[0-9a-f]{64}", fields[4]):
                fail("deploy manifest has invalid file records")
            paths.add(relative)
            files.append((relative, fields[2], int(fields[3]), fields[4]))
        else:
            fail(f"deploy manifest is malformed at record: {line!r}")
    if (schema, release, policy, source) != (1, 1, 1, 1):
        fail("deploy manifest has duplicate or missing authority records")
    if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        fail("deploy manifest source commit is not a full lowercase object ID")
    if source_state != "clean" and not re.fullmatch(r"dirty:[0-9a-f]{64}", source_state):
        fail("deploy manifest source state is invalid")
    if expected_release is not None and release_id != expected_release:
        fail(f"deploy manifest release mismatch: expected {expected_release}, got {release_id}")
    if input_names != EXPECTED_INPUTS or len(inputs) != 15:
        fail("deploy manifest external-input set changed")
    if set(artifacts) != {"device-contract", "catalog"}:
        fail("deploy manifest artifact set changed")
    if artifacts["device-contract"][0] != "bird/bird-device-contract.tsv":
        fail("deploy manifest device-contract path changed")
    if artifacts["catalog"][0] != "launcher/catalog.generated.h":
        fail("deploy manifest catalog path changed")
    return Manifest(release_id, source_commit, source_state, inputs, dirs, files, artifacts)


def verify_early_input_compatibility(manifest: Manifest) -> None:
    for name, expected in EARLY_INPUT_DIGESTS.items():
        actual = manifest.input_digests.get(name)
        if actual != expected:
            fail(
                f"base release input {name} does not match the pinned external-initramfs builder; "
                "use the full release workflow"
            )


def effective_mode_ok(path: pathlib.Path, intended: str, synthetic: bool) -> bool:
    if synthetic:
        owner = int(intended[0])
        if not os.access(path, os.R_OK):
            return False
        if owner & 2 and not os.access(path, os.W_OK):
            return False
        if owner & 1 and not os.access(path, os.X_OK):
            return False
        return True
    return stat.S_IMODE(path.stat().st_mode) == int(intended, 8)


def verify_release(
    root: pathlib.Path,
    release_id: str,
    synthetic_modes: bool,
    *,
    require_complete: bool = True,
) -> Manifest:
    require_directory(root, f"release {release_id}")
    manifest_path = root / "deploy-manifest.tsv"
    complete_path = root / ".complete"
    require_regular(manifest_path, "release manifest")
    if require_complete:
        require_regular(complete_path, "release completion marker")
        marker = complete_path.read_text(encoding="ascii").strip()
        if not re.fullmatch(r"[0-9a-f]{64}", marker) or sha256_file(manifest_path) != marker:
            fail(f"release is incomplete or its completion marker changed: {release_id}")
    elif complete_path.exists() or complete_path.is_symlink():
        fail(f"precommit release unexpectedly has a completion marker: {release_id}")
    manifest = parse_manifest(manifest_path, release_id)
    expected_files: set[str] = set()
    for relative, mode, size, digest in manifest.files:
        target = root / relative
        require_regular(target, f"release file {release_id}/{relative}")
        if target.stat().st_size != size or sha256_file(target) != digest:
            fail(f"release file changed: {release_id}/{relative}")
        if not effective_mode_ok(target, mode, synthetic_modes):
            fail(f"release file mode contract failed: {release_id}/{relative}")
        expected_files.add(relative)
    for relative, mode in manifest.dirs:
        target = root / relative
        require_directory(target, f"release directory {release_id}/{relative}")
        if not effective_mode_ok(target, mode, synthetic_modes):
            fail(f"release directory mode contract failed: {release_id}/{relative}")
    actual_files: set[str] = set()
    for target in root.rglob("*"):
        relative = target.relative_to(root).as_posix()
        info = target.lstat()
        if stat.S_ISLNK(info.st_mode) or not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
            fail(f"release contains a symlink or special node: {release_id}/{relative}")
        if stat.S_ISREG(info.st_mode) and relative not in {"deploy-manifest.tsv", ".complete"}:
            actual_files.add(relative)
    if actual_files != expected_files:
        missing = sorted(expected_files - actual_files)
        extra = sorted(actual_files - expected_files)
        fail(f"release file inventory differs from manifest: missing={missing} extra={extra}")
    actual_empty = {
        target.relative_to(root).as_posix()
        for target in root.rglob("*")
        if target.is_dir() and not any(target.iterdir())
    }
    expected_empty = {relative for relative, _mode in manifest.dirs}
    if actual_empty != expected_empty:
        fail(f"release empty-directory inventory differs from manifest: {release_id}")
    contract_file = root / "bird/bird-device-contract.tsv"
    if sha256_file(contract_file) != manifest.artifacts["device-contract"][1]:
        fail(f"release device-contract artifact binding changed: {release_id}")
    return manifest


def release_snapshot(root: pathlib.Path) -> dict[str, tuple[str, int, str]]:
    result: dict[str, tuple[str, int, str]] = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        info = path.lstat()
        if stat.S_ISREG(info.st_mode):
            result[relative] = ("file", info.st_size, sha256_file(path))
        elif stat.S_ISDIR(info.st_mode):
            result[relative] = ("dir", 0, "")
        elif stat.S_ISLNK(info.st_mode):
            result[relative] = ("symlink", 0, os.readlink(path))
        else:
            result[relative] = ("special", 0, "")
    return result


def verify_safe_removal_tree(root: pathlib.Path, description: str) -> None:
    require_directory(root, description)
    for path in root.rglob("*"):
        info = path.lstat()
        if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
            fail(f"{description} contains a symlink or special node: {path}")


def parse_selector(data: bytes) -> str | None:
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        fail("selector is not ASCII")
    matches = re.findall(r"(?<!\S)bird_release=([A-Za-z0-9._-]+)(?=\s|$)", text)
    if not matches:
        return None
    if len(matches) != 1:
        fail("selector does not contain exactly one Bird release ID")
    return matches[0]


def verify_selector_for_release(data: bytes, release_id: str) -> None:
    if parse_selector(data) != release_id:
        fail(f"selector does not name release exactly: {release_id}")
    text = data.decode("ascii")
    required = (
        f"LINUX /bird-releases/{release_id}/KERNEL",
        f"INITRD /bird-releases/{release_id}/bird-initramfs.cpio.gz",
        f"FDT /bird-releases/{release_id}/dtb.img",
    )
    if any(text.count(value) != 1 for value in required):
        fail(f"selector paths do not name release exactly: {release_id}")


@dataclasses.dataclass(frozen=True)
class CleanupAuthority:
    base_release: str
    selector: bytes
    manifest_sha: str
    protected: tuple[tuple[str, bool, int, str], ...]


def cleanup_authority_bytes(
    release_id: str,
    selector: bytes,
    manifest_sha: str,
    protected: tuple[tuple[str, bool, int, str], ...],
) -> bytes:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", release_id):
        fail("cleanup authority has an unsafe production release ID")
    if is_dev_release_id(release_id):
        fail("cleanup authority cannot name mutable dev-current")
    if not selector or len(selector) > MAX_SELECTOR_BYTES:
        fail("cleanup authority selector size is outside the fixed safety bound")
    if not re.fullmatch(r"[0-9a-f]{64}", manifest_sha):
        fail("cleanup authority has an invalid production manifest digest")
    if tuple(path for path, _exists, _size, _digest in protected) != CLEANUP_PROTECTED_PATHS:
        fail("cleanup authority protected-file inventory changed")
    verify_selector_for_release(selector, release_id)
    prefix = (
        f"schema\t{DEV_CLEANUP_SCHEMA}\n"
        f"base-release\t{release_id}\n"
        f"base-manifest-sha256\t{manifest_sha}\n"
        f"base-selector-bytes\t{len(selector)}\n"
        f"base-selector-sha256\t{sha256_bytes(selector)}\n"
        f"base-selector-hex\t{selector.hex()}\n"
    )
    protected_lines: list[str] = []
    for relative, exists, size, digest in protected:
        if exists:
            if size < 0 or not re.fullmatch(r"[0-9a-f]{64}", digest):
                fail("cleanup authority has an invalid protected-file record")
            protected_lines.append(
                f"protected\t{relative}\tpresent\t{size}\t{digest}\n"
            )
        else:
            if size != 0 or digest:
                fail("cleanup authority has an invalid missing-file record")
            protected_lines.append(f"protected\t{relative}\tmissing\t0\t-\n")
    return (prefix + "".join(protected_lines)).encode("ascii")


def parse_cleanup_authority(path: pathlib.Path) -> CleanupAuthority:
    require_regular(path, "development cleanup authority")
    maximum_record_bytes = (MAX_SELECTOR_BYTES * 2) + 1024
    if path.stat().st_size > maximum_record_bytes:
        fail("development cleanup authority exceeds its fixed size bound")
    raw = path.read_bytes()
    if not raw.endswith(b"\n") or b"\r" in raw or b"\0" in raw:
        fail("development cleanup authority is not canonical TSV")
    try:
        lines = raw.decode("ascii").splitlines()
    except UnicodeDecodeError:
        fail("development cleanup authority is not ASCII")
    if len(lines) != 6 + len(CLEANUP_PROTECTED_PATHS):
        fail("development cleanup authority has an invalid record count")
    fields: list[tuple[str, str]] = []
    for line in lines[:6]:
        parts = line.split("\t")
        if len(parts) != 2:
            fail("development cleanup authority is malformed")
        fields.append((parts[0], parts[1]))
    expected_names = (
        "schema",
        "base-release",
        "base-manifest-sha256",
        "base-selector-bytes",
        "base-selector-sha256",
        "base-selector-hex",
    )
    if tuple(name for name, _value in fields) != expected_names:
        fail("development cleanup authority has unknown, duplicate, or reordered fields")
    values = {name: value for name, value in fields}
    if values["schema"] != DEV_CLEANUP_SCHEMA:
        fail("development cleanup authority has an invalid schema")
    release_id = values["base-release"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", release_id):
        fail("development cleanup authority has an unsafe production release ID")
    if is_dev_release_id(release_id):
        fail("development cleanup authority names mutable dev-current")
    manifest_sha = values["base-manifest-sha256"]
    if not re.fullmatch(r"[0-9a-f]{64}", manifest_sha):
        fail("development cleanup authority has an invalid production manifest digest")
    if not re.fullmatch(r"[0-9]+", values["base-selector-bytes"]):
        fail("development cleanup authority has an invalid selector size")
    selector_size = int(values["base-selector-bytes"])
    if selector_size <= 0 or selector_size > MAX_SELECTOR_BYTES:
        fail("development cleanup authority selector size is outside the fixed safety bound")
    if not re.fullmatch(r"[0-9a-f]{64}", values["base-selector-sha256"]):
        fail("development cleanup authority has an invalid selector digest")
    selector_hex = values["base-selector-hex"]
    if len(selector_hex) != selector_size * 2 or not re.fullmatch(r"[0-9a-f]+", selector_hex):
        fail("development cleanup authority has an invalid selector encoding")
    selector = bytes.fromhex(selector_hex)
    if sha256_bytes(selector) != values["base-selector-sha256"]:
        fail("development cleanup authority selector digest changed")
    protected: list[tuple[str, bool, int, str]] = []
    for expected_path, line in zip(CLEANUP_PROTECTED_PATHS, lines[6:], strict=True):
        parts = line.split("\t")
        if len(parts) != 5 or parts[0] != "protected" or parts[1] != expected_path:
            fail("development cleanup authority protected-file inventory changed")
        state, size_text, digest = parts[2:]
        if not re.fullmatch(r"[0-9]+", size_text):
            fail("development cleanup authority has an invalid protected-file size")
        size = int(size_text)
        if state == "present":
            if not re.fullmatch(r"[0-9a-f]{64}", digest):
                fail("development cleanup authority has an invalid protected-file digest")
            protected.append((expected_path, True, size, digest))
        elif state == "missing" and size == 0 and digest == "-":
            protected.append((expected_path, False, 0, ""))
        else:
            fail("development cleanup authority has an invalid protected-file state")
    verify_selector_for_release(selector, release_id)
    authority = CleanupAuthority(release_id, selector, manifest_sha, tuple(protected))
    if raw != cleanup_authority_bytes(
        authority.base_release,
        authority.selector,
        authority.manifest_sha,
        authority.protected,
    ):
        fail("development cleanup authority is not canonically encoded")
    return authority


@dataclasses.dataclass
class DevState:
    activation: str
    base_release: str
    base_selector_sha: str
    repository_commit: str
    source_state: str
    profile: str
    manifest_sha: str
    inventory_sha: str
    last_build_kind: str
    all_local_inventory_sha: str
    host_test_inventory_sha: str
    host_test_set: str
    components: dict[str, str]


def load_state(state_path: pathlib.Path) -> DevState | None:
    if not state_path.exists() and not state_path.is_symlink():
        return None
    require_regular(state_path, "dev state")
    singles: dict[str, str] = {}
    components: dict[str, str] = {}
    for line in state_path.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) == 2 and fields[0] != "component":
            if fields[0] in singles:
                fail("dev state has duplicate fields")
            singles[fields[0]] = fields[1]
        elif len(fields) == 3 and fields[0] == "component":
            if fields[1] in components or not re.fullmatch(r"[0-9a-f]{64}", fields[2]):
                fail("dev state has malformed component fingerprints")
            components[fields[1]] = fields[2]
        else:
            fail("dev state is malformed")
    required = {
        "schema",
        "activation",
        "dev-release",
        "base-release",
        "base-selector-sha256",
        "repository-commit",
        "source-state",
        "profile",
        "manifest-sha256",
        "source-inventory-sha256",
    }
    schema = singles.get("schema")
    if schema == STATE_SCHEMA:
        required.update(
            {
                "last-build-kind",
                "all-local-source-inventory-sha256",
                "host-test-source-inventory-sha256",
                "host-test-set",
            }
        )
    elif schema != LEGACY_STATE_SCHEMA:
        fail("dev state has an invalid schema")
    if set(singles) != required:
        fail("dev state has an invalid schema")
    if singles["dev-release"] != DEV_RELEASE or singles["activation"] not in {"complete", "incomplete"}:
        fail("dev state identity is invalid")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", singles["base-release"]):
        fail("dev state base release is invalid")
    if is_dev_release_id(singles["base-release"]):
        fail("dev state base release aliases mutable dev-current")
    if not re.fullmatch(r"[0-9a-f]{40}", singles["repository-commit"]):
        fail("dev state repository commit is invalid")
    if singles["source-state"] != "clean" and not re.fullmatch(
        r"dirty:[0-9a-f]{64}", singles["source-state"]
    ):
        fail("dev state source state is invalid")
    if singles["profile"] not in {"release", "profile"}:
        fail("dev state profile is invalid")
    for field in ("base-selector-sha256",):
        if not re.fullmatch(r"[0-9a-f]{64}", singles[field]):
            fail(f"dev state has an invalid {field}")
    for field in ("manifest-sha256", "source-inventory-sha256"):
        if singles[field] != "pending" and not re.fullmatch(r"[0-9a-f]{64}", singles[field]):
            fail(f"dev state has an invalid {field}")
    if schema == STATE_SCHEMA:
        if singles["last-build-kind"] not in {"changed", "all-local", "rebase"}:
            fail("dev state has an invalid last build kind")
        for field in (
            "all-local-source-inventory-sha256",
            "host-test-source-inventory-sha256",
        ):
            if singles[field] != "none" and not re.fullmatch(r"[0-9a-f]{64}", singles[field]):
                fail(f"dev state has an invalid {field}")
        if not re.fullmatch(r"bird-dev-host-gate-v[0-9]+|none", singles["host-test-set"]):
            fail("dev state has an invalid host test set")
        if (singles["host-test-source-inventory-sha256"] == "none") != (
            singles["host-test-set"] == "none"
        ):
            fail("dev state host test authority is incomplete")
        last_build_kind = singles["last-build-kind"]
        all_local_inventory_sha = singles["all-local-source-inventory-sha256"]
        host_test_inventory_sha = singles["host-test-source-inventory-sha256"]
        host_test_set = singles["host-test-set"]
    else:
        # v1 remains recoverable and can still be rolled back, cleaned, or
        # rebased. It deliberately carries no claim that the newer all-local
        # and host-test readiness gates were completed.
        last_build_kind = "unknown"
        all_local_inventory_sha = "none"
        host_test_inventory_sha = "none"
        host_test_set = "none"
    if singles["activation"] == "complete":
        expected_components = all_component_groups() | {"authority:toolchain"}
        if set(components) != expected_components:
            fail("complete dev state has an incomplete component fingerprint set")
        if singles["manifest-sha256"] == "pending" or singles["source-inventory-sha256"] == "pending":
            fail("complete dev state retains pending authority digests")
    elif set(components) != {"authority:toolchain"}:
        fail("incomplete dev state lacks its toolchain authority fingerprint")
    return DevState(
        singles["activation"],
        singles["base-release"],
        singles["base-selector-sha256"],
        singles["repository-commit"],
        singles["source-state"],
        singles["profile"],
        singles["manifest-sha256"],
        singles["source-inventory-sha256"],
        last_build_kind,
        all_local_inventory_sha,
        host_test_inventory_sha,
        host_test_set,
        components,
    )


def state_bytes(state: DevState) -> bytes:
    lines = [
        f"schema\t{STATE_SCHEMA}",
        f"activation\t{state.activation}",
        f"dev-release\t{DEV_RELEASE}",
        f"base-release\t{state.base_release}",
        f"base-selector-sha256\t{state.base_selector_sha}",
        f"repository-commit\t{state.repository_commit}",
        f"source-state\t{state.source_state}",
        f"profile\t{state.profile}",
        f"manifest-sha256\t{state.manifest_sha}",
        f"source-inventory-sha256\t{state.inventory_sha}",
        f"last-build-kind\t{state.last_build_kind}",
        f"all-local-source-inventory-sha256\t{state.all_local_inventory_sha}",
        f"host-test-source-inventory-sha256\t{state.host_test_inventory_sha}",
        f"host-test-set\t{state.host_test_set}",
    ]
    for name, digest in sorted(state.components.items()):
        lines.append(f"component\t{name}\t{digest}")
    return ("\n".join(lines) + "\n").encode()


def changed_inventory_paths(
    previous: dict[str, tuple[str, int, int, str]],
    current: dict[str, tuple[str, int, int, str]],
) -> set[str]:
    return {
        path
        for path in set(previous) | set(current)
        if previous.get(path) != current.get(path)
    }


def source_hash(root: pathlib.Path, paths: Iterable[str], values: Iterable[str] = ()) -> str:
    digest = hashlib.sha256()
    for value in values:
        digest.update(b"value\0" + value.encode() + b"\0")
    for relative in sorted(set(paths)):
        kind, mode, size, file_digest = inventory_entry(root, relative)
        digest.update(
            f"{relative}\0{kind}\0{mode:o}\0{size}\0{file_digest}\n".encode(
                "utf-8", "surrogateescape"
            )
        )
    return digest.hexdigest()


def resolved_tool_identity(name: str, configured: str | None = None) -> str:
    candidate = configured or shutil.which(name)
    if not candidate:
        return f"{name}\tmissing"
    path = pathlib.Path(candidate).expanduser()
    try:
        resolved = path.resolve(strict=True)
        info = resolved.lstat()
    except (FileNotFoundError, OSError):
        return f"{name}\tmissing\t{candidate}"
    if not stat.S_ISREG(info.st_mode):
        return f"{name}\tunsafe\t{resolved}"
    return f"{name}\t{resolved}\t{info.st_size}\t{sha256_file(resolved)}"


def build_tool_configuration(host_test: bool) -> dict[str, str]:
    if not host_test:
        return dict(CANONICAL_BUILD_TOOLS)
    return {
        name: os.environ.get(name, canonical)
        for name, canonical in CANONICAL_BUILD_TOOLS.items()
    }


def reject_ambient_build_tool_overrides(host_test: bool) -> None:
    if host_test:
        return
    overridden = sorted(name for name in CANONICAL_BUILD_TOOLS if name in os.environ)
    if overridden:
        fail(
            "ambient compiler override is not permitted for the canonical development "
            f"toolchain: {','.join(overridden)}"
        )


def build_toolchain_fingerprint(host_test: bool) -> str:
    tools = build_tool_configuration(host_test)
    identities = (
        resolved_tool_identity("clang", tools["CLANG"]),
        resolved_tool_identity("ld.lld", tools["LLD"]),
        resolved_tool_identity("llvm-readelf", tools["READELF"]),
        resolved_tool_identity("cpio"),
        resolved_tool_identity("gzip"),
    )
    return sha256_bytes(("\n".join(identities) + "\n").encode())


def catalog_path_is_hidden_or_artwork(relative: pathlib.Path) -> bool:
    """Mirror the canonical generator's macOS-metadata/artwork exclusion."""
    return any(
        part.startswith(".")
        or part.startswith("._")
        or part.casefold() in CATALOG_IGNORED_DIRECTORY_NAMES
        for part in relative.parts
    )


def catalog_card_inventory(data: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for name in ("ROMS", "MEDIA"):
        root = data / name
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            relative_to_catalog_root = path.relative_to(root)
            if catalog_path_is_hidden_or_artwork(relative_to_catalog_root):
                continue
            # PortMaster keeps mutable saves, configuration, libraries and
            # game data beneath ROMS/Ports/<game>/.  The canonical catalog
            # generator deliberately inspects only direct children of Ports,
            # so those nested runtime bytes cannot change the menu catalog.
            if name == "ROMS" and relative_to_catalog_root.parts[0].casefold() == "ports":
                # Only regular, top-level .sh launchers are PortMaster menu
                # candidates. The Ports directory itself, game directories,
                # non-launcher metadata and all nested runtime state are not.
                if (
                    len(relative_to_catalog_root.parts) != 2
                    or path.suffix.casefold() != ".sh"
                ):
                    continue
            relative = path.relative_to(data).as_posix()
            info = path.lstat()
            if stat.S_ISREG(info.st_mode):
                kind = "file"
            elif stat.S_ISDIR(info.st_mode):
                kind = "dir"
            else:
                fail(f"catalog source contains a symlink or special node: {path}")
            digest.update(f"{kind}\t{relative}\n".encode("utf-8", "surrogateescape"))
    return digest.hexdigest()


def require_repository_file(root: pathlib.Path, relative: str) -> None:
    safe_relative(relative)
    current = root
    for part in pathlib.PurePosixPath(relative).parts[:-1]:
        current = current / part
        require_directory(current, f"repository source parent for {relative}")
    require_regular(root / relative, f"repository source {relative}")


def validate_component_sources(root: pathlib.Path, groups: set[str]) -> None:
    paths: set[str] = set()
    if groups:
        paths.update(
            {
                "bird-device-contract.tsv",
                "generate-device-contract.py",
                *GENERATED_DEVICE_PATHS,
            }
        )
    launcher_common = {
        "kernel/rocknix/build-bird-local-binary.sh",
        "launcher/bird-launcher.c",
        "launcher/bird-device-contract.h",
        "launcher/catalog.generated.h",
        "bird-device-contract.tsv",
    }
    if groups & {"launcher", "early-initramfs", "catalog"}:
        paths.update(
            {
                "generate-launcher-catalog.py",
                "launcher/catalog.generated.h",
                "launcher/library.inventory.tsv",
            }
        )
    if "launcher" in groups:
        paths.update(launcher_common)
    if "pidwait" in groups:
        paths.update({"kernel/rocknix/build-bird-local-binary.sh", "launcher/bird-pidwait.c"})
    if "powerstate" in groups:
        paths.update({"kernel/rocknix/build-bird-local-binary.sh", "launcher/bird-powerstate.c"})
    if "fixed-controls" in groups:
        paths.update(
            {
                "kernel/rocknix/build-bird-local-binary.sh",
                "kernel/rocknix/stock-root/bird-fixed-controls.c",
                "launcher/bird-device-contract.h",
            }
        )
    if "mpv-controls" in groups:
        paths.update(
            {
                "kernel/rocknix/build-bird-local-binary.sh",
                "kernel/rocknix/stock-root/bird-mpv-controls.c",
                "launcher/bird-device-contract.h",
            }
        )
    if "early-initramfs" in groups:
        paths.update(
            {
                *launcher_common,
                "kernel/rocknix/build-stock-root-early-initramfs.sh",
                "kernel/rocknix/stock-root/bird-early.sh",
                "kernel/rocknix/stock-root/bird-release-loader.sh",
                "firmware/normalize-newc.py",
                "firmware/generate-launcher-bootlogo.py",
                "firmware/assets/bird-launcher-backdrop.png",
            }
        )
    if "boot-assets" in groups:
        paths.update(
            {
                "firmware/generate-launcher-bootlogo.py",
                "firmware/assets/bird-launcher-backdrop.png",
            }
        )
    direct = {
        "selector": "kernel/rocknix/stock-root/extlinux.conf",
        "post-flash": "kernel/rocknix/stock-root/post-flash.sh",
        "mount-storage": "kernel/rocknix/stock-root/mount-storage.sh",
    }
    for group in groups:
        if group in direct:
            paths.add(direct[group])
        elif group.startswith("runtime:"):
            paths.add("kernel/rocknix/stock-root/" + group.removeprefix("runtime:"))
    for relative in sorted(paths):
        require_repository_file(root, relative)


def component_fingerprints(
    root: pathlib.Path,
    data: pathlib.Path,
    profile: str,
    host_test: bool,
) -> dict[str, str]:
    helper = "kernel/rocknix/build-bird-local-binary.sh"
    launcher_common = [
        helper,
        "launcher/bird-launcher.c",
        "launcher/bird-device-contract.h",
        "launcher/catalog.generated.h",
        "bird-device-contract.tsv",
    ]
    result = {
        "authority:toolchain": build_toolchain_fingerprint(host_test),
        "launcher": source_hash(root, launcher_common, [profile]),
        "pidwait": source_hash(root, [helper, "launcher/bird-pidwait.c"]),
        "powerstate": source_hash(root, [helper, "launcher/bird-powerstate.c"]),
        "fixed-controls": source_hash(
            root,
            [helper, "kernel/rocknix/stock-root/bird-fixed-controls.c", "launcher/bird-device-contract.h"],
        ),
        "mpv-controls": source_hash(
            root,
            [helper, "kernel/rocknix/stock-root/bird-mpv-controls.c", "launcher/bird-device-contract.h"],
        ),
        "device-contract": source_hash(
            root,
            ["bird-device-contract.tsv", "generate-device-contract.py", *GENERATED_DEVICE_PATHS],
        ),
        "catalog": source_hash(
            root,
            [
                "generate-launcher-catalog.py",
                "launcher/catalog.generated.h",
                "launcher/library.inventory.tsv",
            ],
            [catalog_card_inventory(data)],
        ),
        "boot-assets": source_hash(
            root,
            ["firmware/generate-launcher-bootlogo.py", "firmware/assets/bird-launcher-backdrop.png"],
        ),
        "early-initramfs": source_hash(
            root,
            [
                helper,
                "kernel/rocknix/build-stock-root-early-initramfs.sh",
                "kernel/rocknix/stock-root/bird-early.sh",
                "kernel/rocknix/stock-root/bird-release-loader.sh",
                "firmware/normalize-newc.py",
                "firmware/generate-launcher-bootlogo.py",
                "firmware/assets/bird-launcher-backdrop.png",
                *launcher_common,
            ],
            [profile, DEV_RELEASE, "gzip-9", "reuse-frame-0"],
        ),
        "selector": source_hash(root, ["kernel/rocknix/stock-root/extlinux.conf"], [DEV_RELEASE]),
        "post-flash": source_hash(root, ["kernel/rocknix/stock-root/post-flash.sh"]),
        "mount-storage": source_hash(root, ["kernel/rocknix/stock-root/mount-storage.sh"]),
    }
    for name in RUNTIME_FILES:
        result[f"runtime:{name}"] = source_hash(root, [f"kernel/rocknix/stock-root/{name}"], [DEV_RELEASE])
    return result


def classify_path(path: str) -> tuple[str, set[str]]:
    if path.endswith(".md") or path.startswith("measurements/"):
        return ("documentation", set())
    if path.startswith("kernel/rocknix/tests/"):
        return ("test", set())
    if path in {"dev-build-and-deploy.sh", "kernel/rocknix/dev-release-tool.py"}:
        return ("workflow", set())
    if path == "kernel/rocknix/build-stock-root-compat.sh":
        return ("reviewed-workflow-extraction", set())
    if path == "launcher/bird-launcher.c":
        return ("supported", {"launcher", "early-initramfs"})
    if path in {"launcher/catalog.generated.h", "launcher/library.inventory.tsv", "generate-launcher-catalog.py"}:
        return ("supported", {"catalog", "launcher", "early-initramfs"})
    if path == "launcher/catalog.revision":
        return ("workflow", set())
    if path == "generate-launcher-catalog.sh":
        return ("full-release-only", set())
    if path in {"bird-device-contract.tsv", "generate-device-contract.py", *GENERATED_DEVICE_PATHS}:
        return (
            "supported",
            {"device-contract", "launcher", "fixed-controls", "mpv-controls", "early-initramfs", "runtime:bird-suspend-policy.generated.sh", "runtime:bird-sleep.conf"},
        )
    if path == "kernel/rocknix/build-bird-local-binary.sh":
        return ("supported", {"launcher", "pidwait", "powerstate", "fixed-controls", "mpv-controls", "early-initramfs"})
    if path == "launcher/bird-pidwait.c":
        return ("supported", {"pidwait"})
    if path == "launcher/bird-powerstate.c":
        return ("supported", {"powerstate"})
    if path == "kernel/rocknix/stock-root/bird-fixed-controls.c":
        return ("supported", {"fixed-controls"})
    if path == "kernel/rocknix/stock-root/bird-mpv-controls.c":
        return ("supported", {"mpv-controls"})
    if path in {
        "kernel/rocknix/build-stock-root-early-initramfs.sh",
        "kernel/rocknix/stock-root/bird-early.sh",
        "kernel/rocknix/stock-root/bird-release-loader.sh",
        "firmware/normalize-newc.py",
    }:
        return ("supported", {"early-initramfs"})
    if path in {"firmware/generate-launcher-bootlogo.py", "firmware/assets/bird-launcher-backdrop.png"}:
        return ("supported", {"boot-assets", "early-initramfs"})
    if path == "kernel/rocknix/stock-root/extlinux.conf":
        return ("supported", {"selector"})
    if path == "kernel/rocknix/stock-root/post-flash.sh":
        return ("supported", {"post-flash"})
    if path == "kernel/rocknix/stock-root/mount-storage.sh":
        return ("supported", {"mount-storage"})
    prefix = "kernel/rocknix/stock-root/"
    if path.startswith(prefix):
        name = path[len(prefix) :]
        if name == "portmaster-provider.manifest.tsv":
            return ("full-release-only", set())
        if name in RUNTIME_FILES:
            return ("supported", {f"runtime:{name}"})
        if name == "bird-logind.conf":
            return ("supported", {"device-contract"})
        if name == "extlinux.fallback.conf":
            return ("full-release-only", set())
    full_only = {
        "build-and-deploy.sh",
        "build-launcher-object.sh",
        "rebuild-library.command",
        "firmware/mac-update-rocknix-stock-root-v6.sh",
    }
    if path in full_only or path.startswith("kernel/rocknix/source/") or path.startswith("kernel/rocknix/patches/"):
        return ("full-release-only", set())
    return ("unsupported", set())


def all_component_groups() -> set[str]:
    fixed = {
        "launcher",
        "pidwait",
        "powerstate",
        "fixed-controls",
        "mpv-controls",
        "device-contract",
        "catalog",
        "boot-assets",
        "early-initramfs",
        "selector",
        "post-flash",
        "mount-storage",
    }
    return fixed | {f"runtime:{name}" for name in RUNTIME_FILES}


def expand_dependencies(groups: set[str]) -> set[str]:
    expanded = set(groups)
    if "device-contract" in expanded:
        expanded.update(
            {
                "launcher",
                "fixed-controls",
                "mpv-controls",
                "early-initramfs",
                "runtime:bird-suspend-policy.generated.sh",
                "runtime:bird-sleep.conf",
            }
        )
    if "catalog" in expanded:
        expanded.update({"launcher", "early-initramfs"})
    if "launcher" in expanded or "boot-assets" in expanded:
        expanded.add("early-initramfs")
    return expanded


def changed_paths_for_state(root: pathlib.Path, identity: SourceIdentity, state_dir: pathlib.Path, state: DevState | None) -> set[str]:
    if state is None or state.inventory_sha == "pending":
        return dirty_paths(root)
    inventory_path = state_dir / "source-inventory.tsv"
    require_regular(inventory_path, "saved source inventory")
    data = inventory_path.read_bytes()
    if sha256_bytes(data) != state.inventory_sha:
        fail("saved source inventory digest changed")
    return changed_inventory_paths(parse_inventory(data), identity.inventory)


def render_dev_manifest(
    base: Manifest,
    dev_root: pathlib.Path,
    identity: SourceIdentity,
    contract_digest: str,
    catalog_digest: str,
) -> bytes:
    lines = [
        f"schema\t{MANIFEST_SCHEMA}",
        f"release\t{DEV_RELEASE}",
        "target-mode-policy\tfat-capability",
        f"source-commit\t{identity.commit}\t{identity.state}",
        f"artifact\tdevice-contract\tbird/bird-device-contract.tsv\t{contract_digest}",
        f"artifact\tcatalog\tlauncher/catalog.generated.h\t{catalog_digest}",
        *base.inputs,
    ]
    for relative, mode in base.dirs:
        lines.append(f"dir\t{relative}\t{mode}")
    for relative, mode, _size, _digest in base.files:
        target = dev_root / relative
        require_regular(target, f"dev release file {relative}")
        lines.append(f"file\t{relative}\t{mode}\t{target.stat().st_size}\t{sha256_file(target)}")
    return ("\n".join(lines) + "\n").encode()


def copy_manifest_release(source: pathlib.Path, destination: pathlib.Path, manifest: Manifest, host_test: bool) -> None:
    destination.mkdir(mode=0o755)
    for relative, mode in manifest.dirs:
        target = destination / relative
        target.mkdir(parents=True, exist_ok=True)
        if host_test:
            target.chmod(int(mode, 8))
    for relative, mode, size, digest in manifest.files:
        source_file = source / relative
        require_regular(source_file, f"base release file {relative}")
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_file, target)
        if target.stat().st_size != size or sha256_file(target) != digest:
            fail(f"base release copy verification failed: {relative}")
        if host_test:
            target.chmod(int(mode, 8))


def specialize_selector(source: bytes, source_id: str) -> bytes:
    try:
        text = source.decode("ascii")
    except UnicodeDecodeError:
        fail("release selector is not ASCII")
    if text.count(f"bird_release={source_id}") != 1:
        fail("base release selector does not contain its exact release argument")
    text = text.replace(f"/bird-releases/{source_id}/", f"/bird-releases/{DEV_RELEASE}/")
    text = text.replace(f"bird_release={source_id}", f"bird_release={DEV_RELEASE}")
    result = text.encode("ascii")
    verify_selector_for_release(result, DEV_RELEASE)
    return result


def extract_newc_member(compressed: pathlib.Path, requested: str) -> bytes:
    data = gzip.decompress(compressed.read_bytes())
    offset = 0
    while offset + 110 <= len(data):
        header = data[offset : offset + 110]
        if header[:6] != b"070701":
            fail("generated initramfs is not normalized newc")
        namesize = int(header[94:102], 16)
        filesize = int(header[54:62], 16)
        offset += 110
        name = data[offset : offset + namesize - 1].decode("utf-8", "surrogateescape")
        offset = (offset + namesize + 3) & ~3
        payload = data[offset : offset + filesize]
        offset = (offset + filesize + 3) & ~3
        if name == "TRAILER!!!":
            break
        if name.lstrip("./") == requested.lstrip("/"):
            return payload
    fail(f"generated initramfs member is missing: {requested}")


def copy_test_output(fixture: pathlib.Path, relative: str, destination: pathlib.Path) -> None:
    source = fixture / relative
    require_regular(source, f"host-test build fixture {relative}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def prepare_outputs(
    root: pathlib.Path,
    bird: pathlib.Path,
    data: pathlib.Path,
    groups: set[str],
    profile: str,
    work: pathlib.Path,
    host_test: bool,
) -> tuple[pathlib.Path, str | None, list[str]]:
    updates = work / "updates"
    updates.mkdir()
    generated = work / "generated"
    generated.mkdir()
    tests: list[str] = []
    fixture_value = os.environ.get("BIRD_DEV_TEST_BUILD_FIXTURE", "")
    fixture = pathlib.Path(fixture_value) if fixture_value else None

    contract_header = generated / "bird-device-contract.h"
    suspend_policy = generated / "bird-suspend-policy.generated.sh"
    sleep_policy = generated / "bird-sleep.conf"
    logind_policy = generated / "bird-logind.conf"
    if not host_test:
        run(
            [
                "python3",
                str(root / "generate-device-contract.py"),
                str(root / "bird-device-contract.tsv"),
                str(contract_header),
                "--suspend-policy-output",
                str(suspend_policy),
                "--sleep-policy-output",
                str(sleep_policy),
                "--logind-policy-output",
                str(logind_policy),
            ],
            cwd=root,
        )
        tests.append("generated device-contract outputs")
    else:
        shutil.copyfile(root / "launcher/bird-device-contract.h", contract_header)
        shutil.copyfile(root / "kernel/rocknix/stock-root/bird-suspend-policy.generated.sh", suspend_policy)
        shutil.copyfile(root / "kernel/rocknix/stock-root/bird-sleep.conf", sleep_policy)
        shutil.copyfile(root / "kernel/rocknix/stock-root/bird-logind.conf", logind_policy)

    catalog_header = generated / "catalog.generated.h"
    catalog_inventory = generated / "library.inventory.tsv"
    catalog_digest: str | None = None
    needs_catalog = bool(groups & {"catalog", "launcher", "early-initramfs"})
    if needs_catalog:
        if host_test:
            shutil.copyfile(root / "launcher/catalog.generated.h", catalog_header)
            shutil.copyfile(root / "launcher/library.inventory.tsv", catalog_inventory)
        else:
            run(
                [
                    "python3",
                    str(root / "generate-launcher-catalog.py"),
                    str(data / "ROMS"),
                    "--media-root",
                    str(data / "MEDIA"),
                    "--output",
                    str(catalog_header),
                    "--inventory-output",
                    str(catalog_inventory),
                ],
                cwd=root,
            )
            tests.append("generated embedded catalog")
            if catalog_header.read_bytes() != (root / "launcher/catalog.generated.h").read_bytes() or (
                catalog_inventory.read_bytes() != (root / "launcher/library.inventory.tsv").read_bytes()
            ):
                fail(
                    "generated catalog sources are stale or hand-edited; run "
                    "./generate-launcher-catalog.sh against this BIRD-DATA content first"
                )
        catalog_digest = sha256_file(catalog_header)

    overlay = work / "source/launcher"
    overlay.mkdir(parents=True)
    shutil.copyfile(contract_header, overlay / "bird-device-contract.h")
    if groups & {"launcher", "early-initramfs"}:
        shutil.copyfile(root / "launcher/bird-launcher.c", overlay / "bird-launcher.c")
        shutil.copyfile(catalog_header, overlay / "catalog.generated.h")

    helper = root / "kernel/rocknix/build-bird-local-binary.sh"
    build_env = os.environ.copy()
    build_env.update(build_tool_configuration(host_test))
    build_env["BIRD_LAUNCHER_PROFILE"] = "profile" if profile == "profile" else "none"
    build_env["BIRD_LOCAL_LAUNCHER_DIR"] = str(overlay)

    def build_binary(component: str, relative: str) -> None:
        output = updates / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        if host_test:
            if fixture is None:
                fail("host-test binary build fixture is required")
            copy_test_output(fixture, relative, output)
        else:
            object_path = work / f"{component}.o"
            run(
                [
                    "sh",
                    str(helper),
                    "--build",
                    component,
                    "--object",
                    str(object_path),
                    "--output",
                    str(output),
                ],
                cwd=root,
                env=build_env,
            )
        tests.append(f"static AArch64/PT_INTERP: {relative}")

    if "launcher" in groups:
        build_binary("final-launcher", "bird/bird-launcher")
    for group, component, relative in (
        ("pidwait", "bird-pidwait", "bird/bird-pidwait"),
        ("powerstate", "bird-powerstate", "bird/bird-powerstate"),
        ("fixed-controls", "bird-fixed-controls", "bird/bird-fixed-controls"),
        ("mpv-controls", "bird-mpv-controls", "bird/bird-mpv-controls"),
    ):
        if group in groups:
            build_binary(component, relative)

    if "early-initramfs" in groups:
        early = work / "early"
        (early / "build").mkdir(parents=True)
        (early / "card").mkdir()
        (early / "build/build-flags.tsv").write_text("component\tmode\tflags\n", encoding="utf-8")
        if host_test:
            if fixture is None:
                fail("host-test initramfs build fixture is required")
            copy_test_output(fixture, "bird-initramfs.cpio.gz", updates / "bird-initramfs.cpio.gz")
        else:
            early_env = build_env.copy()
            early_env.update(
                {
                    "OUTPUT": str(early),
                    "BIRD_RELEASE_ID": DEV_RELEASE,
                    "BIRD_INITRAMFS_GZIP_LEVEL": "9",
                    "BIRD_DEV_LOCAL_BUILD": "1",
                    "BIRD_REUSE_UBOOT_FRAME": "0",
                    "BIRD_BOOT_FRAME_VERIFIED_CONTRACT": "",
                }
            )
            run(["sh", str(root / "kernel/rocknix/build-stock-root-early-initramfs.sh")], cwd=root, env=early_env)
            shutil.copyfile(early / "card/bird-initramfs.cpio.gz", updates / "bird-initramfs.cpio.gz")
        loader = extract_newc_member(updates / "bird-initramfs.cpio.gz", "bird-release-loader.sh")
        if f"BIRD_LOADER_RELEASE={DEV_RELEASE}\n".encode() not in loader:
            fail("generated initramfs release loader does not name dev-current")
        extract_newc_member(updates / "bird-initramfs.cpio.gz", "opt/bird/bird-launcher")
        tests.append("external initramfs release-loader and launcher")

    if "boot-assets" in groups:
        contract = updates / "bird/boot-frame.contract"
        xrgb = updates / "bird/launcher-base.xrgb"
        contract.parent.mkdir(parents=True, exist_ok=True)
        if host_test:
            if fixture is None:
                fail("host-test boot asset fixture is required")
            copy_test_output(fixture, "bird/boot-frame.contract", contract)
            copy_test_output(fixture, "bird/launcher-base.xrgb", xrgb)
        else:
            run(
                [
                    "python3",
                    str(root / "firmware/generate-launcher-bootlogo.py"),
                    str(work / "bird-frame-zero.bmp"),
                    "--contract",
                    str(contract),
                    "--xrgb-output",
                    str(xrgb),
                ],
                cwd=root,
            )
        tests.append("boot-frame generated asset contract")

    if "device-contract" in groups:
        (updates / "bird").mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / "bird-device-contract.tsv", updates / "bird/bird-device-contract.tsv")
        shutil.copyfile(suspend_policy, updates / "bird/bird-suspend-policy.generated.sh")
        shutil.copyfile(sleep_policy, updates / "bird/bird-sleep.conf")

    stock = root / "kernel/rocknix/stock-root"
    if "post-flash" in groups:
        shutil.copyfile(stock / "post-flash.sh", updates / "post-flash.sh")
    if "mount-storage" in groups:
        shutil.copyfile(stock / "mount-storage.sh", updates / "mount-storage.sh")
    for name in RUNTIME_FILES:
        if f"runtime:{name}" not in groups:
            continue
        destination = updates / f"bird/{name}"
        destination.parent.mkdir(parents=True, exist_ok=True)
        if name == "supervisor.sh":
            source = (stock / name).read_text(encoding="utf-8")
            transformed, count = re.subn(r"^RELEASE_ID=v6\.23$", f"RELEASE_ID={DEV_RELEASE}", source, flags=re.MULTILINE)
            if count != 1:
                fail("supervisor release specialization contract changed")
            destination.write_text(transformed, encoding="utf-8", newline="\n")
        elif name == "bird-suspend-policy.generated.sh":
            shutil.copyfile(suspend_policy, destination)
        elif name == "bird-sleep.conf":
            shutil.copyfile(sleep_policy, destination)
        else:
            shutil.copyfile(stock / name, destination)
        if name in SCRIPT_RUNTIME_FILES:
            run(["bash", "-n", str(destination)], cwd=root)
            tests.append(f"shell syntax: bird/{name}")
    for group, relative in (("post-flash", "post-flash.sh"), ("mount-storage", "mount-storage.sh")):
        if group in groups:
            run(["bash", "-n", str(updates / relative)], cwd=root)
            tests.append(f"shell syntax: {relative}")

    return updates, catalog_digest, tests


def verify_generated_device_sources(root: pathlib.Path) -> None:
    run(
        [
            "python3",
            str(root / "generate-device-contract.py"),
            str(root / "bird-device-contract.tsv"),
            str(root / "launcher/bird-device-contract.h"),
            "--suspend-policy-output",
            str(root / "kernel/rocknix/stock-root/bird-suspend-policy.generated.sh"),
            "--sleep-policy-output",
            str(root / "kernel/rocknix/stock-root/bird-sleep.conf"),
            "--logind-policy-output",
            str(root / "kernel/rocknix/stock-root/bird-logind.conf"),
            "--check",
        ],
        cwd=root,
    )


def host_test_command(test: pathlib.Path) -> list[str]:
    first_line = test.read_bytes().splitlines()[:1]
    shebang = first_line[0] if first_line else b""
    if test.suffix == ".py" or b"python3" in shebang:
        return ["python3", str(test)]
    if shebang == b"#!/bin/bash":
        return ["/bin/bash", str(test)]
    if shebang == b"#!/bin/sh":
        return ["/bin/sh", str(test)]
    fail(f"mapped host test has an unsupported interpreter: {test}")


def run_named_host_tests(
    root: pathlib.Path,
    names: Iterable[str],
    *,
    host_test: bool,
) -> list[str]:
    ordered = sorted(set(names))
    allowed = BROAD_PRODUCT_HOST_TESTS
    unknown = sorted(set(ordered) - allowed)
    if unknown:
        fail("host test set contains an unreviewed test: " + ",".join(unknown))
    if host_test:
        # Synthetic transaction fixtures deliberately contain only the
        # workflow tests. Do not recursively launch those tests or pretend the
        # fixture is the real complete checkout; the outer suite verifies the
        # exact deterministic names selected here.
        return [f"host fixture mapped test: {name}" for name in ordered]

    with tempfile.TemporaryDirectory(prefix="bird-dev-host-tests-") as temporary:
        environment = os.environ.copy()
        for name in tuple(environment):
            if (
                name
                in {
                    "DATA",
                    "OUTPUT",
                    "CLANG",
                    "LLD",
                    "READELF",
                    "CC",
                    "CFLAGS",
                    "CPPFLAGS",
                    "LDFLAGS",
                }
                or name.startswith("BIRD_")
            ):
                environment.pop(name, None)
        environment.update(
            {
                "TMPDIR": temporary,
                "PYTHONDONTWRITEBYTECODE": "1",
                "LC_ALL": "C",
                "LANG": "C",
                "TZ": "UTC",
                "COPYFILE_DISABLE": "1",
            }
        )
        for name in ordered:
            test = root / "kernel/rocknix/tests" / name
            require_regular(test, f"mapped host test {name}")
            run(host_test_command(test), cwd=root, env=environment, umask=0o022)
    return [f"host behavior: {name}" for name in ordered]


def component_host_tests(groups: set[str]) -> set[str]:
    missing = sorted(group for group in groups if group not in COMPONENT_HOST_TESTS)
    if missing:
        fail("component group lacks a behavioral host-test mapping: " + ",".join(missing))
    return {test for group in groups for test in COMPONENT_HOST_TESTS[group]}


def run_host_only_checks(
    root: pathlib.Path,
    paths: Iterable[str],
    *,
    host_test: bool,
) -> list[str]:
    """Run non-mutating checks for changed documentation/test/workflow inputs."""
    checks: list[str] = []
    requested_tests: set[str] = set()

    for relative in sorted(set(paths)):
        source = root / relative
        if not source.exists():
            if relative.startswith("kernel/rocknix/tests/"):
                fail(f"removed test-only source cannot satisfy its host gate: {relative}")
            checks.append(f"removed host-only source classified: {relative}")
            continue
        require_regular(source, f"host-only source {relative}")
        if relative == "kernel/rocknix/build-stock-root-compat.sh":
            if sha256_file(source) != SAFE_COMPAT_HELPER_EXTRACTION_SHA256:
                fail("canonical compatibility builder changed beyond the reviewed compiler extraction")
            requested_tests.add("test-bird-local-binary.sh")
            checks.append("shared compiler extraction contract and byte identity")
        elif relative == "kernel/rocknix/tests/test-bird-local-binary.sh":
            requested_tests.add("test-bird-local-binary.sh")
            checks.append("bird local binary focused test")
        elif relative == "kernel/rocknix/tests/test-dev-build-and-deploy.sh":
            requested_tests.add("test-dev-build-and-deploy.sh")
            checks.append("dev-current host transaction suite")
        elif relative in {"dev-build-and-deploy.sh", "kernel/rocknix/dev-release-tool.py"}:
            requested_tests.add("test-dev-build-and-deploy.sh")
            checks.append("dev-current host transaction suite")
        elif relative.startswith("kernel/rocknix/tests/"):
            name = pathlib.PurePosixPath(relative).name
            if name in HOST_HARNESS_RUNNERS:
                runner = HOST_HARNESS_RUNNERS[name]
                requested_tests.add(runner)
                checks.append(f"mapped host test: {runner}")
            elif name in KNOWN_STANDALONE_HOST_TESTS:
                requested_tests.add(name)
                checks.append(f"host test: {name}")
            else:
                fail(f"test-only source lacks an explicit safe host-check mapping: {relative}")
        elif relative.endswith(".py"):
            run(
                [
                    "python3",
                    "-c",
                    "import ast,pathlib,sys; ast.parse(pathlib.Path(sys.argv[1]).read_bytes())",
                    str(source),
                ],
                cwd=root,
            )
            checks.append(f"Python syntax: {relative}")
        elif relative.endswith(".sh") or source.read_bytes()[:2] == b"#!":
            run(["bash", "-n", str(source)], cwd=root)
            checks.append(f"shell syntax: {relative}")
        else:
            checks.append(f"host-only source classified: {relative}")
    checks.extend(run_named_host_tests(root, requested_tests, host_test=host_test))
    return checks


def compare_invariants(before: dict[pathlib.Path, tuple[bool, int, str]], description: str) -> None:
    for path, (existed, size, digest) in before.items():
        try:
            info = path.lstat()
        except FileNotFoundError:
            exists = False
        else:
            if not stat.S_ISREG(info.st_mode) or path.is_symlink():
                fail(f"{description} path became a symlink, directory, or special node: {path}")
            exists = True
        if exists != existed:
            fail(f"{description} path existence changed: {path}")
        if existed and (path.stat().st_size != size or sha256_file(path) != digest):
            fail(f"{description} bytes changed: {path}")


def snapshot_files(paths: Iterable[pathlib.Path]) -> dict[pathlib.Path, tuple[bool, int, str]]:
    result: dict[pathlib.Path, tuple[bool, int, str]] = {}
    for path in paths:
        if path.exists() or path.is_symlink():
            require_regular(path, "protected fallback/selector file")
            result[path] = (True, path.stat().st_size, sha256_file(path))
        else:
            result[path] = (False, 0, "")
    return result


class Workflow:
    def __init__(self, args: argparse.Namespace) -> None:
        self.root = args.root.resolve()
        self.bird = args.bird.absolute()
        self.data = args.data.absolute()
        self.mode = args.mode
        self.profile = "profile" if args.profile else "release"
        self.dry_run = bool(args.dry_run)
        self.host_test = os.environ.get("BIRD_DEV_HOST_TEST_MODE", "0") == "1"
        self.synthetic_modes = not self.host_test
        self.releases = self.bird / "bird-releases"
        self.dev_root = self.releases / DEV_RELEASE
        self.state_dir = self.bird / "bird-dev"
        self.state_path = self.state_dir / "state.tsv"
        self.base_selector_path = self.state_dir / "base-selector.conf"
        self.inventory_path = self.state_dir / "source-inventory.tsv"
        self.cleanup_authority_path = self.bird / DEV_CLEANUP_AUTHORITY
        self.selector_path = self.bird / "extlinux/extlinux.conf"
        self.failure_point = os.environ.get("BIRD_DEV_TEST_FAILPOINT", "")
        self.rollback_selector: bytes | None = None
        self.restore_on_failure = False
        self.mutation_started = False
        self.changed_release_paths: list[tuple[str, str, str]] = []
        self.tests: list[str] = []
        self.completed_host_test_inventory_sha = "none"
        self.completed_host_test_set = "none"

    def inject(self, name: str) -> None:
        if self.host_test and self.failure_point == name:
            fail(f"host-only injected failure: {name}")

    def read_selector(self) -> bytes:
        require_regular(self.selector_path, "active extlinux selector")
        return self.selector_path.read_bytes()

    def selector_kind(self, data: bytes) -> tuple[str, str | None]:
        selected = parse_selector(data)
        if selected is not None:
            return ("development" if is_dev_release_id(selected) else "production", selected)
        fallback = self.bird / "extlinux/extlinux.fallback.conf"
        if fallback.is_file() and not fallback.is_symlink() and data == fallback.read_bytes():
            return ("fallback", None)
        return ("legacy-or-malformed", None)

    def verify_named_release(self, release_id: str) -> Manifest:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", release_id):
            fail(f"unsafe release ID: {release_id}")
        return verify_release(self.releases / release_id, release_id, self.synthetic_modes)

    def verify_selector_release(self, selector: bytes, release_id: str) -> Manifest:
        verify_selector_for_release(selector, release_id)
        manifest = self.verify_named_release(release_id)
        release_selector = self.releases / release_id / "extlinux/extlinux.conf"
        require_regular(release_selector, "release selector")
        if release_selector.read_bytes() != selector:
            fail(f"top-level selector differs from complete release selector: {release_id}")
        return manifest

    def saved_base_selector(self, state: DevState) -> bytes:
        require_regular(self.base_selector_path, "saved production selector")
        data = self.base_selector_path.read_bytes()
        if sha256_bytes(data) != state.base_selector_sha:
            fail("saved production selector digest changed")
        self.verify_selector_release(data, state.base_release)
        return data

    def independently_saved_base_selector(self) -> tuple[str, bytes]:
        """Verify the recovery authority without reading mutable state.tsv."""
        require_directory(self.state_dir, "dev metadata directory")
        require_regular(self.base_selector_path, "saved production selector")
        selector = self.base_selector_path.read_bytes()
        release_id = parse_selector(selector)
        if release_id is None:
            fail("saved recovery selector is legacy, fallback, or malformed")
        if is_dev_release_id(release_id):
            fail("saved recovery selector names mutable dev-current, not production")
        self.verify_selector_release(selector, release_id)
        return release_id, selector

    def cleanup_authority(self) -> CleanupAuthority | None:
        """Load the durable cleanup authority, accepting one FAT case alias."""
        reject_distinct_case_entries(
            self.bird,
            self.cleanup_authority_path,
            DEV_CLEANUP_AUTHORITY,
            "cleanup authority",
        )
        if not self.cleanup_authority_path.exists() and not self.cleanup_authority_path.is_symlink():
            return None
        authority = parse_cleanup_authority(self.cleanup_authority_path)
        self.verify_selector_release(authority.selector, authority.base_release)
        manifest_path = self.releases / authority.base_release / "deploy-manifest.tsv"
        if sha256_file(manifest_path) != authority.manifest_sha:
            fail("cleanup authority production manifest digest changed")
        return authority

    def cleanup_protected_records(
        self,
        snapshot: dict[pathlib.Path, tuple[bool, int, str]] | None = None,
    ) -> tuple[tuple[str, bool, int, str], ...]:
        current = self.protected_files() if snapshot is None else snapshot
        return tuple(
            (relative, *current[self.bird / relative])
            for relative in CLEANUP_PROTECTED_PATHS
        )

    def authority_protected_snapshot(
        self,
        authority: CleanupAuthority,
    ) -> dict[pathlib.Path, tuple[bool, int, str]]:
        return {
            self.bird / relative: (exists, size, digest)
            for relative, exists, size, digest in authority.protected
        }

    def publish_cleanup_authority(self, release_id: str, selector: bytes) -> CleanupAuthority:
        """Commit the independent selector authority before destructive cleanup."""
        existing = self.cleanup_authority()
        if existing is not None:
            if existing.base_release != release_id or existing.selector != selector:
                fail("pending cleanup authority names a different production release")
            return existing
        self.verify_named_release(release_id)
        manifest_sha = sha256_file(self.releases / release_id / "deploy-manifest.tsv")
        expected = cleanup_authority_bytes(
            release_id,
            selector,
            manifest_sha,
            self.cleanup_protected_records(),
        )
        publication_temporary = self.bird / (
            f".{self.cleanup_authority_path.name}.dev-new.{os.getpid()}"
        )
        if publication_temporary.exists() or publication_temporary.is_symlink():
            require_regular(publication_temporary, "interrupted cleanup-authority temporary")
            if publication_temporary.read_bytes() != expected:
                fail("cleanup-authority atomic temporary is occupied by different bytes")
            os.replace(publication_temporary, self.cleanup_authority_path)
            remove_appledouble_sibling(publication_temporary)
            remove_appledouble_sibling(self.cleanup_authority_path)
            fsync_directory(self.bird)
        else:
            atomic_write(self.cleanup_authority_path, expected, 0o600)
        if not self.host_test:
            sync_storage()
        published = self.cleanup_authority()
        if published is None or published.base_release != release_id or published.selector != selector:
            fail("development cleanup authority did not verify after publication")
        return published

    def stale_dev_stages(self) -> list[pathlib.Path]:
        """Return only the reserved interrupted-copy stages, failing unsafe."""
        require_directory(self.releases, "release root")
        stages: list[pathlib.Path] = []
        for entry in self.releases.iterdir():
            if not entry.name.lower().startswith(DEV_STAGE_PREFIX):
                continue
            require_directory(entry, "stale dev-current staging directory")
            verify_safe_removal_tree(entry, "stale dev-current staging directory")
            stages.append(entry)
        return sorted(stages, key=lambda item: item.name.lower())

    def stale_cleanup_authority_temporaries(self) -> list[pathlib.Path]:
        """Inventory only interrupted atomic publications of the tombstone."""
        temporaries: list[pathlib.Path] = []
        for entry in self.bird.iterdir():
            lowered = entry.name.lower()
            if not (
                lowered.startswith(DEV_CLEANUP_TEMP_PREFIX)
                or lowered == DEV_CLEANUP_AUTHORITY_SIDECAR
                or lowered.startswith(DEV_CLEANUP_TEMP_SIDECAR_PREFIX)
            ):
                continue
            require_regular(entry, "interrupted cleanup-authority temporary")
            temporaries.append(entry)
        return sorted(temporaries, key=lambda item: item.name.lower())

    def reject_ambiguous_dev_cleanup_aliases(
        self,
        attempts_parent: pathlib.Path | None,
    ) -> None:
        """Accept one FAT entry, but reject true aliases on case-sensitive hosts."""
        reject_distinct_case_entries(
            self.bird,
            self.state_dir,
            "bird-dev",
            "bird-dev",
        )
        reject_distinct_case_entries(
            self.bird,
            self.cleanup_authority_path,
            DEV_CLEANUP_AUTHORITY,
            "cleanup authority",
        )
        reject_distinct_case_entries(
            self.releases,
            self.dev_root,
            DEV_RELEASE,
            "dev-current",
        )
        if attempts_parent is not None:
            reject_distinct_case_entries(
                attempts_parent,
                attempts_parent / DEV_RELEASE,
                DEV_RELEASE,
                "dev attempt state",
            )

    def remove_stale_dev_stages(self) -> int:
        stages = self.stale_dev_stages()
        for stage in stages:
            # Revalidate at the deletion boundary even though the card lock is
            # held by the shell wrapper for every real mutating invocation.
            require_directory(stage, "stale dev-current staging directory")
            verify_safe_removal_tree(stage, "stale dev-current staging directory")
            shutil.rmtree(stage)
        if stages:
            fsync_directory(self.releases)
        return len(stages)

    def verify_production_development_boundary_clear(self) -> str:
        """Mirror the reserved-state predicates enforced by production."""
        selector = self.read_selector()
        kind, release_id = self.selector_kind(selector)
        if kind != "production" or release_id is None:
            fail("active selector is not a verified production selector after cleanup")
        self.verify_selector_release(selector, release_id)
        for entry in self.bird.iterdir():
            if entry.name.lower() == "bird-dev":
                fail("development metadata remains after cleanup")
            if entry.name.lower() == DEV_CLEANUP_AUTHORITY:
                fail("development cleanup authority remains after cleanup")
            lowered = entry.name.lower()
            if (
                lowered.startswith(DEV_CLEANUP_TEMP_PREFIX)
                or lowered == DEV_CLEANUP_AUTHORITY_SIDECAR
                or lowered.startswith(DEV_CLEANUP_TEMP_SIDECAR_PREFIX)
            ):
                fail("interrupted cleanup-authority temporary remains after cleanup")
        for entry in self.releases.iterdir():
            lowered = entry.name.lower()
            if lowered == DEV_RELEASE or lowered.startswith(DEV_STAGE_PREFIX):
                fail("reserved mutable development release state remains after cleanup")
        return release_id

    def cleanup_targets(
        self,
    ) -> tuple[
        list[pathlib.Path],
        list[pathlib.Path],
        pathlib.Path | None,
        pathlib.Path | None,
    ]:
        """Inventory every reserved deletion target before removing any byte."""
        if self.dev_root.exists() or self.dev_root.is_symlink():
            verify_safe_removal_tree(self.dev_root, "dev-current release")
        stages = self.stale_dev_stages()
        attempts_parent = optional_fixed_directory_chain(
            self.data,
            ("Bird", "boot-state", "releases"),
        )
        attempts = attempts_parent / DEV_RELEASE if attempts_parent is not None else None
        self.reject_ambiguous_dev_cleanup_aliases(attempts_parent)
        if attempts is not None and (attempts.exists() or attempts.is_symlink()):
            verify_safe_removal_tree(attempts, "dev attempt state")
        if self.state_dir.exists() or self.state_dir.is_symlink():
            verify_safe_removal_tree(self.state_dir, "dev metadata directory")
        cleanup_temporaries = self.stale_cleanup_authority_temporaries()
        return stages, cleanup_temporaries, attempts_parent, attempts

    def verify_cleanup_precommit(
        self,
        authority: CleanupAuthority,
        attempts_parent: pathlib.Path | None,
        base_snapshot: dict[str, tuple[str, int, str]],
        protected: dict[pathlib.Path, tuple[bool, int, str]],
    ) -> None:
        """Prove only the tombstone remains before committing cleanup."""
        active = self.read_selector()
        if active != authority.selector:
            fail("active production selector changed during development cleanup")
        self.verify_selector_release(active, authority.base_release)
        if release_snapshot(self.releases / authority.base_release) != base_snapshot:
            fail("base production release changed during development cleanup")
        compare_invariants(protected, "fallback/recovery")
        for entry in self.bird.iterdir():
            lowered = entry.name.lower()
            if lowered == "bird-dev":
                fail("development metadata remains before cleanup commit")
            if lowered == DEV_CLEANUP_AUTHORITY:
                if not same_filesystem_entry(entry, self.cleanup_authority_path):
                    fail("ambiguous cleanup authority remains before cleanup commit")
                continue
            if (
                lowered.startswith(DEV_CLEANUP_TEMP_PREFIX)
                or lowered == DEV_CLEANUP_AUTHORITY_SIDECAR
                or lowered.startswith(DEV_CLEANUP_TEMP_SIDECAR_PREFIX)
            ):
                fail("interrupted cleanup-authority temporary remains before cleanup commit")
        for entry in self.releases.iterdir():
            lowered = entry.name.lower()
            if lowered == DEV_RELEASE or lowered.startswith(DEV_STAGE_PREFIX):
                fail("reserved mutable development release state remains before cleanup commit")
        if attempts_parent is not None:
            for entry in attempts_parent.iterdir():
                if entry.name.lower() == DEV_RELEASE:
                    fail("development attempt state remains before cleanup commit")
        current = self.cleanup_authority()
        if current != authority:
            fail("development cleanup authority changed before cleanup commit")

    def finish_cleanup(
        self,
        authority: CleanupAuthority,
        stages: list[pathlib.Path],
        cleanup_temporaries: list[pathlib.Path],
        attempts_parent: pathlib.Path | None,
        attempts: pathlib.Path | None,
    ) -> None:
        """Run a restartable deletion transaction and unlink authority last."""
        base_root = self.releases / authority.base_release
        base_snapshot = release_snapshot(base_root)
        protected = self.authority_protected_snapshot(authority)
        compare_invariants(protected, "fallback/recovery since cleanup publication")

        # A prior process may have become visible after rename but died before
        # its directory sync. Make the authority durable again on every resume
        # before any selector or deletion boundary can become persistent.
        if not self.host_test:
            sync_storage()

        self.restore_selector(authority.selector)
        self.inject("cleanup-after-selector-restoration")

        if self.dev_root.exists() or self.dev_root.is_symlink():
            verify_safe_removal_tree(self.dev_root, "dev-current release")
            shutil.rmtree(self.dev_root)
            fsync_directory(self.releases)
        self.inject("cleanup-after-dev-release-removal")

        if attempts is not None and (attempts.exists() or attempts.is_symlink()):
            verify_safe_removal_tree(attempts, "dev attempt state")
            shutil.rmtree(attempts)
            if attempts_parent is not None:
                fsync_directory(attempts_parent)
        self.inject("cleanup-after-attempt-state-removal")

        for stage in stages:
            if not stage.exists() and not stage.is_symlink():
                continue
            require_directory(stage, "stale dev-current staging directory")
            verify_safe_removal_tree(stage, "stale dev-current staging directory")
            shutil.rmtree(stage)
            fsync_directory(self.releases)
        self.inject("cleanup-after-stale-stage-removal")

        for temporary in cleanup_temporaries:
            if not temporary.exists() and not temporary.is_symlink():
                continue
            require_regular(temporary, "interrupted cleanup-authority temporary")
            lowered = temporary.name.lower()
            temporary.unlink()
            if not (
                lowered == DEV_CLEANUP_AUTHORITY_SIDECAR
                or lowered.startswith(DEV_CLEANUP_TEMP_SIDECAR_PREFIX)
            ):
                remove_appledouble_sibling(temporary)
            fsync_directory(self.bird)
        self.inject("cleanup-after-authority-temporary-removal")

        if self.state_dir.exists() or self.state_dir.is_symlink():
            verify_safe_removal_tree(self.state_dir, "dev metadata directory")
            shutil.rmtree(self.state_dir)
            fsync_directory(self.bird)
        self.inject("cleanup-after-metadata-removal")

        self.verify_cleanup_precommit(
            authority,
            attempts_parent,
            base_snapshot,
            protected,
        )
        # BIRD and BIRD-DATA are separate filesystems. Force every selector
        # and deletion boundary durable before removing the sole cross-restart
        # cleanup authority from BIRD.
        if not self.host_test:
            sync_storage()
        self.inject("cleanup-before-authority-removal")
        remove_appledouble_sibling(self.cleanup_authority_path)
        fsync_directory(self.bird)
        if not self.host_test:
            sync_storage()
        self.inject("cleanup-after-authority-sidecar-removal")
        require_regular(self.cleanup_authority_path, "development cleanup authority")
        self.cleanup_authority_path.unlink()
        fsync_directory(self.bird)
        verified_release = self.verify_production_development_boundary_clear()
        if verified_release != authority.base_release:
            fail("active production release changed at cleanup commit")
        if release_snapshot(base_root) != base_snapshot:
            fail("base production release changed at cleanup commit")
        compare_invariants(protected, "fallback/recovery")

    def recover_production(self) -> None:
        """Restore the independently saved production selector without state.tsv."""
        authority = self.cleanup_authority()
        if authority is not None:
            release_id, selector = authority.base_release, authority.selector
        else:
            release_id, selector = self.independently_saved_base_selector()
        if self.dry_run:
            print(f"dry-run: would restore independently verified production selector for {release_id}")
            return
        self.restore_selector(selector)
        self.verify_selector_release(self.read_selector(), release_id)
        print(f"Recovered exact verified production selector: {release_id}")
        print("Damaged development metadata was left untouched for diagnosis.")

    def clean_recovered(self) -> None:
        """Remove only reserved dev state after independent production recovery."""
        authority = self.cleanup_authority()
        if authority is None:
            release_id, selector = self.independently_saved_base_selector()
        else:
            release_id, selector = authority.base_release, authority.selector
        active_selector = self.read_selector()
        if active_selector != selector:
            fail(
                "active selector is not byte-identical to the independently verified "
                "production selector; run --recover-production first"
            )
        self.verify_selector_release(active_selector, release_id)
        stale_stages, cleanup_temporaries, attempts_parent, attempts = self.cleanup_targets()

        if self.dry_run:
            print(
                f"dry-run: would remove recovered dev-current state after verified "
                f"production selector {release_id}"
            )
            print(f"dry-run: would remove {len(stale_stages)} stale dev-current staging directories")
            print(
                "dry-run: would remove "
                f"{len(cleanup_temporaries)} interrupted cleanup-authority temporaries"
            )
            return
        authority = self.publish_cleanup_authority(release_id, selector)
        self.inject("cleanup-after-authority-publication")
        self.finish_cleanup(
            authority,
            stale_stages,
            cleanup_temporaries,
            attempts_parent,
            attempts,
        )
        print(
            "Removed only recovered dev-current, its attempt state, stale copy stages, "
            "and bird-dev metadata."
        )
        print(f"Production development-state guards are clear for: {release_id}")

    def verify_complete_state_binding(self, state: DevState) -> Manifest:
        if state.activation != "complete":
            fail("dev state is incomplete; use --rebase, --rollback, or --clean")
        manifest = self.verify_named_release(DEV_RELEASE)
        manifest_path = self.dev_root / "deploy-manifest.tsv"
        if sha256_file(manifest_path) != state.manifest_sha:
            fail("dev state does not bind the installed dev-current manifest")
        require_regular(self.inventory_path, "saved source inventory")
        if sha256_file(self.inventory_path) != state.inventory_sha:
            fail("dev state does not bind the saved source inventory")
        return manifest

    def status(
        self,
        identity: SourceIdentity,
        state: DevState | None,
        changed_paths: set[str],
        fingerprints: dict[str, str],
        state_error: str | None = None,
    ) -> None:
        selector = self.read_selector()
        try:
            kind, selected = self.selector_kind(selector)
        except DevError:
            kind, selected = "malformed-or-incomplete", None
        selector_verified = False
        if kind in {"production", "development"} and selected is not None:
            try:
                self.verify_selector_release(selector, selected)
                selector_verified = True
            except DevError:
                kind = "malformed-or-incomplete"
        print(f"selector-kind\t{kind}")
        print(f"selector-release\t{selected or '-'}")
        cleanup_authority_pending = self.cleanup_authority() is not None
        cleanup_publication_pending = bool(self.stale_cleanup_authority_temporaries())
        cleanup_pending = cleanup_authority_pending or cleanup_publication_pending
        print(
            "cleanup-authority-pending\t"
            + ("yes" if cleanup_authority_pending else "no")
        )
        print(
            "cleanup-publication-pending\t"
            + ("yes" if cleanup_publication_pending else "no")
        )
        print(f"base-production-release\t{state.base_release if state else '-'}")
        print(f"dev-current-exists\t{'yes' if self.dev_root.exists() else 'no'}")
        dev_verified = "no"
        state_verified = state is not None and state_error is None
        if state_error is None and self.dev_root.exists() and not self.dev_root.is_symlink():
            try:
                self.verify_named_release(DEV_RELEASE)
                if state is not None and state.activation == "complete":
                    if sha256_file(self.dev_root / "deploy-manifest.tsv") != state.manifest_sha:
                        fail("state/manifest binding mismatch")
                    require_regular(self.inventory_path, "saved source inventory")
                    if sha256_file(self.inventory_path) != state.inventory_sha:
                        fail("state/inventory binding mismatch")
                dev_verified = "yes"
            except DevError:
                dev_verified = "no"
                if state is not None and state.activation == "complete":
                    state_verified = False
        print(f"dev-current-verifies\t{dev_verified}")
        print(f"dev-state-verifies\t{'yes' if state_verified else 'no'}")
        print(f"dev-current-selected\t{'yes' if kind == 'development' else 'no'}")
        print(f"active-dev-profile\t{state.profile if state else '-'}")
        print(f"requested-target-profile\t{self.profile}")
        print(f"repository-head\t{identity.commit}")
        print(f"source-state\t{identity.state}")
        different = sorted(
            group
            for group, digest in fingerprints.items()
            if state is None or state.components.get(group) != digest
        )
        print(f"changed-components\t{','.join(different) if different else '-'}")
        unsupported = []
        for path in sorted(changed_paths):
            classification, _groups = classify_path(path)
            if classification == "supported" and not (self.root / path).exists() and not (
                self.root / path
            ).is_symlink():
                unsupported.append(f"{path}:deployed/source-path-removal")
            elif classification == "reviewed-workflow-extraction":
                if not (self.root / path).is_file() or sha256_file(self.root / path) != SAFE_COMPAT_HELPER_EXTRACTION_SHA256:
                    unsupported.append(f"{path}:full-release-only")
            elif classification in {"unsupported", "full-release-only"}:
                unsupported.append(f"{path}:{classification}")
        if (
            state is not None
            and state.components.get("authority:toolchain") != fingerprints.get("authority:toolchain")
        ):
            unsupported.append("resolved-build-toolchain:full-release-only")
        print(f"full-release-only-changes\t{','.join(unsupported) if unsupported else '-'}")
        rebase = "no"
        if state_error is not None:
            rebase = "yes"
        if kind not in {"production", "development"} or not selector_verified:
            rebase = "yes"
        if state is not None and kind == "production" and selected != state.base_release:
            rebase = "yes"
        if state is not None and state.activation != "complete":
            rebase = "yes"
        if self.dev_root.exists() and dev_verified != "yes":
            rebase = "yes"
        if state is not None and not self.dev_root.exists():
            rebase = "yes"
        if state is not None:
            try:
                self.saved_base_selector(state)
            except DevError:
                rebase = "yes"
        print(f"rebase-required\t{rebase}")
        current_inventory_sha = sha256_bytes(identity.inventory_bytes)
        all_local_current = bool(
            state is not None
            and state.activation == "complete"
            and state.all_local_inventory_sha == current_inventory_sha
        )
        host_tests_current = bool(
            state is not None
            and state.activation == "complete"
            and state.host_test_inventory_sha == current_inventory_sha
            and state.host_test_set == REQUIRED_HOST_TEST_SET
        )
        ready = bool(
            all_local_current
            and host_tests_current
            and state is not None
            and state.profile == "release"
            and state_verified
            and dev_verified == "yes"
            and not different
            and not unsupported
            and rebase == "no"
            and not cleanup_pending
        )
        legacy_readiness = state is not None and state.last_build_kind == "unknown"
        print(f"last-build-kind\t{state.last_build_kind if state else '-'}")
        print(
            "all-local-current\t"
            + ("unknown" if legacy_readiness else ("yes" if all_local_current else "no"))
        )
        print(
            "required-host-tests-current\t"
            + ("unknown" if legacy_readiness else ("yes" if host_tests_current else "no"))
        )
        print(f"host-test-set\t{state.host_test_set if state else '-'}")
        print(
            "ready-for-production-build\t"
            + ("unknown" if legacy_readiness else ("yes" if ready else "no"))
        )

    def choose_base(self, state: DevState | None, selector: bytes) -> tuple[str, bytes, Manifest]:
        kind, selected = self.selector_kind(selector)
        if self.mode == "rebase":
            if kind == "production" and selected is not None:
                return selected, selector, self.verify_selector_release(selector, selected)
            fail("--rebase requires a selected complete production release")
        if state is None:
            if kind != "production" or selected is None:
                fail("first dev invocation requires a selected complete production release")
            return selected, selector, self.verify_selector_release(selector, selected)
        saved = self.saved_base_selector(state)
        if kind == "production" and selected != state.base_release:
            fail(f"selected production release differs from dev base ({state.base_release}); use --rebase")
        if kind not in {"production", "development"}:
            fail("active selector is fallback, legacy, or malformed; restore production before dev work")
        if kind == "development" and selected != DEV_RELEASE:
            fail("active development selector is malformed")
        if kind == "development":
            self.verify_selector_release(selector, DEV_RELEASE)
        return state.base_release, saved, self.verify_named_release(state.base_release)

    def preflight_changes(
        self,
        changed_paths: set[str],
        fingerprints: dict[str, str],
        state: DevState | None,
        committed_transition_paths: set[str],
        working_tree_paths: set[str],
    ) -> tuple[set[str], list[str], list[str]]:
        requested: set[str] = set()
        docs_tests: list[str] = []
        forbidden: list[str] = []
        full_release_forbidden_paths: set[str] = set()
        for path in sorted(changed_paths):
            classification, groups = classify_path(path)
            if classification == "supported":
                source = self.root / path
                if not source.exists() and not source.is_symlink():
                    forbidden.append(f"{path} (deployed/source-path removal requires full release)")
                    continue
                requested.update(groups)
                if path in {
                    "kernel/rocknix/build-bird-local-binary.sh",
                    "kernel/rocknix/build-stock-root-early-initramfs.sh",
                }:
                    docs_tests.append("kernel/rocknix/tests/test-bird-local-binary.sh")
            elif classification in {"documentation", "test", "workflow"}:
                docs_tests.append(path)
            elif classification == "reviewed-workflow-extraction":
                source = self.root / path
                if source.is_file() and not source.is_symlink() and sha256_file(source) == SAFE_COMPAT_HELPER_EXTRACTION_SHA256:
                    docs_tests.append(path)
                else:
                    forbidden.append(f"{path} (full-release-only canonical-builder change)")
                    full_release_forbidden_paths.add(path)
            else:
                forbidden.append(f"{path} ({classification})")
                if classification == "full-release-only":
                    full_release_forbidden_paths.add(path)
        if forbidden:
            message = "changed paths require the full release workflow: " + ", ".join(forbidden)
            if state is None and full_release_forbidden_paths:
                dirty_full_release = full_release_forbidden_paths & working_tree_paths
                committed_full_release = full_release_forbidden_paths & committed_transition_paths
                if dirty_full_release:
                    message += (
                        "; uncommitted full-release-only bytes are not contained in current HEAD; "
                        "commit the intended bytes, then build and physically verify one canonical "
                        "release from the resulting commit before using it as the dev-current base"
                    )
                elif committed_full_release:
                    message += (
                        "; the selected production base predates current source authority; "
                        "build and physically verify one canonical release from current HEAD, "
                        "then use that immutable release as the dev-current base"
                    )
            fail(message)
        if (
            state is not None
            and state.components.get("authority:toolchain") != fingerprints.get(
                "authority:toolchain"
            )
        ):
            fail("resolved compiler/linker/readelf/cpio/compressor identity changed; use the full release workflow")
        if self.mode in {"all-local", "rebase"} or state is None:
            requested = all_component_groups()
        elif self.mode == "changed":
            requested.update(
                group
                for group, digest in fingerprints.items()
                if state.components.get(group) != digest
            )
        return expand_dependencies(requested), docs_tests, forbidden

    def protected_files(self) -> dict[pathlib.Path, tuple[bool, int, str]]:
        return snapshot_files(
            [
                self.bird / "extlinux/extlinux.previous.conf",
                self.bird / "extlinux/extlinux.fallback.conf",
                self.bird / "KERNEL.fallback",
                self.bird / "dtb.img",
            ]
        )

    def ensure_space(
        self,
        manifest: Manifest,
        replacing: bool,
        rebase: bool,
        updates: pathlib.Path,
        source_inventory_bytes: int,
        base_selector_bytes: int,
        incomplete_state_bytes: int,
    ) -> None:
        allowance = 2 * 1024 * 1024
        update_files = [path for path in updates.rglob("*") if path.is_file()]
        largest_atomic_replacement = max((path.stat().st_size for path in update_files), default=0)
        metadata_peak = max(
            source_inventory_bytes,
            (self.dev_root / "deploy-manifest.tsv").stat().st_size if replacing else 0,
            256 * 1024,
        )
        if not replacing:
            base_sizes = {path: size for path, _mode, size, _digest in manifest.files}
            positive_growth = sum(
                max(0, source.stat().st_size - base_sizes.get(source.relative_to(updates).as_posix(), 0))
                for source in update_files
            )
            required = (
                sum(size for _path, _mode, size, _digest in manifest.files)
                + positive_growth
                + largest_atomic_replacement
                + metadata_peak
                + allowance
            )
        else:
            positive_growth = 0
            for source in update_files:
                relative = source.relative_to(updates)
                destination = self.dev_root / relative
                old_size = destination.stat().st_size if destination.is_file() and not destination.is_symlink() else 0
                positive_growth += max(0, source.stat().st_size - old_size)
            required = positive_growth + largest_atomic_replacement + metadata_peak + allowance
        override = os.environ.get("BIRD_DEV_TEST_FREE_BYTES", "") if self.host_test else ""
        available = int(override) if override else shutil.disk_usage(self.bird).free
        recoverable = 0
        if rebase and self.dev_root.is_dir() and not self.dev_root.is_symlink():
            recoverable = sum(path.stat().st_size for path in self.dev_root.rglob("*") if path.is_file())
        if rebase:
            recoverable += sum(
                path.stat().st_size
                for stage in self.stale_dev_stages()
                for path in stage.rglob("*")
                if path.is_file()
            )
        if rebase:
            # Reclaimable dev/staging bytes do not exist as free space until
            # after the production selector and recoverable incomplete state
            # have been published. Reserve each possible atomic temporary plus
            # the general filesystem allowance now. Rebase does not publish a
            # cleanup tombstone, but retaining its fixed maximum here ensures a
            # later recovery cleanup is not stranded at the same space edge.
            cleanup_authority_reserve = (MAX_SELECTOR_BYTES * 2) + 1024
            required_before_reclaim = (
                allowance
                + (2 * base_selector_bytes)
                + incomplete_state_bytes
                + cleanup_authority_reserve
            )
            if available < required_before_reclaim:
                fail(
                    "insufficient immediate space for rebase recovery metadata: "
                    f"required-before-reclaim={required_before_reclaim} available={available} "
                    f"recoverable-dev-bytes={recoverable}; recoverable bytes cannot fund "
                    "pre-reclaim atomic writes"
                )
        # The source-inventory temporary and completed release publications
        # happen after rebase has safely reclaimed the old mutable bytes. Their
        # peak is included in required through metadata_peak above.
        if available + recoverable < required:
            fail(
                f"insufficient space for dev-current: required={required} available={available} "
                f"recoverable-dev-bytes={recoverable}"
            )

    def restore_selector(self, selector: bytes) -> None:
        atomic_write_if_changed(self.selector_path, selector)
        # A previous process can die after rename but before its directory
        # barrier. Even when bytes already match on retry, make that visible
        # selector durable before reporting recovery or beginning cleanup.
        remove_appledouble_sibling(self.selector_path)
        fsync_directory(self.selector_path.parent)
        if not self.host_test:
            sync_storage()
        if self.read_selector() != selector:
            fail("production selector restoration did not verify")

    def incomplete_state_bytes(
        self,
        base_id: str,
        base_selector: bytes,
        identity: SourceIdentity,
        toolchain_digest: str,
    ) -> bytes:
        incomplete = DevState(
            "incomplete",
            base_id,
            sha256_bytes(base_selector),
            identity.commit,
            identity.state,
            self.profile,
            "pending",
            "pending",
            self.mode,
            "none",
            "none",
            "none",
            {"authority:toolchain": toolchain_digest},
        )
        return state_bytes(incomplete)

    def write_incomplete_state(
        self,
        base_selector: bytes,
        incomplete_state: bytes,
    ) -> None:
        self.state_dir.mkdir(mode=0o755, exist_ok=True)
        require_directory(self.state_dir, "dev metadata directory")
        atomic_write(self.base_selector_path, base_selector)
        atomic_write(self.state_path, incomplete_state)

    def install_updates(self, updates: pathlib.Path, manifest: Manifest) -> None:
        modes = manifest.file_modes
        for source in sorted(path for path in updates.rglob("*") if path.is_file()):
            relative = source.relative_to(updates).as_posix()
            if relative not in modes:
                fail(f"fast workflow attempted to add a new release path: {relative}")
            destination = self.dev_root / relative
            require_directory(destination.parent, "dev release destination parent")
            old = sha256_file(destination) if destination.is_file() and not destination.is_symlink() else "missing"
            atomic_write_if_changed(destination, source.read_bytes(), int(modes[relative], 8))
            new = sha256_file(destination)
            if old != new:
                self.changed_release_paths.append((relative, old, new))

    def activate_selector(self, selector: bytes) -> str:
        atomic_write(self.selector_path, selector)
        self.inject("after-selector-rename")
        if self.read_selector() != selector:
            fail("dev selector activation did not verify")
        return sha256_bytes(selector)

    def reset_dev_attempts(self) -> None:
        directory = fixed_directory_chain(
            self.data,
            ("Bird", "boot-state", "releases", DEV_RELEASE),
            create=True,
        )
        atomic_write(directory / "attempts", b"0\n", 0o600)

    def commit_state(
        self,
        base_id: str,
        base_selector: bytes,
        identity: SourceIdentity,
        fingerprints: dict[str, str],
        manifest_sha: str,
        previous_state: DevState | None,
        full_local_build: bool,
    ) -> None:
        atomic_write(self.inventory_path, identity.inventory_bytes)
        if not self.host_test:
            sync_storage()
        inventory_sha = sha256_bytes(identity.inventory_bytes)
        if (self.completed_host_test_inventory_sha == "none") != (
            self.completed_host_test_set == "none"
        ):
            fail("completed host test authority is incomplete")
        if (
            self.completed_host_test_inventory_sha != "none"
            and self.completed_host_test_inventory_sha != inventory_sha
        ):
            fail("completed host tests do not bind the activated source inventory")
        previous_all_local = (
            previous_state.all_local_inventory_sha if previous_state is not None else "none"
        )
        previous_host_inventory = (
            previous_state.host_test_inventory_sha if previous_state is not None else "none"
        )
        previous_host_set = previous_state.host_test_set if previous_state is not None else "none"
        complete = DevState(
            "complete",
            base_id,
            sha256_bytes(base_selector),
            identity.commit,
            identity.state,
            self.profile,
            manifest_sha,
            inventory_sha,
            self.mode,
            inventory_sha if full_local_build else previous_all_local,
            (
                self.completed_host_test_inventory_sha
                if self.completed_host_test_inventory_sha != "none"
                else previous_host_inventory
            ),
            (
                self.completed_host_test_set
                if self.completed_host_test_set != "none"
                else previous_host_set
            ),
            fingerprints,
        )
        atomic_write(self.state_path, state_bytes(complete))

    def mark_required_host_tests_complete(
        self,
        identity: SourceIdentity,
        test_set: str,
    ) -> None:
        """Bind an explicitly completed mapped/broad host gate to this source."""
        if test_set != REQUIRED_HOST_TEST_SET:
            fail(f"unsupported required host test set: {test_set}")
        self.completed_host_test_inventory_sha = sha256_bytes(identity.inventory_bytes)
        self.completed_host_test_set = test_set

    def rollback(self, state: DevState | None) -> None:
        if state is None:
            fail("no dev state exists; there is no saved production selector")
        selector = self.saved_base_selector(state)
        if self.dry_run:
            print(f"dry-run: would restore exact production selector for {state.base_release}")
            return
        self.restore_selector(selector)
        print(f"Restored production selector: {state.base_release}")

    def clean(self, state: DevState | None) -> None:
        if state is None:
            fail("no verified dev metadata exists; refusing ambiguous clean")
        selector = self.saved_base_selector(state)
        if self.dev_root.exists() or self.dev_root.is_symlink():
            verify_safe_removal_tree(self.dev_root, "dev-current release")
            if (self.dev_root / ".complete").exists():
                self.verify_named_release(DEV_RELEASE)
        stale_stages, cleanup_temporaries, attempts_parent, attempts = self.cleanup_targets()
        if self.dry_run:
            print(
                f"dry-run: would restore {state.base_release} and remove only dev-current "
                f"metadata/release plus {len(stale_stages)} stale copy stages and "
                f"{len(cleanup_temporaries)} interrupted authority temporaries"
            )
            return
        authority = self.publish_cleanup_authority(state.base_release, selector)
        self.inject("cleanup-after-authority-publication")
        self.finish_cleanup(
            authority,
            stale_stages,
            cleanup_temporaries,
            attempts_parent,
            attempts,
        )
        print(
            "Removed only dev-current, its attempt state, stale copy stages, "
            "and bird-dev metadata."
        )

    def deploy(
        self,
        identity: SourceIdentity,
        state: DevState | None,
        groups: set[str],
        fingerprints: dict[str, str],
        docs_tests: list[str],
    ) -> None:
        selector_before = self.read_selector()
        base_id, base_selector, base_manifest = self.choose_base(state, selector_before)
        base_root = self.releases / base_id
        base_snapshot = release_snapshot(base_root)
        protected = self.protected_files()
        # Render and validate every source-derived selector byte before any
        # card write or incomplete-state publication.
        selector_bytes = specialize_selector(
            (self.root / "kernel/rocknix/stock-root/extlinux.conf").read_bytes(),
            "v6.23",
        )
        if "early-initramfs" in groups:
            verify_early_input_compatibility(base_manifest)
        previous_dev_manifest: Manifest | None = None
        if self.dev_root.exists() and state is not None and state.activation == "complete":
            previous_dev_manifest = self.verify_named_release(DEV_RELEASE)

        if not groups and self.mode == "changed":
            self.tests.extend(
                run_host_only_checks(self.root, docs_tests, host_test=self.host_test)
            )
            kind, selected = self.selector_kind(selector_before)
            if not docs_tests and kind == "production" and selected == base_id:
                dev_selector_path = self.dev_root / "extlinux/extlinux.conf"
                require_regular(dev_selector_path, "dev-current selector")
                dev_selector = dev_selector_path.read_bytes()
                self.verify_selector_release(dev_selector, DEV_RELEASE)
                if self.dry_run:
                    print("dry-run: would reactivate the unchanged verified dev-current release")
                    return
                self.rollback_selector = base_selector
                self.restore_on_failure = True
                self.reset_dev_attempts()
                if not self.host_test:
                    sync_storage()
                selector_sha = self.activate_selector(dev_selector)
                if not self.host_test:
                    sync_storage()
                self.restore_on_failure = False
                print("Reactivated unchanged verified dev-current; no release payload file was rewritten.")
                print(f"Selector SHA-256: {selector_sha}")
                return
            print("No supported payload component changed; card release was not rewritten or reactivated.")
            if self.tests:
                print("Tests: " + "; ".join(dict.fromkeys(self.tests)))
            return

        if self.dry_run:
            print(f"dry-run: base={base_id} dev={DEV_RELEASE} profile={self.profile}")
            print("dry-run: component groups=" + (",".join(sorted(groups)) if groups else "none"))
            return

        with tempfile.TemporaryDirectory(prefix="bird-dev-build-") as temporary:
            work = pathlib.Path(temporary)
            # Compilation is host-side, but an actual build failure still
            # returns the card to the saved production selector. An explicit
            # insufficient-space decision below remains wholly read-only.
            self.rollback_selector = base_selector
            self.restore_on_failure = True
            updates, generated_catalog_digest, build_tests = prepare_outputs(
                self.root, self.bird, self.data, groups, self.profile, work, self.host_test
            )
            self.tests.extend(build_tests)
            self.tests.extend(
                run_host_only_checks(self.root, docs_tests, host_test=self.host_test)
            )
            full_product_gate = groups == all_component_groups()
            mapped_tests = (
                set(BROAD_PRODUCT_HOST_TESTS)
                if full_product_gate
                else component_host_tests(groups)
            )
            self.inject("before-product-host-tests")
            self.tests.extend(
                run_named_host_tests(self.root, mapped_tests, host_test=self.host_test)
            )
            self.inject("after-product-host-tests")
            if full_product_gate:
                self.mark_required_host_tests_complete(identity, REQUIRED_HOST_TEST_SET)
            identity_after = capture_source_identity(self.root)
            if (identity_after.commit, identity_after.state, identity_after.inventory_bytes) != (
                identity.commit,
                identity.state,
                identity.inventory_bytes,
            ):
                fail("source tree changed while dev bytes were being built")
            if build_toolchain_fingerprint(self.host_test) != fingerprints["authority:toolchain"]:
                fail("build toolchain changed while dev bytes were being built")

            self.restore_on_failure = False
            replacing = self.dev_root.exists() and self.mode != "rebase"
            incomplete_state = self.incomplete_state_bytes(
                base_id,
                base_selector,
                identity,
                fingerprints["authority:toolchain"],
            )
            self.ensure_space(
                base_manifest,
                replacing,
                self.mode == "rebase",
                updates,
                len(identity.inventory_bytes),
                len(base_selector),
                len(incomplete_state),
            )

            self.restore_on_failure = True
            self.restore_selector(base_selector)
            self.verify_selector_release(self.read_selector(), base_id)
            self.inject("after-base-selector-restoration")

            # Publish recoverable intent before every mutation, including an
            # incremental update. A crash after .complete removal must never
            # leave metadata claiming that dev-current is still complete.
            self.write_incomplete_state(
                base_selector,
                incomplete_state,
            )
            if not self.host_test:
                sync_storage()

            if self.mode == "rebase":
                self.remove_stale_dev_stages()

            if self.mode == "rebase" and self.dev_root.exists():
                verify_safe_removal_tree(self.dev_root, "previous dev-current release")
                if state is not None and state.activation == "complete":
                    self.verify_named_release(DEV_RELEASE)
                shutil.rmtree(self.dev_root)

            if not self.dev_root.exists():
                stage = self.releases / f".{DEV_RELEASE}.new.{os.getpid()}"
                if stage.exists() or stage.is_symlink():
                    fail("dev release staging path is occupied")
                try:
                    copy_manifest_release(base_root, stage, base_manifest, self.host_test)
                    os.replace(stage, self.dev_root)
                except BaseException:
                    if stage.exists() and not stage.is_symlink() and stage.is_dir():
                        shutil.rmtree(stage)
                    raise
                fsync_directory(self.releases)
            else:
                self.verify_named_release(DEV_RELEASE)

            self.mutation_started = True
            complete = self.dev_root / ".complete"
            complete.unlink(missing_ok=True)
            fsync_directory(self.dev_root)
            self.inject("after-dev-incomplete")
            self.install_updates(updates, base_manifest)

            selector_relative = self.dev_root / "extlinux/extlinux.conf"
            old_selector_digest = sha256_file(selector_relative)
            atomic_write_if_changed(
                selector_relative,
                selector_bytes,
                int(base_manifest.file_modes["extlinux/extlinux.conf"], 8),
            )
            new_selector_digest = sha256_file(selector_relative)
            if old_selector_digest != new_selector_digest:
                self.changed_release_paths.append(("extlinux/extlinux.conf", old_selector_digest, new_selector_digest))

            supervisor = self.dev_root / "bird/supervisor.sh"
            if f"RELEASE_ID={DEV_RELEASE}\n".encode() not in supervisor.read_bytes():
                fail("dev supervisor does not name dev-current")
            if "early-initramfs" not in groups:
                loader = extract_newc_member(self.dev_root / "bird-initramfs.cpio.gz", "bird-release-loader.sh")
                if f"BIRD_LOADER_RELEASE={DEV_RELEASE}\n".encode() not in loader:
                    fail("existing dev initramfs does not name dev-current")

            remove_appledouble(self.dev_root)
            file_inventory = {
                path.relative_to(self.dev_root).as_posix()
                for path in self.dev_root.rglob("*")
                if path.is_file() and path.name not in {"deploy-manifest.tsv", ".complete"}
            }
            expected_inventory = {path for path, _mode, _size, _digest in base_manifest.files}
            if file_inventory != expected_inventory:
                fail("dev release path inventory differs from the base manifest")

            catalog_digest = generated_catalog_digest
            if catalog_digest is None and previous_dev_manifest is not None:
                catalog_digest = previous_dev_manifest.artifacts["catalog"][1]
            if catalog_digest is None:
                fail("no authoritative catalog digest is available for dev-current")
            manifest_data = render_dev_manifest(
                base_manifest,
                self.dev_root,
                identity,
                sha256_file(self.dev_root / "bird/bird-device-contract.tsv"),
                catalog_digest,
            )
            manifest_path = self.dev_root / "deploy-manifest.tsv"
            atomic_write(manifest_path, manifest_data)
            manifest_sha = sha256_bytes(manifest_data)
            precommit_manifest = verify_release(
                self.dev_root,
                DEV_RELEASE,
                self.synthetic_modes,
                require_complete=False,
            )
            if precommit_manifest.inputs != base_manifest.inputs:
                fail("dev manifest changed immutable input records")
            atomic_write(complete, (manifest_sha + "\n").encode())
            verify_release(self.dev_root, DEV_RELEASE, self.synthetic_modes)

            if release_snapshot(base_root) != base_snapshot:
                fail("base production release changed during dev transaction")
            compare_invariants(protected, "fallback/recovery")
            self.reset_dev_attempts()
            if self.host_test:
                self.tests.append("host fixture reached pre-activation sync boundary")
            else:
                sync_storage()
            self.inject("before-selector-activation")
            selector_sha = self.activate_selector(selector_bytes)
            self.commit_state(
                base_id,
                base_selector,
                identity,
                fingerprints,
                manifest_sha,
                state,
                groups == all_component_groups(),
            )
            self.inject("after-state-commit")
            if self.host_test:
                self.tests.append("host fixture reached final sync boundary")
            else:
                sync_storage()
            verify_release(self.dev_root, DEV_RELEASE, self.synthetic_modes)
            if self.read_selector() != selector_bytes:
                fail("committed dev selector changed after state publication")
            if release_snapshot(base_root) != base_snapshot:
                fail("base production release changed after activation")
            compare_invariants(protected, "fallback/recovery")
            self.mutation_started = False
            self.restore_on_failure = False

        print(f"Base release: {base_id}")
        print(f"Development release: {DEV_RELEASE}")
        print(f"Source: {identity.commit} {identity.state}")
        print("Rebuilt groups: " + ", ".join(sorted(groups)))
        for relative, old, new in sorted(set(self.changed_release_paths)):
            print(f"changed\t{relative}\t{old}\t{new}")
        print("Reused unchanged: KERNEL, KERNEL.fallback, dtb.img, ROCKNIX SYSTEM/STORAGE, PortMaster, KOReader, fallback selector")
        print(f"Manifest SHA-256: {manifest_sha}")
        print(f"Selector SHA-256: {selector_sha}")
        if self.tests:
            print("Tests: " + "; ".join(dict.fromkeys(self.tests)))
        whole = os.environ.get("BIRD_DEV_WHOLE", "CARD")
        print(f"Safe eject: diskutil eject /dev/{whole}")

    def execute(self) -> None:
        require_directory(self.root, "repository root")
        require_directory(self.bird, "BIRD volume")
        require_directory(self.data, "BIRD-DATA volume")
        require_directory(self.bird / "extlinux", "extlinux directory")
        require_directory(self.releases, "release root")
        cleanup_authority = self.cleanup_authority()
        cleanup_temporaries = self.stale_cleanup_authority_temporaries()
        if cleanup_authority is not None and self.mode not in {
            "status",
            "recover-production",
            "clean-recovered",
        }:
            fail(
                "a durable development cleanup is pending; run --recover-production "
                "then --clean-recovered"
            )
        if cleanup_temporaries and self.mode not in {
            "status",
            "recover-production",
            "clean-recovered",
            "clean",
        }:
            fail(
                "an interrupted cleanup-authority publication is pending; run "
                "--recover-production then --clean-recovered"
            )
        if self.mode == "recover-production":
            self.recover_production()
            return
        if self.mode == "clean-recovered":
            self.clean_recovered()
            return
        malformed_state_error: str | None = None
        try:
            state = load_state(self.state_path)
        except DevError as error:
            if self.mode != "status":
                raise
            state = None
            malformed_state_error = str(error)
        orphan_status_error: str | None = None
        if state is None and (self.state_dir.exists() or self.state_dir.is_symlink()):
            orphan_status_error = "orphaned bird-dev metadata exists without a valid state"
        if state is None and (self.dev_root.exists() or self.dev_root.is_symlink()):
            orphan_status_error = "orphaned dev-current exists without verified metadata"
        if orphan_status_error is not None and self.mode != "status":
            fail(orphan_status_error + "; refusing implicit adoption")
        if self.mode == "rollback":
            self.rollback(state)
            return
        if self.mode == "clean":
            if (
                state is not None
                and state.activation == "complete"
                and self.dev_root.exists()
            ):
                self.verify_complete_state_binding(state)
            self.clean(state)
            return
        if self.mode in {"changed", "all-local", "rebase"}:
            reject_ambient_build_tool_overrides(self.host_test)
        if (
            state is not None
            and state.activation == "complete"
            and self.mode in {"changed", "all-local", "rebase"}
            and (self.mode != "rebase" or self.dev_root.exists())
        ):
            self.verify_complete_state_binding(state)
        if state is not None and state.activation == "incomplete" and self.mode in {"changed", "all-local"}:
            fail("dev-current transaction is incomplete; select production and use --rebase")

        identity = capture_source_identity(self.root)
        working_tree_paths = dirty_paths(self.root)
        committed_transition_paths: set[str] = set()
        state_error: str | None = malformed_state_error or orphan_status_error
        try:
            changed_paths = changed_paths_for_state(self.root, identity, self.state_dir, state)
        except DevError as error:
            if self.mode != "status":
                raise
            state_error = str(error)
            changed_paths = dirty_paths(self.root)
        if state is None or self.mode == "rebase":
            selector = self.read_selector()
            try:
                kind, selected = self.selector_kind(selector)
            except DevError:
                kind, selected = "malformed-or-incomplete", None
            if kind == "production" and selected is not None:
                source_base = self.verify_selector_release(selector, selected)
                committed_transition_paths = committed_paths_since(
                    self.root,
                    source_base.source_commit,
                    identity.commit,
                )
                changed_paths.update(committed_transition_paths)
        fingerprints = component_fingerprints(
            self.root,
            self.data,
            self.profile,
            self.host_test,
        )

        if self.mode == "status":
            self.status(identity, state, changed_paths, fingerprints, state_error)
            return
        groups, docs_tests, _forbidden = self.preflight_changes(
            changed_paths,
            fingerprints,
            state,
            committed_transition_paths,
            working_tree_paths,
        )
        validate_component_sources(self.root, groups)
        if "device-contract" in groups:
            verify_generated_device_sources(self.root)
            self.tests.append("generated device-contract source drift check")
        self.deploy(identity, state, groups, fingerprints, docs_tests)

    def emergency_restore(self) -> None:
        if self.rollback_selector is None or not (self.mutation_started or self.restore_on_failure):
            return
        if self.mutation_started:
            try:
                current_state = load_state(self.state_path)
                if current_state is not None and current_state.activation == "complete":
                    incomplete = DevState(
                        "incomplete",
                        current_state.base_release,
                        current_state.base_selector_sha,
                        current_state.repository_commit,
                        current_state.source_state,
                        current_state.profile,
                        "pending",
                        "pending",
                        self.mode,
                        "none",
                        "none",
                        "none",
                        {"authority:toolchain": current_state.components["authority:toolchain"]},
                    )
                    atomic_write(self.state_path, state_bytes(incomplete))
                complete = self.dev_root / ".complete"
                if complete.exists() or complete.is_symlink():
                    require_regular(complete, "failed dev completion marker")
                    complete.unlink()
                    fsync_directory(self.dev_root)
                if not self.host_test:
                    sync_storage()
            except BaseException as error:  # noqa: BLE001 - preserve restoration attempt.
                print(f"error: failed dev marker invalidation also failed: {error}", file=sys.stderr)
        try:
            self.restore_selector(self.rollback_selector)
        except BaseException as error:  # noqa: BLE001 - report both failures at transaction boundary.
            print(f"error: production selector emergency restoration also failed: {error}", file=sys.stderr)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--bird", type=pathlib.Path, required=True)
    parser.add_argument("--data", type=pathlib.Path, required=True)
    parser.add_argument(
        "--mode",
        choices=(
            "changed",
            "all-local",
            "status",
            "rollback",
            "recover-production",
            "clean-recovered",
            "rebase",
            "clean",
        ),
        required=True,
    )
    parser.add_argument("--profile", type=int, choices=(0, 1), required=True)
    parser.add_argument("--dry-run", type=int, choices=(0, 1), required=True)
    return parser.parse_args()


def main() -> int:
    workflow = Workflow(parse_args())
    try:
        workflow.execute()
    except DevError as error:
        workflow.emergency_restore()
        print(f"error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        workflow.emergency_restore()
        print("error: interrupted; production selector restoration was attempted", file=sys.stderr)
        return 130
    except BaseException as error:  # noqa: BLE001 - transaction boundary must restore on OS failures.
        workflow.emergency_restore()
        print(f"error: unexpected dev workflow failure: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
