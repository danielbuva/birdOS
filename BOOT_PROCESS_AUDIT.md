# RG34XX-SP boot-process audit

This audit uses cold boot `723d4474-e6c2-4936-bd71-b123d5d97f0c`, after the
raw-25 U-Boot backlight change. Times are Linux kernel uptime, not LED-on
stopwatch time. The current stopwatch result is approximately four seconds;
the launcher itself is already interactive at 2.286 seconds of kernel uptime.

## Work before the usable menu

| Time | Work | Cost | Decision |
| ---: | --- | ---: | --- |
| 0--2.17 s | kernel, initramfs, root switch and BusyBox inittab mounts | 2.17 s | Lower-layer target after the userspace path is clean. |
| 2.17--2.18 s | `S01entropy` starts `haveged` | ~10 ms | Retain for now; an earlier deferral caused CRNG/audio stalls. Start it after launcher dispatch in the next init-order proof. |
| 2.18--2.22 s | `S02rgb` | ~40 ms, `rc=1` | Remove. This fixed device has no requested RGB experience and the hook fails. |
| 2.22--2.24 s | `S03danilauncher` supervisor dispatch | ~20 ms | Move ahead of all asynchronous observers and optional init hooks. |
| 2.253--2.286 s | open fixed framebuffer/input and draw | 33 ms | Already appropriately narrow; profile after the init-order change. |

The asynchronous backlight, ROM-mount and general boot probes currently start
at 2.17 seconds and compete with the first draw. They do not logically belong
before the menu. Keep the diagnostics, but dispatch them after the launcher has
started; retain the launcher's own exact first-frame/input timestamps.

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
| 6.60 s | backlight probe ends | diagnostic only | Convert to an armed firmware-test probe after the brightness value is finalized. |
| 33.37 s | generic boot probe ends | scans `/proc` every 200 ms and keeps a logger alive | Keep diagnostics but stop once the relevant milestones are captured; remove its 60-second background copy schedule. |

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

## Ordered attack plan

1. Install the launcher-aligned static U-Boot frame zero without changing
   Linux timing.
2. Dispatch the launcher before asynchronous probes and remove failing RGB
   init. This is the last easy pre-menu userspace gain.
3. Record `/dev`, module and audio-node state immediately before and after udev;
   replace its 1.53-second generic cold replay with a fixed-device sequence.
4. Replace the dynamic multi-storage/UnionFS startup with a fixed ROM mount.
5. Move the boot chime to fixed direct ALSA and make the general audio stack
   content-triggered.
6. Bake successful card-side changes into rootfs, delete production user-init
   and generic maintenance jobs, then profile the smaller image.
7. Optimize initramfs, kernel and U-Boot last; this is where most of the
   remaining power-on-to-kernel interval lives.
