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

The physical v4.3 result proves that topology and ordering. Sun4i registered
the DSI/HDMI display as `card0` at 0.904 seconds and retained `fb0`; Panfrost
then registered as render-only `card1` plus `renderD128` at 3.68--3.98 seconds.
Bird's usable input frame remained at 1.78 seconds or earlier, so none of that
GPU warm-up returned to the visible path. Application behavior did not change:
RetroArch still loaded its core and content, then reported `kmsdrm not
available`, selected a null GL context and rejected the video driver. This
localizes the next failure above kernel registration, in the selected
SDL/library/DRM-master handoff.

V4.4 retains the physically proven kernel topology and adds no boot service.
A 67,600-byte diagnostic executable is bind-preserved from the initramfs but
remains dormant until the first content request, after Bird has released the
framebuffer. In the exact compatibility environment it reports the loaded SDL
and libdrm paths, available SDL video backends, KMS resource counts, direct
`drmSetMaster`/authentication results, dynamic GBM/EGL loading and any process
that already has a DRM node open. Its output is written directly to the
boot-ID-specific p6 source-kernel log before the application is launched.

| Compatibility v4.4 diagnostic | Bytes | SHA-256 |
| --- | ---: | --- |
| Bird source-kernel v4.4 `Image` | 29,939,720 | `cc8fa96a90cd95cfca57cac514415755c70284b102fe102bd82ad107bdaba2f8` |
| embedded Bird v4.4 cpio | 4,286,464 | `59479b1225dfe20b2e3612f5ebc05fbaf2c9cd749b22ad488a68596b55871683` |
| fixed `/init` | 13,688 | `d1b87c0bb289d5eafb9d2f1044f3a3a42e235cd79995a9ca609861961ac4918b` |
| `bird-graphics-probe` | 67,600 | `be77ada538fa916ebec4b9503faec5d7c02f7d0276d735f1355924f64a2b6190` |

Two clean v4.4 initramfs builds reproduce both the cpio and probe exactly. The
probe needs only GLIBC 2.34; the preserved muOS RetroArch already needs GLIBC
2.38. The full source gate passes with the shipping-identical DTB and unchanged
deferred Panfrost modules.

The physical v4.4 capture closes the generic graphics-stack investigation.
The private view loaded SDL 2.32.10, libdrm, GBM and EGL successfully. Card0
reported two CRTCs, two connectors and two encoders; direct DRM-master
acquisition succeeded; no other process held a DRM node; and SDL initialized
its KMSDRM backend successfully. MPV then followed the same route, opened
card0 and created 720x480 DRM framebuffers. The preserved muOS RetroArch alone
continued to reject its SDL graphics context with `kmsdrm not available`.
Kernel ordering, permissions, card selection and DRM ownership are therefore
not the remaining RetroArch fault.

V4.5 changes only the process used for libretro sessions. The existing muOS
launch script, arguments, content paths, cores, configurations, controller
policy and return-to-launcher contract remain in place, but its `retroarch`
command is resolved to a shell function that invokes the checksum-pinned
ROCKNIX executable through ROCKNIX's matching dynamic loader and `/usr/lib`.
Using the matching loader deliberately avoids combining a newer libc with the
preserved root's loader. MPV, PPSSPP, ports and every visible boot component
remain unchanged.

| Compatibility v4.5 native RetroArch | Bytes | SHA-256 |
| --- | ---: | --- |
| Bird source-kernel v4.5 `Image` | 29,939,720 | `771c4bbb9696775fb135c6d21166106b84939873fd416956d95760f9d4596cf6` |
| embedded Bird v4.5 cpio | 4,287,488 | `d0d0d1ef7d99b752be87c337de9f5dcace4f58635713f7b889634566be7b7ae0` |
| mainline function bridge | 2,175 | `6c5628e34dcf72b7252c2915e2cdcb030467eedb26c3e75eb2df3c2d5bb3a8c1` |

Two clean v4.5 initramfs builds reproduce exactly. The full source gate again
passes with the shipping-identical RG34XX-SP DTB and unchanged deferred GPU
modules.

