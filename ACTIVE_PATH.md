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

The card currently selects the repaired Stage 5 diagnostic-slot candidate
`v6.23-stage5-slot-d0c6e4e`, built from clean public source
`d0c6e4edb02753f3f006ad2513976ce25b87cbfa`. Its previous selector is the
physically accepted corrected-counter implementation
`v6.23-stage5-counters-9945f9d`. The selected release's canonical manifest
digest is
`bcf8e4575878ba81f8ffd854037436e2876a859148f959d167fe1c1981c8df95`,
and deployment verified all 69 manifest-owned files. The device-contract digest is
`eca6a008947c927ca1b47efc275f7e3bde1a94735223837a353db7db2acf0b40`
and the generated-catalog digest is
`7e29e491bb43191ca9ae6c18bd566b6ba0c984bf43d1d0103eddd6e534306e62`.
The immutable-dispatcher, immutable-supervisor, first-frame-preparation and
boot-snapshot, complete-toolset, content-shell, fixed-autostart, fixed-session,
fixed-housekeeping, fixed-application-profile, fixed-performance and warm-
manager batches passed their RG34XX-SP gates. The manager experiments proved
that on-demand seatd and post-coldplug udevd exit move work into content launch,
so both remain warm. HDMI and Bluetooth remain unchanged; retention or removal
of either is an explicit later product decision. None of these tuples
replaces the broader source/behavior baseline or immutable fallback named above.

Optimization is lexicographic: honest usable menu first; navigation plus every
launch, close and interactive return second; calibrated battery life third;
memory/storage fourth. Interaction and battery use measured fixed-consumer
decisions rather than an all-warm or all-cold rule. A launch-critical process
may remain prepared when its latency benefit is material; unrelated residency
requires a measured energy justification and may be quiesced only inside the
frozen boot/interaction margins.

The operational tie-break is temporal. While a requested navigation, launch,
switch, close or menu-return transition is active, responsiveness wins and
noncritical cleanup is deferred. Once responsive ownership is established and
no action is pending, battery wins and the system should converge promptly to
its lowest practical idle state. Small precomputed or cached state may remain
when its measured common-action benefit justifies idle energy; entire generic
services do not remain warm by default.

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
downloaded canonical manifest verify does it safely inventory and extract the
published archive, then validate every archived path and byte against that same
manifest before removing the exact inactive directory. Archive tar-header
identity is deliberately not an authority: directory timestamps can change tar
bytes without changing the canonical release payload. If the byte-identical
pinned fallback selector is active, no
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
   release with the `bird_release` command-line parameter. The current Stage 1
   candidate maps fbcon away from the fixed panel and disables the VT cursor
   without enabling the serial console on the production entry, so Sway teardown
   cannot clear the launcher-owned framebuffer or expose a console cursor before
   the replacement launcher takes ownership. The previous release selector and
   fixed fallback retain `console=ttyS0,115200` for diagnostics and recovery
   until this candidate completes its physical gate.
2. **Early overlay:** the overlaid ROCKNIX init calls `bird-early.sh start`
   after the special filesystems exist. It creates the storage event channel,
   loads the exact H700 input module and starts the static framebuffer launcher.
3. **First usable menu:** the launcher installs a `/dev/input` creation watch,
   tries the measured event hint and makes one complete named-input recovery
   scan before inspecting framebuffer recovery. If input is not already
   available, it paints a launcher-owned base with no menu rows, then blocks on
   the watch and validates only newly created numbered event nodes. A queue
   overflow permits a complete rescan; unavailable inotify retains the bounded
   polling fallback. An H700 name match is accepted only when its complete
   input ID and event/key/absolute/force-feedback bitmaps match the generated
   fixed-device contract; the retained legacy mapping remains name-based. The
   launcher also installs a `/dev` watch before probing the one fixed `fb0`
   node, accepts only its create/move events and uses the prior 1 ms polling
   path only when inotify is unavailable. Queue overflow permits one exact
   reprobe. Geometry, stride, format and mapping are still validated before
   use. Only
   after input is open does it paint interactive rows, execute the framebuffer
   barrier and publish first-frame readiness. From that marker,
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
   fixed ROM/BIOS view. The replacement launcher now executes from the selected
   immutable `/flash/bird` tree and is neither copied nor rewritten on p6.
   Remaining compatibility files copied into the writable storage image have
   their exact modes repaired by the pinned BusyBox in the already-mounted
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
   or starts a replacement directly from `/flash/bird/bird-launcher` when
   adoption is unavailable. Launcher health races
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
   Returned hardware evidence on `v6.23-framebuffer-watch-84a2435` exercised
   this path: the replacement launcher started at 32033 ms, reopened H700 input
   at 32034 ms and published at 32091 ms with `render=recovery`, a restored
   snapshot, zero visible-region mismatches, stable unused X bytes and exact
   matching bound hashes.
9. **Fixed controls and power:** the separate controls and power workers own
   system volume, brightness, lid/power suspend and the low-battery LED policy.
   The kernel/PMIC owns charging state; the launcher only observes and displays
   it. The controls worker installs a persistent `/dev/input` watch before one
   bounded name scan, validates the exact H700 contract, and thereafter inspects
   only created nodes; reconnect or overflow permits one recovery scan. Its
   250 ms discovery timer exists only when inotify is unavailable. These
   responsibilities are not linked into the launcher. Before systemd starts,
   root preparation canonicalizes `system.suspendmode=off`, installs generated
   no-real-suspend and no-logind-input policy, and removes every competing
   `*.conf` drop-in before PID 1 starts. It also seeds either missing RetroArch
   configuration prerequisite individually, preventing retained
   `chksysconfig` recovery from restoring the complete stock configuration over
   Bird-owned policy. The generic H700 writers remain disabled; a fixed
   common/009 verifier runs after retained common/001 recovery and repairs mode
   or sleep-policy drift without writing on an accepted ordinary boot. This
   prevents split ownership with the H700 real-suspend
   path that the retained provider explicitly does not support. The persistent
   controls process continues to own the retained ROCKNIX resume transaction
   from the first accepted wake request until the wrapper explicitly reports
   core restoration, provider cleanup and Bird brightness restoration. During
   that interval it preserves at most one cancellable power or lid-close intent
   and never starts an overlapping helper.
   Optional networking is released only for direct PortMaster.
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

The two returned cold boots for the current framebuffer candidate recorded
launcher-start/input-ready/usable-frame values of 1221/1221/1224 ms and
1222/1223/1227 ms. The preceding release's three usable-frame observations
were 1226, 1229 and 1227 ms. The functional screen passed and no framebuffer
error appeared, but the late-registration inotify branch was not explicitly
instrumented on those boots. These values establish behavioral
non-regression, not a measured boot improvement. One lid-suspend attempt ended
in a reboot with an incomplete retained suspend trace; its cause is unproven
and remains deferred.

## Deployed Stage 3A and Stage 4 media candidate

The retained Stage 3A change subtracts only normal-success work from
`bird-early.sh`: a shell builtin `read` replaces the
pre-launch BusyBox `cat` of fixed maximum brightness; two brightness diagnostic
writes, three concurrent/later uptime `cut` children and four normal
root-ready/handoff LED `cat` children are removed; LED inspection remains
failure-only. Exact
brightness writes and strike timing, endpoint setup, module loading,
launcher/PID publication, storage acknowledgement, ownership checks, timeout
retirement and failure evidence remain unchanged. The target is one fewer
pre-launch process and two fewer pre-launch writes plus seven fewer
concurrent/later transient children. Its returned timings established
functional non-regression but did not establish a boot, interaction, energy or
memory improvement.

