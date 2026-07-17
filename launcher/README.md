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
off to stock after the system-ready marker; a two-minute timeout provides the
same fallback. D-pad navigation wraps so every direction press visibly moves.

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
