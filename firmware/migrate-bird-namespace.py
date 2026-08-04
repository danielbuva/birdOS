#!/usr/bin/env python3
"""Prepare, publish, inspect or roll back birdOS namespace v1 on one card."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import os
import pathlib
import shutil
import stat
import subprocess
import time


REVISION = "bird-canonical-namespace-v1"
STATE_FILES = ("favorites.txt", "recent.txt")
FRESH_DIRS = ("apps", "boot-state", "home", "log", "migrations", "recovery", "state")


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def fsync_dir(path: pathlib.Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def reject_link(path: pathlib.Path, label: str, *, missing_ok: bool = False) -> None:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        if missing_ok:
            return
        fail(f"{label} missing: {path}")
    if stat.S_ISLNK(mode):
        fail(f"{label} must not be a symlink: {path}")
    if not stat.S_ISDIR(mode):
        fail(f"{label} must be a directory: {path}")


def disk_field(path: pathlib.Path, key: str, fixture: pathlib.Path | None) -> str:
    if fixture:
        for line in fixture.read_text(encoding="utf-8").splitlines():
            fields = line.split("\t")
            if len(fields) == 3 and fields[0] == str(path) and fields[1] == key:
                return fields[2]
        return ""
    output = subprocess.check_output(("diskutil", "info", str(path)), text=True)
    for line in output.splitlines():
        left, separator, right = line.partition(":")
        if separator and left.strip() == key:
            return right.strip()
    return ""


def validate_card(bird: pathlib.Path, data: pathlib.Path, fixture: pathlib.Path | None) -> str:
    reject_link(bird, "BIRD volume")
    reject_link(data, "BIRD-DATA volume")
    whole = disk_field(bird, "Part of Whole", fixture)
    if not whole:
        fail("cannot identify card parent")
    if disk_field(data, "Part of Whole", fixture) != whole:
        fail("volumes are on different disks")
    whole_path = pathlib.Path(f"/dev/{whole}")
    if not (disk_field(whole_path, "Device Location", fixture) == "External" or disk_field(whole_path, "Protocol", fixture) == "Secure Digital"):
        fail("refusing disk that is neither external nor a physical SD card")
    if disk_field(whole_path, "Removable Media", fixture) != "Removable":
        fail("refusing non-removable disk")
    if disk_field(bird, "Device Identifier", fixture) != f"{whole}s1":
        fail("BIRD is not p1")
    if disk_field(data, "Device Identifier", fixture) != f"{whole}s6":
        fail("data is not p6")
    if disk_field(bird, "Volume Read-Only", fixture) != "No" or disk_field(data, "Volume Read-Only", fixture) != "No":
        fail("card volume is read-only")
    return whole


class CardLock:
    """Interoperate with the shell updater's per-card fcntl transaction lock."""

    def __init__(self, whole: str) -> None:
        if not whole or any(character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for character in whole):
            fail("unsafe whole-disk identity for card lock")
        self.root = pathlib.Path("/tmp/bird-card-locks")
        self.root.mkdir(mode=0o700, exist_ok=True)
        root_stat = self.root.lstat()
        if not stat.S_ISDIR(root_stat.st_mode) or stat.S_ISLNK(root_stat.st_mode):
            fail("Bird card lock directory is unsafe")
        if root_stat.st_uid != os.getuid() or stat.S_IMODE(root_stat.st_mode) != 0o700:
            fail("Bird card lock directory authority is unsafe")
        self.transaction_path = self.root / f"{whole}.transaction"
        self.serial_path = self.root / f"{whole}.serial"
        self.owner_path = self.root / f"{whole}.lock"
        self.transaction_fd = -1
        self.serial_fd = -1
        self.token = f"{os.getpid()}:{int(time.time_ns())}:{int(time.time())}"

    def _open_mutex(self, path: pathlib.Path) -> int:
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_nlink != 1:
            os.close(fd)
            fail(f"Bird card mutex is unsafe: {path}")
        return fd

    @staticmethod
    def _lock(fd: int, message: str) -> None:
        deadline = time.monotonic() + 15.0
        while True:
            try:
                fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    fail(message)
                time.sleep(0.025)

    def __enter__(self) -> CardLock:
        self.transaction_fd = self._open_mutex(self.transaction_path)
        self._lock(self.transaction_fd, "another Bird card transaction is active")
        self.serial_fd = self._open_mutex(self.serial_path)
        self._lock(self.serial_fd, "Bird card lock recovery is busy")
        try:
            if self.owner_path.exists() and not self.owner_path.is_symlink():
                fail("Bird card lock is not an atomic owner symlink")
            if self.owner_path.is_symlink():
                self.owner_path.unlink()
            self.owner_path.symlink_to(self.token)
            if os.readlink(self.owner_path) != self.token:
                fail("atomic Bird card lock verification failed")
        finally:
            fcntl.lockf(self.serial_fd, fcntl.LOCK_UN)
            os.close(self.serial_fd)
            self.serial_fd = -1
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        if self.serial_fd < 0:
            self.serial_fd = self._open_mutex(self.serial_path)
            self._lock(self.serial_fd, "Bird card lock release is busy")
        try:
            if self.owner_path.is_symlink() and os.readlink(self.owner_path) == self.token:
                self.owner_path.unlink()
        finally:
            fcntl.lockf(self.serial_fd, fcntl.LOCK_UN)
            os.close(self.serial_fd)
            self.serial_fd = -1
            if self.transaction_fd >= 0:
                fcntl.lockf(self.transaction_fd, fcntl.LOCK_UN)
                os.close(self.transaction_fd)
                self.transaction_fd = -1


