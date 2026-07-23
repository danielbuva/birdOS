# Dani's fixed RG34XX-SP operating system

This repository contains the host-side sources and installation hooks that
began by profiling and converting muOS 2601.1 into a fixed-purpose RG34XX-SP
operating system. The active compatibility-reset candidate boots the exact
ROCKNIX 20260701 kernel, immutable system, writable configuration baseline and
service graph, but replaces its frontend with Bird. The accepted v5.4
permanent-initramfs system remains the automatic recovery path while this full
application contract is proven and then reduced.

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
- Current clean-root LED-on stopwatch result: approximately 2.5 seconds. V5.2
  recorded pixels at 1.137 seconds and direct input ready at 1.294 seconds of
  Linux uptime; the remaining stopwatch interval is primarily pre-kernel.
- Stock-root v6.1 is staged as a deliberate compatibility baseline, not a timing
  candidate. It restores the byte-identical ROCKNIX kernel/SYSTEM/STORAGE set,
  systemd, udev, D-Bus, PipeWire, WirePlumber, Sway-on-content and all H700
  quirks. Bird starts through ROCKNIX's normal UI-service slot after that graph
  is ready. The first physical boot proved the menu and PortMaster handoff but
  found that per-item readiness still tested cached `/mnt/mmc` paths. V6.1 maps
  only those live probes into the mounted ROCKNIX namespace.
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
  and the guarded updater staged it on BIRD p1 without writing p5 or p6. The
  physical v3 gate then drew at 1.586 seconds and opened `H700 Gamepad` at
  1.750 seconds; menu controls and shutdown worked. Content failures were
  localized to the preserved userspace's vendor Mali/ION ABI, not early input
  or the source kernel's DRM, sound or storage devices. V4 retained the fast
  path (frame visible at 1.400 seconds, correct input at 1.553 and storage at
  2.010) but its optional PortMaster policy bind aborted every selected item
  before application `exec`. Later compatibility candidates reached native
  RetroArch and MPV, but their mixture of muOS launch policy, configuration,
  cores and libraries with newer applications remained incoherent. V4.5
  finally proved the boundary: native RetroArch loaded content, then failed its
  SDL KMSDRM context while MPV decoded without restoring the required user
  experience. That hybrid route is closed.
- Bird clean-root v5.0 passed its boot architecture gate: the menu painted at
  1.135 seconds, direct H700 input opened at 1.290, p6 mounted at 1.40,
  Panfrost was ready at 1.42 and the immutable application runtime was ready at
  2.08 seconds. Menu controls, improved brightness and shutdown work. Its
  native application gate failed because the runtime had a read-only `/tmp`,
  RetroArch lacked its required fixed libudev property and inherited the wrong
  graphics policy, while MPV lacked a direct-display and Bird input policy.
  These are measured post-menu session defects, not a regression in the fast
  permanent-root boot.
- Clean-root v5.1 passed the launcher and application-entry boundary, but its
  physical content test exposed two shared session defects. RetroArch and
  Flycast ran in slow motion because a forced Mesa driver bypassed the H700's
  native sun4i-KMS/Panfrost render-node pairing and selected CPU `softpipe`.
  RetroArch and MPV both opened ALSA but produced no sound because Bird had not
  yet programmed the fixed H616 DAC/Line-Out/speaker route. MPV's first frame
  could advance after seeking, confirming that decode and direct DRM output
  were alive; its SDL trigger-up events were also proven unreliable.
- Clean-root v5.2 passed the hardware-rendering, direct-audio and fixed-control
  boundary. RetroArch logs identify the Mali-G31 Panfrost renderer, MP3 audio
  is clean, and menu, brightness, volume, exit and shutdown work at the new
  roughly 2.5-second stopwatch result. The same test exposed application
  policy rather than boot defects: Dreamcast used modern Flycast instead of
  the H700 low-end build, DS used melonDS/FreeBIOS instead of DraStic, PPSSPP
  libretro segfaulted, Ports were unimplemented, and MPV's software DRM path
  dropped frames.

The accepted vendor-root checkpoint started the launcher from initramfs after
mounting p5 and carried it across `switch_root`. Clean-root v5.0 removes that
handoff: the initramfs is Bird's permanent root. A 5,432-byte static first init
starts the launcher, then becomes a 5,112-byte static permanent PID 1 after the
input-ready frame. BusyBox remains an interpreter and utility provider for
post-frame scripts and explicit recovery; it is not PID 1 or a prerequisite for
the usable menu. The verified old shell remains `/init.stock` for deliberate
recovery builds while this hardware gate is open.
The long-term target is a reproducible fixed-device image, not a collection of
card-side patches.

## Current changes

- The active experiment is stock-root v6.1. It stops fixing isolated ABI failures
  in the clean root and restores the coherent ROCKNIX application environment
  first. Its release KERNEL and SYSTEM are byte-identical to 20260701, and its
  writable STORAGE starts from the captured exact configured ext4 image.
