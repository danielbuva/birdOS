# birdOS RG34XX-SP optimization roadmap

This is the governing constitution for the active stock-root implementation.
The current human promotion record binds clean source
`5373c644b9c91ac21a17e145375747a8196a3337`, immutable release
`v6.23-20260814-201218`, deploy manifest
`904c8da42a6ec84ccf4b291205999c3b0e25900f4bec7bb3f9e0cfefb29164dd`,
device contract
`1664a3778abcd3687865a82fd28bba5b468f6c3c7e9a46bf90f7c3acb1e08162`
and catalogue
`9795aae6baddc292f5d9954a444656e303db305c639284f16eb10288c41f1f93`.
Immutable release `v6.23-20260811-234132` remains the previously accepted,
privately archived binary reference. Its canonical manifest digest is
`a0a38b04be25f2d09009b0677d33c0d34c65b027c0ff1b9463f71cdeec9b274b`.
It was built from clean source
`c07fe18769a13a3b1997e2cf1a4900cc55423d5b`; it is verified history rather
than an on-card rollback release.

The historical version narrative remains in
[`docs/history/LEGACY_ROADMAP.md`](docs/history/LEGACY_ROADMAP.md). It explains
how birdOS arrived here but does not define current work.

## Immutable priority and promotion policy

Optimize in this lexicographic order:

1. Power-to-visible, genuinely usable menu.
2. Interaction latency across menu navigation, application/content launch,
   application/content close, and restoration of an interactive Bird menu.
3. Calibrated battery energy and unnecessary wakeups.
4. Memory and storage efficiency.
5. Fixed-device kernel work after userspace promotion.
6. U-Boot performance and frame production last.

Each promotion cycle names one target. At the operator's direction it may batch
as many independently reviewable changes as practical, provided every active
path, baseline, delta, assertion, host test and rollback boundary remains
explicit. The batch promotes or rejects as a whole on hardware, while its
components remain independently revertible in source. It may promote only when
its target improves beyond a margin frozen from A/A variation and instrument
resolution, every higher-priority metric is non-inferior, and accepted behavior
remains intact. Cosmetic continuity may not delay honest usability at all.
Neutral correctness, measurement, rollback and readiness infrastructure may
promote with no measurable regression.

Priority two and priority three require an explicit fixed-consumer balance,
not a universal warm or cold policy. Hardcode and keep a process or prepared
resource warm when device measurements show a material launch/close benefit
inside the fixed RG34XX-SP application closure. Quiesce or start it on demand
when calibrated idle-energy savings are material and every boot and interaction
metric remains within its frozen non-inferiority margin. Near-instant launch
and return is the direction of travel, but not permission to keep unrelated
work resident without an energy result. Memory and storage savings never
justify regressions in boot, interaction, or calibrated battery life.

The tie-break is temporal: interaction latency wins during an active user-
requested transition; battery efficiency wins between transitions. A transition
begins when Bird accepts the action and ends only when the requested UI/content
owns responsive input, or when Bird has regained responsive input after close.
Correctness-critical teardown stays in that interval; unrelated persistence,
diagnostics and cleanup move asynchronously afterward. In inactivity, converge
quickly to the lowest practical power state with no pending action, polling or
unjustified hardware/process residency. This is neither an all-warm nor an all-
cold policy: retain only small measured state whose common-transition benefit
justifies its usage frequency, idle energy and memory cost.

Every implementation summary reports in this order: current stage, a short
reason the previous implementation existed, what changed, lexicographic
priority effects, boot-log timing, tests, hardware verification and next work.

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
validated open input descriptor. `/run/bird/bird-first-frame-ready` publishes
that meaning. Publishing readiness must not force a
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

For every successor to the current accepted binding:

1. Publish a clean commit and verify local, origin and public identity.
2. Build all pinned inputs under a fresh immutable release ID.
3. Build release/profile final-root and early-initramfs launchers.
4. Run the complete host suite and transactional fault-injection tests.
5. Deploy while the accepted canonical base remains intact through candidate
   staging, verification and activation.
6. Complete the RG34XX-SP behavior and measurement gate.
7. Seal the evidence and create the exact promotion record.
8. Only then update authority documents to name the successor as accepted.

If any physical gate fails, retain the preceding accepted source/release tuple
as the externally archived behavior reference and return the card to the host
for verified selector restoration or redeployment.

### Fast-workflow stabilization policy — 2026-08-08

The mutable `dev-current` path is now exercised rather than extended. After the
bounded catalog-metadata and cleanup-readiness corrections, freeze new recovery
states and safety machinery. Use `--changed` for ordinary candidates and
`--all-local` for the complete local gate; record actual duration, selected
groups, unnecessary rebuilds, output clarity, rollback/cleanup friction and
real failures. Harden further only for observed recurring friction or a direct
production/data-loss risk. Rare recoverable residue remains documented unless
it occurs. The human promotion binding remains authoritative, but the fast
workflow gains no mandatory promotion-record enforcement or state-schema
expansion during stabilization.

The first real `--all-local` gate took 716.01 seconds and then rejected its
actual output before card mutation: 37,617,684 bytes were required and
30,601,728 were available. A proposed 128-to-138 MiB migration stopped before
unmount or raw write when its privileged pre-write temporary could not be read
by the following unprivileged comparison. The card remained unchanged and that
migration path is retired.

The replacement policy keeps p1 at 128 MiB and uses one immutable canonical
base plus one mutable `dev-current` slot. Canonical deployment archives and
independently verifies superseded immutable releases privately, self-references
the activated canonical selector, and only then removes their card copies. The
selector therefore never points at removed bytes. No alternate kernel, selector,
or UI remains. Failed boots persist evidence and return the card to the host.

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

### Stage 2 launcher-input candidate — 2026-08-01

The accepted audio diversion boundary is release
`v6.23-audio-defer-a078861`: the complete physical behavior check passed,
headphone exclusion remains correct and crack/pop work remains deferred.

The first discovery candidate changes only launcher input startup and
reconnect. The prior missing-device loop performed a preferred-first scan of
all 32 `event*` candidates, slept 1 ms and repeated until the five-second
deadline. The candidate installs an inotify watch before its preferred probe,
performs one recovery scan, then blocks in `ppoll` and validates only a newly
created numbered event node. Queue overflow is the only ordinary reason for a
second complete scan. If inotify itself is unavailable, the bounded prior
polling behavior remains as a recovery fallback.

The focused host edge fixture records 32 initial failed opens, one blocking
poll, no nanosleep and one open of the created node; the prior design could
repeat the 32-open scan after every 1 ms sleep. This is a structural host
syscall result, not a device boot-latency claim. Full H700 input-ID/capability
validation, fixed-controls discovery and framebuffer discovery remain separate
Stage 2 candidates after this one passes hardware.

Hardware follow-up on release `v6.23-input-watch-c141573` passed the complete
functional screen. The watch-before-scan launcher path is retained; no boot,
input, content or return regression was observed. This is behavioral
acceptance, not a promotion-grade timing claim.

The second launcher-input candidate validates the exact H700 identity after
the name match: bus `0019`, vendor `484b`, product `14df`, version `0100`, plus
the complete event, key, absolute-axis and force-feedback bitmaps. Repeated
retained hardware snapshots exposed and correct one Stage 0 authority error:
the full force-feedback bitmap is `107030000 0`, not the truncated `10000 0`.
The TSV now stores key and force-feedback capabilities as canonical
little-endian 64-bit word arrays, and its generated header supplies those
arrays directly to the freestanding launcher without parsing.

An H700 name match with an ioctl failure or any identity/capability mismatch is
closed and the bounded scan continues. The legacy `muOS-Keys` recovery mapping
is unchanged. The ready H700 path adds five fixed ioctls after the existing
name ioctl; hardware must show boot non-inferiority before promotion.

Hardware follow-up on release `v6.23-input-contract-4fd18d0` passed the complete
functional screen. Exact launcher input validation is retained. No ordinary
behavior regression was observed.

The retained device records now separate the earlier visible-but-not-input-ready
frame from honest usability. Forty older boots reached their later input-ready
frame at a descriptive median 1,504 ms after kernel start. Ninety-four later
boots reached a visible, input-ready frame at a descriptive median 1,229 ms, a
275 ms kernel-relative improvement. The user's external stopwatch observations
also moved from approximately 2.8 seconds toward consistent 2.7-second boots.
These are RG34XX-SP measurements and support an observed boot improvement; they
are not a randomized or environmentally paired promotion distribution.

The third Stage 2 candidate changes only the post-menu fixed-controls worker.
It installs and retains a `/dev/input` creation watch before its initial scan,
stops that scan as soon as power, volume, lid and the exact H700 gamepad are
open, and thereafter opens only a newly created numbered node. Reconnect and
queue overflow permit one complete recovery scan. If inotify is unavailable,
the prior bounded 250 ms scan remains as the recovery fallback.

On the measured RG34XX-SP event layout, ordinary initial discovery drops from
32 event-node opens to five. With any source missing, the prior path woke four
times per second and could issue 128 failed opens per second; the watched path
blocks without a discovery timer. This is principally a priority 3 battery and
wakeup candidate. It may reduce priority 2 scheduler/filesystem contention
during reconnect, does not enter the priority 1 usable-menu path, and adds one
resident descriptor plus a small amount of code rather than targeting priority
4 memory.

The first physical follow-up for that controls candidate found rapid repeated
power and lid suspend requests could be ignored until ROCKNIX resume cleanup
finished. The retained provider brings CPU1--CPU3 online at the start of resume,
but only then restores governors, unfreezes processes, turns the panel on,
releases input grabs, restores the remaining devices and globally kills the old
suspend helpers. A visible panel is therefore not evidence that the transaction
has completed.

Release `v6.23-suspend-queue-ec0ea60` tried to retain this input in separately
invoked shell wrappers. The physical gate rejected it: the cooldown remained
and one suspend cycle ended in an abrupt reboot rather than an orderly Bird
shutdown or restart. Anonymous shell scheduling could not establish ownership
before another helper was dispatched, so that mechanism was removed rather
than promoted.

The first successor, release `v6.23-suspend-coordinator-7c332d5`, moved pending-
intent ownership into the persistent fixed-controls process on CPU0. Its device
trace proved lid resume reached wrapper completion in 92--167 ms, ruling out
the ten-second failure bound as the ordinary cooldown. It also exposed the
remaining defect: no power resume entered the coordinator. Every power edge was
dispatched as a new helper because the hot path still asked ROCKNIX's transient
power flag whether the edge meant suspend or resume. Rapid series consequently
contained only `dispatched` records and no `queued` or `complete` record. The
physical gate rejected that candidate as a cooldown fix.

Read-only inspection after that rejection found the lower-level split owner.
The live writable ROCKNIX image contained `system.suspendmode=mem`,
`AllowSuspend=yes` and no logind lid override. The retained H700 fake-suspend
provider exits immediately in that mode, while logind can independently request
the H700 real suspend path that upstream itself labels broken. File timestamps
showed the H700 policy writer at 14:38:28 and the later generic
`009-sleepmode` rewrite to `mem` at 14:38:29. Bird controls had already started
at 5.308 seconds, while compatibility autostart did not begin until 9.397
seconds, so even a correct late writer could not protect a quick post-menu
suspend. The next candidate therefore installed `off`, `AllowSuspend=no` and
power/suspend/lid `ignore` policy during initramfs root preparation, before
systemd, removed competing sleep/logind `*.conf` drop-ins, and suppressed both
late policy writers. The policy files are generated from the device contract;
accepted files are compared and not rewritten on later ordinary boots.

Release `v6.23-suspend-policy-92abfe8` was deliberately policy-only. Root preparation
canonicalizes exactly one copy of each fixed `system.suspendmode=off`, fake-
suspend, timed-shutdown and core-parking key; installs generated sleep/logind
drop-ins; removes competing drop-ins; and suppresses both late writers. It does
not modify the rejected coordinator, provider, wrapper, controls binary or
their writable execution paths. This isolates whether the observed cooldown
and reboot came from split real/fake-suspend ownership. It is a correctness
candidate pending physical proof and makes no boot, interaction, battery or
memory claim.

The returned physical gate rejected that release: both lid and power became
no-ops. Read-only ext4 evidence proved root preparation installed the candidate
at 17:52:41, then retained common/001 `chksysconfig` found a missing
`retroarch.cfg` and ran its broad `rsync -a /usr/config/ /storage/.config` at
17:52:48. That copied the stock `AllowSuspend=yes` file and a stock
`system.cfg` with no `system.suspendmode`. With both later writers suppressed,
the fake-suspend provider treated the absent key as hardware suspend enabled
and exited successfully before doing work, while logind correctly ignored the
same events. The corrective candidate seeds only missing RetroArch prerequisites
before PID 1 and replaces common/009 with a fixed post-recovery verifier. It
reasserts `off` and the generated sleep policy after any retained recovery but
performs only comparisons in the accepted steady state. H700/030 remains
suppressed. This is a correctness fix pending a new physical suspend gate, not
a performance claim. Its ordinary path removes the returned-card recovery
trigger; fail-closed handling for a separately fault-injected common/001
recovery failure remains a later retained-userspace hardening candidate.

The RG34XX-SP gate accepted release
`v6.23-suspend-recovery-103ce3b` (manifest
`8f779e033385c51d2ebe441c21c637bb00920e7192b93fe4a79277a3924174a0`)
for continued roadmap work. Menu, content and shutdown behavior passed, and
power/lid suspend became substantially more reliable, consistent and
predictable. The returned trace proves ordinary provider resume completion and
the coordinator's queued/cancelled-intent paths. One deliberately rapid power
sequence still reached the existing ten-second completion timeout; that and
the remaining physical quirks are accepted-for-now and explicitly deferred.

This repair did not change launcher dispatch, rendering or input: the early
launcher is byte-identical. In the returned sample, honest first usability was
recorded at approximately 1.22 seconds after kernel start and root preparation
ran later, at approximately 3.87 seconds. That ordering is evidence for the
sample, not an architectural post-usable guarantee: pinned init starts root
preparation concurrently after launcher dispatch and has no explicit
usable-frame barrier before continuing. The fixed verifier runs later in
retained common autostart.

