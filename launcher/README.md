# Direct-framebuffer launcher proof

`dani-launcher.c` is an intentionally freestanding AArch64 Linux program. It
uses direct kernel syscalls and has no libc or dynamic-library dependencies.
The macOS build produces a relocatable object; the RG34XX-SP's own GNU linker
creates the final static executable during user-init.

The calibration runs were deliberately late and temporary:

1. Stock muOS reaches its normal screen.
2. The proof stops stock after three seconds.
3. The proof draws its own 720x480 menu and opens evdev devices directly.
4. The fourth proof captured both Linux evdev events and `/dev/input/js*`
   joystick button/axis events for every remaining built-in control.
5. A timeout ended each capture automatically.
6. Stock muOS restarts automatically.

Input-calibration results are written to
`/mnt/mmc/MUOS/bespoke-launcher/proof-v4-remaining.log`. A
successful run gives the exact framebuffer format, stride, input device names,
first-frame uptime and exit reason needed for the early-boot version.

The first early version started after udev and produced a usable custom screen
in 7.28 seconds by stopwatch (5.581 seconds of kernel boot time). Its launcher
rendered in 19 ms, while the stock `mufbset` helper consumed about 1.65 seconds.

The direct-event version removes that helper and the joystick compatibility
path. `S03danilauncher` starts before udev, and the binary waits only for the
fixed `/dev/fb0` and `/dev/input/event1` nodes. It reads the RG34XX-SP controls
straight from evdev while stock initialization continues behind it. B hands
off to stock after the system-ready marker. D-pad navigation wraps so every
direction press visibly moves.

The verified direct build starts at 2.269 seconds of kernel uptime with input
already usable and completes its first frame at 2.289 seconds. The corresponding
LED-on stopwatch time is approximately four seconds.

## Embedded catalogue proof

`generate-launcher-catalog.py` converts a host-side ROM manifest into a C header
that is compiled directly into the launcher. The launcher never scans storage
at boot and can browse the cached names before `/mnt/mmc` is mounted. A narrow
50 ms readiness probe reports when `/mnt/mmc/ROMS` appears; selecting a cached
title tests only that title's exact path.

The first proof manifest contains four already-tested games across SNES, PSP,
and Ports. It validates nested browsing, paging, back navigation, and storage
readiness without treating the card's temporary 1,952-game SNES set as the final
library. Regenerate the same header from the final curated manifest later with:

```sh
./generate-launcher-catalog.sh /Volumes/dani-sp/ROMS path/to/manifest.txt
```

The catalogue proof measured process entry at 2.305 seconds, first interactive
frame at 2.327 seconds, and ROM storage readiness at 4.117 seconds. All four
cached paths tested ready without any runtime directory scan.

## Fixed game handoff

Selecting a ready title writes a three-line request containing only launch kind,
display name, and exact ROM path, then exits cleanly to release framebuffer and
evdev ownership. `S03danilauncher` waits for the already-dispatched startup,
PipeWire socket, and fixed controller map before using these confirmed mappings:

- SNES: `snes9x_libretro.so` through `lr-general.sh`
- PSP: standalone PPSSPP through `ext-ppsspp.sh`
- Ports: executable script through `ext-general.sh`

The supervisor waits for the game process, records its result, and starts the
custom launcher again without starting the stock frontend or calling `mufbset`.
This keeps the proof narrow while retaining muOS's emulator configuration,
controls, audio setup, saves, and emulator exit behavior.

The hardware proof passed for all three launch paths: SNES through RetroArch,
PSP through standalone PPSSPP, and a native Port. Games were fully playable
with audio and the device volume controls, and each exited directly back to the
custom launcher. The measured interval from game-process end to the next first
launcher frame was 27--29 ms.

## Native system actions

