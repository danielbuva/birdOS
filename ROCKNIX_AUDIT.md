# ROCKNIX compatibility audit

Bird keeps the exact ROCKNIX 20260701 application provider because its broad
physical compatibility gate passes. Keeping the provider does not mean keeping
every generic boot decision. This audit separates the small menu-critical
closure from the later application-compatibility closure and replaces generic
discovery only after its consumers are proven.

## Measured boundaries

The last physically accepted v6.14 boot recorded:

| Boundary | Kernel uptime | Meaning |
| --- | ---: | --- |
| Bird pixels visible | 1.340 s | Direct framebuffer menu exists |
| H700 input ready | 1.454 s | Menu is interactive |
| Fixed p6 storage retained | 2.810 s | Cached rows have live files |
| Generic ROCKNIX autostart entered | 8.721 s | Compatibility generation begins |
| Generic ROCKNIX autostart completed | 16.756 s | Full application contract exists |

The first three boundaries are Bird's user experience. The last two explain why
an unusually early game selection can still queue even though the menu itself
is already responsive. Optimizing that later interval improves time-to-content
and background efficiency; it does not need to block or enter the launcher.

## What Bird retains now

- systemd as the current final-root service manager;
- udev for the complete coldplug/rule compatibility pass;
- D-Bus, PipeWire and WirePlumber for applications and audio;
- warm seatd and udevd because on-demand activation measurably entered the
  content path; logind is removed from the fixed one-user closure;
- the H700 platform/device quirks, controller setup, config provisioning,
  performance policy, rumble, audio routing and Sway configuration;
- stock `runemu.sh`, emulator/core selection, standalone wrappers, MPV and
  PortMaster providers.

These are retained compatibility components, not permanent design decisions.
They stay out of the launcher and may run asynchronously whenever their
dependencies permit.

Lifetime decisions use the product's temporal tie-break. During launch, close,
switch and return, minimize synchronous work and defer cleanup after responsive
ownership whenever safe. During menu/content inactivity, eliminate polling and
unjustified residency as quickly as practical. A retained manager must justify
both its measured transition benefit and its measured idle energy; a stopped
manager must not introduce a noticeable common-action delay.

## v6.15 subtraction

The following common-autostart scripts are deterministic no-ops for the fixed
offline RG34XX-SP profile and are bind-replaced by one two-line exit script:

- update-hint handling, root/Samba password setup, Bluetooth, Moonlight and
  Weston UI-mode generation;
- HDMI scan, dual-display discovery, boot Wi-Fi and USB-gadget startup;
- generic fan/headphone/HDMI/battery/input service switching; and
- the generic configured-daemon start/stop loop.

The fixed input and power services are already requested directly by the Bird
target. Network services remain behind Bird's explicit PortMaster request. The
RG34XX-SP's single internal display is published as a constant rather than
running `modetest`.

ROCKNIX's `006-display` and Bird's old post-frame preparation both rewrote the
backlight after the menu appeared. The accepted trace shows the initramfs set
raw 124/2499 (about five percent), then the later preparation wrote 624/2499
(25 percent) at 8.45 seconds. v6.15 removes both late writes. Manual brightness
changes now have one owner and should remain stable.

Shutdown retains systemd's ordered unmount and poweroff. The generic config
checkpoint sourced the complete interactive profile, ran `grep`, and copied a
small unchanged file. Its replacement compares the exact file, copies only on
change, logs the boundary, and Bird submits the poweroff job without blocking
its supervisor.

The power worker's low-battery red-status threshold is now exactly 41 percent.
Charging remains kernel/PMIC-owned and the green LED remains the ordinary
power indicator.

## v6.15 result through the accepted `79b6e3e...` behavior baseline

The operator accepts public commit
`79b6e3e03771f2787622a3e4f6f9d8f129b7281f` as the current source and behavior
baseline. Immutable fallback release `v6.23-20260731-054816` remains separately
identified by its actual older dirty source in its manifest. The audit below is
behavior evidence; it does not rewrite that binary provenance.

The physical gate passed brightness stability and visible shutdown at roughly
1.8--2.0 seconds. The shutdown log places its exact config compare/copy at
40 ms. The memory capture proves `ksm_run=0`, with every KSM sharing counter at
zero. Generic autostart now enters at 8.681 seconds and completes at 12.263
seconds: 3.58 seconds instead of the prior roughly eight-second tail.

Content selections were reported as permanently queued for storage. The final
returned boot itself recorded a successful FIFO, retained storage at 2.888
seconds, the complete p6 mounts and no A-selection log before shutdown, so that
trace could not identify the failed edge. V6.16 added synchronous selection
revalidation and a bounded 50 ms backup probe. Its own physical trace then
captured the failure precisely: the FIFO arrived at 2.899 seconds, neither
late absolute directory became a retained descriptor, init timed out at 3.60
seconds and the otherwise healthy early owner preserved the queue indefinitely.

V6.16 also replaces `111-sway-init` with the exact output captured from the
working card: `/dev/dri/card1`, `DSI-1`, DRM/libinput, zero transform and the
existing tearing/render-time policy. HDMI/DP discovery and `output_monitor`
leave the ordinary application session. The fixed script never masks or
unmasks `essway.service`. Both mismatched audio-latency scripts are suppressed
because the pinned writable image already contains the required value 64.
Finally, systemd's RF-kill process and activation socket leave offline boot;
the exact process is condition-released with the existing PortMaster network
transaction.

V6.17 tested bind aliases below the retained `/run/muos` directory. Init
published them at 3.07 seconds, but the old-root process still could not open
them. Its bounded timeout retired that process at 4.45 seconds and the normal
root launcher recovered at 7.12 seconds, proving the fallback while explaining
the first repaint. The compatibility coordinator then requested the already
running UI again and a second supervisor appeared near 10 seconds. PortMaster
started every requested provider, but `nm-online` timed out with no connection.

V6.18 deletes the two failed alias mounts. Init now sends one readiness event
after `prepare_sysroot` has moved the completed tree to `/sysroot/storage` but
before `/run` and the other special mounts move. Bird opens that stable path,
acknowledges it and retains the same PID; the timeout fallback remains. The
exact release autostart script is generated with only its redundant UI start,
associated log line and private-console clear removed (2,168 to 2,066 bytes).
Supervisor signal traps will identify any other lifecycle owner. Networking
reloads the saved keyfiles, explicitly activates the sole Wi-Fi profile, waits
for connectivity and records connection/device/reason/route data without the
PSK. Neither credentials nor network work enter offline boot.

The v6.18 physical gate passed every tested menu, storage, application, media,
brightness, control and shutdown path with no redraw regression. Storage became
usable at 2.479 seconds; the post-`prepare_sysroot` acknowledgement took zero
wait iterations. PortMaster remained offline. Its trace proves the saved WPA
keyfile is valid and visible, but Bird requested activation without ROCKNIX's
required iwd-device wait and NetworkManager scan; `wlan0` remained disconnected
with no route.

V6.19 reproduces the necessary fixed connection sequence: unblock the radio,
start iwd and NetworkManager in order, wait for iwd to register `wlan0`, scan,
then activate the sole saved profile on that interface. Failure evidence now
includes rfkill, scan and the two relevant journals. Offline boot is unchanged.
The coordinator also drops its already-completed storage request. Four common
slots are now proven no-ops for the pinned image: its 54-file, 548 KiB module
tree is byte-identical, the compatibility link already exists, no device switch
is present and H700/RG34XX-SP has no config overlay. Seven constant H700 writers
become one checked Bird profile transaction. Suspend-mode and GPU-overclock
side effects remain exact until separately audited.

