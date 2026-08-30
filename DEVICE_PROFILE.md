# Fixed RG34XX-SP experience

This is the build contract for the target console. Values here are deliberate
product decisions, not runtime options.

The operator-accepted source and behavior binding is clean commit
`5373c644b9c91ac21a17e145375747a8196a3337`, immutable release
`v6.23-20260814-201218`, deploy-manifest digest
`904c8da42a6ec84ccf4b291205999c3b0e25900f4bec7bb3f9e0cfefb29164dd`,
device-contract digest
`1664a3778abcd3687865a82fd28bba5b468f6c3c7e9a46bf90f7c3acb1e08162`
and catalog digest
`9795aae6baddc292f5d9954a444656e303db305c639284f16eb10288c41f1f93`.
The previously accepted immutable release remains privately archived as
`v6.23-20260811-234132` with manifest digest
`a0a38b04be25f2d09009b0677d33c0d34c65b027c0ff1b9463f71cdeec9b274b`.
It was built from clean source
`c07fe18769a13a3b1997e2cf1a4900cc55423d5b` and remains verified external
history, not required on-card rollback state. `ROADMAP.md` owns successor
promotion status. This document owns human policy;
`bird-device-contract.tsv` owns the machine-readable hardware subset without
replacing this experience contract.

## Fixed hardware

- Device: Anbernic RG34XX-SP only (`rg34xx-sp`).
- SoC: Allwinner H700, AArch64 Cortex-A53.
- Internal display: 720x480, landscape, 3:2.
- Input: built-in left and right analog sticks, D-pad, A/B/X/Y, shoulders,
  triggers, Start/Select/Menu, L3/R3 and lid switch. Both sticks and all four axes
  (`ABS_X`, `ABS_Y`, `ABS_RX`, `ABS_RY`) are required hardware; their ADC
  sampling must not be removed as presumed-unused polling.
  The primary launcher device is the exact `H700 Gamepad` identity
  `0019:484b:14df:0100` with its complete generated event, key, absolute-axis
  and force-feedback closure. Retained hardware captures establish the full
  force-feedback bitmap as `107030000 0`.
- Primary storage: the OS card's content partition, retained by the early
  launcher at `/storage/bird-data`. The active catalog and providers use
  `/storage/roms` and `/storage/media` directly; mutable Bird state lives under
  `/storage/bird-data/Bird`. No active launcher-time path translation remains.
- Boot storage: the fixed 128 MiB `BIRD` partition keeps one immutable
  canonical base and one mutable `dev-current` slot. Superseded canonical
  releases are archived and verified privately before their card copies are
  removed. No alternate kernel, selector, or UI is retained outside that pair.
- Offline boot targets the internal panel and built-in controls. Alternate
  boards, touchscreens and external-controller setup remain outside this
  product.
- Whether the final image retains HDMI and Bluetooth support is an explicit
  later product decision. Current optimization candidates preserve both
  retained paths; absence from offline boot is not approval to remove them.
- CPU core count and governor, GPU governor and bounded H700 overclock, and CPU
  turbo are retained adjustable RG34XX-SP capabilities. Their implementation
  may use fixed board paths and verified limits, but later optimization must
  not collapse them into one immutable performance mode.
- The built-in PWM vibrator is retained hardware. Rumble may be enabled or
  disabled by policy and remains available to compatible content; removing
  generic device discovery is not permission to remove force feedback.

## Fixed behavior

Optimization policy is lexicographic. Power-to-honest-usable Bird is first and
may not be slowed by later preparation. Interaction is second and includes
menu navigation, launching and closing every game/application/media provider,
and restoring Bird input after return. Battery is third: the fixed image may
keep measured launch-critical resources warm or hardcode their preparation,
but must not keep every generic process resident by default. Each warm/cold
decision balances calibrated idle energy against a frozen interaction margin.
Memory and storage are fourth and may be reduced only when boot, interaction,
and battery remain non-inferior.

During an accepted user action, responsiveness wins until the destination—or
the returned Bird menu—has working input. Cleanup not required for ownership or
correctness continues asynchronously after that boundary. Between actions,
power wins: the device should rapidly become quiet, with no polling, avoidable
hardware activity or unjustified warm process. Residency, caching, suspension
and termination are fixed measured choices based on launch/close cost, usage
frequency, idle energy and memory rather than a universal warm/cold rule.

