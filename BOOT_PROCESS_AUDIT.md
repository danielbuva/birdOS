# RG34XX-SP boot-process audit

This audit uses cold boot `723d4474-e6c2-4936-bd71-b123d5d97f0c`, after the
raw-25 U-Boot backlight change. Times are Linux kernel uptime, not LED-on
stopwatch time. The static-`/init` first frames are at 1.957, 1.980 and 1.964
seconds of kernel uptime, while current LED-on stopwatch timing is approximately
3.5--3.8 seconds.

## Work before the usable menu

| Time | Work | Cost | Decision |
| ---: | --- | ---: | --- |
| 0--1.809 s | kernel built-in driver initialization | 1.809 s | Fixed-device kernel/DT target. Input is registered at 1.726 s and ALSA finishes at 1.808 s. |
| 0.755--0.905 s | unpack 2.6 MiB compressed initramfs | 150 ms, overlapping kernel init | Remove the 2.8 MiB magic database, generic ALSA profiles and unused recovery tools. |
| 1.809--1.852 s | initramfs filesystem check and root mount | ~43 ms on a clean boot | Use a dirty-state policy instead of unconditional `e2fsck -y`; retain recovery for unclean shutdowns. |
| 1.852--2.20 s | fixed early-root handoff, then root BusyBox setup | menu cost is now 105--128 ms | The launcher draws at 1.957--1.980 s before root dispatch begins at 2.18--2.20 s. |
| 2.17--2.18 s | `S01entropy` starts `haveged` | ~10 ms | Retain for now; an earlier deferral caused CRNG/audio stalls. Start it after launcher dispatch in the next init-order proof. |
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
previous initramfs-shell pair. The staged next candidate replaces the remaining
root BusyBox PID 1 with a 5,128-byte blocking static init.

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
| 2.24--3.77 s | full udev cold replay and settle | 1.53 s; gates the stock startup sequence, not the menu | Inventory pre/post device nodes, then replace the all-subsystem/all-device replay with the fixed devices actually needed. |
| 3.77--3.85 s | D-Bus | 80 ms; required mainly by the general audio stack | Start concurrently where safe; eventually remove if direct ALSA replaces the PipeWire boot path. |
| 3.85--3.86 s | dispatch stock startup | 10 ms | Keep only as a temporary compatibility supervisor while dependencies are extracted. |
| 2.24--4.49 s | dynamic ROM-storage mount path | storage becomes browse-launchable at 4.115 s | Replace device discovery, `blkid`, SD/USB probes and union setup with one fixed `/dev/mmcblk0p6` mount. |
| 4.18--4.38 s | PipeWire and WirePlumber | socket only; final boot chime starts at 4.66 s | The largest experiential target: fixed ALSA setup plus a tiny embedded-PCM player, with PipeWire started only for content that needs it. |
| 4.61 s | boot partition and storage bind setup | no first-frame dependency | Defer or delete any bind/boot mounts unused by the fixed launcher and launch wrappers. |
| 4.84 s | stock hotkey service | volume/system shortcuts become ready later | Keep during compatibility phase; later integrate the exact desired shortcuts into the launcher. |
| 4.94 s | user-init | development installers and patch guards run | Keep while developing. Bake all changes into the final image, then disable it in production. |
| 6.60 s | backlight probe ends | diagnostic only | Removed from ordinary boot; restore only as an explicitly armed firmware-test probe. |
| 33.37 s | generic boot probe ends | scanned `/proc` every 200 ms and kept a logger alive | Removed from ordinary boot together with its 60-second background copy schedule. |

The stock frontend appearing at 18.64 seconds in this trace is not ordinary
boot work. B was pressed at 18.55 seconds, deliberately invoking the stock
recovery frontend.

## Persistent userspace after startup

The compatibility system retains `haveged`, `udevd`, `dbus-daemon`, PipeWire,
WirePlumber, the lid listener, the hotkey listener and two UnionFS workers in
addition to the custom launcher. None is required to draw or operate the main
menu. The intended reduction is:

1. Stop `haveged` once the CRNG is ready rather than leaving it resident.
2. Replace generic udev cold discovery with fixed-device setup; retain hotplug
   only if a chosen feature needs it.
3. Replace two UnionFS workers with the fixed card paths already compiled into
   the catalogue and launch wrappers.
4. Replace boot-time PipeWire/WirePlumber/D-Bus with direct early ALSA for the
   chime, then start the larger stack on content launch only if an emulator or
   MPV still requires it.
5. Absorb the exact lid and volume behavior into the permanent launcher before
   removing their general-purpose services.

## Efficiency rules

- The menu and its exact post-draw timestamp are the only ordinary-boot
  observability on the critical path.
- Polling is a temporary bring-up technique, not a permanent idle behavior.
- The launcher now blocks on evdev once storage is ready; its former 4 ms idle
  poll and ordinary raw-event logging are removed.
- General services start on content demand unless hardware correctness requires
  them earlier.
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
5. [staged] Replace root BusyBox PID 1/inittab with the fixed static child
   reaper and shutdown event loop; verify shutdown and application round trips.
6. Record `/dev`, module and audio-node state immediately before and after udev;
   replace its 1.53-second generic cold replay with a fixed-device sequence.
7. Replace the dynamic multi-storage/UnionFS startup with a fixed ROM mount.
8. Make the general audio stack
   content-triggered.
9. Bake successful card-side changes into rootfs, delete production user-init
   and generic maintenance jobs, then profile the smaller image.
10. Trim the initramfs, then build the fixed kernel and optimize U-Boot last;
   this is where most of the remaining power-on-to-menu interval lives.
