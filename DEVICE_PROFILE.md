# Fixed RG34XX-SP experience

This is the build contract for the target console. Values here are deliberate
product decisions, not runtime options.

Commit `79b6e3e03771f2787622a3e4f6f9d8f129b7281f` is the operator-accepted source
and behavior baseline. The accepted binary fallback is immutable release
`v6.23-20260731-054816`, whose canonical deploy-manifest digest is
`5f95153bf46239a5e178fde28924f01c7fe586be182562f9bd9f33cf13da02ba`.
Its manifest retains its actual older dirty source identity rather than
claiming a clean `79b6e3e...` provenance. `ROADMAP.md` owns successor promotion
status. This document owns human policy; `bird-device-contract.tsv` owns the
machine-readable hardware subset without replacing this experience contract.

## Fixed hardware

- Device: Anbernic RG34XX-SP only (`rg34xx-sp`).
- SoC: Allwinner H700, AArch64 Cortex-A53.
- Internal display: 720x480, landscape, 3:2.
- Input: built-in D-pad, A/B/X/Y, shoulders, Start/Select/Menu and lid switch.
  The primary launcher device is the exact `H700 Gamepad` identity
  `0019:484b:14df:0100` with its complete generated event, key, absolute-axis
  and force-feedback closure. Retained hardware captures establish the full
  force-feedback bitmap as `107030000 0`.
- Primary storage: the OS card's content partition, retained by the early
  launcher at `/storage/bird-data` and exported to applications through the
  fixed `/storage/roms` view. `/mnt/mmc` is only the launcher's compiled
  catalogue namespace; the runner translates it before dispatch.
- HDMI, alternate boards, touchscreens and external controller setup are not
  part of the first custom-launcher target.

## Fixed behavior

- Language: English only.
- Startup destination: the custom launcher's four-item main menu.
- Network: completely off at boot; loaded only for the explicit PortMaster
  network task.
- Game discovery: a generated cache, never a boot-time directory scan.
- Storage readiness: the cached collection remains browsable while storage is
  made ready asynchronously; launching is gated on the selected ROM path.
- Diagnostics: no probe gates the first usable frame. Ordinary boots retain
  the exact readiness logs and one bounded, idle-priority post-frame snapshot;
  deeper probes are individually armed for a specific experiment and removed
  again afterward.
- Compatibility provider: the pinned ROCKNIX 20260701 application and hardware
  closure, with birdOS replacing its frontend and selected generic policy.
- Boot recovery: loader or post-flash verification failure selects the
  preserved clean-root fallback immediately; repeated full-stack startup
  failure before an honest interactive frame selects it at the fixed attempt
  threshold. The verified runtime plus input-open framebuffer marker commits
  boot health before the graphical supervisor, so a usable-menu refresh or
  reboot cannot consume the threshold. Both fallback paths verify the recovery
  assets before changing the selector. B on the main menu refreshes birdOS
  in-process; it neither opens a stock frontend nor chooses or modifies the
  boot fallback.

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
the exact saved dim level. A late generic brightness reset is not part of the
contract. Final effects will be designed only after the fixed init/kernel path
is complete.

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
