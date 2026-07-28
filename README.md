# birdOS

birdOS is a fixed-purpose operating system for the Anbernic RG34XX-SP. This
repository contains its launcher, fixed-device integration, reproducible build
inputs and the engineering record that began with muOS 2601.1. The accepted
hardware baseline is **stock-root v6.23**: it retains the exact ROCKNIX
20260701 DDR4 compatibility base and replaces its frontend and selected generic
policy with birdOS. Its 2026-07-26 physical gate and host fault-injection suite
passed with canonical deploy-manifest digest
`e441f9c2755173353a9d29969807c2a05411240b7e9d2a1d18ed099d3c91b4d2`.

The governing priority is: boot latency, interaction latency, battery
efficiency, memory efficiency, then exact user features. Generality is a cost,
not a feature. Every persistent process, wake-up, probe, parser and loaded byte
must serve this one device and this one experience.

## Start here

[`ACTIVE_PATH.md`](ACTIVE_PATH.md) is the authority for the current build,
deployment transaction, boot sequence, readiness contracts, runtime ownership
and recovery semantics. In particular, `deploy-manifest.tsv` is the single
source for both versioned staging and installed-tree verification; the launcher
B button does not select the preserved boot fallback.

Use [`ROADMAP.md`](ROADMAP.md) for planned work and
[`ROCKNIX_AUDIT.md`](ROCKNIX_AUDIT.md) for the retained-userspace audit.
Historical measurements and the complete version-by-version narrative live in
[`docs/history/PROJECT_CHRONOLOGY.md`](docs/history/PROJECT_CHRONOLOGY.md).

## Build and deploy from macOS

Insert the RG34XX-SP card and wait for exactly one `BIRD` and one `BIRD-DATA`
volume to mount. From the repository root, use one command:

```sh
./build-and-deploy.sh --release
```

For a launcher profiling build:

```sh
./build-and-deploy.sh --profile
```

To name the preferred immutable release explicitly, or to perform a read-only
preflight without deleting, building, or deploying anything:

```sh
./build-and-deploy.sh --release --release-id v6.24
./build-and-deploy.sh --profile --dry-run
```

If the preferred ID is already present on the card or in the GitHub archive,
the command automatically selects an unused timestamped ID. It never overwrites
a completed release. The
command verifies the fixed removable-card identity, pinned inputs, toolchain,
free space and generated canonical manifest before invoking the existing
transactional updater.

The card keeps the selected complete release until its replacement is fully
staged and verified. If `BIRD` needs staging space, the command may select one
inactive complete release, verify its installed manifest and every file, and
archive its exact bytes in the private, immutable GitHub release repository
`danielbuva/birdOS-release-archive`. It removes that inactive directory only
after GitHub release attestation, asset verification, and a downloaded-manifest
comparison all succeed. Upload interruption leaves the inactive card release
and boot selector unchanged; rerunning the same command resumes a draft archive.
ROMs, BIOS, media, saves, and `BIRD-DATA` content are outside this lifecycle.

Run `./build-and-deploy.sh --help` for the complete contract and, after a
profiling boot, collect
`BIRD-DATA/MUOS/Bird/log/early-initramfs-latest.log`.

## Repository map

- [`ACTIVE_PATH.md`](ACTIVE_PATH.md): authoritative active build, deployment,
  boot and runtime graph.
- [`kernel/rocknix/build-stock-root-compat.sh`](kernel/rocknix/build-stock-root-compat.sh):
  complete accepted-baseline build.
- [`kernel/rocknix/stock-root/`](kernel/rocknix/stock-root/): active final-root
  integration sources.
- [`firmware/mac-update-rocknix-stock-root-v6.sh`](firmware/mac-update-rocknix-stock-root-v6.sh):
  guarded transactional card deployment.
- [`build-and-deploy.sh`](build-and-deploy.sh): guarded one-command macOS build,
  manifest validation and deployment entry point.
- [`launcher/bird-launcher.c`](launcher/bird-launcher.c): active freestanding
  launcher source.
- [`DEVICE_PROFILE.md`](DEVICE_PROFILE.md): fixed hardware and experience
  contract.
- [`docs/history/README.md`](docs/history/README.md): index of superseded paths
  and retained engineering evidence.

An untouched recovery image or card remains valuable external insurance. The
active card can select its verified clean-root fallback automatically once the
release loader is running, as described in [`ACTIVE_PATH.md`](ACTIVE_PATH.md).
A kernel or initramfs failure
before that loader still requires manual selector recovery; bootloader-owned
A/B recovery remains roadmap work.
