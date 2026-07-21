# Linux 7.0.11 compatibility-build audit

Audit date: 2026-07-21.

This is a source, configuration, DT and reproducibility milestone. It is not a
claim that the replacement kernel has booted the RG34XX-SP.

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
- fixed-device DTB: 35,161 bytes,
  SHA-256 `e379cd18a88b78377a0bde3ee74f001a661e276e64544bca6e719adcef1a67ed`
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

## Remaining gates before trimming

1. Audit Android boot-image packaging and vendor U-Boot's `update dts`
   mutations against the new mainline tree.
2. Produce a checksum-gated, one-command install and restore workflow while
   retaining the accepted vendor boot image as the recovery anchor.
3. Verify internal display/brightness, direct launcher input, power/charging,
   lid/suspend, storage, audio/volume, shutdown and first-frame timing.
4. Verify launcher framebuffer assumptions and input event numbering.
5. Verify games and media on DRM/KMS/Panfrost; the current application stack
   was assembled around the vendor framebuffer/Mali ABI.
6. Verify deferred Wi-Fi/PortMaster, then begin fixed-device config removal in
   independent measured batches.
