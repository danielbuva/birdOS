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

`S10udev-once` is the next proof. It generates the same verified input/sound
records, waits for all work, then stops udevd while preserving `/run/udev/data`.
This changes daemon lifetime without changing the metadata consumed by the
existing clients.

`device-install-fixed-devices.sh` accepts only the measured profiler checksum,
backs it up and atomically installs the fixed candidate. Run
`stage-fixed-devices.sh /Volumes/dani-sp` on the Mac to deliver it.

`device-install-minimal-udev.sh` accepts only that failed fixed-device checksum,
backs it up and atomically installs the narrow compatibility candidate. Run
`stage-minimal-udev.sh /Volumes/dani-sp` to reproduce the verified checkpoint.

`device-install-udev-once.sh` accepts only the verified minimal-udev checksum
and installs the no-resident-daemon candidate. Run
`stage-udev-once.sh /Volumes/dani-sp` to deliver the active proof.

The rules and 9.7 MB hardware database remain installed. After the one-shot
proof passes, replace remaining libudev clients or generate their fixed records
directly. Delete udev only after launcher, every emulator family, MPV audio and
video, volume, suspend/lid, the deferred PortMaster/network check and shutdown
all pass.