The accepted steady state adds no writes, resident process, timer or idle
wakeup. Raw release payload excluding the manifest grew by 3,688 bytes; cpio
block rounding kept the uncompressed early archive at 2,072,064 bytes and the
gzip archive changed from 615,064 to 615,052 bytes. That compressed-size
variation is release-identity noise, not an optimization claim. Transient peak
memory and RG34XX-SP timing and energy remain unmeasured. The remaining suspend
quirks are accepted for now and are not a gate on the next bounded candidate.

### Stage 2 framebuffer discovery and retained-return result — 2026-08-01

The bounded framebuffer candidate changes only how the launcher waits for the fixed
`/dev/fb0` node. It installs a `/dev` inotify watch before the first exact
`fb0` probe, accepts only `fb0` create or move events, and performs one exact
reprobe after queue overflow. The previous bounded 1 ms polling loop remains
only when inotify cannot be installed. Framebuffer geometry, stride, format,
mapping validation, framebuffer ownership and all render paths are unchanged.

When `fb0` registers late, this removes repeated failed opens and 1 ms sleeps
from the power-to-usable path. When `fb0` is already present, it adds inotify
setup and close work to the prior single-open path. It therefore targets
priority 1 only for delayed framebuffer registration and adds no ordinary-idle
polling.

The returned card selected
`v6.23-framebuffer-watch-84a2435`; its previous selector remained
`v6.23-suspend-recovery-103ce3b`. The selected release's canonical manifest
digest is
`4e056a6f6d9a03525b79db5504f260499f1f8748000984b295b31f132239fd83`,
and deployment verification covered all 54 of 54 manifest-owned files. Two
returned cold-boot records reported launcher-start/input-ready/usable-frame
milestones of 1221/1221/1224 ms and 1222/1223/1227 ms after kernel start. The
immediately preceding release's three usable-frame samples were 1226, 1229 and
1227 ms. These small unpaired sets establish functional non-regression only;
they do not support a boot-time improvement claim.

No framebuffer wait, ioctl, mapping or format error appeared. The returned
boots do not carry an explicit counter proving whether the inotify wait branch
ran, so late-registration branch activation remains host-tested but
uninstrumented on hardware. The complete functional screen passed.

Application return also exercised retained-frame reuse on this exact release.
The replacement launcher started at 32033 ms, reopened the exact H700 input at
32034 ms and published its usable frame at 32091 ms. It recorded
`render=recovery`, restored the saved snapshot, found zero
header/content/footer region mismatches, observed a stable unused X byte and
produced exact matching expected and actual bound hashes. The user verified
the returned menu and content behavior. This completes Stage 2 behaviorally;
it is not a promotion-grade interaction-latency distribution.

One lid-suspend attempt on the returned release ended in a reboot. Its retained
suspend evidence ends before a matching completion record, but that does not
prove whether the reboot originated in Bird's coordinator, the retained
provider, the kernel or a separate power path. The cause is unproven and the
remaining suspend quirk stays explicitly deferred rather than gating Stage 3.

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

#### Stage 3A normal-success shell subtraction — pending host and physical gates

The first Stage 3A candidate changes diagnostics and shell mechanics only. On
the current normal-success path, the early hook spawns BusyBox `cat` to read the
fixed backlight maximum, writes two brightness-diagnostic records before launcher
dispatch, then spawns three BusyBox `cut` children for concurrent/later uptime
records and four BusyBox `cat` children to inspect the two LEDs at root-ready
and handoff. The
candidate replaces the fixed maximum read with a shell builtin `read`, removes
the two pre-launch success writes and removes those seven later success-only
children. LED inspection moves to failure evidence only.

The candidate must preserve the exact backlight writes and 50 ms strike,
endpoint creation, H700 module load, launcher start and PID publication,
storage notification and acknowledgement wait, ownership verification,
timeouts, launcher retirement and all failure records. It does not reorder
launcher, module or brightness work and does not introduce a trace-mode branch
or helper into the critical path.

Its priority-1 target is the removal of one pre-launch child process, two
pre-launch diagnostic writes and one root-ready uptime child that can execute
concurrently with launcher startup. Removing the remaining six later transient
children may reduce root-handoff CPU, I/O and transient memory/energy and may
help later application readiness; it does not target menu interaction and adds
no resident task, timer or ordinary idle wakeup. Launcher code, framebuffer
byte traffic and steady memory are unchanged. No boot, content, energy or
memory improvement is claimed until the host and RG34XX-SP gates measure it.

Returned hardware evidence for `v6.23-early-shell-24a364c` recorded
launcher/input/usable milestones of 1217/1218/1229 ms and 1211/1212/1225 ms,
with storage anchored at 3685 and 3739 ms. Menu, launch, return and shutdown
behavior passed, but a movie pause press also selected the next audio track.
The active and previous releases carry byte-identical MPV input policy, so that
content-control defect is not attributed to the early-shell subtraction. It
nevertheless blocks combined-candidate acceptance.

The first bounded correction made `GAMEPAD_ACTION_RIGHT` harmless and moved
audio-track selection to `GAMEPAD_ACTION_UP`. Hardware disproved the assumption
that this was independent: west retained its original time-details behavior but
also changed tracks, south paused correctly, and east both paused and changed
tracks. A second policy-only move cannot establish one-command ownership.

Active-path inspection found the cause: retained `start_mplayer.sh` starts the
raw-evdev `mpv_sense` service and also enables MPV's SDL gamepad reader. Both
consume the H700 event stream, and the shell service additionally forks
`evtest`, `udevadm`, `echo` and `socat` work. The deployed Stage 4 candidate
therefore uses one media-lifetime freestanding process to validate the fixed
input contract and send MPV JSON IPC directly. The player wrapper starts
neither `mpv_sense` nor SDL/default input handling, but preserves the provider's
`set_kill set "mpv"` fake-suspend freeze contract and clears it on return.
Ordinary media idle blocks in `ppoll`; an IPC retry timer exists only before
the MPV socket is available or while reconnecting. Evdev overflow is discarded
through `SYN_REPORT` and held modifiers are resynchronized from the device.
IPC reconnect clears unsent commands so a stale action cannot reach a new
connection.

The candidate restores the complete documented regular and one-handed control
set: face actions, short/long seeks, chapters, playlists, subtitles and
shoulder+Select audio-track cycling. Select+Start emits no media command and
remains owned by the global exit worker. Menu+D-pad contrast and saturation
steps of exactly one point per press are explicit Bird extensions. This
final-root media path adds no boot or menu-idle work. Its priority-2 target is
one command per physical edge without per-press process creation; its secondary
priority-3/4 targets are fewer
media-session tasks, wakeups and resident bytes. No device latency, energy or
memory improvement is claimed before measurement.

Clean source `f866fe7dbeaec3e3ee0d3937296968c804b77665` is deployed for
this physical gate as immutable release `v6.23-mpv-single-input-f866fe7` with
canonical manifest
`475e786077d54d7247dbd11d463fcb8b8bd1377c7315e5913644f58bdb9fe017`.
All 56 manifest-owned files verified, and
`v6.23-mpv-controls-659594b` remains the previous selector. The final-root
helper adds no launcher or early-initramfs executable. Its 6,424-byte file and
8,288-byte text/data/BSS footprint are host binary measurements only. The
launcher is byte-identical to the previous release, so boot timing remains a
hardware non-inferiority check rather than a claimed improvement.

The physical gate rejects that exact tuple for content-control completeness.
The one-point contrast/saturation extensions worked, but bumper taps no longer
changed MPV-local volume and direct audio-language cycling was absent. Physical
B reached the configured `frame-step` action; MPV pauses and advances one frame
when it receives that command during playback, explaining the apparent rapid
play/pause. Trigger chapter commands remain silent on content without chapters.
Host `ffprobe` found zero chapters in both tested files; the next physical gate
uses `Angel's Egg.mkv` or `The Godfather.mp4`, which contain seven and 23 chapter
records respectively.

The next bounded correction keeps one raw input owner and adds no boot work.
Physical X cycles audio instead of mute. A bare L1/R1 press resolves on release
to MPV-local volume -/+2; using that bumper with another control suppresses the
volume action and retains the one-handed layer. Menu+L1/R1 changes MPV-local
video brightness by one point. L2/R2 retain chapter navigation and the
shoulder-modified trigger path retains playlist navigation.

The correction is deployed for physical gating as clean source
`813226d4c1b0fe9715bdae3f37d44485e4ad815f`, immutable release
`v6.23-mpv-complete-controls-813226d` and canonical manifest
`05f20822324d62be334a290f9567d341efc6f08243c14ab88adda43073d975a6`.
All 56 manifest-owned files verified and the rejected
`v6.23-mpv-single-input-f866fe7` tuple remains the previous selector. The
launcher is byte-identical. The final-root helper grows by 280 file bytes and
six loadable-section bytes; it adds no boot executable, menu task, timer or
wakeup. Physical controls, media suspend, launch, exit and return remain the
gate before promotion.

Boot ID `347650ca` passes that physical control gate, so the exact tuple is the
accepted Stage 4 MPV-control checkpoint. The returned early log recorded
launcher start/input/usable-frame at 1218/1219/1222 ms and storage at 3945 ms.
One earlier candidate sample recorded 1223 ms input and 1232 ms usability; this
unpaired result is non-regression evidence, not a boot-time improvement claim.

The same run provides the next content-interaction baseline: request at
7.558 s, content-session start at 10.09 s, application contract at 12.21 s,
Sway readiness at 14.04 s and provider dispatch at 14.29 s. Provider return at
73.98 s was followed by replacement-launcher start at 74.324 s and matched
retained-frame usability at 74.377 s. Optimize one attributable interval at a
time and retain physical photon measurement as the promotion metric.

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
until its own host-recoverable extlinux candidate and card-return procedure pass
without relying on an on-card superseded production release.

## Stage 4 — Retained userspace and content interaction

Run immutable final-root programs directly from versioned `/flash/bird`; keep
the early launcher in initramfs and mutable state under `/storage`. Evaluate one
at a time: fixed coordinator/module/firmware layouts, exact internal audio,
generic quantum work, warm versus on-demand PipeWire, narrowed udev, on-demand
seatd, logind removal after suspend proof, volatile journald before removal,
trace-only diagnostics and PortMaster-only networking. HDMI and Bluetooth
retention/removal remains an explicit later product decision and is not
authorized in current candidates.

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

Hardware follow-up on release `v6.23-audio-prewake-eba3438` accepts only the
fixed route correction. The first content launch observed the exact CARD jack
as on and the independent speaker switch as on, changed that switch off, and
later launches observed it already off. Physical testing confirmed that audio
then used the headphones alone. The muted prewake sequence reported `ready` on
every observed launch but did not remove the speaker transient or the two
headphone transients. It is rejected and removed: its three extra `pactl`
operations have no accepted benefit and must not remain in the content path.

Crack/pop elimination is now deliberately deferred within Stage 4. A future
bounded candidate must attribute the transition among H616 codec power, the
analog amplifier/path, PipeWire suspension and UCM policy before changing
residency or timing. The accepted path remains nonfatal state reconciliation at
the provider boundary; it does not keep audio awake while the menu is idle.

### Stage 4 direct-flash launcher candidate — 2026-08-02

The first immutable-execution candidate moves only replacement launcher exec,
not early ownership. Clean source
`12b8ff6906eebe86eac9431d690769fcc94db1c1` is deployed as immutable release
`v6.23-flash-launcher-12b8ff6` with canonical manifest
`44ce41ac87cea8f84a36ea1934c28b2d9ed3821d76bf8b864d2bc484ecececd5`.
All 56 manifest-owned files verified, and the physically accepted
`v6.23-mpv-complete-controls-813226d` release is the previous selector.

The initramfs launcher and its ownership/handoff contract are byte-identical.
The supervisor executes a necessary replacement from
`/flash/bird/bird-launcher`; root preparation no longer copies, chmods or
verifies the 597,336-byte launcher under writable storage. Including the
17-byte supervisor shrink, the per-boot copy payload falls from 817,170 to
219,817 bytes (73.1 percent), with one fewer `cp` process, one fewer mode
operand and one fewer destination capability check. Release and profile
final-root/early launcher variants compile; the release launchers remain
byte-identical to the accepted checkpoint.

This targets final-root preparation and content return. It does not change
launcher rendering, input, early-initramfs execution, resident tasks or idle
timers. Hardware boot non-inferiority, launch/return behavior, content timing,
transient memory and energy remain the gate; no RG34XX-SP latency or battery
improvement is claimed yet. If accepted, move the next final-root executable to
the immutable release as a separate candidate rather than widening this one.

The direct-flash candidate passed the RG34XX-SP functional gate. Boot ID
`a4886df4` recorded launcher start/input/usable-frame at 1220/1221/1224 ms,
only +2 ms in each unpaired observation versus the accepted MPV checkpoint;
this is non-regression evidence, not a boot improvement. An early game request
also exposed the next priority-two interval: launcher exit at 3.996 s left its
last pixels visible without input until provider start at 14.50 s. Optimize
that attributed 10.5-second content-readiness gap one boundary at a time.

The next correctness/instrumentation candidate is clean source
`e2c46b278c19974c2983aadc1249bcce9353f709`, immutable release
`v6.23-emergency-recovery-e2c46b2` and canonical manifest
`cfe5864bd9a21805d14b625bc17945dd14eb38a5206593f22072ffcf1e640f91`.
Menu+Select+Start captures bounded volatile diagnostics to persistent storage,
syncs them, cancels pending foreground state, exits only the managed foreground
tree, validates any inherited launcher by exact executable identity and asks
the existing supervisor to restore the menu. It adds no ordinary boot work,
resident process, idle timer or wakeup. Fixed controls add 256 file bytes with
unchanged BSS; the immutable emergency-only helper adds 6,254 release bytes.
The physical gate is logged recovery plus unchanged ordinary launch, exit,
brightness, volume and suspend behavior. This candidate does not block later
content-readiness investigation if the reported early-selection fault remains
intermittent.

Boot ID `bf45b45b` accepts the recovery mechanism and turns the intermittent
freeze into attributable evidence. The chord persisted 178,213 bytes, completed
foreground cleanup and restored a retained-frame usable menu in about 656 ms;
the same game then launched and returned normally. Initial
launcher/input/usable-frame milestones were 1217/1218/1221 ms.