The v6.19 physical trace proves scanning itself is correct: the configured
access point appeared at 65-percent signal, the radio was unblocked and iwd
registered `wlan0`.
NetworkManager nevertheless rejected the manually created profile immediately
at its prepare transition with no reason. Further Wi-Fi work is deferred until
the stock UI creates a working profile whose exact state can be copied.

More importantly, the trace explains the redraw and reboot regressions. A
provisional `essway` supervisor started near 5.6 seconds, was terminated at the
graphical transition near 8.4 and then replayed the still-armed request. The
post-frame audit was a oneshot wanted by `rocknix.target`; any slow diagnostic
there kept the target job open until `JobTimeoutAction=reboot-force`. V6.20
orders `essway` after `graphical.target`, so the initramfs Bird remains sole
owner until one stable final supervisor adopts it. The audit becomes an
idle-priority `Type=simple` service: systemd considers it started immediately,
so diagnostics cannot trigger the boot watchdog.

The v6.20 physical gate passed without either reboot or movie black-screen
failure. One Library selection froze and recovered at Home before a reboot;
the latest-only logs had already overwritten that failed boot. The launcher
also bounded its fixed input search at `event7` even though the snapshot saw 11
input classes, and the intended continuous volatile UI checkpoint was not
enabled by either build. V6.21 searches `event0` through `event31`, enables the
checkpoint in both launcher binaries and archives supervisor, early-launcher
and boot-state logs by boot ID. A recovery therefore returns to the exact view
and retains its own evidence instead of silently looking like a Home reset.

Lid wake also changed visible brightness because the retained generic fake
suspend toggles `bl_power` without owning Bird's exact raw level. A separate
Bird wrapper now saves that value before the provider transaction and restores
it after resume. The fixed controls binary writes the known backlight sysfs
directly instead of spawning the generic Bash/find/bc/settings stack. V6.21
initially treated raw one as lit and reserved zero for display-off; the later
physical correction below replaces that unstable minimum.

The retained fake-suspend implementation parks CPU1--CPU3 and deliberately
leaves CPU0 online. On resume it unparks those cores before restoring governors,
unfreezing processes, enabling the panel, releasing evdev grabs, restoring
audio/LED state and globally terminating the old suspend workers. That ordering
creates a real post-visible completion window. Bird's fixed-controls process on
CPU0 is consequently the durable transaction owner; the wrapper's explicit
completion marker, not panel visibility, releases a queued follow-up request.

The first hardware trace of release `v6.23-suspend-coordinator-7c332d5`
showed lid completion in 92--167 ms, ruling out its ten-second failure bound as
the ordinary cooldown. Power edges never entered coordinator state: every edge
was dispatched because the existing hot path still classified it from
ROCKNIX's transient power flag. That release is therefore rejected as a
cooldown fix, and the policy-only successor intentionally leaves its controls,
wrapper and provider behavior unchanged.

Read-only inspection of the returned card exposed a lower-level split owner.
The active writable image held `system.suspendmode=mem`, `AllowSuspend=yes` and
no logind lid override. The retained H700 fake-suspend provider exits before
doing any work unless that mode is `off`, while logind could independently
request the unsupported H700 real-suspend path. Timestamps showed H700
`030-suspend_mode` writing first and common `009-sleepmode` rewriting `mem` one
second later. Controls started several seconds before either writer, so a quick
post-menu suspend could race both. The policy-only candidate canonicalizes the
four fixed `system.cfg` keys and installs generated no-real-suspend and
no-logind-input policy during root preparation, before systemd, then suppresses
both late writers and removes competing drop-ins. It adds no coordinator,
provider, wrapper, trace or executable-path change, so the next physical gate
isolates this authority correction.

That gate rejected `v6.23-suspend-policy-92abfe8`: lid and power events were
dispatched but produced no suspend effect. The release and manifest verified,
and inode evidence localized the failure after root preparation. Retained
common/001 `chksysconfig verify` found `retroarch.cfg` absent and used its broad
`rsync -a /usr/config/ /storage/.config` recovery. The newly created RetroArch
file and overwritten stock sleep file share the same 17:52:48 inode time and
archived source timestamps; Bird's generated policy had been installed at
17:52:41. The same recovery restored a stock `system.cfg` containing the three
fake-suspend enable values but no `system.suspendmode`. The provider therefore
exited through its non-`off` hardware-suspend guard, while generated logind
policy left no second input owner.

The corrective boundary preserves common/001 recovery but removes its ordinary
reason to bulk-restore: root preparation copies either missing RetroArch
prerequisite individually before PID 1. A manifest-owned common/009 verifier
runs after common/001, restores an absent/non-`off` provider mode and repairs a
stale sleep file atomically. It is comparison-only in the accepted steady state;
generic common/009 behavior and H700/030 remain suppressed. This closes both
the observed first-boot overwrite and later policy drift without changing the
controls, coordinator, wrapper, or provider transaction under test.
The retained autostart loop does not propagate a common-hook failure, so a
future bounded candidate must either replace the broad common/001 recovery or
add an explicit fail-closed consumer. That fault-injection boundary is not part
of this returned-card correctness repair.

The physical follow-up accepted
`v6.23-suspend-recovery-103ce3b` for continued work. The full functional screen
passed and suspend was materially more reliable and predictable. Returned
event records now contain provider resume completions plus exercised
coordinator `queued` and `cancelled` transitions, proving the restored `off`
policy reaches the intended fake-suspend transaction. One rapid power-button
stress sequence reached the existing ten-second coordinator timeout. The user
accepts that residual quirk for now; it is documented rather than silently
treated as fixed.

The repair does not change launcher dispatch, rendering or input; its launcher
binary is byte-identical to the prior candidate. In the returned sample,
honest first usability was approximately 1.22 seconds after kernel start and
root preparation followed at approximately 3.87 seconds. Root preparation is
nevertheless concurrent post-launch work: pinned init has no explicit
usable-frame barrier before it continues, so the sampled ordering must not be
generalized into a categorical post-usable boundary. The fixed verifier runs
later in common autostart.

On this card all prerequisites are present and the verifier performs read-only
comparisons. It installs no resident process or timer and adds no steady-state
memory or ordinary idle-wakeup cost. Raw release payload excluding the manifest
grew by 3,688 bytes. Transient peak memory and device timing and energy remain
unmeasured. No framebuffer, input, UI-instruction or launcher-memory delta is
attributed to the repair, and its residual suspend quirks are accepted for now.

Stage 2 is now behaviorally complete on the active card. Its selected release
is `v6.23-framebuffer-watch-84a2435`, with
`v6.23-suspend-recovery-103ce3b` preserved as the previous selector. The
selected canonical manifest digest is
`4e056a6f6d9a03525b79db5504f260499f1f8748000984b295b31f132239fd83`,
and all 54 of 54 deployed files verified. The launcher installs a `/dev` watch
before the exact `fb0` probe, accepts only `fb0` create/move events, reprobes
once on queue overflow and retains the bounded 1 ms polling path only when
inotify is unavailable. Geometry, stride, format, mapping validation,
rendering and ownership remain unchanged.

Two returned boot records reported launcher-start/input-ready/usable-frame
milestones of 1221/1221/1224 ms and 1222/1223/1227 ms. The preceding release's
three usable-frame samples were 1226, 1229 and 1227 ms. No framebuffer error
appeared and the complete functional screen passed. These unpaired samples are
functional non-regression evidence, not a boot-time improvement claim. The
late-registration inotify branch has focused host coverage, but these device
logs do not instrument whether that branch activated.

