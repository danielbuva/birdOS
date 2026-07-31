#!/usr/bin/env python3
"""Bind an acquired source snapshot to its completed build without changing identity."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[2]


def digest(path: pathlib.Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def git(*arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments], cwd=ROOT, text=True, check=True,
        stdout=subprocess.PIPE,
    ).stdout.rstrip("\n")


def read_identity(path: pathlib.Path) -> dict[str, str]:
    rows = [line.split("\t") for line in path.read_text(encoding="utf-8").splitlines()]
    if not rows or rows[0] != ["key", "value"] or any(len(row) != 2 for row in rows):
        raise SystemExit("identity.tsv is malformed")
    result = dict(rows[1:])
    if len(result) != len(rows) - 1:
        raise SystemExit("identity.tsv contains duplicate keys")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=pathlib.Path)
    parser.add_argument("--deploy-manifest", type=pathlib.Path, required=True)
    parser.add_argument("--build-output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    artifact = args.artifact.resolve()
    try:
        artifact.relative_to(ROOT)
    except ValueError:
        pass
    else:
        raise SystemExit("live measurement output must remain outside the repository")
    if not artifact.is_dir() or (artifact / "SEALED.sha256").exists():
        raise SystemExit("artifact is missing or already sealed")

    identity_path = artifact / "identity.tsv"
    identity = read_identity(identity_path)
    current_status = git("status", "--porcelain=v1", "-uall")
    expected_state = "clean" if not current_status else "dirty"
    checks = {
        "source-head": git("rev-parse", "HEAD"),
        "origin-main": git("rev-parse", "origin/main"),
        "source-state": expected_state,
    }
    for key, current in checks.items():
        if identity.get(key) != current:
            raise SystemExit(f"source identity changed after acquisition: {key}")

    manifest = args.deploy_manifest.resolve()
    build_output = args.build_output.resolve()
    build_flags = build_output / "build/build-flags.tsv"
    if not manifest.is_file() or manifest.is_symlink():
        raise SystemExit("deploy manifest is missing or unsafe")
    if not build_flags.is_file() or build_flags.is_symlink():
        raise SystemExit("build flags are missing or unsafe")
    manifest_rows = [line.split("\t") for line in manifest.read_text(encoding="utf-8").splitlines()]
    release = [row[1] for row in manifest_rows if len(row) == 2 and row[0] == "release"]
    source = [row[1:] for row in manifest_rows if len(row) == 3 and row[0] == "source-commit"]
    if release != [identity.get("release-id")] or source != [[identity.get("source-head"), identity.get("source-state")]]:
        raise SystemExit("build manifest does not match the acquired source identity")

    replacements = {
        "deploy-manifest-sha256": digest(manifest),
    }
    lines = identity_path.read_text(encoding="utf-8").splitlines()
    rendered = []
    for line in lines:
        fields = line.split("\t")
        if len(fields) == 2 and fields[0] in replacements:
            rendered.append(f"{fields[0]}\t{replacements[fields[0]]}")
        else:
            rendered.append(line)
    identity_path.write_text("\n".join(rendered) + "\n", encoding="utf-8", newline="\n")
    (artifact / "build-flags.tsv").write_bytes(build_flags.read_bytes())
    external = ["path\tmode\tsize\tsha256\tprovenance"]
    for row in manifest_rows:
        if len(row) == 6 and row[0] == "input":
            external.append("\t".join(row[1:]))
    (artifact / "external-inputs.tsv").write_text("\n".join(external) + "\n", encoding="utf-8", newline="\n")
    print(digest(manifest))


if __name__ == "__main__":
    main()