The fault was a final-root systemd cycle, not a provider crash. The retained
image enables powerstate from multi-user, Bird made it wait for essway, essway
waits through graphical/seatd/multi-user, and systemd deleted the initial
`essway.service` job at 5.268 s. The early launcher subsequently exited on a
valid request with nobody available to dispatch it.

The next bounded Stage 4 correctness candidate removes only
`After=essway.service` from powerstate. Source
`895e6a7ae557df3b202e6ac7b78234441b705c0e`, release
`v6.23-ui-order-895e6a7` and manifest
`fdf3e466ef85682c4b6de977ff8484c5bb9b24eddf953f4f6981eb206aa6e149`
are deployed with the accepted recovery release as previous. The unit shrinks
15 bytes; launcher and power-worker binaries are identical. No early-initramfs
executable, boot task, timer, idle wakeup, framebuffer traffic or resident
memory changes. The hardware gate requires both services active, no ordering
cycle, repeated cold first-game launches and unchanged boot/UI behavior before
the next content-latency subtraction.

That gate passes. Six returned boots recorded usable-frame times of 1229, 1225,
1222, 1222, 1224 and 1218 ms, with a descriptive median of 1223 ms. Both
`essway.service` and `powerstate.service` were active in every captured
final-root snapshot; no ordering-cycle/job-deletion event remained. Repeated
first-game launch, normal provider return, shutdown and a second logged
emergency restart passed. This is boot non-regression evidence, not a new
distribution claim.

The next independently bounded Stage 4 candidate executes the immutable
content dispatcher directly as `/flash/bird/run-content.sh`. Clean source
`0b438f52b767e3c8ec008c1a5e7c342c0d503643` is deployed as
`v6.23-flash-runner-0b438f5`, manifest
`2ca0ba49a33e0a62f9abbe73419696a32943af70fbc266659ad59bd08cf75ec6`,
with all 57 manifest-owned files verified and the accepted ordering checkpoint
as previous. Root preparation no longer copies, chmods or verifies a writable
dispatcher duplicate. The copy set falls from 18 files/220,067 source bytes to
17 files/154,715 bytes: one fewer `cp` child, one fewer mode operand, one fewer
destination check and 65,352 fewer source and destination bytes per boot. The
65,346-byte dispatcher and both launcher variants are byte-identical; no
framebuffer, input, task, timer or resident-memory behavior changes. Boot and
content timing, energy and the complete launch/return gate remain physical
measurements rather than claims.

That gate passes. Three surviving usable-frame records are 1224, 1232 and
1239 ms, a descriptive median of 1232 ms versus 1223 ms for the preceding six
boots. The early launcher is byte-identical and the external stopwatch remained
about 2.7 seconds, so the sparse observations establish non-regression only.
Content launch/return, media, emergency recovery and shutdown remained
functional.

One suspend stress boot reset during an in-flight power resume. Four cycles had
completed; the persistent trace then recorded power dispatch at 29.623 and
30.566 seconds without a subsequent resume-complete marker. No shutdown,
panic/Oops, pstore or PMIC reset cause survived, and the following boot passed
repeated cycles. With no attributable failing layer, a cooldown or provider
change would be speculative; the quirk remains deferred for finer phase/reset
instrumentation and does not block Stage 4.

The next independently bounded candidate starts the generated supervisor as
`/flash/bird/supervisor.sh` and removes only its writable duplicate. Clean
source `f06686ab0cf80676733de800809c39765aadfc6e` is deployed as
`v6.23-flash-supervisor-f06686a`, manifest
`e69a5c90fae8479161819b5797984d03e9d8a15e0c96f23a75c4647c6582bb37`,
with all 57 manifest files verified and the accepted dispatcher checkpoint as
previous. Preparation falls from 17 files/154,715 bytes to 16 files/136,973
bytes: one fewer `cp`, mode operand and destination check, plus 17,742 fewer
source and destination bytes. Launcher, input, framebuffer, provider, suspend,
audio, resident tasks, timers and memory are unchanged. That physical gate
passes. The direct supervisor, both services, game/media launch and return,
emergency restart and shutdown remained functional. Valid usable-frame records
were 1232 and 1221 ms after kernel start and the external stopwatch remained
near 2.7 seconds. This establishes non-regression only.

Audio-only MPV suspend remains a separate non-blocking defect. One run ended
inside resume without a completion marker or surviving reset cause. The next
run completed suspend/resume but audibly repeated about one second; PipeWire
logged output and MPV XRUNs at resume. A movie completed the same retained
fake-suspend path correctly. The provider currently stops MPV while leaving the
PipeWire graph alive, then resumes MPV before unmuting. Do not add a blind pause
toggle or apply an audio-only workaround to movies. A future isolated candidate
must use acknowledged MPV IPC, preserve prior pause state, fit the intended
background-music policy and follow finer resume/reset instrumentation.

The next independently bounded candidate executes
`/flash/bird/first-frame-prep.sh` directly from `essway.service` and removes its
writable duplicate. Preparation falls from 16 files/136,973 bytes to 15
files/136,162 bytes: one fewer `cp`, mode operand and destination check, plus
811 fewer source-read and destination-write bytes. This is a post-usable-frame
storage-efficiency candidate; no boot improvement is claimed. Its hardware gate
is boot non-inferiority, read-only brightness evidence, quick launch/return,
emergency restart and shutdown.

Clean source `094be8be0555c4ab51f2968b21f13993b63de96f` is deployed as
`v6.23-flash-firstframe-094be8b`, manifest
`c90a4b6b5b21fd5cedabdb58f0756ec8ceb810adf18c39efae017becde8dff20`,
with all 57 files verified and the accepted supervisor checkpoint as previous.
Release launchers are byte-identical at 597,336/600,600 bytes; profile launchers
remain 658,408/669,992 bytes. The 615,256-byte overlay is five compressed bytes
larger with an unchanged early launcher. The inactive dispatcher release was
archived and independently verified on GitHub before card reclamation.

That RG34XX-SP gate passes. Five valid usable-readiness records are 1229, 1221,
1221, 1229 and 1226 ms after kernel start, a descriptive median of 1226 ms and
non-regression from the accepted supervisor checkpoint. The external stopwatch
remained near 2.7 seconds. The immutable pre-start completed in about 10 ms
without a brightness write. Game, music, reader, movie, retained-frame return,
emergency UI restart and durable shutdown passed without a failed unit or
ownership loss. One shutdown requested before storage readiness exercised the
unchanged bounded final-root wait and completed normally.

The next independently bounded candidate executes the post-autostart diagnostic
as `/flash/bird/capture-boot-state.sh`. It removes only the writable copy, chmod
operand and destination check for that 4,831-byte single-consumer script.
Preparation falls from 15 files/136,162 bytes to 14 files/131,331 bytes, with
4,831 fewer source-read and destination-write bytes. It does not alter the
launcher, provider, input, controls, suspend, audio, task, timer or memory paths,
and cannot improve the first usable frame because the work is already
post-usable. The hardware gate is boot non-inferiority, a fresh complete
post-autostart snapshot, content return and shutdown.

Clean source `9c4250ee50afd37c720a25b7cf109a64bd1a1303` is deployed as
`v6.23-flash-snapshot-9c4250e`, manifest
`4d854a95edbea36e0e23e26ce7fa76c6a559b790ffcf30e0a852c98d0f877b93`,
with all 57 files verified and the accepted first-frame-preparation checkpoint
as previous. Release launchers and their ELF sections remain byte-identical at
597,336/600,600 bytes; profile launchers remain 658,408/669,992 bytes. The
615,256-byte overlay is unchanged in size but changed in content as expected
from the initramfs copy-list subtraction. The inactive supervisor release was
archived and independently verified on GitHub before card reclamation. The
RG34XX-SP gate passes on boot `02d6aba1`: input 1222 ms, usable frame 1229 ms
and storage 3713 ms. The usable result remains inside the prior 1221--1229 ms
range. The complete 47,325-byte/786-line snapshot executed from immutable
`/flash`, reported zero failed units and no pending jobs, and game, music,
movie, PortMaster/network cleanup, suspend/resume, launcher return and durable
shutdown passed.

The next aggressive Stage 4 batch removes the complete remaining immutable
runtime-publication layer. That layer existed to give the first stock-root
integration one conventional writable execution namespace, normalize modes
that FAT could not carry and reject partial destination installation. Every
consumer now names the manifest-verified, session-stable `/flash/bird` release:
PID waiter, controls, power, exit, shutdown, PortMaster preparation/verifier/
manifest, storage, network, suspend, volume and OSD. The only retained copy is
the mutable 260-byte ROCKNIX memory policy.

Preparation falls from 14 files/131,331 bytes to 1 file/260 bytes: 13 fewer
`cp` invocations, 131,071 fewer source-read and destination-write bytes, no
executable chmod transaction and 13 fewer destination checks. It changes no
launcher/render/task/timer behavior and is post-usable, so boot improvement is
not claimed. Each consumer has its own path assertion and host coverage; the
combined hardware gate exercises controls, normal/forced content cleanup,
providers, PortMaster Wi-Fi teardown, suspend, quick/changed shutdown and
rollback.

Clean source `61c51dd798af47330af604e2884553f2e0275e68` is deployed as
`v6.23-flash-toolset-61c51dd`, manifest
`d806243beeb5edbffadc36ac1f83fb9306407935d1084e24d23aa11a2881a8a9`,
with all 57 files verified and the accepted boot-snapshot checkpoint as
previous. Release and profile launchers and their ELF sections are unchanged at
597,336/600,600 and 658,408/669,992 bytes. Fixed controls lose 40 `.rodata`
bytes with unchanged code/data/BSS. The manifest-owned release is 1,869 bytes
smaller, the mount hook is 1,692 bytes smaller and the compressed overlay is
two bytes smaller at 615,254. The inactive first-frame release was archived and
independently verified on GitHub before card reclamation. The broad RG34XX-SP
gate passes. Boot `b116d112` records direct input at 1218 ms, usable frame at
1226 ms and storage readiness at 3723 ms; its pre-storage game selection
remained exactly one pending intent and dispatched at readiness. Both managed
game sessions returned 0, retained-frame restoration matched, shutdown
completed its durable checkpoint and the operator reported the full behavior
matrix passing. The usable time remains within the accepted 1221--1229 ms
range, so this is non-regression rather than a boot improvement.

### Stage 4 requested-diagnostics/content-shell candidate — 2026-08-02

The ordinary post-autostart snapshot existed to capture the broad retained
ROCKNIX state after autostart without delaying the usable frame. Boot
`b116d112` nevertheless showed its 46,984-byte/782-line probe forest starting
at 12.17 s, overlapping the first content contract at 12.10 s and preceding
content services at 13.94 s. The runner and supervisor also retained
conventional external parsers for readable, exact state validation, while
`systemd-run` applied default environment expansion to both content command
boundaries.

The next batch gates the broad snapshot behind persistent request marker
`/storage/bird-data/MUOS/Bird/boot-diagnostics.request`; ordinary boots retain the
narrow readiness, supervisor, content, emergency and shutdown records.
Requested captures publish atomically under their own boot ID before updating
the latest copy. Both `systemd-run` boundaries preserve literal arguments with
`--expand-environment=no`, fixing the observed guard-variable corruption and
protecting provider paths containing `$`.

Built-in parsing changes the following structural counts without changing the
launcher or provider contract:

- external `/proc/uptime` parser sites across runner/supervisor: 39 to 0;
- main runner process-stat parsing: two `cat` and three `awk` sites removed;
- per-launch path validation: `wc`, `tr` and `grep` removed;
- scope metadata validation: three `sed | head` pipelines removed per pass;
- PortMaster owner logging: four `cat` substitutions removed;
- tiny supervisor state/boot/handoff reads: seven external commands removed.

The exact-line replacement rejects truncated, extended and multi-line records.
Provider returns gain accurate post-return classifications for success,
ordinary exits and Linux signal-derived statuses. The proven completed D-Bus
barrier remains separate from audio startup; the unsafe one-transaction variant
was rejected during review rather than sent to hardware.

Clean source `e87e4910459b953b7a1f2ebd19a0efee35fe9e57` is deployed as
`v6.23-content-shell-e87e491`, manifest
`28e2372b36cef01c5f49b584c8896b00ce6969299a30eebb1d40a367d960c70c`,
with the accepted toolset checkpoint as previous. All 57 files, selectors and
the `.complete` digest verified. Launcher/profile pairs remain
597,336/600,600 and 658,408/669,992 bytes with identical sections and profile
metrics. Explicit shell validation grows the manifest-owned release by 2,703
bytes; gzip output falls three bytes to 615,251. The older snapshot was
published and independently verified in the private GitHub archive before card
reclamation.

This candidate changes no framebuffer bytes, launcher syscalls, timer, resident
task, HDMI or Bluetooth path. First-usable timing therefore has no host-side
improvement claim. Its RG34XX-SP gate covers ordinary no-snapshot boot, one
deliberately armed boot-ID snapshot, absence of expansion warnings, immediate
and pre-storage launch, normal and forced return classification, providers,
controls, suspend, shutdown and boot/UI non-inferiority.

The returned gate passed. Boots `d86b5a36` and `ce9da31c` recorded direct input
at 1223/1219 ms and usable readiness at 1229/1222 ms, ordinary snapshot absence,
correct 0/143/137 exit classification, matched recovery and durable shutdown.
This accepts the exact content-shell release as the next candidate's rollback;
1222 ms is a best sample, not a distribution-level boot claim.

### Stage 4 fixed-autostart/journal candidate — 2026-08-02

The generic coordinator existed to preserve the full ROCKNIX product matrix
while the fixed-device closure was being proven. It still scanned platform and
common directories, launched 26 no-op shells, forked approximately 45 timestamp
helpers and depended on 31 per-script bind substitutions. Journald was already
effectively volatile, but empty flush and catalog-update jobs still ran after
the menu.

The fixed coordinator calls the 14 retained duties in exact pinned order,
continues after individual failures, preserves optional custom hooks and
publishes application readiness only through validating `999-export`. Fixed
producers execute from `/flash/bird`; retained stock producers execute from
exact SYSTEM paths. No-op launches and autostart binds are removed. Journald
remains available under an explicit volatile 2 MiB policy; only empty flush and
catalog jobs are masked.

