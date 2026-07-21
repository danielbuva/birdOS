# Source-kernel challenger: exact ROCKNIX chain

The replacement-kernel path begins with the complete boot chain known to run
the RG34XX-SP, not with another hybrid Android handoff.  This directory pins
the stable ROCKNIX `20260701` DDR4 release and the exact public sources that
produced it.

## Fixed device choice

The stock-kernel oracle reports the DRAM regulator at 1,100,000 microvolts.
ROCKNIX's own updater maps that value to its DDR4 bootloader.  This device
therefore uses:

- release: `ROCKNIX-H700.aarch64-20260701-DDR4.img.gz`;
- distribution tag/commit: `20260701` /
  `3e4ee5852e6ca5ea73a38369d2639fad2262648b`;
- Linux: `7.0.11`;
- U-Boot: `v2026.01` with
  `anbernic_rg35xx_h700_lpddr4_defconfig`;
- TF-A: `v2.12.0`, platform `sun50i_h616`;
- device tree: `sun50i-h700-anbernic-rg34xx-sp.dtb`, not the v2-panel
  alternative.

The verified release artifact has these identities:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| compressed official image | 1,221,786,248 | `5b26c704ddab59e61eb7ead115879ad5370c20973be7118b823e32726bed24dc` |
| uncompressed official image | 2,198,863,872 | `fce3fe81be706be795311b361db7b98eb1316befc5d543a1ad6ca184aedcc3d6` |
| guarded RG34XX-SP reference image | 2,432,696,320 | `4d5c16452c7e45970f60bb4897c45a4e10f0e4fb10957927fb02405810b45dc7` |
| release `KERNEL` | 30,926,856 | `af4e75cb30b097ee5764764eb056d686bc00c6bd03fefece26b0ebbaa7fbb673` |
| release `SYSTEM` | 1,206,476,800 | `6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac` |
| RG34XX-SP DTB | 49,010 | `f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31` |

The generic release image intentionally has no root `dtb.img`. Its documented
device-provisioning step was applied by copying the exact RG34XX-SP DTB to
`/dtb.img`. The shipping 32 MiB storage partition also contains
`.please_resize_me`; allowing that first-boot service to consume the rest of
this 512 GB card would overwrite the card-resident recovery checkpoint. The
guarded reference therefore fixes storage at 256 MiB and removes only that
auto-grow marker. U-Boot, TF-A, `KERNEL`, `SYSTEM`, extlinux and device-tree
payloads remain byte-identical to the release. This preserves the exact boot
and hardware chain while bounding all reference writes below 2,432,696,320
bytes, far before the saved partition-6 recovery data.

## Why the card layout must change for the proof

The working chain is structurally different from muOS:

| Layer | Current muOS card | ROCKNIX reference |
| --- | --- | --- |
| table | GPT | MBR |
| SPL/U-Boot | Allwinner boot0 + TOC1/Android path | mainline SPL/U-Boot at 8 KiB |
| Linux payload | Android boot v2 in p4 | raw `KERNEL` from FAT32 |
| DT handoff | Android image plus vendor mutation | extlinux `/dtb.img` |
| first partition | begins at 36 MiB | 2 GiB FAT32 begins at 16 MiB |

The two failed candidates combined ROCKNIX-derived Linux with the vendor
Android handoff and remained on the inherited U-Boot frame.  They did not test
the boot chain ROCKNIX actually ships.  The first proof therefore writes the
reference layout exactly and restores the customized card afterward.

Before any write, `mac-capture-source-kernel-checkpoint.sh` records the exact
first 156 MiB locally and the complete customized 8 GiB rootfs on partition 6.
`mac-restore-source-kernel-checkpoint.sh` first restores the GPT/boot prefix,
which makes partition 6 visible again, and then restores the rootfs from that
partition without overlapping its source data.

## Acceptance sequence

1. Boot the guarded RG34XX-SP-provisioned DDR4 image. This proves the exact
   public SPL, TF-A, U-Boot, Linux and DT chain on this physical unit. It is a
   compatibility proof, not a speed candidate.
2. Rebuild the same U-Boot, TF-A, Linux, patch set and broad release config from
   the pinned sources. It must reproduce the hardware behavior before any
   trimming.
3. Replace the ROCKNIX initramfs/system handoff with Bird's static first init,
   launcher and fixed root contract. Preserve an early watchdog and an
   externally verified recovery image.
4. Compare physical power-to-input and internal first-input-ready timestamps
   against the accepted vendor-kernel Bird image.
5. Remove options in measured, independent batches. Hardware, launcher,
   games, media, audio, controls, suspend/lid, power and shutdown must pass
   after every batch.

The source kernel is a challenger, not an automatic upgrade. It is promoted
only if the final fixed-device build beats the accepted vendor-kernel Bird
baseline on the same card and experience. A merely functional or equal result
does not replace stock.

## Physical reference result

The guarded reference booted this DDR4 RG34XX-SP successfully. The display and
controls worked; brightness and volume changed normally; system applications,
including the media player, opened. No audio file was available for an actual
playback test. The one bundled Pico-8 title crashed on launch, which is retained
as an application/content compatibility result rather than evidence against
the kernel handoff.

One stopwatch observation was approximately 24 seconds to the stock ROCKNIX
interface. That is a measurement of its complete generic initramfs, systemd
and distribution frontend, not a source-kernel result for Bird. It is not
compared with Bird's roughly 3.5-second accepted path.

After the physical boot, all immutable FAT payloads still matched the pinned
release identities exactly:

- `KERNEL`: `af4e75cb30b097ee5764764eb056d686bc00c6bd03fefece26b0ebbaa7fbb673`;
- `SYSTEM`: `6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac`;
- `dtb.img`: `f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31`.

This closes the key uncertainty left by the two failed hybrid attempts: the
public DDR4 SPL/U-Boot/TF-A/Linux/DT chain itself is compatible with this
physical unit. The next candidate keeps that proven lower chain and replaces
the generic ROCKNIX initramfs/userspace with Bird before any kernel option is
trimmed.

## Exact source gate result

The stable distribution source is cloned at commit
`3e4ee5852e6ca5ea73a38369d2639fad2262648b`. Its Linux checkout is pinned to
stable commit `bb532bfaf7919c7c98caab81864e9ce2646e11e3` (`7.0.11`). The
rebuild applies the exact executed release order: five mainline patches, two
Linux-7.0 patches and 23 H700 patches. It also copies the release H700 device
trees and the exact panel, RTL8821CS and RTW8821C firmware payloads.

`build-source-reference.sh` extracts the shipping configuration from the
release `KERNEL`, permits only compiler-capability and initramfs-source drift,
and fails on every other option difference. The available container uses GCC
14.2 rather than ROCKNIX's GCC 15.2, so this gate is source/configuration and
hardware-closure reproduction, not a claim that the complete Linux `Image` is
byte-identical to the release. The most important board artifact is exact:
the rebuilt 49,010-byte RG34XX-SP DTB has the shipping SHA-256
`f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31`.

The broad source baseline with no embedded initramfs is 28,239,880 bytes. No
driver or kernel option has been removed yet.

The build identity is fixed as `bird@rg34xxsp`, build number 1 and
`2026-07-01 04:53:00 UTC`. This removes Kbuild's host container and wall-clock
inputs. Two clean Bird-enabled builds now produce byte-identical kernel Images
and module archives.

## Bird substitution candidate

`build-bird-initramfs.sh` reconstructs the accepted direct-handoff archive
from its pinned inputs. It contains the 9,648-byte first init, 5,128-byte root
PID 1 and the exact accepted 621,736-byte launcher. The only behavior change
for this hardware gate is a 20-second no-first-frame watchdog; a kernel panic
also reboots after five seconds. The uncompressed archive is 3,881,472 bytes
with SHA-256
`b55a0dac4518bf712010ec911464bcd4318b662ff09f86d3708e86895bb61b52`.

Building the untrimmed kernel with that archive produces:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Bird source-kernel `Image` | 29,943,816 | `f93cdd0008f9dae05be9192d9360fd097213cb377163d3d19cd58624c4bd5c31` |
| embedded Bird cpio | 3,881,472 | `b55a0dac4518bf712010ec911464bcd4318b662ff09f86d3708e86895bb61b52` |
| RG34XX-SP DTB | 49,010 | `f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31` |

The builder scans the resulting kernel and proves that the embedded archive
decompresses byte-for-byte to the input cpio. It also builds the complete
module set even though this first gate deliberately retains shipping breadth.

## Card-safe hardware gate

`build-bird-prefix.sh` packages only the bytes before the existing p5 root.
It preserves the physically proven ROCKNIX SPL, TF-A and U-Boot at 8 KiB,
creates a deterministic 128 MiB FAT32 boot partition, and describes the
existing p5 root and p6 data partitions through an MBR extended chain. The FAT
contains only `KERNEL`, `dtb.img` and `extlinux/extlinux.conf`; it is populated
without mounting, so macOS metadata cannot enter the image. Two independent
builds are byte-identical.

| Boundary | Start | Size |
| --- | ---: | ---: |
| boot FAT (p1) | 16 MiB | 128 MiB |
| existing root (p5) | 156 MiB | 8 GiB |
| existing data (p6) | 8,348 MiB | 503,320,672,768 bytes |

The candidate ends exactly at byte 163,577,856, the first byte of p5. Its
SHA-256 is
`b88dbb35e1e33c737587fed85a2bad81f116aa91ae726c6fe12060e2abe8dbba`.
Neither the customized root nor the media/game library is part of the write.
The local accepted-prefix recovery oracle has SHA-256
`0bcacc83bf7345306ef7615be1012b5c7dd0a92630cf764f34b049f88e9b9f78`.

The install and restore commands are intentionally separate and require an
explicit action token:

```sh
firmware/mac-install-rocknix-bird-prefix.sh \
  /Volumes/dani-sp --install-bird-prefix

firmware/mac-restore-bird-prefix.sh \
  /dev/diskN --restore-bird-prefix
```

Both reject internal/non-removable disks and unexpected capacity, verify the
fixed p5/p6 offsets, write only 156 MiB, and reread the raw prefix before
reporting success. The installer also refuses unless the card's current raw
prefix still matches the local accepted recovery oracle.

This image remains an untested hardware candidate. Its first physical gate is:
interactive Bird frame and controls, brightness/volume, game launch/return,
MP3, full movie controls, favorites persistence, shutdown and repeated cold
boots. Only after those pass do kernel trimming and timing comparisons begin.

## Fetch

`download-reference-release.sh` resumes an existing prefix, fetches the rest
as eight independent HTTP ranges and accepts the output only when both its
published byte count and SHA-256 match.

The guarded raw candidate is generated under `/Users/dani`, outside the
Downloads folder. macOS provenance scanning was observed blocking new opens of
the otherwise verified multi-gigabyte image inside Downloads; an APFS clone at
the fixed location opened and rehashed immediately with identical bytes.
