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

The Orange Pi audit is checksum-pinned under ignored
`kernel/work/vendor-baseline/`. A forced compile with normalized defaults also
failed while linking an unresolved `yt8511_config_out_125m` Motorcomm PHY
reference. Enabling that unrelated public-tree option could make the compile
continue, but would not restore the missing RG34XX-SP drivers and would create a
false baseline.

## Decision

No source-complete match was located in the public trees audited above. The
accepted vendor `Image` therefore remains the only boot kernel and rollback
anchor. It must not be replaced by the public lineage build.

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