The same release physically exercised application-return frame reuse. A
replacement launcher started at 32033 ms, reopened H700 input at 32034 ms and
published a usable frame at 32091 ms with `render=recovery`. Its snapshot was
restored, all three visible region hashes matched, the unused X byte remained
stable and both bound hashes matched exactly. This is behavioral proof of the
retained-frame contract, not a promotion-grade return-latency distribution.

One lid-suspend attempt rebooted the device and left no matching completion in
the retained suspend trace. That incomplete record cannot attribute the cause
to the coordinator, provider, kernel or another power path. The quirk remains
unproven and explicitly deferred while the plan advances.

The retained Stage 3A candidate subtracts only normal-success early-shell work.
It replaces the pre-launch BusyBox maximum-brightness `cat` with a shell
builtin `read`, removes two brightness diagnostic writes, removes three
concurrent/later uptime `cut` children and four normal root-ready/handoff LED
`cat` children, and reserves LED inspection for failure evidence. Exact
launcher/PID, storage acknowledgement, ownership, timeout, retirement and
failure boundaries remain unchanged. This targets one fewer pre-launch child
and two fewer pre-launch writes, plus seven fewer concurrent/later transient
children. It does not change launcher/framebuffer work or add a resident
process, timer or idle wakeup, and remains pending host and physical proof with
no performance or energy claim.

Returned Stage 3A hardware evidence recorded launcher/input/usable values of
1217/1218/1229 ms and 1211/1212/1225 ms, followed by storage at 3685 and
3739 ms. The broad menu/content path passed except that one movie pause press
also cycled the audio track. Both the Stage 3A and preceding framebuffer
releases contain the same MPV policy digest, so the shell subtraction did not
introduce that binding. Moving the audio command among SDL action aliases also
failed: west and east each emitted an intended action plus audio-track change.

The retained provider explains the overlap. `start_mplayer.sh` starts
`mpv.service`, whose Bash `mpv_sense` discovers devices, runs multiple `evtest`
readers and forks `echo | socat` for actions; the wrapper simultaneously passes
`--input-gamepad=yes` to MPV. The deployed Stage 4 candidate bypasses that
wrapper with a Bird wrapper that preserves fullscreen geometry and hardware
decoding but disables SDL/default bindings. One 6,424-byte static AArch64
helper validates the fixed H700 name, ID and capability bitmaps, uses
event-driven reconnect, and resynchronizes evdev state after overflow before
sending direct JSON IPC
commands. IPC loss reconnects without stale queued actions. The wrapper retains
the `mpv` process-name publication used by fake suspend and removes it at
provider return. The helper runs only for Listen/Watch content and blocks in
`ppoll` after socket readiness, so it changes neither boot nor menu idle. Host
tests cover every regular/one-handed command, chapters, playlists,
subtitle/audio chords, Select+Start suppression, picture adjustments,
`SYN_DROPPED`, bounded queuing and wrapper cleanup. Physical command mapping,
content interaction and media-session task/wakeup/memory effects remain gated.

The candidate is clean source
`f866fe7dbeaec3e3ee0d3937296968c804b77665`, immutable release
`v6.23-mpv-single-input-f866fe7`, canonical manifest
`475e786077d54d7247dbd11d463fcb8b8bd1377c7315e5913644f58bdb9fe017`
and 56 verified files. Menu+D-pad adjusts contrast or saturation by exactly one
point per press. The helper and wrapper exist only in the final-root media
payload, so this deployment adds no executable to the boot-critical path and
makes no boot-time claim before the RG34XX-SP gate.

Hardware rejected this tuple for media-control completeness while confirming
that the one-point contrast and saturation commands work. The successor keeps
the single event-driven helper but replaces mute with direct audio-language
cycling, restores the preceding player-relative volume contract on bare
bumper taps, preserves held bumpers as one-handed modifiers, and adds
Menu+bumper MPV-local brightness. Physical B remains the documented frame-step
action; its pause-and-one-frame behavior is not a second pause owner. This
follow-up remains final-root media-only and cannot alter boot or menu idle.

The follow-up is deployed as clean source
`813226d4c1b0fe9715bdae3f37d44485e4ad815f`, immutable release
`v6.23-mpv-complete-controls-813226d` and canonical manifest
`05f20822324d62be334a290f9567d341efc6f08243c14ab88adda43073d975a6`.
Deployment verified all 56 manifest-owned files and retained the rejected
single-input tuple as the previous selector. Host tests explicitly cover one
B edge producing one frame-step, both global-exit chord orders, shoulder-use
suppression, reconnect snapshots and `SYN_DROPPED`. The launcher is
byte-identical; the final-root helper's 280-byte file and six-byte loadable
section increases do not create a boot or menu-idle cost.

The RG34XX-SP gate passes the complete successor control contract on boot ID
`347650ca`, including chaptered `Angel's Egg.mkv`, provider exit and matched
retained-frame return. The early log recorded launcher start at 1218 ms,
validated input at 1219 ms, usable frame at 1222 ms and storage at 3945 ms.
The content log then attributed request/session/application-contract/Sway/
provider-dispatch milestones to 7.558/10.09/12.21/14.04/14.29 seconds. Provider
return at 73.98 seconds preceded launcher restart and usable retained-frame
publication at 74.324 and 74.377 seconds. These are one-run kernel-relative
stage observations, not physical content-photon or distribution claims.

The next Stage 4 candidate removes only the largest remaining per-boot runtime
copy. Clean source `12b8ff6906eebe86eac9431d690769fcc94db1c1` is deployed as
`v6.23-flash-launcher-12b8ff6`, canonical manifest
`44ce41ac87cea8f84a36ea1934c28b2d9ed3821d76bf8b864d2bc484ecececd5`,
with all 56 files independently verified. Its previous selector is the accepted
MPV-control checkpoint. The early launcher stays in initramfs and is
byte-identical; only a final-root replacement executes from the selected
immutable `/flash/bird/bird-launcher`.

The writable preparation set falls from 19 copies/817,170 bytes to 18
copies/219,817 bytes. This removes one `cp` child, one chmod operand, one
destination check and 597,353 aggregate bytes (73.1 percent). No launcher code,
framebuffer traffic, input work, resident task or timer changes. The likely
benefit is less post-launch storage work and a shorter path to replacement
launcher availability; boot, UI/content timing, transient memory and energy
remain physical measurements rather than claims.

The returned direct-flash gate is functionally accepted. Boot ID `a4886df4`
recorded launcher start, validated input and usable frame at 1220, 1221 and
1224 ms, compared with 1218, 1219 and 1222 ms for the preceding checkpoint.
Those unpaired +2 ms samples support non-regression only. The same log explains
one apparent early-selection freeze: selection/request/launcher-exit occurred
at 3.606/3.956/3.996 s, but the provider did not begin until 14.50 s. No failed
unit, OOM, release fallback or launcher adoption fault was recorded; the old
pixels were noninteractive during a roughly 10.5-second content-readiness gap.

