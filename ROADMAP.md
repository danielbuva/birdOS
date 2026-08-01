# birdOS RG34XX-SP optimization roadmap

This is the governing constitution for the active stock-root implementation.
Commit `79b6e3e03771f2787622a3e4f6f9d8f129b7281f` is the operator-accepted source
and behavior baseline. Immutable release `v6.23-20260731-054816` remains the
accepted binary fallback and performance reference. Its canonical manifest
digest is
`5f95153bf46239a5e178fde28924f01c7fe586be182562f9bd9f33cf13da02ba`.
That manifest retains its actual older dirty source identity; it is not
represented as a clean build of `79b6e3e...`.

The historical version narrative remains in
[`docs/history/LEGACY_ROADMAP.md`](docs/history/LEGACY_ROADMAP.md). It explains
how birdOS arrived here but does not define current work.

## Immutable priority and promotion policy

Optimize in this lexicographic order:

1. Power-to-visible, genuinely usable menu.
2. UI interaction latency, then content launch and return latency.
3. Calibrated battery energy and unnecessary wakeups.
4. Memory and storage efficiency.
5. Fixed-device kernel work after userspace promotion.
6. U-Boot performance and frame production last.

Each candidate names one target and changes one attributable boundary. It may
promote only when its target improves beyond a margin frozen from A/A variation
and instrument resolution, every higher-priority metric is non-inferior, and
accepted behavior remains intact. Cosmetic continuity may not delay honest
usability at all. Neutral correctness, measurement, rollback and readiness
infrastructure may promote with no measurable regression.

Use randomized or ABBA paired acquisition in controlled charge, temperature,
brightness, card and content-state blocks. Use 20 boots for screening, at least
60 for promotion, at least 100 events per UI scenario and repeated cold/warm
provider runs. Treat p95 and maxima as descriptive unless the sample supports a
tail claim. Ordinary promotion runs permit no missed milestone, duplicate
launch, ownership loss or unexpected timeout/recovery activation. New recovery
mechanisms require separate fault injection.

Host dynamic instructions, syscalls and synthetic framebuffer bytes are host
metrics, not RG34XX-SP latency claims. Hardware timing uses both external power
origin and kernel-relative `CLOCK_BOOTTIME`. Input acquisition distinguishes
electrical-edge-to-photons, evdev-to-photons and launcher-read-to-framebuffer
barrier. Energy is measured at the battery path or a calibrated inline shunt.

## Readiness contract

Record separately:

1. External power origin.
2. Kernel start.
3. Framebuffer node available.
4. `first_pixel_commit`.
5. Panel ready.
6. Input registration.
7. Input node creation.
8. Validated input descriptor open: `input_ready`.
9. `usable_frame_ready`.
10. Storage ready.
11. Application contract ready.
12. Provider/content ready.

`usable_frame_ready` means a successful visible commit, panel readiness and a
validated open input descriptor. `/run/muos/bird-first-frame-ready` temporarily
retains that meaning for compatibility. Publishing readiness must not force a
second framebuffer write. Before input works, display only noninteractive
background/header pixels.

Until the kernel exposes truthful readiness, use the hardware-characterized
predicate: backlight interface ready, selected brightness sequence complete,
framebuffer commit complete, and observed vblank or the conservative proven
interval elapsed. Never publish readiness before visible photons.

## Stage 0 — Authority, provenance and successor gate

Authority is intentionally divided:

- `ACTIVE_PATH.md`: active implementation and deployment.
- `DEVICE_PROFILE.md`: human product and one-user policy.
- `bird-device-contract.tsv`: fixed hardware and one-user invariants.
- generated `bird-device-contract.h`: compiled subset.
- generated catalog sources: catalog revision, counts and data.
- `deploy-manifest.tsv`: release files, immutable inputs, modes, sizes and hashes.
- out-of-tree card-instance evidence: replaceable card/filesystem identity.
- promotion record: accepted source/release/digest binding.

The digest graph is one-way. The deploy manifest records the device-contract
file/digest and catalog digest. The device contract never contains the final
manifest digest. A promotion record binds clean source SHA, immutable release
ID, manifest digest, device-contract digest, catalog digest and sealed host and
hardware evidence.

