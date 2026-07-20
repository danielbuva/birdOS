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
- The latest static-`/init` supervisor starts are at 1.93, 1.96 and 1.94
  seconds of kernel uptime.
- Their interactive frames are at 1.957, 1.980 and 1.964 seconds, with input
  ready on every frame; permanent-root startup begins later at 2.18--2.20.
- Three static-root-PID-1 boots explicitly recorded the new init marker,
  produced input-ready frames at 2.032--2.103 seconds, launched content and
  shut down normally. As expected for post-frame work, stopwatch boot time
  remained approximately 3.8 seconds.
- Current LED-on stopwatch range: approximately 3.5--3.8 seconds.

The boot image now starts the launcher from initramfs after mounting the fixed
root but before `switch_root`. The launcher and its input descriptors survive
the handoff, while the later root startup sees the existing supervisor and does
not start a duplicate. The generic initramfs shell is now replaced by a
6,424-byte static fixed-device init, with the verified shell retained as
`/init.stock`. The remaining root BusyBox PID 1 is also replaced by a
hardware-verified 5,128-byte blocking static init; BusyBox remains available
only as feature-triggered applets and as the automatic root-init fallback.
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
- The active boot image hardcodes the exact SD root and mount sequence in a
  freestanding C `/init`. Its full 64 MiB image rebuilds byte-for-byte and is
  hardware-verified with no recovery activation.
- A two-byte U-Boot package change is installed and raw-verified, making
  frame-zero through menu inherit raw brightness 3/255 with no userspace
  display write. This is 1.18% of the raw range, not a claim of linear panel
  luminance or the same scale used by manual brightness controls.
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
- Cold libretro handoff is now measured separately. The profiler attributes
  1.63 seconds to the generic SDL/controller scan, 0.20 seconds to remaining
  shell/config work and 5.67 seconds after RetroArch exec before its no-op color
  stage appears. Warm equivalents are 0.04, 0.20 and 1.79 seconds. The fixed
  direct bridge passed complete functionality testing but remained perceptibly
  slow, so further game-load work is documented and deferred.
- The behavior-preserving udev inventory is complete. A no-udev proof retained
  the menu and shutdown but exposed current `/run/udev` dependencies in
  RetroArch/MPV input, ALSA setup and system hotkeys. Explicit Mali probing
  consumes about 1.10 seconds of the former 1.51 seconds. The 1.35-second
  input/sound-only replay restored functionality. The one-shot variant failed
  to terminate udevd cleanly and broke MPV's `gptokeyb2`-injected rich controls,
  while its global close/volume/brightness controls still worked. The verified
  resident minimal bridge is restored; it remains fully outside and after the
  interactive launcher. PortMaster/network remains a deferred check at the
  configured home network.
- The first fixed-storage proof is staged. It replaces the two resident
  UnionFS-FUSE processes with kernel bind mounts from this card at the same
  `/mnt/union/ROMS` and `/mnt/union/ports` compatibility paths. The exFAT mount
  and `/run/muos/storage` binds are deliberately unchanged for this test.
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
- `userspace/`: fixed-service profiling and replacement stages, beginning with
  the behavior-preserving udev pre/post inventory.
- `storage/`: checksum-gated single-card mount and UnionFS replacement stages.
- `ROADMAP.md`: target architecture and project sequence.
- `GAME_LOAD_DEFERRED.md`: parked cold-game findings and resume-later build
  checklist.
- `POWER_BUTTON_DEFERRED.md`: confirmed PMIC turn-on threshold values and the
  final-firmware 128 ms hardware proof plan.
- `DEVICE_PROFILE.md`: fixed hardware and experience contract.
- `INPUT_MAP.md`: confirmed logical control bitmasks and muOS calibration notes.
- `launcher/`: dependency-free direct-framebuffer launcher proof.
- `firmware/`: exact stock partition map, checksums and reproducible offline
  image inspection tools.
- `generate-boot-sound.py`: archived deterministic source for the completed
  chime proof; it is not staged on the active boot path.

The untouched recovery card remains the authoritative known-good system.