Clean source `e2c46b278c19974c2983aadc1249bcce9353f709` is deployed as
`v6.23-emergency-recovery-e2c46b2`, manifest
`cfe5864bd9a21805d14b625bc17945dd14eb38a5206593f22072ffcf1e640f91`.
Menu+Select+Start now runs a final-root, emergency-only helper directly from
`/flash`. It snapshots unit/process/memory/Bird state and bounded journal/kernel
evidence into `/storage/bird-data/MUOS/Bird/log/emergency/`, syncs before
mutation, invokes the existing managed foreground exit, cancels pending state,
validates an inherited launcher before signalling it and requests one UI
supervisor restart. This adds no boot executable, resident task, timer, ordinary
syscall or idle wakeup. The controls binary adds 256 file bytes (`.text` +60,
`.rodata` +192, `.bss` unchanged); the helper adds 6,254 immutable release
bytes. Physical recovery and log-survival remain unclaimed until tested.

Boot ID `bf45b45b` physically accepts emergency recovery. The chord at
75.887 s sealed a 178,213-byte snapshot and restored a matched retained-frame
menu by 76.543 s without resetting. The same Atari game then completed a normal
RetroArch launch and return. Initial launcher/input/usable-frame timing was
1217/1218/1221 ms.

The snapshot proves the freeze preceded provider execution. Systemd reported
the chain `powerstate -> essway -> graphical -> seatd -> multi-user ->
powerstate` at 5.268 s and deleted `essway.service/start`. The launcher produced
a valid request and exited at 27.157 s; process and unit snapshots later showed
no supervisor, Sway or content process. The old menu pixels therefore had no
input owner or dispatcher. Earlier result-137 content evidence belonged to a
different boot and is not the cause of this incident.

The correction deletes the `After=essway.service` edge while retaining both
units in the fixed target. Clean source
`895e6a7ae557df3b202e6ac7b78234441b705c0e` is deployed as
`v6.23-ui-order-895e6a7`, manifest
`fdf3e466ef85682c4b6de977ff8484c5bb9b24eddf953f4f6981eb206aa6e149`.
The unit file falls from 291 to 276 bytes; the launcher and 5,528-byte power
worker remain byte-identical. This adds no boot executable, process, timer,
wakeup, framebuffer traffic or binary memory. Hardware must now show both
services active and repeated first-game dispatch without an ordering cycle.

That hardware gate passes. Six returned boots recorded usable-frame times of
1229, 1225, 1222, 1222, 1224 and 1218 ms, with a descriptive median of 1223 ms.
All captured final-root snapshots had both units active and none contained the
ordering cycle or deleted UI job. Repeated content dispatch/return, shutdown
and logged UI recovery also passed; the samples establish non-regression only.

The next retained-userspace subtraction moves only `run-content.sh` from the
per-boot writable preparation set to direct execution from `/flash`. Clean
source `0b438f52b767e3c8ec008c1a5e7c342c0d503643` is deployed as
`v6.23-flash-runner-0b438f5`, canonical manifest
`2ca0ba49a33e0a62f9abbe73419696a32943af70fbc266659ad59bd08cf75ec6`.
The dispatcher remains byte-identical at 65,346 bytes. The copy set shrinks
from 18 files/220,067 bytes to 17 files/154,715 bytes, removing one `cp`, one
mode operand, one destination check and 65,352 source plus destination bytes.
This changes no launcher/input/framebuffer path, resident service, idle timer or
memory footprint. The RG34XX-SP gate passes complete content launch/return,
media, recovery and shutdown. Three surviving usable-frame records are 1224,
1232 and 1239 ms, a descriptive median of 1232 ms; the external stopwatch
remained about 2.7 seconds. The small unpaired set and byte-identical early
launcher establish non-regression only.

One stress boot reset during a power resume after four completed suspend cycles.
The O_DSYNC trace ends with dispatches at 29.623 and 30.566 seconds and no
resume-complete marker. No panic, ordered shutdown, pstore or reset-cause record
survived; the following boot completed repeated cycles. No retained-service or
coordinator change is supported by that evidence, so the quirk remains deferred
for finer phase/reset instrumentation.

The next subtraction starts the same generated supervisor directly from
`/flash/bird/supervisor.sh`. Clean source
`f06686ab0cf80676733de800809c39765aadfc6e` is deployed as
`v6.23-flash-supervisor-f06686a`, canonical manifest
`e69a5c90fae8479161819b5797984d03e9d8a15e0c96f23a75c4647c6582bb37`.
The writable set falls from 17 files/154,715 bytes to 16 files/136,973 bytes,
removing one `cp`, one mode operand, one destination check and 17,742 source
plus destination bytes. This changes no retained process or launcher, provider,
suspend, audio, timer, wakeup or memory behavior. Hardware service state,
boot timing, content return, recovery and shutdown remain the gate. That gate
passes: two valid per-boot usable-readiness records are 1232 and 1221 ms after
kernel start, the stopwatch remained near 2.7 seconds, and direct supervision,
game/media return, emergency restart and shutdown remained functional. The
sparse timing set establishes non-regression only.

Audio-only MPV suspend exposed a separate retained discontinuity. One run
abruptly reset after resume dispatch without a completion marker or attributable
panic/OOM/reset cause. The next run completed the transaction but replayed about
one second; PipeWire reported output and MPV XRUNs at resume. Movie suspend on
that boot completed correctly. The retained provider stops MPV but leaves the
PipeWire graph alive, then resumes MPV before unmuting. No blind pause behavior
is accepted; a future audio-only candidate needs acknowledged IPC, prior-pause
preservation, background-music policy and finer resume/reset evidence first.

The next subtraction executes the single-consumer 811-byte
`first-frame-prep.sh` directly from immutable `/flash`. It removes one copy
child, chmod operand, destination check and 811 source plus destination bytes,
without changing the launcher, content, audio, suspend, task, timer or memory
paths. The physical gate remains boot non-regression, brightness observation,
quick content return, emergency restart and shutdown.

Clean source `094be8be0555c4ab51f2968b21f13993b63de96f` is deployed as
`v6.23-flash-firstframe-094be8b`, manifest
`c90a4b6b5b21fd5cedabdb58f0756ec8ceb810adf18c39efae017becde8dff20`,
with all 57 manifest files verified and the accepted supervisor as previous.
Both release launchers and their ELF sections are byte-identical; profile sizes
remain 658,408/669,992 bytes. The overlay changed from 615,251 to 615,256
compressed bytes with no early-launcher change. That gate passes: five valid
usable-frame records are 1229, 1221, 1221, 1229 and 1226 ms after kernel start,
with a descriptive median of 1226 ms and no regression from the supervisor
checkpoint. The stopwatch remained near 2.7 seconds. The immutable pre-start
completed in about 10 ms without writing brightness, and game, music, reader,
movie, retained-frame return, emergency UI restart and durable shutdown passed
without failed units or ownership loss.

The next subtraction runs the single-consumer 4,831-byte
`capture-boot-state.sh` directly from immutable `/flash` after autostart. It
removes its writable copy, chmod operand and destination check, reducing
preparation from 15 files/136,162 bytes to 14 files/131,331 bytes and removing
4,831 source-read plus destination-write bytes. The script execution and its
diagnostic writes remain. This changes no launcher, content, input, controls,
suspend, audio, task, timer or resident-memory behavior, and is not a boot-time
claim. A fresh complete snapshot, boot non-regression, content return and
shutdown remain the physical gate.

