# RG34XX-SP boot-process audit

This audit uses cold boot `723d4474-e6c2-4936-bd71-b123d5d97f0c`, after the
raw-25 U-Boot backlight change. Times are Linux kernel uptime, not LED-on
stopwatch time. The static-`/init` first frames are at 1.957, 1.980 and 1.964
seconds of kernel uptime, while current LED-on stopwatch timing is approximately
3.5--3.8 seconds. Three later boots with the static root PID 1 recorded
input-ready frames at 2.032--2.103 seconds and retained approximately
3.8-second stopwatch timing.

## Work before the usable menu

| Time | Work | Cost | Decision |
| ---: | --- | ---: | --- |
| 0--1.809 s | kernel built-in driver initialization | 1.809 s | Fixed-device kernel/DT target. Input is registered at 1.726 s and ALSA finishes at 1.808 s. |
| 0.755--0.905 s | unpack 2.6 MiB compressed initramfs | 150 ms, overlapping kernel init | Remove the 2.8 MiB magic database, generic ALSA profiles and unused recovery tools. |
| 1.809--1.852 s | initramfs filesystem check and root mount | ~43 ms on a clean boot | Use a dirty-state policy instead of unconditional `e2fsck -y`; retain recovery for unclean shutdowns. |
| 1.852--2.20 s | fixed early-root handoff, then root BusyBox setup | menu cost is now 105--128 ms | The launcher draws at 1.957--1.980 s before root dispatch begins at 2.18--2.20 s. |
| 2.08 s | `S01entropy` starts `haveged` | ~10 ms to dispatch; CRNG ready at 4.07 s and generator stopped at 4.10 s | Retain early and concurrent. Deferral caused CRNG/audio stalls; the revised service now exits after readiness. |
| 2.18--2.22 s | `S02rgb` | ~40 ms, `rc=1` | Remove. This fixed device has no requested RGB experience and the hook fails. |
| 2.22--2.24 s | `S03danilauncher` supervisor dispatch | ~20 ms | Move ahead of all asynchronous observers and optional init hooks. |
| 2.253--2.286 s | open fixed framebuffer/input and draw | 33 ms | Already appropriately narrow; profile after the init-order change. |

The staged critical-UI revision dispatches the launcher before entropy, ROM
mounting and compatibility startup, waits only for its exact post-draw marker,
and then continues normal initialization. `S02rgb` and the completed polling
observers are deleted from ordinary boot, and the 60-second log-sync sleeper is
removed. Their source and historical results remain available for deliberately
armed firmware experiments. Proof animation and chime are also absent so the
measurement represents the interactive menu alone.

The hardware-verified card-side proof inserts an additive BusyBox inittab entry immediately
after the fixed `/run` setup and before the generic sysinit tree. It leaves the
existing sysinit launcher entry in place as an automatic fallback and adds
duplicate-start protection to the supervisor. Its first frames varied from
2.220 to 2.327 seconds, leaving root mount/inittab work in front of the menu.
The verified candidate embeds the launcher in initramfs and starts its root
supervisor before `switch_root`, while leaving both later starts as
duplicate-safe fallbacks. The generic shell `/init` is now replaced by a
6,424-byte static fixed-device executable, with the verified shell retained as
`/init.stock`. Three hardware boots explicitly report the fixed path active and
average 1.967 seconds to an input-ready frame, about 88 ms earlier than the
previous initramfs-shell pair. The remaining root BusyBox PID 1 is now replaced
by a hardware-verified 5,128-byte blocking static init. Three boots recorded its
explicit marker; content round trips and shutdown completed normally.

## Kernel-time opportunities inside the first 1.809 seconds

The kernel log exposes concrete general-purpose work that is unrelated to this
fixed internal-screen, one-card menu:

- Three EHCI and three OHCI host-controller probes occupy much of
  approximately 0.99--1.32 seconds.
- Wi-Fi/Bluetooth platform and protocol setup runs despite network being
  disabled at userspace boot.
- Extra SD/SDIO hosts probe from roughly 1.49--1.65 seconds; one repeatedly
  times out while looking for the network device.
- PPP, IPsec, tunnelling, IPv6 and generic USB storage/network/HID drivers are
  built in and initialized unconditionally.
- HDMI initializes even though this experience is permanently internal-screen.
- Failed CPU OPP/debug link creation consumes roughly 40 ms at 1.676--1.716.

Before rebuilding the kernel, moving the existing static launcher into the
early-root handoff can plausibly move first interaction from roughly 2.3 to
1.85--1.95 kernel seconds. A fixed kernel can then attack the larger 0--1.809
interval by disabling unused DT nodes and making optional subsystems load only
when their features are selected. U-Boot time before the kernel is additional
and is not included in these timestamps.

## Work already after the usable menu

