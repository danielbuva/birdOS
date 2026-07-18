# Fixed RG34XX-SP experience

This is the build contract for Dani's console. Values here are deliberate
product decisions, not runtime options.

## Fixed hardware

- Device: Anbernic RG34XX-SP only (`rg34xx-sp`).
- SoC: Allwinner H700, AArch64 Cortex-A53.
- Internal display: 720x480, landscape, 3:2.
- Input: built-in D-pad, A/B/X/Y, shoulders, Start/Select/Menu and lid switch.
- Primary storage: the OS card's ROM partition mounted at `/mnt/mmc`.
- HDMI, alternate boards, touchscreens and external controller setup are not
  part of the first custom-launcher target.

## Fixed behavior

- Language: English only.
- Startup destination: the custom launcher's four-item main menu.
- Network: completely off at boot; loaded only for an explicit network task
  such as PortMaster or scraping.
- Game discovery: a generated cache, never a boot-time directory scan.
- Storage readiness: the cached collection remains browsable while storage is
  made ready asynchronously; launching is gated on the selected ROM path.
- Diagnostics: retained during development, then reduced to precise milestone
  markers in the reproducible firmware.
- Stock muOS frontend: retained only as a fallback until the custom launcher
  can launch games, return from them, suspend and shut down reliably. B on the
  main menu remains the explicit recovery path during development.

## Launcher menu

The first hardware proof deliberately contains only:

1. Games
2. Favorites
3. PortMaster
4. Shutdown

This is a functional skeleton, not the final visual design. It embeds only its
English bitmap glyphs, draws directly to the Linux framebuffer, reads evdev
directly, and remains resident as the permanent shell. B from the main screen
is the explicit development recovery path; there is no inactivity handoff to
stock.

Games opens an embedded, generated catalogue. The current proof catalogue
contains five titles across SNES, PSP, and Ports, including the newly installed
ROTA Port. It is browsable
before ROM storage mounts; storage readiness and individual ROM availability
are presented separately.

Favorites is an exact-path cache, not a scan. Y adds or removes the selected
title, an atomic text file persists the selection across boots and catalogue
reordering, and the cache is loaded only after ROM storage becomes ready.

Ready proof titles use fixed launch mappings: Snes9x for SNES, standalone PPSSPP
for PSP, and the external-script launcher for Ports. The custom launcher releases
display and input ownership while content runs, then returns directly when the
content process exits. No automatic core discovery is part of this device.

PortMaster is the explicit network boundary: selecting it loads Wi-Fi, connects,
runs the tool, then disconnects services and unloads the driver before returning.
Shutdown uses the normal muOS poweroff machinery directly from the custom menu.
Both paths are hardware-verified and do not enter the stock frontend.

The boot-effects proof keeps the complete menu as frame zero and starts its
1.6-second procedural accent immediately. It completes on the first input, so
it cannot delay or capture interaction. muOS's later saved-brightness restore
is disabled; the firmware-established value remains until manual adjustment.
A 320 ms mono PCM chime waits asynchronously for the existing PipeWire route,
uses the proven `mpv` path directly, and is cancelled if the launcher hands off
before playback. The line and tone are development assets; final effects move
to an earlier firmware layer.

## Decisions reserved for the visual phase

- Final color palette and wallpaper.
- Final font design and sizes.
- Animation motion and duration.
- Boot sound.
- Whether History/Resume gets a permanent first-level entry.
- Exact game-system grouping and emulator mappings after the real library is
  added.
