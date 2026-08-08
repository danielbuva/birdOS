# Fast development workflow

`dev-build-and-deploy.sh` provides a short test cycle for birdOS-owned local
changes. It maintains one explicitly mutable release named `dev-current`
without changing the immutable production release from which it was derived.

The normal release builder exists to reproduce and validate the complete
product: kernel, DTB, ROCKNIX inputs, imported providers, recovery files, the
entire Bird payload, and its deployment transaction. That remains the only
production and promotion path. The development workflow avoids repeating that
work when only local Bird files changed.

`dev-current` is mutable test state. It is never an accepted or archival
production release, production rollback, previous selector or archive target.

## Typical use

With the supported birdOS card mounted at `/Volumes/BIRD` and
`/Volumes/BIRD-DATA`, run:

```sh
./dev-build-and-deploy.sh --changed
```

This compares the current source inputs with the last successfully activated
development build. It builds and installs only the affected component groups.

For a broad local change that still touches only supported Bird-owned files:

```sh
./dev-build-and-deploy.sh --all-local
```

This is the complete local rebuild and host-test gate for the exact current
source inventory. It does not record or imply RG34XX-SP acceptance.

Before removing the card, use the exact safe-eject command printed by a
successful deployment.

## Commands

Exactly one primary mode is required:

```sh
./dev-build-and-deploy.sh --changed
./dev-build-and-deploy.sh --all-local
./dev-build-and-deploy.sh --status
./dev-build-and-deploy.sh --rollback
./dev-build-and-deploy.sh --recover-production
./dev-build-and-deploy.sh --rebase
./dev-build-and-deploy.sh --clean
```

- `--changed` rebuilds groups whose complete source fingerprints changed. The
  first invocation behaves as `--all-local`. Documentation-only and test-only
  changes run their applicable host checks but do not rewrite or reactivate the
  card release. After an explicit rollback, an otherwise unchanged `--changed`
  reselects the already verified `dev-current` without rewriting its payload.
- `--all-local` rebuilds every supported local Bird component while reusing the
  base release's kernel, DTB, ROCKNIX images, imported providers, and recovery
  bytes.
- `--status` is read-only. It reports the selected release, recorded production
  base, `dev-current` verification state, repository provenance, changed
  component groups, unsupported paths, active development profile, requested
  target profile, software readiness, and whether a rebase is required.
- `--rollback` restores the exact saved production selector atomically. It
  leaves `dev-current` installed so it can be selected again by a later build.
- `--recover-production` is the state-independent emergency rollback. It does
  not parse `state.tsv`: it validates the separately saved
  `base-selector.conf`, its non-development release ID, the complete release
  manifest and inventory, completion marker and embedded selector, then
  atomically restores those exact selector bytes. Damaged development metadata
  remains untouched for diagnosis.
- `--rebase` makes the currently selected complete, versioned production
  release the new base, replaces only the identified `dev-current`, applies an
  all-local build, verifies it, and activates it. Select the intended production
  release before using this command. Legacy, fallback, development, malformed,
  and incomplete selectors are refused.
- `--clean` first performs the rollback, then removes only the verified
  `dev-current` release and its development metadata. It never removes,
  archives, or retires a production release.

Available modifiers are:

```sh
--profile
--dry-run
--help
```

- `--profile` selects the supported profiling build mode for build operations
  and previews that target with `--status`. Build mode is part of component
  fingerprints, so changing it causes the affected binaries to be rebuilt.
- `--dry-run` performs classification, verification, and planning without card
  writes.
- `--help` prints command help.

## First run and later updates

On the first development build, the command:

1. verifies the exact supported card and its currently selected complete
   production release;
2. saves an exact copy of that production selector;
3. copies the complete production release once to a new `dev-current`;
4. applies all supported local components from the current working tree;
5. regenerates and verifies the complete development manifest;
6. marks the development release complete and atomically selects it.

Later builds restore the production selector before mutating `dev-current`,
replace only affected manifest-listed files, regenerate the whole development
manifest, and reactivate `dev-current` only after verification succeeds. The
base production release remains byte-for-byte untouched.

Development state is stored outside the immutable release under
`/Volumes/BIRD/bird-dev`. It records the base selector and release, source
provenance, successful component fingerprints, and development-manifest
digest. The `bird-dev-state-v2` state also records the last build kind, the
source inventory for the last complete all-local rebuild, the source inventory
for the required host-test result and the versioned host-test set. Fingerprints
and readiness records are updated only after successful activation and tests.

If the production base on the card no longer matches the recorded base,
`--changed` and `--all-local` stop before card mutation. Select the intended
complete production release and use `--rebase`.

## Supported fast-development groups

### Launcher and embedded catalog

Launcher-affecting changes rebuild both distinct launcher contracts:

- the final-root launcher installed as `bird/bird-launcher`;
- the early-initramfs launcher that normally survives `switch_root`.

They also rebuild only the small external Bird initramfs. They do not rebuild
the kernel, DTB, SYSTEM, or STORAGE image. Catalog changes remain build-time
generated; this workflow does not introduce runtime ROM scanning.

### Small native helpers

The workflow can rebuild the active Bird-owned native helpers already present
in the base manifest, including:

- `bird-pidwait`;
- `bird-powerstate`;
- `bird-fixed-controls`;
- `bird-mpv-controls`.

Each helper replaces only its existing manifest-listed destination.

### Final-root runtime files

Supported manifest-listed files sourced from
`kernel/rocknix/stock-root/` include active scripts, service units, policies,
and configuration files. Their canonical builder mapping is retained: root
files such as `post-flash.sh` and `mount-storage.sh` do not get incorrectly
placed under `bird/`. The development supervisor is specialized to
`RELEASE_ID=dev-current`.