The returned Stage 3A boots recorded launcher/input/usable milestones of
1217/1218/1229 ms and 1211/1212/1225 ms, with storage anchored at 3685 and
3739 ms. The user verified the rest of the functional gate. The release and
its previous selector contain byte-identical MPV input policies, so the newly
observed pause-plus-audio-track action was not introduced by the shell
subtraction. Two attempted SDL-policy corrections then proved that changing
`GAMEPAD_ACTION_*` aliases cannot make the path deterministic: physical west
and east presses each retained one intended action while also changing audio
tracks.

Inspection found two simultaneous owners in the retained provider. ROCKNIX's
`start_mplayer.sh` starts `mpv.service`/`mpv_sense`, which reads raw evdev and
spawns `socat` commands, while the same wrapper starts MPV with
`--input-gamepad=yes`. The deployed Stage 4 candidate replaces both media-only
translation paths with one 6,424-byte freestanding `bird-mpv-controls` process.
It validates the complete H700 contract, uses watch-before-scan discovery,
discards overflowed evdev records through `SYN_REPORT`, resynchronizes held
keys, reconnects IPC without replaying stale commands, blocks in `ppoll`, and
sends direct JSON commands without per-press processes. The wrapper disables
MPV default/SDL gamepad bindings and never starts `mpv_sense`, while retaining
the provider's `mpv` freeze publication for fake suspend. The documented
regular and one-handed controls, chapter, playlist, subtitle and
shoulder+Select audio-track actions are preserved; Menu+D-pad adds isolated
contrast and saturation steps of exactly one point per press. This candidate is
loaded only after media selection and adds no initramfs, launcher, boot-time
process, timer, framebuffer traffic or ordinary menu-idle work.

The exact deployed tuple is clean source
`f866fe7dbeaec3e3ee0d3937296968c804b77665`, immutable release
`v6.23-mpv-single-input-f866fe7` and manifest
`475e786077d54d7247dbd11d463fcb8b8bd1377c7315e5913644f58bdb9fe017`.
The final-root helper is 6,424 bytes with 5,320 bytes of text, 32 bytes of data
and 2,936 bytes of BSS. The launcher is byte-identical to the previous release,
and the compressed early overlay is two bytes smaller; neither host fact is a
device boot-time claim. Physical command mapping, suspend integration, launch
and return behavior remain the promotion gate.

The returned gate rejects this exact tuple as the accepted media-control
candidate. Contrast and saturation passed, but bumper taps lost the preceding
player-relative volume contract, audio-language cycling was no longer directly
reachable, and chapter actions gave no feedback on the tested files. Physical
B was correctly reaching MPV's `frame-step` command: when invoked during
playback, that command pauses and advances one frame, which can look like a
rapid play/pause rather than a distinct control.

