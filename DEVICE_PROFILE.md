# Fixed RG34XX-SP experience

This is the build contract for the target console. Values here are deliberate
product decisions, not runtime options.

The operator-accepted source and behavior binding is clean commit
`8aeb117d995e5b56c875fd5016a727189e01bc55`, immutable release
`v6.23-20260811-071550`, deploy-manifest digest
`5569cca6998617850aeeda9a77597c16b08a1755b5538d96c7e62665e9a1b415`,
device-contract digest
`1664a3778abcd3687865a82fd28bba5b468f6c3c7e9a46bf90f7c3acb1e08162`
and catalog digest
`9795aae6baddc292f5d9954a444656e303db305c639284f16eb10288c41f1f93`.
The previously accepted immutable binary reference remains archived as
`v6.23-20260731-054816` with manifest digest
`5f95153bf46239a5e178fde28924f01c7fe586be182562f9bd9f33cf13da02ba`.
Its manifest retains its actual older dirty source identity. It is external
verified history, not required on-card rollback state. `ROADMAP.md` owns
successor promotion status. This document owns human policy;
`bird-device-contract.tsv` owns the machine-readable hardware subset without
replacing this experience contract.

## Fixed hardware

- Device: Anbernic RG34XX-SP only (`rg34xx-sp`).
- SoC: Allwinner H700, AArch64 Cortex-A53.
- Internal display: 720x480, landscape, 3:2.
- Input: built-in left and right analog sticks, D-pad, A/B/X/Y, shoulders,
  Start/Select/Menu and lid switch. Both sticks and all four axes
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

Tools currently contains only PortMaster. Quit contains Reload, Reboot and
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
brightness. Its stable low-end ticks are 5, 3 and 1 percent; lid/power wake
briefly starts the panel at the measured 10-percent threshold, then restores
the exact saved dim level. Suspend is the retained H700 fake-suspend policy:
CPU0 remains online, CPU1--CPU3 park, systemd real suspend is disabled and
logind never owns the power key or lid switch. Missing application defaults are
recovered individually so they cannot reset this policy. A fixed post-recovery
verifier may reassert `off` and `AllowSuspend=no`; on an accepted ordinary boot
it performs read-only checks. A late generic brightness or suspend-policy reset
is not part of the contract. Final effects will be designed only after the
fixed init/kernel path is complete.

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