def hash_file(path: pathlib.Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def inventory(root: pathlib.Path) -> list[str]:
    result: list[str] = []
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix().encode()):
        relative = path.relative_to(root).as_posix()
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            fail(f"symlink rejected in prepared payload: {relative}")
        if stat.S_ISDIR(mode):
            result.append(f"d\t{stat.S_IMODE(mode):04o}\t0\t-\t{relative}")
        elif stat.S_ISREG(mode):
            result.append(f"f\t{stat.S_IMODE(mode):04o}\t{path.stat().st_size}\t{hash_file(path)}\t{relative}")
        else:
            fail(f"unsupported prepared payload entry: {relative}")
    return result


def payload_inventory(bird: pathlib.Path, bios: pathlib.Path) -> list[str]:
    result: list[str] = []
    for name, root in (("Bird", bird), ("bios", bios)):
        mode = root.lstat().st_mode
        if not stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
            fail(f"prepared {name} root is not a real directory")
        result.append(f"d\t{stat.S_IMODE(mode):04o}\t0\t-\t{name}")
        for line in inventory(root):
            fields = line.split("\t", 4)
            fields[4] = f"{name}/{fields[4]}"
            result.append("\t".join(fields))
    return sorted(result, key=lambda line: line.split("\t", 4)[4].encode())


