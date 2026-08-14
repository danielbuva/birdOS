#!/usr/bin/env python3
"""Compile birdOS' accepted initrd and DTB load addresses into the handoff.

This is a host-only source transform.  It emits a board-scoped default
environment plus the exact fast-init defconfig which selects it; it has no
build or media-writing mode.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import tempfile


SOURCE_SHA256 = "f0b0c44e54c28675fddc2d92243ff0b35d475a07b2c196af053294fa38e90922"
RESULT_SHA256 = "0254301f87e2222f04c67a34e5351bce16ebaac712bd96cc096f76027d9ded13"
ENV_SHA256 = "335b569a6f63acab13d20bccb843b5d6d979b7141ede3a5a5a2647b59ec132ce"
ENV_BASENAME = "bird-rg34xx-sp-handoff"
ENV_FILENAME = f"{ENV_BASENAME}.env"
ENV_SELECTION = f'CONFIG_ENV_SOURCE_FILE="{ENV_BASENAME}"\n'.encode()
ENVIRONMENT = (
    b"fdt_high=ffffffffffffffff\n"
    b"initrd_high=ffffffffffffffff\n"
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(source: bytes) -> tuple[bytes, bytes]:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit("accepted fast-init defconfig authority changed")
    if b"CONFIG_ENV_SOURCE_FILE=" in source or ENV_SELECTION in source:
        raise SystemExit("in-place handoff environment selection is ambiguous")
    for name in (b"fdt_high", b"initrd_high"):
        if name in source:
            raise SystemExit("in-place handoff policy is already present")

    result = source + ENV_SELECTION
    if sha256(result) != RESULT_SHA256:
        raise SystemExit("in-place handoff defconfig identity changed")
    if sha256(ENVIRONMENT) != ENV_SHA256:
        raise SystemExit("in-place handoff environment identity changed")
    return result, ENVIRONMENT


def _publish_pair(
    config_output: Path,
    environment_output: Path,
    config: bytes,
    environment: bytes,
) -> None:
    """Publish the environment before its defconfig commit marker.

    A crash can leave an unreferenced environment file, never a published
    defconfig which names a missing environment.  Ordinary failures remove
    both outputs.
    """

    if environment_output.name != ENV_FILENAME:
        raise SystemExit(f"environment output must be named {ENV_FILENAME}")
    if config_output.parent != environment_output.parent:
        raise SystemExit("paired outputs must share one directory")
    for path in (config_output, environment_output):
        if path.exists() or path.is_symlink():
            raise SystemExit(f"refusing to replace in-place handoff output: {path}")
    parent = config_output.parent
    if parent.is_symlink() or not parent.is_dir():
        raise SystemExit("unsafe or missing paired output directory")

    temporaries: list[Path] = []
    published: list[Path] = []
    try:
        for final, data in (
            (environment_output, environment),
            (config_output, config),
        ):
            descriptor, temporary_name = tempfile.mkstemp(
                prefix=f".{final.name}.bird-new.", dir=parent
            )
            temporary = Path(temporary_name)
            temporaries.append(temporary)
            try:
                with os.fdopen(descriptor, "wb") as output:
                    output.write(data)
                    output.flush()
                    os.fsync(output.fileno())
            except BaseException:
                os.close(descriptor)
                raise

        # The config is the activation record, so it is always published last.
        os.link(temporaries[0], environment_output)
        published.append(environment_output)
        os.link(temporaries[1], config_output)
        published.append(config_output)
        directory_fd = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except BaseException:
        for path in reversed(published):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        raise
    finally:
        for path in temporaries:
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("config_output", type=Path)
    parser.add_argument("environment_output", type=Path)
    args = parser.parse_args()
    if args.source.is_symlink() or not args.source.is_file():
        raise SystemExit("unsafe or missing fast-init defconfig")
    config, environment = transform(args.source.read_bytes())
    _publish_pair(args.config_output, args.environment_output, config, environment)


if __name__ == "__main__":
    main()