The physical v4.5 run reached the native ROCKNIX RetroArch 1.22.2 executable,
loaded the requested core and Stella content, and then failed with
`kmsdrm not available` / `Cannot open video driver`. MPV decoded content, but
the visible and input behavior was still not the required experience. This is
the final hybrid result: replacing only the executable while retaining muOS
wrappers, configuration, cores, paths and policy does not create a coherent
application environment.

## Bird clean-root v5.0

V5.0 removes the mixed root rather than adding another compatibility shim.
Bird remains on the initramfs as the permanent root and never mounts p5 during
a successful boot. Its static launcher and direct H700 input are the visible
critical path. After the input-ready marker, an independent post-frame script
mounts p6, warms the exact Panfrost modules, mounts the checksum-pinned ROCKNIX
SYSTEM image read-only and publishes runtime readiness. A separate fixed input
service owns global brightness, volume and suspend policy.

Content launches through a narrow four-line request. Native RetroArch, MPV,
libretro cores, configuration baseline, dynamic loader and libraries all come
from the same runtime. Bird contributes only its fixed core mapping, save paths,
input policy and return contract. No muOS wrapper, application, core,
configuration or shared library is used. ROCKNIX is therefore a native
application/runtime provider and kernel source, not the booted operating
system.

| Bird clean-root v5.0 | Bytes | SHA-256 |
| --- | ---: | --- |
| source-built Linux `Image` | 29,874,184 | `b585d2b59ffd735e16cfefe1fcafeaf4d2d56831d0d4bd937819a87440a4be64` |
| embedded clean-root cpio | 4,193,792 | `4b5a6e2c5b029b808b672d13107f0cf98801349adaf03c2b082edc6a1caedd2d` |
| fixed first init | 5,432 | embedded in cpio |
| fixed permanent PID 1 | 5,112 | embedded in cpio |
| static launcher | 623,064 | embedded in cpio |
| separate controls service | 5,240 | embedded in cpio |

Two clean cpio builds are byte-identical. The full kernel build passes the
pinned Linux 7.0.11 source/patch/config gate, contains that exact cpio, retains
the shipping-identical DTB and uses byte-identical H700 input and deferred GPU
modules. The guarded updater changes only p1 `KERNEL`; p5 is untouched and the
v4.5 kernel is copied to p6 recovery. The physical v5.0 gate painted Bird at
1.135 seconds, opened direct H700 input at 1.290, mounted p6 at 1.40, prepared
Panfrost at 1.42 and published the immutable runtime at 2.08. Menu controls,
improved brightness and shutdown passed. Native applications exposed a
post-frame session-policy failure: absent controller properties, an inherited
640x480/invalid graphics context, read-only runtime scratch space and MPV
without a direct-display/control policy.

## Bird clean-root v5.1

V5.1 retains the physically accepted v5.0 kernel, DTB, first-frame sequence and
application/runtime boundary. It changes the embedded post-frame policy only:

- bind writable `/tmp` into the read-only native runtime;
- publish the built-in H700 pad's three fixed libudev properties without
  starting udevd or replaying hardware;
- use exact single-entry RetroArch and SDL controller profiles, with
  Select+Start as Bird's global application-exit contract;
- inherit native RetroArch's automatic direct-KMS context at the exact 720x480
  panel mode instead of forcing the nonexistent `kmsdrm` context;
- run MPV through its compiled direct DRM output and fixed gamepad map;
- exclusively grab the dedicated volume-key node for direct ALSA `DAC` control,
  while shoulder buttons remain player-relative media volume; and
- preserve a separate content log and dmesg snapshot for every launch.

All of this begins after the input-ready menu. The steady idle path still has
no udevd, D-Bus, PipeWire, network, entropy or media daemon. Direct MPV DRM uses
software presentation for this correctness gate; Panfrost/video optimization
follows only after visible playback and input pass.