Before every build or acquisition, freeze local/origin/public SHA, complete
tracked diff, untracked path inventory, submodules, pinned inputs, tool
versions/executable hashes, exact flags, mode, environment, commands and raw
samples. Acquire under an output-root `measurements-live` directory outside the
repository. Seal it with a canonical inventory only after acquisition ends.
Importing sealed evidence into `measurements/` establishes a new source identity
for all later work and never affects a runtime image.

For every successor to `79b6e3e...`:

1. Publish a clean commit and verify local, origin and public identity.
2. Build all pinned inputs under a fresh immutable release ID.
3. Build release/profile final-root and early-initramfs launchers.
4. Run the complete host suite and transactional fault-injection tests.
5. Deploy without replacing the accepted fallback.
6. Complete the RG34XX-SP behavior and measurement gate.
7. Seal the evidence and create the exact promotion record.
8. Only then update authority documents to name the successor as accepted.

If any physical gate fails, retain `79b6e3e...` as the accepted source/behavior
reference and `v6.23-20260731-054816` as the accepted binary fallback.

## Stage 1 — Low-risk release-path cleanup

Promote independently: zero pre-usable release logging; trace/recovery-only
diagnostics; deferred power netlink, battery reads and battery rendering;
removal of the valid-resume startup rewrite; removal of normal LED inspection
and `dmesg | tail`; bounded Favorites retries; no same-view A-button full
redraw; no redundant marquee clearing; production extlinux with no serial
console A/B against diagnostics; and identical-payload gzip `-9`, gzip `-1`
and LZ4 experiments. Report image size, card-read/decompression timing and
power-to-usable results. Do not replace the early shell in this stage.

### Stage 1 decision record — 2026-08-01

The gzip A/B was screened on the RG34XX-SP with the same normalized early
overlay payload. gzip `-9` produced a 613,865-byte initramfs; gzip `-1`
produced 681,658 bytes. Cold stopwatch samples for gzip `-1` were 2.7–2.9 s,
which was non-inferior to the preceding 2.7–2.8 s gzip `-9` samples but did
not exceed the frozen improvement margin. gzip `-1` is therefore not
promoted. The canonical build and the next candidate use gzip `-9` again;
the validated level switch remains available for later controlled tests.

The production no-serial-console candidate is `v6.23-no-serial-328db9e`.
It removes only `console=ttyS0,115200` from the active extlinux entry. The
previous selector and fixed fallback retain the serial console for diagnostics
and recovery. The RG34XX-SP behavior screen passed, and three consecutive cold
stopwatch boots measured 2.7 s. This is a favorable screening result with no
observed regression, but it is not yet a promotion-grade tail or latency claim.
No kernel or launcher change is included in this experiment.

## Stage 2 — Race-free event-driven discovery

Install the `/dev/input` watch before discovery, try the fixed hint once,
validate name, full input ID and capabilities, then perform one recovery scan.
Afterward inspect only creation events; rescan on overflow, ambiguity,
reconnect or explicit recovery. Apply the same watch-before-scan pattern to
`/dev/fb0`, validating geometry, stride, format and mapping. Controls use the
same input contract. Eliminate repeated 1 ms failed-open scans, preserve input
priority and block ordinary idle in `ppoll`.

Hardware-verify application-return retained-frame reuse. Cold bootloader-frame
reuse remains disabled.

## Stage 3 — Bootstrap progression

### 3A — Minimal shell

Retain pinned `/init` and its `start`, `root-ready` and `handoff` hooks plus the
filesystem/FIFO contract. Keep only endpoint setup, H700 module load, brightness
preparation, launcher start/PID, storage-root notification/acknowledgement and
ownership verification. Move all other logging and diagnostics after usability.

After Stage 2, A/B fully deferred preparation against low-priority concurrent
release/root/storage/application preparation after launcher dispatch. Test
release verification, storage, noncritical module, audio and provider work
separately. Concurrency promotes only if boot and UI interaction remain
non-inferior, failed probes/contention do not increase and content readiness
improves.

### 3B — Persistent freestanding coordinator

`start` launches one long-lived coordinator. It owns a private
`SOCK_SEQPACKET` launcher socketpair; launcher FD 3 is the fixed endpoint and FD
4 is closed. Transient later hooks use a root-owned mode-0600 control socket
with peer credential validation. The coordinator forwards versioned commands,
returns matching results and lives through acknowledged handoff.