Clean source `9c4250ee50afd37c720a25b7cf109a64bd1a1303` is deployed as
`v6.23-flash-snapshot-9c4250e`, manifest
`4d854a95edbea36e0e23e26ce7fa76c6a559b790ffcf30e0a852c98d0f877b93`,
with all 57 manifest files and the `.complete` digest verified. The accepted
first-frame-preparation checkpoint is the previous selector. Final and early
release launchers and their ELF sections remain byte-identical at
597,336/600,600 bytes; profile sizes remain 658,408/669,992 bytes. The overlay
remains 615,256 compressed bytes with changed content from the copy-list
subtraction. The inactive supervisor release was archived, published and
independently verified on GitHub before its card copy was removed. This
candidate's physical gate passes. Boot `02d6aba1` opened input at 1222 ms,
committed the usable frame at 1229 ms and published storage at 3713 ms. The
47,325-byte/786-line snapshot ran from `/flash/bird` through its final section,
with zero failed units and no jobs. Game, media, PortMaster networking/cleanup,
suspend/resume, exact return and durable shutdown also passed.

The next aggressive subtraction removes all 13 remaining immutable
runtime-publication copies. They were retained by the original stock-root
bridge to provide a conventional writable execution namespace, repair FAT mode
semantics and fail closed on partial destinations. Every active consumer now
uses the manifest-verified session-long `/flash/bird` bind; mutable launcher
state remains under `/storage/.config/bird`, and only ROCKNIX's 260-byte mutable
memory policy is still copied to `/storage/.config/swap.conf`.

Preparation falls from 14 files/131,331 bytes to 1 file/260 bytes, eliminating
13 `cp` invocations, 131,071 source-read plus destination-write bytes, the
executable chmod transaction and 13 destination checks. This is post-usable
storage/application work, not a boot claim. The combined physical gate covers
all controls, content and forced cleanup, provider/network return, suspend,
quick and changed shutdown and rollback; per-path source assertions keep each
batched change independently diagnosable.

Clean source `61c51dd798af47330af604e2884553f2e0275e68` is deployed as
`v6.23-flash-toolset-61c51dd`, manifest
`d806243beeb5edbffadc36ac1f83fb9306407935d1084e24d23aa11a2881a8a9`,
with all 57 files and the `.complete` digest verified. The accepted snapshot
checkpoint is the previous selector. Both release/profile launcher pairs and
their sections remain byte-identical. The only executable-size change is fixed
controls, 10,608 to 10,568 bytes through a 40-byte `.rodata` reduction. The
manifest-owned release shrinks 1,869 bytes; the mount hook contributes 1,692
bytes and the compressed overlay changes from 615,256 to 615,254 bytes. The
inactive first-frame release was archived, published and independently verified
on GitHub before its card copy was removed. The broad gate passes. Boot
`b116d112` opened direct input at 1218 ms, committed the usable frame at 1226 ms
and published storage at 3723 ms. Its early selection remained one pending
intent; two managed games returned 0 with matched retained-frame restoration.
The operator reported the full controls/provider/PortMaster/suspend/shutdown
matrix passing. The usable result remains inside the accepted 1221--1229 ms
range, so it proves non-regression rather than improvement.

The next Stage 4 audit candidate removes ordinary execution of the broad
post-autostart snapshot. The accepted boot's 46,984-byte/782-line snapshot
began at 12.17 s, overlapping application-contract readiness at 12.10 s and
preceding content-service startup at 13.94 s. It is now armed only by persistent
marker `/storage/bird-data/MUOS/Bird/boot-diagnostics.request`, atomically publishes a
boot-scoped record and then refreshes the latest copy. Narrow readiness,
supervisor, content, emergency and shutdown logs remain ordinary behavior.

The accepted emergency evidence also showed systemd prematurely expanding the
cleanup guard's shell variables and reporting invalid environment-variable
names. Both `systemd-run` boundaries now specify `--expand-environment=no`.
This is a correctness fix for literal provider/guard arguments, not merely log
cleanup. Built-in reads remove all 39 external uptime parser sites, two
`cat`/three `awk` process-stat sites, three path-validation helpers, three
`sed | head` metadata pipelines, four PortMaster owner reads and seven tiny
supervisor state reads. Exact validation and the completed D-Bus-before-audio
barrier remain intact.

Clean source `e87e4910459b953b7a1f2ebd19a0efee35fe9e57`, release
`v6.23-content-shell-e87e491` and manifest
`28e2372b36cef01c5f49b584c8896b00ce6969299a30eebb1d40a367d960c70c`
are deployed with the accepted toolset checkpoint as previous. All 57 files
verified; launcher/profile binaries and sections are unchanged, total
manifest-owned bytes grow 2,703 and the overlay shrinks to 615,251 bytes. The
older snapshot is independently verified in the private GitHub archive. HDMI
and Bluetooth are untouched and remain explicit later product decisions. The
physical gate covers ordinary and armed diagnostics, expansion-warning
absence, immediate/queued launches, forced-exit classification, providers,
controls, suspend, shutdown and boot/UI non-inferiority.

The returned content-shell gate passed on boots `d86b5a36` and `ce9da31c` with
usable readiness at 1229/1222 ms, ordinary snapshot absence, correct exit
classification, matched recovery and durable shutdown. It is now the accepted
rollback for the fixed-coordinator candidate.

The retained coordinator audit is closed in candidate source
`133834108ee66a6ad965c44441b6e09690eb8369`. One fixed coordinator replaces 26
no-op process launches, approximately 45 timestamp helpers, generic directory
scans and 31 autostart bind substitutions while calling the 14 retained duties
in the same pinned order. Optional custom hooks and tolerant failure behavior
remain; the validating application marker is still authoritative. Journald is
explicitly volatile and bounded, with empty flush/catalog jobs masked but the
daemon retained. Release `v6.23-fixed-autostart-1338341` has manifest
`2c9553b94c7fffd25dff2f45b764c342c134ca6564ed3f9ae9a040ca0149d198`.
This is post-usable subtraction and makes no first-frame claim.

The returned gate passed all functionality. Six current-release usable samples
span 1223--1235 ms, while final-root supervisor entry moved from 9.65--9.69 s
to 9.25--9.53 s. It is now the accepted rollback for the fixed-session batch.

The session audit found no active login1 consumer: Bird owns lid/power, fake
suspend does not call logind, and content explicitly starts seatd before Sway.
Candidate `v6.23-fixed-session-46dd170`, clean source
`46dd1704e3453dd3f3fcbb55ea96488716deb840`, masks logind, the daily tmpfiles
wakeup and volatile UTMP boot/runlevel jobs. Manifest
`00ba951842afc78f2f27a34f952f790e7cc32eab385db4f902cc0e9c0d7df7cd`
binds the deployed release. Udev is intentionally retained: historical device
evidence shows required metadata consumers and a failed daemon-stop experiment.

The returned fixed-session gate passed all tested functionality. Boots
`17553b07`, `9ff881cd` and `b7c3b076` reached usable readiness at 1222, 1223
and 1222 ms. Final-root supervisor entry was 9.42, 10.67 and 9.26 seconds; the
middle outlier prevents an application-readiness improvement claim. The exact
fixed-session tuple is now the physically accepted rollback.

The next audit boundary is clean source
`91b2f58ed696dfcd547b1ffd52fcb5ceb3ad3602`, release
`v6.23-fixed-housekeeping-91b2f58` and manifest
`41edbb038356df9cbf1086d451a6731ba3b2bc3c7ad71c9d0754d6b76ee9100f`.
Generic logging and Pico-8 hooks previously performed three steady-state
filesystem mutations after the menu, and storage preparation retained a
logind-policy comparison, mode read and drop-in scan after logind removal. The
fixed hooks are idempotent and the inert policy work is absent. Udev, seatd,
journald, audio, networking, HDMI and Bluetooth are unchanged. This is a
post-frame application-readiness/I/O candidate; no boot, power or memory gain
is claimed before device evidence.

