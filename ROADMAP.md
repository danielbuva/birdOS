## Summary of the idea

You are turning muOS from a flexible general-purpose firmware into a **purpose-built RG34XXSP console OS** tuned for exactly one device, one language, one visual identity, one control layout and one game library.

Instead of discovering and configuring everything during every boot, the system should already know:

* RG34XXSP hardware and controls
* English-only text and font
* Fixed screen layout and wallpaper
* Fixed boot animation and sound
* Exact ROM locations
* Exact emulator/core for each game
* The menu page shown at startup
* Which services are actually necessary

The target experience is:

```text
Power button
→ interactive text menu at the earliest hardware-supported instant
→ cached collection is immediately browsable
→ essential storage and runtime setup finish asynchronously
→ selected content becomes launchable
→ optional effects appear only if the final experience benefits from them
```

The long-term centerpiece would be a tiny custom launcher—ideally a small statically linked program—that replaces the heavier general-purpose frontend while retaining muOS underneath for hardware support, emulator launching, PortMaster, power controls and other useful infrastructure.

## Active compatibility reset

Clean-root v5.4 proved the desired fast architecture but also proved that an
application stack cannot be reconstructed reliably by copying binaries and
guessing its hidden service and configuration contract one failure at a time.
Stock-root v6.18 now optimizes the proven software baseline:

- exact ROCKNIX 20260701 KERNEL, DTB, SYSTEM and configured STORAGE;
- complete systemd, udev, D-Bus, PipeWire, WirePlumber and H700 autostart path;
- Bird substituted for EmulationStation through the ordinary UI-service slot;
- stock Sway and stock `runemu.sh` started only around selected content; and
- automatic return to the accepted v5.4 clean root after two failed starts.

The v6.1 full-stack physical gate restored near-stock compatibility across the
tested emulator, standalone, media, system-control and lid-close paths. Its one
shared application failure was Ports: muOS kept scripts in `ROMS/Ports` and
16 GiB of game directories in `/ports`, while ROCKNIX expects one native
`/roms/ports` tree and a bootstrapped release PortMaster provider. V6.2 performed
same-filesystem metadata moves into that exact layout, retains per-game script
identity and records the release application's real diagnostic log. Its
physical gate exposed a second shared cause: ROCKNIX's generic automounter
replaced Bird's p6 view with its internal writable-image game tree. V6.3
replaces that one service with a deterministic fixed-p6 assertion and retains
the same ordering. Its broad physical gate passed. V6.4 starts Bird before the
generic graph, runs compatibility setup silently in parallel, makes networking
PortMaster-only and masks services absent from the fixed profile; its broad
physical gate passed at roughly seven stopwatch seconds. V6.5 proved Bird
pixels before `switch_root` but exposed a release-module ABI mismatch; v6.6
uses the exact SYSTEM H700 input module from the tiny external overlay, then
hands state to the proven full runtime. V6.7 localized one failed final-root
bridge path; v6.8 then proved its detached replacement exited with status 2
before launcher entry. V6.9 removes the replacement entirely. Its physical
gate proved uninterrupted input and one persistent PID, then exposed a narrower
storage defect: the launcher did not get scheduled between `/storage` becoming
available and that mount moving into the final root. V6.10 adds a bounded
readiness handshake at that exact boundary. The first Bird retains descriptors
to the mounts that move, and the final supervisor adopts that original PID with
a blocking pidfd, so one process owns input until selection.
Early selections remain queued until the provider's generated application
contract is ready. V6.10 physically passed the complete menu, content and
system-control gate. V6.11 begins post-menu resident cleanup by keeping name
resolution and network time synchronization inside explicit PortMaster
sessions rather than every offline play session. Its idle physical test exposed
that storage anchoring could still depend on incidental button activity because
the raw `ppoll` timeout did not wake Bird. V6.12 replaces that polling path with
one explicit FIFO event from init after storage completes. Its physical trace
showed the FIFO was never created because this exact BusyBox omits `mkfifo`.
V6.13 uses and checksum-gates its available `mknod` applet instead. Its broad
physical gate passed with Bird interactive at kernel uptime 1.520 seconds and
storage anchored at 2.563 seconds. V6.14 is the first fixed-resident-service
pass: early selections become one-shot queued intents, one static process
replaces the generic input graph, one static event process replaces power
polling, and the fixed 2 GiB profile disables KSM scanning. Its broad physical
gate passed. The latest trace painted at 1.340 seconds, accepted H700 input at
1.454 seconds and retained the real 5,953-game library at 2.810 seconds.
V6.15 begins the measured ROCKNIX audit: it prevents two late brightness
owners, suppresses fixed-profile autostart no-ops, fixes the low-battery red
LED policy at 41 percent and shortens the safe shutdown/config checkpoint. Its
physical result proves brightness stability, `ksm_run=0`, a 40 ms config-save
checkpoint and roughly 1.8--2.0-second visible shutdown. The generic
application tail fell from about 8.0 to 3.58 seconds. Content selection reported
a queued-storage regression, although the final returned boot recorded storage
anchored at 2.888 seconds and no selection event. V6.16 made readiness
self-healing, replaced the 11.5 KiB multi-device Sway generator with the exact
card1/DSI-1 files, removed duplicate broken latency writes and moved RF-kill
state management out of offline boot. Its physical trace caught the precise
remaining race: the FIFO arrived at 2.899 seconds, but neither absolute
storage directory was retained before the mount move. V6.17's `/run` aliases
also remained invisible to the old-root process, but its timeout correctly
recovered through the final-root launcher instead of preserving the queue.
That recovery and a second generic UI request produced the reported redraws.
V6.18 signals only after `prepare_sysroot`, opens the stable
`/sysroot/storage` tree, removes the redundant UI start and explicitly
activates the saved Wi-Fi profile inside PortMaster's network session. Its
physical gate passed without redraws and restored every tested function except
networking. V6.19 waits for iwd, scans through NetworkManager and activates the
saved profile on the fixed `wlan0`; it also removes repeated immutable module,
profile, storage-start and known-empty compatibility work.
Its physical trace showed the access point in NetworkManager's scan but the
manually provisioned profile still failed immediately. It also exposed an
existing provisional-supervisor replay and a new diagnostic/watchdog coupling.
V6.20 orders the one final supervisor after `graphical.target` and takes the
audit process out of target completion. Network configuration is deferred until
the stock ROCKNIX UI produces a known-working connection to copy and trim.
Its physical gate passed without reboots or movie black screens. A one-time
Library selection reset and a lid-wake brightness change exposed two remaining
recovery contracts. V6.21 searches all 32 bounded input-event slots, retains
the exact volatile screen across any launcher recovery, archives per-boot
evidence, restores the raw pre-suspend panel level and moves manual brightness
steps into the fixed controls binary with raw level one as the lit floor.
V6.22 adds one app-independent Select+Start exit chord without grabbing input,
tracks each foreground provider tree for wrappers that publish no kill name,
and routes MSX through the pinned release's fMSX core after blueMSX segfaulted.