Clean source `133834108ee66a6ad965c44441b6e09690eb8369` is deployed as
`v6.23-fixed-autostart-1338341`, manifest
`2c9553b94c7fffd25dff2f45b764c342c134ca6564ed3f9ae9a040ca0149d198`,
with accepted `v6.23-content-shell-e87e491` as previous. All 57 files verified.
Release/profile final-root and early-initramfs builds pass; launcher binaries,
sections, framebuffer metrics and host dynamic-instruction metrics are
unchanged. The mount hook shrinks 2,719 bytes and the manifest-owned release
shrinks 1,789 bytes; gzip grows seven bytes to 615,258. The expected gain is
post-frame application/content readiness and lower late CPU/I/O. Boot and UI
must remain non-inferior. HDMI, Bluetooth, udev, seatd, logind and warm audio
are unchanged.

The returned gate passed all functions. Boot-scoped usable samples are 1223,
1226, 1228, 1229, 1229 and 1235 ms, versus accepted 1222--1229 ms; this is
non-regression, not a faster first-menu claim. A 1567 ms stale catalog/runtime
record is excluded from the release-scoped evidence. Final-root supervisor
entry improved from 9.65--9.69 s to 9.25--9.53 s.

### Stage 4 fixed-session/idle-wakeup candidate — 2026-08-03

ROCKNIX retained logind for generic lid, power and login-session ownership.
Bird's fixed controls now own lid/power, fake suspend has no login1 consumer,
and content explicitly joins seatd before Sway. The general tmpfiles-clean timer
targets roots which are fresh tmpfs here, and UTMP accounting writes only the
same volatile `/var` without any Bird login session.

Clean source `46dd1704e3453dd3f3fcbb55ea96488716deb840` independently masks
logind, the 15-minute/daily tmpfiles timer and both UTMP one-shots. It preserves
seatd, udev, journald, audio, networking, HDMI and Bluetooth. Release
`v6.23-fixed-session-46dd170`, manifest
`00ba951842afc78f2f27a34f952f790e7cc32eab385db4f902cc0e9c0d7df7cd`,
is deployed with accepted fixed-autostart as previous. All 57 files verify;
release/profile final-root and early-initramfs builds pass. Launcher binaries,
sections, framebuffer metrics and compressed overlay are unchanged. Explicit
assertions add 530 manifest bytes. The target is one fewer resident task, one
fewer scheduled wake source and two fewer volatile accounting jobs. Device PSS,
wakeups and energy remain unclaimed until measured.

The returned RG34XX-SP gate passed all tested functionality. Three boot-scoped
samples reached direct input at 1219, 1221 and 1219 ms and usable readiness at
1222, 1223 and 1222 ms. Those samples accept the exact fixed-session tuple as
rollback and show no first-menu regression; they are not a promoted tail or
energy claim.

### Stage 4 fixed post-frame housekeeping candidate — 2026-08-03

The generic hooks existed because ROCKNIX supports mutable layouts and multiple
devices. In birdOS's fixed steady state, logging nevertheless removed and
recreated the same valid RetroArch log symlink, Pico-8 touched an existing
sentinel, and storage preparation still verified writable logind policy after
logind itself had been physically accepted as absent.

Clean source `91b2f58ed696dfcd547b1ffd52fcb5ceb3ad3602` introduces two small
idempotent fixed hooks and removes only the dead logind-policy publication and
drop-in scan. It preserves failure repair: missing or stale log links are
replaced and missing Pico-8 state is created. Release
`v6.23-fixed-housekeeping-91b2f58`, manifest
`41edbb038356df9cbf1086d451a6731ba3b2bc3c7ad71c9d0754d6b76ee9100f`,
is deployed with physically accepted fixed-session as previous; all 58 files
and `.complete` verify. Release/profile launchers, ELF behavior and framebuffer
metrics are unchanged. The accepted-state structural delta is three fewer
filesystem-mutating applet launches plus one fewer `cmp`, one fewer `stat` and
no logind drop-in scan. Manifest-owned bytes grow 403. This is post-usable work:
boot-log timing should remain non-inferior, while application readiness and
late I/O are the device targets.

The returned gate passed all tested functionality. One preserved clean boot
reached input at 1216 ms and usable readiness at 1220 ms, supporting
first-menu non-regression but not a distribution claim. Suspend stress produced
one incomplete lid-resume event group followed by a new boot sequence; later
cycles passed and no durable kernel cause survived. Because this candidate did
not touch suspend, the event remains an explicitly deferred intermittent issue.

### Stage 4 fixed application profiles candidate — 2026-08-03

Generic controller/setup generation existed for arbitrary hardware and mutable
ROCKNIX installations. The accepted H700 path nevertheless invoked runtime XML
selection, two UUID generators, `control-gen`, 100 per-input `awk` operations
and a persistent controller-profile rewrite. It also rewrote valid sorted
settings, cloud state, cache/UI/panel profile links and the unused
EmulationStation `start.games` condition on every boot.

Clean source `b87dcc2a5c7f7ef0fc8c4737eebf51ac60b2dd87` derives the fixed profile
from the pinned H700 XML under a host test, publishes it transactionally only
when bytes differ, retains `chksysconfig` and malformed-settings repair, and
makes UI/panel/export publication idempotent. Application readiness validates
the controller profile. Release `v6.23-fixed-profiles-b87dcc2`, manifest
`c9dbc12ff1ca1ef98d7436824321db922905dce45afcac50617db18e1ffe0564`,
is deployed with accepted fixed-housekeeping as previous; all 61 files verify.
Both launchers are byte-identical and the release overlay shrinks three bytes;
manifest-owned bytes grow 3,513. The target is earlier application readiness
and fewer persistent writes, with boot/UI required to remain non-inferior.

The returned hardware gate passed the complete tested matrix. Direct input was
available at 1216/1218 ms, usable readiness at 1222/1221 ms and supervisor start
at 9.28/9.26 s. These are non-regression samples, not a distribution-level boot
improvement. Fixed profiles are the accepted rollback for the next candidate.

The next larger-but-separable Stage 4 batch replaces generic performance,
overclock, turbo and rumble wrappers with fixed RG34XX-SP policy scripts. This
subtracts discovery and profile loading only: adjustable 1--4/all CPU cores,
captured CPU/GPU governors, the bounded 648 MHz H700 GPU option, CPU turbo and
the built-in PWM vibrator remain product features. Independent host fault
injection and rollback boundaries are required for each policy. HDMI,
Bluetooth and audio are unchanged.

Clean public source `01e8119ac9953f87442f1627bfd2032485cf9aa5` is deployed as
`v6.23-fixed-performance-01e8119`, manifest
`70bfa8c408e1f939c3a678ba506ca65e3a5aebdbf33eaa2e5ca370ae2734cc6a`,
with accepted fixed-profiles as rollback. All 65 files verify. The launcher is
byte-identical, `bird-autostart` shrinks 172 bytes, explicit policy payloads
total 4,544 bytes, manifest-owned bytes grow 5,239 and the compressed release
overlay shrinks four bytes. The full 30-executable host matrix and the catalog,
provider and Stage-0 Python checks pass. This remains post-usable work: device
boot/UI must be non-inferior, while CPU/core, GPU/overclock, turbo and rumble
behavior require the physical gate. Production remains no-serial and the
diagnostic entry retains serial.

The returned RG34XX-SP gate passed every tested function. One preserved boot
recorded launcher start at 1218 ms, input at 1219 ms and usable readiness at
1222 ms, accepting fixed-performance as the next rollback without claiming a
faster distribution.

The observed `12 Angry Men` file starts AAC 125.125 ms before its H.264 stream.
No Bird/MPV audio-delay option is active. MPV's reported A/V clock stayed close
to zero but the seek-heavy 1200x720 session dropped video frames, so no global
sync correction is authorized from this single-file result.

The next separable Stage 4 batch moves seatd from graphical-boot residency to
an explicit Sway/content lease and stops udevd after coldplug while retaining
its control/kernel activation sockets. Seatd startup must not regress content
interaction; udev must reactivate on a later event. Each manager has an
independent host-test and rollback boundary. Menu boot code, providers, HDMI,
Bluetooth and the kernel are unchanged.

Clean public source `d2e064928727a0580f4c07085d2b8eb46be0a4ee`, release
`v6.23-fixed-managers-d2e0649` and manifest
`0c13e8d8a35042b3853b8debf1f1be05e78df4e7682e3a48cfeca53cf6a09463`
are deployed with accepted fixed-performance as rollback. All 67 files verify;
both launcher modes compile and the release launcher/615,254-byte overlay are
unchanged. Manifest-owned bytes grow 2,316. The target is up to two fewer
menu-idle managers, but PSS, wakeups, energy and content-start non-inferiority
require the RG34XX-SP gate. Production remains no-serial; diagnostics retain
serial.

The fixed-manager hardware cycle passed functionality and kept one recorded
boot at 1220 ms launcher/input and 1223 ms usable readiness, non-inferior to the
1218/1219/1222 ms fixed-performance reference. On-demand seatd does not pass
the lexicographic content-interaction gate: stable session-to-Sway-ready median
rose from 470 ms to 490 ms. Session-to-provider median rose from about 630 ms
to 710 ms for the combined manager candidate, so that larger delta is not yet
assigned to either component. Restore warm seatd and retain only udev-idle as
the next A/B. The roughly 1,556 KiB observed seatd RSS is accepted rather than
trading about 20 ms of first-content readiness for a lower-priority memory
saving. Production remains no-serial; diagnostic and fallback entries retain
serial.

The isolated implementation is public source
`7d74bf668e3a38a9ae1cd1ceb15d81babf191592`, release
`v6.23-udev-isolation-7d74bf6`, manifest
`c5fbebc38faa9a469d5c6363dc47811ef0983e973e30908648c09872b8fdbe6f`.
All 66 files verify; both launcher modes compile, the release launcher is
byte-identical and manifest-owned bytes shrink 1,459 from fixed-managers.
Fixed-managers remains the functional on-card rollback and fixed-performance is
sealed in the private GitHub archive. The next device cycle attributes udev
alone: verify hotplug reactivation and compare Sway/provider timing while boot
must remain inside the accepted range.

The returned isolated cycle recorded 1215/1216/1219 ms for launcher, input and
usable readiness, a fast single sample without a distribution claim. Warm
seatd restored stable session-to-Sway-ready median to 470 ms. The total
session-to-provider boundary remained 690--730 ms instead of roughly 630 ms,
and the extra 60--70 ms is in the services interval where Sway/providers
reactivate udevd. Reject udev-idle under the lexicographic interaction gate and
restore fixed-autostart v2. Stage 4 manager closure therefore retains warm
seatd, udevd, PipeWire and bounded volatile journald; logind remains removed
and networking remains PortMaster-only. HDMI and Bluetooth remain unchanged
until their explicit product decision. After the warm-manager restoration
passes physically, proceed to Stage 5 measurement and one attributable idle-
cost candidate at a time.

The warm-manager restoration is clean source
`72d7fe6058dcd21d8c95545871c0acffc3d3dce6`, release
`v6.23-warm-managers-72d7fe6`, manifest
`8b81f34ab5f84e4c1faafee2ee13357de08a26af704f2a8a26e6ac8107f1b545`.
All 65 files verify and both launcher variants are byte-identical to the prior
candidate. Manifest-owned bytes shrink 875 and the compressed overlay remains
615,256 bytes. Udev-isolation is the on-card rollback; fixed-managers is sealed
in the private GitHub archive. This cycle is the Stage 4 closure gate before
Stage 5 measurement, not a new boot-speed claim.

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

The first Stage 5 infrastructure candidate extends only the explicitly armed
post-autostart diagnostic. `capture-stage5-state.sh` emits a versioned labelled
raw snapshot of scheduler totals, per-process PSS/USS, wakeup sources, IRQs,
softirqs, CPU-idle counters and available battery counters. It has no ordinary-
boot caller and introduces no periodic sampling timer. Two labelled snapshots
may be differenced inside a controlled state block, but the sampler's own work
means those counters remain structural evidence rather than calibrated energy.
Battery promotion still requires an inline shunt or battery-path measurement.

Clean source `3ce316d17574e8487ab846975c404f82f3366e56`, release
`v6.23-stage5-metrics-3ce316d`, manifest
`aba835ad6dd467ff553df81ec64db6542ea4f13e87903fe3268e89bfe3083289`
is deployed with warm-managers as the accepted on-card rollback. All 66 files
verify and both launcher modes are byte-identical. The sampler adds 3,036
manifest-owned bytes and no ordinary task, timer, syscall or wakeup because the
request marker is unarmed. Production remains no-serial and diagnostic/fallback
entries retain serial.

The request-only sampler passed its broad RG34XX-SP gate with
launcher/input/usable readiness at 1218/1219/1223 ms and unchanged stopwatch
timing. Clean source `2ca82cdf5fd3d173644b756797ae8f0421f4a87d`, release
`v6.23-stage5-idle-2ca82cd`, manifest
`c44f2639aaa714d46ef264d26f3627ed7598699d85c4aaadb7e7abfe88af09c1`
adds a one-shot controlled menu-idle window. It settles five seconds, records
start counters, leaves fifteen seconds untouched, records end counters and
disarms only after atomic log publication. All 66 files verify; launchers are
unchanged, manifest bytes grow 566, and ordinary boots remain sampler-free.

The broad physical gate passed, but the first requested window produced no
sample because the host marker was written to BIRD-DATA `.config` while the
unit checked the separate ROCKNIX `/storage/.config` filesystem. Reject that
measurement as nonexistent. Move both request paths to the already-mounted,
host-visible `/storage/bird-data/MUOS/Bird` authority and assert that exact path
in the builder and unit-ordering tests. This is neutral instrumentation; it
does not authorize a battery, wakeup or memory claim.

Clean source `97dd6ffc55b2c1f86650bf1a7bb95cd10d1ff9e0`, release
`v6.23-stage5-trigger-97dd6ff`, manifest
`505ac5d6674d81f18aff22723117dd2d48fafdffb443d3d961de6229bf2a6af5`
implements the corrected host-visible trigger with stage5-idle as rollback.
All 66 files verify; launchers are unchanged and manifest bytes grow by 31.
The next boot is measurement-only until the one-shot window publishes.

