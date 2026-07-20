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

`S10fixed-devices` is the hardware-test candidate. It explicitly loads Mali,
waits only for `/dev/mali0`, preserves exact input/audio/Mali permissions and
creates the `/dev/rtc` link used by shutdown. It does not start `udevd`, replay
unrelated devices or create unused persistent-name trees.

`device-install-fixed-devices.sh` accepts only the measured profiler checksum,
backs it up and atomically installs the fixed candidate. Run
`stage-fixed-devices.sh /Volumes/dani-sp` on the Mac to deliver it.

The rules and 9.7 MB hardware database deliberately remain installed during
this proof. Delete them only after launcher, every emulator family, MPV audio
and video, volume, suspend/lid, PortMaster/network and shutdown all pass without
a udev daemon or database.
