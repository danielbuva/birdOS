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
(50 decimal). A verified candidate changed it to `<0x19>` and booted normally,
but two cold hardware tests showed no visible brightness change. This property
therefore does not own the RG34XX-SP's displayed boot level, at least across its
seamless U-Boot/Linux display handoff. Visible brightness is controlled later
through the Allwinner `dispdbg` `disp0 getbl/setbl` interface.

## Confirmed U-Boot payload and brightness owner

Allwinner boot0 and the checksummed TOC1 package live before the first GPT
partition. The active TOC1 package begins at byte `0x1004000` (sector 32800),
is `0x140000` bytes long and contains four items:

- 1 MiB U-Boot payload at relative offset `0x800`
- 105 KiB ARM trusted monitor at `0x100800`
- 3 KiB DT overlay at `0x11ac00`
- 137,756-byte U-Boot DTB at `0x11b800`

That separate U-Boot DTB contains `lcd_backlight = <50>` and
`lcd_pwm_max_limit = <255>`. The early hardware probe measured all of the
following on the same cold boot:

- active Linux DTB candidate: raw 25
- saved muOS setting: raw 16
- U-Boot DTB: raw 50
- `disp0 getbl`: 50 from 2.31 through 6.35 seconds
- PWM: 50 kHz, 3,906 ns duty over a 20,000 ns period

Only U-Boot's value matches the inherited hardware state. It is therefore the
visible boot-brightness owner; Linux preserves that already-running display.
These are raw 0--255 driver units, not percentages: raw 25 is about 9.8% and a
literal 25% target would be approximately raw 64.

`boot-resource/bootlogo.bmp` is a 720x480 24-bit image shown before Linux. It is
the correct frame-zero asset for a visually immediate boot. The final image can
match the launcher's background so the U-Boot-to-launcher transition appears
continuous even before U-Boot itself is customized.

`fat16-file.py` safely extracts or replaces a fixed-size file in the exact
32 MiB partition payload despite the incorrect 128 MiB BPB size. It follows
the real FAT16 cluster chain and changes no allocation table, directory entry
or timestamp. `build-launcher-boot-resource.sh` first proves a byte-identical
no-change replacement, then generates a 720x480 launcher-aligned first frame
and replaces only `bootlogo.bmp`. The charging image remains stock.

The first frame uses the launcher's exact background, header, bitmap font and
idle accent colours but intentionally omits menu rows. U-Boot can display it
before Linux without pretending input is ready; the interactive launcher adds
the menu at its first real frame.

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

Before the critical-UI patch, BusyBox ran:

`S00chrony -> S01entropy -> S02rgb -> S10udev -> S30dbus -> S99muos`

The staged fixed-device order is now:

`launcher + exact first-frame marker -> entropy -> udev -> D-Bus -> compatibility startup`

RGB, the continuous backlight/process observers and the 60-second background
log-sync sleeper are removed from ordinary boots. Specific firmware diagnostics
remain available as deliberately armed probes. The next lower-layer target is
starting the same static launcher during early-root handoff, before generic
BusyBox startup.

The latest complete kernel log further divides the pre-muOS interval. Built-in
kernel initialization finishes and frees unused memory at 1.809 seconds. The
initramfs checks and mounts the clean ext4 root by 1.852 seconds, after which
switch-root and generic BusyBox inittab work take roughly 0.36 seconds before
the instrumented muOS dispatcher begins. Input is already registered at 1.726
seconds and ALSA at 1.808 seconds. This makes an early-root launcher handoff the
next firmware target before rebuilding the kernel itself.

The 150 ms initramfs unpack currently includes a 2.8 MiB `magic.mgc`, generic
ALSA profiles and recovery utilities unused by normal boot. Kernel logs also
show unconditional USB host, network protocol, Bluetooth, HDMI and extra
SD/SDIO initialization. These are fixed-kernel targets; they cannot be removed
from the ROM partition alone.

## Reproduce the inventory

Install the host dependencies once:

```sh
brew install coreutils e2fsprogs dtc
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

Extract the boot0/TOC1 area and its U-Boot DTB:

```sh
./firmware/extract-stock-bootloader.sh SOURCE_IMG_GZ OUTPUT_DIRECTORY
```

Generate a DTB candidate in raw driver units and repack the TOC1 checksum:

```sh
./firmware/set-backlight-dtb.sh INPUT_DTB OUTPUT_DTB 25
./firmware/repack-toc1-dtb.sh STOCK_TOC1 OUTPUT_DTB OUTPUT_TOC1
```

The TOC1 repacker validates every fixed header, item offset and payload length,
then recomputes Allwinner's stamped additive checksum. Passing the original
U-Boot DTB reproduces the stock package byte-for-byte with SHA-256
`3973c37b2bc1f0b242c5d89b7a64a864d619dc9d9ae21aee40265c62dfc115e5`.
No candidate should be written until both Android-boot and TOC1 no-change round
trips pass offline verification.

## Installed DTB experiment

The hidden card workspace contains:

- `dani-boot-backlight-25.img` — SHA-256
  `eab1f16833a69c8e9a04297d87d0dee1b86980d27edc8e027ae3966b352865bd`
- `rg34xxsp-backlight-25.dtb` — SHA-256
  `8e16058b184bdc7ae46b2d57cc293c9c2f542f5bc7023de501a7d76d69c3c427`

Re-extraction proves that the candidate's kernel and ramdisk are byte-identical
to stock and its `lcd_backlight` reads 25. The complete 64 MiB image differs
from stock at exactly 21 bytes: one DTB value byte and the required 20-byte
Android boot ID. The installer wrote it to `/dev/mmcblk0p4`, read the raw
partition back and matched SHA-256
`eab1f16833a69c8e9a04297d87d0dee1b86980d27edc8e027ae3966b352865bd`.
Two subsequent cold boots remained approximately four seconds and looked
identical in brightness, disproving the working ownership assumption without
regressing boot or launcher behavior.

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

The completed installer is disabled as
`/mnt/mmc/MUOS/init/98-install-backlight-25.sh.done`. Its verified 64 MiB stock
backup is `/mnt/mmc/.firmware-work/device-boot-before-backlight.img`; the
rollback helper remains inert at
`/mnt/mmc/.firmware-work/device-restore-stock-boot.sh`.

`device-backlight-probe.sh` runs asynchronously
before the launcher and never sets a brightness value. It records the configured
brightness, DTB cell, standard backlight sysfs nodes, PWM diagnostics and nine
`disp0 getbl` samples, then persists the result after ROM storage mounts. The one-shot
`device-install-backlight-probe.sh` installs it into the early async init
directory without delaying the usable-screen path.

## Completed U-Boot ownership test

The U-Boot DTB candidate changes raw brightness from 50 to 25. Its SHA-256 is
`5252e2325ad49837f3210d3069f4f5efc0e0aabcc59308fd852aa592b26d482e`.
The repacked TOC1 SHA-256 is
`6330ac906f69a283e76e4a2c4387f6480becefdc1abbadd79fbefd585dccd737`.
The complete package differs from stock at exactly two bytes: the DTB value and
the resulting checksum byte. U-Boot, monitor and DTBO payloads remain
byte-identical.

`device-install-uboot-backlight-25.sh` was installed as a one-shot user-init
installer. It accepts only the exact stock raw TOC1 hash, creates and verifies a
1.25 MiB device backup, writes sector 32800, reads the raw package back and
automatically restores stock on write-verification failure. Because a
checksum-valid but unbootable U-Boot change cannot restore itself, the trusted
stock image remains the external recovery path. The inert on-device helper is
`device-restore-stock-toc1.sh` for cases that still reach user-init.

The cold hardware trace confirmed raw 25 in the active U-Boot/Linux device
tree, `disp0 getbl` and the corresponding 1,953 ns inverse-PWM duty from 2.31
through 6.35 seconds. No later brightness writer exists on this boot path.

## Launcher-aligned frame-zero candidate

Build from an extracted stock boot-resource partition:

```sh
./firmware/build-launcher-boot-resource.sh STOCK_BOOT_RESOURCE OUTPUT_DIRECTORY
```

The no-change FAT16 round trip is byte-identical. The generated BMP is exactly
1,036,938 bytes, 720x480, uncompressed 24-bit BGR with a 138-byte V5 header.
The verified candidate SHA-256 is
`38f42814f8523225e6695f6e446eb435a821410c53214ded80be729f2b138fd7`.
Read-only mounting and `fsck_msdos -n` confirm that the FAT16 filesystem is
valid, `bootlogo.bmp` has changed to SHA-256
`79eddfdd5a452d150ea2d89784da4b094f1e6d2ba05e9d3168e935739a6fc842`,
and `bat/battery_charge.bmp` retains the stock SHA-256
`c0c724acc8bb666b0800fcfd0ba72f9dd117e370dc6137c4cfaa67bee82617e8`.

The device installer intentionally refused to write this candidate: the test
card's active partition hashes to
`eb55e0793d7064e5db4654681e19e1054b94a0736b01a29638b3d564aed81e64`,
not the fresh archive's partition hash. No boot-resource bytes were changed.
The active card was evidently provisioned after flashing, so the archived FAT
asset cannot yet be assumed to own its normal splash. The failed installer is
disabled and this investigation is shelved until after first interaction is
optimized.