Boot `62fc769f` satisfied the one-shot publication contract and passed the broad
hardware gate. Its 15.04-second screening delta was 0.43 percent aggregate CPU
busy, about 1,469 context switches/s and 1,030 IRQs/s. `arch_timer` contributed
about 486.5/s and `5070000.adc` exactly 300/s. Do not promote from these numbers:
the start sampler's remaining reads occurred inside the interval and PSS/USS
aborted on a disappearing PID. Replace the all-files awk with race-tolerant
per-PID shell reads. Add paired per-process `schedstat`/context-switch counters,
and order the minimal global scheduler timestamp last at start and first at end.
Only a repeated corrected sample may select the next idle-cost candidate.

Clean source `9945f9d4f43013a0f09df7ea51a7a23dc1812b04`, release
`v6.23-stage5-counters-9945f9d`, manifest
`f65def91471288ea1aa7fb310ccfbb07fdc18414bf8d85d692d39fbe2814b704`
implements that correction with stage5-trigger as rollback. All 67 files
verify. The launchers are unchanged; the new counter endpoint and race-tolerant
sampler changes grow the manifest-owned inventory by 3,371 bytes and the
compressed overlay by one byte to 615,258. Start captures structural state
before its global boundary; end captures the global boundary before structural
state. Per-process scheduler and context-switch records permit an attributable
userspace follow-up. Ordinary boots remain sampler-free.

This is a measurement-only physical gate. Leave the first boot untouched for
about 50 seconds and require complete versioned start/end blocks, valid PSS/USS
records and one-shot disarm before selecting an optimization. Production is
still the no-serial entry; serial remains available only in diagnostic and
fallback entries. No timing, wakeup, energy or memory improvement is claimed
before the corrected device sample returns.

The corrected return passed broad hardware behavior. Its 15-second window
measured 0.45 percent aggregate CPU busy and about 1,484 context switches/s.
Launcher and powerstate each used less than 0.5 ms; warm audio and seatd used no
runtime. Udevd used 53.3 ms, but stopping it is already rejected by the higher-
priority content-launch gate. The remaining dominant work is kernel worker,
ADC and timer activity. Treat that only as a hypothesis until a longer settled
window repeats it; no energy claim follows from scheduler counters.

Clean source `56d58d404817f90588e61e0faa58beb0e7547f66`, release
`v6.23-stage5-settled-56d58d4`, manifest
`8e0988258c445c4c743f9afe8ae042a86d3bf144aa8a6c78456070641c343ebc`
moves the one-shot window into its own conditioned service. It waits 30 seconds,
measures 60 seconds, publishes atomically and disarms. Broad diagnostics no
longer run in that acquisition. Global CPU/IRQ/softirq counters are adjacent at
both boundaries. All 69 files verify; ordinary boots add no process or timer.
The next physical gate is one untouched two-minute menu-idle boot plus the broad
functional matrix.

Reject `v6.23-stage5-settled-56d58d4`: its newly named service had no existing
unit-file bind target in the immutable stock root. Root preparation stopped, so
only the early launcher remained and all final-root actions were unavailable.
No measurement was acquired. This is a path-contract failure, not a launcher,
input or timing result.

Clean source `d0c6e4edb02753f3f006ad2513976ce25b87cbfa`, release
`v6.23-stage5-slot-d0c6e4e`, manifest
`bcf8e4575878ba81f8ffd854037436e2876a859148f959d167fe1c1981c8df95`
reuses the proven stock report-statistics service slot and dispatches the broad
or Stage 5 request there. Host coverage now proves every unit bind target exists
in the pinned root. Keep measurement unarmed until the complete recovery gate
passes; stage5-counters is the known-good rollback.

The repaired slot passed physically at 1223/1224/1226 ms launcher/input/usable
readiness. Pending launch, all tested content, controls, suspend, emergency
recovery and shutdown passed. Re-arm only the standalone 30-second-settle,
60-second menu-idle window on the same release; no rebuild is needed.

The clean short-label menu-idle window passed on boot `71d6d1b1` after the
30-second settle. Over 60 seconds it measured 0.289 percent aggregate CPU busy,
1,454.5 context switches/s and 949.9 interrupts/s. Launcher and all retained
resident managers except `bird-powerstate` recorded zero runtime; powerstate
used 0.868 ms and eight slices. ADC and architecture-timer rates were 300.1/s
and 464.2/s, with kernel workers dominating runtime. Launcher PSS/USS was
1,776/1,772 KiB. Treat the instantaneous 437 mA battery-current field as context,
not energy. Preserve the higher-priority warm-audio and udev decisions; next
measure marquee idle with identical binaries and acquisition boundaries.

The marquee sample passed on boot `cb7daf5b` with unchanged 1217/1218/1226 ms
boot milestones. Scrolling cost the launcher 30.1 ms and 277 slices in 60
seconds, or 0.050 percent of one core and 4.62 slices/s. Aggregate busy moved
from 0.289 to 0.318 percent while the fixed ADC rate remained 300.1/s. Keep the
current marquee behavior. Extend only the explicit one-shot sampler to label
`game-paused`, `audio-playback`, `video-playback` and
`external-power-menu-idle`; ordinary boot remains condition-gated and unchanged.

Clean source `e8cd4ef2b5546bd158454bccaf0db951298a3237`, release
`v6.23-stage5-states-e8cd4ef`, manifest
`9e62d8ffabe2d2091a5b832aca4f53b77e90c1a3cd450c247efc02774c299a18`
is deployed unarmed. All 69 files verify; stage5-slot remains the on-card
rollback. Stage5-counters was sealed in the private GitHub archive before card
reclamation. Launchers are unchanged and the overlay is 615,249 bytes. Require
the broad behavior gate before arming the first paused-game window.

The unarmed hardware gate passed with 1219/1220/1222 ms
launcher/input/usable readiness and broad behavior intact. Keep the binaries
fixed and acquire the paused-game window next.

The RetroArch paused-menu window passed on boot `24facdce`. Its main thread
recorded 53.59 CPU-seconds and the Sway main thread 5.55 CPU-seconds over 60
seconds; aggregate four-core busy was 28.58 percent. Audio-manager main threads
recorded zero runtime. RetroArch PSS/USS was 204,267/194,748 KiB. This
identifies continuous menu presentation as a real paused-state battery
candidate, but changing its cadence must preserve active menu responsiveness.

The ordinary MP3 playback window passed on boot `a91f03d0`. The MPV main thread
recorded 1.95 CPU-seconds over 60 seconds, while the retained PipeWire,
PulseAudio and WirePlumber main threads recorded none and held 18,682 KiB PSS.
Aggregate four-core busy was 3.40 percent. Treat the warm audio stack as a measured
memory/residency candidate only after provider compatibility and launch latency
are compared.

The ordinary video window passed on boot `35f2c9f5`, with unchanged 1226 ms
usable readiness. Aggregate four-core busy was 63.32 percent, equivalent to 2.53
cores, and MPV PSS/USS was 120,127/116,508 KiB. The per-process sampler was then
found to represent only each process's main thread. Counter ABI v2 now records
every task/TID outside the global measurement boundary. Repeat representative
content windows with v2 before selecting a content battery candidate.

The ABI-v2 repeat attributed 167.83 CPU-seconds to MPV's complete thread group
over 60 seconds; aggregate load was 2.91 cores. The fixed 1080p H.264 source
fell back from `--hwdec=auto-safe` and used `wlshm`, so hardware decoding remains
unproven. Its session also wrote 320,566 bytes and 5,852 lines, dominated by
terminal progress. First remove that release-mode status stream while retaining
warnings/errors and trace-mode output; measure before considering decoder or
kernel work.

The quiet-MPV paired screening window passed on boot `0f8278ee`. The identical
movie log fell 99.58 percent, from 320,566 to 1,349 bytes. MPV thread-group
runtime fell from 167.83 to 130.28 CPU-seconds and aggregate load from 2.91 to
2.28 equivalent cores, with no warning/error or behavior failure. Usable
readiness moved only from 1226 to 1229 ms on the byte-identical launcher. Keep
this as strong screening evidence rather than a calibrated energy claim, and
complete the external-power idle matrix next.

The external-power idle window passed on boot `e353f4cd`. USB/charging state
remained true, all retained userspace managers recorded zero runtime, aggregate
busy was 0.302 percent and the capacity timer was absent. Usable readiness was
1222 ms on unchanged binaries. This closes the structural external-power row.

Post-logind shutdown logs consistently show the high-level `systemctl poweroff`
verb failing through the masked logind interface. Bird now submits
`poweroff.target`/`reboot.target` directly with the same bounded, non-forced
systemd client. Physically verify ordered shutdown and reboot before accepting
this interaction/reliability candidate.

The release `v6.23-stage5-shutdown-d221dfd` physical gate passed reboot, quick
shutdown and post-content shutdown. The quick path acknowledged dispatch in
about 140 ms; the post-content path entered the target before the client could
write its final record. Ordered config checkpoints completed, no logind failure
returned and usable readiness remained 1221 ms. That checkpoint began Stage 6
with a complete active `/run/muos` namespace inventory before the atomic
migration described below.

## Stage 6 — Canonical namespace and hermetic image

Atomically migrate `/run/muos` to `/run/bird`, legacy state to Bird state,
catalog paths to `/storage/roms`, and normalized BIOS/Ports/media/persistence
paths. Supply one migration tool, rollback, interruption recovery and mixed-
state rejection; do not perform piecemeal compatibility removal.

The accepted namespace-v1 transaction boundary is recorded in
`kernel/rocknix/canonical-namespace-v1.tsv`. The old layout existed because
Bird initially overlaid the retained ROCKNIX/muOS card and needed the accepted
fallback to read its original paths. Namespace v1 creates a fresh active
`/storage/bird-data/Bird` tree rather than copying the 985 MB historical
`MUOS/Bird` tree. It copies and seals only favorites/recent state and the BIOS
library, retains every legacy fallback byte, and can resume after interruption
between the Bird-state and BIOS same-volume publication renames. Runtime
activation remained one separately promotable candidate until the transaction,
provider repair and full RG34XX-SP behavior gate passed.

`/storage/bird-data/MUOS/runtime` remains an explicit pinned external boot
input until the hermetic-image boundary; it is not relabelled as canonical
Bird state. The active catalog roots become `/storage/roms` and
`/storage/media`, Ports remain under `/storage/roms/ports`, and the runtime
namespace converges on `/run/bird`. A populated canonical destination without
a matching transaction state is mixed state and must fail closed.

The accepted namespace-v1 activation removes active `/run/muos` use,
emits catalog and request paths directly under `/storage/roms` and
`/storage/media`, stores mutable Bird state under
`/storage/bird-data/Bird`, publishes media as one fixed bind and removes the
nested legacy BIOS bind. The launcher retains `/storage` itself at the
root-ready edge, so the same PID can cross final-root handoff and reach both
canonical libraries without a path translation. Deployment and the boot hook
reject an absent or mixed migration marker. This is correctness/subtraction
infrastructure, not a claimed hardware latency or energy improvement.

The first physical screen accepted canonical mounts, direct content browsing,
Ports, media, books, PortMaster, networking and fresh favorites persistence,
but rejected the activation candidate because every emulator provider returned
immediately. Device logs showed readable `/storage/roms` requests and no
`runemu.sh` start. The remaining fixed tuple map was case-sensitively matching
the retired `*/ROMS/*` namespace. The bounded repair changes that in-process
map to exact `/storage/roms/*` paths and host-tests every supported provider;
it adds no boot, idle, mount or filesystem work. Historical favorites recovery
is waived by product decision while new canonical favorites remain required to
persist. The exact-path repair then passed RetroArch, Flycast, PPSSPP, DraStic,
OpenBOR, Ports, media, books, PortMaster, networking, persistence and the broad
hardware matrix in immutable release `v6.23-20260808-214626`, source
`af83ca945815676d6dabc030ad568c1e5fbb62d2`. Namespace v1 is accepted. This
functional gate makes no new boot-time or energy claim.

Stage 6 is therefore split cleanly: the canonical namespace and its provider
repair are accepted, while the hermetic complete image remains pending. p1 stays
at 128 MiB. Its one canonical-base plus mutable-development-slot policy is a
deployment lifecycle decision, not the deterministic-image build and not a
Stage 6 performance result.

The first post-namespace `dev-current` storage fast path passed the broad
RG34XX-SP behavior gate. It removes the accepted-state ROM remount and three
diagnostic children while retaining the complete wrong-layer and noexec repair
path. One observed boot recorded input at 1217 ms, usable frame at 1229 ms and
storage readiness at 3703 ms; treat those as descriptive, not a promoted
latency distribution. The next independent storage refinement removed the
remaining accepted-state directory-creation process and second mount-table
scan, then passed the broad behavior gate. Its returned boot logged input at
1219 ms, usable frame at 1239 ms and storage at 3744 ms, with a sub-three-second
stopwatch result; those remain descriptive samples. The following candidate
removed nine unchanged fixed-platform comparison/timing children and four
fixed-Sway children using shell reads, while retaining all volatile contract
publication and mismatch repair. It is included in the later accepted
`v6.23-20260810-080340` broad hardware gate; current logs show fixed-platform
9.10--9.11 seconds and fixed-Sway at 10.99 seconds.

The accepted bounded application-readiness candidate changed only `999-export`.
That final validator previously launched twenty-one avoidable accepted-boot helper
processes: fixed-profile `cmp` calls, repeated `wc`/`grep` checks, one extra
`readlink`, `cut`, and unconditional ready-file/directory setup. Strict shell
utilities were originally used because they made the last trust boundary
simple to audit and diagnose while its independent producer contracts were
still evolving; that correctness-first choice preceded the now-fixed contract.
Strict shell
reads now compare the same newline-terminated producer and persistent files,
reject truncated or trailing data, and preserve all repair, symlink, atomic
marker and fail-closed behavior. The normal fresh-boot path retains only the
necessary `readlink`, marker `chmod`, and atomic `mv`. This runs after the
honest usable menu and targets queued-launch/application readiness only. Its
combined broad gate passed games, media, PortMaster and shutdown. Boot
`25e66c8c` recorded the visible input-ready menu at 1222 ms and storage at
3405 ms, with the stopwatch still below three seconds.