Host `ffprobe` inspection found zero chapter records in the two tested files,
`12 Angry Men.mp4` and `Akira (1988).mp4`. The retained trigger mapping must be
verified with chaptered content: the card's `Angel's Egg.mkv` has seven chapter
records and `The Godfather.mp4` has 23. Silence on a zero-chapter file is not
evidence that the raw L2/R2 codes were missed.

The bounded successor retains the single raw-evdev owner. Physical X cycles
audio instead of mute; L1/R1 taps restore MPV-local volume while a bumper used
with another control remains the one-handed modifier; Menu+L1/R1 changes
MPV-local picture brightness; and L2/R2 remain chapter navigation with OSD
feedback where chapter metadata exists. Dedicated volume and Menu+volume stay
system-volume and panel-backlight controls. No SDL, `mpv_sense`, per-press
process, boot-time executable, or menu-idle wakeup returns.

That successor is deployed as clean source
`813226d4c1b0fe9715bdae3f37d44485e4ad815f`, immutable release
`v6.23-mpv-complete-controls-813226d` and canonical manifest
`05f20822324d62be334a290f9567d341efc6f08243c14ab88adda43073d975a6`.
All 56 manifest-owned files verified and
`v6.23-mpv-single-input-f866fe7` is the previous selector. Focused tests prove
that one physical B press queues one `frame-step` and no pause command, both
Select+Start orders suppress media actions, and modifier/reconnect paths cannot
leak a bumper-volume action. The helper is 6,704 bytes, 280 bytes larger than
the rejected helper; its loadable section total excluding `.comment` is 8,294
bytes, six bytes larger. The launcher is byte-identical to the rejected
release. These are host binary facts, not RG34XX-SP timing claims.

The returned physical gate confirmed the complete control map, including
one-frame B behavior, direct audio cycling, player-local volume and brightness,
chapter navigation on chaptered content, subtitles, picture controls, exit and
menu return. The same boot's early log recorded launcher start at 1218 ms,
validated input at 1219 ms, honest usable frame at 1222 ms and storage at
3945 ms. Its SHA-256 is
`5ca5e2aaa8174ff7226271f1ae6416bc8870fc32363d1115f8b72beb574623a8`.
The preceding candidate's latest sample was 1223 ms input and 1232 ms usable;
the unpaired single samples establish functional non-regression only, not a
boot improvement.

This gate also establishes a content-interaction attribution baseline. The
launcher published the MPV request at 7.558 s; the content session began at
10.09 s, application contract became ready at 12.21 s, Sway became ready at
14.04 s and provider dispatch began at 14.29 s. After provider return at
73.98 s, the replacement launcher started at 74.324 s and published a matched
retained-frame usable menu at 74.377 s. These kernel-relative stages do not
substitute for button-to-photon or first-content-photon measurement.

### Direct-flash replacement-launcher candidate

The next bounded Stage 4 candidate changes only the final-root replacement
path. The original initramfs launcher remains `/opt/bird/bird-launcher` and
retains framebuffer, input and storage ownership through `switch_root` exactly
as before. If adoption or content return needs another launcher, the supervisor
now executes `/flash/bird/bird-launcher` from the selected immutable release.
`mount-storage.sh` no longer copies, chmods or verifies a second writable
launcher under `/storage/.config/bird`. An old writable copy may remain as
inert data; ordinary boot neither executes nor deletes it.

Against the accepted MPV checkpoint, the per-boot writable copy set falls from
19 regular-file copy operations and 817,170 source bytes to 18 operations and
219,817 bytes. That is one fewer external `cp`, one fewer `chmod` operand, one
fewer destination capability check and 597,353 fewer aggregate source bytes
(73.1 percent); 597,336 bytes are the launcher itself and 17 bytes come from
the shorter supervisor path. The final-root launcher remains exactly 597,336
bytes with SHA-256
`df44db7997c88cc1ee3d9cbcbf33bb56ca8b45712009299b8199d33b51725a18`.
The early launcher remains exactly 600,600 bytes with SHA-256
`2d82606ad6b4cc28ceebcdd5005bef54d13c3ad846ed7f7da945d9e2e91b1821`;
both binaries are byte-identical to the accepted checkpoint. Profile-mode
final-root and early variants also compile at 658,408 and 669,992 bytes.

This is a storage/root-preparation and content-return candidate, not a launcher
rendering change. Host launcher syscalls, dynamic instructions, framebuffer
bytes, ELF sections and resident memory are unchanged by construction. It
removes no resident task or idle timer. Device boot, UI/content interaction,
transient memory and energy remain unmeasured; in particular, no boot or
battery improvement is claimed until the RG34XX-SP gate passes.

The RG34XX-SP functional gate passed direct `/flash` replacement launch and
return. Boot ID `a4886df4` recorded launcher start/input/usable-frame at
1220/1221/1224 ms, versus 1218/1219/1222 ms for the preceding MPV checkpoint.
The unpaired +2 ms observations are boot non-regression evidence only, not a
latency claim. An early selection at 3606 ms was queued before storage at
3889 ms, published at 3956 ms and relinquished the launcher at 3996 ms. The
provider did not start until 14.50 s. The unchanged menu pixels were therefore
visible but noninteractive for about 10.5 seconds: a real content-readiness UX
gap, not evidence that the kernel or launcher process was still hung.

### Logged emergency UI recovery candidate

Menu+Select+Start now invokes one operator-only recovery transaction. It first
writes a unique mode-0600 snapshot below
`/storage/bird-data/MUOS/Bird/log/emergency/`, including boot identity, unit and
process state, memory pressure, Bird state files, bounded journal/dmesg output
and the existing early/supervisor/content logs. It syncs that evidence before
using the existing foreground-exit helper, cancelling one pending request,
terminating only an exactly validated inherited launcher when necessary and
requesting a nonblocking `essway.service` restart. The chord is latched until
Select or Start is released, and a late Menu edge upgrades an already-issued
Select+Start exit to logged recovery.

The helper is executed directly from immutable `/flash` and is never copied
per boot. It is 6,254 bytes. The fixed-controls binary grows from 10,352 to
10,608 bytes: `.text` +60 bytes, `.rodata` +192 bytes and `.bss` unchanged at
8 bytes. There is no new resident task, syscall, timer, framebuffer traffic or
ordinary idle wakeup; diagnostics and sync cost occur only when the emergency
chord is deliberately invoked. Host dynamic-instruction counts are unavailable
because Valgrind is not installed. Physical chord recovery, preserved logs and
ordinary Select+Start behavior remain the device gate.

Boot ID `bf45b45b` passes that recovery gate. The initial launcher started at
1217 ms, validated input at 1218 ms and published a usable frame at 1221 ms.
Menu+Select+Start at 75.887 s persisted a 178,213-byte snapshot, completed the
managed foreground-exit path, cancelled the pending action and successfully
requested the UI restart. A retained-frame menu was usable at 76.543 s without
a reset. The same game then launched through RetroArch and returned with result
0. Brightness, volume, media launch and shutdown also remained functional.

The snapshot identifies the first-game freeze precisely. At 5.268 s systemd
found an ordering cycle from the retained multi-user-enabled
`powerstate.service`, through its `After=essway.service` edge, graphical target,
seatd and back to multi-user/powerstate. It deleted `essway.service/start` to
break the cycle. The early launcher later published the Atari request and
exited normally at 27.157 s, but no supervisor existed to consume it. No game,
RetroArch, OOM, input or kernel fault occurred before the freeze.

The bounded correction removes only powerstate's invalid reverse ordering edge.
`powerstate.service` remains requested by both the retained multi-user enablement
and `rocknix.target`, while `essway` remains behind the stable graphical
boundary. The unit shrinks from 291 to 276 bytes. The 597,336-byte launcher and
5,528-byte power worker are byte-identical to the recovery checkpoint; there is
no new task, timer, framebuffer byte, syscall loop, binary memory or early-boot
work. This is final-root correctness after the already-usable menu, not a boot
latency claim. It prevents systemd from sacrificing either the supervisor or
power worker and therefore protects content interaction and power policy.

Clean source `895e6a7ae557df3b202e6ac7b78234441b705c0e` is deployed as
`v6.23-ui-order-895e6a7`, canonical manifest
`fdf3e466ef85682c4b6de977ff8484c5bb9b24eddf953f4f6981eb206aa6e149`.
All 57 manifest-owned files verified, with the accepted emergency checkpoint as
the previous selector. That RG34XX-SP gate passes. Six returned boots recorded
usable-frame times of 1229, 1225, 1222, 1222, 1224 and 1218 ms, a descriptive
median of 1223 ms; the latest sample was the fastest. Every captured final-root
snapshot had both `essway.service` and `powerstate.service` active, and no
ordering-cycle/job-deletion event remained. Repeated cold first-game launch,
content return, media controls, suspend, shutdown and a second logged emergency
restart also passed. These observations establish functional and boot
non-regression, not a new latency distribution claim.

### Immutable content-dispatcher candidate

The next bounded Stage 4 candidate moves only the final-root content dispatcher
to the selected immutable release. The supervisor now executes
`/flash/bird/run-content.sh`; `mount-storage.sh` no longer copies, chmods or
verifies a writable duplicate under `/storage/.config/bird`. An old writable
copy may remain as inert data, but ordinary boot neither executes nor deletes
it. Provider selection, storage handoff, one-pending-intent behavior and the
dispatcher itself are unchanged. The deployed dispatcher remains exactly
65,346 bytes with SHA-256
`9a471700d333f1d22f5c55066c1ce1683b560ea42081c1b97b3534106432e6d9`,
byte-identical to the accepted ordering checkpoint.

Against that checkpoint, the writable preparation set falls from 18 files and
220,067 source bytes to 17 files and 154,715 bytes. This removes one external
`cp` child, one `chmod` operand, one destination capability check and 65,352
source bytes plus 65,352 destination bytes per boot, a 29.7 percent reduction
of that remaining payload and an 81.1 percent cumulative reduction from the
original 817,170-byte set. The final and early launchers, fixed controls and
power worker are byte-identical. The release initramfs differs by one compressed
byte solely because of release metadata. There is no launcher syscall,
framebuffer, input, resident-task, idle-timer or memory change.

Clean source `0b438f52b767e3c8ec008c1a5e7c342c0d503643` is deployed as
`v6.23-flash-runner-0b438f5`, canonical manifest
`2ca0ba49a33e0a62f9abbe73419696a32943af70fbc266659ad59bd08cf75ec6`.
All 57 manifest-owned files verified, with the accepted ordering checkpoint as
the previous selector. That RG34XX-SP gate passes: first content launch,
provider return, media controls, emergency recovery and shutdown remained
functional. Three surviving boot records reported usable-frame times of 1224,
1232 and 1239 ms, a descriptive median of 1232 ms. This is 9 ms above the
preceding six-boot median, but the early executable is byte-identical and the
external stopwatch remained about 2.7 seconds. The small unpaired set supports
non-regression only, not either a speedup or regression claim.

Suspend stress produced one non-blocking abrupt reboot after several successful
cycles. Its O_DSYNC trace completed four cycles, then ended with power dispatches
at 29.623 and 30.566 seconds without the normal resume-complete record before
the sequence reset on the next boot. No ordered shutdown, panic, Oops, OOM,
pstore record or reset reason survived, and the following boot completed repeated
suspend cycles normally. The evidence locates interruption inside an in-flight
resume but cannot attribute the provider, kernel or power hardware. No cooldown
or behavior change is justified; the quirk remains deferred for finer provider-
phase and reset-cause instrumentation.

### Immutable final-root supervisor candidate

The next bounded Stage 4 candidate changes only the final-root UI service exec
path. `essway.service` now starts `/flash/bird/supervisor.sh`, and
`mount-storage.sh` no longer copies, chmods or verifies a writable supervisor
duplicate. The same generated Bash supervisor, launcher adoption, content
dispatch, boot-attempt, recovery and shutdown behavior remain in place. The
manifest-verified `/flash/bird` mount is established before this service starts
and remains stable until the service is stopped for shutdown.

Against the accepted dispatcher checkpoint, writable preparation falls from 17
files/154,715 bytes to 16 files/136,973 bytes. This removes one `cp` child, one
mode operand, one destination capability check and 17,742 source plus 17,742
destination bytes, 11.47 percent of the remaining payload and 83.24 percent
cumulatively from the original 817,170-byte set. `essway.service` shrinks ten
bytes. The generated supervisor grows four immutable bytes only because the new
release ID is longer. Final and early launchers are byte-identical at 597,336
and 600,600 bytes; profile variants remain 658,408 and 669,992 bytes. The
615,251-byte early overlay differs from the accepted overlay by one compressed
metadata byte. There is no launcher, framebuffer, input, provider, suspend,
audio, task, timer, wakeup or resident-memory change.

Clean source `f06686ab0cf80676733de800809c39765aadfc6e` is deployed as
`v6.23-flash-supervisor-f06686a`, canonical manifest
`e69a5c90fae8479161819b5797984d03e9d8a15e0c96f23a75c4647c6582bb37`.
All 57 manifest-owned files verified, with the accepted immutable-dispatcher
checkpoint as previous. The RG34XX-SP gate passes the direct supervisor path,
both retained service states, game and media launch/return, retained-frame
emergency restart and orderly shutdown. The two valid per-boot records report
usable readiness at 1232 and 1221 ms after kernel start; the external stopwatch
remained near 2.7 seconds. The missing per-boot log from the abruptly reset run
is not reconstructed from `early-initramfs-latest.log`. These sparse records
establish boot non-regression only; no latency or energy improvement is claimed.

Audio-only MPV playback also exposed a retained fake-suspend discontinuity on
this otherwise accepted checkpoint. Boot `8e3ced38` dispatched power suspend and
resume at 38.956 and 40.910 seconds but left no resume-complete marker before an
abrupt reboot. No orderly shutdown, panic, Oops, OOM, pstore or reset cause
survived. On boot `aa4a04bf`, the same song completed suspend/resume at
22.122/24.647/25.697 seconds but replayed about one second before recovering;
a movie later completed lid suspend/resume at 52.314/53.600/54.639 seconds and
continued normally. The active and previous releases have byte-identical MPV,
suspend, controls and content-runner artifacts, so the immutable-supervisor
subtraction did not introduce this behavior.

The retained provider mutes PipeWire, stops matching MPV processes with
`SIGSTOP`, leaves PipeWire and WirePlumber running, then sends `SIGCONT` before
unmuting. That is not an acknowledged MPV pause transaction and can leave an
audio-only stream with stale buffered output; the exact buffer-level cause is
not logged. No behavior change is promoted: a blind pause toggle is
non-idempotent, pausing every media provider would regress the working movie
path, and letting MPV advance while muted conflicts with the current policy. A
future bounded audio-suspend candidate must distinguish audio-only from video,
preserve prior pause state through acknowledged IPC, align with background-music
policy and follow finer provider-phase/reset-cause instrumentation.

### Immutable first-frame preparation candidate

The next bounded Stage 4 candidate changes only `essway.service`'s pre-start
path from the writable duplicate to
`/flash/bird/first-frame-prep.sh`. The selected release is already required by
the accepted immutable supervisor, and this 811-byte script uses absolute
kernel/storage paths and writes only its diagnostic log. Root preparation no
longer copies, chmods or verifies the writable duplicate.

Against the accepted supervisor checkpoint, writable preparation falls from 16
files/136,973 bytes to 15 files/136,162 bytes. This removes one `cp` child, one
mode operand, one destination capability check and 811 source plus 811
destination bytes. The script still executes once later, so its execution read
is not counted as removed. There is no launcher, framebuffer, input, provider,
suspend, audio, task, timer, wakeup or resident-memory change. Boot timing, the
read-only brightness log, quick launch/return, repeated emergency restart and
shutdown remain the RG34XX-SP gate.

Clean source `094be8be0555c4ab51f2968b21f13993b63de96f` is deployed as
`v6.23-flash-firstframe-094be8b`, canonical manifest
`c90a4b6b5b21fd5cedabdb58f0756ec8ceb810adf18c39efae017becde8dff20`.
All 57 manifest-owned files and the `.complete` digest verified, with the
accepted immutable-supervisor checkpoint as the previous selector. The final
and early release launchers are byte-identical to that checkpoint at 597,336
and 600,600 bytes; `.text`, `.rodata`, `.data.rel.ro`, `.data` and `.bss` are
unchanged. Profile variants remain 658,408 and 669,992 bytes. The early overlay
is 615,256 bytes, five compressed bytes larger than the accepted overlay even
though its early launcher is byte-identical. The inactive immutable-dispatcher
release was archived and independently verified in the private GitHub release
archive before its card copy was reclaimed.

The physical gate passes. Five valid kernel-to-usable records were 1229, 1221,
1221, 1229 and 1226 ms, a descriptive median of 1226 ms and no regression from
the accepted supervisor checkpoint. The external stopwatch remained near 2.7
seconds. The immutable pre-start completed in about 10 ms without a brightness
write. Game, music, reader, movie, retained-frame returns, an emergency UI
restart and durable shutdown completed with no failed unit or ownership loss.
One shutdown requested before storage readiness exercised the existing bounded
final-root wait and still completed; that path was unchanged by this candidate.

### Immutable boot-snapshot candidate

The next bounded Stage 4 candidate changes only
`rocknix-report-stats.service` from the writable diagnostic duplicate to
`/flash/bird/capture-boot-state.sh`. The 4,831-byte script has one post-autostart
consumer, uses absolute paths and writes only its snapshot below writable
storage. The accepted immutable `/flash/bird` lifetime already covers the
launcher, dispatcher, supervisor and first-frame preparation.

Writable preparation falls from 15 files/136,162 bytes to 14 files/131,331
bytes. This removes one `cp` invocation, one mode operand, one destination
capability check and 4,831 source-read plus 4,831 destination-write bytes. The
diagnostic still runs once after autostart, so its execution read is not counted
as removed. Launcher, framebuffer, input, content, controls, suspend, audio,
timers, tasks and resident memory are unchanged. This is post-usable storage
work reduction; it cannot claim a first-frame improvement. Its physical gate is
boot non-inferiority, a fresh complete snapshot after 25 seconds, normal content
return and shutdown.

Clean source `9c4250ee50afd37c720a25b7cf109a64bd1a1303` is deployed as
`v6.23-flash-snapshot-9c4250e`, canonical manifest
`4d854a95edbea36e0e23e26ce7fa76c6a559b790ffcf30e0a852c98d0f877b93`.
All 57 manifest-owned files and the `.complete` digest verified, with the
accepted first-frame-preparation checkpoint as the previous selector. The final
and early release launchers and their ELF sections remain byte-identical at
597,336 and 600,600 bytes. Profile variants remain 658,408 and 669,992 bytes.
The early overlay remains 615,256 compressed bytes but has a new digest because
the initramfs copy list changed. The inactive immutable-supervisor release was
archived, published and independently verified in the private GitHub release
archive before its card copy was reclaimed.

The physical gate passes on boot `02d6aba1`. Input opened at 1222 ms, the usable
frame committed at 1229 ms and storage became ready at 3713 ms. The usable
sample is inside the accepted 1221--1229 ms range, so this is non-regression
rather than a speed claim. The 47,325-byte/786-line snapshot ran as
`/flash/bird/capture-boot-state.sh` through its final section, with zero failed
units and no pending jobs. Game, music, movie, PortMaster networking and cleanup,
suspend/resume, exact menu return and the durable shutdown checkpoint passed.

### Complete immutable final-root toolset candidate

The original stock-root bridge published Bird programs and fixed provider data
under `/storage/.config/bird` because that was the established writable runtime
namespace, FAT modes were not authoritative and destination checks had to fail
closed on partial installation. The selected release is now manifest-verified
before its session-long `/flash/bird` bind, and direct execution is physically
proven across the launcher, supervisor, dispatcher, recovery, preparation and
diagnostic paths.

The next aggressive Stage 4 batch converts every remaining immutable consumer
to `/flash/bird`: PID waiting, global controls, power policy, foreground exit,
shutdown save, PortMaster preparation/verifier/manifest, fixed storage,
networking, suspend, volume and OSD. Only the mutable 260-byte ROCKNIX memory
policy remains copied to `/storage/.config/swap.conf`. Preparation falls from 14
files/131,331 bytes to 1 file/260 bytes, removing 13 `cp` invocations, 131,071
source-read plus destination-write bytes, the complete executable chmod
transaction and 13 destination checks. Inert old writable copies are not
deleted; the fallback overwrites its own versions before use.

This batch changes no launcher, framebuffer, catalog, render traffic, retained
task or timer. It removes post-usable storage/application preparation work and
therefore cannot claim a first-usable-frame improvement. The physical gate must
cover boot timing, storage/application readiness, all global controls, normal
and forced content exit, game/media/reader/PortMaster launch and return, Wi-Fi
cleanup, repeated suspend/resume, input reconnect, changed and quick shutdown,
and rollback availability.

Clean source `61c51dd798af47330af604e2884553f2e0275e68` is deployed as
`v6.23-flash-toolset-61c51dd`, canonical manifest
`d806243beeb5edbffadc36ac1f83fb9306407935d1084e24d23aa11a2881a8a9`.
All 57 manifest-owned files and the `.complete` digest verified, with the
accepted boot-snapshot checkpoint as the previous selector. Release launchers
and their ELF sections remain byte-identical at 597,336/600,600 bytes; profile
launchers remain 658,408/669,992 bytes. Fixed controls shrink from 10,608 to
10,568 bytes entirely in `.rodata`; `.text`, data and BSS are unchanged. The
manifest-owned release shrinks 1,869 bytes, including a 1,692-byte smaller
mount hook and a two-byte smaller 615,254-byte compressed overlay. The inactive
first-frame release was archived, published and independently verified in the
private GitHub release archive before its card copy was reclaimed.

The broad RG34XX-SP gate passes. Boot `b116d112` opened the direct launcher and
input at 1218 ms, committed the honest usable frame at 1226 ms and published
storage readiness at 3723 ms. A game selected at 2493 ms remained exactly one
pending intent and dispatched only after storage became ready. Two managed game
sessions returned status 0 with matched retained-frame restoration. The
operator reported the complete behavior matrix passing, including controls,
providers, PortMaster/network cleanup, suspend/resume and shutdown. Shutdown
was requested at 92.50 s, dispatched at 92.56 s and completed the durable save
at 92.74 s. The 1226 ms usable result remains inside the accepted 1221--1229 ms
range, so timing is unchanged/non-inferior rather than improved.

### Requested diagnostics and content-shell candidate

The ordinary post-autostart snapshot existed to expose retained ROCKNIX unit,
process, memory, journal, kernel, udev and audio state after the compatibility
graph settled. It was idle-I/O-priority work, but boot `b116d112` proves it
still overlapped priority-two content startup: its 46,984-byte/782-line capture
began at 12.17 s, while the first content contract was ready at 12.10 s and
content services began at 13.94 s. Conventional shell parsers also made the
early and content state contracts easy to inspect while those contracts were
still changing. Finally, `systemd-run` retained its default `$` expansion even
for the cleanup guard's embedded shell program.

This candidate makes the full snapshot explicitly requested by the persistent
marker `/storage/bird-data/MUOS/Bird/boot-diagnostics.request`. Ordinary boots retain
readiness, supervisor, content, emergency and shutdown logs without launching
the broad probe set. A requested capture atomically publishes
`stock-root-boot-state-<boot-id>.log`, then refreshes the latest copy; the
supervisor no longer attributes an older latest capture to a later boot. Both
content `systemd-run` boundaries use `--expand-environment=no`, preserving
literal provider arguments and guard parameter expansion. This fixes the
invalid-environment warnings found in the accepted checkpoint's emergency
records and protects paths containing `$`.

Built-in reads replace all 39 external `/proc/uptime` parser sites across the
runner and supervisor, two `cat` plus three `awk` process-stat sites, three
per-launch path-validation helpers, three `sed | head` metadata pipelines,
four PortMaster owner-token `cat` substitutions and seven tiny supervisor
state-read commands. Exact-line parsing still rejects missing terminators,
extra lines and malformed action/PID records. Provider returns now distinguish
success, ordinary exits, SIGKILL, SIGTERM and other Linux signal-derived
statuses after content has returned.

Clean source `e87e4910459b953b7a1f2ebd19a0efee35fe9e57` is deployed as
`v6.23-content-shell-e87e491`, canonical manifest
`28e2372b36cef01c5f49b584c8896b00ce6969299a30eebb1d40a367d960c70c`,
with all 57 files verified and the physically accepted toolset checkpoint as
previous. Release/profile launcher pairs and their ELF sections remain
unchanged at 597,336/600,600 and 658,408/669,992 bytes. The manifest-owned
release grows 2,703 bytes from explicit validation and diagnostics code while
the compressed overlay shrinks three bytes to 615,251. The retired snapshot
release was published and independently verified in the private GitHub archive
before its card copy was reclaimed.

Launcher, framebuffer traffic, input ownership, timers and resident tasks are
unchanged, so no first-frame improvement is claimed. The physical gate must
prove an ordinary boot creates no broad snapshot, a deliberately armed boot is
complete and correctly attributed, systemd expansion warnings are absent,
immediate/pre-storage and normal content launch/return work, deliberate force
quit is classified, and boot/UI timing, providers, controls, suspend and
shutdown remain non-inferior. HDMI and Bluetooth are not part of this change.

The returned content-shell gate passed the complete behavior matrix. Boots
`d86b5a36` and `ce9da31c` opened direct input at 1223/1219 ms and published
usable frames at 1229/1222 ms. The latter is a new best sample but remains a
non-regression, not a distribution-level speed claim. Ordinary boots produced
no broad snapshot, content exits were correctly classified as 0, 143 or the
deliberate 137, retained frames matched and shutdown checkpoints completed.

### Fixed post-frame coordinator and volatile-journal candidate

The generic coordinator existed to preserve the ROCKNIX product matrix while
fixed-device consumers were still being audited. It still scanned H700/common
directories, launched 26 release-provided no-op scripts, forked approximately
45 `date` helpers and required 31 per-script bind substitutions. The accepted
journal was already bounded under `/run`, but systemd still launched an empty
persistent flush and message-catalog update after the menu.

Clean source `133834108ee66a6ad965c44441b6e09690eb8369` replaces that scan with
one fixed coordinator. It calls the 14 proven responsibilities in their exact
pinned order, preserves tolerant failure semantics and optional custom hooks,
and lets `999-export` validate application readiness. Fixed Bird producers run
from `/flash/bird`; retained stock producers run from exact SYSTEM paths. The
no-op helper and all autostart bind substitutions are gone. Journald remains
available with an explicit volatile 2 MiB/128 KiB policy; only the empty flush
and catalog jobs are masked.

Release `v6.23-fixed-autostart-1338341`, manifest
`2c9553b94c7fffd25dff2f45b764c342c134ca6564ed3f9ae9a040ca0149d198`,
is deployed with the accepted content-shell release as previous. Launcher and
profile binaries/sections are unchanged. The mount hook shrinks 2,719 bytes,
the manifest-owned release shrinks 1,789 bytes, and the release overlay changes
from 615,251 to 615,258 bytes. This is post-usable work: no first-frame gain is
claimed. The physical target is earlier application/content readiness and less
late CPU/I/O with boot/UI non-inferior. HDMI, Bluetooth, udev, seatd, logind and
the warm audio policy are unchanged.

The returned fixed-autostart gate passed all functions. Six boot-scoped samples
published usable readiness at 1223, 1226, 1228, 1229, 1229 and 1235 ms, versus
the accepted 1222--1229 ms range. That supports non-regression, not a faster
first-menu claim. The initially suspicious 1567 ms record was a stale
catalog/runtime file outside this release's boot-scoped evidence. Final-root
supervisor entry moved from 9.65--9.69 s to 9.25--9.53 s, consistent with less
post-frame coordinator work.

### Fixed session manager and idle-wakeup candidate

Logind remained because ROCKNIX normally delegates lid, power and login-session
policy to it. Bird now owns lid/power through its fixed controls, the retained
fake-suspend provider has no login1 client, and Sway explicitly joins seatd.
The tmpfiles timer served general persistent roots, while this image recreates
its cleaned `/tmp` and `/var` roots as tmpfs. UTMP recorders likewise served
multi-user login accounting, but wrote only volatile `/var` here.

Clean source `46dd1704e3453dd3f3fcbb55ea96488716deb840` masks logind, its one
resident task, the 15-minute/daily tmpfiles-clean timer and the two boot/runlevel
UTMP one-shots. Seatd, udev, journald, audio, networking, HDMI and Bluetooth
remain unchanged. Release `v6.23-fixed-session-46dd170`, manifest
`00ba951842afc78f2f27a34f952f790e7cc32eab385db4f902cc0e9c0d7df7cd`,
is deployed with the accepted fixed-autostart release as previous. Launcher,
ELF sections and compressed overlay are unchanged; added explicit assertions
grow the manifest-owned release by 530 bytes. No first-frame gain is claimed.
The returned physical gate passed all tested functionality. Boot-scoped samples
`17553b07`, `9ff881cd` and `b7c3b076` published usable readiness at 1222, 1223
and 1222 ms respectively, with direct input at 1219, 1221 and 1219 ms. This
accepts the fixed-session tuple as the next candidate's rollback and supports
first-menu non-regression, not a distribution-level improvement claim. PSS and
wakeup savings remain unclaimed until device measurement.

### Fixed post-frame housekeeping candidate

The generic logging and Pico-8 hooks existed to support mutable configuration
and many ROCKNIX devices. On this fixed image they still removed and recreated
an already-correct RetroArch log symlink and touched an existing `Splore.png`
sentinel every boot. Logind policy publication likewise survived from when
logind still owned input policy, despite the physically accepted service mask.

Clean source `91b2f58ed696dfcd547b1ffd52fcb5ceb3ad3602` replaces those two generic
hooks with fixed idempotent scripts and removes comparison, mode inspection and
drop-in cleanup for inert logind configuration. Udev, seatd, journald, audio,
networking, HDMI and Bluetooth remain unchanged. Release
`v6.23-fixed-housekeeping-91b2f58`, manifest
`41edbb038356df9cbf1086d451a6731ba3b2bc3c7ad71c9d0754d6b76ee9100f`,
is deployed with physically accepted fixed-session as previous. All 58 files
verify; release/profile launchers are byte-identical to the checkpoint. The
steady state removes `rm`, `ln` and `touch` filesystem mutations plus one
logind `cmp`, one `stat` and its obsolete drop-in scan. Manifest-owned bytes
increase by 403 and the fixed Bird-file subset by 564 bytes. These operations
occur after usable readiness, so no first-frame timing change is expected or
claimed; the target is lower post-frame I/O and earlier application readiness.

The returned physical gate passed all tested functionality. The preserved
clean boot reached direct input at 1216 ms and usable readiness at 1220 ms,
inside the accepted range; this is non-regression and a best observation, not a
distribution-level improvement. One suspend stress sequence dispatched lid
close and lid open but never recorded the normal coordinator resume completion,
then a new boot sequence began. Later suspend cycles passed. No panic or
watchdog cause survived, and the housekeeping candidate changed no suspend
path, so no speculative fix is included.

### Fixed application profiles candidate

The generic controller and setup hooks existed to derive profiles for arbitrary
controllers and repair mutable multi-device installations. On the fixed H700
they still ran `control-gen`, XML selection, two UUID generators, 100 per-input
`awk` operations and rewrote `098-controller` every boot. Setup also re-sorted
and replaced valid persistent settings, deleted and re-added
`clouddrive.mounted=0`, and recreated an already-correct cache link. The fixed
UI and application publishers rewrote two valid profiles and one symlink, while
`start.games` served only the absent EmulationStation unit.

Clean source `b87dcc2a5c7f7ef0fc8c4737eebf51ac60b2dd87` publishes a build-verified
H700 controller profile, retains `chksysconfig` recovery, and makes every other
accepted-state publication comparison-only. Application readiness now validates
the fixed controller bytes. Release `v6.23-fixed-profiles-b87dcc2`, manifest
`c9dbc12ff1ca1ef98d7436824321db922905dce45afcac50617db18e1ffe0564`,
is deployed with accepted fixed-housekeeping as previous. All 61 files and
`.complete` verify. Release/profile launchers are byte-identical; the release
overlay shrinks three bytes. Manifest-owned bytes grow 3,513 for explicit fixed
profiles and their repair code. This is post-usable work, so no first-frame
change is expected or claimed; application readiness and storage-write
reduction require device verification.

The returned RG34XX-SP gate accepted this exact fixed-profile release. All
menu, launch, return, media, storage, power and suspend checks passed. Two
preserved clean boots reached direct input at 1216/1218 ms and honest usable
readiness at 1222/1221 ms; their supervisors began at 9.28/9.26 s. These samples
establish non-regression inside the accepted first-menu range, not a faster
distribution. This release is the physical rollback for the next candidate.

The next retained-policy boundary replaces four generic post-frame wrappers:
multi-board CPU/GPU discovery, H700 GPU-overclock profile loading, recursive
platform rumble discovery and generic turbo settings loading. Fixed board paths
and limits retain adjustable core count, every captured CPU/GPU governor, the
600/648 MHz GPU maximum, turbo on/off and built-in PWM rumble on/off. HDMI,
Bluetooth and audio are unchanged. Each policy remains independently tested
and revertible even though the batch shares one hardware cycle.

Clean public source `01e8119ac9953f87442f1627bfd2032485cf9aa5` implements that
boundary. Release `v6.23-fixed-performance-01e8119`, canonical manifest
`70bfa8c408e1f939c3a678ba506ca65e3a5aebdbf33eaa2e5ca370ae2734cc6a`,
is selected with physically accepted fixed-profiles as its on-card rollback;
all 65 files and `.complete` verify. The fixed-housekeeping release was verified,
published to the private release archive and only then reclaimed. Release and
profile variants both compile; release launchers are byte-identical to the
rollback. `bird-autostart` shrinks 172 bytes, the four explicit policy scripts
total 4,544 bytes, manifest-owned bytes grow 5,239, and the compressed release
overlay shrinks four bytes. Production remains the no-serial entry; diagnostic
fallback retains `console=ttyS0,115200`. Because all policy execution remains
after usable readiness, no first-frame timing change is expected or claimed.

The returned hardware gate accepts the fixed-performance tuple. All tested
hardware and application behavior passed, including retained rumble and the
fixed performance closure. The preserved boot started the launcher at 1218 ms,
validated input at 1219 ms and published usable readiness at 1222 ms. This is
inside the accepted range and supports non-regression, not a faster
distribution.

One `12 Angry Men` observation reported imperfect lip sync. Its MP4 metadata
starts AAC audio at 0 while H.264 video starts 125.125 ms later; Bird has no
global or per-file `audio-delay`. MPV's cleaner observed run held its reported
A/V clock between -42 and +33 ms, but accumulated 155 dropped video frames
during a seek-heavy 1200x720/23.976 fps session. This evidence does not justify
a global offset that would desynchronize healthy media. The file-specific
observation remains open for comparison with other movies.

The next Stage 4 manager candidate independently makes seatd content-scoped and
quiesces udevd after successful coldplug. A fixed seatd unit requires an exact
`/run/bird/seat-request` lease; the content owner publishes it before Sway and
releases it only after Sway is proven stopped, including external-guard cleanup.
The udev step waits for settlement and stops only the resident manager while
retaining both activation sockets for later hardware events. Content timing is
a higher-priority gate: seatd-on-demand promotes only if Sway readiness remains
non-inferior. HDMI and Bluetooth capability are unchanged.

Clean public source `d2e064928727a0580f4c07085d2b8eb46be0a4ee` is deployed as
`v6.23-fixed-managers-d2e0649`, canonical manifest
`0c13e8d8a35042b3853b8debf1f1be05e78df4e7682e3a48cfeca53cf6a09463`,
with accepted fixed-performance as the on-card rollback. All 67 files and the
completion digest verify. Release/profile final-root and early-initramfs
variants compile; release launchers and the 615,254-byte compressed overlay are
byte-identical to rollback. The two policy files plus lease/cleanup logic add
2,316 manifest-owned bytes. A retained older manager snapshot observed 1,556
KiB RSS for seatd and 8,548 KiB for udevd before worker memory, but current PSS,
wakeups and energy remain unmeasured. Production remains no-serial; diagnostic
fallback retains serial.

The returned hardware gate found all tested behavior functional and preserved
the boot milestones at 1220 ms launcher/input and 1223 ms usable readiness,
effectively unchanged from fixed-performance's 1218/1219/1222 ms single-log
reference. The lower-priority seatd residency saving is nevertheless rejected:
stable content sessions reached Sway-ready in a 490 ms median versus 470 ms on
fixed-performance, a roughly 20 ms first-launch regression. Total
session-to-provider timing also moved from roughly 630 ms to 710 ms, but the
combined candidate cannot attribute the remainder between manager scheduling
and udev quiescence. The next isolated candidate therefore restores the warm
graphical-boot seatd policy and retains only post-coldplug udevd quiescence.
This intentionally retains seatd's observed 1,556 KiB RSS because content
interaction outranks memory. Udev reactivation, content timing, PSS, wakeups
and energy remain device gates. Production remains no-serial; diagnostic and
fallback entries retain serial.

Clean public source `7d74bf668e3a38a9ae1cd1ceb15d81babf191592` is deployed as
the isolated candidate `v6.23-udev-isolation-7d74bf6`, canonical manifest
`c5fbebc38faa9a469d5c6363dc47811ef0983e973e30908648c09872b8fdbe6f`.
All 66 manifest files verify. Fixed-managers is the on-card functional
rollback; fixed-performance was archived to the private GitHub release archive
before card-space reclamation. Release/profile final-root and early-initramfs
variants compile and the 600,600-byte release launcher is byte-identical to
fixed-managers. Removing the rejected seat unit and lease machinery reduces
manifest-owned bytes by 1,459; the compressed overlay changes by two bytes to
615,256. No boot-timing improvement is expected because warm seatd remains
post-usable graphical work and launcher bytes are unchanged.

The returned udev-isolation cycle resolves the combined timing attribution.
Its cold boot recorded launcher start at 1215 ms, validated input at 1216 ms
and usable readiness at 1219 ms; this is a fast non-regression sample, not a
distribution claim. With warm seatd restored, six stable content sessions
returned to a 470 ms median from session start through Sway readiness. The
later services-ready/provider boundary remained 690--730 ms from session start,
roughly 60--70 ms above the warm-manager reference. Sway and providers are
udev consumers, so stopping udevd after coldplug displaced daemon activation
into the A-button path rather than eliminating it. The udev-idle candidate is
rejected and the fixed coordinator returns to revision v2 with udevd warm.
The retained-userspace audit now intentionally keeps warm seatd and udevd for
priority-two interaction, keeps volatile journald for recovery, keeps audio
warm, removes logind, and gates networking to PortMaster. HDMI and Bluetooth
remain undecided and unchanged.

Clean public source `72d7fe6058dcd21d8c95545871c0acffc3d3dce6` is deployed as
`v6.23-warm-managers-72d7fe6`, canonical manifest
`8b81f34ab5f84e4c1faafee2ee13357de08a26af704f2a8a26e6ac8107f1b545`.
All 65 manifest files verify. Udev-isolation is the on-card rollback and the
older fixed-managers release is sealed in the private GitHub release archive.
Release/profile final-root and early-initramfs variants compile. The 597,336-
byte final-root and 600,600-byte early launchers are unchanged; removing the
udev-idle script reduces manifest-owned bytes by 875 while the compressed
overlay remains 615,256 bytes. Production remains no-serial; diagnostic and
fallback entries retain serial.

The warm-manager hardware return passes all tested behavior. Its cold boot
recorded launcher/input/usable milestones at 1217/1218/1221 ms, inside the
accepted range and consistent with the operator's unchanged stopwatch result.
Four stable content sessions reached Sway-ready in 460--490 ms and provider
dispatch in 700--720 ms. Because the complete runtime implementation is byte-
equivalent to the earlier fixed-performance checkpoint, the difference from
the older roughly 630 ms provider sample remains unclaimed run/environment
variation rather than an attributable regression or improvement.

Stage 5 begins with request-only measurement infrastructure. The existing
`boot-diagnostics.request` service calls a fixed versioned sampler after
autostart; ordinary boots do not execute it. The sampler records raw scheduler,
PSS/USS, wakeup-source, IRQ, CPU-idle and battery counters with an explicit
state label. These snapshots support paired attribution but are not calibrated
energy measurements and do not authorize a battery claim.

Clean public source `3ce316d17574e8487ab846975c404f82f3366e56` is deployed as
`v6.23-stage5-metrics-3ce316d`, canonical manifest
`aba835ad6dd467ff553df81ec64db6542ea4f13e87903fe3268e89bfe3083289`.
All 66 manifest files verify. Warm-managers is the on-card accepted rollback;
udev-isolation is sealed in the private GitHub release archive. Both launcher
modes compile and remain byte-identical. The request-only sampler adds one file
and 3,036 manifest-owned bytes; the compressed overlay changes by two bytes to
615,258. Its persistent request marker is not armed for the ordinary hardware
gate. Production remains no-serial; diagnostic and fallback entries retain
serial.

The returned measurement-infrastructure release passed the broad hardware
gate. Its cold boot recorded 1218 ms launcher, 1219 ms input and 1223 ms usable
readiness. Stable post-first-launch sessions reached Sway-ready in 460--470 ms
and provider dispatch in about 680--690 ms; launch return, PortMaster cleanup
and shutdown completed normally. This accepts the unarmed sampler without a
boot, interaction or battery improvement claim.

Clean public source `2ca82cdf5fd3d173644b756797ae8f0421f4a87d` is deployed as
`v6.23-stage5-idle-2ca82cd`, canonical manifest
`c44f2639aaa714d46ef264d26f3627ed7598699d85c4aaadb7e7abfe88af09c1`.
All 66 manifest files verify. Stage5-metrics is the on-card accepted rollback;
warm-managers is sealed in the private GitHub release archive. Both launcher
modes remain byte-identical. The one-shot control adds 566 manifest-owned bytes
while the compressed overlay changes to 615,255 bytes. When explicitly armed,
the diagnostic settles for five seconds, samples, records a fifteen-second
untouched interval, samples again and disarms the idle-window request after
atomic publication. Ordinary boots still execute no sampler. Production
remains no-serial; diagnostic and fallback entries retain serial.

The one-shot idle-window release passed the broad hardware gate with unchanged
boot behavior. Its first requested measurement did not execute: the documented
`/storage/.config` marker belongs to the internal ROCKNIX storage image, while
the macOS writer had placed the same relative path on BIRD-DATA, which the
device exposes at `/storage/bird-data`. No false sample is recorded. The fixed
request authority is now the existing host-visible Bird directory
`/storage/bird-data/MUOS/Bird`; both the systemd condition and one-shot disarm
path use that exact mount. The two ineffective BIRD-DATA `.config` markers were
removed. This changes measurement triggering only and adds no ordinary process,
timer or content-path work.

Clean public source `97dd6ffc55b2c1f86650bf1a7bb95cd10d1ff9e0` is deployed as
`v6.23-stage5-trigger-97dd6ff`, canonical manifest
`505ac5d6674d81f18aff22723117dd2d48fafdffb443d3d961de6229bf2a6af5`.
All 66 manifest files verify. Stage5-idle is the on-card accepted rollback;
stage5-metrics is sealed in the private GitHub release archive. Both launcher
modes remain byte-identical. The corrected absolute strings add 31 manifest-
owned bytes and the compressed overlay is 615,257 bytes. Production remains
no-serial; diagnostic and fallback entries retain serial.

The corrected trigger passed its broad hardware gate and produced boot-scoped
sample `62fc769f`; the one-shot marker disappeared only after both labels and
the atomic latest copy existed. Across 15.04 seconds, raw `/proc/stat` deltas
show 26 busy and 5,958 idle aggregate jiffies (0.43 percent busy), 22,087
context switches (about 1,469/s) and 15,498 hardware interrupts (about
1,030/s). The largest named IRQ deltas are `arch_timer` 7,317 (486.5/s) and
`5070000.adc` 4,512 (exactly 300/s), followed by I2C 113 and thermal 61. This is
screening evidence, not calibrated energy. The start sampler performed
structural reads after its scheduler timestamp, and one `/proc/PID` exit caused
the combined PSS awk to abort, so process memory and the exact global idle rate
from this run are invalid.

The next measurement-only correction uses a race-tolerant shell read for each
`smaps_rollup` and a minimal paired counter endpoint. Start enumerates structural
and per-process scheduler state before writing the final global scheduler
timestamp; end writes the global timestamp first. The timed global delta thus
excludes start-side enumeration. Per-process `schedstat` plus voluntary and
nonvoluntary context-switch counters identify actual runtime without inferring
cost from residency alone. The ADC and timer rates remain hypotheses until the
corrected sample repeats them.

Clean public source `9945f9d4f43013a0f09df7ea51a7a23dc1812b04` is deployed as
`v6.23-stage5-counters-9945f9d`, canonical manifest
`f65def91471288ea1aa7fb310ccfbb07fdc18414bf8d85d692d39fbe2814b704`.
All 67 manifest files verify. Stage5-trigger is the on-card rollback and
stage5-idle is sealed in the private GitHub release archive. The release
launcher remains 597,336 bytes and the early launcher 600,600 bytes; the new
counter endpoint adds one file and the release inventory grows by 3,371 bytes.
The compressed overlay changes by one byte to 615,258. Both profile variants
also compile; the profile early launcher is 669,992 bytes and its overlay is
630,752 bytes. Ordinary boots still execute no sampler. Production remains
no-serial; diagnostic and fallback entries retain serial.

The next armed boot must remain untouched for about 50 seconds. Acceptance
requires both versioned `start` and `end` counter blocks, race-tolerant PSS/USS
records, atomic publication and removal of the one-shot marker. Until that
physical return, this release is neutral measurement infrastructure and no
boot, interaction, battery or memory improvement is claimed.

The returned corrected 15-second window completed and the broad hardware gate
passed. Aggregate CPU was 0.45 percent busy with about 1,484 context switches/s.
The launcher used 0.423 ms and five scheduling slices; powerstate used 0.380 ms
and five slices. Warm PipeWire, PulseAudio, WirePlumber and seatd recorded zero
runtime during the window. Udevd used 53.3 ms and 24 slices, but the prior
isolated udev experiment measurably delayed content launch and remains rejected.
The dominant activity was kernel work and the fixed ADC/timer interrupt stream.
This is structural evidence, not calibrated energy.

Clean source `56d58d404817f90588e61e0faa58beb0e7547f66` is deployed as
`v6.23-stage5-settled-56d58d4`, manifest
`8e0988258c445c4c743f9afe8ae042a86d3bf144aa8a6c78456070641c343ebc`.
All 69 files verify; stage5-counters is the on-card rollback and stage5-trigger
is sealed in the private GitHub archive. A standalone request-only service now
settles for 30 seconds and measures for 60 seconds without running the broad
boot diagnostic. Global CPU, IRQ and softirq boundaries exclude process/sysfs
enumeration. The inventory adds two files and 1,745 bytes; release launchers
remain 597,336/600,600 bytes and the overlay shrinks five bytes to 615,253.
Ordinary boots add no process or timer. Production remains no-serial;
diagnostic/fallback entries retain serial.

The settled candidate failed its hardware gate before final-root handoff. Its
new `bird-stage5-window.service` bind target did not exist in the immutable
stock root, so root preparation stopped. The early launcher could navigate,
but content, controls, suspend and emergency recovery were unavailable because
their final-root owners never started. No new logs survived because storage
handoff never completed.

Clean source `d0c6e4edb02753f3f006ad2513976ce25b87cbfa` repairs this as
`v6.23-stage5-slot-d0c6e4e`, manifest
`bcf8e4575878ba81f8ffd854037436e2876a859148f959d167fe1c1981c8df95`.
The existing stock report-statistics service slot now dispatches either
explicit diagnostic request through two systemd OR conditions; no new bind
target is introduced. A host test rejects every systemd bind destination absent
from the pinned stock root. All 69 files verify. Stage5-counters remains the
known-good rollback; the failed release is archived privately and removed from
the card. Measurement is unarmed for the recovery gate. Launchers are unchanged
and the overlay is 615,252 bytes. Production remains no-serial.

The repaired slot passed the complete RG34XX-SP recovery gate. Launcher, input
and usable readiness were 1223/1224/1226 ms. Early pending launch dispatched
once at storage readiness; games, music, reader, movie, PortMaster, brightness,
volume, suspend, emergency recovery and shutdown all returned to their normal
owners. The clean Stage 5 window may now be armed on this same release.

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

The content boundary reconciles audio state without blocking provider launch:
it reads the exact H616 CARD headphone jack and changes the independent MIXER
speaker switch only when the live route disagrees. The RG34XX-SP physical gate
accepts headphone-only output from that correction. Crack/pop transients at
codec activation remain deferred Stage 4 work. An explicit muted PipeWire
prewake was tested, reported success, produced no audible improvement and is
not part of the active path.

Kernel trimming, U-Boot timing, earlier LED/display assertion, emulator and
PortMaster performance, remaining provider cold-load work, final boot effects
and complete shim removal remain roadmap work. Their absence is not evidence
that the active stock-root path is incomplete.

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