The returned housekeeping gate passed all tested functionality. The preserved
clean sample reached H700 input at 1216 ms and usable readiness at 1220 ms.
One stress sequence ended after lid-open without a resume-complete record and
was followed by a new boot sequence; subsequent suspend cycles passed. The
available logs contain no durable panic/watchdog cause and housekeeping did not
change controls, suspend, power or kernel code, so this is documented without a
speculative correction.

The next audit boundary is clean source
`b87dcc2a5c7f7ef0fc8c4737eebf51ac60b2dd87`, release
`v6.23-fixed-profiles-b87dcc2` and manifest
`c9dbc12ff1ca1ef98d7436824321db922905dce45afcac50617db18e1ffe0564`.
It replaces runtime H700 controller XML generation with the exact derived fixed
profile, retains configuration recovery while removing valid-state settings
rewrites, makes UI/application profiles idempotent and removes the unused
EmulationStation start lock. Udev, seatd, journald, audio, networking, HDMI,
Bluetooth and suspend remain unchanged. This is an application-readiness and
persistent-I/O candidate, not a first-frame candidate.

The returned physical gate accepted that exact fixed-profile tuple. Two clean
samples reached input at 1216/1218 ms, usable readiness at 1222/1221 ms and the
supervisor at 9.28/9.26 s, with the complete tested behavior matrix passing.
The next retained-policy audit removes generic runtime discovery around CPU,
GPU, turbo and rumble but explicitly preserves their RG34XX-SP controls. The
captured closure includes four Cortex-A53 cores, all advertised CPU/GPU
governors, 600 MHz normal and 648 MHz overclocked GPU maxima, CPU boost and the
joypad driver's PWM vibrator. These are retained capabilities, not feature
deletion candidates. HDMI, Bluetooth and audio are outside this batch.

Clean source `01e8119ac9953f87442f1627bfd2032485cf9aa5` replaces the four
wrappers without changing the accepted values. Release
`v6.23-fixed-performance-01e8119`, manifest
`70bfa8c408e1f939c3a678ba506ca65e3a5aebdbf33eaa2e5ca370ae2734cc6a`,
is deployed with fixed-profiles as rollback and all 65 files verified. The
steady path removes recursive `find`, general profile loading and external
`seq`, `wc`, `ls`, `grep` and `tee` helpers. Shell parsing reads each exact key
without a child process, malformed values take fixed safe defaults without a
persistent rewrite, and each policy has independent fault-injection coverage.
The launcher binary and framebuffer metrics are unchanged; no host A53
instruction or device latency/power claim is made. HDMI, Bluetooth, audio,
suspend and the production no-serial policy are unchanged.

The returned fixed-performance gate passed all tested hardware and content.
Launcher start/input/usable readiness were 1218/1219/1222 ms, inside the
accepted range. That exact release is the rollback for manager-lifetime work.

The media follow-up found no active MPV audio-delay override. `12 Angry Men`
has AAC start time 0 and H.264 start time 0.125125 seconds; MPV's reported A/V
error remained small while its log recorded substantial dropped video frames
after seeks. This is retained as source-file/decode evidence and does not alter
the global player policy.

The next audit separates two managers. Seatd becomes an on-demand content
provider under an exact lease that spans Sway ownership and forced cleanup.
Udevd completes coldplug and then exits, but its systemd kernel/control sockets
remain available to reactivate it. This tests one fewer steady menu-idle task
per manager without deleting rules, hwdb, hotplug capability, HDMI or Bluetooth.
Any measurable content-start regression rejects the seatd half independently.

Clean source `d2e064928727a0580f4c07085d2b8eb46be0a4ee` implements both
independent lifetimes. Release `v6.23-fixed-managers-d2e0649`, manifest
`0c13e8d8a35042b3853b8debf1f1be05e78df4e7682e3a48cfeca53cf6a09463`,
is deployed with fixed-performance as rollback and all 67 files verified. The
launcher and compressed overlay are byte-identical; explicit policy/lease code
adds 2,316 manifest bytes. Host tests prove failure retention, Sway rollback,
ownership transfer, external-guard release, udev settle/stop/state rejection
and retained socket activation. Device manager PSS, wakeups and energy are not
claimed before measurement.

The device gate accepts functionality but rejects the seatd lifetime change.
Stable session-to-Sway-ready median was 490 ms versus 470 ms with warm seatd.
The combined candidate's session-to-provider median was about 710 ms versus
630 ms, which does not prove that the remaining delta belongs to udev. Restore
the stock warm seatd lifetime and preserve explicit content-side
`systemctl start` for early queued-launch correctness. Retain only the
independently tested post-coldplug udev manager quiescence in the next release,
with its activation sockets intact. This keeps the measured higher-priority
content path ahead of seatd's observed 1,556 KiB RSS saving and gives udev an
attributable physical A/B.

Clean source `7d74bf668e3a38a9ae1cd1ceb15d81babf191592` implements that
isolation in release `v6.23-udev-isolation-7d74bf6`, manifest
`c5fbebc38faa9a469d5c6363dc47811ef0983e973e30908648c09872b8fdbe6f`.
All 66 files verify. The launcher is byte-identical to fixed-managers, the
content runner shrinks 807 bytes and total manifest-owned bytes shrink 1,459.
The only remaining manager experiment is udevd exit after settlement with both
activation sockets retained; seatd again starts through the normal graphical
path and the explicit content-side join remains as an idempotent early-launch
guard.

The isolated RG34XX-SP cycle rejects that remaining experiment. Six stable
sessions reached Sway-ready in a 470 ms median after warm seatd was restored,
but session-to-provider remained 690--730 ms versus roughly 630 ms with warm
managers. The delay is concentrated after Sway readiness while udev consumers
prepare, showing that socket activation moved udevd startup into content launch.
Restore fixed-autostart v2 and retain udevd through menu idle. This deliberately
accepts the previously observed manager memory in favor of priority-two content
latency. The retained audit is closed with warm udevd, warm seatd, warm audio,
bounded volatile journald, no logind, PortMaster-only networking, and no HDMI or
Bluetooth removal decision.

Clean source `72d7fe6058dcd21d8c95545871c0acffc3d3dce6` restores that
closure in release `v6.23-warm-managers-72d7fe6`, manifest
`8b81f34ab5f84e4c1faafee2ee13357de08a26af704f2a8a26e6ac8107f1b545`.
All 65 manifest files verify. The launchers are unchanged, the rejected udev
policy file is absent, manifest-owned bytes shrink 875, and the active
coordinator is again the physically accepted v2 implementation. Production
remains no-serial while diagnostic and fallback entries retain serial.

The warm-manager physical return passed hardware behavior and recorded
1217/1218/1221 ms launcher/input/usable readiness. Stable Sway readiness was
460--490 ms from session start; total provider dispatch was 700--720 ms despite
implementation equivalence with the earlier warm checkpoint, so the older
roughly 630 ms sample is not used as a hard regression boundary without a
larger controlled set. The next audit work is measurement, not another manager
lifetime guess: an explicitly requested Stage 5 sampler captures raw PSS/USS,
wakeup, IRQ, CPU-idle and battery counters without entering ordinary boot.