Its first device gate found a separate PortMaster failure: the provider's
generic frontend assumes `/tmp/battery.percent` or the power-supply capacity
attribute is synchronously readable, while the Bird-native power replacement
had not retained the former cache contract. Two AXP717 capacity reads returned
`ETIMEDOUT`, producing an uncaught provider exception and then a launcher
`--` display. The focused repair publishes Bird's already acquired last-valid
capacity before PortMaster starts and makes content return prefer that cache;
direct cold-boot and power-event reads remain authoritative when available.
Provider bytes remain immutable. Two device launches logged the published 51%
cache, no timeout traceback, successful Bird return and the retained 51%
display.

Real workflow use also showed Port software writing nested save/config files; development
catalog fingerprints now ignore those generator-invisible runtime files so
they do not rebuild the launcher or early initramfs.

Build the complete image with a digest-pinned container or immutable toolchain,
fixed partition/filesystem identities, deterministic mkfs seeds/options,
timestamps, owners, modes, ordering and sparse handling. Require two clean
builds in separate output roots and a separate-host reproduction where
feasible, yielding byte-identical output or a formally defined excluded-region
list. Include a verified host restore/reimage procedure; an on-card A/B selector
is not an acceptance requirement.

The first hermetic boundary is now proven without changing the device image.
`build-stock-root-hermetic-system.sh --parity` uses a digest-pinned arm64 Debian
base, a dated immutable package snapshot and byte-pinned SquashFS/Python tools.
It extracts the shipping SYSTEM twice in independent containers, records every
node's type, mode, uid/gid, timestamp, content, link target, hardlink topology
and xattrs, repacks with fixed zstd/block/time options, and requires both output
images to be byte-identical and both effective trees to match the shipping
tree. The full 54,510-node gate passed: shipping digest
`6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac`,
deterministic repack digest
`769edbb4522ae031129e5a07712b5529a7ec238735762c2d3d7ddb288e7e37ab`,
and inventory digest
`0714f306f480e40849efa722505d8ae9ddc2921ebf2629130be579629725f86f`.
The repack is 4,583,424 bytes larger, so it is not silently substituted yet.
The bounded physical candidate uses that exact no-content-change repack before
any Bird override is baked into SYSTEM. Deployment stages it under the new
release ID on BIRD-DATA and verifies the manifest-bound size and digest before
selector activation. The active SYSTEM is never overwritten in place. After a
successful activation and verified release rotation, the superseded
release-scoped SYSTEM is removed; the legacy shared muOS SYSTEM is retired only
after the one-time transition commits. Its complete RG34XX-SP behavior and
boot-parity gate remains pending.

The no-content-change physical gate passed in release
`v6.23-20260810-032646`, source
`faca047b626c7cb13bb2414663742514d257c538`, manifest
`a9bfc96764b3e621ef52ec57989ce29ee52715ff8a5bf78525fb333458f7a85d`.

The next mask subtraction passed in release `v6.23-20260810-051204`, source
`bee2f26f6c53798c1e6455d6f2d66c2cd083e58b`, manifest
`b14b7a2552ede731712b0b9dbd1a25ebdc0d46c820a75bedab48cc8a36081a22`.
The broad behavior matrix and sub-three-second stopwatch gate passed. Five
recent logs recorded input-ready 1218--1226 ms and usable-frame 1221--1236 ms;
these remain descriptive parity samples. The image contains the sixteen
accepted masks, with HDMI/Bluetooth-adjacent policy still reversible.

The following independently measurable image subtraction bakes fourteen accepted
fixed service/config files into that SYSTEM and removes their pre-systemd bind
mounts. Two independent builds are byte-identical, the exact combined delta is
sixteen masks plus fourteen files, output digest
`214ae075864fbe848f0fc6c31d4bec68778a111efb2ed1de78366446348d2af4`,
and image size remains 1,211,060,224 bytes. No service policy changes. It passed
the broad physical gate in release `v6.23-20260810-080340`, source
`e039e1dfd84f4196e4c9c7c0ad798cde948ce305`, manifest
`6e59560198455dd68e3124f9aea3bb46bf749a46607d7a57541fd0941b3cc505`.
The stopwatch remained below three seconds; two boots logged input ready at
1219 ms, usable frame at 1225/1232 ms and storage receipt at 3384/3404 ms.

The next bounded post-menu subtraction makes two accepted directories
repair-only and replaces `wc` plus two `grep` namespace readers with strict
shell built-ins. It removes five child processes while preserving missing-state
repair and fail-closed namespace ordering/cardinality checks.
The first development build exposed a sourced-hook descriptor collision: the
new reader closed FD 3, already owned by the upstream init as `SILENT_OUT`, and
therefore prevented final-root preparation after the early menu appeared. No
new persistent boot log survived. Preserving FD 3 with a private FD 9 did not
clear the device failure, so the next correction removes borrowed descriptors
entirely and uses the already proven redirected BusyBox read loop. The host
test still requires FD 3 to remain writable. For this development gate, the
fatal storage boundary also writes directly to p6 and converts a later launcher
exit into a logged three-second forced-poweroff countdown. Only this corrected
build is eligible for the physical gate.

Because the descriptor-free build still hung without reaching its failure
return, the next diagnostic build starts a separate unconditional 30-second
early-initramfs watchdog before storage work. It records countdown plus final
mount/process/kernel evidence directly on p6, syncs and forces poweroff even if
the main init shell is stuck. Temporary storage-stage markers localize the hang.
This watchdog is not a promotion candidate and must be removed after diagnosis.

The watchdog proved the stop occurs earlier than the storage hook: post-flash
failed at 2.19 seconds because it derived the SYSTEM directory from
`dev-current` instead of the recorded immutable production base. The corrected
fast workflow specializes those authorities separately and rejects a dev
release whose post-flash hook does not name its exact base SYSTEM.

The corrected build then passed the broad RG34XX-SP gate. Logs prove that the
selected supervisor was `dev-current`, input became ready at 1220 ms, the
usable frame at 1223 ms and storage at 3467 ms; games, Ports, music, books,
movies, PortMaster, Favorites, suspend and shutdown all completed. The
diagnostic watchdog wrote only its 29- and 28-second ticks before successful
`switch_root` retired the extra initramfs process, which is why no forced
shutdown occurred. That is expected on a healthy boot. The follow-up removed
the unconditional watchdog and eleven temporary storage-stage writes while the
base-SYSTEM correction and five-child post-menu subtraction remained;
the storage-failure-only logged three-second shutdown remains because it adds
no normal-path work and covers the observed failure mode.

The diagnostic-free follow-up also passed the broad hardware gate. Its boot
logged input readiness at 1219 ms, usable-frame readiness at 1225 ms and
storage readiness at 3408 ms. This physically accepts the base-SYSTEM
correction and five-child subtraction without the watchdog or stage writes;
the timings remain descriptive samples rather than a promoted distribution.

## Stage 7 — Fixed-fallback boot-contract subtraction (complete)

The earlier U-Boot A/B and on-card recovery lane is retired by operator choice.
This one-device development workflow returns an unbootable card to the host and
restores or redeploys from verified canonical bytes. It does not spend p1 space
on superseded immutable releases or block userspace, standalone-bootstrap, or
source-kernel experiments on a new bootloader recovery state machine.

The v5.4 fallback kernel, root fallback DTB, fallback selector, automatic
selector mutation, boot-attempt journal, forced retry reboot and supervisor
restart loop are removed together. Manifest verification persists a diagnostic
and stops. Host repair and the private canonical archive are the accepted safety
model.

## Stage 8 — Source-kernel parity lane

Parity builds may begin after Stage 0 in a digest-pinned environment but cannot
redefine the active baseline early. Rebuild the behavior-equivalent unmodified
ROCKNIX kernel/modules/DTB, boot the accepted current userspace, retain exact
config/tool/patch provenance, pass the full hardware/application matrix and
compare boot, interaction, power, size and memory. Promote that source-built
baseline before optimizing the kernel.

The first current-userspace candidate is now host-qualified. The initial
28,239,880-byte packaging omitted the shipping kernel's embedded ROCKNIX
initramfs; Bird's external initramfs is only an overlay, so the device rebooted
before storage or persistent logging. No Bird userspace or replacement module
ran. The corrected gate rejects that incomplete composition. Two isolated
digest-pinned builds produced identical 30,926,856-byte Images containing the
exact 7,474,688-byte official embedded initramfs, complete module
archives, joypad modules, configurations, symbol versions and patch records.
The 49,010-byte RG34XX-SP DTB is byte-identical to shipping. Two further
isolated SYSTEM repacks replaced exactly 99 nodes beneath the Linux 7.0.11
module tree while preserving every other accepted userspace node; both SYSTEM
images are byte-identical and retain the accepted 1,211,060,224-byte size.
This closes the host gate only. The source kernel is not the source-built
baseline until the complete physical matrix and metric comparison pass.

The corrected package subsequently reached the early Bird menu while every
launch and system-control action remained pending. A temporary early-initramfs
watchdog captured the exact stop: release verification still hardcoded the
fourteen-input stock manifest, while source parity intentionally adds a unique
fifteenth `source-kernel-parity.tsv` authority record. The parser now verifies
the complete named stock set and permits only that optional authority; unknown,
missing and duplicate inputs remain fatal. The watchdog was removed after this
evidence was acquired.

The corrected handoff then passed on clean `dev-current` source
`741a997955e3463149b340e56e10d905b2d0ec98`. The broad hardware/application
matrix was functional across games, Ports, media, reader, PortMaster, controls,
suspend and shutdown. Two source-kernel boots recorded input/usable readiness
at 1219/1222 ms and 1230/1232 ms, inside the accepted stock range; storage
anchored at 3475/3430 ms. Retained stock evidence contains the same two DRM
property warnings. Functional and boot screening therefore pass.

The condition-gated 30-second-settled, 60-second short-label menu-idle window
then passed structural parity. D-pad activity at 3.7/4.5 seconds was before the
settle boundary. Source versus accepted stock measured 0.285/0.289 percent
aggregate busy, 1462.6/1454.5 context switches per second, 957.6/949.9 total
interrupts per second, 474.3/464.2 arch-timer interrupts per second and an
identical 300.1 ADC interrupts per second. Launcher, supervisor and warm audio
services accumulated zero runtime; powerstate was 0.876 ms/eight slices versus
0.868 ms/eight. Launcher PSS/USS was 1832/1824 KiB versus 1776/1772 KiB; the
warm audio stack was 20,600 KiB versus 20,898 KiB and seatd was identical at
263 KiB. The instantaneous 418-to-421 mA battery readings are context only, not
calibrated energy. This closes Stage 8 dev-current structural screening. Run
the all-local host gate, build the canonical immutable source-kernel release,
and give that exact release its final physical gate before promotion.

## Stage 9 — Fixed-device kernel optimization

Stage 8 is accepted in immutable release `v6.23-20260811-011242`. The broad
device gate passed and the accepted boot logged input/usable at 1233/1235 ms,
storage at 3452 ms and a sub-three-second stopwatch result. Stage 9 may now
change one attributable fixed-device kernel group at a time.

The kernel owns panel initialization and cold brightness. Test standard DRM,
vblank and backlight readiness before adding a clean read-only driver
attribute. A/B direct cold brightness against the wake strike; keep the strike
only for proven off-to-on/resume transitions and restore exact requested
brightness. Prevent blanking, flashing and generic high brightness. Define
firmware-frame adoption experimentally but leave it disabled until Stage 10
provides the producer.

The upper bi-colour LED is split across boot authorities. Linux's accepted DTB
already declares green/power on and red/status off; the observed red-from-power
interval is selected by U-Boot before Linux executes. Do not add a later Linux
write to disguise it or delay the usable menu. Stage 10 must switch the fixed
U-Boot status GPIO from PI11 red to PI12 green and measure power-key acceptance
to green assertion and power-to-usable together, minimizing both without
lengthening either.

Measure live H700 polling and electrical topology. Use IRQ-backed GPIO input
where possible and minimal polling only where necessary while preserving exact
identity, capabilities, SDL GUID, rumble, reconnect and provider behavior.

The first bounded Stage 9 input candidate links the exact pinned
`rocknix-singleadc-joypad` driver into the Image. This removes the early
initramfs `insmod` and duplicate module payload without changing driver source,
DTB, identity or capabilities. Its reproducible host authority is
`source-kernel-builtin-input.tsv`; promotion still requires input-registration,
usable-menu, reconnect, rumble, suspend/resume and complete provider testing on
the RG34XX-SP. Host construction is byte-reproducible across two kernel builds
and two SYSTEM repacks. The kernel Image remains 30,926,856 bytes; omitting the
duplicate early module reduced the gzip-9 external overlay from the accepted
615,201 bytes to 603,518 bytes (11,683 bytes).

That candidate passed its complete RG34XX-SP behavior gate as immutable release
`v6.23-20260811-030650`. The following button-only experiment in immutable
release `v6.23-20260811-034244` stopped the four-axis ADC sampling while leaving
the advertised ABS bitmap intact. It is rejected: physical testing established
that RG34XX-SP has working left and right analog sticks. Future input work must
preserve `ABS_X`, `ABS_Y`, `ABS_RX`, `ABS_RY`, their live sampling, dead zones,
reconnect behavior and provider mappings.
Corrective release `v6.23-20260811-050010` restored that accepted input path.
Release `v6.23-20260811-071550` then stored one
`gpio_get_value_cansleep()` result per button and used it for both error
handling and state reporting instead of reading the same GPIO twice. All four
stick ADC reads remained intact, the broad hardware gate passed, and stopwatch
timing stayed below three seconds. Release `v6.23-20260811-093148` retained every
sample but emitted one combined axes-and-buttons input frame per polling cycle;
its broad hardware gate passed with normal sub-three-second stopwatch timing.
Release `v6.23-20260811-100937` kept that sampling cadence and published only
when Linux's input core accepted a changed button or axis value. Its broad
hardware gate passed with normal sub-three-second stopwatch timing. Release
`v6.23-20260811-220044` then added the fixed H700 PIO non-sleeping GPIO path
for digital buttons and removed the earlier of two input-device open frames.
Its broad physical gate passed, retaining the exact DTB, all four stick samples,
the 10 ms cadence, one input identity, rumble and reconnect.

