# Fixed userspace stages

This directory replaces generic post-menu services only after a measured,
checksum-gated hardware proof. The permanent target is a reproducible rootfs;
card-side installers are temporary development delivery mechanisms.

## Device discovery

`S10udev-profile` wraps the stock replay without changing its behavior. On the
measured RG34XX-SP boot it proved:

- input devices, ALSA cards/devices and partitions already existed beforehand;
- `mali_kbase` and `/dev/mali0` were the only new module/device pair;
- the remaining changes were generic ownership and `/dev` convenience links;
- the core daemon/trigger/settle phase took approximately 1.51 seconds;
- the replay left one daemon plus temporary workers rather than a fixed result.

`S10fixed-devices` was the first hardware-test candidate. It explicitly loaded
Mali, preserved exact input/audio/Mali permissions and created the `/dev/rtc`
link without starting `udevd`. The menu and shutdown worked, but the existing
compatibility clients did not:

- RetroArch reported that `/run/udev` was missing and discovered no controls;
- MPV and RetroArch failed ALSA hardware initialization;
- the stock hotkey service did not provide game/media exit, system volume or
  brightness handling.

The candidate also proved that explicit `modprobe mali_kbase` itself consumes
about 1.10 seconds. Most of the former 1.51-second udev interval was necessary
GPU probing, not removable database work. The rejected candidate is retained as
evidence and a future endpoint after those clients are replaced.

`S10minimal-udev` is the hardware-verified compatibility proof. The launcher is already
interactive when it runs. It starts udevd, generates records only for the fixed
input and sound subsystems, and overlaps that work with explicit Mali loading.
It omits the all-subsystem/all-device replay and all persistent storage naming.
Games, MP3, movies, controls, system volume/brightness and shutdown passed.
PortMaster/network remains an explicit deferred acceptance check because the
test was performed away from the configured home network.

`S10udev-once` is a rejected proof retained as evidence. It generated the same
input/sound records, paused the execution queue, and attempted to stop udevd.
The daemon did not exit within the one-second guard, so this path added about
1.9 seconds of post-menu work. Games, audio and global hotkeys still worked,
but MPV lost its rich pause, seek, subtitle, speed and player-volume controls.
Those controls are injected by PortMaster's `gptokeyb2` bridge, which uses the
SDL/libudev controller path. System volume, brightness and close continued to
work because the separate global hotkey service owns them.

`device-install-fixed-devices.sh` accepts only the measured profiler checksum,
backs it up and atomically installs the fixed candidate. Run
`stage-fixed-devices.sh /Volumes/BIRD-DATA` on the Mac to deliver it.

`device-install-minimal-udev.sh` accepts either the failed fixed-device proof or
the rejected one-shot checksum, backs it up and atomically installs the narrow
compatibility candidate. Run `stage-minimal-udev.sh /Volumes/BIRD-DATA` to
restore or reproduce the verified checkpoint.

`device-install-udev-once.sh` and `stage-udev-once.sh` are preserved only to
reproduce the failed daemon-lifetime experiment. Do not deploy them as the
current compatibility configuration.

The rules and 9.7 MB hardware database remain installed, and the minimal udevd
stays resident for compatibility. The launcher neither contains nor waits for
it: it is already interactive before this independent stage starts. Replace
`gptokeyb2`/SDL media input and the other remaining libudev clients with fixed
direct-event paths before retrying daemon removal. Delete udev only after the
launcher, every emulator family, MPV audio/video controls, volume, suspend/lid,
the deferred PortMaster/network check and shutdown all pass.

## Entropy lifecycle

`S01entropy-once` preserves the early haveged start that previously prevented
CRNG/audio stalls. The first background guard reused muOS's 256-bit counter
test, but the captured kernel log reached `random: crng init done` while that
condition still kept haveged alive. The revised guard watches that explicit
kernel event, stops the generator afterward, and retains it on an eight-second
timeout. Its completion record and final PID state are written after the ROM
mount exists, independent of the earlier user-init collector.

## Post-menu session-warm audio

`S30dbus-on-demand` and `pipewire-on-demand` are narrow wrappers around the
unaltered stock scripts. The first content-triggered proof kept all three audio
daemons absent until selection and passed the full game/media/system-control
test. Its measured cold initialization cost was about 1.0--1.5 seconds, which
made the first content choice pay avoidable latency.

The verified stage schedules audio only when the existing startup reaches the
wrapper after the menu is interactive. Its worker waits for the system-ready
marker, then runs concurrently with entropy and the noncritical storage tail.
Storage does not depend on CRNG; audio may block only inside its own random
request, and cannot hold the menu or mount path. A lock makes an unusually fast
content selection join the same startup instead of creating duplicate daemons.
Audio remains warm across game/media returns. PortMaster can borrow the same
D-Bus without stopping it underneath PipeWire, while stock-frontend fallback
explicitly ensures audio is ready.