Runtime-only changes do not rebuild the external initramfs.

### Early-initramfs files

Changes to early startup, release loading, init injection, initramfs
normalization, launcher boot-frame generation, the early launcher, or generated
headers consumed there rebuild only the external Bird initramfs. Its embedded
release loader is specialized to `BIRD_LOADER_RELEASE=dev-current`.

### Generated device contract

`generate-device-contract.py` remains authoritative. Contract or generator
changes must first leave all established checked-in generated outputs current;
the workflow rejects stale or hand-edited generated files. It then regenerates
private build outputs, rebuilds local consumers of the generated header,
replaces the existing manifest-listed contract and policy files, and updates
the contract artifact digest.

The embedded catalog follows the same rule. Its header and inventory must
match deterministic generation from the mounted card's ROM and media names.
The workflow rejects stale or hand-edited generated catalog sources rather
than recording source bytes that were not compiled.

## How change detection works

`--changed` does not depend on `git status` alone. Each component fingerprint
covers every known source, generated input, active header, asset, recipe value,
and build mode capable of changing that component's output. It hashes the
actual bytes in the current checkout, including tracked, staged, unstaged, and
untracked inputs.

Repository provenance uses the same convention as the production builder:

- `clean`; or
- `dirty:<sha256>`.

The recorded source commit is the full lowercase 40-character `HEAD` object
ID. Because successful component fingerprints are stored independently of the
working-tree status, a committed change made after the previous development
activation is still detected even when the current worktree is clean.

Resolved compiler, linker, readelf, cpio, and compressor executable bytes are
also fingerprinted. Real development builds require the canonical compiler
tools used by the production path:

```text
CLANG=/opt/homebrew/opt/llvm/bin/clang
LLD=/opt/homebrew/opt/lld/bin/ld.lld
READELF=/opt/homebrew/opt/llvm/bin/llvm-readelf
```

Ambient overrides are rejected outside isolated host fixtures. A later
toolchain identity change is deliberately refused as a full-release-only
boundary. Supported source inputs must be regular, non-symlink files
throughout their repository path.

No active product-source change is silently ignored. An unclassified or
full-release-only path causes the operation to fail before card mutation and
reports why the complete workflow is required.

## Full release required

Use the complete production workflow for changes involving:

- `KERNEL`, the kernel provider, `KERNEL.fallback`, or kernel modules outside a
  proven local mapping;
- `dtb.img` or fallback DTB bytes;
- ROCKNIX `SYSTEM` or `STORAGE`;
- partition layout, card migration, selector/recovery format, or fallback
  selector bytes;
- upstream provider archives, provider inventories, PortMaster imports, or
  KOReader/imported provider bytes;
- pinned external-input or toolchain identity;
- deployment, archive, retirement, or complete-release schema behavior;
- adding or removing a deployed manifest path;
- changing the external-input record set;
- any source path the development classifier cannot safely map.

Changes to `build-and-deploy.sh` or
`firmware/mac-update-rocknix-stock-root-v6.sh` require their own focused tests
and complete release validation. Copying those scripts through `dev-current`
would not test the production path they control.

The fast workflow never archives or deletes a production release to make
space. It builds into a private host directory first, calculates space from the
actual outputs, reports required and available byte counts, and stops without
card writes when there is not enough room.

## Safety and recovery

All card operations reuse the existing card identity and lock checks. Before
changing `dev-current`, the workflow verifies and selects the saved production
base, then invalidates the development completion marker. Production,
fallback, and recovery bytes are checked before activation and are never
development outputs.

If a build, copy, manifest check, or selector activation fails, the production
base remains selected and `dev-current` remains incomplete. The command does
not retry automatically and never falls through to the full builder.

`--rollback` is the normal way to return to production. It restores the saved
selector exactly; it does not reconstruct one from assumptions, change the
fallback or previous selectors, modify fallback kernel/DTB files, or reset
production boot-attempt state.

If `state.tsv` is malformed while `dev-current` remains selected, use
`--recover-production`. Recovery fails closed unless the separately saved
production selector and the complete release it names both verify fully. It
leaves the malformed metadata and development release in place for diagnosis;
it is not a cleanup or repair operation.

## Status and software readiness

Status always separates what is installed from what the next command would
build:

```text
active-dev-profile          release|profile|-
requested-target-profile    release|profile
```

Plain `--status` previews a release target. `--status --profile` previews a
profile target. A different active and requested profile can therefore make
launcher or initramfs groups correctly appear changed; status reports both
values so that result is not mistaken for source drift.

The state-bound readiness lines are:

```text
all-local-current            yes|no|unknown
required-host-tests-current  yes|no|unknown
ready-for-production-build   yes|no|unknown
```

They are current only when the recorded all-local build and versioned required
host-test set match the exact present source inventory. Older state schemas are
read safely but report unknown readiness. `ready-for-production-build` is only
the software-side result; it never records or implies that the RG34XX-SP
physical gate passed.

## Production promotion

The complete handoff runs the software gate, then the development-device
physical gate, then removes all mutable state before invoking the canonical
pipeline:

```sh
./dev-build-and-deploy.sh --all-local
# Verify ready-for-production-build=yes, then run the RG34XX-SP physical gate.
./dev-build-and-deploy.sh --clean
./build-and-deploy.sh --release
```

The production builder and updater reject the reserved release ID
`dev-current`, an active or inactive `dev-current` release, and any remaining
`bird-dev` metadata. This prevents mutable development bytes from becoming a
previous selector, rollback release or archive candidate. The full command,
not `dev-current`, creates the immutable candidate used for production
acceptance, reproducibility evidence, release archival and later rollback.
