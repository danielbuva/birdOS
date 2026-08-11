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
and failure semantics. In particular, `deploy-manifest.tsv` is the single
source for both versioned staging and installed-tree verification; the launcher
B button does not select a boot target. On the main page it
refreshes birdOS in-process; it does not retire the early launcher or open the
stock ROCKNIX frontend.

The active launcher uses a Mister Menu ES-DE-inspired 720x480 presentation with
a `HOME` rail, battery-only home top bar, nested breadcrumbs and a fixed opaque
content panel. Its original pinned PNG is converted deterministically at build
time into BMP and native XRGB assets; the launcher performs no runtime image
decode or alpha blend and does not expose selectable rows before input opens.
Final-root recovery always retains the exact 1,382,400-byte XRGB page. Until
U-Boot frame reuse has an exact hardware-verified contract, the early overlay
carries the same native fallback under a 786,432-byte compressed budget; the
verified reuse mode omits that early duplicate and retains the 262,144-byte
budget. The full contract is documented in
[`launcher/README.md`](launcher/README.md).

Use [`ROADMAP.md`](ROADMAP.md) for planned work and
[`ROCKNIX_AUDIT.md`](ROCKNIX_AUDIT.md) for the retained-userspace audit.
Historical measurements and the complete version-by-version narrative live in
[`docs/history/PROJECT_CHRONOLOGY.md`](docs/history/PROJECT_CHRONOLOGY.md).

## Development loop

For supported birdOS-owned launcher, early-initramfs, helper and runtime-file
changes, use the mutable development release instead of rebuilding the whole
product on every iteration:

```sh
./dev-build-and-deploy.sh --changed
```

Use `./dev-build-and-deploy.sh --all-local` for the complete local rebuild and
host-test gate at the end of a development cycle. See
[`DEV_WORKFLOW.md`](DEV_WORKFLOW.md) for supported groups, recovery and the
full-release-only boundary.

`dev-current` is never an accepted release, production rollback, previous
selector or archive candidate. The 128 MiB `BIRD` partition deliberately keeps
only one immutable canonical base plus that mutable development slot. Older
canonical releases live in the private, verified GitHub archive rather than as
an on-card rollback chain. Before starting a canonical production build, remove
the mutable slot and its metadata with:

```sh
./dev-build-and-deploy.sh --clean
./build-and-deploy.sh --release
```

The production path fails closed while `dev-current` or its metadata exists.
If damaged development metadata prevents ordinary rollback while
`dev-current` is selected, `./dev-build-and-deploy.sh --recover-production`
verifies and restores the separately saved production selector without
altering the damaged evidence. After retaining any evidence you need, run
`./dev-build-and-deploy.sh --clean-recovered` to remove only the reserved
development state without trusting the damaged metadata. Production also
refuses stale `.dev-current.new.*` copies left by a hard interruption. Cleanup
is restartable through the durable top-level `bird-dev-cleanup.tsv` authority;
while that record or its `.bird-dev-cleanup.tsv.dev-new.*` publication
temporary exists, recover production and finish with `--clean-recovered`.

After committed production-builder or updater changes, an older production
base intentionally cannot initialize `dev-current`. Build and physically
accept a clean canonical release from the current commit or a descendant first;
then use that release as the development base. See the one-time transition in
[`DEV_WORKFLOW.md`](DEV_WORKFLOW.md).

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

The same preflight accepts the installed PortMaster provider only when its
managed files match the repository-pinned official `2026.07.28-1212` release.
The upstream nested `pylibs.zip` may be absent after first use or present with
its one exact recorded digest; an arbitrary replacement is rejected. Generated
Python caches remain card data but are made inert by redirecting every
PortMaster execution to a fresh `/run/bird` cache prefix with bytecode writes
disabled. A legitimate later network update must be imported into a new exact
manifest before the next birdOS deployment.

The card keeps the selected complete release until its replacement is fully
staged, verified and activated. If the old active-plus-previous layout cannot
fit candidate staging, the guarded planner first archives, independently
verifies and atomically points the previous selector at the selected release,
then removes only the inactive older release; the selected release stays
intact. The command then builds and activates the candidate and archives
the now-superseded active release in the private GitHub repository
`danielbuva/birdOS-release-archive`, independently verifies the published
assets and downloaded manifest, and removes the corresponding card directory
only after those checks pass and the previous selector atomically
self-references the newly activated canonical release. Upload interruption
retains the superseded release and its previous selector and can be resumed
safely.
ROMs, BIOS, media, saves, and `BIRD-DATA` content are outside this lifecycle.

birdOS retains no fallback kernel, fallback selector or alternate UI. Release
verification failures write `bird-loader-failure.txt` and stop without changing
the selector or rebooting. If a candidate does not boot, return the card to the
Mac and repair or redeploy it from the verified canonical base.

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
- [`dev-build-and-deploy.sh`](dev-build-and-deploy.sh): transactional mutable
  `dev-current` build and deployment entry point for supported local changes.
- [`DEV_WORKFLOW.md`](DEV_WORKFLOW.md): development commands, supported
  component map, recovery and production handoff contract.
- [`KERNEL_DELTA.md`](KERNEL_DELTA.md): exact accepted and candidate kernel
  differences from stock ROCKNIX.
- [`launcher/bird-launcher.c`](launcher/bird-launcher.c): active freestanding
  launcher source.
- [`DEVICE_PROFILE.md`](DEVICE_PROFILE.md): fixed hardware and experience
  contract.
- [`docs/history/README.md`](docs/history/README.md): index of superseded paths
  and retained engineering evidence.

An untouched image or spare card can remain external insurance. The card itself
has no fallback kernel, alternate selector, or old UI. A failed boot persists a
diagnostic and returns the card to the host for verified repair or redeployment.
