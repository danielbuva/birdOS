# RG34XX-SP firmware workspace

**Status:** this document is the historical muOS firmware, bootloader,
power-key and clean-root investigation. Its measurements remain hardware
evidence, but its old deployment paths are not the active stock-root build.
See [`ACTIVE_PATH.md`](../ACTIVE_PATH.md) for the current system.

Three tools in this directory do participate in the active path:

- [`mac-update-rocknix-stock-root-v6.sh`](mac-update-rocknix-stock-root-v6.sh)
  transactionally stages and activates the complete manifest-verified release;
  and
- [`mac-migrate-rocknix-ports.sh`](mac-migrate-rocknix-ports.sh) performs the
  explicit, resumable same-volume legacy Ports data migration that must finish
  before deployment. Set `BIRD` and `DATA` when either mounted volume uses a
  custom Finder label; and
- [`migrate-bird-namespace.py`](migrate-bird-namespace.py) owns the Stage 6
  canonical-namespace prepare, commit, status and rollback transaction. It
  creates fresh active Bird state, copies only live persistence and verified
  BIOS data, and leaves the complete legacy tree available to the fallback.

Card-writing operations validate the same removable p1/p6 card identity and serialize
through one host-side atomic card lock. This protects concurrent Mac processes;
it is not a claim of FAT metadata durability across sudden power loss.

For ordinary builds and deployments, invoke the guarded repository-level
`./build-and-deploy.sh --release` or `./build-and-deploy.sh --profile` command
instead of calling the updater directly. The lower-level updater remains the
transaction authority and is still useful to the host fault-injection suite.

Their contracts are defined by [`ACTIVE_PATH.md`](../ACTIVE_PATH.md); the
firmware experiments documented below are historical evidence.

This directory records the exact lower-layer layout of the muOS 2601.1 image
used for the target RG34XX-SP. Generated images stay outside Git; scripts and
checksums make the analysis repeatable.

## Trusted source

Source archive:

`$HOME/Downloads/MustardOS_RG34XX-SP_2601.1_FUNKY_JACARANDA-bc38efa0.img.gz`

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

The same U-Boot DTB proves that display onset is lower-layer work:
`disp_init_enable = 1`, the fixed LCD driver is `rg34xxsp_v1`, and its panel,
PWM and backlight GPIO sequence is already active before Linux. Linux inherits
that display. Turning the panel on earlier therefore means measuring and
shortening U-Boot's fixed panel/boot-resource path, not adding launcher code.
The upper work indicator is bi-colour: the exact DTB maps PI11 to red/status
and PI12 to green/power. The verified 512-to-128 ms retained PMIC power-key
setting moves power acceptance earlier, but the ROCKNIX DDR4 U-Boot defconfig
currently selects GPIO 267/PI11 red as its status LED. A guarded U-Boot test
must switch that policy to GPIO 268/PI12 before attributing remaining colour or
assertion delay to the PMIC. Any such delay is below userspace.

## Early Linux findings

The initramfs expands to about 8.0 MiB. Its `/init` mounts proc, sysfs and
devtmpfs, reads the fixed `root=/dev/mmcblk0p5` boot argument, checks and mounts
the rootfs, then switches to the real BusyBox init. The command line already
contains `rootwait quiet splash`, so the one-second `autoconfig` fallback is not
part of a normal SD boot.

The initramfs included payload unrelated to this path, led by a 2.8 MiB
`magic.mgc` database and generic ALSA profiles. `build-trimmed-initramfs.sh`
now removes those plus unused filesystem-creation, FAT, CIFS and serial-transfer
tools from an exact copy of the active power-key image. The retained recovery
closure is BusyBox, `e2fsck`, and the seven shared libraries those two binaries
actually request.

The same candidate reads four bytes at ext4 superblock offset 56 before mount:
magic `53 ef` and state `01 00` skip the clean-root check, while error state
`03 00`, a dirty state, a short read or unexpected magic invokes the existing
`e2fsck -y`. A synthetic ext4 image verified both clean and forced-check byte
patterns. The compressed ramdisk falls from 2,772,302 to 1,725,023 bytes and
two independent builds produce SHA-256
`ff447e7243f7031d99f3559a57868e2116cbf8508fc0654926ef66e5b4460f70`.
The kernel, DTB, embedded launcher, static root PID 1 and stock shell fallback
remain byte-identical to the active base.

Hardware acceptance confirms the trimmed marker, normal controls/content and
the raw candidate checksum. Two preceding boots spent about 159 ms expanding a
2,704 KiB initrd; two trimmed boots spend about 95 ms and free 1,684 KiB. The
latest ordinary interactive marker is 1.98 seconds versus 2.06 immediately
before this change.

