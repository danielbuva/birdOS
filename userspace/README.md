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
`stage-fixed-devices.sh /Volumes/dani-sp` on the Mac to deliver it.

`device-install-minimal-udev.sh` accepts either the failed fixed-device proof or
the rejected one-shot checksum, backs it up and atomically installs the narrow
compatibility candidate. Run `stage-minimal-udev.sh /Volumes/dani-sp` to
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
CRNG/audio stalls. A background readiness guard uses muOS's existing 256-bit
threshold and stops haveged only after it is satisfied; on a five-second
timeout, the daemon remains resident. It is staged independently alongside the
fixed-storage batch so audio behavior and the final haveged PID can be tested
and attributed separately.
