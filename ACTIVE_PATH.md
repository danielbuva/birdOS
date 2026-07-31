# Active birdOS path

This document is the authority for the code that builds, installs and runs the
current birdOS system. The active implementation path is **stock-root v6.23**.
Commit `79b6e3e03771f2787622a3e4f6f9d8f129b7281f` is the operator-accepted source
and behavior baseline. The accepted immutable binary fallback is release
`v6.23-20260731-054816`, published as `stable-v6.23-20260731-054816`; its
canonical manifest digest is
`5f95153bf46239a5e178fde28924f01c7fe586be182562f9bd9f33cf13da02ba`.
That older release manifest honestly records its own source as commit
`19ca0bbac47c037a868dac5500aa49c96feeb2f2` plus dirty-state digest
`d0c3a1d805205cb2bb94b95e4c3d4fb89145ca9c1f693ed12079aa70860792b0`;
it is not falsely relabelled as a clean build of `79b6e3e...`. A successor
becomes the optimization baseline only when its exact clean source, release,
manifest, contract and catalogue tuple passes the host and physical gates.

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
| Launcher visual source | [`firmware/assets/bird-launcher-backdrop.png`](firmware/assets/bird-launcher-backdrop.png) and [`firmware/generate-launcher-bootlogo.py`](firmware/generate-launcher-bootlogo.py) |
| Card deployment | [`firmware/mac-update-rocknix-stock-root-v6.sh`](firmware/mac-update-rocknix-stock-root-v6.sh) |
| Legacy Ports data migration | [`firmware/mac-migrate-rocknix-ports.sh`](firmware/mac-migrate-rocknix-ports.sh), run separately before deployment |
| Accepted hardware and product policy | [`DEVICE_PROFILE.md`](DEVICE_PROFILE.md) |
| Current optimization work | [`ROADMAP.md`](ROADMAP.md) and [`ROCKNIX_AUDIT.md`](ROCKNIX_AUDIT.md) |
| Fixed machine-readable hardware contract | [`bird-device-contract.tsv`](bird-device-contract.tsv), compiled through its generated launcher header |

The complete build emits `deploy-manifest.tsv` at the build-output root. That
manifest is the authority for every deployed regular file, required empty
directory, mode and digest, plus every immutable external byte stream consumed
by build or deployment. The updater uses the same file for preflight, staging
and installed-tree verification; a second hand-maintained copy list is not an
independent source of truth.

The manifest records the deployed device contract and its digest plus the
generated catalogue digest. The device contract never refers back to the
manifest. A promotion record created only after the physical gate binds source
SHA, immutable release ID, manifest digest, device-contract digest and
catalogue digest. Live measurements are acquired and sealed outside the source
tree before any optional import under `measurements/`.

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
   digest in that release's `.complete` marker. With a versioned Bird selector,
   the previously selected complete release remains intact throughout staging
   and verification. With the exact fallback selector, the selected complete
   runtime is instead the pinned top-level fallback selector, kernel and DTB;
   those assets remain byte-identical until activation. If the legacy root
   `KERNEL` has already been retired, the build wrapper also pins and preserves
   one fully verified immutable release as its kernel source: the canonical
   versioned previous selector when present, otherwise the lexically greatest
   installed release when the previous selector is the exact fallback.
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

The accepted PortMaster provider is the exact repository-pinned managed
inventory of the official `2026.07.28-1212` tag. Its optional upstream
`pylibs.zip` is accepted only when absent or byte-identical to the recorded
nested archive. Provider-local Python caches are tolerated only because every
PortMaster, Port and KOReader execution redirects Python cache lookup to a fresh
tmpfs prefix and disables bytecode writes; they are never an executable trust
source. The updater may atomically migrate an absent, empty, v1 or v2 checkpoint
after exact verification, but it never rewrites managed provider bytes. A
different v3 checkpoint or unrecognized provider state fails before stale-stage
cleanup or selector mutation.
The full managed-tree verifier runs only during host deployment or a
transactional provider bootstrap. Normal device boots and content launches
validate the exact persistent installation checkpoint, perform bounded
once-per-boot setup, and never rescan or hash the 445 MB provider tree.