`build-direct-handoff-initramfs.sh` removes the last BusyBox invocation from
the successful first-stage path. The 9,312-byte static init implements the
kernel-documented switch-root sequence directly: retain the mounted `/mnt`
filesystem, delete only the old rootfs contents, move `/mnt` over `/`, chroot,
and execute the already-proven static root PID 1. Its deletion walk never
descends into `/mnt` and repeats directory passes so changing offsets cannot
leave initramfs payload resident. BusyBox and `/init.stock` remain untouched
for failures before this boundary.

Two direct builds from the accepted trimmed image and a single-pass build from
the earlier power-key image all produce the same complete 64 MiB SHA-256:
`da5549e1cdad5b9f445f4634dacc0254fd468148182175a06b43346dc1dddbc7`.
The staged diagnostics separately record direct-handoff and clean-fs markers.
Hardware acceptance passed all tested functionality at about 3.8 seconds by
stopwatch. The corresponding internal trace reaches an input-ready frame at
1.98 seconds, records direct handoff and clean-filesystem skip, and starts the
remaining root sysinit only after that frame.

## Fixed-device DTB v1

`build-fixed-device-dtb-v1.sh` repacks the accepted direct-handoff image with
exactly 20 device-tree status changes. It disables unused USB host controllers
1–3, the empty second SD slot, HDMI/HDMI-audio/TV, video input/deinterlace and
Bluetooth/UART1. It preserves USB controller 0, main SD, Wi-Fi, internal audio,
display/input, PMIC/RTC and GPU. Kernel and initramfs comparisons must remain
byte-for-byte identical.

The verified 64 MiB candidate SHA-256 is
`872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f`.
The guarded installer accepts only the hardware-verified direct-handoff image,
backs it up, writes and rereads the candidate, and restores automatically on a
write mismatch. A marker-gated collector stays armed during the installation
boot and records the following candidate boot.

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

## Power-key threshold proof

The Linux DTB programs the AXP2202/AXP2101-compatible power key for a 512 ms
cold-power hold, while the U-Boot DTB already requests the PMIC's 128 ms
minimum. `build-power-key-128.sh` patches only the Linux property in the exact
static-PID1 image. A complete repack/unpack verification proves the kernel and
initramfs are byte-identical and the 1,500/6,000 ms long/forced-off thresholds
are unchanged. The candidate SHA-256 is
`a6bafa83add62af92a27450594f6da4e8dfacdbcc0c247c08c512a7b1495b6b5`.

Because Linux can program only the *next* cold-power state, the installation
boot writes the image, the following boot runs the new driver and programs the
PMIC, and only the third boot is a valid short-tap test. The device installer
backs up and raw-verifies all 64 MiB with automatic restore on mismatch.

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
./firmware/inspect-stock.sh /Volumes/BIRD-DATA/.firmware-work --checksums
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

## Source-built Linux 7.0.11 compatibility image

`repack-boot-kernel-dtb.sh` replaces both variable-sized payloads while
preserving the accepted ramdisk and every byte outside the repacked Android
payload area. Passing the accepted kernel and DTB reproduces the full 64 MiB
base image byte-for-byte.

`build-mainline-compat-boot.sh` admits only the hardware-verified fixed-device
base and the checksum-audited kernel output. It rebuilds the Android SHA-1 ID,
unpacks the result and verifies that the direct-handoff initramfs and launcher
did not change. It also rejects a kernel over U-Boot's 32 MiB bootm limit, a
kernel that reaches the fixed ramdisk address, or any payload beyond the boot
partition.

The first offline candidate is SHA-256
`d683c1b9c3f4ed8c67e337a2f1d4527a5f1391b28c8a40c14c5d57660313ea6d`.
It is not installed by the build. `stage-mainline-compat.sh` places a one-shot
checksum-gated installer and first-boot collector on the ROM partition. The
installer creates a verified copy of the accepted 64 MiB boot partition before
writing anything. `mac-restore-mainline-compat.sh` is the external recovery
path: with the card connected to macOS, it accepts only the known external
partition layout, candidate hash and device-created backup before restoring raw
partition 4.

That exact set was hardware-tested on 2026-07-21. The install boot successfully
backed up, wrote and reread the candidate, but the following cold boot remained
on the U-Boot logo and produced no userspace capture. The external workflow was
then exercised: it restored and reread all 64 MiB as accepted image
`872a3d0d...7764f`. The on-card installer and collector were disabled; the
candidate and recovery image remain only as evidence.