The gate order is compatibility first, then early Bird handoff, then service
deferral/removal, then kernel trimming. No component is removed from the full
baseline until its exact consumers and physical behavior are known.

## Ordered execution roadmap

This is the current priority order. Deferred items remain intentional backlog,
not discarded ideas.

1. **ROCKNIX implementation audit — active.** Classify every retained startup
   script, service, output file, dependency and idle wake-up. Remove or replace
   only measured fixed-profile work. v6.22 is the current physical gate; details
   and discovered bugs live in [`ROCKNIX_AUDIT.md`](ROCKNIX_AUDIT.md).
2. **Finish fixed userspace contracts.** Generate the exact RG34XX-SP Sway and
   audio configuration, reduce the remaining autostart runner, then reassess
   udev, logind/seatd, journald and other resident managers.
3. **Remove muOS-to-ROCKNIX shims.** Move runtime markers from `/run/muos` to
   `/run/bird`, regenerate the catalogue with canonical `/storage/roms` paths,
   move Bird state out of the `MUOS` namespace, normalize BIOS/Ports paths and
   delete launcher/runner path rewriting after one migration gate.
4. **Boot-chain indicators and shutdown.** Physically time v6.15 shutdown. In a
   separate recovery-guarded U-Boot experiment, stop driving PI11 red during
   boot and assert PI12 green at the earliest safe bootloader boundary. Keep
   runtime red exclusively for discharging capacity at or below 41 percent.
5. **Reproduce the complete Bird image.** Bake accepted card-side development
   state into one deterministic build and recovery route.
6. **Fixed RG34XX-SP kernel.** Trim the already compatible public ROCKNIX kernel
   only after userspace contracts and benchmarks settle; it must beat the
   accepted baseline in latency and efficiency without losing functionality.
7. **U-Boot optimization last.** Remove unused targets/probes, advance panel
   response and decide whether any splash is still useful.
8. **Deferred experience work.** Survey muOS/other OS optimizations; optimize
   RetroArch/emulators and first-game load; optimize PortMaster; make each
   music/movie/reader/emulator application bespoke; optimize suspend/wake
   battery behavior; then add final animation, sound and player controls.

Cross-cutting priorities remain: interaction speed first, then battery, then
memory, then exact desired features. Independent changes may share a card cycle
only when their physical results remain distinguishable.

## Governing optimization order

This layered order supersedes the original feature-oriented numbering below.
Every retained process, wake-up, file read, library and line of code must serve
the fixed RG34XX-SP experience.

### Layer 1 — userspace

Highest return and lowest risk. Make the launcher the first userspace
application and move everything unrelated to an interactive menu behind it.

- [x] Replace the stock frontend with the static direct-framebuffer launcher.
- [x] Compile the real library catalogue instead of scanning it at boot.
- [x] Keep networking off until PortMaster or scraping explicitly requests it.
- [x] Dispatch the launcher before entropy, storage and diagnostic observers.
- [x] Remove the failed RGB hook from the fixed device path.
- [x] Remove proof animation and audio from the critical interaction path.
- [x] Retire completed high-frequency observers and their 60-second log sync.
- [x] Replace launcher idle polling and raw-event logs with blocking evdev.
- [x] Inventory every remaining boot process, fork, file read and idle wake-up.
  The settled 24-second snapshot confirms no UnionFS or haveged process, about
  61 MiB in use beyond `MemAvailable`, session-warm audio and the remaining
  udev, hotkey, lid, idle and low-battery workers.
- [x] Replace dynamic
  multi-storage discovery and UnionFS with exact card paths. Kernel binds now
  preserve both union compatibility paths with zero resident FUSE processes.
  Direct `/dev/mmcblk0p6` mounting, unused boot/configfs-mount removal and the
  fixed `/run/muos/storage` map passed the combined functionality test.
- [x] Warm D-Bus, PipeWire and WirePlumber after the interactive menu and retain
  them for the session. Hardware verification recorded 3.97-second dispatch,
  4.22-second D-Bus readiness and 6.31-second audio completion; immediate
  selections join the same locked initialization and functionality passed.
- [x] Disable WirePlumber camera, V4L2, MIDI, Bluetooth and logind
  discovery while retaining the exact built-in ALSA graph and routing policy.
- [x] Remove delayed generic startup jobs for unused USB, catalogue,
  sound preparation, log cleanup, SSH permission repair and fixed controller
  rewrites. Hardware functionality passed afterward.
- [x] Retain early entropy seeding and terminate haveged after the kernel's
  explicit readiness event. Hardware logs show CRNG ready at 4.07 seconds and
  haveged gone at 4.10 seconds. Storage never waits for it.
- [x] Replace device startup, hotkey shell, lid
  watcher, low-battery watcher, charge check, idle scanner, module loader and
  user-init dispatcher with fixed RG34XX-SP policy. The first transaction
  safely refused a stale checksum before changing any target; the corrected
  batch uses the exact settled-card hash. It removes the five-second `/proc`
  scan while retaining the proven input binary, lid suspend, display idle,
  global controls and battery warning. Hardware functionality passed and the
  stopwatch result remained around 3.5 seconds.
- [x] Retire the completed 1,122-line migration engine from ordinary user-init.
  A 45-line collector retains boot and service traces without old patch guards
  or delayed log-copy sleepers.
- [x] Remove the next set of redundant fixed-startup work: per-boot
  immutable policy/geometry writes, obsolete update-file cleanup, zero-swap
  probing and the unnecessary squashfs module request.