- Language: English only.
- Startup destination: the custom launcher's four-item main menu.
- Network: completely off at boot; loaded only for the explicit PortMaster
  network task.
- Game discovery: a generated cache, never a boot-time directory scan.
- Storage readiness: the cached collection remains browsable while storage is
  made ready asynchronously; launching is gated on the selected ROM path.
- Diagnostics: no probe gates the first usable frame. Ordinary boots retain
  exact readiness, supervisor, content, emergency and shutdown records but do
  not run the broad post-autostart probe set. A full snapshot is explicitly
  armed by persistent marker
  `/storage/bird-data/Bird/boot-diagnostics.request`,
  publishes under its own boot ID and refreshes
  `stock-root-boot-state-latest.log`; remove the marker to disarm subsequent
  captures.
- Compatibility provider: the pinned ROCKNIX 20260701 application and hardware
  closure, with birdOS replacing its frontend and selected generic policy.
- Boot failure policy: retain no alternate kernel, selector, UI, retry counter,
  or automatic supervisor restart. Verification failures persist a reason and
  stop with the selected release unchanged. Return the card to the host, then
  repair or redeploy from verified canonical bytes. B on the main menu refreshes
  birdOS in-process and never chooses or modifies a boot selector.

## Launcher menu

The permanent fixed shell starts with exactly:

1. Play
2. Listen
3. Read
4. Watch
5. Tools
6. Quit

It embeds only its English bitmap glyphs, draws directly to the Linux
framebuffer, reads evdev directly, and remains the permanent shell. B from Home
refreshes that frame in-process and is not a UI route into the boot fallback.

Play contains Systems and Favorites. Systems opens the
embedded 5,984-title, 27-system game catalogue. It is browsable before ROM
storage mounts; storage readiness and individual ROM availability remain
separate.

**Input Tester** appears before PortMaster under Tools. It is a direct,
event-driven visual check of all 17 gamepad controls, both analog sticks,
L3/R3, volume, power and vibration. It remains idle without a frame loop; Menu
gives a short rumble test and holding B exits. Its 29/29 RG34XX-SP gate passed.
Quit contains Reload, Reboot and
Shutdown. These remain explicit launcher handoffs rather than direct power or
process-management syscalls from the UI.

Favorites is an exact-path cache, not a scan. Y adds or removes the selected
title, an atomic text file persists the selection across boots and catalogue
reordering, and the cache is loaded only after ROM storage becomes ready.

Ready titles use their compiled launch mappings, including RetroArch cores,
standalone PPSSPP, DraStic, OpenBOR and Port scripts. The custom launcher
releases display and input ownership while content runs, then returns to the
exact previous view and row. No automatic core discovery is part of this
device.

Listen, Read and Watch open their own compiled category/file catalogues. The
current card contributes 51 audio files, five EPUB/PDF books and eight films.
Listen and Watch use the firmware-native MPV bridge; Read opens the exact
selected EPUB or PDF through the installed KOReader PortMaster application.
None of these views scans storage at boot.

The fixed MPV control contract follows the documented regular and one-handed
RG34XX-SP layout without SDL aliases:

| Control | Regular action | While L1 or R1 is held |
| --- | --- | --- |
| A | Pause/play | Seek forward 5 seconds |
| B | Advance one frame and remain paused | Seek backward 60 seconds |
| X | Cycle audio language/off | Seek forward 60 seconds |
| Y | Playback time/details | Seek backward 5 seconds |
| D-pad left/right | Seek backward/forward 5 seconds | Pause/playback details |
| D-pad down/up | Seek backward/forward 60 seconds | Frame step/cycle audio |
| L1/R1 | Tap for player volume -/+2; hold for one-handed mode | Modifier |
| L2/R2 | Previous/next chapter | Previous/next playlist item |
| Select | Cycle subtitles | Cycle audio track |
| Start | Toggle subtitles | Toggle subtitles |
| Select+Start | Exit through Bird's global content contract | Same |

Dedicated volume keys change system volume, and Menu+volume changes display
brightness. Bird adds two non-overlapping picture-control chords: Menu+D-pad
left/right changes contrast by -/+1, and Menu+D-pad down/up changes saturation
by -/+1. Menu+L1/R1 changes MPV's player-local video brightness by -/+1
without changing display backlight or system volume. These extensions are not
represented as historical muOS controls.