When the small `BIRD` partition lacks room for another staged release, the
top-level command uses a guarded lifecycle. It never retires the release named
by the active extlinux selector. It validates the minimum lexically ordered set
of inactive releases needed, including each `.complete` marker, canonical
manifest, file set, modes, sizes and hashes; packages those exact installed
bytes; and publishes every one as an attested release in the private GitHub
archive repository. Only after each release's published assets, attestation and
downloaded canonical manifest verify does it remove that exact inactive
directory. If the byte-identical pinned fallback selector is active, no
versioned Bird release is boot-selected, but the selected fallback runtime
remains on-card and its selector hash is rechecked before every archive and
removal. When that build needs an immutable release kernel, the fully verified
source release is pinned and excluded from retirement until the replacement
release is staged, verified and activated. A malformed previous selector, a
near-match to the fallback selector, or an unavailable or corrupt deterministic
source fails closed. A draft or failed upload is resumable and does not change
the selector. GitHub release
immutability must be enabled or reclamation is refused. The new card release is
then built and installed through the same canonical builder and transactional
updater described above.

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
   release with the `bird_release` command-line parameter. It maps fbcon away
   from the fixed panel and disables the VT cursor while retaining the serial
   console, so Sway teardown cannot clear the launcher-owned framebuffer or
   expose a console cursor before the replacement launcher takes ownership.
2. **Early overlay:** the overlaid ROCKNIX init calls `bird-early.sh start`
   after the special filesystems exist. It creates the storage event channel,
   loads the exact H700 input module and starts the static framebuffer launcher.
3. **First usable menu:** the launcher makes one immediate named-input scan
   before inspecting framebuffer recovery. If input is not already available,
   it paints a launcher-owned base with no menu rows before entering the bounded
   input wait. Only after input is open does it paint interactive rows, execute
   the framebuffer barrier and publish first-frame readiness. From that marker,
   every zero-time input poll and complete drain may advance at most one deferred
   profiling, logging, checkpoint, power, storage or Favorites task; input,
   reconnect and exit work always interrupt that sequence. Its cached catalogue
   does not require a boot-time ROM scan. List viewports use fixed nine-row
   pages: movement within a page redraws only the old and new rows plus status,
   while crossing a page boundary redraws the bounded content region. The
   persisted selection deterministically restores its containing page. After
   startup is complete, the one-shot storage FIFO consumes at most one read
   attempt per post-input background slot. Power uevents consume at most eight
   read attempts per slot and coalesce matching records into one sysfs snapshot
   and at most one battery render; any unread tail yields to another complete
   input sample. Generated catalogue access is isolated behind fixed-index
   accessors. The generator rejects duplicate canonical game or media paths and
   emits one game-path order for logarithmic Favorites lookup. Favorites load
   publishes a fixed catalogue-ordered `u16` member index in one bounded bitmap
   pass, independent of file order; browsing and saving then touch only the
   requested ordinal or the actual member count, while the persistent file
   remains exact-path based and reorder-compatible. The generated catalogue
   stores exact UTF-8 strings once in an immutable NUL-terminated pool and
   represents every logical record with naturally aligned `u32` pool offsets,
   `u32` ranges and `u8` identities. Accessors return stable pointers directly
   into that pool, so rendering and handoff do no runtime decoding or path
   reconstruction and the launcher carries no catalogue pointer-relocation
   table.
4. **Stock-root preparation:** the selected initramfs uses its immutable
   `bird-release-loader.sh`, not the mutable top-level compatibility hook. The
   loader requires the exact `bird_release` selector, validates the complete
   release and its manifest-listed versioned `post-flash.sh`, then sources that
   hook. The hook transactionally records the boot attempt, revalidates every
   runtime file it will expose, binds the release's `mount-storage.sh` and
   `bird/` tree over the fixed boot targets, mounts p6 and binds the pinned
   `SYSTEM` image into ROCKNIX's normal handoff. Once those exact binds and the
   launcher's honest input-open framebuffer barrier both exist, the hook
   transactionally commits that release's boot health. A later user refresh or
   reboot from an already-usable menu is therefore never charged as a failed
   full-stack attempt. Previous initramfs images keep
   their original top-level hook, so changing the extlinux selector is the only
   runtime activation boundary. The selected mount helper then publishes the
   fixed ROM/BIOS view. Runtime files copied into the writable storage image
   have their exact modes repaired by the pinned BusyBox in the already-mounted
   SYSTEM tree; the smaller initramfs BusyBox intentionally has no `chmod`
   applet. Init checks the selected mount helper's result explicitly. A failed
   storage transaction leaves the interactive early launcher in control and
   records `mount-storage-latest.log` on p6 instead of continuing into a
   partially configured stock frontend.