- [ ] [stock-root v6.10 broad gate passed; v6.13 FIFO correction staged] Bake
  changes into the image and remove the card-side development user-init
  delivery path. The successful path is entirely embedded and does not enter
  p5. V5.0 physically proved the menu at 1.135 seconds, H700 input at 1.290 and
  the post-frame runtime at 2.08. V5.1 isolated CPU `softpipe` selection and an
  unprogrammed H616 speaker route. V5.2 passed fixed Panfrost, audio and global
  controls at roughly 2.5 seconds by stopwatch, then exposed wrong emulator
  choices, absent Ports and software movie presentation. V5.4 remained
  incomplete across DS, PSP, Ports and media because the manually recreated
  runtime contract was still partial. Stock-root v6.1 restored the entire exact
  provider and physically passed DS, PSP, media and broad emulator behavior;
  v6.2 normalized the native Ports layout; v6.3 removes the generic automount
  namespace collision before subtraction. Delete
  recovery partitions and obsolete
  payloads only after the new broad compatibility gate and later optimized
  replacement both pass.
- [x] [v6.3 physical gate passed] Physically verify representative native Ports: one FRT
  runtime game, one LÖVE game, one commercial-data game and Stardew; preserve
  `/var/log/exec.log` after every return so any remaining failures become
  per-game tuning rather than another common-provider guess.
- [x] [v6.2 physical gate passed] Separate suspend acceptance into three cases:
  power suspend/resume with lid open, ignored power while lid remains closed,
  and automatic resume when the lid opens. Do not enable H700 kernel suspend;
  the exact ROCKNIX profile disables it as broken and uses fake suspend.
- [x] [v6.3 physical gate passed; player-volume remap deferred] Remove duplicate
  MPV volume ownership without replacing the exact player. Physical VOL+/VOL-
  is system-owned, L1/R1 no longer changes player volume, and the remaining
  stock movie controls pass.
- [ ] [media pacing deferred] Profile decoder/VO drop counters before changing
  the exact player or kernel video configuration.
- [x] [v6.4 physical gate passed] Start Bird and its fixed storage before the generic systemd
  graph. Keep exact autostart running in parallel but isolate its console so it
  cannot repaint the menu; join audio only when an unusually early selection
  outruns the background warm-up.
- [x] [v6.4 physical gate passed] Keep NetworkManager and iwd stopped until PortMaster, then
  stop them again on return. Remove SSH, RPC, discovery, touchscreen, Sixaxis,
  statistics and HDMI-monitor units from this fixed user's ordinary boot; mask
  RPC's activation socket as well as its daemon so it cannot wake indirectly.
- [ ] [numeric gauge exposed; calibration and LED meaning pending] Physically
  verify the AXP717 charging path. Bird reads the
  kernel's fixed battery status and receives state changes through blocking
  uevents with no polling daemon. Plug/unplug updates passed. The exact kernel
  driver returns the raw AXP717 fuel-gauge percentage and documents the current
  channel's unknown offset, so the observed 100 percent and 492 mA are not yet
  calibrated proof. Numeric accumulation and the red/green LED state are now
  captured together;
  next compare it across a meaningful charging interval. Reconcile the DT's
  1,500,000-uA USB maximum with the
  driver's observed 2,000,000-uA boot default before hardcoding charge policy.

### Layer 2 — early userspace and init

Replace generic startup with a minimal fixed-device init. The static launcher
first proved that it could draw before `switch_root`; clean-root v5.0 now
removes the handoff entirely while keeping the verified menu-first boundary.

- [x] Build and hardware-test a minimal fixed init with a stock-init recovery
  route.
- [x] Hardware-verify the pre-`rcS` inittab launch and fallback.
- [x] Embed the launcher in initramfs and hardware-verify an interactive frame
  before `switch_root`.
- [ ] [v6.9 persistent PID passed; v6.10 storage correction staged] Overlay the exact release initramfs with the same
  static launcher and exact H700 input module. Keep that original process alive
  using retained descriptors to the moved runtime, device, sysfs and storage
  mounts, then let the supervisor adopt its PID with `pidfd_open`/`ppoll`.
- [x] [v6.9 physical gate passed] Physically verify uninterrupted navigation
  across the 1.5-second early-input point and final-root takeover. The original
  process and input descriptor now survive without an ownership swap.
- [x] [v6.10 physical gate passed] Verify that game and media rows become ready after the
  bounded pre-move storage acknowledgement. Select content both before and
  after the provider milestone and confirm the queued request launches.
- [ ] [v6.11 retained; network session still needs physical gate] Keep resolver and network time synchronization stopped in
  ordinary offline sessions, then start and release their exact providers with
  the existing PortMaster-only network transaction.
- [x] [v6.14 physical gate passed] Replace the generic `input_sense`
  shell/`grep`/four-`evtest` graph with one fixed RG34XX-SP control process.
  V6.11 captured the exact fixed map:
  event0 `axp20x-pek`, event2 `gpio-keys-volume`, event3 `gpio-keys-lid` and
  event4 `H700 Gamepad`; event1 is only the codec headphone switch. The
  5,184-byte candidate preserves volume repeat, Menu+volume brightness,
  power/lid fake suspend and Select+Start global exit without grabbing the
  gamepad.
- [x] [v6.14 physical gate passed] Replace `powerstate`'s two-second
  battery polling with fixed initial policy plus kernel power-supply events.
  V6.11 captured idle CPU `ondemand` at 480--1,416 MHz and GPU
  `simple_ondemand` at a 420--600 MHz bound. The 5,528-byte candidate never
  rewrites content policy and retains one 40-second capacity safety check only
  on battery because the AXP717 driver emits no capacity-change event.
- [x] [v6.15 state proof passed] Disable KSM on the fixed 2 GiB
  profile while retaining ROCKNIX's one-shot VM tuning. The idle snapshot had
  about 1.8 GiB available, only about 24 MiB anonymous memory and no workload
  that justifies a one-second same-page scan. V6.15 records the live KSM `run`
  value and counters. The physical result is `ksm_run=0` with all sharing
  counters at zero; the dormant kernel thread performs no scan.
- [x] [v6.15 physical gate passed] Prevent post-frame brightness resets. The early fixed
  five-percent value and manual controls are the only writers; generic
  `006-display` and the old preparation write are removed from the boot path.
- [ ] [v6.22 global exit/MSX staged] Replace fixed-profile generic autostart work while retaining
  controller, audio, emulator configuration and Sway compatibility. Audit and
  measured follow-ups are recorded in `ROCKNIX_AUDIT.md`.
- [x] [v6.15 physical gate passed] Shorten shutdown without bypassing ordered unmounts. Use an
  exact compare/copy config checkpoint and submit poweroff asynchronously;
  record request, save and final timing on hardware. Config preservation took
  40 ms and visible shutdown measured roughly 1.8--2.0 seconds.