PortMaster is an explicit network boundary: its selected session may acquire
Wi-Fi, resolver and time services, then release them before returning. Saved
network configuration is used only by that direct scoped session; network setup
never enters offline boot. The currently accepted provider is the official
`2026.07.28-1212` managed inventory. Its runtime-generated Python caches are
never trusted as provider code: every PortMaster, Port and KOReader execution
uses a fresh tmpfs `PYTHONPYCACHEPREFIX` and disables bytecode writes. Shutdown
requests the normal ordered systemd poweroff path from the birdOS menu.

The active boot path has no animation or startup sound while earliest
interaction is being optimized. The fixed controls worker owns manual
brightness. Its stable low-end ticks are 5, 3 and 1 percent. The accepted
canonical release stores the rounded 10-percent cold-start level before
unblanking, with no timed strike or restore; RG34XX-SP testing showed the Bird
menu without a black interval or flash and was descriptively about 50--55 ms
earlier than the preceding cold-strike boots. Release
`v6.23-20260814-201218` passed the separate immutable physical gate. Lid/power
wake still briefly starts the panel at the measured
10-percent threshold, then restores the exact saved dim level. Suspend is the
retained H700 fake-suspend policy:
CPU0 remains online, CPU1--CPU3 park, systemd real suspend is disabled and
logind never owns the power key or lid switch. Missing application defaults are
recovered individually so they cannot reset this policy. A fixed post-recovery
verifier may reassert `off` and `AllowSuspend=no`; on an accepted ordinary boot
it performs read-only checks. A late generic brightness or suspend-policy reset
is not part of the contract. Final effects will be designed only after the
fixed init/kernel path is complete.

Green-at-power work is deferred: the inspected mainline U-Boot candidates did
not remove the earlier red interval. The unused FAT environment backend and
the fixed MMC0-partition-1 extlinux command are both physically accepted; the
latter passed the complete RG34XX-SP behavior gate at about 2.6 seconds by the
user's stopwatch.
Generic U-Boot zeroes its malloc arena for callers across many boards; the
accepted intermediate Stage 10 boundary removes only that 64.125 MiB
full-U-Boot clear while retaining its allocation capacity and SPL policy. Its
two reproducible builds, component authority and bounded installer gate pass.
The reviewed 620,745-byte artifact is
`38ace6d738fed727fdd2274b510c3e18105b2c71f7b1d908dece357e31d1365c`,
and its exact 16 MiB prefix is
`ea1afbf3186945e562aa0844d7ab6d1b027be9cfafe225a0e4c0745ffc50b305`.
Its bounded installation completed exact full-prefix readback, supplied the
required predecessor for fast-init, and passed the returned broad device gate.
Generic U-Boot also supports interactive autoboot, filesystem and target
discovery, explicit MMC selection, networking and bootstd for variable systems.
The reviewed fast-init boundary uses fixed FAT sysboot, removes the unneeded MMC
wrapper and UART abort check, and builds neither network nor bootstd. Its
reproducible 556,977-byte artifact is
`4afc68bd2a7fdaacc212683a1a268380c07775d18cf12025285778221e986081`,
with exact 16 MiB prefix
`172ca1a500603ea371a17bee1b6a7632ba17e4991a400f57cee0b2231e75bdeb`.
It is 63,768 bytes (10.27 percent) smaller than no-heap-clear while preserving
SPL, TF-A and the control DTB exactly. The two separately asserted transaction
boundaries passed their combined RG34XX-SP physical gate. Fast-init's installer
reread and matched its complete pinned prefix before remount; three subsequent
boots and the returned broad functional matrix passed. A fresh raw reread is
unavailable because the host sudo lease expired. Fast-init therefore became the
physically accepted predecessor on the install-time exact verification and
post-install boot evidence. No new stopwatch result was reported, so no
boot-time improvement is claimed. Green-at-power work remains
deferred.