That sampler is deployed from clean source
`3ce316d17574e8487ab846975c404f82f3366e56` as release
`v6.23-stage5-metrics-3ce316d`, manifest
`aba835ad6dd467ff553df81ec64db6542ea4f13e87903fe3268e89bfe3083289`.
All 66 manifest files verify. Warm-managers remains the accepted on-card
rollback. The unarmed sampler adds no ordinary process or wakeup; its 3,036-
byte manifest increase is measurement infrastructure, not a memory-efficiency
claim.

The request-only metrics release passed its broad physical gate at
1218/1219/1223 ms launcher/input/usable readiness. Clean source
`2ca82cdf5fd3d173644b756797ae8f0421f4a87d`, release
`v6.23-stage5-idle-2ca82cd`, manifest
`c44f2639aaa714d46ef264d26f3627ed7598699d85c4aaadb7e7abfe88af09c1`
adds only an explicitly armed one-shot idle counter window. It has no ordinary
caller, process or timer. Its paired counter deltas can attribute wakeup and
residency candidates, while calibrated energy remains a separate physical
metric.

The first armed window did not run because the host wrote BIRD-DATA `.config`
but the unit checked the separate ROCKNIX storage-image `.config`. The broad
hardware gate still passed; there is simply no valid idle sample. The corrected
fixed boundary is `/storage/bird-data/MUOS/Bird`, which is already mounted and
host-visible before final-root systemd. Builder and host tests reject either
request path returning to `/storage/.config`.

The corrected trigger is clean source
`97dd6ffc55b2c1f86650bf1a7bb95cd10d1ff9e0`, release
`v6.23-stage5-trigger-97dd6ff`, manifest
`505ac5d6674d81f18aff22723117dd2d48fafdffb443d3d961de6229bf2a6af5`.
All 66 files verify and the launchers are unchanged. The next returned card
must contain both labelled samples and an absent one-shot marker before any
counter delta is used.

Boot `62fc769f` met that contract and the hardware gate passed. The raw window
observed 0.43 percent aggregate CPU busy, about 1,469 context switches/s and
1,030 IRQs/s; `arch_timer` was about 486.5/s and the H700 ADC exactly 300/s.
These are screening observations only. A PID exited between glob expansion and
awk open, invalidating PSS/USS, and the start sampler's structural reads entered
the scheduler interval. The next sampler reads each `smaps_rollup` independently
and brackets the global interval with minimal ordered counter endpoints while
also recording per-process scheduler/context-switch deltas. Do not attribute
the timer or ADC cost to userspace or begin kernel work from this single run.

That corrected sampler is deployed from clean source
`9945f9d4f43013a0f09df7ea51a7a23dc1812b04` as release
`v6.23-stage5-counters-9945f9d`, manifest
`f65def91471288ea1aa7fb310ccfbb07fdc18414bf8d85d692d39fbe2814b704`.
All 67 files verify; stage5-trigger remains the on-card rollback. A separate
minimal counter endpoint orders structural collection outside the global timed
interval and records per-process scheduler/context-switch state. PSS/USS now
reads one process at a time so an ordinary exit cannot invalidate the complete
sample. The 3,371-byte release-inventory increase is neutral instrumentation,
not a memory-efficiency regression claim, because it adds no ordinary resident
mapping, process, timer or syscall. Production remains no-serial and the
diagnostic/fallback entries retain serial.

The next untouched device boot is the physical gate. Only complete versioned
start/end blocks and atomic one-shot disarm may replace the contaminated
screening values or justify an idle-cost candidate.

The corrected return passed. Its 15-second interval recorded 0.45 percent CPU
busy and about 1,484 context switches/s. Launcher and powerstate each consumed
under 0.5 ms; PipeWire, PulseAudio, WirePlumber and seatd consumed zero runtime.
Udevd consumed 53.3 ms, but its earlier quiescence experiment lost the priority-
two launch gate. The dominant recorded activity is now kernel worker plus fixed
ADC/timer work, not a warm userspace manager. These counters do not measure
energy.

Clean source `56d58d404817f90588e61e0faa58beb0e7547f66` deploys the longer
standalone acquisition as `v6.23-stage5-settled-56d58d4`, manifest
`8e0988258c445c4c743f9afe8ae042a86d3bf144aa8a6c78456070641c343ebc`.
All 69 files verify. It separates the one-shot window from broad diagnostics,
uses a 30-second settle and 60-second interval, suppresses expected disappearing
`smaps_rollup` errors and brackets CPU/IRQ/softirq counters outside structural
enumeration. Stage5-counters remains the on-card rollback. This is neutral
measurement infrastructure; ordinary boots have no new process or timer.

The first standalone-service deployment is rejected. The immutable stock root
had no `bird-stage5-window.service` destination, so its bind mount failed and
root preparation never completed. That exactly explains the early menu with no
content, brightness, volume, suspend or emergency helper. Storage never handed
off, so no new diagnostic log was expected to survive.

Clean source `d0c6e4edb02753f3f006ad2513976ce25b87cbfa` repairs the boundary in
release `v6.23-stage5-slot-d0c6e4e`, manifest
`bcf8e4575878ba81f8ffd854037436e2876a859148f959d167fe1c1981c8df95`.
The already-present stock report-statistics service becomes a two-request
dispatcher. A new host assertion rejects absent unit bind destinations. The
failed release is archived; stage5-counters remains the on-card known-good
rollback. Do not arm measurement until final-root behavior passes again.

That recovery gate passed. Final-root ownership, early pending launch, games,
media, reader, PortMaster, controls, suspend, emergency recovery and shutdown
worked; boot milestones were 1223/1224/1226 ms. The diagnostic slot is accepted
and the clean menu-idle request may be armed again without changing binaries.

The repaired slot then produced a clean 60-second short-label menu-idle window
after a 30-second settle on boot `71d6d1b1`. Aggregate CPU busy was 0.289 percent.
The launcher and retained journald, udevd, PipeWire, PulseAudio, WirePlumber,
seatd and supervisor recorded zero runtime in the window; `bird-powerstate`
used 0.868 ms. The remaining structural floor was kernel dominated: the ADC
delivered 300.1 interrupts/s and the architecture timer 464.2/s. This is a
userspace-exhaustion boundary for this state, not calibrated battery evidence
and not permission to begin kernel optimization before the remaining Stage 5
matrix and userspace promotion gates pass.

The second-boot marquee window passed on `cb7daf5b`. Launcher work was 30.1 ms
and 277 slices over 60 seconds; aggregate busy was 0.318 percent and ADC stayed
at 300.1 interrupts/s. Boot milestones remained 1217/1218/1226 ms. That cost is
limited to active scrolling and does not justify reducing visual cadence. The
same condition-gated sampler may now acquire distinctly labelled paused-game,
audio-playback, video-playback and external-power menu windows; none adds an
ordinary-boot process, timer or probe.

Clean source `e8cd4ef2b5546bd158454bccaf0db951298a3237` deploys that label-only
extension as `v6.23-stage5-states-e8cd4ef`, manifest
`9e62d8ffabe2d2091a5b832aca4f53b77e90c1a3cd450c247efc02774c299a18`.
All 69 files verify. The executable owners and launcher binaries are unchanged;
only the explicitly requested diagnostic parser accepts the additional states.
Stage5-slot is the card rollback. Do not arm a content window until the broad
hardware behavior gate passes.

That unarmed gate passed. Launcher/input/usable readiness was
1219/1220/1222 ms and the broad physical matrix remained functional. The
paused-game window may now be armed without rebuilding or changing owners.