| Bird clean-root v5.1 | Bytes | SHA-256 |
| --- | ---: | --- |
| source-built Linux `Image` | 29,939,720 | `5f1238b5f3010f88ac142505097064264c2a6090d0e19a809a0c1a97da6bde5c` |
| embedded clean-root cpio | 4,198,912 | `d4ab202c99090c76ac86cde5490ea51b765b282ec9eb6ac5783167348b5647d0` |
| fixed first init | 5,432 | embedded in cpio |
| fixed permanent PID 1 | 5,112 | embedded in cpio |
| static launcher | 623,064 | embedded in cpio |
| separate controls service | 5,880 | embedded in cpio |

Two independent cpio builds and two independent full kernel builds are
byte-identical. The build audit re-extracted the exact input archive from the
kernel, retained the shipping-identical 49,010-byte DTB and reproduced the
same H700 and deferred Panfrost modules. The guarded v5.1 updater accepts only
v5.0 or v5.1 on this exact removable card, preserves v5.0 on p6 and changes
only p1 `KERNEL`. Its physical gate passed menu input, brightness, application
entry and Bird's exit contract. Atari, FBNeo and Flycast all ran in slow motion
and without audio; every RetroArch log named Mesa `softpipe`, while ALSA
accepted the requested direct format and failed only when writing. MPV decoded
and accepted its controls but did not advance normally until a seek/play event,
and SDL trigger events repeated a speed change without a matching release.
Those results localize the defects to post-frame graphics, audio and media
policy rather than Bird's permanent-root architecture.

## Bird clean-root v5.2

V5.2 corrects the measured v5.1 session defects without changing the
input-ready path:

- delete the forced `panfrost` loader override so Mesa's native sun4i KMSRO
  driver pairs display `card0` with Panfrost `renderD128`;
- inherit the native H700 threaded-video policy and core-options file;
- initialize the one fixed H616 DAC, stereo Line Out and RG34XX-SP speaker
  route after the menu, without UCM, PipeWire or an audio daemon;
- retain the already-proven direct `hw:0,0` endpoint and move user volume from
  the fixed DAC level to `Line Out`;
- remove MPV's unreliable SDL trigger-speed bindings;
- replace the fixed 150 ms content-exit sleep with bounded 10 ms readiness
  polling, allowing up to one second before a forced kill; and
- create the fixed core scratch, screenshot and native core-options paths and
  disable the unused GameMode client attempt.

| Bird clean-root v5.2 | Bytes | SHA-256 |
| --- | ---: | --- |
| source-built Linux `Image` | 29,939,720 | `bb7e320b084a5b643f9c8015ff8986f7fd81a86a7aa76b0789ec3fc9f517646a` |
| embedded clean-root cpio | 4,200,960 | `936d3f9408b822e042670dd3538ccac3a80ca593022fe3d0fe9af39f3fc681c7` |
| fixed first init | 5,432 | embedded in cpio |
| fixed permanent PID 1 | 5,112 | embedded in cpio |
| static launcher | 623,064 | embedded in cpio |
| separate controls service | 5,880 | embedded in cpio |

Three clean cpio builds are byte-identical. Two independent complete kernel
builds are byte-identical, embed that exact archive at the same offset, retain
the shipping-identical 49,010-byte DTB and reproduce the same H700 input and
deferred Panfrost modules. The guarded v5.2 updater accepts only v5.1 or v5.2
on this exact removable card, verifies the retained v5.0 recovery kernel,
preserves v5.1 on p6 and changes only p1 `KERNEL`. The physical gate passed
the built-in speaker, Panfrost, direct audio, MP3 and global-control boundary.
Frame pacing and application selection did not: the evidence and v5.3
corrections are recorded below. Headphone amplifier switching remains outside
this proof.

## Bird clean-root v5.3

The v5.2 physical pass proved the fast permanent-root, fixed input, Panfrost,
direct ALSA and global-control architecture at roughly 2.5 seconds by
stopwatch. Its logs separated the remaining regressions from boot: Dreamcast
used modern Flycast rather than ROCKNIX's H700 low-end build, DS substituted
melonDS with FreeBIOS for DraStic, libretro PPSSPP segfaulted, content kind 3
was explicitly unimplemented, and MPV's software DRM output dropped 81 frames
in the first eight seconds of the measured movie.

