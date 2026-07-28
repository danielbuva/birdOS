# Active birdOS path

This document is the authority for the code that builds, installs and runs the
current birdOS system. The accepted implementation is **stock-root v6.23**.
The complete host fault-injection suite and broad RG34XX-SP physical gate
passed on 2026-07-26. The accepted release manifest digest is
`e441f9c2755173353a9d29969807c2a05411240b7e9d2a1d18ed099d3c91b4d2`.

birdOS targets one device: the Anbernic RG34XX-SP. Fixed paths, device names,
display geometry and hardware policy are deliberate. Older muOS stages,
source-kernel challengers and clean-root experiments remain useful evidence,
but they are not alternate active implementations.

## Authority

| Responsibility | Canonical source |
| --- | --- |
| Complete stock-root build | [`kernel/rocknix/build-stock-root-compat.sh`](kernel/rocknix/build-stock-root-compat.sh) |
| Early initramfs overlay | [`kernel/rocknix/build-stock-root-early-initramfs.sh`](kernel/rocknix/build-stock-root-early-initramfs.sh), invoked by the complete build |
| Final-root integration | [`kernel/rocknix/stock-root/`](kernel/rocknix/stock-root/) |
| Launcher | [`launcher/bird-launcher.c`](launcher/bird-launcher.c) and its generated catalogue |
| Card deployment | [`firmware/mac-update-rocknix-stock-root-v6.sh`](firmware/mac-update-rocknix-stock-root-v6.sh) |
| Legacy Ports data migration | [`firmware/mac-migrate-rocknix-ports.sh`](firmware/mac-migrate-rocknix-ports.sh), run separately before deployment |
| Accepted hardware and product policy | [`DEVICE_PROFILE.md`](DEVICE_PROFILE.md) |
| Current optimization work | [`ROADMAP.md`](ROADMAP.md) and [`ROCKNIX_AUDIT.md`](ROCKNIX_AUDIT.md) |

The complete build emits `deploy-manifest.tsv` at the build-output root. That
manifest is the authority for every deployed regular file, required empty
directory, mode and digest, plus every immutable external byte stream consumed
by build or deployment. The updater uses the same file for preflight, staging
and installed-tree verification; a second hand-maintained copy list is not an
independent source of truth.

Generated files below `kernel/work/` are build results, not source. The
committed `launcher/bird-launcher.o`, old card-side installers and historical
payload checksums do not participate in the active stock-root build unless the
complete builder names them explicitly.

## Pinned compatibility base

The active baseline retains the exact ROCKNIX `20260701` DDR4 compatibility
base:

- the release `KERNEL` and `dtb.img`;
- the immutable ROCKNIX `SYSTEM` image;
- the captured, configured writable `STORAGE` image; and
- the release-matched H700 joypad module used by the early overlay.

The complete builder verifies these inputs before generating birdOS files.
birdOS currently changes the external initramfs overlay, launcher, fixed
services, integration scripts and activation metadata. It does not claim to
rebuild or trim the release kernel yet.

## Build and deployment

The normal macOS entry point is `./build-and-deploy.sh --release`, or
`./build-and-deploy.sh --profile` for lightweight launcher counters. It chooses
one release ID before the build, passes that ID to both canonical scripts and
selects a fresh timestamped ID whenever the preferred immutable directory or
archived GitHub release tag is already occupied. `--release-id ID` chooses a
different preferred ID and `--dry-run` performs the read-only preflight only.

1. `build-stock-root-compat.sh` validates the pinned upstream inputs and the
   exact upstream files it consumes.
2. It compiles the final-root launcher, PID waiter, controls worker and power
   worker, generates the reduced autostart coordinator, and invokes the early
   overlay builder.
3. It assembles a complete release card tree and emits the canonical
   `deploy-manifest.tsv` only after validating scripts, binaries, units and
   upstream identities.
4. The Mac updater validates the removable-card identity and immutable inputs,
   then stages the complete release in a hidden sibling below
   `/flash/bird-releases/` without modifying the active runtime.
5. It verifies the staged tree against the release manifest, atomically
   renames it to `/flash/bird-releases/<release-id>`, and records the manifest
   digest in that release's `.complete` marker. The previously selected complete
   release remains intact throughout staging and verification.
6. The active extlinux entry refers only to its versioned kernel,
   initramfs and DTB paths and passes the matching `bird_release` ID. One verified
   temporary-file rename of `/flash/extlinux/extlinux.conf` is the activation
   point; the separate fallback entry names its preserved top-level assets.
