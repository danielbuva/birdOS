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

## Fetch

`download-reference-release.sh` resumes an existing prefix, fetches the rest
as eight independent HTTP ranges and accepts the output only when both its
published byte count and SHA-256 match.

The guarded raw candidate is generated under `/Users/dani`, outside the
Downloads folder. macOS provenance scanning was observed blocking new opens of
the otherwise verified multi-gigabyte image inside Downloads; an APFS clone at
the fixed location opened and rehashed immediately with identical bytes.
