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

## v6.15 result through the v6.21 hardening pass

The physical gate passed brightness stability and visible shutdown at roughly
1.8--2.0 seconds. The shutdown log places its exact config compare/copy at
40 ms. The memory capture proves `ksm_run=0`, with every KSM sharing counter at
zero. Generic autostart now enters at 8.681 seconds and completes at 12.263
seconds: 3.58 seconds instead of the prior roughly eight-second tail.

Content selections were reported as permanently queued for storage. The final
returned boot itself recorded a successful FIFO, retained storage at 2.888
seconds, the complete p6 mounts and no A-selection log before shutdown, so that
trace could not identify the failed edge. V6.16 added synchronous selection
revalidation and a bounded 50 ms backup probe. Its own physical trace then
captured the failure precisely: the FIFO arrived at 2.899 seconds, neither
late absolute directory became a retained descriptor, init timed out at 3.60
seconds and the otherwise healthy early owner preserved the queue indefinitely.

V6.16 also replaces `111-sway-init` with the exact output captured from the
working card: `/dev/dri/card1`, `DSI-1`, DRM/libinput, zero transform and the
existing tearing/render-time policy. HDMI/DP discovery and `output_monitor`
leave the ordinary application session. The fixed script never masks or
unmasks `essway.service`. Both mismatched audio-latency scripts are suppressed
because the pinned writable image already contains the required value 64.
Finally, systemd's RF-kill process and activation socket leave offline boot;
the exact process is condition-released with the existing PortMaster network
transaction.

V6.17 tested bind aliases below the retained `/run/muos` directory. Init
published them at 3.07 seconds, but the old-root process still could not open
them. Its bounded timeout retired that process at 4.45 seconds and the normal
root launcher recovered at 7.12 seconds, proving the fallback while explaining
the first repaint. The compatibility coordinator then requested the already
running UI again and a second supervisor appeared near 10 seconds. PortMaster
started every requested provider, but `nm-online` timed out with no connection.

V6.18 deletes the two failed alias mounts. Init now sends one readiness event
after `prepare_sysroot` has moved the completed tree to `/sysroot/storage` but
before `/run` and the other special mounts move. Bird opens that stable path,
acknowledges it and retains the same PID; the timeout fallback remains. The
exact release autostart script is generated with only its redundant UI start,
associated log line and private-console clear removed (2,168 to 2,066 bytes).
Supervisor signal traps will identify any other lifecycle owner. Networking
reloads the saved keyfiles, explicitly activates the sole Wi-Fi profile, waits
for connectivity and records connection/device/reason/route data without the
PSK. Neither credentials nor network work enter offline boot.

The v6.18 physical gate passed every tested menu, storage, application, media,
brightness, control and shutdown path with no redraw regression. Storage became
usable at 2.479 seconds; the post-`prepare_sysroot` acknowledgement took zero
wait iterations. PortMaster remained offline. Its trace proves the saved WPA
keyfile is valid and visible, but Bird requested activation without ROCKNIX's
required iwd-device wait and NetworkManager scan; `wlan0` remained disconnected
with no route.

V6.19 reproduces the necessary fixed connection sequence: unblock the radio,
start iwd and NetworkManager in order, wait for iwd to register `wlan0`, scan,
then activate the sole saved profile on that interface. Failure evidence now
includes rfkill, scan and the two relevant journals. Offline boot is unchanged.
The coordinator also drops its already-completed storage request. Four common
slots are now proven no-ops for the pinned image: its 54-file, 548 KiB module
tree is byte-identical, the compatibility link already exists, no device switch
is present and H700/RG34XX-SP has no config overlay. Seven constant H700 writers
become one checked Bird profile transaction. Suspend-mode and GPU-overclock
side effects remain exact until separately audited.

The v6.19 physical trace proves scanning itself is correct: `BC9FFE` appeared
at 65-percent signal, the radio was unblocked and iwd registered `wlan0`.
NetworkManager nevertheless rejected the manually created profile immediately
at its prepare transition with no reason. Further Wi-Fi work is deferred until
the stock UI creates a working profile whose exact state can be copied.

More importantly, the trace explains the redraw and reboot regressions. A
provisional `essway` supervisor started near 5.6 seconds, was terminated at the
graphical transition near 8.4 and then replayed the still-armed request. The
post-frame audit was a oneshot wanted by `rocknix.target`; any slow diagnostic
there kept the target job open until `JobTimeoutAction=reboot-force`. V6.20
orders `essway` after `graphical.target`, so the initramfs Bird remains sole
owner until one stable final supervisor adopts it. The audit becomes an
idle-priority `Type=simple` service: systemd considers it started immediately,
so diagnostics cannot trigger the boot watchdog.

The v6.20 physical gate passed without either reboot or movie black-screen
failure. One Library selection froze and recovered at Home before a reboot;
the latest-only logs had already overwritten that failed boot. The launcher
also bounded its fixed input search at `event7` even though the snapshot saw 11
input classes, and the intended continuous volatile UI checkpoint was not
enabled by either build. V6.21 searches `event0` through `event31`, enables the
checkpoint in both launcher binaries and archives supervisor, early-launcher
and boot-state logs by boot ID. A recovery therefore returns to the exact view
and retains its own evidence instead of silently looking like a Home reset.

Lid wake also changed visible brightness because the retained generic fake
suspend toggles `bl_power` without owning Bird's exact raw level. A separate
Bird wrapper now saves that value before the provider transaction and restores
it after resume. The fixed controls binary writes the known backlight sysfs
directly instead of spawning the generic Bash/find/bc/settings stack; its last
down-step reaches raw level one while zero remains reserved for display-off.

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

1. Physically gate v6.21: repeat Library entry before and after the graphical
   boundary, exact brightness across both suspend paths, raw-one recovery,
   retained content suite and shutdown.
2. Replace generic audio setup with a fixed H700 route while preserving the
   already-warm asynchronous audio services.
3. Audit udev coldplug output and let its manager exit if no retained feature
   needs runtime hotplug; keep fixed hardware initialization separate from
   Bird.
4. Audit logind versus seatd, journald policy, and remaining idle wakeups.
5. Remove the muOS-to-ROCKNIX compatibility namespace as an explicit migration:
   canonical `/storage/roms`, `/run/bird`, Bird-owned data/config directories,
   native BIOS/Ports paths and no launcher-time path rewriting.
6. Re-measure menu, storage and application-contract boundaries before kernel
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