7. Legacy same-volume Port layout conversion is an explicit card-data migration
   performed by
   [`firmware/mac-migrate-rocknix-ports.sh`](firmware/mac-migrate-rocknix-ports.sh),
   outside the runtime transaction. The updater refuses a nonempty legacy tree
   or an unverified PortMaster provider, so both conditions must be resolved
   before selector activation without producing a mixed birdOS runtime.

When the small `BIRD` partition lacks room for another staged release, the
top-level command uses a guarded two-slot lifecycle. It never retires the
release named by the active extlinux selector. It validates one inactive
release's `.complete` marker, canonical manifest, file set, modes, sizes and
hashes; packages those exact installed bytes; and publishes them as an attested
release in the private GitHub archive repository. Only after the published
assets, attestation, and downloaded canonical manifest verify does it remove
that exact inactive directory. A draft or failed upload is resumable and does
not change the card. GitHub release immutability must be enabled or reclamation
is refused. The new card release is then built and installed through the same
canonical builder and transactional updater described above.

The builder fixes locale, timezone, umask and generated filesystem metadata,
and it rejects a persistent source-tree change during the build. Repeatability
is tested with the current host toolchain across distinct output paths and host
settings. The Homebrew compiler and archive tools are not yet hermetically
pinned across future upgrades; that stronger cross-host guarantee belongs to
the complete-image work in the roadmap. Release and installed bytes are still
fully content-addressed by the canonical manifest.

The host transaction covers updater process interruption: before the selector
rename, the previous complete runtime remains selected; after a verified
rename, only the complete new release is selected. A partially copied tree is
never a valid activation target. The selector lives on FAT, so this is not a
claim that arbitrary power loss during a FAT metadata update is boot-atomic.
True power-loss recovery requires the later U-Boot A/B design in the roadmap.

## Boot and runtime sequence

1. **Bootloader:** extlinux selects the active release's versioned unchanged
   ROCKNIX kernel and DTB plus its `bird-initramfs.cpio.gz`, and identifies that
   release with the `bird_release` command-line parameter.
2. **Early overlay:** the overlaid ROCKNIX init calls `bird-early.sh start`
   after the special filesystems exist. It creates the storage event channel,
   loads the exact H700 input module and starts the static framebuffer launcher.
3. **First usable menu:** the launcher paints before generic final-root work,
   opens the named H700 input device and publishes first-frame readiness only
   when input is usable. Its cached catalogue does not require a boot-time ROM
   scan.
4. **Stock-root preparation:** the selected initramfs uses its immutable
   `bird-release-loader.sh`, not the mutable top-level compatibility hook. The
   loader requires the exact `bird_release` selector, validates the complete
   release and its manifest-listed versioned `post-flash.sh`, then sources that
   hook. The hook transactionally records the boot attempt, revalidates every
   runtime file it will expose, binds the release's `mount-storage.sh` and
   `bird/` tree over the fixed boot targets, mounts p6 and binds the pinned
   `SYSTEM` image into ROCKNIX's normal handoff. Previous initramfs images keep
   their original top-level hook, so changing the extlinux selector is the only
   runtime activation boundary. The selected mount helper then publishes the
   fixed ROM/BIOS view.
5. **Persistent launcher ownership:** after `prepare_sysroot` establishes the
   final tree, init signals the early launcher. The launcher retains exact
   storage and configuration descriptors and acknowledges them before special
   mounts move. The same process remains the input owner across `switch_root`.
6. **Final-root supervision:** systemd starts the stable birdOS supervisor at
   the graphical boundary. It adopts the early launcher through the PID waiter
   or starts a replacement when adoption is unavailable. Launcher health races
   first-frame readiness against child exit and uses bounded local recovery for
   recoverable startup failures.
7. **Application contract:** retained ROCKNIX setup continues asynchronously.
   Its final export publishes a revisioned ready marker only after every
   required profile and link is validated. A queued selection remains intact
   when that contract cannot be completed.
8. **Content session:** `run-content.sh` maps the cached content identity to the
   pinned ROCKNIX provider, joins only the services needed by that selection
   and places the complete foreground tree inside one enforceable session
   boundary. Normal return and the global exit chord both terminate and reap
   the entire boundary before the launcher resumes.