- [x] [v6.18 physical gate passed] Make storage readiness deterministic.
  Init signals after `prepare_sysroot`; Bird opens content and config below the
  stable `/sysroot/storage` tree, acknowledges before special mounts move and
  retains the same PID. A timeout still falls back instead of stranding a queue.
- [x] [v6.18 physical gate passed] Replace generic Sway display discovery with the physically
  generated `card1`/`DSI-1` profile, remove external-display polling from normal
  content sessions and stop unmasking/restarting the live Bird service.
- [ ] [deferred: capture stock-created profile] Keep systemd RF-kill state and its activation socket out of
  offline boot; start the exact manager inside explicit PortMaster networking
  and join a usable NetworkManager link only inside that session.
- [ ] [migration gate planned] Remove muOS-to-ROCKNIX shims only after cached
  catalogue paths, runtime markers, state directories, BIOS and Ports all use
  canonical Bird/ROCKNIX namespaces in one coherent transaction.
- [x] [v6.18 final-tree proof passed]
  Verify an untouched idle
  boot logs `early_storage_fifo=ready`, `storage_signal_received`,
  `storage_anchor_ready` and an acknowledged marker, then launches content
  without requiring any earlier input event.
- [x] Replace the generic initramfs shell with a tiny static fixed-device init
  while retaining the existing root PID 1 as the fallback second phase.
- [x] Replace the root BusyBox PID 1 with a blocking 5,128-byte static init;
  three boots verified the marker, content round trips and normal shutdown.
- [x] Replace the generic root startup coordinator with the fixed RG34XX-SP
  sequence. Hardware functionality passed and stopwatch boots remain below
  3.8 seconds.
- [x] Remove BusyBox from both successful PID 1 roles. The accepted early-root
  path implements handoff directly, and the normal root PID 1 is static.
- [ ] Rebuild the remaining compatibility BusyBox with only its measured applet
  set. It remains the early recovery shell and interprets some post-frame root
  scripts; feature-specific applets should be invoked only when requested.
- [x] Mount only the exact filesystems and device nodes the experience uses.
  The accepted static first/root init pair owns proc, sysfs, devtmpfs, ext4,
  tmpfs, devpts and shared memory; debugfs is added only for chosen display
  controls.
- [x] Replace unconditional filesystem repair with a safe dirty-state
  policy. The static init reads the ext4 magic/state bytes directly, skips only
  state `0x0001`, and runs the retained `e2fsck -y` for error, dirty, unreadable
  or unexpected states. Hardware boot and functionality passed; the next
  candidate adds explicit branch evidence to ordinary diagnostics.
- [x] Remove unused magic data, generic ALSA profiles and recovery
  tools from the initramfs. Two byte-identical builds reduce its compressed
  size from 2,772,302 to 1,725,023 bytes while preserving the exact repair
  dependency closure and BusyBox shell fallback. Hardware functionality passed
  with an ordinary first-frame marker at 1.98 seconds.
- [x] Produce a byte-reproducible boot-image candidate containing this early
  path.
- [x] [clean-root v5.0 physically proved] Run Bird as the permanent root. The
  static launcher becomes usable first; storage, Panfrost, the immutable
  application runtime and global controls start independently afterward. The
  success path never mounts or switches into old p5.
- [ ] [clean-root v5.4 staged] Pass the coherent native-application boundary:
  fixed H700 metadata and mappings, exact 720x480 KMS policy, writable runtime
  scratch space, native sun4i-KMS/Panfrost pairing, a deterministic H616
  speaker route, H700-tuned Flycast, standalone DraStic/PPSSPP, native Ports,
  system-owned volume, lid-close suspend and one process-group Select+Start
  exit contract. MPV's direct DRM path remains the correctness baseline pending
  Cedrus and a rebuilt EGL-enabled media runtime. No muOS wrapper,
  configuration, core or library enters this path.

### Layer 3 — fixed RG34XX-SP kernel

Build for the hardware that actually exists rather than a family of possible
boards.

- [x] [complete source set pinned; exact-chain baseline reproduced]
  Reproduce or replace the current vendor 4.9.170
  kernel before changing the boot kernel. The active `Image` and its embedded
  4,209-line config are pinned, as is the exact Linaro GCC 5.3.1 compiler. The
  closest public Orange Pi `sun50iw9` source is only lineage: config
  normalization proves it lacks the active AXP2202 power, newer sunxi audio and
  exFAT code. Never deploy that comparison build. The next hardware run
  captured live module, device and DT closure is now pinned. Linux 7.0.11 plus
  the exact public ROCKNIX H700 hardware patch base is the chosen replacement
  path. The H700 profile also selects the separately published ROCKNIX joypad
  module at pinned commit `7647fdb0...dc7e`; omitting that package from the
  first source audit caused the v1/v2 input failures. The build gate now treats
  Linux, its patches, the DTB and that external GPL module as one complete
  source set. Keep the accepted vendor kernel as oracle until the broad
  replacement build passes every compatibility gate.
- [x] [profile captured; DTB v1 rejected] Record the exact live board hardware,
  buses and device IDs. The live DTB, modules, interrupts, I/O map and measured
  kernel timeline are pinned. The first raw-DTB candidate booted and passed
  functionality, but vendor U-Boot restored all 20 disabled nodes; targeted
  probes still ran and the 12.279 ms `/init` movement was only jitter.
- [x] [static/reproducibility gates passed] Build and audit the source-complete
  Linux 7.0.11 RG34XX-SP compatibility baseline. Two clean container builds
  produced byte-identical artifacts. The exact internal panel stream, DT and
  built-in first-frame driver closure pass the automated audit.
- [ ] [first candidate failed; recovery proven] Package and
  hardware-test that broad baseline with a checksum-gated, one-command restore
  path. The Android image round-trips, fits U-Boot/kernel/ramdisk limits, passes
  the known MMC/DRAM mutation simulation and has an external Mac restore path.
  Candidate `d683c1b9...ea6d` remained indefinitely on the U-Boot logo and
  produced no userspace capture. The external restore then rewrote and reread
  all 64 MiB as accepted image `872a3d0d...7764f`; the failed installer and
  collector are disabled on-card. The next candidate must expose progress
  before the normal display and `/mnt/mmc` paths so we can distinguish U-Boot
  handoff, early-kernel, initramfs/storage and display-only failures.
