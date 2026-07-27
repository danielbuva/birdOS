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

## Repository map

- [`ACTIVE_PATH.md`](ACTIVE_PATH.md): authoritative active build, deployment,
  boot and runtime graph.
- [`kernel/rocknix/build-stock-root-compat.sh`](kernel/rocknix/build-stock-root-compat.sh):
  complete accepted-baseline build.
- [`kernel/rocknix/stock-root/`](kernel/rocknix/stock-root/): active final-root
  integration sources.
- [`firmware/mac-update-rocknix-stock-root-v6.sh`](firmware/mac-update-rocknix-stock-root-v6.sh):
  guarded transactional card deployment.
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
