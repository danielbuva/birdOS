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

## First Bird substitution candidate

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

## First Bird physical result and compatibility v2

The first candidate booted the exact public chain and reached the following
observable boundaries on the physical RG34XX-SP:

| Boundary | Kernel boot time |
| --- | ---: |
| fixed init begins | 1.277 s |
| root mounted | 1.399 s |
| launcher supervisor dispatched | 1.523 s |
| Bird first frame ready | 1.547 s |
| permanent-root event loop | 3.815 s |

The menu painted, but the later framebuffer console overwrote it. Suspend and
wake worked, while input reached the console as escape sequences; the launcher
had opened its vendor-era fixed `/dev/input/event1` rather than the mainline
`H700 Gamepad`. The old root also printed its missing `FBCON_DISABLE` helper and
failed a request for vendor-only `mali_kbase`. Mainline Panfrost is built in and
correctly exposes DRM instead of `/dev/mali0`.

Compatibility v2 changes only these localized boundaries:

- extlinux retains the serial console but maps fbcon away from the only
  framebuffer, so no virtual terminal can reclaim Bird's panel;
- Bird scans the bounded event0--event7 set by device name, accepts either the
  vendor `muOS-Keys` or mainline `H700 Gamepad`, and uses the corresponding
  fixed button map;
- fixed init bind-mounts a separate post-frame mainline udev/device bridge and
  a built-in-Panfrost module no-op over the 4.9-oriented root scripts;
- the bridge persists dmesg, input names/capabilities, ALSA, framebuffer, DRM,
  backlight, nodes and mounts after the data partition becomes available.

Two clean v2 builds are byte-identical:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Bird source-kernel v2 `Image` | 29,943,816 | `0fa4d5d2d30423302bb83be86761465799b21f0fda396544e09c3e700789f597` |
| embedded Bird v2 cpio | 3,886,080 | `75a24651e70f3e2a24df32e6d99bca24aedcf08b6ebf2b4c4bfc862c1bb33e88` |
| v2 launcher | 622,720 | `ab82e90a822c2baa4402829be3dba8cb9db71761b970e7dbab689bf4d7f0c85e` |
| RG34XX-SP DTB | 49,010 | `f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31` |

`firmware/mac-update-rocknix-bird-compat-v2.sh` accepts only the verified
p1/p5/p6 layout and old/new candidate hashes. It updates only the mounted p1
kernel and extlinux file, leaving the customized p5 root and p6 library
untouched. The independently reproduced complete v2 prefix has SHA-256
`b9828838e6197efa9108365493275a4ebc246c2e24725b7c852d650d42bbfb38`.

The v2 physical gate was negative but localized. It never produced a
data-partition capture, and the 20-second first-frame watchdog restarted what
looked like a fallback. Extlinux contains only one Bird label, so the second
failure was another v2 attempt. The exact DTB requests
`rocknix-singleadc-joypad`, but that driver is not in Linux 7.0.11 or the 30
distribution patches. ROCKNIX builds it from the separate
`rocknix-joypad` repository at commit
`7647fdb0fc89cd69b284903bf7707e861df5dc7e`. V1 had accidentally opened the
volume-key event; v2 correctly rejected it and therefore waited without ever
drawing or publishing readiness.

Compatibility v3 treats that repository as a required source input. Its exact
37,248-byte module has SHA-256
`fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05`,
vermagic `7.0.11 SMP preempt mod_unload modversions aarch64`, and no module
dependencies. Fixed init loads it before launcher dispatch. The launcher now
paints immediately after framebuffer mapping, then opens `H700 Gamepad`; it
still publishes readiness and cancels the watchdog only after input is usable.

| Compatibility v3 artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Bird source-kernel `Image` | 29,943,816 | `82f1a2ed941b55f5bb3a79421962f78029fa0559379c0651a4d4c82bd46d8653` |
| embedded Bird cpio | 3,924,992 | `a2f247e9723a2bd6db440485fcb5af33a85569a4bef090367cc3491401553ebf` |
| v3 launcher | 623,064 | `840ab4cfd967f18687e624a3dd916ea6cb852a23db84f554d81e1b7c2bcecf2c` |
| H700 joypad module | 37,248 | `fd2ceb95f0b3bdc1d68e7182a8ac5239b5286cc277a04980e53f65e0f73d3a05` |
| complete p1 prefix | 163,577,856 | `6f5f6cec067c9e03c088d629c9a31f9f382d6302e1095fbacd66fde1476761cb` |

Two complete v3 kernel builds and two complete prefix builds reproduce these
bytes exactly. `firmware/mac-update-rocknix-bird-compat-v3.sh` accepted only
the card's exact removable p1/p5/p6 geometry and v2/v3 checksums, then staged
v3 by updating p1 alone. P5 root and p6 data were not written.