- [x] [second candidate failed; recovery proven again] Candidate
  `8b9ba424...9078` also remained on the U-Boot logo and produced no capture.
  That cycle incorrectly concluded there was no exposed red LED. Current
  hardware observation plus the exact DTB prove the upper indicator is
  bi-colour: PI11 is red/status and PI12 is green/power. The old diagnostic
  still yielded no boundary evidence, so the accepted image
  `872a3d0d...7764f` was restored and reread; all failed installers are disabled.
- [x] [vendor one-shot path evaluated; superseded by exact-chain checkpoint]
  Prove that a compact Android candidate fits as a contiguous FAT file and add
  an opt-in first-frame watchdog to the fixed initramfs. Do not use that route
  for the baseline: it would retain the same unproven vendor U-Boot/Android
  hybrid that failed twice. The exact-chain trial instead checkpoints the full
  customized rootfs plus every byte through partition 4 before changing the
  card layout; Mac recovery does not depend on candidate Linux starting.
- [ ] [hard acceptance gate] Treat the source kernel as a challenger, not an
  automatic replacement. Run it with the same Bird initramfs/userspace and
  promote it only after it beats accepted 4.9.170 on physical power-to-input,
  kernel-to-first-frame, interaction latency and efficiency. Keep the accepted
  kernel as default and oracle until every required gate passes.
- [x] [exact public DDR4 chain booted on physical hardware]
  Reproduce the exact working ROCKNIX H700 boot chain before modifying it.
  The rejected candidates mixed Anbernic's vendor U-Boot/TF-A and Android
  handoff with a ROCKNIX-derived kernel; that unproven hybrid is no longer the
  baseline. Stable tag `20260701`, DDR4 U-Boot v2026.01, TF-A v2.12.0, Linux
  7.0.11 and the v1 RG34XX-SP DTB are checksum-pinned. The guarded reference
  reached the ROCKNIX interface with working display, controls, brightness,
  volume and application launch; its immutable payloads remained exact after
  the test. The roughly 24-second stopwatch result belongs to generic ROCKNIX
  userspace and is not a Bird comparison. Substitute Bird one layer at a time.
- [x] [offline and first physical localization gates complete] Rebuild the exact
  stable-tag source baseline, then replace only its generic initramfs/system
  handoff with Bird's fixed init and launcher. The exact 30-patch order,
  shipping broad config and byte-identical v1 DTB are pinned. The embedded Bird
  cpio is byte-verified and protected by a 20-second first-frame watchdog. A
  deterministic 156 MiB candidate preserves the proven DDR4 U-Boot/TF-A and
  ends exactly where the existing root begins; checksum-gated install and
  prefix-only recovery commands are ready. On hardware, Linux mounted the root
  and Bird drew its first frame at 1.547 seconds. The later framebuffer console
  reclaimed the screen, the launcher selected the wrong event node, and the
  old root requested vendor-only `mali_kbase`; those are localized userspace
  compatibility failures, not a failure to boot the source kernel.
- [x] [compatibility v2 failed; cause localized] Retest the untrimmed
  Bird/source-kernel candidate. V2 prevented fbcon from reclaiming the panel
  and correctly rejected the separate volume-key event, but the expected
  `H700 Gamepad` never appeared. The launcher waited before drawing or marking
  readiness, so its 20-second watchdog reboot looked like a failed fallback;
  extlinux has only one Bird label, so it was another attempt at the same v2
  image. No source-kernel capture was written before the restart. The exact
  shipping DTB requests
  `rocknix-singleadc-joypad`, while the Linux tree and 30 patches contain only
  the standard `adc-joystick` driver. ROCKNIX ships the requested driver from a
  separate repository/package that the initial source gate had not included.
- [x] [compatibility v3 hardware gate complete] Load the exact pinned H700
  joypad module from early init before dispatching the launcher. The launcher
  paints as soon as the framebuffer exists, but retains the correct semantic gate:
  it publishes readiness and cancels the watchdog only after `H700 Gamepad`
  has opened. Keep the display-console and old-root compatibility bridges from
  v2. Persist input, audio, framebuffer, DRM, mount and dmesg evidence after p6.
  The physical gate drew at 1.586 seconds, opened the correct gamepad at 1.750
  seconds and passed menu controls and shutdown. Udev subsequently exposed
  ALSA and standard DRM/Panfrost nodes. Brightness still called the vendor
  display helper, while MPV, RetroArch, PPSSPP and native ports requested
  vendor Mali-fbdev/ION; DraStic reached its JIT and trapped. These are now
  localized preserved-userspace ABI failures rather than an early-kernel or
  input failure.
- [x] [compatibility v4 failure localized before application exec] Keep the launcher first and
  mount a pinned modern SDL2/Mesa runtime only after content selection. Put
  only the required graphics/protocol sonames ahead of the preserved root,
  satisfy its redundant `libmali.so.0` dependency with an empty ABI stub and
  continue to use muOS launch scripts, controller maps, audio and frontend
  policy. Replace vendor brightness writes with standard backlight sysfs and
  route source-kernel NDS launches through the pinned melonDS libretro core.
  The physical pass retained a 1.400-second visible frame, 1.553-second usable
  input and 2.010-second storage boundary. Runtime mounting began only after a
  selection, but a transient optional PortMaster bind failed and returned every
  request before `exec`; therefore none of the application ABI was retested.
- [x] [compatibility v4.2 physical gate; userspace card selection insufficient]
  V4.1 proved that the
  shared preparation and application `exec` path now works, but all SDL users
  selected Panfrost's render-only DRM `card0` instead of sun4i-drm's display
  `card1`. RetroArch reported `kmsdrm not available`; MPV, PPSSPP and SDL-linked
  FRT ports stayed alive with blank output until the user exited. Pin the fixed
  display as `SDL_KMSDRM_DEVICE_INDEX=1` in the on-demand content environment.
  Persist direct controls-service discovery and action results through kmsg so
  brightness and volume failures are observable. Brightness passed physically,
  but application behavior was otherwise unchanged; SDL still failed KMSDRM
  and decoded video remained invisible. The hint alone did not repair the
  legacy applications' shared display path.
- [x] [compatibility v4.3/v4.5 topology proof complete; superseded by clean root]
  Make Panfrost and its
  exact DRM helpers modules so built-in sun4i-drm owns display `card0`. Preserve
  the three matching modules through `switch_root`, then warm them
  automatically in parallel with the post-frame input/sound replay. The
  launcher never owns GPU initialization and content selection only performs a
  bounded readiness wait for `renderD128`. Hardware proved that topology and
  clean-root v5.2 later proved Panfrost, brightness, volume, audio and content
  return without the mixed muOS ABI. Application selection/performance is now
  the v5.3 gate above. Reduce the SquashFS only after that gate.
