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
until Stage 7 passes.

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
`/storage/.config/bird/boot-diagnostics.request`; ordinary boots retain the
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