- Bird is temporarily a normal systemd UI service. ROCKNIX initializes its
  complete H700 hardware and service contract, writes only `essway.service` as
  the selected boot UI, and starts the unchanged Sway compositor on demand
  around content. Selections use the release's own `runemu.sh`, platform/core
  identities, standalone wrappers and configuration generators.
- P5 and the large library remain untouched. The exact writable filesystem is
  loop-mounted from p6; the existing ROM and BIOS trees are bind-mounted into
  its expected namespace. The accepted v5.4 clean-root kernel is retained on
  p1 and automatically selected after two failed stock-root starts.
- Cached catalogue identities remain provider-independent. Bird now resolves
  `/mnt/mmc` to `/storage/bird-data` for live file checks, while the separate
  runner performs the same mapping at application handoff. Existing writable
  ROCKNIX storage is preserved across Bird-only deployments.
- Once the broad physical compatibility gate passes, Bird moves progressively
  earlier again and services are removed or deferred one measured closure at a
  time. V5.4 remains the accepted speed architecture and evidence base, not
  discarded work.
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
- The historical early-root proof started it before `rcS`; duplicate-start protection
  lets the existing sysinit entry remain as a fallback during hardware testing.
- The boot-image candidate is hardware-verified with sub-four-second stopwatch
  results. It embeds the freestanding executable in initramfs, starts it after
  the fixed root mount, and crosses `switch_root` only after the interactive
  frame.
- The accepted vendor-root image hardcoded the exact SD root and mount sequence in a
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
- Historical source-kernel compatibility v4.1 kept that post-frame udev bridge separate
  from the launcher and adds no work to the interactive-menu path. Only after
  a content selection, the supervisor mounts a checksum-pinned ROCKNIX
  SquashFS read-only and exposes the narrow SDL2 KMSDRM plus Mesa/Panfrost ABI
  needed by the unchanged muOS applications. An empty `libmali.so.0` SONAME
  satisfies their redundant vendor dependency without loading the ION/Mali
  driver, the brightness helper now targets standard backlight sysfs, and NDS
  uses the runtime's melonDS libretro core instead of the vendor DraStic JIT
  that trapped on the source kernel. The full runtime image is a compatibility
  proof; after hardware acceptance it will be reduced to the exact dependency
  closure Bird actually uses. The first v4 physical pass did not exercise this
  graphics stack: an optional PortMaster bind failed after the runtime mounted
  and returned every selection to Bird before `exec`. V4.1 removes that bind
  from the common launch path and installs the fixed PortMaster policy directly
  on p6. It also replaces the 4.9-specific `muhotkey` watcher with a separate
  6,160-byte mainline input service, dispatched after the first frame. It opens
  the known gamepad, volume and PMIC keys by device name, blocks in `ppoll`,
  never grabs them from applications, and owns only volume,
  Menu+volume brightness and power suspend.
- The v4.1 physical pass proved that content now reaches `exec`, then exposed
  one fixed-device mismatch shared by RetroArch, MPV, PPSSPP and SDL-linked
  PortMaster/FRT games. Panfrost is render-only DRM `card0`, while sun4i-drm
  owns the panel as `card1`; SDL's default probe therefore reports KMSDRM
  unavailable or renders no visible frame. V4.2 exports
  `SDL_KMSDRM_DEVICE_INDEX=1` only in the on-demand content environment. It
  also writes the separate controls service's device discoveries and applied
  brightness, volume and suspend actions to the delayed persistent dmesg
  capture. Neither operation joins the launcher or first-frame dependency path.
- The v4.2 device pass confirmed direct brightness control, but selecting
  `card1` in userspace did not repair the shared application display path:
  RetroArch still reported KMSDRM unavailable and MPV continued decoding into
  an invisible software-converted surface. V4.3 fixes the topology instead.
  Sun4i remains built in and claims display `card0`; the exact Panfrost module
  plus its two DRM helpers are preserved across `switch_root` and warmed
  automatically by the existing post-frame device stage. This work overlaps
  input/sound replay after the menu is usable. Content selection only waits for
  `renderD128` if the user gets there before warm-up finishes; it never loads
  the GPU. One diagnostic cycle keeps SDL video and loader tracing enabled.
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
- The accepted vendor-root batch replaced the remaining generic root startup
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
- Kernel specialization began from evidence, not a generic defconfig. The
  vendor-oracle 17,686,536-byte Linux 4.9.170 `Image` contains its complete 4,209-line
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

The historical cached-module test reported `cached`, and that optimized-stock
functionality checkpoint remains in Git. The card currently advances through
the clean-root native-application gate; v5.3 and the accepted v5.2, v5.1, v5.0
and v4.5 kernels are preserved on p6 as staged.

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
