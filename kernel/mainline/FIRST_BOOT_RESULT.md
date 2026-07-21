# First source-built kernel hardware result

Test date: 2026-07-21.

## Observed result

The first device boot stayed on the accepted vendor kernel long enough for the
guarded installer to complete:

- installer start: 4.200 seconds of vendor-kernel uptime
- accepted boot SHA verified: 12.010 seconds
- accepted 64 MiB backup complete: 20.060 seconds
- candidate written and raw-verified: 26.430 seconds

On the following cold boot the RG34XX-SP remained indefinitely on the U-Boot
logo. The launcher never became visible. No
`MUOS/boot-timing/mainline-compat/` directory was created.

The candidate was SHA-256
`d683c1b9c3f4ed8c67e337a2f1d4527a5f1391b28c8a40c14c5d57660313ea6d`.
The backup and restored boot partition were SHA-256
`872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f`.

## What this proves—and does not prove

The on-device readback proves that the intended 64 MiB candidate reached the
boot partition without corruption. The retained U-Boot logo and missing
collector bound the failure before the normal user-init collection point. They
do not distinguish among:

1. failure during the vendor U-Boot-to-mainline handoff;
2. an early-kernel failure before MMC/initramfs progress can be persisted;
3. initramfs or MMC device-numbering failure before `/mnt/mmc` is available;
4. a running headless system whose DRM/fbdev path never replaced the U-Boot
   framebuffer.

The U-Boot logo alone is not evidence that the kernel never executed; it stays
visible until some later display owner repaints it.

## Recovery result

The external Mac recovery path was exercised immediately. It accepted only the
known removable `disk4` layout, known candidate and device-created recovery
hash. It restored partition 4, reread the complete 64 MiB partition and matched
the accepted SHA. The one-shot installer and collector were renamed with
non-`.sh` suffixes so the failed candidate cannot reactivate.

## Next diagnostic gate

Do not trim the broad kernel yet. First add progress evidence that does not
depend on the normal launcher, DRM/fbdev, or the ROM-volume mount. The next
candidate should independently expose at least these boundaries:

1. kernel entry and earliest writable hardware;
2. completion of core and device initcalls;
3. initramfs `/init` entry;
4. MMC block-device availability;
5. direct-launcher exec.

Prefer a visible LED/GPIO code plus an early raw-partition trace. Reuse the
guarded two-boot installer and proven external recovery unchanged.

## Staged diagnostic derivative

Candidate `8b9ba42467b9879b94a7f61241fc5065c31206b71da1f29c21c6c13e993f9078`
keeps the failed candidate's exact `Image` SHA-256
`2294fca4c88834d379d063eb08c606224fea2d4eb6a77edd50b6e1b320ab3150`.
The complete initramfs comparison changes only `/init`; the diagnostic DTB adds
only a heartbeat/panic policy to the existing red status LED.

Interpret the second cold boot as follows:

| Red status LED | Furthest proven boundary |
| --- | --- |
| off throughout | GPIO LED driver not proven; U-Boot handoff or early kernel remains possible |
| heartbeat | kernel reached the built-in LED driver, but instrumented `/init` did not take ownership |
| solid | initramfs PID 1 mounted proc/sys/dev; fixed root device has not been observed |
| fast 100/100 ms blink | `/dev/mmcblk0p5` appeared; fsck/root mount is next |
| slow 700/300 ms blink | root mounted; launcher supervisor dispatch is next |
| off after an earlier pattern | launcher supervisor returned; a retained boot logo points at display/DRM/userspace painting |

The diagnostic `/init` and full 64 MiB image each reproduced byte-for-byte in
two clean host builds. Its one-shot installer, success collector and exact-hash
external recovery helper are staged on the test card.