The measured behavior boot drew its input-ready menu at 2.11 seconds, scheduled
audio at 3.60, crossed system-ready at 3.95, started the audio worker at 3.97,
completed D-Bus at 4.22 and completed PipeWire/WirePlumber at 6.31. A game
selected at 18.84 seconds therefore did not pay audio initialization. Games,
MP3, movies and system controls remained functional.

The original installer stored the stock D-Bus implementation at a visible
`S30dbus.bird-real` name. The `S??*` dispatcher consequently ran that file as a
second boot service and left D-Bus resident. The migration hides the preserved
implementation as `.S30dbus.bird-real` and explicitly skips `S30dbus` in the
generic dispatcher. These D-Bus, PipeWire, launcher and dispatcher changes are
checksum-gated and installed as one rollback unit.

The captured default WirePlumber graph enables camera, V4L2, ALSA MIDI,
Bluetooth and logind even though this fixed experience uses only built-in ALSA.
`89-bird-fixed-main.lua` and `89-bird-fixed-bluetooth.lua` turn off those
monitors without replacing the proven sink, volume and stream-linking policy.

`patch-fixed-startup-tail.sh` independently removed delayed generic jobs that
wake 8--20 seconds into a session: USB gadget setup, catalogue generation,
controller and SDL-map rewriting, system-sound preparation, recursive SSH
permission repair, RetroArch precache and log cleanup. It preserves low-battery
monitoring, user-init and delayed `dmesg` diagnostics. The behavior pass after
installation retained games, media, controls and shutdown.

`startup-rg34xxsp.sh` is the next fixed-root step. It replaces the generic
startup coordinator with the exact internal-display RG34XX-SP path: no factory
reset, first-boot, HDMI, rumble-probe or alternate-board branches. Device
setup, fixed storage and session-warm audio remain separate workers. The global
hotkey daemon starts before the storage wait so system controls can become
usable as early as possible, while game/media execution still waits for the
fixed mount-ready marker. Its small TSV trace preserves substage evidence
during development. Startup v2 additionally moves immutable policy and screen
geometry writes to its one-time installer, removes the zero-swap probe and
drops the redundant squashfs module request (the filesystem is already
available without it).

The first `S98bird-stable-snapshot` incorrectly checked its card-side arm file
before `/mnt/mmc` had mounted. The revised explicitly armed hook waits for the
ROM mount, captures the settled process/module/mount state once, clears the arm
and deletes itself from the rootfs. It does not become a permanent service.

Run `stage-fixed-init-orchestrator.sh /Volumes/BIRD-DATA` to stage the fixed
startup and repaired one-shot snapshot as independent installers.

## Fixed runtime policy

The settled snapshot after that coordinator records the menu at 2.06 seconds,
storage priority-ready at 4.20, system-ready at 4.24 and complete audio at 6.02.
At 24.08 seconds, `haveged` and both UnionFS workers are absent. The remaining
shell workers are the generic hotkey wrapper plus its five-second all-PID idle
scanner, lid polling and low-battery polling.

`stage-fixed-runtime-batch.sh` installs eight checksum-gated replacements. Every
source and active target is validated before any target is written. The first
six-target attempt therefore refused safely when its expected device-start
checksum was stale; the corrected value comes from the following settled
snapshot:

- `device-start-rg34xxsp.sh` mounts the display debug interface, applies the
  fixed normal stereo map and starts only the SP lid worker. It performs no
  post-menu brightness or colour write.
- `hotkey-rg34xxsp.sh` retains the proven compiled `muhotkey` event source and
  only the chosen display-idle, explicit suspend and closed-lid policies.
- `lid-rg34xxsp.sh` hardcodes the enabled AXP2202 hall path instead of rereading
  configuration every five seconds.
- `lowpower-rg34xxsp.sh` checks the exact charger/capacity/LED paths once per
  minute, retains the 25 percent warning and removes all RGB/config discovery.
- `charge-rg34xxsp.sh` retains the exact cold-charge frontend path without
  factory-reset, board or device-path discovery.
- `idle-disabled-rg34xxsp.sh` makes obsolete calls harmless; the fixed hotkey
  shell owns display idle, idle sleep is disabled and no `/proc` scan remains.
- `module-rg34xxsp.sh` handles only Mali suspend/resume; built-in SquashFS,
  Wi-Fi, alternate-board GPU and depmod branches are gone.
- `user-init-fixed.sh` dispatches the single fixed card-side init directory
  without loading muOS configuration and formatting helpers.

The migration engine has already been replaced in ordinary user-init by
`99bird-diagnostics.sh`, a 1,504-byte collector for the boot, fixed-startup and
minimal-udev traces. This stage preserves that collector, installs startup v2,
and rearms a self-removing snapshot to record the post-change process set on
the following boot.

The corrected transaction installed all eight targets and the complete game,
media, global-control, lid and shutdown functionality pass succeeded. The
following settled snapshot verifies every replacement checksum and confirms
that the former five-second idle scanner is no longer resident.
