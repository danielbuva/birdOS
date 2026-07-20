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
remain available as deliberately armed probes. The staged intermediate proof
adds the launcher immediately after BusyBox's essential mounts and `/run` setup,
before the generic sysinit tree; it does not alter the boot partition. Hardware
testing verified that boundary with fully functional sub-four-second boots.

The latest complete kernel log further divides the pre-muOS interval. Built-in
kernel initialization finishes and frees unused memory at 1.809 seconds. The
initramfs checks and mounts the clean ext4 root by 1.852 seconds, after which
switch-root and generic BusyBox inittab work take roughly 0.36 seconds before
the instrumented muOS dispatcher begins. Input is already registered at 1.726
seconds and ALSA at 1.808 seconds. The inittab proof attacks the tail of that
interval; moving it across `switch_root` in the boot image attacks the remainder
before rebuilding the kernel itself.

`build-initramfs-launcher.sh` builds the next candidate from the exact installed
backlight-25 boot image. It links the launcher as a stripped static AArch64 ELF,
embeds it in initramfs, bind mounts it into the already-mounted root, starts the
existing supervisor in that root, waits only for the first-frame marker, then
executes `switch_root`. Generic root BusyBox init therefore begins after the
interactive frame.

Hardware verification records supervisor starts at 2.00 and 2.06 seconds,
interactive frames at 2.029 and 2.082 seconds, and generic root dispatch only
at 2.25 and 2.30 seconds. Each boot contains one supervisor start. This proves
that the pre-`switch_root` process survives the handoff rather than being
replaced by the root fallback.

BusyBox is not a daemon: its current initramfs shell interprets `/init`, and its
root `init` becomes PID 1 after `switch_root`; individual applets run only when
invoked. This candidate defers generic root init but still uses a BusyBox shell
for mount and supervisor glue. The permanent architecture replaces that glue
with a tiny static PID 1, invokes compatibility applets on demand, and then
either rebuilds BusyBox with the measured minimal applet set or removes it from
the normal path entirely.

`build-fixed-initramfs.sh` implements the first half of that replacement. Its
6,424-byte freestanding AArch64 `/init` hardcodes `/dev/mmcblk0p5`, invokes the
existing filesystem check, mounts only proc, sysfs, devtmpfs, the ext4 root,
`/run`, and `/tmp`, dispatches the verified launcher supervisor, waits for its
exact first-frame marker, then uses the existing `switch_root`. NAND, MTD,
autoconfiguration, command-line parsing, `awk`, `grep`, `expr`, and generic
getty branches are absent from the executable. The verified shell path remains
as `/init.stock` for failures before the root is mounted; the existing root
BusyBox PID 1 remains the second phase.

Hardware verification records three explicit `fixed initramfs path: active`
markers, supervisor starts at 1.93--1.96 seconds, and input-ready frames at
1.957--1.980 seconds. No shell fallback activated. This is about 88 ms earlier
than the preceding pre-`switch_root` shell implementation.

The build normalizes host-dependent newc CPIO inode identity without changing
device-node identities or payload bytes. Two clean builds produced the same
2,769,443-byte compressed initramfs, Android SHA-1 boot ID, and complete 64 MiB
image. The hardware-verified image is SHA-256
`3f6e8b07826ba307ff22665b9ca4d6cd2a485ce3b5162be95c7eacfa8301578c`.

`build-static-pid1.sh` produces the hardware-verified static-root candidate. It
binds a 5,128-byte static executable into the future root and asks the existing
`switch_root` applet to execute it as PID 1 instead of `/init`. That binary
performs only the remaining devpts, shared-memory, fixed symlink and hostname
setup, dispatches compatibility sysinit behind the already-interactive menu,
reaps orphaned children, and blocks on a signal file descriptor without idle
polling. BusyBox remains available as feature-triggered applets and as an
automatic root-init fallback. Two clean builds produce the same 2,772,302-byte
ramdisk and complete image, SHA-256
`c8e5e713488bb334e083ba1c686ac3b405ea96b7b98c3e7957ca3f32edec5bf3`.

`stage-static-pid1.sh` places the image and a checksum-gated one-shot installer
on the ROM partition. The installer accepts only the hardware-verified fixed
init image, backs up all 64 MiB of the active boot partition, rereads the write,
and restores automatically if raw verification fails. It also updates the late
timing collector so the following boot records `static_pid1_active`.