## Compatibility v4: deferred userspace ABI

The v3 hardware result closes the early-input question. Bird drew at 1.586
seconds, opened the real `H700 Gamepad` at 1.750 seconds, and retained menu
controls and shutdown. Post-frame udev produced ALSA, `/dev/dri/card0`,
`renderD128`, Panfrost and the standard backlight class. The failures began
only when preserved applications loaded muOS's vendor `libmali`/SDL ABI:
Mali-fbdev required `/dev/ion`, MPV's SDL initialization failed, and DraStic
eventually trapped in its vendor JIT.

V4 therefore does not add hardware setup to the launcher. The already separate
post-frame udev process remains separate. On a content request only,
`S03danilauncher` mounts the checksum-pinned ROCKNIX `SYSTEM` SquashFS from p6
read-only and builds a private `/run/bird-mainline-lib` view containing modern
SDL2 KMSDRM, GLVND/Mesa/Panfrost and only the protocol sonames required by that
Mesa build. A dependency-free 1,824-byte `libmali.so.0` stub satisfies the old
binaries' redundant DT_NEEDED entry; EGL/GLES symbols come from Mesa. The
vendor `libmustage` preload and GL4ES path are suppressed only in that selected
content process. V4 initially tried to replace PortMaster's later GL4ES policy
with a transient bind mount.

Brightness keeps muOS's existing `R`, `U`, `D` and numeric command contract but
maps it to `/sys/class/backlight/backlight`. NDS uses the runtime's ABI-stable
melonDS libretro core through the existing RetroArch policy because the vendor
DraStic binary's JIT is not a viable source-kernel compatibility layer.

| Compatibility v4 input | Bytes | SHA-256 |
| --- | ---: | --- |
| Bird source-kernel v4 `Image` | 29,943,816 | `1645639aec0ac16f1b2ef901f1bb922ab89e4ae54352580076bc42cd73fa4c8f` |
| embedded Bird cpio | 3,944,960 | `4fc0f948f27655f3cf0868ac1a78701ed086a83e90057647c9dc07230b97d848` |
| fixed `/init` | 13,144 | `5057ed3a9364a6c9e66c6a260392d538765add4672b3940dadcba02a35bd338f` |
| v4 launcher | 623,064 | `840ab4cfd967f18687e624a3dd916ea6cb852a23db84f554d81e1b7c2bcecf2c` |
| Mali ABI stub | 1,824 | `fa728d1079a34e9b1d0a96328b7fbc6b3383c903115e1f6bd61c11bc48f2d117` |
| pinned ROCKNIX `SYSTEM` | 1,206,476,800 | `6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac` |

Two independent initramfs builds reproduce the cpio exactly. The full
SquashFS is intentionally a first compatibility proof, not Bird's final
runtime: once the physical matrix passes, reduce it to the exact transitive
library/core closure and then measure size, launch latency and memory again.

The v4 physical pass reached Bird quickly and remained stable: the framebuffer
was visible at 1.400 seconds, `H700 Gamepad` was usable at 1.553 and storage was
ready at 2.010. Every content request mounted the modern SquashFS successfully,
but the optional PortMaster bind then failed with `ENOENT` and
`BIRD_MAINLINE_PREPARE` returned before application `exec`. Consequently this
pass did not yet retest MPV, RetroArch, PPSSPP or the graphics ABI.

V4.1 removes PortMaster policy from the shared preparation function and from
the embedded cpio. Its guarded updater installs the fixed policy directly as
`MUOS/PortMaster/libgl_muOS.txt` on p6. It also replaces the vendor-era hotkey
watcher, whose fixed event paths no longer match mainline, with a separate
6,160-byte static `bird-controls` service. The service is dispatched by the
existing post-frame `HOTKEY start`, opens the three fixed devices by name,
blocks in `ppoll`, does not grab events, and handles only global volume,
Menu+volume brightness and power suspend. It is not linked into the launcher.

| Compatibility v4.1 artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Bird source-kernel v4.1 `Image` | 30,009,352 | `dd2a9dd38e33d4625ac774458d13401d90f6f35513c43e63c405eb76a746f47a` |
| embedded Bird v4.1 cpio | 3,950,592 | `c22f516796d4e6b8b7f38648c73a5ef5704f7cee984acff2bc0e132a3037bc8c` |
| fixed `/init` | 13,128 | `f194e77966a7e6eea2e39f2bb221978fe1b0ce72f3764249cdb3f3e507b013e6` |
| `bird-controls` | 6,160 | `8ce5d91c2f15784f7f4971eed723e1fd7c31491926eaf0ac3e81cabac9220f22` |
| direct PortMaster policy | 409 | `9d65f67c706d23a3b651659c11c6771da039a199b5f03d4e7a8d0d8e689a2e36` |