- [ ] If the trimmed source path loses a measured race, reverse-engineer only
  the corresponding accepted-kernel path (display handoff, MMC, clocks,
  regulators or fixed delay) and port the finding into controlled source. Do
  not attempt wholesale decompilation of the 4.9.170 binary.
- [ ] Remove the installed-runtime assumption that modules always live below
  `/lib/modules/4.9.170`. The fixed networking profile currently names the
  vendor `8821cs.ko` there, while an old depmod migration guard also embeds the
  release. This cannot explain a failure before the initramfs launcher, but it
  must be resolved before Wi-Fi or any modular driver can pass on a replacement
  kernel. Prefer eliminating unnecessary modules; give every retained module
  one fixed final-kernel path.
- [ ] Remove unused drivers, protocols, filesystems and alternate-board paths.
- [ ] [DTB v1 could not survive U-Boot] Disable or defer unused USB hosts, HDMI,
  Bluetooth, Wi-Fi and extra SDIO in the compiled source. Bluetooth is already
  modular in the broad replacement config; Wi-Fi, HDMI and their firmware/DT
  activation become explicit feature-triggered closures only after baseline
  compatibility is proven.
- [ ] Remove known failed probes and generic discovery paths.
- [ ] Measure kernel and initramfs compression choices on real hardware.

### Layer 4 — bootloader

Optimize U-Boot only after the userspace, early-init and kernel boundaries are
measured. Keep the minimum required for power, the internal display, SD boot
and a deliberate recovery path.

- [ ] Remove unused boot targets, probes and environment flexibility.
- [ ] Preserve a clean display handoff to the launcher.
- [ ] Decide whether a splash is useful only after final menu latency is known.
- [ ] Optimize U-Boot configuration and timing last.
- [ ] [exact owner found; guarded test pending] Replace U-Boot's status-LED
  selection. Its DDR4 defconfig drives GPIO 267, which is PI11 red/status, with
  boot state 2; PI12 green/power is GPIO 268. Test the corrected green policy
  only with the existing external recovery route, then measure how early the
  indicator can be asserted.
- [ ] Start the fixed `rg34xxsp_v1` LCD/panel sequence earlier in U-Boot; Linux
  inherits an already-running display and cannot recover pre-kernel darkness.

## System-wide efficiency priorities

1. Power-on-to-interaction time and interaction latency.
2. Battery efficiency: eliminate polling, needless wake-ups and resident work.
3. Memory efficiency: load and retain only what the fixed experience uses.
4. Add the exact desired features after the base system is lean.

The launcher remains a prototype. Blocking input is complete; the permanent
version should also minimize framebuffer writes, keep compact state and make
emulator/media handoffs exact. This profiling follows the larger architectural
savings; it is not forgotten.

## Current implementation status

- [x] Preserve the working system, Git history, diagnostics and stopwatch baseline.
- [x] Define the fixed RG34XX-SP/English/offline-at-boot experience.
- [x] Build a freestanding static launcher with direct framebuffer rendering.
- [x] Start at the earliest proven point using direct evdev input before udev.
- [x] Prove the embedded game catalogue and asynchronous ROM readiness.
- [x] Add fixed SNES/PSP/Port launch handoff and reliable direct return.
- [x] Replace daily PortMaster/network and shutdown stock-frontend paths.
- [x] Prove persistent Favorites and recent-game state.
- [x] Replace the diagnostic Home menu with fixed Play, Listen, Read and Watch
  destinations and compile the real audio/video library into the cache.
- [x] Add native MPV media handoff and exact media-screen return without a boot
  scan or a new playback dependency.
- [x] Promote the launcher to a permanent shell with B-only stock recovery and
  state-only asynchronous storage completion.
- [x] Prove nonblocking procedural animation, input skip and handoff-cancelled
  boot audio.
- [x] Remove the asynchronous saved-brightness restore and profile the existing
  sound-player paths.
- [x] Inventory the exact GPT, boot resource, U-Boot environment, Android boot
  image, initramfs and ext4 rootfs from the trusted stock archive.
- [x] Prove a byte-identical Android boot v2 unpack/repack round trip and build
  an offline-only raw-25 device-tree brightness candidate.
- [x] Safely install and raw-verify that candidate; hardware testing proved its
  `lcd_backlight` property does not own the visible boot brightness.
- [x] Trace the Allwinner `disp0 getbl/setbl` handoff to U-Boot's separate
  raw-50 DTB property.
- [x] Hardware-test the checksum-verified U-Boot raw-25 ownership candidate;
  U-Boot and Linux both preserve raw 25 with no later display write.
- [x] Install and raw-verify inherited startup level 3 of 255 in the owning
  U-Boot DTB, with no userspace brightness write. Perceived brightness is
  dimmer, but raw units are not a linear optical percentage and differ from the
  scale used by manual controls.
- [ ] Revisit the active splash owner after first-frame optimization; the
  archived-image FAT asset is not identical to this card's provisioned asset.
- [x] Remove the RGB call and dispatch the interactive launcher before entropy,
  storage mounting and diagnostic observers.
- [x] Remove the proof animation and chime from the active critical-UI path.
- [x] [historical vendor-root bridge; superseded by clean root] Replace the all-device
  replay with input/sound-only metadata while Mali loads concurrently. Keep
  udevd resident outside and after the launcher until MPV's `gptokeyb2`/SDL
  controls and the other libudev clients have fixed direct-event replacements.
  The one-shot proof broke rich movie controls and did not terminate cleanly.
  PortMaster/network remains a deferred home-network acceptance check. Clean
  root removes this muOS compatibility requirement instead of extending it.
- [x] [hybrid application route rejected after v4.5] Prove conventional display `card0`
  plus asynchronously warmed Panfrost `renderD128` across MPV, RetroArch,
  PPSSPP and an SDL/FRT port. Direct brightness passed in v4.2; prove volume and
  power/lid suspend from the separate `bird-controls` kmsg markers. Both the
  controls service and GPU warm-up remain post-frame and outside the launcher.
  The kernel/DRM topology passed; native RetroArch still failed when combined
  with muOS policy and assets, so the clean-root candidate now pairs each
  application with its own native configuration, cores and libraries.
