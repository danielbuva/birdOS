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

The fixed 128 MiB `BIRD` partition uses one rotating pair: one immutable
canonical base plus `dev-current`. Superseded immutable releases are published
and independently verified in the private GitHub release archive, then removed
from the card by the canonical production workflow. The card is not a release-
history store. No alternate kernel, fallback selector, or older UI occupies a
third slot.

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
./dev-build-and-deploy.sh --clean-recovered
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
  not parse `state.tsv`. Before cleanup starts it uses the separately saved
  `base-selector.conf`; after cleanup authority is published it instead uses
  `/Volumes/BIRD/bird-dev-cleanup.tsv`. In either case it validates the exact
  non-development selector and complete release before durably restoring those
  selector bytes. Damaged development metadata remains untouched for diagnosis.
- `--clean-recovered` completes that emergency path without parsing
  `state.tsv`. It requires the active selector to be byte-identical to the
  independently verified saved production selector, inventories every reserved
  development tree, rejects symlinks and special nodes, and removes only
  `dev-current`, its attempt state, stale `.dev-current.new.*` copy stages, and
  `bird-dev` metadata. It resumes an interrupted cleanup from the durable
  cleanup authority and removes that authority only as the final commit.
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

### One-time transition after production-tooling changes

The first development build compares current `HEAD` with the source commit
recorded by the selected production release. If that committed range changes a
full-release-only path, including `build-and-deploy.sh` or
`firmware/mac-update-rocknix-stock-root-v6.sh`, both `--changed` and
`--all-local` intentionally stop before card mutation. A mutable release cannot
prove a change to the production builder or updater that creates it.

Build a clean canonical immutable release from the current commit or a
descendant, run its separate RG34XX-SP physical gate, and only then use that
accepted release as the base for the first `dev-current`. Do not bypass the
refusal or broadly reclassify production tooling as a fast-development input.

Immutable release `v6.23-20260808-214626`, built from clean source
`af83ca945815676d6dabc030ad568c1e5fbb62d2` with deploy-manifest digest
`2a8d51a52e9277e599f6e7a8401513c6c8a2e8edf1e75118360c44a3c5d3eed8`,
passed its RG34XX-SP gate and is the current eligible development base. Any
later committed full-release-only change establishes a new transition and
requires a newer canonical base.

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

The card-side catalog fingerprint mirrors the generator's ordinary metadata
policy: it ignores a path when any relative component starts with `.`,
including `._*`, `.DS_Store` and other hidden entries, or when a component is
`imgs` or `images` case-insensitively. Those names cannot alter the generated
catalog and therefore must not rebuild the launcher or initramfs.

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

### First real all-local capacity result and decision — 2026-08-08

The first complete real-card `--all-local` attempt spent 716.01 seconds in its
host build and required-test gate, then correctly stopped at the actual-output
space check. It required 37,617,684 bytes on `BIRD`; 30,601,728 bytes were
available, a 7,015,956-byte shortfall. The check ran before the card mutation
boundary: the accepted production selector and both immutable releases stayed
unchanged, and no `dev-current`, development metadata, attempt state or hidden
copy stage was published.

At that point the card contained two immutable production releases plus the
fixed fallback. A 128-to-138 MiB p1 migration was built as a possible remedy,
but its installer stopped while comparing the pre-write boot bytes: a root-
owned temporary created by the privileged raw read was not readable by the
following unprivileged comparison. The failure occurred before unmount or raw
write, so the card and its 128 MiB partition remained unchanged. That migration
path is retired rather than repaired.

The adopted policy removes the unnecessary second production release instead.
The canonical workflow first archives and independently verifies a superseded
immutable release in `danielbuva/birdOS-release-archive`. After a successful
canonical activation it makes `extlinux.previous.conf` self-reference the same
base and only then removes the verified old card copy, leaving exactly that one
immutable base and reserving the other release-sized slot for `dev-current`.
The fast command itself still never archives or deletes production to make
room.