def write_record(path: pathlib.Path, lines: list[str]) -> None:
    temporary = path.with_name(path.name + f".new-{os.getpid()}")
    with temporary.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write("\n".join(lines) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    fsync_dir(path.parent)


def read_record(path: pathlib.Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []


class Migration:
    def __init__(self, data: pathlib.Path) -> None:
        self.data = data
        self.control = data / ".bird-namespace-v1"
        self.prepare = self.control / "prepare"
        self.inventory_path = self.control / "inventory.tsv"
        self.state_path = self.control / "state.tsv"
        self.canonical_bird = data / "Bird"
        self.canonical_bios = data / "ROMS" / "bios"
        self.legacy_bird = data / "MUOS" / "Bird"
        self.legacy_bios = data / "MUOS" / "bios"
        self.legacy_state = data / ".config" / "bird"

    def validate_roots(self) -> None:
        reject_link(self.data / "MUOS", "legacy MUOS root")
        reject_link(self.data / "ROMS", "canonical ROM root")
        reject_link(self.legacy_bios, "legacy BIOS root")
        reject_link(self.legacy_bird, "legacy Bird fallback", missing_ok=True)
        reject_link(self.legacy_state, "legacy persistence", missing_ok=True)
        reject_link(self.control, "migration control", missing_ok=True)
        reject_link(self.canonical_bird, "canonical Bird state", missing_ok=True)
        reject_link(self.canonical_bios, "canonical BIOS root", missing_ok=True)
        if self.legacy_bios.stat().st_dev != self.data.stat().st_dev:
            fail("legacy BIOS is not on p6")

    def state(self) -> str:
        lines = read_record(self.state_path)
        if lines[:1] == [f"revision\t{REVISION}"] and len(lines) == 2 and lines[1].startswith("state\t"):
            return lines[1].split("\t", 1)[1]
        return "none"

    def set_state(self, value: str) -> None:
        write_record(self.state_path, [f"revision\t{REVISION}", f"state\t{value}"])

    def prepared_valid(self) -> bool:
        expected = read_record(self.inventory_path)
        bird = self.prepare / "Bird"
        bios = self.prepare / "bios"
        if not bird.is_dir() and self.canonical_bird.is_dir():
            bird = self.canonical_bird
        if not bios.is_dir() and self.canonical_bios.is_dir():
            bios = self.canonical_bios
        return bool(expected) and bird.is_dir() and bios.is_dir() and expected == [
            f"revision\t{REVISION}", *payload_inventory(bird, bios)
        ]

    def prepare_payload(self) -> None:
        self.validate_roots()
        if self.state() == "committed":
            print("Canonical namespace is already committed.")
            return
        if self.canonical_bird.exists():
            fail("mixed state: canonical Bird tree exists without committed transaction")
        if self.canonical_bios.exists() and any(self.canonical_bios.iterdir()):
            fail("mixed state: canonical BIOS tree is not empty")
        self.control.mkdir(mode=0o700, exist_ok=True)
        if self.prepare.exists():
            if self.prepared_valid():
                self.set_state("prepared")
                print("Canonical namespace is already prepared and verified.")
                return
            fail("prepared payload differs from its sealed inventory")
        temporary = self.control / f"prepare-new-{os.getpid()}"
        bird = temporary / "Bird"
        bios = temporary / "bios"
        for directory in FRESH_DIRS:
            (bird / directory).mkdir(parents=True, exist_ok=True)
        if self.legacy_state.exists():
            for name in STATE_FILES:
                source = self.legacy_state / name
                if source.is_symlink():
                    fail(f"legacy persistence file is a symlink: {source}")
                if source.is_file():
                    shutil.copyfile(source, bird / "state" / name)
        # Only file bytes are part of the fixed BIOS authority. copy2() asks
        # macOS to preserve xattrs on exFAT, which materializes one AppleDouble
        # `._` sidecar per file and can nearly double the tree. Do not copy
        # host metadata into the device's canonical content namespace.
        shutil.copytree(
            self.legacy_bios,
            bios,
            copy_function=shutil.copyfile,
            ignore=lambda _directory, names: {
                name for name in names if name == ".DS_Store" or name.startswith("._")
            },
        )
        bios_file_count = sum(1 for path in bios.rglob("*") if path.is_file())
        os.replace(temporary, self.prepare)
        write_record(self.inventory_path, [f"revision\t{REVISION}", *payload_inventory(self.prepare / "Bird", self.prepare / "bios")])
        self.set_state("prepared")
        print(f"Prepared and verified {bios_file_count} BIOS files.")

    def commit(self) -> None:
        self.validate_roots()
        if self.state() == "committed":
            if not self.canonical_bird.is_dir() or not self.canonical_bios.is_dir():
                fail("committed marker disagrees with canonical trees")
            print("Canonical namespace is already committed.")
            return
        if not self.prepare.exists() or not self.prepared_valid():
            fail("no verified prepared payload")
        prepared_bird = self.prepare / "Bird"
        prepared_bios = self.prepare / "bios"
        if not self.canonical_bird.exists():
            os.replace(prepared_bird, self.canonical_bird)
            fsync_dir(self.data)
        elif prepared_bird.exists():
            fail("mixed state: both prepared and canonical Bird trees exist")
        if not self.canonical_bios.exists():
            os.replace(prepared_bios, self.canonical_bios)
            fsync_dir(self.canonical_bios.parent)
        elif prepared_bios.exists():
            if any(self.canonical_bios.iterdir()):
                fail("mixed state: both prepared and canonical BIOS trees exist")
            self.canonical_bios.rmdir()
            os.replace(prepared_bios, self.canonical_bios)
            fsync_dir(self.canonical_bios.parent)
        if prepared_bird.exists() or prepared_bios.exists():
            fail("commit did not consume the complete prepared payload")
        self.prepare.rmdir()
        write_record(self.canonical_bird / "namespace-v1.tsv", [f"revision\t{REVISION}", "state\tcommitted"])
        self.set_state("committed")
        print("Canonical namespace committed; legacy fallback data retained.")

    def rollback(self) -> None:
        self.validate_roots()
        if self.state() != "committed":
            fail("canonical namespace is not committed")
        rollback = self.control / "rollback" / str(int(time.time()))
        rollback.mkdir(parents=True)
        if not self.canonical_bird.is_dir() or not self.canonical_bios.is_dir():
            fail("canonical trees missing; refusing incomplete rollback")
        os.replace(self.canonical_bird, rollback / "Bird")
        os.replace(self.canonical_bios, rollback / "bios")
        write_record(rollback / "inventory.tsv", [f"revision\t{REVISION}", *inventory(rollback)])
        self.set_state("rolled-back")
        print(f"Canonical trees retained at {rollback}; legacy fallback is unchanged.")

    def status(self) -> None:
        self.validate_roots()
        state_value = self.state()
        partial = self.prepare.exists() and (self.canonical_bird.exists() or (self.canonical_bios.exists() and any(self.canonical_bios.iterdir())))
        print(f"revision\t{REVISION}")
        print(f"state\t{state_value}")
        print(f"prepared\t{int(self.prepare.exists())}")
        print(f"partial-commit\t{int(partial)}")
        print(f"canonical-bird\t{int(self.canonical_bird.is_dir())}")
        print(f"canonical-bios\t{int(self.canonical_bios.is_dir() and any(self.canonical_bios.iterdir()))}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("prepare", "commit", "status", "rollback"))
    parser.add_argument("--bird", type=pathlib.Path, default=pathlib.Path("/Volumes/BIRD"))
    parser.add_argument("--data", type=pathlib.Path, default=pathlib.Path("/Volumes/BIRD-DATA"))
    parser.add_argument("--device-info", type=pathlib.Path)
    args = parser.parse_args()
    if args.device_info:
        roots = (str(args.bird), str(args.data), str(args.device_info))
        if not all(value.startswith(("/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/")) for value in roots):
            fail("device metadata override is limited to temporary host fixtures")
    whole = validate_card(args.bird, args.data, args.device_info)
    with CardLock(whole):
        migration = Migration(args.data)
        getattr(migration, "prepare_payload" if args.action == "prepare" else args.action)()


if __name__ == "__main__":
    main()
