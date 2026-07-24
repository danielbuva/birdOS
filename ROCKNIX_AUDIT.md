# ROCKNIX compatibility audit

Bird keeps the exact ROCKNIX 20260701 application provider because its broad
physical compatibility gate passes. Keeping the provider does not mean keeping
every generic boot decision. This audit separates the small menu-critical
closure from the later application-compatibility closure and replaces generic
discovery only after its consumers are proven.

## Measured boundaries

The last physically accepted v6.14 boot recorded:

| Boundary | Kernel uptime | Meaning |
| --- | ---: | --- |
| Bird pixels visible | 1.340 s | Direct framebuffer menu exists |
| H700 input ready | 1.454 s | Menu is interactive |
| Fixed p6 storage retained | 2.810 s | Cached rows have live files |
| Generic ROCKNIX autostart entered | 8.721 s | Compatibility generation begins |
| Generic ROCKNIX autostart completed | 16.756 s | Full application contract exists |

The first three boundaries are Bird's user experience. The last two explain why
an unusually early game selection can still queue even though the menu itself
is already responsive. Optimizing that later interval improves time-to-content
and background efficiency; it does not need to block or enter the launcher.

## What Bird retains now

- systemd as the current final-root service manager;
- udev for the complete coldplug/rule compatibility pass;
- D-Bus, PipeWire and WirePlumber for applications and audio;
- seatd and logind until their exact Sway/application consumers are measured;
- the H700 platform/device quirks, controller setup, config provisioning,
  performance policy, rumble, audio routing and Sway configuration;
- stock `runemu.sh`, emulator/core selection, standalone wrappers, MPV and
  PortMaster providers.

These are retained compatibility components, not permanent design decisions.
They stay out of the launcher and may run asynchronously whenever their
dependencies permit.

## v6.15 subtraction

The following common-autostart scripts are deterministic no-ops for the fixed
offline RG34XX-SP profile and are bind-replaced by one two-line exit script:

- update-hint handling, root/Samba password setup, Bluetooth, Moonlight and
  Weston UI-mode generation;
- HDMI scan, dual-display discovery, boot Wi-Fi and USB-gadget startup;
- generic fan/headphone/HDMI/battery/input service switching; and
- the generic configured-daemon start/stop loop.

The fixed input and power services are already requested directly by the Bird
target. Network services remain behind Bird's explicit PortMaster request. The
RG34XX-SP's single internal display is published as a constant rather than
running `modetest`.

ROCKNIX's `006-display` and Bird's old post-frame preparation both rewrote the
backlight after the menu appeared. The accepted trace shows the initramfs set
raw 124/2499 (about five percent), then the later preparation wrote 624/2499
(25 percent) at 8.45 seconds. v6.15 removes both late writes. Manual brightness
changes now have one owner and should remain stable.

Shutdown retains systemd's ordered unmount and poweroff. The generic config
checkpoint sourced the complete interactive profile, ran `grep`, and copied a
small unchanged file. Its replacement compares the exact file, copies only on
change, logs the boundary, and Bird submits the poweroff job without blocking
its supervisor.

The power worker's low-battery red-status threshold is now exactly 41 percent.
Charging remains kernel/PMIC-owned and the green LED remains the ordinary
power indicator.

## v6.15 physical result and v6.16 correction

The physical gate passed brightness stability and visible shutdown at roughly
1.8--2.0 seconds. The shutdown log places its exact config compare/copy at
40 ms. The memory capture proves `ksm_run=0`, with every KSM sharing counter at
zero. Generic autostart now enters at 8.681 seconds and completes at 12.263
seconds: 3.58 seconds instead of the prior roughly eight-second tail.

Content selections were reported as permanently queued for storage. The final
returned boot itself recorded a successful FIFO, retained storage at 2.888
seconds, the complete p6 mounts and no A-selection log before shutdown, so that
trace cannot identify the failed edge. v6.16 removes the possibility anyway:
selection synchronously revalidates the real retained directory, and a bounded
50 ms probe backs up the FIFO only until storage succeeds. There is no ongoing
storage polling afterward.

V6.16 also replaces `111-sway-init` with the exact output captured from the
working card: `/dev/dri/card1`, `DSI-1`, DRM/libinput, zero transform and the
existing tearing/render-time policy. HDMI/DP discovery and `output_monitor`
leave the ordinary application session. The fixed script never masks or
unmasks `essway.service`. Both mismatched audio-latency scripts are suppressed
because the pinned writable image already contains the required value 64.
Finally, systemd's RF-kill process and activation socket leave offline boot;
the exact process is condition-released with the existing PortMaster network
transaction.

## Bugs and inefficiencies found

These remain after v6.15 and are ordered for later fixed replacements:

1. `111-sway-init` is an 11.5 KiB device-family script. It scans DRM connectors,
   EDIDs, rotations, dual panels and many unrelated products, then rewrites the
   Sway config every boot. A generated RG34XX-SP Sway profile is the largest
   obvious application-contract target.
2. `050-audio` uses `[ -n "/usr/sbin/quantum" ]`, which is always true; it
   should test whether the executable exists. It also performs generic HDMI,
   Bluetooth and route discovery on a fixed internal codec.
3. `020-set_audio_latency` reads `audiolatency` but writes
   `global.audiolatency`, an inconsistent key pair.
4. `020-configs` tests relative `.quirk-*` marker paths while writing markers
   under `/storage`, which can repeat expensive `rsync` work depending on its
   working directory.
5. `055-hdmi-check` performs two DRM scans and contains an unquoted numeric
   test. Bird suppresses it because HDMI is not a boot feature.
6. `098-deviceutils` and `099-networkservices` repeatedly ask systemd to start
   or stop whole device-family service sets even when the fixed target and unit
   masks already express the answer. Bird suppresses them in v6.15.
7. The generic autostart runner serially visits platform, device and 27 common
   script slots, then joins background work. Replace it only after every
   retained output file and application consumer is catalogued.

## Next active order

1. Physically gate v6.16: storage recovery, fixed Sway content suite, suspend,
   PortMaster, charging indicator, low-battery LED policy and shutdown time.
2. If the v6.16 Sway profile passes, remove the generic connector generator
   permanently from the reproducible image.
3. Replace generic audio setup with a fixed H700 route while preserving the
   already-warm asynchronous audio services.
4. Audit udev coldplug output and let its manager exit if no retained feature
   needs runtime hotplug; keep fixed hardware initialization separate from
   Bird.
5. Audit logind versus seatd, journald policy, and remaining idle wakeups.
6. Remove the muOS-to-ROCKNIX compatibility namespace as an explicit migration:
   canonical `/storage/roms`, `/run/bird`, Bird-owned data/config directories,
   native BIOS/Ports paths and no launcher-time path rewriting.
7. Re-measure menu, storage and application-contract boundaries before kernel
   or U-Boot subtraction.

## Deliberately deferred

- survey muOS and other operating systems for transferable optimizations;
- emulator/RetroArch experience and cold-load tuning;
- PortMaster load-time tuning;
- bespoke music, movie, emulator and application experiences;
- suspend/wake battery optimization; and
- final boot animation, sound and media-player control design.

Those are preserved roadmap items, not rejected work. They follow the current
ROCKNIX audit and namespace cleanup so they are tuned on Bird's final contracts.