| Time | Work | Current effect | Bespoke direction |
| ---: | --- | --- | --- |
| 2.26--3.77 s | full udev daemon, cold replay and settle | 1.51 s; gates the stock startup sequence, not the menu | The 1.35-second input/sound-only replay is functional and current. The rejected one-shot proof broke MPV's rich controls and timed out stopping udevd. |
| 3.45--3.52 s | unintended stock D-Bus copy | 70 ms; the preserved `S30dbus.dani-real` accidentally matches `S??*` | Staged migration hides the real script, skips boot D-Bus, then warms it asynchronously after the menu. |
| 3.85--3.86 s | dispatch stock startup | 10 ms | Keep only as a temporary compatibility supervisor while dependencies are extracted. |
| 2.24--4.49 s | dynamic ROM-storage mount path | latest storage ready at 3.75 s; no first-frame dependency | Exact kernel binds are verified with no FUSE PIDs. Direct `/dev/mmcblk0p6` mounting, no SD/USB probing, no boot/configfs startup mounts and a fixed bind map are staged together with separate logs. |
| after system-ready (staged) | PipeWire and WirePlumber post-menu warm-up | wrapper returns immediately; measured cold readiness costs 1.0--1.5 s | Run concurrently with entropy/noncritical storage and retain for the session; later replace the general graph with a fixed audio profile or direct ALSA. |
| 4.61 s | boot partition and storage bind setup | no first-frame dependency | Defer or delete any bind/boot mounts unused by the fixed launcher and launch wrappers. |
| 4.84 s | stock hotkey service | volume/system shortcuts become ready later | Keep during compatibility phase; later integrate the exact desired shortcuts into the launcher. |
| 4.94 s | user-init | development installers and patch guards run | Keep while developing. Bake all changes into the final image, then disable it in production. |
| 6.60 s | backlight probe ends | diagnostic only | Removed from ordinary boot; restore only as an explicitly armed firmware-test probe. |
| 33.37 s | generic boot probe ends | scanned `/proc` every 200 ms and kept a logger alive | Removed from ordinary boot together with its 60-second background copy schedule. |

The stock frontend appearing at 18.64 seconds in this trace is not ordinary
boot work. B was pressed at 18.55 seconds, deliberately invoking the stock
recovery frontend.

## Persistent userspace after startup

The current compatibility system retains `udevd`, the lid listener and the
hotkey listener in addition to the custom launcher. The latest entropy proof
removes `haveged`, fixed binds removed both UnionFS workers, and the current
content-triggered audio proof leaves PipeWire/WirePlumber absent. An accidental
visible stock-script copy still starts D-Bus; the staged migration fixes that
and then intentionally warms the three audio processes after the menu. None is
required to draw or operate the main menu. The intended reduction is:

1. Stop `haveged` once the CRNG is ready rather than leaving it resident.
2. Replace generic udev cold discovery with fixed-device setup; retain hotplug
   only if a chosen feature needs it.
3. Replace two UnionFS workers with the fixed card paths already compiled into
   the catalogue and launch wrappers.
4. Profile the session-warm PipeWire/WirePlumber/D-Bus configuration, replace
   its generic graph with the fixed device profile, then evaluate direct ALSA.
5. Absorb the exact lid and volume behavior into the permanent launcher before
   removing their general-purpose services.

## Efficiency rules

- The menu and its exact post-draw timestamp are the only ordinary-boot
  observability on the critical path.
- Polling is a temporary bring-up technique, not a permanent idle behavior.
- The launcher now blocks on evdev once storage is ready; its former 4 ms idle
  poll and ordinary raw-event logging are removed.
- General services start after the interactive menu. Keep them demand-only when
  battery matters more; warm them concurrently when measured interaction
  latency justifies the session-resident cost.
- A compatibility component is removed only after its exact launcher, emulator,
  media, lid, volume or shutdown responsibility has a fixed replacement.
- Optimize in order: interaction latency, battery/wake-ups, resident memory,
  then the exact desired features.

## Ordered attack plan

1. [staged] Dispatch the launcher first; remove RGB, completed polling probes,
   the 60-second sync and proof effects while retaining the first-frame marker.
2. Inventory and eliminate/defer remaining nonessential userspace work, starting
   with dynamic multi-storage/UnionFS and always-resident general audio.
3. [done] Move the hardware-verified pre-`rcS` boundary into the initramfs
   root-mount handoff and defer root BusyBox init until first frame.
4. [done] Replace the generic shell `/init` with the fixed-device static init;
   hardware testing shows no recovery activation.
5. [done] Replace root BusyBox PID 1/inittab with the fixed static child reaper
   and shutdown event loop; three boots verified content and shutdown.
6. [minimal replay verified; daemon removal deferred] The inventory confirmed identical
   input, ALSA and partition state across udev and found only `mali_kbase` newly
   loaded. A no-udev proof kept the menu and shutdown working but broke
   RetroArch/MPV input, ALSA initialization and system hotkeys because the
   existing binaries consume `/run/udev` input/sound records. It also measured
   about 1.10 seconds in explicit Mali probing. The narrowly filtered
   input/sound replay restored games, media, controls, volume and brightness in
   1.35 seconds. The one-shot proof then timed out while stopping udevd and
   removed MPV's `gptokeyb2`-provided pause, seek, subtitle, speed and
   player-volume controls. The resident minimal bridge is therefore the current
   checkpoint until those libudev/SDL clients receive fixed direct-event
   replacements. PortMaster/network remains a deferred acceptance check.
7. [FUSE removal verified; exact mount/binds staged] Replace the dynamic
   multi-storage/UnionFS startup with a fixed ROM mount. Its two resident FUSE
   processes are gone behind identical kernel-bind compatibility paths. The
   next batch replaces the remaining probing, unused boot/configfs mounts and
   generic bind selection.
8. [staged] Warm the general audio stack asynchronously after the menu, with
   locked first-selection joining and no launcher/storage wait.
9. Bake successful card-side changes into rootfs, delete production user-init
   and generic maintenance jobs, then profile the smaller image.
10. Trim the initramfs, then build the fixed kernel and optimize U-Boot last;
   this is where most of the remaining power-on-to-menu interval lives.
