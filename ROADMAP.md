# birdOS roadmap

This is the authoritative plan for the active birdOS implementation. The
current repository candidate is **stock-root v6.23**. Stock-root v6.22 remains
the last broad hardware-accepted checkpoint until v6.23 passes the host and
RG34XX-SP promotion gates in [`ACTIVE_PATH.md`](ACTIVE_PATH.md).

The original feature-by-feature plan and full version narrative are preserved
in [`docs/history/LEGACY_ROADMAP.md`](docs/history/LEGACY_ROADMAP.md).
They explain how the project arrived here, but do not define the current build
or deployment path.

## Governing order

birdOS optimizes in this order:

1. Power-to-interactive-menu and interaction latency.
2. Battery efficiency and avoidable wake-ups.
3. Memory and storage efficiency.
4. Only the exact features required by the fixed RG34XX-SP experience.

Compatibility is a promotion gate, not a permanent excuse for generic work.
Each retained process, dependency, probe and abstraction must have a measured
consumer before it is accepted into the final image.

## Current state

| Boundary | Status |
| --- | --- |
| Fixed direct-framebuffer launcher, input and cached catalogue | Hardware accepted |
| Asynchronous storage, application dispatch and exact-page return | Hardware accepted through v6.22 |
| Games, media, Ports, system controls, suspend/wake and shutdown | Broadly accepted through v6.22 |
| Process-interruption-safe release deployment and post-init fallback | v6.23 candidate; promotion gate pending |
| Fail-closed application readiness and launcher health recovery | v6.23 candidate; promotion gate pending |
| Enforced foreground content lifetime and atomic persistence | v6.23 candidate; promotion gate pending |
| Fixed-device userspace reduction | Active |
| Custom kernel trimming | Deferred until userspace stabilizes |
| U-Boot optimization | Last lower-layer stage |

The active compatibility base remains the exact ROCKNIX 20260701 DDR4 kernel,
DTB, immutable system image and configured writable provider. birdOS replaces
the frontend and selected policy while retaining that proven application and
hardware closure.

## 1. Promote stock-root v6.23

Complete the combined correctness gate before subtracting more runtime work:

- build from every pinned input and verify the canonical
  `deploy-manifest.tsv`;
- fault-inject process interruption during release staging and selector
  activation, plus post-init automatic fallback, and prove that only a
  complete release can be selected;
- prove the application contract fails closed and a launcher exit is detected
  before a stale first-frame marker can be accepted;
- prove every foreground descendant is contained and reaped before the launcher
  resumes, including TERM-resistant and reparented children;
- verify atomic Favorites and shutdown checkpoints plus bounded polling and
  execution-error recovery; and
- repeat the broad physical gate for menu/input, early storage, games, media,
  Ports, controls, suspend/wake, global exit, fallback and shutdown.

No v6.23 result is a new baseline until both the host suite and physical device
gate pass.

## 2. Finish the retained-userspace audit

Continue with the highest-return, lowest-risk layer:

- classify every retained ROCKNIX startup script, service, output and idle
  wake-up by its exact consumer;
- keep the launcher as the first usable userspace application and move all
  nonessential work behind its interactive frame;
- replace generic discovery with fixed RG34XX-SP initialization only after all
  game, media, control and suspend consumers are proven;
- generate the exact Sway, audio and application profiles instead of running
  broad multi-device generators;
- reassess udev, logind/seatd, journald and other resident managers from
  measured behavior; and
- keep networking absent from offline boot and acquire it only for an explicit
  network session such as PortMaster.

The retained implementation and open audit evidence are tracked in
[`ROCKNIX_AUDIT.md`](ROCKNIX_AUDIT.md).

## 3. Remove compatibility namespaces and shims

After the v6.23 gate is stable:

- move runtime markers and persistent state from legacy `MUOS`/`muos`
  namespaces into canonical birdOS locations;
- generate catalogue paths directly for the final `/storage/roms` contract;
- normalize BIOS, Ports and media paths; and
- delete launcher and runner rewrites only after one coherent migration and
  rollback test.

This is a single migration boundary. Partial namespace conversion is not an
acceptable deployed state.

## 4. Reproduce the complete birdOS image

Bake the accepted card-side state, fixed profiles, launcher, recovery assets and
content contracts into one deterministic image build. A clean checkout with the
pinned upstream inputs must reproduce identical boot and runtime artifacts. The
process-interruption-safe release mechanism remains the development and recovery
path until that image passes the same broad device gate.

## 5. Build the fixed RG34XX-SP kernel

Only after userspace contracts and benchmarks settle:

- start from the compatible public ROCKNIX Linux source and exact device tree;
- record the complete live hardware and module closure;
- remove unused drivers, buses, protocols and probes in measured batches;
- hardcode fixed-device policy where that improves latency or efficiency without
  coupling unrelated application behavior; and
- require the custom kernel to beat the accepted release kernel in boot latency
  or efficiency while preserving display, input, storage, audio, charging,
  suspend, content and shutdown behavior.

Kernel work does not absorb launcher, content-session or optional-network
policy. Those remain separate userspace responsibilities.

## 6. Optimize U-Boot last

Once the kernel boundary is stable:

- shorten unused target discovery and fixed-device probes;
- investigate earlier green-LED and panel assertion;
- implement a genuine bootloader-owned A/B selector with redundant durable
  boot state, bounded tries and a recovery-tested response to power loss at
  every state transition;
- preserve a recovery-tested boot path for every experiment; and
- decide from measured power-to-menu behavior whether any splash is still
  useful.

The runtime red LED remains reserved for the fixed low-battery threshold. Boot
indicator policy and runtime battery policy are separate owners.

## Deferred experience and performance work

These items are intentional backlog, not discarded features:

- survey muOS and other handheld operating systems for transferable performance
  techniques;
- tune RetroArch, standalone emulators and first-game cold loading;
- optimize PortMaster startup and finish its network experience;
- package the pinned KOReader runtime as an RG34XX-SP-native on-demand app so
  books no longer cross PortMaster preparation hooks;
- add build-time game collections and optional post-first-frame user playlist
  indexes without adding a boot-time ROM scan;
- make music, video, reading, Ports and emulator interfaces bespoke;
- finish media controls, playlists and reader formats;
- optimize suspend/wake battery behavior;
- calibrate charging percentage and final LED behavior; and
- retain the accepted static cat-and-stairway wallpaper; keep boot animation
  and sound as future ideas unless they can be introduced without delaying
  usable input.

Independent items may share one physical card cycle only when their outcomes
remain distinguishable. Larger performance work comes before cosmetic
diminishing returns; once those boundaries are stable, line-by-line subtraction
remains part of the project goal.
