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
- The static-`/init` launcher record remains 1.957 seconds to an input-ready
  frame. The accepted direct-handoff boot produced its frame at 1.98 seconds,
  while permanent-root sysinit begins concurrently at 1.97 seconds and remains
  outside the first-frame dependency path.
- Three static-root-PID-1 boots explicitly recorded the new init marker,
  produced input-ready frames at 2.032--2.103 seconds, launched content and
  shut down normally. As expected for post-frame work, stopwatch boot time
  remained approximately 3.8 seconds.
- Current LED-on stopwatch range: approximately 3.5--3.8 seconds. The accepted
  direct-handoff boot records an ordinary interactive marker at 1.98 seconds;
  the latest hardware pass was approximately 3.8 seconds by stopwatch.
- Fixed-root-coordinator behavior test: all functionality passed with
  sub-3.8-second stopwatch boots. Its latest trace records an input-ready frame
  at 2.06 seconds, system-ready at 4.24 and audio ready at 6.02.
- The exact ROCKNIX stable source chain now rebuilds offline with its executed
  30-patch order and shipping broad configuration. Its RG34XX-SP DTB is
  byte-identical to the physically accepted release. The first Bird-enabled
  untrimmed 7.0.11 candidate reached a drawn frame at 1.547 seconds and mounted
  the customized root. Its remaining failure was localized to framebuffer
  console ownership, a hardcoded vendor input-event number and the old root's
  `mali_kbase` request. V2 fixed framebuffer ownership and rejected the wrong
  volume-key input node, but then exposed an incomplete source audit: ROCKNIX
  supplies the DTB's H700 joypad driver as a separate GPL package, not in its
  30 Linux patches. Without it the launcher never reached input readiness and
  the 20-second watchdog restarted the same sole boot label. V3 pins that
  package, loads its 37,248-byte module before launcher dispatch and paints
  before input discovery while still withholding the usable marker until the
  correct gamepad opens. Its two clean full kernel builds are byte-identical,
  and the guarded updater has staged it on BIRD p1 without writing p5 or p6.

The boot image now starts the launcher from initramfs after mounting the fixed
root but before `switch_root`. The launcher and its input descriptors survive
the handoff, while the later root startup sees the existing supervisor and does
not start a duplicate. The generic initramfs shell is now replaced by a
6,424-byte static fixed-device init, with the verified shell retained as
`/init.stock`. The remaining root BusyBox PID 1 is also replaced by a
hardware-verified 5,128-byte blocking static init; BusyBox remains available
only as feature-triggered applets and as the automatic root-init fallback.
The accepted first init now performs the successful `switch_root` sequence by
direct system calls as well, so BusyBox is no longer PID 1 in either normal
boot phase.
The long-term target is a reproducible fixed-device image, not a collection of
card-side patches.

## Current changes

- Early ROM mount.
- Frontend/audio readiness gate removed. The session-warm stage is verified:
  menu input was ready at 2.11 seconds, audio started at 3.97, D-Bus completed
  at 4.22 and PipeWire/WirePlumber completed at 6.31. All tested functionality
  passed, and immediate selections join the same locked startup.
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
- A later game request at 18.84 seconds proved audio had already been ready for
  more than 12 seconds, excluding audio initialization from that perceived
  delay. The generic 8--20-second startup jobs have since been removed and the
  resulting complete game/media/control behavior test passed.
- A reported first Flycast/RetroArch exit pause is not launcher restoration:
  after the content process actually exited, the supervisor restarted the
  launcher and drew its prior screen in about 32 ms. Core/frontend teardown is
  now recorded with the deferred cold-game work.
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
- The fixed-storage path is hardware-verified. It replaces the two resident
  UnionFS-FUSE processes with kernel bind mounts from this card at the same
  `/mnt/union/ROMS` and `/mnt/union/ports` compatibility paths; diagnostics
  confirmed exact exFAT binds and no UnionFS PID. Its final self-persisted proof
  is complete and it is unchanged by the current batch.
- The Linux-DTB 128 ms power-key candidate is raw-verified and functional: a
  normal quick tap now powers on the device. Because Linux programs the PMIC
  for the next cold start, this result becomes valid only after the candidate
  has booted and the device has shut down normally. The same lower threshold
  should advance the PMIC power-accepted/green-LED boundary by about 384 ms.
- The first entropy-lifecycle proof retained haveged because the 256-bit
  counter condition stayed false even after the kernel logged CRNG readiness.
  A revised independent stage now keys termination to the kernel's explicit
  `random: crng init done` event and persists its final PID proof itself.
- ROM/Favorites readiness updates state without asynchronously repainting the
  launcher, and the permanent shell no longer times out into stock.
- The animation and MPV-chime proofs are removed from the active path until the
  earliest interactive-menu architecture is complete. Final effects come later.
- Low-power monitoring remains for battery safety. The verified startup-tail
  pass removes per-boot USB setup, device-control/SDL rewrites, catalogue
  generation, sound preparation, recursive SSH permission repair and log
  cleanup; its full functionality test passed.
- Fixed WirePlumber overrides now disable camera, V4L2, MIDI, Bluetooth and
  logind discovery while retaining ALSA and normal policy/routing. Their full
  functionality test passed.