9. **Fixed controls and power:** the separate controls and power workers own
   system volume, brightness, lid/power suspend and the low-battery LED policy.
   The kernel/PMIC owns charging state; the launcher only observes and displays
   it. These responsibilities are not linked into the launcher. Optional
   networking is released only for PortMaster.
10. **Shutdown:** systemd retains ordered shutdown. The birdOS configuration
    checkpoint is an atomic, verified transaction and reports failure instead
    of publishing a false successful checkpoint.

## Readiness contracts

The first frame, storage anchor, application contract and content session are
different boundaries:

- **First frame ready** means the menu is visible and input works.
- **Storage ready** means the first launcher has retained the final content and
  configuration tree; it does not gate the first frame.
- **Application contract ready** means the retained ROCKNIX profiles and links
  required to launch content have all been validated for the expected contract
  revision.
- **Content session active** means one selected provider owns its supervised
  process boundary. It must become empty before birdOS resumes the menu.

No later marker may be inferred from an earlier one.

## Recovery semantics

Automatic boot recovery and the launcher's B button are unrelated:

- The boot-attempt guard records attempts in state scoped to the selected
  release, so staging or failed activation cannot reset the prior release's
  health journal. After the fixed post-init failure threshold, it validates
  and activates the
  preserved clean-root fallback selector through a verified temporary-file
  rename before rebooting.
- Release-loader or post-flash verification failure takes the same verified
  fallback path immediately, before the full-stack attempt threshold applies.
- The current fallback cannot execute before the selected release loader. A
  kernel, external-initramfs or earlier hang still requires manual selector
  recovery; automatic recovery across that boundary requires the later
  U-Boot-owned A/B design.
- `KERNEL.fallback` and the fallback extlinux configuration are offline boot
  recovery assets. They are preserved and verified by deployment.
- B navigates back inside nested launcher views. On the main page it returns a
  dedicated user-reload result that immediately restarts the birdOS launcher;
  it does **not** open a stock ROCKNIX frontend, count as a runtime failure or
  select the boot fallback. The active UI describes this as `B RELOAD`.

## Acceptance boundary

The accepted v6.23 baseline includes early menu/input, asynchronous fixed storage,
cached games and media, Favorites, exact-page return, supported game/media
dispatch, system volume and brightness, charging display, suspend/wake,
global foreground exit and shutdown. The v6.23 hardening pass adds deployment,
fallback, readiness, supervision and persistence correctness around those
behaviors. The physical gate also accepts movie resume, internal-speaker audio,
ROCKNIX volume/brightness notifications, Y-button Favorites, native Menu+Start
for RetroArch and PPSSPP alongside Bird's Select+Start global exit, native and
translated Ports, fMSX, standalone PSP, OpenBOR, N64 audio and DraStic's
non-striped desktop-OpenGL presentation. Brightness exposes stable 5, 3 and 1
percent low ticks; wake strikes the panel at its measured 10-percent threshold
for 50 ms and restores the exact saved dim value.

Kernel trimming, U-Boot timing, earlier LED/display assertion, emulator and
PortMaster performance, final media controls, final boot effects and complete
shim removal remain roadmap work. Their absence is not evidence that the
active stock-root path is incomplete.

## Accepted v6.23 evidence

The v6.23 baseline completed these gates:

1. Build from the pinned inputs and verify every release file through
   `deploy-manifest.tsv`.
2. Inject updater process termination before, during and after release staging
   and selector publication, then prove the selected path names only a complete
   release. This host test does not substitute for bootloader-level power-loss
   recovery.
3. Exercise failed application export, launcher pre-frame exits, content that
   forks/reparents or ignores TERM, auxiliary-descriptor failure, over-limit
   catalogue paths and shutdown-checkpoint failure.
4. On the RG34XX-SP, repeat early input/storage timing plus the broad game,
   media, Ports, volume, brightness, suspend/wake, global-exit and shutdown
   suite.
5. Exercise the automatic attempt threshold and verify that the preserved
   clean-root kernel boots after the verified fallback selector publication.

The macOS suite drives the real registration dispatcher and cleanup functions
with fault-injected manager states. The device gate validates the required
user-visible behavior and managed exit paths. Future changes to Linux systemd
scope/cgroup ownership still require an on-device adversarial check in addition
to the host suite.

## Historical material

The rest of the repository records many deliberately superseded experiments.
Start at [`docs/history/README.md`](docs/history/README.md) before using them.
Historical files may document a result accurately for their own stage while no
longer describing the active runtime. When history and this document disagree
about what currently builds or boots, this document and the canonical build
graph win.