V5.3 changes only independent post-menu application policy:

- map Dreamcast/Naomi to the H700-tuned Flycast 2021 core and clear the
  incompatible modern-Flycast per-core options once;
- run the runtime's standalone DraStic and PPSSPP builds with fixed direct
  KMSDRM, GLES2, ALSA and H700 controller policy;
- launch installed Ports through a small Bird device profile, translate their
  legacy `/mnt/mmc` path at dispatch and prevent later generic probing from
  replacing that profile;
- give each content launch a new session/process group so one Select+Start
  contract terminates the application and every helper it created;
- snapshot, raise and restore CPU/GPU policy only around emulation, Ports and
  video; the launcher and idle menu never request performance clocks;
- present movies through SDL KMSDRM/GLES2 because pinned MPV lacks a native EGL
  context, while retaining direct `hw:0,0` audio and system-owned volume; and
- remove a partial ALSA configuration override and replace unsupported decimal
  BusyBox sleeps with exact microsecond waits.

The movie path is a measured intermediate step, not the final media design.
Hardware decode still requires H616 Cedrus, V4L2-request-enabled FFmpeg and an
EGL-enabled MPV build; v5.3 tests whether GPU presentation alone removes the
visible scaling/frame-pacing cost.

| Bird clean-root v5.3 | Bytes | SHA-256 |
| --- | ---: | --- |
| source-built Linux `Image` | 29,939,720 | `ad60468b880fba88c1fc85eca888fbceefd05eb5d54a9a14f9fe74dd8c0847f9` |
| embedded clean-root cpio | 4,212,736 | `b6bf87cfc291fa663194445b5b768717908367126fac90d25bc6ab18a729d01c` |
| complete module archive | 937,412 | `2282447fb26b35b6ff5651959a359fde556602c746dcfe9d39db095662412288` |
| fixed first init | 5,432 | embedded in cpio |
| fixed permanent PID 1 | 5,112 | embedded in cpio |
| static launcher | 623,064 | embedded in cpio |
| separate controls service | 5,880 | embedded in cpio |

Two independent initramfs builds and two sequential complete kernel builds are
byte-identical. Both kernels re-extract the exact cpio above, retain the
shipping-identical 49,010-byte DTB, and reproduce the same H700 input and
deferred Panfrost modules. The guarded v5.3 updater accepted only the exact
removable-card geometry, v5.2/v5.3 kernel identities, runtime and DTB. It
preserved v5.2 on p6 and replaced only p1 `KERNEL`. The v5.3 physical run
passed the fast launcher, Panfrost RetroArch, Dreamcast, MP3 and global
controls, then supplied the failure evidence for v5.4 below.

## Bird clean-root v5.4

V5.4 remains entirely after the input-ready menu and makes six independent
corrections from the v5.3 hardware logs:

- make the clock boundary diagnostic-only; the native governor already reached
  1.416 GHz CPU and 648 MHz GPU, while Bird's 600 MHz cap and governor writes
  produced repeated `ccu_helper_wait_for_lock` warnings;
- select SDL desktop OpenGL for DraStic, matching `libdrastouch`'s Panfrost
  state path instead of the column-corrupt GLES2 output;
- copy only PPSSPP's writable `PSP` tree to exFAT, force an opaque fullscreen
  KMS window and invalidate the old GL cache once;
- include ALSA's complete runtime definitions and override only `default` to
  fixed `hw:0,0` for OpenAL/LÖVE/MonoGame Ports;
- return MPV to the visible direct-DRM correctness path because its gamepad
  initialized SDL before `vo=sdl` and made video reject its second owner; and
- open the kernel's existing `gpio-keys-lid` event in the separate controls
  process and suspend only on `SW_LID=1`.

The app boundary also erases the exited launcher's fixed framebuffer once, so
KMS window recreation can flash black but cannot expose stale menu pixels.
Boot, first frame, menu input, storage/runtime preparation and Panfrost warm-up
are unchanged.