The operator-positioned RetroArch paused-menu sample passed on boot
`24facdce`. RetroArch used 53.59 CPU-seconds and Sway 5.55 CPU-seconds in the
60-second window, while PipeWire, PulseAudio, WirePlumber and seatd used none.
Aggregate four-core busy was 28.58 percent and RetroArch PSS/USS was
204,267/194,748 KiB. This attributes the paused-state cost to continuous
RetroArch/Sway menu presentation rather than the retained audio managers. It is
structural evidence, not calibrated energy; preserve responsiveness until an
independent throttling candidate is measured.

The ordinary MP3 playback window passed on boot `a91f03d0`. MPV used 1.95
CPU-seconds and 5,712 slices over 60 seconds. PipeWire, PulseAudio, WirePlumber,
seatd, Sway and the Bird MPV helpers recorded effectively zero runtime during
the window. The three warm audio managers nevertheless retained 18,682 KiB PSS.
This proves that this MPV path is not consuming their CPU during steady
playback; it does not yet prove that other providers can launch, play, suspend
and return without them. Preserve interaction behavior until that closure is
measured.

The v6.21 physical gate passed those UI and brightness contracts. Four MSX
games then proved a single provider fault: storage, input, audio and the full
blueMSX BIOS tree initialized before the pinned `bluemsx_libretro.so` segfaulted.
V6.22 selects the release's included fMSX core and copies its six required ROMs
from the already-present shared BIOS directory only when absent. OpenBOR also
proved ROCKNIX's name-based global kill contract incomplete: its runner clears
the kill list and never replaces it. V6.22 records the active wrapper PID,
tries the provider's graceful name first, then terminates only descendants of
that managed wrapper. Bird's uniform chord remains Select+Start; because the
fixed process never grabs the gamepad, generated RetroArch Menu+Start and all
native application keybinds remain available.

The 2026-07-26 follow-up gate disproved the earlier raw-one brightness
assumption. The RG34XX-SP exposes a Linux maximum of 2499, making raw 1 only
0.04 percent; after DPMS wake that requested value can remain physically dark.
The fixed low-end contract is therefore 5, 3 and 1 percent (raw 125, 75 and 25
at the observed maximum). The next physical gate proved all three values remain
visible once running but cannot start the panel after DPMS; raw 250 (10 percent)
is the first reliable wake value. Wake now strikes at that measured threshold
for 50 ms and then restores the exact saved dim level. Zero remains display-off
only.

The Nintendo DS display baseline is explicit: earlier hardware work reproduced
striped/column-corrupt DraStic output on its GLES2 path and restored correct
presentation by selecting desktop OpenGL with Panfrost. Any later DraStic,
Sway or profile change must preserve that graphics path.

V6.23 follows the accepted-functionality code review rather than adding a new
feature. The complete payload manifest now owns release preflight, staging
and destination verification; deployment and fallback activation use verified
temporary files and atomic renames. Application readiness carries an exact
revision and is published only after its profile transaction succeeds. The
supervisor races first-frame creation against launcher exit and retries bounded
recoverable failures locally. Every content provider runs in a transient
systemd scope whose invocation identity is recorded for the fixed global-exit
helper, while all runner exits reconcile Sway and optional networking. The same
pass adds the controls exec handshake, one catalogue/favorites path limit,
auxiliary-descriptor recovery and an atomic shutdown checkpoint. This is the
accepted repository and hardware baseline. The host fault-injection suite and
complete RG34XX-SP functional gate passed on 2026-07-26 with canonical
deploy-manifest digest
`e441f9c2755173353a9d29969807c2a05411240b7e9d2a1d18ed099d3c91b4d2`.

That physical gate accepts movie resume; stable global audio and ROCKNIX
volume/brightness notifications; Y-button Favorites; native Menu+Start in
RetroArch and PPSSPP alongside Bird's Select+Start managed exit; native Ports
and the translated Stardew launcher; fMSX; standalone PSP; N64 audio; DraStic
without striped output; and OpenBOR. Repeated boot, launcher recovery, content
return, brightness, low-level lid wake and shutdown checks completed without
the reported reboot regression.

## Audit findings and current disposition

The v6.15 audit found the following generic work and defects. Only items marked
**open** remain active optimization targets after the accepted v6.23 baseline:

1. **Closed in v6.16:** `111-sway-init` scanned DRM connectors, EDIDs,
   rotations, dual panels and unrelated products before rewriting Sway on every
   boot. birdOS now bind-replaces it with the generated RG34XX-SP
   `card1`/`DSI-1` profile.
2. **Partially closed; pop work deferred:** `050-audio` uses
   `[ -n "/usr/sbin/quantum" ]`, which is always true, instead of testing
   whether the executable exists. Bird's content boundary now reads the exact
   H616 CARD jack and reconciles the independent MIXER speaker switch only when
   needed; physical testing accepts headphone-only output. A muted explicit
   PipeWire resume did not remove the speaker or headphone transients and was
   removed. Generic quantum work and codec power/pop attribution remain later
   audit candidates. HDMI and Bluetooth subtraction is not authorized; whether
   either retained path belongs in the final image is an explicit later product
   decision.
3. **Closed in v6.16:** the two latency writers used inconsistent
   `audiolatency` and `global.audiolatency` keys. Both are suppressed because
   the pinned writable provider already contains the required value.
4. **Closed in v6.19:** `020-configs` used relative `.quirk-*` tests while
   writing markers under `/storage`, allowing expensive `rsync` work to repeat.
   The fixed profile transaction now owns the required H700 outputs and the
   generic slot is a no-op.
5. **Closed in v6.15:** `055-hdmi-check` performed two DRM scans and contained
   an unquoted numeric test. The fixed internal-display profile suppresses it;
   HDMI is not an offline-boot feature. Suppressing offline connector scans does
   not decide whether retained HDMI support ships in the final image.
6. **Closed in v6.15:** `098-deviceutils` and `099-networkservices` repeatedly
   started or stopped device-family service sets already expressed by the fixed
   target and unit gates. Both slots are bind-replaced by the fixed no-op.
7. **Closed in fixed-autostart candidate:** the retained coordinator visited
   every platform/common slot. The fixed coordinator calls only the catalogued
   responsibilities and retains the validated application marker.

## Next active order

1. Physically restore the warm-manager checkpoint after rejecting both
   on-demand seatd and post-coldplug udevd exit for content latency.
2. Preserve HDMI and Bluetooth until their explicit product decision.
3. Measure retained seatd, udevd, PipeWire and volatile journald PSS, wakeups
   and calibrated energy before proposing another lifetime change.
4. Keep logind removed and networking PortMaster-only while completing the
   Stage 5 idle/content/suspend power matrix.
5. Remove the muOS-to-ROCKNIX compatibility namespace as an explicit migration:
   canonical `/storage/roms`, `/run/bird`, Bird-owned data/config directories,
   native BIOS/Ports paths and no launcher-time path rewriting.
6. Re-measure menu, storage and application-contract boundaries before kernel
   or U-Boot subtraction.

## Deliberately deferred

- survey muOS and other operating systems for transferable optimizations;
- emulator/RetroArch experience and cold-load tuning;
- PortMaster load-time tuning;
- bespoke music, movie, emulator and application experiences;
- codec crack/pop attribution and retained audio residency/power policy;
- suspend/wake battery optimization; and
- final boot animation, sound and media-player control design.

Those are preserved roadmap items, not rejected work. They follow the current
ROCKNIX audit and namespace cleanup so they are tuned on Bird's final contracts.
