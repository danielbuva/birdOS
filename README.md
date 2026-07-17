# RG34XX-SP bespoke muOS work

This repository contains the host-side sources and installation hooks used to
profile and convert muOS 2601.1 into a fixed-purpose RG34XX-SP system.

## Measured state

- Fresh-card stopwatch baseline: approximately 19.1 seconds.
- Current stopwatch result after Wi-Fi module deferral: approximately 10.44 seconds.
- Pre-font internal input-ready average: 9.84 seconds.
- English-only-font internal input-ready average: 9.60 seconds.
- Current internal input-ready average: 8.92 seconds.

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
- PortMaster requests a network connection when launched.
- Sounds, low-power monitoring, USB setup, device-control refresh, and SDL-map
  refresh deferred until after frontend startup.
- Early entropy retained: deferring haveged delayed kernel CRNG readiness and
  caused PipeWire/SDL audio to block the frontend until 12-14 seconds.

## Font payload

Run `./build-font-stubs.sh` on macOS to compile the five AArch64 relocatable
objects. The device-side user-init hook links them with the target system's own
GNU linker, then installs the resulting shared libraries.

## Important files

- `99-frontend-native-log.sh`: persistent installer and diagnostic collector.
- `PortMaster.sh`: PortMaster launcher with on-demand Wi-Fi.
- `font-stubs/`: source and AArch64 object payloads for unused language fonts.
- `ROADMAP.md`: target architecture and project sequence.

The untouched recovery card remains the authoritative known-good system.