Two independent v4.1 initramfs builds are byte-identical. The source gate
retains the shipping-identical DTB and exact H700 module. The guarded updater
verified and installed the new p1 kernel plus p6 policy without writing p5.

The v4.1 device pass localized the remaining shared graphics failure. Mainline
registers Panfrost's render-only node as `/dev/dri/card0` and the sun4i display
engine as `/dev/dri/card1`. The runtime SDL defaulted to index zero: RetroArch
logged `kmsdrm not available`, while MPV, PPSSPP and an SDL-linked FRT port
remained alive without visible application output. V4.2 treats that numbering
as part of the fixed RG34XX-SP profile and exports
`SDL_KMSDRM_DEVICE_INDEX=1` in the selection-only compatibility environment.
The freestanding controls process also sends device-ready and action-result
markers to `/dev/kmsg`, which the existing delayed dmesg collector persists.

| Compatibility v4.2 artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Bird source-kernel v4.2 `Image` | 30,009,352 | `2ef4a12f4f56942722be4426739cab2802b0c6d0973e2abe4fc3b6f17c3217f4` |
| embedded Bird v4.2 cpio | 3,952,640 | `31deab031c0065a4d436dd05b87eccb86a4caf59fb2233b6eb8fabfd0f64626e` |
| diagnostic `bird-controls` | 7,736 | `a101360c7f26feedbcc02b3e1adc8fbaf77316d5a541b75c30e574867bfd1617` |

Two independent v4.2 initramfs builds are byte-identical. The kernel build
again retains the shipping-identical DTB
`f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31`.

The v4.2 physical pass proved the direct standard-backlight path: brightness
up/down worked and its `bird-controls` action markers were persisted. The
graphics result did not change. RetroArch still rejected KMSDRM, while MPV
decoded and advanced audio/video but produced no visible application surface.
The remaining issue is therefore corrected at DRM registration rather than by
another userspace card hint.

V4.3 leaves the sun4i display driver built in so it registers the panel as
`/dev/dri/card0`. Panfrost and the two helpers selected with it are exact
matching modules. Early init only bind-preserves them into the future root;
the existing post-first-frame S10 stage loads the two dependency-free helpers
and Panfrost while udev replays input and sound. The launcher neither contains
nor waits for this work. A content request performs only a bounded render-node
readiness check, covering a selection made unusually soon after first frame.

| Compatibility v4.3 artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Bird source-kernel v4.3 `Image` | 29,939,720 | `9772446def037d134761ba9b135347bb1037ff5e90a59c11a7df12a6c0fa6672` |
| embedded Bird v4.3 cpio | 4,217,344 | `8f200dc0531691e554be4b3960b42bb634acdf8c72c7863f0e234023b8d89089` |
| fixed `/init` | 13,592 | `29fbb6546f633b672bb4c2dbddd3e0022f814fb27868f6b7c19584224aaadb85` |
| `drm_shmem_helper.ko` | 46,280 | `ccf22e0f100a6bb09cfba0906c5dab77ff2eb5ef38b0dc37727446e08e69d8a0` |
| `gpu-sched.ko` | 62,440 | `f2b2cf8f52bbd92f7169a86c2337da1af967d9d5b608469f17de3fe79799a8c6` |
| `panfrost.ko` | 152,432 | `238a5314869aa6e8d6b691c93d15e91340bfee10faa13077e329cd69a23e1991` |

Two independent v4.3 initramfs builds reproduce byte-for-byte. The bootstrap
and final builds also reproduce all three module hashes despite embedding
different cpio inputs, proving that the preserved modules match the final
kernel ABI. The DTB remains shipping-identical.

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

The first image completed the boot/display localization gate but not the
functionality gate. Compatibility v2 must now retain Bird ownership and pass
controls, brightness/volume, game launch/return, MP3, full movie controls,
favorites persistence, suspend/wake, shutdown and repeated cold boots. Only
after those pass do kernel trimming and timing comparisons begin.

## Fetch

`download-reference-release.sh` resumes an existing prefix, fetches the rest
as eight independent HTTP ranges and accepts the output only when both its
published byte count and SHA-256 match.

The guarded raw candidate is generated under `/Users/dani`, outside the
Downloads folder. macOS provenance scanning was observed blocking new opens of
the otherwise verified multi-gigabyte image inside Downloads; an APFS clone at
the fixed location opened and rehashed immediately with identical bytes.