Stage 9 release `v6.23-20260811-234132` moves all 17 digital controls, including
L3/R3, to GPIO edge interrupts with independent 5 ms debounce. The four analog
stick axes remain ADC-polled every 10 ms. The complete input, rumble, auxiliary
control and broad behavior gate passed, including an Input Test result of
29/29. Latency and energy remain unmeasured and are not inferred from this
functional acceptance.

The previous cold path reused the proven off-to-on resume strike because Linux
backlight takeover had not yet been shown to illuminate the panel reliably
without it. The final Stage 9 panel candidate instead stores the rounded
ten-percent cold-start level (raw 250 of 2499) before clearing Linux's inherited
backlight blank. It does not replay the 50 ms resume strike, wait or restore on
cold boot; the separate suspend/resume path retains that proven strike and exact
saved-level restoration. Returned RG34XX-SP boots reached a visible Bird menu
without a black interval or flash. The diagnostic pair was descriptively about
50--55 ms earlier than the preceding strike boots; this is physical evidence
for removing that cold delay, not a broader latency distribution. Canonical
release `v6.23-20260814-201218` includes this path and passed its separate broad
RG34XX-SP gate, completing the Stage 9 production-acceptance boundary.

Subtract drivers, modules, probes, buses, protocols and subsystems one
attributable group at a time only after complete consumer closure. Neutral
kernel measurement/readiness infrastructure may promote without regression;
performance changes require a measured boot, interaction, power, wakeup,
memory or size benefit.

## Stage 10 — U-Boot performance and inherited frame

Stage 10 is complete. Environment-nowhere,
direct-extlinux, no-heap-clear, fast-init and in-place handoff are physically
accepted, and canonical release `v6.23-20260814-201218` satisfies the clean
full-release prerequisite. The raw-kernel bootstage measurement and paired LZ4
host preparation are complete, and the corrected uninstrumented LZ4 runtime
has passed its broad development-device gate. The remaining large boundaries
are the inherited-frame producer and reuse experiment. The simple-parser,
fixed-read-path and fixed-command-closure successors have passed their
broad hardware gates. Why before: fixed-read-path retained generic U-Boot
commands so its hardware result attributed only storage closure. Why change:
the repeat-identical fixed-command-closure candidate retains the complete
`sysboot`/extlinux/`booti` boot chain and removes 66,056 more combined bytes.
The exact authority, corruption, installer transaction and workflow gates
passed before installation, and the returned device passed the broad functional
screen. Three completed cold boots recorded usable-frame, input-ready and
storage-ready medians of 1185, 1174 and 3427 ms. Those results and the unchanged
stopwatch timing do not establish a speed improvement over fixed-read-path;
they accept the smaller fixed command closure without making a latency claim.
The detailed diagnostic logs remained usable.

The inherited-frame consumer remains guarded but cannot yet be activated by
the accepted producer. Why before: proprietary firmware owned an early
boot-resource splash, making exact frame reuse appear to be an asset/contract
change. Why change direction: the accepted mainline H700 U-Boot is built with
video disabled, its pinned Sunxi video choices exclude the H616/H700
generation, and the current card has no proprietary boot-resource partition.
A producer now means porting the H700 display engine, TCON, fixed RGB panel,
GPIO/PWM sequencing and Linux handoff. Stage 10 defers that high-risk driver
project and retains the verified fallback. The bounded successor instead packs
only the nine fixed wallpaper regions the launcher reads, removing 529,552 raw
bytes without changing framebuffer traffic or the visual contract. Immutable
candidate `v6.23-20260830-201239` is built and installed from clean commit
`56ae92d94243f5759b7dee0a7d2d433701815bf7`; its manifest is
`43beaab6860e9eea76fe534c113e8f47b8fd03ffde9b6f3eb1eded863ee83734`.
The raw/compressed early overlays fell from 2,039,296/604,882 bytes to
1,509,888/588,520 bytes. Its returned broad RG34XX-SP gate passed. Five
usable-frame samples had a 1188 ms median and input-ready had a 1176 ms median,
neither faster than the preceding 1185/1174 ms medians. Two completed storage
samples had a 3359.5 ms midpoint, nominally 67.5 ms below the preceding 3427 ms
median but insufficient to claim a gain. U-Boot is outside Linux
`CLOCK_BOOTTIME`, so its improvements are intentionally invisible to these
logged frame/storage values. The slightly faster stopwatch impression remains
compatible with, but does not prove, a pre-kernel improvement.

The first Stage 10 candidate has passed its complete non-deploying host gate.
The four-pass build produced two byte-identical baselines that each reproduce
the 621,049-byte shipping DDR4 U-Boot at SHA-256
`42c01f4524b45cba7c239cd940fc4e71eed7545901da201f27fed2193b7fdf45`
and two byte-identical constant-green candidates at SHA-256
`080ae5fde3476addb5aa74f03a021aa4fbaa5deccb0964227c0fc91fe657b584`.
The candidate changes exactly one byte at combined-artifact offset 488836 for
the build-config selection from GPIO 267/PI11 red to GPIO 268/PI12 green while
keeping the same assertion point and constant-on policy. The reviewed U-Boot
payload SHA-256 is
`c60605e6a533404d5eb66549e4905152c42ff937de8cc922a1b8b8b7eac3ff56`;
the exact resulting 16 MiB prefix SHA-256 is
`fe363dd09e40ccef994912c01ed1c77d3285485299a40ce7ae7fc74431b5a998`.
Independent artifact, installer and exact-baseline-recovery host audits passed.
The first real write then exposed an unmodeled macOS constraint: the 621,049-byte
logical artifact did not fill its final raw-device sector, so `gdd` returned
`EINVAL`, and Disk Arbitration remounted the card before cleanup could reopen
it. No boot was attempted. The installer now writes a 621,056-byte aligned
sector span whose final seven bytes come unchanged from the verified prefix,
forces a fresh whole-disk unmount before recovery, and models rejection of the
old write in its host gate. The explicit baseline repair preceded the corrected
green install. The returned card passed broad functionality but did not pass
the intended constant-green gate: it still showed the same initial red interval
before green. The first config changes only the full-U-Boot green GPIO and does
not initialize a red-off entry or run the LED framework in SPL. A successor
source gate passes for U-Boot's existing SPL hook with PI12/green on and
PI11/red off in the same status-LED initialization. It remains unpromoted and
undeployed with the green-at-power work deferred. One non-deploying feasibility
build keeps the fixed 40,960-byte SPL region valid with 3,685 trailing zero
bytes; it consumes 392 bytes of former
SPL reserve and grows full U-Boot by 24 bytes. A second isolated build is
byte-identical at combined SHA-256
`ac55433c1b39363b6665d3de0bb949f25ee067a7863ac149fc07b885e14b5c82`
and SPL SHA-256
`c9e0982fb0aaced7ef658bd8c89a822009e9e3b1bb570720ba8ac4e6e125c8a0`.
The repeat builds, exact component/difference authority and separately pinned
aligned 16 MiB prefix now pass. The bounded installer has a distinct
`--install-early-green` action, writes the successor as 1,214 complete sectors,
and restores either the exact prior green prefix or the independently retained
shipping prefix on failure. This is the earliest supported software owner in
the inspectable mainline chain. StockOS and muOS nevertheless establish green
earlier through an unavailable boot-chain implementation. After more than
twelve hours without reproducing it, green-at-power work is deferred unless
another boot task reveals the missing owner.

The launcher can turn the green LED off once the interactive
first-frame contract has been published, using one best-effort write in its
existing post-marker startup work; it is deferred with green-start work.
Why the environment behavior existed before: generic U-Boot supports a
persistent environment so users and board integrations can change boot
settings without rebuilding it. birdOS deliberately owns one immutable boot
policy and the card has no `uboot.env`. The exact Kconfig transform replacing
that always-missing FAT-backed environment with compiled defaults has two
byte-identical builds. The 620,745-byte combined candidate is
`970b5c485b0468e60c894ed39a0fbf786a3633d92e852a1f4005091b40d887e7`;
its deterministic 16 MiB prefix is
`eceb7bcf3f8831b7a7cbb90859ea47bdf67c0cf87650a17977e225c4a43a54f2`.
It is based directly on the physically identified shipping baseline and
contains no LED change.
SPL and control DTB remain exact. MMC, FAT filesystem access, extlinux and the
compiled boot variables remain; only the guaranteed missing `uboot.env`
load/save backend is removed.

The environment subtraction then passed the broad RG34XX-SP functional gate;
the stopwatch remained below three seconds. This accepts the removal of the
unused backend, but does not establish a timing improvement.

Why the next work existed before: upstream U-Boot's generic distro command is
designed to discover bootable partitions and support removable-media and
network targets. birdOS has one fixed card layout and one fixed extlinux path.
The direct-extlinux candidate retains MMC initialization and the shipping
extlinux parser, but executes `mmc dev 0; sysboot mmc 0:1 any ${scriptaddr}
/extlinux/extlinux.conf` directly. Failure stops instead of trying FEL, PXE or
DHCP, matching birdOS's host-repair policy. Two isolated builds are
byte-identical at combined SHA-256
`cd99dd9edaad868e460b256729c2e0f5a20a606a2a33e4015d93c42159da1191`;
the exact resulting 16 MiB prefix SHA-256 is
`f81187878bbe491dabaf1a4f5fda051d4edabbcb476681d1323d73557e3072ff`.
Its installer transaction and no-op host gates pass. The RG34XX-SP then passed
the complete functional matrix at about 2.6 seconds by the user's stopwatch.
Three recent
interactive-frame records were 1189, 1179 and 1176 ms, versus 1189, 1186 and
1185 ms immediately before; that small descriptive shift is not a calibrated
U-Boot timing claim. This physically accepts the direct-extlinux boundary.

Why the previous implementation existed: generic sunxi U-Boot reserves a
64.125 MiB malloc arena and initializes all of it to zero so ordinary
`malloc()` callers encounter clean memory across many boards and use cases. The
accepted config executes that 67,239,936-byte write before MMC and kernel
loading. U-Boot's own Kconfig calls
the operation slow and recommends disabling it for arenas larger than a few
MiB. The accepted intermediate boundary removes only full-U-Boot heap clearing,
retains the same arena size and explicitly preserves SPL's existing policy. Two
isolated builds are byte-identical at 620,745 bytes and SHA-256
`38ace6d738fed727fdd2274b510c3e18105b2c71f7b1d908dece357e31d1365c`;
their exact 16 MiB prefix SHA-256 is
`ea1afbf3186945e562aa0844d7ab6d1b027be9cfafe225a0e4c0745ffc50b305`.
The 579,785-byte FIT is
`991d29c7201afceea7e18e5bc03707c8308306ba2cf67f16a1d48f95c2d14a7b`,
and its 500,936-byte full-U-Boot payload is
`d1ad2598283dac0913c5d49c5d3ccec7b21f9b14226038561c7334afff48fba4`.
The resolved config changes only `CONFIG_SYS_MALLOC_CLEAR_ON_INIT`, while SPL,
TF-A, the control DTB, heap size, environment and boot command remain exact.
The authority is reviewed; independent reconstruction and the bounded
install/no-op/failure-restore host gate pass. Its physical installation
completed the exact full-prefix readback and supplied the required predecessor
for the successful fast-init transaction. The returned broad behavior gate
passed. This physically accepts the removed 67,239,936-byte write as an
intermediate transaction boundary, not as a separately measured timing gain.

The launcher-off handoff is authorized only when creation of the exact
first-frame readiness marker succeeds; a publication failure deliberately
leaves green on. The host installer also passes an explicit exact-baseline
restore gate that repairs an interrupted partial bootloader write without
adding any on-card fallback or recovery state. The independently retained
intermediate boundary removes the full-U-Boot heap clear. Why the removed
generic behavior existed before: U-Boot keeps an autoboot interruption window,
filesystem and boot-target discovery, an explicit MMC-selection command,
network targets and boot-standard support for interactive and variable-media
systems. birdOS has
one fixed FAT partition and no boot-time network or bootflow search. The
reviewed fast-init boundary therefore selects FAT directly, removes the
unneeded `mmc dev` wrapper and UART abort check, sets the boot delay to `-2`,
and builds neither the network stack nor bootstd. The architecture-selected
preboot facility remains with an empty compiled hook. Its exact resolved GCC
config delta is 42 symbols. Two builds reproduce the same 556,977-byte combined
artifact at SHA-256
`4afc68bd2a7fdaacc212683a1a268380c07775d18cf12025285778221e986081`;
the 516,017-byte FIT is
`d827586fefa78cc12dba89b3912f1a428b5218415c62dc8308c24a252a0eaea9`,
the 437,168-byte full-U-Boot payload is
`9d557ccc6efb40b4e4f3daeea648f51ae313d6bec9c342d41abf4b8fdefbeb89`,
and the resulting 16 MiB prefix is
`172ca1a500603ea371a17bee1b6a7632ba17e4991a400f57cee0b2231e75bdeb`.
This is 63,768 bytes (10.27 percent) smaller than the reviewed no-heap-clear
boundary; SPL, TF-A and the control DTB remain byte-identical. The retained
duplicate-build and component authorities passed the combined physical gate:
the no-heap-clear transaction installed and verified first, then the fast-init
installer reread and matched its complete pinned 16 MiB prefix before remount.
Three subsequent boots reached the direct launcher and the returned broad
functional matrix passed. A fresh current raw reread is unavailable because the
host sudo lease expired; the acceptance boundary is the install-time exact
verification plus those post-install boots. Fast-init became the physically
accepted predecessor for the next boundary. The user did not report a new
stopwatch result for this return, so the size reduction and removed work are not
claimed as a hardware timing improvement. Green-at-power work remains deferred unless
another boot task reveals its earlier owner.