The installer raw-verified the complete partition on device. Three subsequent
boots recorded `static_pid1_active`, launched libretro content, returned to the
exact launcher screen and powered off normally. Input-ready frames were at
2.032, 2.093 and 2.103 seconds; the approximately 3.8-second stopwatch result
was unchanged because root PID 1 begins after the menu is already interactive.

The 150 ms initramfs unpack currently includes a 2.8 MiB `magic.mgc`, generic
ALSA profiles and recovery utilities unused by normal boot. Kernel logs also
show unconditional USB host, network protocol, Bluetooth, HDMI and extra
SD/SDIO initialization. These are fixed-kernel targets; they cannot be removed
from the ROM partition alone.

The cold-game profile exposes a second firmware-build target. The 12.4 MB
generic RetroArch executable directly requests 24 shared libraries, including
FFmpeg codec/device/format/scaling/resampling, ASS subtitles, FriBidi,
Fontconfig, FreeType and libusb. Flycast adds a 22.4 MB cold core. The measured
first Dreamcast launch spent 5.67 seconds between `exec` and the first identity
color-stage message versus 1.79 seconds warm. A fixed RetroArch build can remove
the unused dependency graph instead of hiding it with unconditional prefetch.

## Reproduce the inventory

Install the host dependencies once:

```sh
brew install coreutils e2fsprogs dtc lld
```

Extract exact partitions into the hidden workspace on the mounted card:

```sh
./firmware/extract-stock-partitions.sh
```

Build and stage the pre-`switch_root` launcher candidate:

```sh
./firmware/build-initramfs-launcher.sh
./firmware/stage-initramfs-launcher.sh
```

After hardware-verifying that image, build and stage the fixed `/init`
candidate:

```sh
./firmware/build-fixed-initramfs.sh
./firmware/stage-fixed-initramfs.sh
```

Build and stage the static root PID 1 candidate:

```sh
./firmware/build-static-pid1.sh
./firmware/stage-static-pid1.sh
```

The installation boot continues using the verified shell image. Leave that
boot running for at least 30 seconds so the installer can back up, write and
reread the raw partition. The following cold boot tests the static init.

The launcher builder refuses any base other than the exact installed
backlight-25 boot image. It verifies that kernel and DTB bytes are unchanged
after repacking and that the embedded executable and patched `/init` survive a
complete unpack. The fixed-init builder similarly requires the exact
hardware-verified launcher image and verifies `/init`, `/init.stock`, the
launcher, kernel and DTB after another complete unpack.
The device installer then verifies the 64 MiB candidate, backs up the active raw
boot partition to `.firmware-work/device-boot-before-initramfs-launcher.img`,
writes it, rereads the raw partition and automatically restores the backup if
verification fails. The installation boot still uses the previous image; the
following cold boot tests the candidate.

The first verified build links the complete 5,953-game launcher to 621,736
bytes. Its compressed initramfs grows from 2,606,337 to 2,768,060 bytes: only
161,723 bytes. The exact staged 64 MiB candidate is SHA-256
`316cb568015cf7d13ab5b33ab9b7d5fb8e274de59d5951951e5cbe8449fd5107`.

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

## Installed raw-3 startup brightness

The requested fixed startup level is encoded where the panel level originates:
U-Boot's DTB. Raw `3/255` is the nearest integer representation of 1% of the
driver range, or 1.18%. It is not a promise of linear optical luminance and is
not necessarily the same scale exposed by manual brightness controls.
`build-uboot-backlight.sh` starts from the hardware-verified raw-25
package, proves a byte-identical no-change repack, changes the DTB value to 3,
and recomputes the Allwinner package checksum. The result changes exactly two
of 1,310,720 bytes. U-Boot, the trusted monitor, overlay, remaining DTB
properties and Android boot image are unchanged.

The installed and raw-verified TOC1 candidate is SHA-256
`50fe29fb4f8783c1abf97d610dbdbba466da296f516b24311b8124b711c84720`.
Its one-shot installer accepts only the active raw-25 package, backs it up,
writes and rereads sector 32800, and automatically restores raw 25 on a write
mismatch. It performs no userspace brightness write, so there is no later
brightness transition or repaint.

Build and stage it with:

```sh
./firmware/build-uboot-backlight.sh
./firmware/stage-uboot-backlight-3.sh
```

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