| Bird clean-root v5.4 | Bytes | SHA-256 |
| --- | ---: | --- |
| source-built Linux `Image` | 29,939,720 | `a53a3483731d28d2e96e53def0fba347fa53607aa9fbda8bfb82db677126daef` |
| embedded clean-root cpio | 4,213,248 | `bac7347f742be00ec0a117c19d69d48ab15bf3b11e87279cf9e65aeb33080afc` |
| complete module archive | 937,412 | `2282447fb26b35b6ff5651959a359fde556602c746dcfe9d39db095662412288` |
| fixed first init | 5,432 | embedded in cpio |
| fixed permanent PID 1 | 5,112 | embedded in cpio |
| static launcher | 623,064 | embedded in cpio |
| lid-aware controls service | 6,472 | embedded in cpio |

Two clean initramfs builds and two complete source-kernel builds are
byte-identical. Both kernels re-extract the exact cpio above, retain the
shipping-identical 49,010-byte DTB and reproduce the same H700 input and
deferred Panfrost modules.

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

## Stock-root v6 compatibility reset

Clean-root v5.4 retained the correct fast-launch architecture but had become a
manual reconstruction of ROCKNIX's application environment. Restoring one
missing library, device property, audio route or wrapper at a time did not
prove that the resulting session matched what the applications were built and
tested against. V6 changes the order of work: establish one coherent provider,
then optimize it by measured subtraction.

The active card uses these release artifacts without modification:

| V6 provider artifact | SHA-256 |
| --- | --- |
| ROCKNIX `KERNEL` | `af4e75cb30b097ee5764764eb056d686bc00c6bd03fefece26b0ebbaa7fbb673` |
| RG34XX-SP `dtb.img` | `f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31` |
| immutable `SYSTEM` | `6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac` |
| configured ext4 `STORAGE` | `12affdad7bc2042cb590fea60fc015a7ee8d4374ebcc3b1c11098a64b9ffa3be` |

The small BIRD partition cannot contain the 1.2 GB SYSTEM. The unmodified
release initramfs instead sources `post-flash.sh`, which mounts p6 and bind
publishes that exact file at its normal `/flash/SYSTEM` target.
`mount-storage.sh` loop-mounts the captured configured ext4 image from p6 and
binds the existing ROM and BIOS trees into ROCKNIX's `/storage/roms`
namespace. P5 is not read or written.

The cached catalogue deliberately retains its canonical `/mnt/mmc` paths so
favorites, recents and launch requests stay provider-independent. For this
layout, Bird maps that prefix to `/storage/bird-data` only when checking a
selected file; the separate content runner applies the same mapping at the
ROCKNIX handoff.

The first v6 hardware boot exposed this boundary precisely: the root probe
reported ready, but selected entries were still probed at `/mnt/mmc`, so Bird
displayed `WAITING FOR ... STORAGE` and never emitted a request. V6.1 adds only
the live-prefix resolver above; PortMaster had already proved the supervisor,
Sway handoff and unmodified application stack could start.

The v6.1 physical gate then restored the coherent result the reset was meant
to establish. Tested libretro systems, Dreamcast, DraStic, PPSSPP, MP3, MPV,
brightness and lid close behaved at or near the exact release baseline. The
remaining common failure was not another kernel or ABI gap: the imported muOS
library split 63 launch scripts under `ROMS/Ports` from 58 game-data directories
under `/ports`. ROCKNIX's `control.txt` instead resolves both through one
`/roms/ports` tree, and its release runner assumes the bundled PortMaster
provider has already been initialized there.

Stock-root v6.2 makes that contract native. The guarded Mac update validates
all names, moves the 58 directories within the same ExFAT volume and seeds the
checksummed `2026.05.04-1202` release provider. This changes directory metadata
rather than copying the 16 GiB payload. `prepare-ports.sh` is a separate
selection-time process—not launcher or boot work—and reproduces only the setup
half of release `start_portmaster.sh`. It synchronizes release control files
and bind-attaches only the already downloaded squashfs `libs` after a Port is
selected. Exact `pugwash`/`harbourmaster` remains free to create its matching
`exlibs` from the bundled `pylibs.zip`. Normal launchers execute at their native
basename so exact per-game controller, GPU, display and governor policy works
again. Only the
pre-existing custom Stardew launcher receives its two narrowly scoped old-root
translations until that game is reinstalled from the native provider.

