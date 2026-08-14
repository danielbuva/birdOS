#!/usr/bin/env python3
"""Verify the active BIRD selector and its complete manifest-bound release."""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import re
import stat
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
DEV_RELEASE_TOOL = ROOT / "kernel/rocknix/dev-release-tool.py"
MAX_SELECTOR_BYTES = 16 * 1024


def fail(message: str) -> None:
    raise RuntimeError(message)


def load_release_tool():
    spec = importlib.util.spec_from_file_location(
        "bird_selected_release_authority", DEV_RELEASE_TOOL
    )
    if spec is None or spec.loader is None:
        fail("could not load the canonical birdOS release verifier")
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves annotations through the importing module namespace.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_regular(path: pathlib.Path, description: str) -> bytes:
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        fail(f"{description} is missing or unsafe: {path}")
    data = path.read_bytes()
    if not data or len(data) > MAX_SELECTOR_BYTES:
        fail(f"{description} size is outside the fixed safety bound")
    return data


def verify_selected_release(bird: pathlib.Path, *, host_test: bool) -> str:
    mode = bird.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        fail(f"BIRD root is missing or unsafe: {bird}")

    release_tool = load_release_tool()
    selector_path = bird / "extlinux/extlinux.conf"
    selector = read_regular(selector_path, "active BIRD selector")
    release_id = release_tool.parse_selector(selector)
    if release_id is None:
        fail("active BIRD selector does not name a birdOS release")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", release_id):
        fail("active BIRD selector has an unsafe release ID")
    release_tool.verify_selector_for_release(selector, release_id)

    release = bird / "bird-releases" / release_id
    release_tool.verify_release(
        release,
        release_id,
        # Real FAT volumes expose effective capabilities rather than stable
        # Unix mode bits; host fixtures preserve and verify exact modes.
        synthetic_modes=not host_test,
        require_complete=True,
    )
    embedded_selector = read_regular(
        release / "extlinux/extlinux.conf", "release-embedded selector"
    )
    release_tool.verify_selector_for_release(embedded_selector, release_id)
    if embedded_selector != selector:
        fail("active BIRD selector differs from the verified release selector")
    return release_id


def main() -> int:
    parser = argparse.ArgumentParser(
        description="verify the selected BIRD release before a bounded raw write"
    )
    parser.add_argument("--host-test", action="store_true")
    parser.add_argument("bird", type=pathlib.Path)
    args = parser.parse_args()
    try:
        release_id = verify_selected_release(args.bird, host_test=args.host_test)
    except (OSError, UnicodeError, ValueError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(release_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