- The current card batch replaces the remaining generic root startup
  coordinator with a fixed RG34XX-SP script. It removes factory-reset,
  first-boot, HDMI and alternate-board branches, dispatches only the proven
  device/storage/audio workers and starts global hotkeys before storage binding
  completes. Content readiness still waits for the fixed mount marker.
- The accompanying explicitly armed process snapshot now waits until the ROM
  mount exposes its arm file, captures once after the system settles, and
  removes its own rootfs hook after success.
- That snapshot completed at 24.08 seconds. It confirms exact exFAT bind mounts,
  no UnionFS or haveged process, roughly 61 MiB used beyond `MemAvailable`, and
  the remaining udev, hotkey, lid, idle, battery and session-audio workers.
- Eight independent generic runtime scripts are now replaced by fixed
  RG34XX-SP policy, and the complete functionality pass succeeded at about
  3.5 seconds by stopwatch. The first installer attempt safely
  refused every write when its device-start checksum did not match the active
  card; the settled snapshot supplied the exact replacement guard. The
  compiled `muhotkey` event source remains, while its shell wrapper loses
  RGB/network/alternate-board logic; lid and battery checks lose repeated
  configuration discovery; the five-second all-process idle scan is
  eliminated. Module loading and user-init dispatch are also reduced to this
  device's exact paths.
- Fixed startup v2 removes per-boot writes for immutable display geometry and
  policy, the obsolete update-file delete, the zero-swap probe and a redundant
  squashfs module request. Those constants are applied once by the installer;
  the hardware functionality pass succeeded.
- The next reproducible boot-image candidate reduces the compressed initramfs
  from 2,772,302 to 1,725,023 bytes (37.8%). It removes the 2.94 MB magic
  database, 100 generic ALSA profiles, filesystem-creation/FAT/CIFS/serial
  utilities and their unused libraries. A direct ext4-superblock test skips
  `e2fsck` only for a clean filesystem; dirty, error-marked or unreadable roots
  retain the existing automatic repair path. Hardware functionality passed;
  decompression fell from roughly 159 to 95 ms and initrd memory from 2,704 to
  1,684 KiB.
- The accepted direct-handoff candidate replaces the successful-path BusyBox
  `switch_root` execution with 1,672 bytes of fixed direct-syscall code in the
  static first init. It deletes only the old initramfs filesystem, preserves
  the mounted `/mnt` root, moves/chroots it and executes the static PID 1.
  BusyBox and `/init.stock` remain solely for pre-handoff recovery. Three
  independent builds—incremental and single-pass—produce exact SHA-256
  `da5549e1cdad5b9f445f4634dacc0254fd468148182175a06b43346dc1dddbc7`.
  Hardware acceptance passed the launcher, controls, content and shutdown;
  diagnostics recorded both direct-handoff and clean-root-skip markers.
- Kernel specialization has begun from evidence, not a generic defconfig. The
  active 17,686,536-byte Linux 4.9.170 `Image` contains its complete 4,209-line
  config, now extracted and checksum-pinned. A case-sensitive amd64 Linux build
  environment uses the closest public Orange Pi `sun50iw9` lineage and exact
  Linaro GCC 5.3.1 release. That public tree is not the complete downstream
  source: normalizing the active config removes the AXP2202 power driver, newer
  sunxi audio stack and exFAT implementation. Its output is therefore a source
  comparison only and will not be put on the card. A one-boot post-menu
  inventory is staged to capture the running modules, interrupts, I/O map,
  devices and live DTB before constructing the auditable fixed-device kernel.
- The first exact-chain Bird candidate is ready without touching the current
  card. Its deterministic FAT contains only the source-built 7.0.11 kernel,
  shipping-identical RG34XX-SP DTB and extlinux policy. It preserves the proven
  ROCKNIX DDR4 SPL/U-Boot/TF-A and changes exactly the 156 MiB prefix before
  the existing root; p5 and the 503 GB p6 library remain in place. A
  checksum-gated installer and independent prefix-only restore path are staged.
- The 1,122-line card-side migration engine has completed its job. The staged
  replacement is a 45-line diagnostics-only collector with no old patch guards
  or 18--25-second log-copy sleepers.
- Early entropy retained: deferring haveged delayed kernel CRNG readiness and
  caused PipeWire/SDL audio to block the frontend until 12-14 seconds.
- Storage has no CRNG dependency. Entropy, fixed storage and post-menu audio
  therefore run concurrently; only audio's own random request may wait for the
  CRNG, never the launcher or storage path.
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
- `POWER_BUTTON_DEFERRED.md`: staged PMIC 128 ms candidate, ownership caveats
  and the hardware proof/result.
- `DEVICE_PROFILE.md`: fixed hardware and experience contract.
- `INPUT_MAP.md`: confirmed logical control bitmasks and muOS calibration notes.
- `launcher/`: dependency-free direct-framebuffer launcher proof.
- `firmware/`: exact stock partition map, checksums and reproducible offline
  image inspection tools.
- `kernel/`: extracted active config, pinned vendor source/toolchain build and
  the fixed-device kernel acceptance workflow.
- `generate-boot-sound.py`: archived deterministic source for the completed
  chime proof; it is not staged on the active boot path.

The untouched recovery card remains the authoritative known-good system.