The launcher uses the same narrow exit-code handoff for its remaining system
actions. Shutdown calls muOS's proven poweroff path directly, without entering
the stock frontend. PortMaster waits for the normal audio/controller runtime,
loads and connects the RG34XX-SP network only when selected, runs PortMaster,
then disconnects services, unloads the Wi-Fi device, restores launcher ownership
and redraws the custom menu. Network setup therefore adds no work to boot.

Both hardware tests passed: PortMaster connected on demand and installed ROTA,
existing games still launched, and Shutdown powered the device off directly.
The following boot entered the launcher at 2.307 seconds and finished its first
interactive frame at 2.326 seconds.

## Persistent library state

The v6 proof added ROTA to the five-title embedded catalog and turned Favorites
into a real view. Y toggles the selected title. Favorites are stored as exact ROM
paths in an atomically replaced text cache, so rebuilding or reordering the
compiled catalog cannot silently point a favorite at the wrong game. The cache
loads asynchronously only after storage is ready and never delays first frame.
Each launch also atomically records the exact most-recent path for the later
History/Resume decision. Per-boot launcher logs are archived by kernel boot ID
so a later shutdown no longer overwrites evidence from a PortMaster or game run.

The hardware proof persisted ROTA across a reboot, launched it from Favorites,
removed other favorites correctly, and recorded Goof Troop as the latest path.
The larger build still entered at 2.256 seconds and drew its first interactive
frame at 2.276 seconds. Favorites loaded at 3.677 seconds, after first frame and
only 40 ms after the ROM root became visible.

## Nonblocking boot-effects proof

The first boot process draws the complete interactive menu before beginning a
procedural accent line. Input ends the animation immediately, and game returns
do not replay it. No images, decoder, timer service, compositor or new launcher
library is involved.

`generate-boot-sound.py` deterministically produces a 320 ms, 48 kHz, 16-bit
mono WAV. The supervisor waits in parallel for the normal system-ready marker,
PipeWire socket and exact asset path, then uses muOS's existing audio player. It
cancels the pending sound on game, PortMaster, stock or shutdown handoff. This
first audio proof deliberately preserves the known-good PipeWire setup; a later
profile will decide whether replacing the player is worth its dependency cost.

The v7 hardware run kept first frame at 2.275--2.356 seconds, proved input skip,
played the chime normally, and cancelled it when a game was opened. It also
exposed two useful refinements: the later saved-brightness restore visually
split the line, and `mpv` remained alive for roughly 4.7 seconds to play a
320 ms file.

The v8 proof leaves the menu immediately usable but holds decorative motion
until the device-start brightness case emits an exact readiness marker. It then
redraws once at the final brightness and runs a shorter 1.6-second accent. The
sound wrapper prefers `pw-play`, then `aplay`, with the proven `mpv` path only as
a fallback; logs record the selected player and total lifetime. Hardware logs
showed that `pw-play` saw the PipeWire socket before a target sink existed,
failed after roughly 2.2 seconds, and only then invoked `mpv`. That explained
why the chime arrived after the animation.

The v9 build removes brightness handling from the boot experience rather than
choosing a card-side percentage. `device/start.sh` no longer performs its late
saved-brightness restore, so the firmware-established brightness remains stable
until the user changes it manually. The 1.6-second animation starts with the
first interactive frame again. Input still intentionally completes and removes
the decorative animation immediately; this is an explicit interaction policy,
not an accidental repaint side effect. The sound wrapper invokes the proven
`mpv` path directly, eliminating the known failing-player delay while keeping
game-launch cancellation.

## Permanent launcher shell

The v10 build removes the proof's two-minute automatic handoff to stock. The
launcher now remains the permanent shell until the user launches content,
selects a system action, or explicitly presses B on the main menu for recovery.

Hardware testing also proved that the apparent late display repaint was the
launcher's own ROM-readiness callback. Storage and Favorites became ready at
3.69--4.40 seconds and `probe_storage()` unnecessarily called `draw_screen()`.
The callback now changes state and logs readiness without drawing. The next
user action naturally renders the current state, so background storage work
cannot overwrite the foreground or interrupt unrelated visual effects.
