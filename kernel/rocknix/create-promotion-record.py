#!/usr/bin/env python3
"""Bind a fully gated release to its non-circular Stage 0 promotion identity."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import stat


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pass_gate(path: pathlib.Path, label: str) -> str:
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"{label} gate is missing or unsafe: {path}")
    rows = [line.split("\t") for line in path.read_text(encoding="utf-8").splitlines()]
    if rows.count(["schema", "bird-gate-v1"]) != 1 or rows.count(["result", "PASS"]) != 1:
        raise SystemExit(f"{label} gate is not an exact PASS: {path}")
    checks = [row for row in rows if row and row[0] == "check"]
    if not checks or any(len(row) != 3 or row[2] != "PASS" for row in checks):
        raise SystemExit(f"{label} gate has incomplete checks: {path}")
    if any(row[0] not in {"schema", "result", "check"} for row in rows if row):
        raise SystemExit(f"{label} gate contains an unknown record: {path}")
    return digest(path)


def tsv_map(path: pathlib.Path, header: list[str]) -> dict[str, str]:
    rows = [line.split("\t") for line in path.read_text(encoding="utf-8").splitlines()]
    if not rows or rows[0] != header or any(len(row) != 2 for row in rows[1:]):
        raise SystemExit(f"malformed evidence identity: {path}")
    result = dict(rows[1:])
    if len(result) != len(rows) - 1:
        raise SystemExit(f"duplicate evidence identity key: {path}")
    return result


def verify_sealed_evidence(seal: pathlib.Path) -> tuple[str, dict[str, str]]:
    if not seal.is_file() or seal.is_symlink():
        raise SystemExit("sealed evidence digest is missing or unsafe")
    artifact = seal.parent
    inventory = artifact / "inventory.tsv"
    seal_fields = seal.read_text(encoding="ascii").split()
    if (len(seal_fields) != 2 or seal_fields[1] != "inventory.tsv" or
            not re.fullmatch(r"[0-9a-f]{64}", seal_fields[0])):
        raise SystemExit("evidence seal is malformed")
    if not inventory.is_file() or inventory.is_symlink() or digest(inventory) != seal_fields[0]:
        raise SystemExit("evidence inventory does not match its seal")
    rows = [line.split("\t") for line in inventory.read_text(encoding="utf-8").splitlines()]
    if not rows or rows[0] != ["path", "type", "mode", "size", "sha256"]:
        raise SystemExit("evidence inventory is malformed")
    recorded: dict[str, str] = {}
    for row in rows[1:]:
        if (len(row) != 5 or row[1] != "file" or not re.fullmatch(r"[0-7]{4}", row[2]) or
                not row[3].isdigit() or not re.fullmatch(r"[0-9a-f]{64}", row[4])):
            raise SystemExit("evidence inventory record is malformed")
        relative = pathlib.PurePosixPath(row[0])
        if relative.is_absolute() or ".." in relative.parts or row[0] in recorded:
            raise SystemExit("evidence inventory path is unsafe or duplicated")
        path = artifact / pathlib.Path(*relative.parts)
        info = path.lstat()
        if (not stat.S_ISREG(info.st_mode) or path.is_symlink() or
                f"{stat.S_IMODE(info.st_mode):04o}" != row[2] or
                str(info.st_size) != row[3] or digest(path) != row[4]):
            raise SystemExit(f"sealed evidence file changed: {row[0]}")
        recorded[row[0]] = row[4]
    actual = {
        path.relative_to(artifact).as_posix()
        for path in artifact.iterdir()
        if path.is_file() and path.name not in {"inventory.tsv", "SEALED.sha256"}
    }
    if actual != set(recorded):
        raise SystemExit("sealed evidence inventory does not match its files")
    return seal_fields[0], recorded


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--device-contract", type=pathlib.Path, required=True)
    parser.add_argument("--catalog", type=pathlib.Path, required=True)
    parser.add_argument("--host-gate", type=pathlib.Path, required=True)
    parser.add_argument("--hardware-gate", type=pathlib.Path, required=True)
    parser.add_argument("--evidence-seal", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    manifest = args.manifest.read_text(encoding="utf-8").splitlines()
    rows = [line.split("\t") for line in manifest]
    release_rows = [row for row in rows if row[0] == "release"]
    source_rows = [row for row in rows if row[0] == "source-commit"]
    artifacts = {row[1]: row[2:] for row in rows if row[0] == "artifact" and len(row) == 4}
    if len(release_rows) != 1 or len(release_rows[0]) != 2:
        raise SystemExit("manifest has no unique release")
    if len(source_rows) != 1 or len(source_rows[0]) != 3 or source_rows[0][2] != "clean":
        raise SystemExit("promotion requires a uniquely identified clean source")
    source = source_rows[0][1]
    if not re.fullmatch(r"[0-9a-f]{40}", source):
        raise SystemExit("promotion source is not a full commit SHA")
    if set(artifacts) != {"device-contract", "catalog"}:
        raise SystemExit("manifest artifact binding is incomplete")
    contract_sha = digest(args.device_contract)
    catalog_sha = digest(args.catalog)
    if artifacts["device-contract"] != ["bird/bird-device-contract.tsv", contract_sha]:
        raise SystemExit("manifest device-contract binding changed")
    if artifacts["catalog"] != ["launcher/catalog.generated.h", catalog_sha]:
        raise SystemExit("manifest catalog binding changed")
    evidence_digest, evidence_files = verify_sealed_evidence(args.evidence_seal)
    identity = tsv_map(args.evidence_seal.parent / "identity.tsv", ["key", "value"])
    expected_identity = {
        "source-head": source,
        "source-state": "clean",
        "release-id": release_rows[0][1],
        "deploy-manifest-sha256": digest(args.manifest),
        "device-contract-sha256": contract_sha,
        "catalog-sha256": catalog_sha,
    }
    for key, expected in expected_identity.items():
        if identity.get(key) != expected:
            raise SystemExit(f"sealed evidence identity disagrees with promotion: {key}")
    for gate, label in ((args.host_gate, "host"), (args.hardware_gate, "hardware")):
        try:
            relative = gate.resolve().relative_to(args.evidence_seal.parent.resolve()).as_posix()
        except ValueError as error:
            raise SystemExit(f"{label} gate is outside sealed evidence") from error
        if evidence_files.get(relative) != digest(gate):
            raise SystemExit(f"{label} gate is not bound by sealed evidence")
    output = (
        "schema\tbird-promotion-v1\n"
        f"source-commit\t{source}\n"
        f"release\t{release_rows[0][1]}\n"
        f"deploy-manifest-sha256\t{digest(args.manifest)}\n"
        f"device-contract-sha256\t{contract_sha}\n"
        f"catalog-sha256\t{catalog_sha}\n"
        f"evidence-inventory-sha256\t{evidence_digest}\n"
        f"host-gate-sha256\t{pass_gate(args.host_gate, 'host')}\n"
        f"hardware-gate-sha256\t{pass_gate(args.hardware_gate, 'hardware')}\n"
    )
    args.output.write_text(output, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
