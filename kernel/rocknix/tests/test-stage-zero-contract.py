#!/usr/bin/env python3
"""Focused host tests for Stage 0 contract generation and evidence sealing."""

from __future__ import annotations

import hashlib
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]


def run(*command: str, ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    if (result.returncode == 0) != ok:
        raise AssertionError(f"unexpected result {result.returncode}: {' '.join(command)}\n{result.stdout}")
    return result


def main() -> None:
    policy_shell = "kernel/rocknix/stock-root/bird-suspend-policy.generated.sh"
    sleep_policy = "kernel/rocknix/stock-root/bird-sleep.conf"
    logind_policy = "kernel/rocknix/stock-root/bird-logind.conf"
    run(
        "python3", "generate-device-contract.py", "bird-device-contract.tsv",
        "launcher/bird-device-contract.h", "--check",
        "--suspend-policy-output", policy_shell,
        "--sleep-policy-output", sleep_policy,
        "--logind-policy-output", logind_policy,
    )
    header = (ROOT / "launcher/bird-device-contract.h").read_text()
    assert "BIRD_DEVICE_FB_MAPPING_BYTES 1382400U" in header
    assert "BIRD_DEVICE_INPUT_NAME \"H700 Gamepad\"" in header
    assert "BIRD_DEVICE_INPUT_KEY_BITMAP_WORD_COUNT 12U" in header
    assert "0x0000000107030000UL" in header
    assert "BIRD_DEVICE_BACKLIGHT_MAXIMUM_RAW 2499U" in header
    assert "deploy-manifest" not in (ROOT / "bird-device-contract.tsv").read_text()
    assert "BIRD_SUSPEND_PROVIDER_MODE=off" in (ROOT / policy_shell).read_text()
    assert "AllowSuspend=no" in (ROOT / sleep_policy).read_text()
    assert "HandleLidSwitch=ignore" in (ROOT / logind_policy).read_text()

    with tempfile.TemporaryDirectory(prefix="bird-stage-zero-") as temporary:
        temporary_path = pathlib.Path(temporary)
        # Generate a changed header from a modified contract, then prove the
        # unchanged runtime policy artifacts cannot pass the same check. This
        # prevents the manifest's device authority from drifting away from the
        # shell and systemd policy that the release actually installs.
        changed_contract = temporary_path / "changed-device-contract.tsv"
        changed_contract.write_text(
            (ROOT / "bird-device-contract.tsv").read_text(encoding="utf-8").replace(
                "suspend.provider_mode\tstring\toff\n",
                "suspend.provider_mode\tstring\tmem\n",
            ),
            encoding="utf-8",
        )
        changed_header = temporary_path / "changed-device-contract.h"
        run(
            "python3", "generate-device-contract.py", str(changed_contract),
            str(changed_header),
        )
        run(
            "python3", "generate-device-contract.py", str(changed_contract),
            str(changed_header), "--check",
            "--suspend-policy-output", policy_shell,
            "--sleep-policy-output", sleep_policy,
            "--logind-policy-output", logind_policy,
            ok=False,
        )
        contract_digest = hashlib.sha256((ROOT / "bird-device-contract.tsv").read_bytes()).hexdigest()
        catalog_digest = hashlib.sha256((ROOT / "launcher/catalog.generated.h").read_bytes()).hexdigest()
        source = run("git", "rev-parse", "HEAD").stdout.strip()
        manifest = temporary_path / "deploy-manifest.tsv"
        manifest.write_text(
            "schema\tbird-deploy-v1\n"
            "release\tstage-zero-test\n"
            f"source-commit\t{source}\tclean\n"
            f"artifact\tdevice-contract\tbird/bird-device-contract.tsv\t{contract_digest}\n"
            f"artifact\tcatalog\tlauncher/catalog.generated.h\t{catalog_digest}\n",
            encoding="utf-8",
        )
        artifact = pathlib.Path(temporary) / "baseline"
        run("python3", "kernel/rocknix/capture-baseline-evidence.py", str(artifact),
            "--mode", "release", "--release-id", "stage-zero-test",
            "--command", "./build-and-deploy.sh --release --release-id stage-zero-test")
        identity = (artifact / "identity.tsv").read_text(encoding="utf-8")
        identity = identity.replace("source-state\tdirty\n", "source-state\tclean\n")
        identity = identity.replace(
            "deploy-manifest-sha256\tpending\n",
            f"deploy-manifest-sha256\t{hashlib.sha256(manifest.read_bytes()).hexdigest()}\n",
        )
        (artifact / "identity.tsv").write_text(identity, encoding="utf-8")
        gate = "schema\tbird-gate-v1\nresult\tPASS\ncheck\tfixture\tPASS\n"
        (artifact / "host-gate.tsv").write_text(gate, encoding="utf-8")
        (artifact / "hardware-gate.tsv").write_text(gate, encoding="utf-8")
        for name in (
            "boot-release.tsv", "boot-profile.tsv", "interaction-ui.tsv",
            "interaction-content.tsv", "idle-power.tsv", "suspend-power.tsv",
            "binary-sections.tsv", "memory.tsv",
        ):
            with (artifact / name).open("a", encoding="utf-8") as output:
                output.write("test\tfixture\n")
        assert not (artifact / "SEALED.sha256").exists()
        result = run("python3", "kernel/rocknix/seal-baseline-evidence.py", str(artifact))
        sealed = (artifact / "SEALED.sha256").read_text().split()[0]
        assert sealed == result.stdout.strip()
        assert sealed == hashlib.sha256((artifact / "inventory.tsv").read_bytes()).hexdigest()
        assert (artifact.stat().st_mode & 0o222) == 0

        promotion = pathlib.Path(temporary) / "promotion.tsv"
        run(
            "python3", "kernel/rocknix/create-promotion-record.py",
            "--manifest", str(manifest),
            "--device-contract", "bird-device-contract.tsv",
            "--catalog", "launcher/catalog.generated.h",
            "--host-gate", str(artifact / "host-gate.tsv"),
            "--hardware-gate", str(artifact / "hardware-gate.tsv"),
            "--evidence-seal", str(artifact / "SEALED.sha256"),
            "--output", str(promotion),
        )
        assert "schema\tbird-promotion-v1" in promotion.read_text()
        failed_gate = pathlib.Path(temporary) / "failed-hardware.tsv"
        failed_gate.write_text(
            "schema\tbird-gate-v1\nresult\tFAIL\ncheck\tfixture\tFAIL\n", encoding="utf-8"
        )
        run(
            "python3", "kernel/rocknix/create-promotion-record.py",
            "--manifest", str(manifest),
            "--device-contract", "bird-device-contract.tsv",
            "--catalog", "launcher/catalog.generated.h",
            "--host-gate", str(artifact / "host-gate.tsv"),
            "--hardware-gate", str(failed_gate),
            "--evidence-seal", str(artifact / "SEALED.sha256"),
            "--output", str(pathlib.Path(temporary) / "must-not-promote.tsv"),
            ok=False,
        )

        inside = ROOT / "measurements-live-test-must-not-exist"
        run("python3", "kernel/rocknix/capture-baseline-evidence.py", str(inside),
            "--mode", "release", "--release-id", "bad", ok=False)
        assert not inside.exists()

        artifact.chmod(0o755)
        for path in artifact.iterdir():
            path.chmod(0o644)

        finalize_artifact = temporary_path / "finalize"
        run("python3", "kernel/rocknix/capture-baseline-evidence.py", str(finalize_artifact),
            "--mode", "release", "--release-id", "finalize-test")
        finalize_identity = dict(
            line.split("\t", 1)
            for line in (finalize_artifact / "identity.tsv").read_text(encoding="utf-8").splitlines()[1:]
        )
        finalize_manifest = temporary_path / "finalize-manifest.tsv"
        finalize_manifest.write_text(
            "schema\tbird-deploy-v1\n"
            "release\tfinalize-test\n"
            f"source-commit\t{finalize_identity['source-head']}\t{finalize_identity['source-state']}\n"
            "input\tKERNEL\t700\t1\t" + "0" * 64 + "\tfixture\n",
            encoding="utf-8",
        )
        build_output = temporary_path / "build"
        (build_output / "build").mkdir(parents=True)
        (build_output / "build/build-flags.tsv").write_text(
            "component\tmode\tflags\nlauncher\trelease\tfixture\n", encoding="utf-8"
        )
        run(
            "python3", "kernel/rocknix/finalize-baseline-evidence.py", str(finalize_artifact),
            "--deploy-manifest", str(finalize_manifest), "--build-output", str(build_output),
        )
        finalized = (finalize_artifact / "identity.tsv").read_text(encoding="utf-8")
        assert hashlib.sha256(finalize_manifest.read_bytes()).hexdigest() in finalized
        assert "KERNEL\t700\t1" in (finalize_artifact / "external-inputs.tsv").read_text()

    print("stage-zero contract/evidence tests: PASS")


if __name__ == "__main__":
    main()