Why the previous behavior existed: generic U-Boot relocates the initramfs and
device tree because it must safely support unknown boards, load addresses and
payload sizes. Why change it: birdOS has one fixed RG34XX-SP layout. The
accepted extlinux path loads the exact 603,487-byte
initramfs at `0x4ff00000` and the exact 49,010-byte DTB at `0x4fa00000`; the
12,288-byte DTB pad and later fixed buffers have explicit non-overlap proofs.
The physically accepted in-place-handoff boundary compiles
`initrd_high=ffffffffffffffff` and
`fdt_high=ffffffffffffffff` from the 55-byte board environment
`bird-rg34xx-sp-handoff.env` at
`335b569a6f63acab13d20bccb843b5d6d979b7141ede3a5a5a2647b59ec132ce`.
Its only resolved change from accepted fast-init is
`CONFIG_ENV_SOURCE_FILE=""` to `"bird-rg34xx-sp-handoff"`; the transformed
defconfig is
`0254301f87e2222f04c67a34e5351bce16ebaac712bd96cc096f76027d9ded13`.
The repeated build identities are: 556,977-byte combined artifact
`7423ffeda197645b6b774c83fcebcbefef47bd7eaa6f087c71ab339750af4e91`,
516,017-byte FIT
`c11d9b780c4c78940590ee17965550aa3eca7e7d0d04fdb37b4c9869b2418bf4`,
437,168-byte full U-Boot
`cff9a9ca1bd7db20a3a136fec655d7120481afa8a837930266a9962ab2dec578`,
47,408-byte config
`77f2bee66adc542e3475594c4727933607f76c2adf72e6428e0e57cadb6de762`
and 16 MiB prefix
`c168640be0e3b0fc3899853d71aabc0c3b3e65fdf230b19782ff40ff19f001dd`.
Its SPL (`0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c`),
BL31 (`431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673`)
and control DTB
(`ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589`)
remain byte-identical. Avoiding the initramfs move and padded-DTB move models
664,785 fewer copied bytes, not a hardware timing improvement. Its bounded
installer completed its exact post-write authority check and two returned
RG34XX-SP cycles passed the broad functional matrix. The following canonical
gate bound clean commit `5373c644b9c91ac21a17e145375747a8196a3337` to release
`v6.23-20260814-201218` and manifest
`904c8da42a6ec84ccf4b291205999c3b0e25900f4bec7bb3f9e0cfefb29164dd`.
Its four usable-frame records are 1174--1177 ms, with a midpoint median of
about 1176 ms; input-ready median is 1170 ms. Three completed asynchronous
storage records have a 3514 ms median; that three-sample result is noise-scale.
The 2.8--2.9-second stopwatch result likewise establishes no measurable
improvement. In-place handoff is the active physically accepted U-Boot
boundary. Stage 10 is roughly 90 percent complete. The raw-kernel bootstage
measurement and corrected uninstrumented LZ4 development-device gate are
complete; deeper fixed-path pruning and the inherited-frame experiment remain.

Why before: the retained fake-suspend provider
owns the proven audio, input, governor, core-parking and LED transaction; Bird
owns only fixed-panel restoration, and the rare-edge trace uses `O_DSYNC`
without adding an idle timer. Why change: no suspend behavior is changed now
because canonical boot `96df160e` retained suspend and resume-dispatch records
but no matching resume-complete, timeout, orderly shutdown or reset cause before
the next boot,
while boot `a245d090` completed three later cycles in 726--768 ms from wake edge
to completion. This nonblocking intermittent reset remains deferred for a
focused provider/PMIC and reset-surviving diagnostic cycle.

