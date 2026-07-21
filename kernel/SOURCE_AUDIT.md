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
| [ROCKNIX H700 support](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/devices/H700) at `d88cf6393e55364ec6470d625737125fc0d32cd4` | Current RG34XX-SP panel identifier, panel command data and H700 display/PWM/USB patches used by a shipping distribution | Chosen hardware-evidence layer; legacy polling joypad, RGB and distro-specific policy are deliberately excluded |

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

The compilation, static DT/config and reproducibility gates now pass. Two
clean container builds produced byte-identical artifact manifests; the kernel
is exactly `7.0.11-dani-compat` and its `Image` SHA-256 is
`2294fca4c88834d379d063eb08c606224fea2d4eb6a77edd50b6e1b320ab3150`.
This closes the source-build gate, not the hardware-compatibility gate. The
full result and next acceptance boundary are recorded in
[`mainline/BUILD_AUDIT.md`](mainline/BUILD_AUDIT.md).