The fixed 32-byte protocol includes magic, version, size, event, status,
sequence and `CLOCK_BOOTTIME`. Commands receive ACK/NACK with the same sequence;
completed duplicates return cached results; stale/malformed/truncated messages
are rejected; EOF, peer death, full buffers, `EINTR`, `EAGAIN` and timeout have
fixed semantics; unused ends close immediately; readiness is never dropped.

Pinned init still owns release selection, `prepare_sysroot`, mounts, recovery
and `switch_root`. Prove the same launcher PID and framebuffer/input ownership,
one storage anchor, one cancellable pending intent, no duplicate launch and
correct supervisor adoption.

### 3C — Standalone bootstrap/PID 1

Develop only as a separate extlinux candidate with the accepted initramfs still
bootable. It mounts `/dev`, `/proc`, `/sys` and `/run`, reproduces 3B transitions,
validates the release, owns the launcher protocol, handles PID 1 signals and
reaping, moves special filesystems and execs one fixed continuation. A fatal
failure preserves pixels but disables interaction. It cannot become default
until Stage 7 passes.

## Stage 4 — Retained userspace and content interaction

Run immutable final-root programs directly from versioned `/flash/bird`; keep
the early launcher in initramfs and mutable state under `/storage`. Evaluate one
at a time: fixed coordinator/module/firmware layouts, exact internal audio,
removal of HDMI/Bluetooth/quantum work, warm versus on-demand PipeWire, narrowed
udev, on-demand seatd, logind removal after suspend proof, volatile journald
before removal, trace-only diagnostics and PortMaster-only networking.

Measure A edge through launcher request, supervisor acceptance, provider exec,
usable provider state and first accepted input, plus provider exit through
restored Bird interaction. Cover RetroArch, PPSSPP, DraStic, OpenBOR/native
Ports, MPV audio/video, KOReader and PortMaster.

### Stage 4 audio-restore decision — 2026-08-01

Application-contract publication no longer restores audio: the menu has no
audio consumer, and the same restore already exists at the content-service
boundary. This removes an unnecessary post-menu gain, mute and route operation
while preserving silent-route recovery before a provider can emit audio.

The first candidate, source `1e58c93` and release
`v6.23-audio-pop-1e58c93`, is rejected. On the RG34XX-SP every recorded launch
reached `services-start`, returned status 1 before provider execution, and
cleaned up; some observed attempts required a forced reset. The candidate's
fail-closed mixer inspection therefore violated the content contract, and its
unconditional restore writes did not eliminate the audible transient.

The successor restore is a state reconciliation. It reads jack, speaker,
current sink volume and mute, writes no value that already matches, and changes
only the independent ALSA speaker switch when boot-with-headphones requires it.
It deliberately does not wake the suspended PCM sink with a PulseAudio mute
before that switch. Numeric volume and route mute are written only when their
saved and live values differ. Inspection or correction failures are recorded
in the content log but cannot block a game, reader or other provider. Volume
buttons retain their existing path. This remains a hardware candidate until
cold boots with and without headphones and repeated game/media launches prove
launch recovery, routing correctness and absence of the transient.

Hardware follow-up on release `v6.23-audio-reconcile-e400bb4` restored content
launching but rejected both remaining audio claims. Its logs recorded
`jack=unknown`, because the H616 jack is the proven ALSA `CARD` control while
the helper implicitly queried the `MIXER` interface. The same records proved
that Bird changed no route, volume or mute value, yet the suspended sink still
cracked when the provider opened it. Headphones produced two transients and the
still-enabled speaker reproduced audio simultaneously.

The next bounded candidate pins the full jack identifier
`iface=CARD,name='Headphone Jack'`. For audio-bearing content kinds 1–6 only,
it corrects the independent speaker switch first, then requests one explicit
PipeWire sink resume while muted and unmutes before provider exec. The intent is
to hide the codec power transition without keeping audio awake during menu idle
or adding work to reader and PortMaster sessions. The sequence is nonfatal and
must be rejected if it does not remove the transients, restore headphone-only
output, or remain interaction-non-inferior on the RG34XX-SP.

## Stage 5 — Battery, suspend and memory closure