`build-mainline-diagnostic-boot.sh` keeps that candidate's exact kernel but
rebuilds `/init` with opt-in red-LED boundaries and substitutes the diagnostic
DTB. Two builds produced the same 64 MiB image, SHA-256
`8b9ba42467b9879b94a7f61241fc5065c31206b71da1f29c21c6c13e993f9078`.
`stage-mainline-diagnostic.sh` stages its fixed-hash installer, success
collector and matching external restore helper. It is a failure-localization
image, not a performance candidate.

The diagnostic was hardware-tested and also remained on the retained U-Boot
logo without producing its userspace capture. That cycle reported no visible
red pattern and incorrectly inferred the device lacked a red status LED. Later
hardware observation plus the exact DTB prove PI11 red/status and PI12
green/power; the diagnostic remains invalid because it supplied no boundary
evidence and did not account for U-Boot's existing PI11 ownership. Exact-hash
external recovery again restored and reread accepted partition 4, and both
failed candidate installers are disabled.

Those failures belonged to the hybrid vendor-Android handoff, not to the
source kernel itself. The later exact ROCKNIX DDR4 chain booted, and the first
Bird-enabled source kernel reached its frame at 1.547 seconds. Compatibility
v2 prevented fbcon from reclaiming the display and rejected the wrong input
node, but never found `H700 Gamepad`: that device is created by a separately
packaged ROCKNIX driver that the initial Linux-only source gate omitted. Its
watchdog therefore rebooted the sole Bird label rather than entering a second
fallback image. Compatibility v3 embeds the exact pinned GPL module, loads it
from fixed init before launcher dispatch, and keeps the obsolete `mali_kbase`
request behind the separate post-frame mainline device bridge. The guarded Mac
v3 updater changed only mounted BIRD p1 and left the customized root and data
partitions untouched. It staged kernel
`82f1a2ed941b55f5bb3a79421962f78029fa0559379c0651a4d4c82bd46d8653`
and the physical gate confirmed a 1.586-second visible frame, a 1.750-second
correct gamepad, working menu controls and shutdown. The remaining failures
were the old root's vendor Mali/ION graphics and brightness interfaces.

Compatibility v4 bind-mounts its userspace helpers from the embedded cpio but
does not execute the graphics bridge during boot. A selection mounts the exact
ROCKNIX `SYSTEM` SquashFS from p6 read-only, constructs a private library view
in `/run`, selects SDL KMSDRM and Mesa/Panfrost, and then invokes the preserved
muOS launcher scripts. The root partition is still not rewritten. The same
batch maps muOS brightness commands to mainline backlight sysfs and substitutes
melonDS for the vendor DraStic JIT on NDS selections.

The first v4 physical pass retained the fast Bird frame and correct gamepad,
but all selected applications returned before `exec`: the modern runtime
mounted, then an optional bind over PortMaster's p6 policy failed. Compatibility
v4.1 removes that unrelated operation from normal content preparation and
installs the 409-byte mainline PortMaster policy directly on p6. It also embeds
a 6,160-byte freestanding `bird-controls` process and overrides only the
post-frame `HOTKEY` helper. The process blocks on the fixed mainline input
devices by name and leaves launcher/application input ownership independent.
`mac-update-rocknix-bird-compat-v4-1.sh` accepts only v4 or its own installed
kernel hash, verifies the full card geometry, runtime, DTB and policy, and
writes p1 plus that single p6 policy file; p5 remains untouched.

The v4.1 physical pass then proved that applications reach `exec`, but exposed
the source kernel's deterministic DRM numbering: Panfrost render-only is
`card0`, while the sun4i panel is `card1`. The runtime SDL defaulted to card0,
causing RetroArch's explicit `kmsdrm not available` failure and blank output
from MPV, PPSSPP and SDL/FRT ports. V4.2 pins SDL to display index 1 only after
a content selection and adds persistent kmsg markers to the independent global
controls service. `mac-update-rocknix-bird-compat-v4-2.sh` accepts only the
verified v4.1 or v4.2 kernel, rechecks the same complete card geometry and
artifact identities, and still writes only p1 plus the unchanged p6 policy.

The v4.2 physical pass verified standard backlight control but left the shared
graphics failure unchanged, so v4.3 changes registration order instead of
adding another launcher or selection-time workaround. Sun4i-drm stays built in
and owns display `card0`. The 46,280-byte DRM shmem helper, 62,440-byte GPU
scheduler and 152,432-byte Panfrost module are embedded with the kernel and
bind-preserved into `/run/muos` before the old initramfs is deleted. S10udev,
already dispatched after Bird's first frame, loads that fixed chain while its
input/sound replays proceed. The content bridge only waits for `renderD128` if
warm-up has not finished; it never initializes the GPU on demand.

