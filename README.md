# RG34XX-SP bespoke muOS work

This repository contains the host-side sources and installation hooks used to
profile and convert muOS 2601.1 into a fixed-purpose RG34XX-SP system.

## Measured state

- Fresh-card stopwatch baseline: approximately 19.1 seconds.
- Optimized-stock stopwatch checkpoint: 10.25 seconds (10.35, 10.30, 10.10).
- Pre-font internal input-ready average: 9.84 seconds.
- English-only-font internal input-ready average: 9.60 seconds.
- Optimized-stock internal input-ready average: 8.43 seconds.
- Current direct-launcher process entry: 2.256 seconds of kernel uptime.
- Current first interactive frame: 2.276 seconds, 20 ms after process entry.
- Current LED-on stopwatch result: approximately four seconds.

Diagnostics remain enabled. The long-term target is a small custom launcher
with fixed RG34XX-SP hardware, English text, embedded assets, a cached game
index, on-demand networking, and a reproducible firmware image.

## Current changes

- Early ROM mount.
- Frontend/audio readiness gate removed while PipeWire remains available.
- Detailed sysinit, mount, frontend, process, and native frontend logging.
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
- Its embedded catalog remains browsable while ROM storage mounts concurrently.
- SNES, PSP, and native Port launch/return paths work with audio and volume.
- PortMaster and shutdown run directly without entering the stock frontend.
- Persistent Favorites and most-recent path tracking are hardware-verified.
- ROM/Favorites readiness updates state without asynchronously repainting the
  launcher, and the permanent shell no longer times out into stock.
- The boot-effects proof animates only after the usable frame and starts a tiny
  preconverted PCM chime only after the normal audio route is ready. The later
  muOS brightness restore is removed, leaving the firmware-established level
  unchanged until a manual adjustment. Final effects move to firmware later.
- Sounds, low-power monitoring, USB setup, device-control refresh, and SDL-map
  refresh deferred until after frontend startup.
- Early entropy retained: deferring haveged delayed kernel CRNG readiness and
  caused PipeWire/SDL audio to block the frontend until 12-14 seconds.

The cached-module test reported `cached`, and the complete post-change
functionality test passed. The optimized-stock checkpoint remains in Git; the
active card now boots the custom launcher as its normal frontend.

## Font payload

Run `./build-font-stubs.sh` on macOS to compile the five AArch64 relocatable
objects. The device-side user-init hook links them with the target system's own
GNU linker, then installs the resulting shared libraries.

## Important files

- `99-frontend-native-log.sh`: persistent installer and diagnostic collector.
- `PortMaster.sh`: captured PortMaster reference; the on-demand network boundary
  lives in `launcher/S03danilauncher`.
- `font-stubs/`: source and AArch64 object payloads for unused language fonts.
- `ROADMAP.md`: target architecture and project sequence.
- `DEVICE_PROFILE.md`: fixed hardware and experience contract.
- `INPUT_MAP.md`: confirmed logical control bitmasks and muOS calibration notes.
- `launcher/`: dependency-free direct-framebuffer launcher proof.
- `generate-boot-sound.py`: deterministic source for the tiny PCM boot chime.

The untouched recovery card remains the authoritative known-good system.
