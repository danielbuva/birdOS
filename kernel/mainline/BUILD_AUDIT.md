# Linux 7.0.11 compatibility-build audit

Audit date: 2026-07-21.

This is a source, configuration, DT and reproducibility milestone. The first
hardware candidate did not reach a visible launcher or userspace capture.

## Result

Two clean ARM64 container builds produced byte-identical checksum manifests.
The second build passed `kernel/audit-mainline-compat.sh`, including the exact
release, fixed-device DT, embedded panel stream and every required built-in
first-frame driver.

- release: `7.0.11-dani-compat`
- Linux commit: `bb532bfaf7919c7c98caab81864e9ce2646e11e3`
- ROCKNIX evidence commit: `d88cf6393e55364ec6470d625737125fc0d32cd4`
- `Image`: 28,043,272 bytes,
  SHA-256 `2294fca4c88834d379d063eb08c606224fea2d4eb6a77edd50b6e1b320ab3150`
- fixed-device DTB: 35,197 bytes,
  SHA-256 `5c695aa096d7b03a4d1acceead274e4d8571124f9edbd33b9f0363e4444cb597`
- deterministic module archive: 889,764 bytes,
  SHA-256 `b7efeb24ba87137ff77cc9d65f9d5045394f5ca585a6116fd8df10a295a69e34`

The broad configuration has 1,902 built-in options, 56 module selections and
52 installed module files. Bluetooth is modular. The internal display, DRM
fbdev compatibility, Panfrost, fixed digital and analog input, MMC, ext4,
exFAT, PMIC/regulators/battery/charger, RTC, internal audio and USB-C controller
are built in.

## Deliberate excess

The compatibility baseline still includes KVM, profiling, IPv6, netfilter,
bridging, WireGuard, NFS/server, 9P, Btrfs, F2FS, NAND/MTD, SCSI, USB mass
storage/network adapters, media capture and many alternate drivers. Wi-Fi is
also built in. These are measured removal candidates, not the desired final
profile.

The 28.0 MB image is 10,356,736 bytes larger than the accepted 17.7 MB vendor
image. Size and startup cost will be reduced only after the broad baseline
passes the device compatibility test; otherwise a missing driver and a broken
application ABI would be indistinguishable from an optimization regression.

## Offline boot packaging

The kernel and DTB were packed into the accepted 64 MiB Android boot v2 image.
The repacker first reproduces the accepted image byte-for-byte when passed its
unchanged payloads. The replacement candidate then survives a complete unpack:
its kernel and DTB match the source artifacts, while the accepted direct-handoff
initramfs and launcher remain byte-identical.

- candidate SHA-256:
  `d683c1b9c3f4ed8c67e337a2f1d4527a5f1391b28c8a40c14c5d57660313ea6d`
- U-Boot bootm limit: 33,554,432 bytes; kernel: 28,043,272 bytes
- kernel load end: `0x41b3e808`; fixed ramdisk address: `0x42000000`
- remaining non-overlap margin: 4,986,872 bytes
- DTB working capacity: 141,856 bytes; DTB: 35,197 bytes

The known vendor DT mutations also pass the offline simulation described in
[`UBOOT_HANDOFF_AUDIT.md`](UBOOT_HANDOFF_AUDIT.md).

On 2026-07-21 the exact candidate, one-shot installer, first-boot collector and
external recovery helper were byte-verified after staging on the test card.
The installer successfully backed up, wrote and reread the candidate. On the
following cold boot the device remained indefinitely on the U-Boot logo and no
collector directory was created. The guarded external restore then rewrote and
reread all 64 MiB as accepted image `872a3d0d...7764f`. See
[`FIRST_BOOT_RESULT.md`](FIRST_BOOT_RESULT.md).

## Remaining gates before trimming

1. Use the checksum-gated installer and external Mac restore workflow while
   retaining the accepted vendor boot image as the recovery anchor.
2. Verify internal display/brightness, direct launcher input, power/charging,
   lid/suspend, storage, audio/volume, shutdown and first-frame timing.
3. Verify launcher framebuffer assumptions and input event numbering.
4. Verify games and media on DRM/KMS/Panfrost; the current application stack
   was assembled around the vendor framebuffer/Mali ABI.
5. Verify deferred Wi-Fi/PortMaster, then begin fixed-device config removal in
   independent measured batches.