Why the previous measurement boundary existed: source inspection expected
generic bootm's `bootm_load_os` mark. The accepted trace proved that `booti`
owns `BOOTM_STATE_LOADOS` itself and never emits it. Why change it: require the
actually emitted `boot_jump_linux` mark with `bootm_start`, preserving an exact
setup/decompression-to-handoff boundary without custom timing. The post-frame
capture now requires `board_init_f`, `board_init_r`, `main_loop`, `bootm_start`,
`boot_jump_linux` and `start_kernel` in order. Incomplete evidence fails closed,
and `start_kernel` remains handoff-start rather than literal Linux entry. Why
the first builder stopped: raw `CONFIG_BOOTSTAGE` enlarged SPL global
data even with `SPL_BOOTSTAGE=n`, shifting `cyclic_list` and changing SPL bytes.
Why change it: the host-reviewed measurement-only artifact combines the exact
accepted 40,960-byte SPL with the diagnostic FIT and retains the reproducible
different generated SPL as explicitly unused evidence. The combined image is
561,073 bytes at
`0b22418db35ee591870ccd652d4aaa3d0a50bd216e600f7b8ca0c4052e2e8e83`;
the full prefix is
`c1dadb6b43782ac25b8be6ea168cbad7c2e435da49207210213be68701f7f94b`.
Only full-U-Boot data changes in the FIT, both passes are byte-identical, and
the artifact grants no production-successor deployment authority. A separately
pinned `temporary-measurement-only` installer now admits only the exact
in-place prefix and canonical `v6.23-20260814-201218`, requires capture to be
armed, and provides exact in-place restoration. Its raw-sector and recovery
host gates pass. Three returned traces put the median fixed FAT/extlinux load
interval (`main_loop` to `bootm_start`) at 1,419,998 us and the following booti
setup/handoff interval at 224,968 us. Seven coarse stopwatch samples had a
2.78-second median and the broad behavior gate passed. This prioritizes the
LZ4 functional gate without claiming calibrated total latency. Why the raw
kernel existed: it is
the accepted simplest handoff and
needs neither a U-Boot decompression stage nor its temporary output buffer. Why
consider changing it: the fixed 30,926,856-byte Image becomes a 17,565,707-byte
LZ4 frame, leaving 13,361,149 fewer kernel payload bytes (43.2024 percent) to
load before decompression. The host-ready frame is at
`a7321d2a79b18e81f114aefd9bb7509ba70d5e56b562a345ea5ca66dbf11262a`,
but is full-release-only until paired with
`kernel_comp_size=0x10c080b` and passed through the broad RG34XX-SP functional
gate. These host byte counts are not a device timing result.
Two fresh isolated linked passes are byte-identical at combined SHA-256
`9f3d96da4126a6654187a3cddb9b0c038b251882aee9938e0b258d0bac94f35b`
and full-U-Boot SHA-256
`35cd4f8d50568f7bdae89fe01ce851b80276c4a44c18138de553872456523f9e`.
They retain the accepted config, SPL and control DTB, change only four compiled
environment bytes and leave a 19,378,066-byte guard margin before the DTB. The
pair is reviewed production-successor authority. Its bounded transaction
admits only exact in-place U-Boot and provides direct exact in-place recovery.

Why the two authorities remained separate: the first linked proof isolated the
four-byte LZ4 bound, while the accepted bootstage authority remained an exact
timing diagnostic. Why change: both reviewed bootstage A/B payloads now receive
that proven equal-length delta independently and converge on a 561,073-byte
paired image at
`d386f00ee8b0db002f5de3206d4af522a33a0f26960efe0561b29e01dbf2a083`.
Its full-U-Boot SHA is
`57232f25c04da2fb8bac08f4c5f5be6af6d1da069b32e0bb50baaebff4219fe3`
and its derived prefix is
`cf13ad801ffc3a2c1b1e65879f72a683cebe29e476c7dfde7d0c136eeb54d2ee`.
The accepted SPL, config and control DT are exact. The instrumented combination
remains historical and nondeployable; immutable LZ4 release construction and
the broad device gate remain required.

Why the measurement path is now retired: it was a temporary way to locate the
dominant U-Boot interval, not a product feature. Why change: the returned traces
already show the fixed loading interval dominates. The next canonical runtime
therefore removes the capture helper and restores exact uninstrumented in-place
U-Boot before testing the uninstrumented LZ4 pair through the broad functional
device gate. Human stopwatch samples remain a coarse sanity check only.

## Efficiency contract

Priorities are strict:

1. Boot and interaction latency.
2. Battery efficiency: eliminate polling, needless wake-ups and resident
   services.
3. Memory efficiency: remove unused processes, libraries, caches and assets.
4. Add only the exact features selected for the fixed device profile.

The launcher remains a prototype. Its architecture is proven, and its first
idle pass now blocks on the fixed evdev descriptor instead of waking every
4 ms. Framebuffer write strategy and state representation remain explicit
later optimization targets rather than reasons to delay larger boot and init
wins.

## Further visual decisions

- Replacement artwork for the currently pinned static wallpaper.
- Whether any animation can justify a fixed framebuffer-write and battery
  budget without adding an ordinary idle wakeup.
- Animation motion and duration.
- Boot sound.
- Whether History/Resume gets a permanent first-level entry.
- Exact game-system grouping and emulator mappings after the real library is
  added.