The dispatcher now appends the final 256 KiB of ROCKNIX's `/var/log/exec.log`
to Bird's persistent latest-session log. This closes a diagnostic blind spot:
the release runner deliberately redirects application output there, so earlier
Port crashes looked silent after returning to Bird.

The v6.2 physical gate then showed that layout alone was insufficient: all
Ports, including Stardew, returned immediately. ROCKNIX autostart synchronously
started its generic automounter after Bird's initramfs bind. That service
unmounted `/storage/roms`, skipped p6 because it was already mounted at
`/storage/bird-data`, and published its internal writable-image game tree.
Direct Bird content paths continued to work, which isolated the regression to
Port scripts' native `/roms/ports` contract.

Stock-root v6.3 replaces that generic scanner at its existing ordered systemd
boundary with `fixed-storage.sh`. It performs no device discovery: it verifies
that `/storage/roms` is the already-mounted p6 `ROMS` directory, repairs the
bind if necessary, explicitly retains executable mount policy and republishes
the fixed BIOS tree. The process remains separate from Bird and finishes before
the UI service, so the launcher stays storage-policy-free. Port setup also
checks this identity before honoring its per-boot ready marker. ExFAT is mounted
with explicit `exec,fmask=0022,dmask=0022`, matching the proven muOS execution
contract for scripts and native Port payloads.

V6.3 also preserves every content session in a unique bounded log and installs
a four-line MPV input overlay only when media is selected. Physical volume and
L1/R1 player-volume bindings are ignored by MPV, while the exact release
`start_mplayer.sh`, hardware decode policy and remaining movie controls stay
unchanged. The confirmed power/lid fake-suspend cases are now closed.

The automatic fallback remains deliberately a first-frame liveness guard, not
a post-menu application gate. Bird reads its catalogue directly from p6 and can
still paint if the fixed compatibility namespace fails; in that case the
storage service records its failure and Port preparation refuses the wrong
tree. This preserves the menu-first architecture while making the physical
Ports test, rather than a hidden reboot, the acceptance signal.

The v6.3 physical gate passed the complete requested behavior sweep. Its new
evidence also identified the next optimization boundary precisely: fixed p6
storage completed at 8.48 seconds, while autostart did not launch Bird until
17.36 seconds; the frame appeared at 17.38 and the H700 input gate passed at
17.50. The remaining delay was therefore the generic service graph preceding
the UI, not catalogue parsing or launcher work.

Stock-root v6.4 moves the already-proven Bird service before that graph. Both
Bird and the fixed storage assertion use `DefaultDependencies=no`; the default
target requests Bird immediately, and its existing framebuffer/input waits are
the readiness checks. PipeWire and WirePlumber continue warming concurrently,
while the content dispatcher explicitly starts and joins them if the user
selects something first. The first-frame watchdog is extended to the launcher's
20-second input deadline so an early visible frame cannot be mistaken for a
failed boot while udev is still exposing the H700 gamepad.

The exact ROCKNIX autostart script remains intact for this pass. Its service now
receives a private mount namespace with `/dev/null` over `/dev/console`; common
setup and H700 quirks run in parallel without late `tocon` or `clear` writes
repainting Bird. Persisted backlight state is applied directly before the first
frame so the later exact display step repeats the same value invisibly.

Networking becomes explicit maintenance work. Condition-gated exact
NetworkManager and iwd units start only around PortMaster and stop on return.
The fixed profile also masks always-irrelevant SSH, RPC, WSD, Entware,
touchscreen, Sway-touch, Sixaxis, statistics and HDMI-monitor jobs before PID 1
loads its units. RPC's socket is masked with its service so socket activation
cannot resurrect it. A single post-frame service/process snapshot waits for
autostart completion and records the next measured subtraction boundary.