- [ ] [clean-root v5.4 native-application gate] V5.0 verified menu/input,
  brightness and shutdown. V5.1 then verified application entry, controls and
  direct DRM decode while exposing forced CPU rendering, an unprogrammed H616
  speaker route and repeating MPV trigger events. V5.2 then proved Panfrost,
  direct speaker audio, MP3 and fixed controls while exposing modern Flycast,
  melonDS/FreeBIOS, a PPSSPP libretro crash, no Port dispatch and MPV software
  frame drops. V5.3 selects the H700-tuned and standalone applications,
  implements the fixed Port adapter, uses one process-group exit contract and
  probes GPU-backed SDL movie presentation. Its hardware run exposed an unsafe
  648-to-600 MHz devfreq write with PLL warnings, GLES2 DraStic columns,
  exFAT/transparent-window PPSSPP failures, missing default Port audio, an SDL
  owner collision in MPV, and an unopened kernel lid event. V5.4 independently
  corrects those boundaries without changing the launcher path. Verify
  Dreamcast, DS and layout switching, PSP, Balatro audio, Stardew, a lighter
  Port, MP3, visible movie controls, Select+Start, volume, brightness, button
  and lid suspend/wake, shutdown and absence of new PLL warnings. PortMaster
  networking remains a later home-network check; Cedrus/EGL media optimization
  follows this boundary.
- [ ] After built-in-speaker audio passes, add a fixed headphone-jack policy
  that uses the existing H700 detect GPIO to mute the external speaker
  amplifier. Do not introduce a UCM or PipeWire session daemon for this one
  binary device state.
- [ ] Move the final animation and audio to the earlier firmware layer.
- [ ] Complete the final visual, animation and audio identity.
- [ ] Remove superseded muOS components and produce a reproducible firmware image.
- [ ] Optimize kernel and U-Boot last.

Verified interactive milestone: clean-root v5.2 recorded pixels at 1.137
seconds and input-ready at 1.294 seconds of kernel uptime. LED-on to an
immediately usable menu is approximately 2.5 seconds by stopwatch. V5.4 leaves
that launcher/early-init dependency path unchanged and awaits its physical
application gate.
At the last accepted vendor-root checkpoint, all three emulator/Port paths were
playable with audio and returned to a redrawn launcher in 27--29 ms. The
clean-root native-session gate is tracked separately above.

## Original feature-oriented checklist

This checklist records the build history and feature milestones. The layered
roadmap above controls the order of new optimization work.

### 1. Preserve the working system and measurements

Before changing architecture:

* Keep an untouched recovery card or full image.
* Put every modification in Git on your Mac.
* Record cold-boot stopwatch/video timings.
* Preserve internal timing markers.
* Document the current startup scripts and process tree.

You need a reliable baseline and one-command rollback before making boot-critical changes.

### 2. Define the exact finished experience

Write down what the device will always do:

* Always English
* Always RG34XXSP
* Always open to the main games menu
* One wallpaper and visual style
* One font
* One boot animation
* One boot sound
* Fixed controls
* Fixed systems and emulator mappings
* Whether Wi-Fi, Bluetooth and SSH should start automatically
* Whether Resume, Favorites, Games and Shutdown appear immediately

This lets you replace runtime configuration with fixed build-time decisions.

### 3. Build a tiny early-display proof of concept

Create the smallest possible program that can:

* Turn the display into a usable canvas
* Draw a solid background or wallpaper
* Render one embedded English bitmap font
* Show several text entries
* Draw a selection arrow
* Read D-pad and A/B
* Exit cleanly

Do this after normal boot first. Stop the existing frontend and run your test program manually over SSH.

Do not initially include storage, artwork, audio, animation or emulator launching.

### 4. Determine the earliest reliable launch point

Move the tiny program earlier through the boot sequence until it can start reliably as soon as:

* The display device exists
* The built-in controls exist
* The backlight is usable

Do not wait for all of `udev`, networking, storage bindings or other unrelated hardware. Wait only for the exact devices the early UI requires.

This establishes your true earliest interactive-menu time.

### 5. Create a cached game index

Stop scanning the ROM collection during boot.

Generate a compact catalog ahead of time containing:

```text
Display name
System
ROM path
Emulator/core
Favorite status
Optional artwork path
```

The launcher can display this cached catalog immediately. Storage mounting happens concurrently, and each game becomes launchable once its ROM path is available.

Regenerate the index only when the collection changes.

### 6. Add asynchronous storage readiness

Separate these two concepts:

```text
The collection can be browsed
The ROM can be launched
```

The catalog can appear immediately from cache, while a background process:

* Mounts storage
* Creates required bindings
* Verifies the expected paths
* Signals the launcher when games are available

The launcher should remain responsive throughout this process.

### 7. Replace the full frontend with the tiny launcher

Once the proof of concept can browse the catalog:

* Launch the correct emulator/core
* Hide or release the display
* Wait for the emulator to exit
* Restore the launcher
* Handle shutdown and reboot
* Optionally handle suspend or save-state shutdown

At this point it becomes the permanent shell rather than a temporary loading screen.

This is likely the largest remaining boot-time improvement.

### 8. Embed one lightweight font

Replace the multilingual font dependency chain with exactly what you use.

Best starting option:

* Embedded monochrome bitmap font
* ASCII plus any symbols you actually need
* Fixed supported sizes
* No runtime font discovery
* No shaping engine
* No unused language libraries

A bitmap font is extremely cheap to load and render. Later, you could use one small English TrueType font if you strongly prefer smoother text, but bitmap is ideal for the first fast build.

### 9. Embed and optimize the wallpaper

Convert the wallpaper ahead of time into the display’s preferred pixel format and dimensions.

Instead of:

```text
open PNG
→ parse PNG
→ decompress it
→ convert pixels
→ scale image
→ draw
```

use something closer to:

```text
map embedded image
→ copy pixels to display
```

A preconverted RGB565 or other native-format image uses more storage but substantially less startup processing. Since it is only one fixed wallpaper, that trade is sensible.

### 10. Add the boot animation efficiently

Avoid general-purpose video playback.

Use one of:

* Procedural animation
* Sprite sheet
* Small sequence of preconverted frames
* Palette animation
* Movement of text/logo elements

For example, a logo sliding or unfolding over the wallpaper can look polished while involving only a few memory copies.

The animation should never delay menu readiness. Once input is available, the user should be able to skip it or interact immediately.

### 11. Add low-overhead boot audio

Avoid initializing an elaborate audio stack solely for a startup sound.

Use:

* One short embedded PCM sample
* Correct target sample rate and format ahead of time
* Direct ALSA playback or the simplest available device interface
* Playback in parallel with animation and storage mounting