Why the previous behavior existed: generic U-Boot relocates the initramfs and
device tree so variable boards, load addresses and payload sizes receive new
safely allocated handoff ranges. Why change it: birdOS has one fixed RG34XX-SP
layout. The accepted extlinux path already loads the exact 603,487-byte
initramfs at `0x4ff00000` and the exact 49,010-byte DTB at `0x4fa00000`; its 12,288-byte
padding and all later fixed buffers are proven non-overlapping. The reviewed,
physically accepted in-place-handoff boundary adds the exact board
environment values `initrd_high=ffffffffffffffff` and
`fdt_high=ffffffffffffffff`, preserving LMB reservation while avoiding the
second moves. The only resolved config delta from accepted fast-init is
`CONFIG_ENV_SOURCE_FILE=""` to `"bird-rg34xx-sp-handoff"`. The transformed
defconfig is
`0254301f87e2222f04c67a34e5351bce16ebaac712bd96cc096f76027d9ded13`;
the 55-byte environment is
`335b569a6f63acab13d20bccb843b5d6d979b7141ede3a5a5a2647b59ec132ce`.
Two isolated builds reproduce the 556,977-byte combined artifact at
`7423ffeda197645b6b774c83fcebcbefef47bd7eaa6f087c71ab339750af4e91`,
516,017-byte FIT at
`c11d9b780c4c78940590ee17965550aa3eca7e7d0d04fdb37b4c9869b2418bf4`,
437,168-byte full U-Boot at
`cff9a9ca1bd7db20a3a136fec655d7120481afa8a837930266a9962ab2dec578`,
47,408-byte resolved config at
`77f2bee66adc542e3475594c4727933607f76c2adf72e6428e0e57cadb6de762`
and exact 16 MiB prefix at
`c168640be0e3b0fc3899853d71aabc0c3b3e65fdf230b19782ff40ff19f001dd`.
The SPL (`0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c`),
BL31 (`431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673`)
and control DTB
(`ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589`)
are byte-identical to fast-init. The removed 603,487-byte initramfs move plus
61,298-byte padded-DTB move models 664,785 fewer copied bytes; this is not a
hardware timing claim. Its bounded installer completed the exact post-write
authority check, and two returned RG34XX-SP hardware cycles passed the broad
functional matrix. Canonical release `v6.23-20260814-201218`, built from clean
commit `5373c644b9c91ac21a17e145375747a8196a3337` with manifest digest
`904c8da42a6ec84ccf4b291205999c3b0e25900f4bec7bb3f9e0cfefb29164dd`,
then passed the complete returned behavior gate. Its four usable-frame records
are 1174, 1175, 1176 and 1177 ms, a midpoint median reported as about 1176 ms;
input-ready median is 1170 ms. The three completed asynchronous storage records
have a 3514 ms median, with one short boot shutting down before storage became
ready; that three-sample result is noise-scale. The 2.8--2.9-second stopwatch
result likewise establishes no measurable improvement. In-place handoff is the
active physically accepted
U-Boot boundary.

After userspace and kernel stability, split PMIC, SPL/DRAM, TF-A, U-Boot,
storage, decompression and kernel-entry time. Hardcode the board, target and
paths; remove unused menus, discovery, USB/network paths, protocols and probes;
then optimize fixed loading and handoff. Add frame production last and enable
kernel adoption only in the joint experiment. Promote only when no blank,
clear, flash or input delay occurs and total power-to-usable or continuity
improves without higher-priority regression.

Why before: the retained ROCKNIX fake-suspend
provider owns the accepted audio, input, governor, core-parking and LED
transaction; Bird restores the fixed panel, while the `O_DSYNC` rare-edge trace
keeps the blocking input loop free of periodic work. Why change: no suspend
behavior is changed now because canonical boot `96df160e` recorded suspend at
311.471 seconds and resume dispatch at 312.632 seconds but no resume-complete,
timeout, orderly shutdown,
panic, Oops, pstore or reset cause. The next canonical boot completed three
power/lid cycles with wake-edge-to-complete times of 726--768 ms. The
intermittent reset is nonblocking for Stage 10 and remains deferred for focused
provider/PMIC and reset-surviving diagnostics.

Why the previous measurement boundary existed: source inspection treated
generic bootm's `bootm_load_os` mark as the kernel-load boundary. The accepted
device trace proved that `booti` performs `BOOTM_STATE_LOADOS` itself and never
emits that mark. Why change it: the capture contract now requires the actually
emitted `boot_jump_linux` mark. Together with `bootm_start`, it bounds booti
setup/decompression and the remaining handoff without custom timing. The
measurement boundary preserves the
accepted in-place environment and enables bootstage records in the handoff DT
without serial reporting, an interactive command or SPL timing. Its post-frame
capture accepts evidence only when `board_init_f`, `board_init_r`, `main_loop`,
`bootm_start`, `boot_jump_linux` and `start_kernel` each occur once as strictly
increasing marks; missing, duplicate, non-mark and out-of-order records fail
closed. It never enters first-frame work, and `start_kernel` is handoff-start
before U-Boot's final cleanup. Why the first two-pass builder stopped:
`SPL_BOOTSTAGE=n` disabled recording, but raw `CONFIG_BOOTSTAGE` still enlarged
SPL global data and shifted `cyclic_list`, changing the generated SPL. Why
change it: the host-reviewed measurement-only artifact packages the exact
accepted 40,960-byte SPL, retains the A/B-identical different generated SPL as
explicitly unused evidence, and changes only full-U-Boot data in the FIT. The
561,073-byte combined image is
`0b22418db35ee591870ccd652d4aaa3d0a50bd216e600f7b8ca0c4052e2e8e83`;
the reconstructed 16 MiB prefix is
`c1dadb6b43782ac25b8be6ea168cbad7c2e435da49207210213be68701f7f94b`.
Both passes are byte-identical; the 4,096-byte host size increase is not a
timing claim. The artifact remains barred as a production successor. Why change
the former no-write boundary: a separately pinned
`temporary-measurement-only` installer accepts only the exact in-place prefix
and canonical `v6.23-20260814-201218`, requires capture to be armed, and has a
direct exact in-place restore. Its sector-tail, forced-unmount and injected
failure-recovery gates pass. Three returned traces preserved the actual emitted
records. Their median phase times were 602,524 us from reset to `board_init_f`,
304,745 us to `board_init_r`, 76,759 us to `main_loop`, 1,419,998 us from
`main_loop` to `bootm_start`, and 224,968 us from `bootm_start` to
`boot_jump_linux`. Seven coarse stopwatch samples had a 2.78-second median and
all behavior passed. This prioritizes the LZ4 functional gate without making
a calibrated total-boot claim. Why the raw Image existed: it is the
physically accepted simplest handoff and avoids both a U-Boot decompression
stage and its temporary output buffer. Why consider changing it: the fixed
kernel becomes a 17,565,707-byte LZ4 frame, 13,361,149 bytes (43.2024 percent)
smaller than the raw Image, so the device can determine whether fewer payload
bytes to load outweigh decompression. The separate host-ready, full-release-only frame
is at
`a7321d2a79b18e81f114aefd9bb7509ba70d5e56b562a345ea5ca66dbf11262a`.
It is not deployable until paired U-Boot authority constrains
`kernel_comp_size` to `0x10c080b`, keeping the damaged-frame expansion guard
below the fixed DTB buffer. These are host byte counts, not a device timing
claim. Two fresh isolated linked U-Boot passes now reproduce a 556,977-byte
diagnostic pair at
`9f3d96da4126a6654187a3cddb9b0c038b251882aee9938e0b258d0bac94f35b`.
The 437,168-byte full-U-Boot payload is
`35cd4f8d50568f7bdae89fe01ce851b80276c4a44c18138de553872456523f9e`;
its config, SPL and control DTB remain exact accepted bytes. Only four bytes in
the compiled `kernel_comp_size` value change, the FIT difference remains inside
`/images/uboot:data`, and the guard ends 19,378,066 bytes before the DTB. The
derived 16 MiB prefix is
`2e6680950a885cef607a9642c0133a8794d7407c7879ccb0fe9c153b6be45f56`.
This is now reviewed production-successor authority. The bounded installer
accepts only exact in-place U-Boot and retains a direct exact restore action.

Why the two authorities remained separate: the uninstrumented linked proof
isolated the four-byte LZ4 bound, while the accepted bootstage artifact retained
the exact timing path. Why change: independently applying the proven
equal-length delta to both reviewed bootstage passes produces one 561,073-byte
paired measurement image at
`d386f00ee8b0db002f5de3206d4af522a33a0f26960efe0561b29e01dbf2a083`.
The full-U-Boot payload is
`57232f25c04da2fb8bac08f4c5f5be6af6d1da069b32e0bb50baaebff4219fe3`;
the exact-prefix result is
`cf13ad801ffc3a2c1b1e65879f72a683cebe29e476c7dfde7d0c136eeb54d2ee`.
Accepted SPL, config and control DT bytes remain exact and FIT scope remains
U-Boot data only. Focused gates and all 79 workflow cases pass. This
instrumented combination remains historical and nondeployable. Next gate:
install the reviewed uninstrumented pair, construct the clean immutable LZ4
release, and run the broad device functional gate.

Decision after the returned trace: retire the measurement branch rather than
perform another formal instrumented A/B. Why before: bootstage was the smallest
way to determine whether fixed loading or later handoff dominated. Why change:
the 1,419,998 us median load interval already identifies the useful target, and
the external stopwatch is reaction-limited. Remove the capture helper from the
next canonical runtime, restore exact uninstrumented in-place U-Boot, and judge
the uninstrumented LZ4 pair by exact host authority plus the complete RG34XX-SP
functional screen. Do not promote bootstage instrumentation into production.

The first immutable uninstrumented LZ4 gate reached the menu but did not acquire
usable storage, leaving launch and orderly shutdown unavailable. No durable
failure evidence survived, so changing storage ordering would be speculative.
Why before: the retained `storage-failed` branch armed shutdown only after the
launcher exited. Why change: reintroduce the proven 30-second initramfs
watchdog placement before the launcher, but make it safe for permanent use by
disarming only on the verified storage-anchor acknowledgement. A timeout now
captures mounts, partitions, readiness, processes, mount-storage evidence,
early-launcher output and dmesg before a synchronized three-second forced
poweroff. Prefer p6 for the per-boot record and fall back to a bounded top-level
BIRD diagnostic when p6 itself is unavailable. Do not infer an LZ4 timing race
until this evidence names the failing boundary.

The watchdog named strict release verification rather than an LZ4 timing race:
the exact valid LZ4 source-kernel provenance was not in the optional-input
allowlist. The corrected verifier admits only that unique authority in addition
to the stock set. Clean `dev-current` source `f22e2b8` then passed release
verification, reached a usable frame at 1.178 seconds, anchored storage at
3.388 seconds, disarmed the watchdog and passed the broad charged-device
functional gate. A later abrupt cutoff had no Bird shutdown/suspend record and
was confirmed as a depleted test device, not a boot regression.

Why the next generic path existed: sunxi implies U-Boot's distro defaults,
which retain the hush shell, editing, completion, tracing and long help for
interactive multi-command systems. Why change: Bird's uninterruptible boot
policy executes one fixed `sysboot` command, and U-Boot's simple parser still
provides its required variable expansion and extlinux handoff. Two isolated
host-only feasibility links are byte-identical while retaining MMC, FAT,
PXE/extlinux parsing, raw initramfs, LZ4 and `booti`; SPL and the control DTB are
byte-identical, and FIT differences remain confined to `/images/uboot:data`.
The formal sparse-policy builder first stopped because disabling those defaults
also removed boot dependencies that the feasibility command had reselected.
Those retained dependencies are now explicit, and two fresh isolated builds
reproduce the exact feasibility bytes. The combined artifact shrinks from
556,977 to 518,369 bytes, saving 38,608 bytes (6.93 percent); full U-Boot shrinks
8.83 percent. A self-verifying production-successor authority and bounded
LZ4-to-parser installer now pass the full host transaction gate, including
predecessor rejection, sector-tail preservation, complete-prefix readback,
failure rollback and exact LZ4 recovery. This is a host size/load result, not a
hardware latency claim. Returned boot `07d80b9c` passed games, PSP, native
Ports, PortMaster, music, books, video, controls 29/29, networking, one complete
suspend/resume and orderly shutdown. Its detailed logs survived, but no
comparable initial usable-frame timestamp did, so no device speed claim is
made.

Why the previous parser boundary existed: it retained generic filesystem and
partition support so the returned hardware gate isolated only the parser
subtraction. Why change: the fixed RG34XX-SP command reads one extlinux file
through FAT on MBR and never invokes filesystem shell commands, EXT, GPT/EFI,
partition UUID or FAT-write paths. The next sparse policy retains exact MMC,
DOS/MBR, FAT-read, sysboot/PXE, raw-initramfs, LZ4 and `booti` dependencies and
removes only that unreachable surface. Two sealed networkless builds are
byte-identical at 478,033 combined bytes and 358,224 full-U-Boot bytes, saving
40,336 bytes against simple-parser (7.78 and 10.12 percent). SPL and control DTB
are exact; FIT scope remains U-Boot data only. The bounded installer accepts
only the reviewed simple-parser prefix, writes 934 complete sectors, preserves
the reviewed 175-byte sector tail, verifies all 16 MiB, rolls back on failure
and provides explicit exact simple-parser recovery. Focused authority tests,
the destructive-path simulator and all 79 workflow cases pass. This is a
host size result rather than a timing claim. The exact installation and
independent raw-prefix reread matched the reviewed identity. The returned broad
screen passed with Input Tester 29/29, complete suspend/resume and orderly
shutdown. Boot `e8129b34` recorded usable frame at 1,182 ms, input readiness at
1,173 ms and storage at 3,355 ms; the user's stopwatch result was about the same
as before. Detailed logs survived without a usability change. This physically
accepts the fixed MBR/FAT read-path boundary without claiming acceleration.

## Candidate report gate

Before editing, inspect and state the active critical path. Acquire and seal a
baseline, add focused tests, compile release/profile final-root and early
launchers where applicable, and run affected launcher, catalog, boot-frame,
storage, supervisor, application, content, persistence, controls, brightness,
PortMaster, deployment and reproducibility tests. Run the retained fixed-
fallback tests when a candidate actually touches that deferred boot contract.

Report syscalls, framebuffer bytes, host dynamic instructions, ELF sections,
binary size, PSS/USS, tasks, wakeups and IRQs separately from RG34XX-SP timing
and calibrated energy. Preserve menu/navigation/paging/actions, Favorites,
asynchronous storage, exactly one pending selection, exact return state,
reconnect, foreground recovery, all providers, networking isolation, charging,
battery, brightness, suspend/resume, shutdown and verified host card recovery.
