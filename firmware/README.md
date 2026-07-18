# RG34XX-SP firmware workspace

This directory records the exact lower-layer layout of the muOS 2601.1 image
used for Dani's RG34XX-SP. Generated images stay outside Git; scripts and
checksums make the analysis repeatable.

## Trusted source

Source archive:

`/Users/dani/Downloads/MustardOS_RG34XX-SP_2601.1_FUNKY_JACARANDA-bc38efa0.img.gz`

SHA-256:

`18c6e1e20421be2bf604cbaf920c3fc69b0ab49c758a0a42e04626499f1444ee`

The raw image is 8,769,240,576 bytes. `gzip -l` reports only 179,305,984
bytes because gzip's legacy ISIZE field wraps at 4 GiB; that value is not the
real image size.

## Partition map

The GPT contains six fixed partitions. Exact LBAs and sizes live in
`layout.tsv`.

| Partition | Offset | Size | Purpose |
| --- | ---: | ---: | --- |
| spare | 36 MiB | 8 MiB | Allwinner boot payload area |
| boot-resource | 44 MiB | 32 MiB | FAT16 splash and charging resources |
| env | 76 MiB | 16 MiB | Allwinner U-Boot environment |
| boot | 92 MiB | 64 MiB | Android boot image v2 |
| rootfs | 156 MiB | 8 GiB | muOS ext4 userspace |
| roms | 8,348 MiB | 4 MiB | exFAT seed expanded after flashing |

The FAT header in `boot-resource` declares 128 MiB even though the GPT grants
it 32 MiB. Its used files are inside the available 32 MiB. Pad a working copy
to 128 MiB before opening it with general FAT/archive tools, then write back
only the original 32 MiB partition payload.

## Confirmed boot payload

The Android boot image uses a 2,048-byte v2 header layout:

- 17,686,536-byte uncompressed AArch64 Linux `Image`
- 2,606,337-byte gzip initramfs
- no second-stage or recovery-DTBO payload
- 137,723-byte device tree at offset 20,297,728

The device tree explicitly identifies `rg34xxsp_v1`, enables the internal LCD,
contains the complete Anbernic GPIO key map and sets `lcd_backlight = <0x32>`
(50 decimal). This is the firmware-established brightness that now remains
stable because the later muOS brightness restore was removed. A future fixed
25% firmware default is therefore `<0x19>`; it belongs here, not in an
asynchronous userspace script.

`boot-resource/bootlogo.bmp` is a 720x480 24-bit image shown before Linux. It is
the correct frame-zero asset for a visually immediate boot. The final image can
match the launcher's background so the U-Boot-to-launcher transition appears
continuous even before U-Boot itself is customized.

## Early Linux findings

The initramfs expands to about 8.0 MiB. Its `/init` mounts proc, sysfs and
devtmpfs, reads the fixed `root=/dev/mmcblk0p5` boot argument, checks and mounts
the rootfs, then switches to the real BusyBox init. The command line already
contains `rootwait quiet splash`, so the one-second `autoconfig` fallback is not
part of a normal SD boot.

The initramfs includes payload unrelated to this path, led by a 2.8 MiB
`magic.mgc` database and generic ALSA profiles. Those are credible trimming
targets, but they must be removed from a repacked copy and timed on hardware;
the current clean-root `e2fsck -y` should also be measured before changing its
policy.

After the root switch, BusyBox runs:

`S00chrony -> S01entropy -> S02rgb -> S10udev -> S30dbus -> S99muos`

The custom launcher already enters before udev, at roughly 2.26 seconds of
kernel uptime, so remaining large perceived-boot gains are now in the static
boot resource, Android boot payload, kernel and U-Boot rather than in the stock
muOS frontend.

## Reproduce the inventory

Install the two host dependencies once:

```sh
brew install coreutils e2fsprogs
```

Extract exact partitions into the hidden workspace on the mounted card:

```sh
./firmware/extract-stock-partitions.sh
```

Validate sizes, ext4 integrity and optionally all checksums:

```sh
./firmware/inspect-stock.sh
./firmware/inspect-stock.sh /Volumes/dani-sp/.firmware-work --checksums
```

Unpack and decompile the Android boot image without changing it:

```sh
./firmware/unpack-boot.sh
```

Repack a DTB into the fixed Android v2 layout:

```sh
./firmware/repack-boot-dtb.sh STOCK_BOOT NEW_DTB OUTPUT_BOOT
```

The repacker preserves all bytes outside the DTB slot and rebuilds the Android
v2 SHA-1 ID using the payload-plus-little-endian-size order specified by the
[official AOSP mkbootimg implementation](https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/main/mkbootimg.py).
Passing the original extracted DTB must reproduce the complete 64 MiB stock
boot partition byte-for-byte; this is the mandatory no-change safety test.

Generate the first fixed-device DTB candidate with a 25% firmware-established
backlight:

```sh
./firmware/set-backlight-dtb.sh INPUT_DTB OUTPUT_DTB 25
```

No firmware candidate should be written to the card's boot partition until its
unpacked kernel, ramdisk, device tree, layout, digest and no-change round trip
all pass offline verification.

## Current candidate (not installed)

The hidden card workspace contains:

- `dani-boot-backlight-25.img` — SHA-256
  `eab1f16833a69c8e9a04297d87d0dee1b86980d27edc8e027ae3966b352865bd`
- `rg34xxsp-backlight-25.dtb` — SHA-256
  `8e16058b184bdc7ae46b2d57cc293c9c2f542f5bc7023de501a7d76d69c3c427`

Re-extraction proves that the candidate's kernel and ramdisk are byte-identical
to stock and its `lcd_backlight` reads 25. The complete 64 MiB image differs
from stock at exactly 21 bytes: one DTB value byte and the required 20-byte
Android boot ID. It has not been written to `/dev/mmcblk0p4`; the active card's
boot firmware remains unchanged until a controlled installer and restore path
are staged.

`device-install-backlight-25.sh` is that controlled one-shot path. It waits
until after the usable-screen path, verifies the candidate, accepts only the
known stock boot-partition hash, creates and verifies a 64 MiB backup, writes
the candidate, reads the raw partition back, and automatically restores stock
if verification fails. It then renames its card-side user-init copy to `.done`.
It deliberately does not reboot the device.

`device-restore-stock-boot.sh` is the inverse helper. It accepts only the known
candidate hash, prefers the device-created backup, verifies the raw restore and
is not installed as a user-init script unless a rollback is intentionally
requested.

The one-shot installer is currently staged as
`/mnt/mmc/MUOS/init/98-install-backlight-25.sh`. The rollback helper is inert at
`/mnt/mmc/.firmware-work/device-restore-stock-boot.sh`. The active boot
partition is still stock at this checkpoint; the installer will change it only
after its first device-side hash check.