Do not decode MP3, Ogg or another compressed format during early boot unless storage size genuinely matters. A short raw PCM sound is larger but trivial to play.

The UI should not wait for audio hardware; sound begins whenever the audio device becomes ready.

### 12. Eliminate runtime questions and configuration parsing

Hardcode or compile in your permanent choices:

* Screen dimensions
* Device model
* Control mapping
* Language
* Font
* Wallpaper
* Menu structure
* Initial selection
* Emulator mappings
* Storage locations
* Default brightness behavior
* Theme measurements

Avoid repeatedly reading configuration files for values that never change.

Keep configuration files only for things you genuinely expect to adjust, such as brightness, volume, favorites and recent games.

### 13. Defer all nonessential services

Do not start these before the launcher is usable unless necessary:

* Wi-Fi
* Bluetooth
* SSH
* Samba
* Time synchronization
* Scraping
* Update checks
* Maintenance jobs
* Emulator verification
* Log cleanup
* Artwork processing

Start them:

* After first frame
* In the background
* On demand from the menu
* Only when enabled

The critical path should contain only display, input, launcher and required storage.

### 14. Replace fixed delays with readiness checks

Remove patterns such as:

```sh
sleep 1
sleep 2
```

Replace them with narrow bounded checks:

```text
Wait until exact display device exists
Wait until exact input device exists
Wait until exact mount is available
```

This prevents the fast case from waiting unnecessarily while still handling slower boots safely.

### 15. Minimize dynamic dependencies

Once the launcher works, inspect what it loads.

Aim for:

* One executable
* Few or no shared libraries
* Embedded font
* Embedded wallpaper
* Embedded animation assets
* Embedded startup sound
* Minimal libc and hardware interfaces

Static linking is useful here because it makes startup predictable, but the more important goal is reducing the amount of code and data loaded at all.

### 16. Optimize perceived response before chasing milliseconds

Make the device react immediately even when Linux is still working:

* LED turns on at the earliest possible point
* Backlight/display activates early
* Static wallpaper or splash appears before menu construction
* Animation begins while input and storage initialize
* Menu becomes interactive before animation ends
* Loading state is visible rather than a black screen

A system that visibly responds at two seconds and becomes fully ready at five will feel much faster than one that remains black for four seconds and finishes at the same time.

### 17. Profile launcher internals

Once the custom launcher exists, add timestamps around:

* Process entry
* Display open
* First pixel written
* First frame presented
* Input open
* First input accepted
* Catalog loaded
* Storage ready
* First game launch

Optimize measured bottlenecks rather than assumptions.

### 18. Simplify the remaining muOS userspace

After replacing the frontend, inspect what parts of muOS remain necessary:

* Hardware initialization
* Emulator launching
* Power management
* Volume and brightness controls
* Save handling
* PortMaster environment
* Networking utilities

Disable or remove components that exclusively supported the old frontend or configurations you no longer use.

### 19. Customize and rebuild the root filesystem

When installed-file experimentation stabilizes, create a reproducible custom OS image containing:

* Your launcher
* Your fixed assets
* Your game index
* Your scripts
* Only required libraries
* Your service configuration
* Your permanent device settings

This turns the project from “modified SD card” into a repeatable personal firmware build.

### 20. Specialize the kernel, then touch U-Boot last

Only proceed here after userspace is highly optimized and measurements prove meaningful time remains below it.

Possible later work:

* Fixed U-Boot boot target
* Remove unnecessary device probing
* Earlier splash or LED control
* Smaller kernel configuration
* Remove unused drivers and filesystems
* Build essential drivers directly into the kernel
* Tune kernel compression
* Narrow device-tree configuration

These changes are higher risk, but measurements now show that the kernel owns
the largest remaining measured interval before the menu. They begin after the
userspace and early-init boundaries are made exact; U-Boot remains last.

## Best immediate sequence

Your next concrete milestones should be:

```text
1. [done] Draw wallpaper and text from a tiny executable
2. [done] Read the RG34XXSP controls
3. [done] Launch it automatically at the earliest safe point
4. [done] Load a cached game list
5. [done] Mount storage in parallel
6. [done] Launch games and return directly to the menu
7. [in progress] Remove/defer every remaining nonessential userspace task;
   fixed device/power/control workers passed; the ROCKNIX application tail is
   now under a script-by-script audit
8. [in progress] Replace dynamic storage, audio and device discovery with fixed
   paths; storage/input/power are fixed and the Sway/audio provider is next
9. [done] Launch the same static menu before `switch_root`
10. [done] Replace both generic PID 1 layers and the root startup coordinator
    with fixed-device implementations
11. Bake and reproduce the complete custom image
12. Build the fixed RG34XX-SP kernel
13. Reduce U-Boot only after the final boundary measurement
14. [deferred] Optimize cold game loading after the current system roadmap
15. [done: 128 ms Linux-DTB hardware proof] Reduce the PMIC cold-power hold
    from 512 ms to its minimum; quick-tap power-on is verified, while earlier
    green-LED/display response remains a later bootloader/firmware boundary
16. [active: v6.22] Audit and reduce the retained ROCKNIX userspace contract;
    v6.15 passed brightness/KSM/shutdown and cut the application tail, while
    v6.16 fixed Sway/RF-kill profiles, v6.18 hardens retained storage/UI and
    v6.19 removes repeated fixed-profile/module work and v6.20 fixes its
    supervisor/diagnostic lifecycle regressions; v6.21 hardens UI/input recovery
    and suspend brightness; v6.22 adds one managed global foreground-exit
    contract and replaces the crashing MSX core; Wi-Fi profile capture is deferred
17. [planned coherent migration] Remove muOS-to-ROCKNIX namespace shims
18. [guarded bootloader gate] Use PI12 green during boot and reserve PI11 red
    for the 41-percent low-battery policy
```

Cold game launch findings and the resume-later checklist are intentionally
parked in [`GAME_LOAD_DEFERRED.md`](GAME_LOAD_DEFERRED.md). The accepted
compatibility stack is functional. The persistent original launcher remains
under physical test before further timing work moves below it.

The power-key threshold is confirmed programmable in the AXP2202/AXP2101 PMIC.
Its isolated Linux-DTB proof has been promoted into the current batch; exact
ownership caveats and the required three-boot test sequence are in
[`POWER_BUTTON_DEFERRED.md`](POWER_BUTTON_DEFERRED.md).

The philosophy is simple: **one device, one experience, no unnecessary decisions, no unnecessary work, and something useful on-screen as early as the hardware permits.**