Measure calibrated energy, wakeups, IRQs and CPU residency for short-label menu
idle, marquee idle, paused game, audio/video, Wi-Fi acquisition/transaction/
cleanup, lid suspend, resume and external power. Resume also records latency,
energy and exact brightness restoration. Audit every timer, retry, manager,
audio wake, network cleanup, storage access and input poll. Retain the capacity
timer until a proven event source replaces it.

Measure PSS/USS at usable frame, storage readiness, application readiness,
content idle and post-return. Reduce memory only where boot, interaction and
battery remain non-inferior.

## Stage 6 — Canonical namespace and hermetic image

Atomically migrate `/run/muos` to `/run/bird`, legacy state to Bird state,
catalog paths to `/storage/roms`, and normalized BIOS/Ports/media/persistence
paths. Supply one migration tool, rollback, interruption recovery and mixed-
state rejection; do not perform piecemeal compatibility removal.

Build the complete image with a digest-pinned container or immutable toolchain,
fixed partition/filesystem identities, deterministic mkfs seeds/options,
timestamps, owners, modes, ordering and sparse handling. Require two clean
builds in separate output roots and a separate-host reproduction where
feasible, yielding byte-identical output or a formally defined excluded-region
list. Content reproducibility may pass before Stage 7; selector power-loss
acceptance may not.

## Stage 7 — U-Boot A/B safety lane

Begin after Stage 0 in parallel without altering the accepted card. Implement
only redundant selector state, durable bounded attempts, externally forced
fallback, pre-userspace recovery, verified fallback assets and power-loss tests
at every transition. No display, artwork, frame or speed work.

Stage 7 gates 3C default promotion, deterministic-image selector acceptance
and routine experimental-kernel deployment.

## Stage 8 — Source-kernel parity lane

Parity builds may begin after Stage 0 in a digest-pinned environment but cannot
redefine the active baseline early. Rebuild the behavior-equivalent unmodified
ROCKNIX kernel/modules/DTB, boot the accepted current userspace, retain exact
config/tool/patch provenance, pass the full hardware/application matrix and
compare boot, interaction, power, size and memory. Promote that source-built
baseline before optimizing the kernel.

## Stage 9 — Fixed-device kernel optimization

The kernel owns panel initialization and cold brightness. Test standard DRM,
vblank and backlight readiness before adding a clean read-only driver
attribute. A/B direct cold brightness against the wake strike; keep the strike
only for proven off-to-on/resume transitions and restore exact requested
brightness. Prevent blanking, flashing and generic high brightness. Define
firmware-frame adoption experimentally but leave it disabled until Stage 10
provides the producer.

Measure live H700 polling and electrical topology. Use IRQ-backed GPIO input
where possible and minimal polling only where necessary while preserving exact
identity, capabilities, SDL GUID, rumble, reconnect and provider behavior.
Subtract drivers, modules, probes, buses, protocols and subsystems one
attributable group at a time only after complete consumer closure. Neutral
kernel measurement/readiness infrastructure may promote without regression;
performance changes require a measured boot, interaction, power, wakeup,
memory or size benefit.

## Stage 10 — U-Boot performance and inherited frame

After userspace and kernel stability, split PMIC, SPL/DRAM, TF-A, U-Boot,
storage, decompression and kernel-entry time. Hardcode the board, target and
paths; remove unused menus, discovery, USB/network paths, protocols and probes;
then optimize fixed loading and handoff. Add frame production last and enable
kernel adoption only in the joint experiment. Promote only when no blank,
clear, flash or input delay occurs and total power-to-usable or continuity
improves without higher-priority regression.

## Candidate report gate

Before editing, inspect and state the active critical path. Acquire and seal a
baseline, add focused tests, compile release/profile final-root and early
launchers where applicable, and run affected launcher, catalog, boot-frame,
storage, supervisor, application, content, persistence, controls, brightness,
PortMaster, deployment, fallback and reproducibility tests.

Report syscalls, framebuffer bytes, host dynamic instructions, ELF sections,
binary size, PSS/USS, tasks, wakeups and IRQs separately from RG34XX-SP timing
and calibrated energy. Preserve menu/navigation/paging/actions, Favorites,
asynchronous storage, exactly one pending selection, exact return state,
reconnect, recovery, all providers, networking isolation, charging, battery,
brightness, suspend/resume, shutdown, fallback and power-loss recovery.