The first transition from the old two-production layout has two explicit
reclamations. If staging is short, production preflight archives, re-downloads,
verifies and atomically self-references the selected canonical release before
removing only the already-inactive older release. The selected build source
remains complete even if the later host build fails. After the new canonical
release activates, it applies the same selector-before-removal sequence to the
formerly active source. A later ordinary production cycle normally needs only
that post-activation rotation.

No fallback kernel, alternate selector or boot-attempt retry state is retained.
Manifest verification remains mandatory; a failed boot writes its reason and
stops. Return the card to the host and use the saved verified canonical selector
or redeploy.

## Host transaction safety and recovery

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

These are host-side development-transaction controls, not an automatic device-
boot recovery promise. If `dev-current` cannot boot, return the card to the host
and restore the saved canonical selector or redeploy it.

If `state.tsv` is malformed while `dev-current` remains selected, use
`--recover-production`. Recovery fails closed unless the separately saved
production selector and the complete release it names both verify fully. It
leaves the malformed metadata and development release in place for diagnosis.
After recording any evidence you need, complete the supported recovery with
`--clean-recovered`; that command is also independent of `state.tsv` and refuses
to run unless the exact recovered production selector is active.

Before either cleanup mode changes the selector or removes development bytes,
it atomically publishes `/Volumes/BIRD/bird-dev-cleanup.tsv`. This strict,
versioned record contains the exact production selector, its release and
manifest identity, and the pre-cleanup identities of the previous/fallback
selectors, fallback kernel and fallback DTB. It is independent of `bird-dev`,
is forced durable before deletions on both card filesystems, and remains the
restart authority through a power loss or partially completed recursive
deletion. While it exists, ordinary build, rebase, rollback and clean modes
stop; run `--recover-production`, then `--clean-recovered`. Cleanup removes the
record atomically last only after every reserved development path is gone and
the production and fallback invariants still match.

An interrupted atomic publication can leave only
`.bird-dev-cleanup.tsv.dev-new.*`. That exact prefix is also reserved. Cleanup
inventories and removes only safe regular files with that prefix; production
and ordinary development work refuse them until cleanup completes.

A hard interruption during the first base-release copy can leave a hidden
`.dev-current.new.*` sibling. The prefix is reserved case-insensitively.
Production refuses it, while `--clean`, `--clean-recovered`, and `--rebase`
inventory and remove only exact matching stages. Near matches and unrelated
hidden release directories remain untouched.

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
read safely but report unknown readiness. A durable cleanup authority or an
in-progress cleanup-authority publication prevents
`ready-for-production-build=yes`; depending on the readable development state,
status may report `no` or `unknown`. The readiness value is only the
software-side result; it never records or implies that the RG34XX-SP physical
gate passed.

## Stabilization policy

The workflow is now exercised rather than expanded. Use `--changed` during
ordinary development and record real duration, rebuild scope, output clarity,
rollback/cleanup friction and observed failures. Add fast-path hardening only
for a recurring observed problem, an ordinary misleading result, or a direct
production/data-loss risk. Rare recoverable residue remains documented unless
real use shows that another state transition is justified. Do not add mandatory
promotion-record enforcement, duplicate cleanup authorities or another state
schema merely for theoretical completeness.

The first real `--all-local` run supplied that evidence: its 716.01-second host
gate completed, its exact capacity refusal was truthful, and it performed no
card mutation. The aborted resize likewise performed no raw write. The next
workflow exercise uses the rotating canonical-base plus `dev-current` layout
on the unchanged 128 MiB partition, not another speculative transaction state.

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
`dev-current`, an active or inactive `dev-current` release, any remaining
`bird-dev` metadata, a pending `bird-dev-cleanup.tsv`, interrupted
`.bird-dev-cleanup.tsv.dev-new.*` publications, and stale `.dev-current.new.*`
stages. This prevents
mutable development bytes from becoming a previous selector, rollback release
or archive candidate—or from silently consuming production staging space. The
full command, not `dev-current`, creates the immutable candidate used for
production acceptance and reproducibility evidence. After activation it
archives and verifies every superseded canonical release, makes the previous
selector self-reference the accepted canonical release, and only then removes
the old card copy. A failed boot is handled by returning the card to the host,
not by retaining another production release on p1.