V6.4 passed the full physical gate at roughly seven stopwatch seconds. Its
captured boots put visible Bird frames at 5.60--9.82 seconds and correct H700
input at 7.93--9.94 seconds of kernel uptime. Against v6.3's 17.38/17.50-second
frame/input baseline, early systemd ordering removed about nine seconds without
breaking any tested application or device behavior. Fixed storage and the
stock initramfs-to-SYSTEM transition are now the first-frame boundary.

Stock-root v6.5 restores Bird before `switch_root` without returning to the
incomplete clean-root application stack. A reproducible 217,666-byte external
cpio is unpacked over the byte-identical release kernel's pinned built-in
initramfs. It overrides only `/init`, adding one start call after the stock
console clear, suppressing the later stock splash repaint, and adding one
handoff call before the special mounts move into sysroot.
The first physical v6.5 boot proved that architecture at kernel uptime 1.377
seconds, corresponding to about 3.2 seconds from the green LED by stopwatch.
It also found a precise input defect: the 37,248-byte module rebuilt from the
pinned source had matching `vermagic` but not the exact release kernel's symbol
versions, so `insmod` returned `Invalid argument`. Bird remained visible while
input waited for the later SYSTEM copy, producing the measured 3.2-second
visible/10.4-second interactive split.

Stock-root v6.6 replaces only that module with the byte-exact 36,584-byte
`rocknix-singleadc-joypad.ko` carried by the checksummed release SYSTEM
(`a8ac6cac...b79b`). The build now checks both its full hash and 7.0.11 ABI.
The reproducible overlay is 218,397 bytes and keeps the same unchanged release
KERNEL, DTB, SYSTEM and writable STORAGE. Early failure now captures the last
kernel messages instead of discarding the reason.

V6.6's physical gate then proved immediate navigation at the early frame but
exposed the remaining process boundary directly: initramfs Bird was interactive
at kernel uptime 1.497 seconds, stopped near 2.9 seconds and system-root Bird
did not return until 5.7--8.9 seconds. A selection at 2.900 seconds was recorded
correctly but its request was consumed while the ROCKNIX application contract
was still being generated.

Stock-root v6.7 attempted to replace that frozen-frame interval with a final-root bridge.
Its reproducible external overlay is 218,810 bytes.
Before the four special mounts move, the initramfs hook copies the already
verified static launcher into `/run` and preserves its state. Immediately after
`/run` moves, it was intended to execute that binary through `chroot /sysroot`.
The physical log contained only an empty `uptime=` field: the hook tried to read
old-root `/proc/uptime` after `/proc` had moved and did not establish the bridge.
The later systemd Bird therefore still replaced the early input owner.

Stock-root v6.8 removes that fallible pre-dispatch read, writes the child PID
immediately and checks that the process survived. The systemd supervisor no
longer retires a valid bridge. It adopts it and sleeps in an 896-byte static
`pidfd_open`/`ppoll` helper until the user launches content, requests shutdown
or the launcher actually exits. Its physical trace proved the detached
`setsid`/`chroot` process exited with status 2 before the launcher emitted its
entry marker, so systemd still had to create the later input owner.

Stock-root v6.9 deletes that fragile replacement path. The first initramfs Bird
keeps open descriptors for framebuffer, input, power, runtime and storage.
Those descriptors remain attached to the same mounts when `/dev`, `/sys`,
`/run` and the prepared root move. File operations after the move use
`openat`, `renameat` and `unlinkat` relative to those anchors. Systemd adopts
the original PID with the same blocking pidfd waiter. If ROCKNIX actually
re-registers the gamepad, Bird detects `POLLERR`/`POLLHUP` and reopens it
through the retained `/dev/input` descriptor instead of starting another UI.

The exact final common-autostart action now also publishes a timestamped
`/run/bird/application-contract-ready` marker after Sway configuration exists.
An initramfs game/media/PortMaster request remains on disk, and its handoff
action remains armed, until the separate runner joins that milestone. A killed
or restarted supervisor therefore cannot lose the request; the menu stays
independent while an early selection queues for the first reliable launch
point.