`mac-update-rocknix-bird-compat-v4-3.sh` staged kernel
`9772446def037d134761ba9b135347bb1037ff5e90a59c11a7df12a6c0fa6672`
after verifying the full removable-card geometry, v4.2 predecessor, unchanged
DTB/runtime/policy hashes and temporary copies. It updated p1 plus the same p6
PortMaster policy and did not write p5.

The original one-shot plan required preserving an automatic normal boot target.
This card is now explicitly disposable experimental media, so a candidate may
replace BIRD p1 only after exact layout, old-hash and readback gates pass. The
20-second Linux watchdog restarts the selected candidate; it is not an
automatic alternate-kernel fallback. The earlier
`stage-one-shot-boot-state-capture.sh` first staged a read-only collector for
the exact active 32 MiB FAT boot-resource partition and 16 MiB U-Boot
environment partition. The same harmless boot captures the accepted kernel's
live kallsyms, configuration, DTB, modules, interrupts and memory map as a
targeted performance oracle. Those captures are inputs to a one-shot scheme
that keeps accepted partition 4 intact, restores/saves U-Boot's normal command
before loading a compact candidate file from FAT, and therefore returns to the
accepted kernel after a reset. An opt-in initramfs watchdog will cover the
narrower case where Linux starts but no first-frame-ready marker arrives; it
cannot execute during a pre-kernel hang.

The watchdog code in `bird-fixed-init.c` is absent unless a candidate is built
with `BIRD_BOOT_TIMEOUT_SECONDS`. It forks before the first mount attempt,
issues the Linux restart syscall when the deadline expires, and is killed and
reaped only after `bird-first-frame-ready` is observed. Production builds do
not arm it. `fat16-file.py add` is similarly constrained: it accepts only the
exact physical 32 MiB image, a root-level 8.3 name and one contiguous run that
is free in every FAT copy, then performs an exact readback before emitting the
new image. This avoids trusting the misleading 128 MiB size in the FAT BPB.

## Installed DTB experiment

The hidden card workspace contains:

- `bird-boot-backlight-25.img` — SHA-256
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

## Bird clean-root application gate

Clean-root v5.0 physically proved that Bird can remain in its embedded root:
the static menu painted and accepted H700 input before p6, Panfrost or the
immutable ROCKNIX application runtime were ready. It also localized the next
failures to the post-frame application session rather than boot or launcher
ownership.

`mac-update-bird-clean-root-v5-1.sh` advances only p1 `KERNEL`. It preserves
the accepted v5.0 kernel on p6, verifies the exact card geometry, DTB and
runtime image, stages through a temporary FAT file and rereads the installed
checksum. P5 and the game/media library remain untouched. The candidate gives
native applications writable scratch space, one fixed H700 libudev record and
controller map, direct DRM MPV output, Bird-owned system volume and a global
Select+Start exit contract. None of that work enters the first-frame path.

The v5.1 physical gate proved application entry and controls, then localized
slow RetroArch/Flycast playback to a forced Mesa `softpipe` path and silent
RetroArch/MPV playback to the untouched reset-state H616 mixer route.
`mac-update-bird-clean-root-v5-2.sh` preserves v5.1 as an additional recovery
kernel and changes only p1 `KERNEL`. V5.2 restores Mesa's native sun4i
KMSRO/Panfrost pairing, applies the fixed six-control speaker route after the
menu, retains direct hardware ALSA for native clients and removes MPV's broken
repeating trigger-speed bindings. It still starts no generic session daemon.

V5.3 proved that the native application runtime can drive Panfrost RetroArch,
Dreamcast, standalone DraStic, Ports, MP3 and global controls without changing
the approximately 2.5-second menu. Its full logs also showed that Bird's clock
helper lowered the GPU and provoked PLL warnings, DraStic's forced GLES2 output
striped, PPSSPP inherited an exFAT copy failure and transparent KMS window,
Ports lacked a complete default ALSA definition, MPV's SDL input and video
owners collided, and the controls process ignored the already-enumerated lid
switch. The guarded v5.4 updater preserves v5.3 and changes only p1 `KERNEL`;
all six corrections remain outside the first-frame dependency path.

`mac-update-bird-clean-root-v5-4.sh` accepts only the exact removable-card
geometry, v5.3/v5.4 kernel identity, shipping-identical DTB and pinned runtime.
It checksum-verifies the new 29,939,720-byte kernel, preserves v5.3 at
`MUOS/Bird/recovery/KERNEL-v5.3`, stages through a temporary FAT file and
rereads SHA-256 `a53a3483731d28d2e96e53def0fba347fa53607aa9fbda8bfb82db677126daef`.