5. **Persistent launcher ownership:** after `prepare_sysroot` establishes the
   final tree, init signals the early launcher. The launcher retains exact
   storage and configuration descriptors and acknowledges them before special
   mounts move. The same process remains the input owner across `switch_root`.
6. **Final-root supervision:** systemd starts the stable birdOS supervisor at
   the graphical boundary. It adopts the early launcher through the PID waiter
   or starts a replacement when adoption is unavailable. Launcher health races
   first-frame readiness against child exit and uses bounded local recovery for
   recoverable startup failures. A usable early launcher may complete an
   authoritative content, shutdown or PortMaster handoff before
   the supervisor exists. In that case only the conjunction of
   the fresh interactive-frame
   marker and an exact atomically published action is accepted as boot health;
   the release-scoped attempt reset must become durable before the action is
   consumed. A failed reset leaves the action intact for a supervisor retry.
7. **Application contract:** retained ROCKNIX setup continues asynchronously.
   Its final export publishes a revisioned ready marker only after every
   required profile and link is validated. A queued selection remains intact
   when that contract cannot be completed.
8. **Content session:** `run-content.sh` maps the cached content identity to the
   pinned ROCKNIX provider, joins only the services needed by that selection
   and places the complete foreground tree inside one enforceable session
   boundary. Normal return and the global exit chord both terminate and reap
   the entire boundary before the launcher resumes. Before a content or
   PortMaster handoff, the launcher first commits authoritative UI state and
   may atomically publish a volatile descriptor bound to the exact visible RGB
   pixels of the measured one-page XRGB8888 framebuffer plus the displayed
   battery and Favorites state. An independent descriptor digest protects that
   snapshot from accidental corruption. The unused X byte is fingerprinted only
   for diagnostics because the measured format declares no transparency bits
   and DRM/fbdev ownership changes may normalize that non-visible byte. A
   replacement launcher preserves the frame only when input was already
   reopened and the exact format, UI state and all visible RGB pixels match; it
   then updates only the return-status region. A sealed descriptor with changed
   visible RGB still restores the exact Favorites and displayed-power snapshot
   before the normal full-render fallback. Missing, stale, dirty, corrupt,
   UI-mismatched or unsupported state takes the full-render path without trusting
   snapshot data. The descriptor lives only in `/run`, cannot authorize a
   content launch and is cleared after startup or any failed handoff.
9. **Fixed controls and power:** the separate controls and power workers own
   system volume, brightness, lid/power suspend and the low-battery LED policy.
   The kernel/PMIC owns charging state; the launcher only observes and displays
   it. These responsibilities are not linked into the launcher. Optional
   networking is released only for direct PortMaster.
10. **Shutdown:** systemd retains ordered shutdown. The birdOS configuration
    checkpoint is an atomic, verified transaction and reports failure instead
    of publishing a false successful checkpoint. The supervisor bounds only the
    nonblocking systemd client to three seconds and resumes the launcher if the
    request was not accepted; accepted requests continue through ordinary
    ordered systemd shutdown. The real p6 data mount lives at `/run/bird-data`,
    outside the `/storage` loop filesystem backed by a file on p6. A bind alias
    publishes it at `/storage/bird-data`, permitting shutdown to unmount nested
    aliases, then the loop filesystem, and finally p6 without a mount/backing-
    filesystem cycle. The next boot archives the prior shutdown trace before a
    later request can overwrite it.

## Launcher visual architecture

