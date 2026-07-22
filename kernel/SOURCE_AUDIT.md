# RG34XX-SP kernel source audit

Audit date: 2026-07-21.

The objective is a source-complete, reproducible kernel for this exact device.
An image that happens to boot another H700 handheld is not an acceptable
baseline.

| Candidate | Evidence | Result |
| --- | --- | --- |
| Active muOS kernel | Linux 4.9.170 `Image`, embedded 4,209-line config and exact Linaro compiler identity | Bootable reference; source is not contained in the firmware |
| [Orange Pi sun50iw9 4.9 branch](https://github.com/orangepi-xunlong/linux-orangepi/tree/orange-pi-4.9-sun50iw9) | Correct version and obvious BSP lineage | Incomplete: `olddefconfig` changes 97 diff lines and removes active power, audio and exFAT symbols |
| [KNULLI RG34XX-SP target](https://github.com/knulli-cfw/knulli-linux/tree/knulli-main/board/allwinner/h700/rg34xx-sp) at `099125a6e2c669b6f1287c7a193cebd3857ce630` | Exact device target, public H700 config and prebuilt device boot partitions | Still selects the Orange Pi 4.9 branch; its config differs from the active muOS config in 52 config records and lacks the later active power/audio/exFAT additions |
| Public mustardroot external tree | H700 config and binary device assets | No matching downstream kernel source located |
| [Linux stable v7.0.11](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tag/?h=v7.0.11) at `bb532bfaf7919c7c98caab81864e9ce2646e11e3` | Source-complete upstream H700/RG35XX-SP, AXP717 power, H616 audio, Panfrost, RTC and fixed-button support | Chosen replacement base; the RG34XX-SP panel/display and analog controls still need an exact device layer |
| [ROCKNIX H700 stable release](https://github.com/ROCKNIX/distribution/tree/20260701/projects/ROCKNIX/devices/H700) at `3e4ee5852e6ca5ea73a38369d2639fad2262648b` | Exact public source tag for the verified `20260701` DDR4 artifact, including RG34XX-SP DTB, Linux 7.0.11 patches, U-Boot v2026.01 and TF-A v2.12.0 | Chosen complete boot-chain baseline; the shipping chain is reproduced before Bird or any trimming is introduced |

The Orange Pi audit is checksum-pinned under ignored
`kernel/work/vendor-baseline/`. A forced compile with normalized defaults also
failed while linking an unresolved `yt8511_config_out_125m` Motorcomm PHY
reference. Enabling that unrelated public-tree option could make the compile
continue, but would not restore the missing RG34XX-SP drivers and would create a
false baseline.

## Vendor-lineage decision

No source-complete match was located in the public trees audited above. The
accepted vendor `Image` therefore remains the only boot kernel and rollback
anchor. It must not be replaced by the public lineage build.

The installed userspace does contain literal `4.9.170` assumptions. The active
network profile names
`/lib/modules/4.9.170/kernel/drivers/net/wireless/rtl8821cs/8821cs.ko`, and an
older depmod migration guard tests `/lib/modules/4.9.170/modules.dep`. These are
runtime paths, not evidence that the matching downstream source ships on the
card. Vanilla `linux-4.9.170` can build some compatible add-on modules when
paired with a close config/toolchain, but it still lacks the private vendor
tree that produced this PMIC/audio/exFAT-enabled `Image`.

Work continues in two non-destructive tracks:

1. Capture the running DTB, modules, devices, interrupts and memory map from the
   accepted kernel. This defines the hardware closure the replacement must
   satisfy.
2. Evaluate a source-complete kernel base against that closure. Prefer a
   maintained, auditable base if it supports the panel, PMIC, input, audio,
   storage, suspend and Mali path. Reconstructing unpublished 4.9 downstream
   pieces remains a fallback, not an assumption.

Only after a source-complete untrimmed replacement passes every hardware and
application check will fixed-device config removal begin.

## Replacement decision

Reconstructing the unpublished vendor 4.9 additions is no longer the primary
path. Linux 7.0.11 plus the pinned ROCKNIX H700 hardware patch set provides a
complete, maintained source tree for a clean-room compatibility baseline. The
custom board DTS uses standard upstream `adc-joystick`, `io-channel-mux` and
`gpio-mux` bindings instead of importing the distribution's legacy polling
driver. Only the RG34XX-SP panel command stream is embedded; wireless firmware
stays outside the kernel so networking can remain on demand.

This is not yet permission to flash it. The current launcher and applications
were built around the vendor framebuffer/Mali ABI, whereas the replacement
uses DRM/KMS and Panfrost. Compilation, DT validation, module-closure review,
boot packaging and a rollback-safe hardware acceptance sequence are separate
gates. The accepted vendor image remains the recovery anchor throughout.

The first compilation, static DT/config and reproducibility gates pass. Two
clean container builds produced byte-identical artifact manifests; the kernel
is exactly `7.0.11-dani-compat` and its `Image` SHA-256 is
`2294fca4c88834d379d063eb08c606224fea2d4eb6a77edd50b6e1b320ab3150`.
Both attempts to boot it through the vendor U-Boot/Android handoff stopped
before Linux left any capture. This closes only the source-build gate and is
negative evidence against that hybrid handoff. The exact shipping chain is now
pinned under [`rocknix/`](rocknix/); its unmodified hardware proof precedes a
new source rebuild. The full first-build result remains in
[`mainline/BUILD_AUDIT.md`](mainline/BUILD_AUDIT.md).

## Why clean 4.9.170 remains a fallback

Nothing prevents Bird from extending vanilla Linux 4.9.170 with new
RG34XX-SP-specific code. ROCKNIX is also a valuable public reference for the
required panel sequence, device-tree topology, gamepad mapping, PMIC behavior,
audio graph and suspend path. The difficulty is not permission or conceptual
feasibility; it is the backport boundary. ROCKNIX's implementations target
modern DRM, regulator, clock, input, audio and power-management APIs. Copying
them into 4.9 usually requires translating those APIs and their dependencies,
then validating the interactions the unpublished vendor tree previously
handled.

The physically tested 7.0.11 route has already crossed the stronger gate: the
exact public boot chain reached Bird's first frame at 1.547 seconds, mounted
the customized root and suspended/woke. Its first failures are narrow
4.9-oriented userspace assumptions, not missing early hardware support.
Therefore the current order is to finish that source-kernel compatibility
matrix, trim it for this single device, and compare it against the accepted
vendor kernel. A targeted 4.9 backport remains justified if the modern path
later loses a measured latency, power or compatibility race; ROCKNIX and the
accepted kernel traces would then serve as behavioral references rather than
code copied without adaptation.
