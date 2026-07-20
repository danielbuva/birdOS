# Dani's fixed RG34XX-SP operating system

This repository contains the host-side sources and installation hooks used to
profile and convert muOS 2601.1 into a fixed-purpose RG34XX-SP operating
system. muOS is now the compatibility foundation, not the product boundary.

The governing priority is: boot latency, interaction latency, battery
efficiency, memory efficiency, then exact user features. Generality is a cost,
not a feature. Every persistent process, wake-up, probe, parser and loaded byte
must serve this one device and this one experience.

## Measured state

- Fresh-card stopwatch baseline: approximately 19.1 seconds.
- Optimized-stock stopwatch checkpoint: 10.25 seconds (10.35, 10.30, 10.10).
- Pre-font internal input-ready average: 9.84 seconds.
- English-only-font internal input-ready average: 9.60 seconds.
- Optimized-stock internal input-ready average: 8.43 seconds.
- The two latest pre-`switch_root` supervisor starts are at 2.00 and 2.06
  seconds of kernel uptime.
- Their interactive frames are at 2.029 and 2.082 seconds, with input ready on
  both frames; permanent-root startup begins later at 2.25--2.30 seconds.
- Current LED-on stopwatch result: approximately four seconds.

The boot image now starts the launcher from initramfs after mounting the fixed
root but before `switch_root`. The launcher and its input descriptors survive
the handoff, while the later root startup sees the existing supervisor and does
not start a duplicate. The next staged proof replaces the generic initramfs
shell with a static fixed-device init while retaining the existing root PID 1
as its fallback second phase.
The long-term target is a reproducible fixed-device image, not a collection of
card-side patches.

## Current changes

- Early ROM mount.
- Frontend/audio readiness gate removed while PipeWire remains available.
- Historical detailed sysinit, mount, frontend and process logs retained;
  continuous observers are being replaced by explicitly armed diagnostic runs.
- The launcher blocks on evdev after storage readiness instead of waking 250
  times per second, and ordinary boots no longer record every raw input event.
- Maintenance and log copying moved away from the UI critical path.
- Emulator verification deferred and cached by OS build.
- Five unused multilingual font DSOs replaced by tiny AArch64 stubs.
- Boot Wi-Fi and Chrony disabled; Wi-Fi remains available on demand.
- General device initialization no longer loads rtl8821cs; the explicit network
  path loads the Wi-Fi module when requested.
- Kernel module metadata is rebuilt only if the fixed kernel's cached
  `modules.dep` database is missing.
- The custom launcher supervisor loads the network only around PortMaster.
- The fixed launcher starts before udev, renders directly to both framebuffer
  pages, and reads the built-in evdev device without SDL or joystick services.
- The staged early-root proof starts it before `rcS`; duplicate-start protection
  lets the existing sysinit entry remain as a fallback during hardware testing.
- The boot-image candidate is hardware-verified with sub-four-second stopwatch
  results. It embeds the freestanding executable in initramfs, starts it after
  the fixed root mount, and crosses `switch_root` only after the interactive
  frame.
- Its embedded catalog remains browsable while ROM storage mounts concurrently.
- The real cache contains 5,953 games across 27 systems; artwork and metadata
  stay out of the boot executable.
- Home is fixed to Play, Listen, Read and Watch. The same generated cache now
  embeds three audio files and six films, while Read remains an intentional
  empty destination until its reader policy is fixed.
- Local audio and video launch through the exact firmware's existing MPV bridge
  and controller map, then return to the selected cached media row.
- SNES, PSP, and native Port launch/return paths work with audio and volume.
- PortMaster and shutdown run directly without entering the stock frontend.
- Persistent Favorites and most-recent path tracking are hardware-verified.
- ROM/Favorites readiness updates state without asynchronously repainting the
  launcher, and the permanent shell no longer times out into stock.
- The animation and MPV-chime proofs are removed from the active path until the
  earliest interactive-menu architecture is complete. Final effects come later.
- Low-power monitoring, USB setup, device-control refresh and SDL-map refresh
  remain post-menu compatibility work and are candidates for fixed/on-demand
  replacement.
- Early entropy retained: deferring haveged delayed kernel CRNG readiness and
  caused PipeWire/SDL audio to block the frontend until 12-14 seconds.
- The stock 8.17 GiB image now has an exact partition map and verified offline
  extraction workflow. Its Android boot v2 payload round-trips byte-for-byte;
  a raw-25 `lcd_backlight` DTB candidate was verified, installed and found not to
  control the visible RG34XX-SP boot level. The real backlight path is now being
  profiled through the Allwinner `disp0 getbl/setbl` interface. Early hardware
  traces identify U-Boot's separate raw-50 DTB value as the actual handoff owner.

The cached-module test reported `cached`, and the complete post-change
functionality test passed. The optimized-stock checkpoint remains in Git; the
active card now boots the custom launcher as its normal frontend.

## Font payload

Run `./build-font-stubs.sh` on macOS to compile the five AArch64 relocatable
objects. The device-side user-init hook links them with the target system's own
GNU linker, then installs the resulting shared libraries.

Double-click `/Users/dani/Desktop/Rebuild Dani SP Library.command` whenever the
card's library changes. It inventories the mounted card, regenerates the
embedded cache, compiles the AArch64 object, verifies every staged copy and
writes a content revision that user-init installs on the next boot.

## Important files

- `99-frontend-native-log.sh`: development-only persistent installer; it will
  disappear from the production image after rootfs changes are baked in.
- `PortMaster.sh`: captured PortMaster reference; the on-demand network boundary
  lives in `launcher/S03danilauncher`.
- `font-stubs/`: source and AArch64 object payloads for unused language fonts.
- `ROADMAP.md`: target architecture and project sequence.
- `DEVICE_PROFILE.md`: fixed hardware and experience contract.
- `INPUT_MAP.md`: confirmed logical control bitmasks and muOS calibration notes.
- `launcher/`: dependency-free direct-framebuffer launcher proof.
- `firmware/`: exact stock partition map, checksums and reproducible offline
  image inspection tools.
- `generate-boot-sound.py`: archived deterministic source for the completed
  chime proof; it is not staged on the active boot path.

The untouched recovery card remains the authoritative known-good system.