The active 720x480 launcher presentation is inspired by Mister Menu's ES-DE
layout, but it remains birdOS's freestanding direct-framebuffer implementation;
ES-DE is not a launcher runtime dependency. The original source artwork is the
pinned 720x480 RGB PNG
[`firmware/assets/bird-launcher-backdrop.png`](firmware/assets/bird-launcher-backdrop.png).
The build-time generator verifies that PNG's format and SHA-256, decodes it on
the host, and deterministically emits a fully composited bottom-up 24-bit BMP
and a sparse one-page native XRGB8888 wallpaper image plus their digest
contract. The native artifact is exactly 720x480, top-down, 2,880-byte stride,
page offset 0:0 and `B,G,R,X` memory order. The opaque top bar, menu container
and menu shadow are subtracted to zero in that artifact. The PNG is the only
editable wallpaper source in the repository; neither PNG nor BMP is shipped to
or decoded by the launcher. Runtime recovery maps the native bytes, copies only
visible wallpaper spans and composes fixed chrome before one framebuffer
barrier.

The home view has a narrow vertical rail labelled `HOME`; its cream top bar is
otherwise reserved for the vertical battery icon and percentage. Nested Play, Systems,
Favorites and media views place their full path in the top bar as fixed
breadcrumbs while retaining the battery at the right. The content surface is
a fixed opaque burgundy panel over the backdrop. It does not use per-pixel
alpha or runtime alpha blending. The centered 400x288 content surface keeps
nine complete rows and the MiSTer reference's 1.39 panel aspect ratio. The
footer has no panel or visible diagnostic line: a fixed wallpaper strip is
restored before control-hint changes, with a 96,000-byte static inherited-frame snapshot as the only
fallback when no native base is mapped. The static backdrop and chrome may be painted
while the named evdev device is still unavailable, but all selectable menu rows
remain hidden until input has opened. Only that interactive overlay and its
framebuffer barrier can publish first-frame readiness.

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

The final-root recovery payload always carries
`/flash/bird/launcher-base.xrgb`, the exact 1,382,400-byte sparse native XRGB page
generated from the pinned source. Until inherited U-Boot frame reuse is proven
on the RG34XX-SP, the early initramfs carries the same native page at
`/opt/bird/launcher-base.xrgb`; its compressed-overlay ceiling is therefore
786,432 bytes. `BIRD_REUSE_UBOOT_FRAME=1` is accepted only with an external
hardware-verified contract byte-identical to the generated build contract. In
that verified mode the early payload omits the duplicate XRGB page and returns
to the retained 262,144-byte compressed-overlay ceiling. The final-root asset
remains present in either mode for recovery after content. No mode introduces
a runtime PNG or BMP decoder.
Current enforced budgets are 600,000 release / 660,000 profile bytes for the
final launcher, 610,000 / 670,000 bytes for the early launcher, 786,432
compressed early-overlay bytes with the native fallback or 262,144 bytes with
verified U-Boot reuse, 2,100,000 physical framebuffer bytes for a cold Phase 5A
base-plus-menu render, 500,000 bytes for a verified inherited-base menu overlay
and 65,536 bytes for a matched application return. The generated boot contract
separately records 345,600 logical pixels, 1,036,800 visible bytes, one
framebuffer page and 1,382,400 physical XRGB bytes.
The current generated catalogue additionally enforces host-test ceilings of
460,000 immutable string-pool bytes, 56 KiB of fixed-width logical records and
16 KiB for the path-order index. Exact binary and section sizes remain reported
benchmark outputs rather than brittle equality contracts.

## Recovery semantics

Automatic boot recovery and the launcher's B button are unrelated:

- The boot-attempt guard records attempts in state scoped to the selected
  release, so staging or failed activation cannot reset the prior release's
  health journal. The selected hook resets that state as soon as the verified
  runtime and honest interactive-frame marker coexist; only boots that fail
  before that usable boundary consume the threshold. After the fixed failure
  threshold, it validates
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
- B navigates back inside nested launcher views. On the main page it returns
  the selection to `PLAY` with an ordinary dirty-row update and is intentionally
  absent from the footer legend. It does **not** retire the early owner, open a
  stock ROCKNIX frontend, count as a runtime failure or select the boot
  fallback.

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