The early launcher applies the fixed five-percent backlight value, paints from
the compiled catalogue and opens the H700 input module while the unchanged
ROCKNIX init continues. Its navigation state and any content/PortMaster/
shutdown action are written to `/run`. Immediately before mount movement, the
stock init terminates only that early process; the framebuffer retains its last
image and `/run` moves into the real root. The normal systemd supervisor then
loads the same state or consumes the action. This keeps all v6.3/v6.4 content,
audio, power and service compatibility while attacking the measured pre-root
wait.

When Bird emits a four-line content request, its separate supervisor starts the
unchanged `sway.service`, calls the release's `runemu.sh` with the release
platform/emulator/core identity, waits for the application, stops Sway and
redraws Bird. PortMaster and MPV continue to use their release wrappers.

`build-stock-root-compat.sh` builds the two static Bird binaries and external
overlay, then copies the checksummed release files. Two independent v6.5 builds
reproduce all 40 files byte-for-byte; offline extraction also verifies the
overlay merges cleanly over the complete 7,474,688-byte official archive.
Two independent v6.6 and v6.7 builds likewise reproduce all card payloads
byte-for-byte. Two independent v6.8 builds reproduce every card payload too,
including its 896-byte static pidfd waiter and 219,371-byte external overlay.
V6.9 retains that waiter while removing the failed detached bridge.
Two independent v6.9 builds reproduce every card payload byte-for-byte; its
external overlay is 220,467 bytes.
`mac-update-rocknix-stock-root-v6.sh`
validates the exact removable-card geometry and every provider hash, stages the
loop image and boot hooks, and preserves v5.4 as `KERNEL.fallback`. A persistent
attempt counter returns extlinux to that fallback before a third failed v6
boot; the guarded ROCKNIX target also requests a forced reboot if its startup
job has not completed in 45 seconds. A successful Bird first frame resets the
counter.

After the seed image is installed, updates validate its fixed size and ext4
superblock rather than recopying it. This preserves the writable ROCKNIX and
PortMaster state and reduces subsequent Bird-only deployments to the small
boot/UI payload.

Charging remains a kernel/PMIC function rather than a launcher or daemon
responsibility. The exact H700 DTB binds the AXP717 battery and USB supplies,
sets `constant-charge-current-max-microamp` to 1,024,000 and declares a
1,500,000-uA USB input maximum. The battery driver programs the former. The
USB driver uses the latter only to clamp future writes, and the unplugged
hardware snapshot reported the PMIC's 2,000,000-uA boot default; reconcile that
before changing charge policy. Bird reads
`/sys/class/power_supply/battery/status` and `capacity`, then listens to kernel
power-supply uevents. The upper right now shows the live percentage without a
periodic wake-up and colors it orange while charging. In the exact kernel
source, capacity is the raw seven-bit AXP717 fuel-gauge register, while the
driver explicitly says the current channel has an unknown offset around
450 mA. The observed 100 percent and 492 mA therefore require physical
calibration. The diagnostic snapshot now records every battery/USB property,
every LED class brightness/trigger and relevant AXP717 messages rather than
inferring charge state from one LED color.

V6.3 intentionally accepted the slower full compatibility graph and passed its
broad physical gate. V6.4 passed the first speed/subtraction gate. V6.9 now
tests initramfs pixels, immediate input, persistent process ownership and the same
menu, content, media, Ports, PortMaster, global controls, suspend and shutdown
closure before any release-kernel option is removed.

The H700 release does not currently enter real kernel suspend. Its platform
quirk explicitly disables that path and `input_sense` invokes a userspace fake
suspend instead. Under the release policy, a power press while the lid remains
closed is intentionally ignored; opening the lid is the resume event. The
physical gate therefore distinguishes that expected case from power-button
suspend/resume with the lid open and lid-open wake. All three cases passed on
v6.2. V6.3 removes the release's duplicate MPV volume ownership without
replacing its player; measured H700 video-frame tuning remains after the
provider compatibility gate.
