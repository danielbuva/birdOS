# Power-button turn-on threshold proof

This hardware-owned interaction was originally deferred to final kernel and
U-Boot work. It has now been promoted into the current batched hardware cycle
because it is independent of the storage and entropy changes and its result is
easy to distinguish: deliberate short cold-power taps either work or do not.

## What the firmware proves

The RG34XX-SP device tree identifies an X-Powers AXP2202 PMIC using the
AXP2101-compatible power-key driver. The active Linux boot device tree contains:

```text
pmu_powkey_on_time = <0x200>;   # 512 ms
pmu_powkey_long_time = <0x5dc>; # 1500 ms
pmu_powkey_off_time = <0x1770>; # 6000 ms
```

The U-Boot DTB embedded in the original TOC1 instead contains:

```text
pmu_powkey_on_time = <0x80>;    # 128 ms
pmu_powkey_long_time = <0x5dc>; # 1500 ms
pmu_powkey_off_time = <0x6000>; # vendor U-Boot value
```

The PMIC exposes four discrete cold-power thresholds: 128 ms, 512 ms, 1 second
and 2 seconds. Therefore a literal zero-duration edge is not available, but a
normal tap longer than 128 ms should be sufficient after the PMIC is programmed
with its minimum setting.

The Linux value is the likely owner of the *next* cold start because its power-
key driver probes while the device is already running and programs the PMIC
before shutdown. U-Boot cannot shorten the press that was required to reach
that same U-Boot instance. This ownership inference must be verified on
hardware rather than assumed from the two DTBs.

## Staged proof

`firmware/build-power-key-128.sh` starts from the exact hardware-verified static
PID-1 boot image. It changes only Linux's `pmu_powkey_on_time` from 512 to 128,
rebuilds the Android v2 SHA-1 ID, unpacks the result again, and verifies:

- kernel bytes are identical;
- compressed initramfs bytes are identical;
- DTB size remains 137,723 bytes;
- long-press remains 1,500 ms;
- forced-off remains 6,000 ms.

The resulting 64 MiB image is SHA-256
`a6bafa83add62af92a27450594f6da4e8dfacdbcc0c247c08c512a7b1495b6b5`.
The checksum-gated installer accepts only the currently verified boot image,
backs it up, writes and rereads the raw partition, and automatically restores
the backup on a verification mismatch.

## Hardware proof plan

1. The first boot installs the candidate but still runs the old 512 ms kernel.
2. The second cold boot runs the new DTB and programs the PMIC, then must be
   shut down normally. This press may still require the old threshold.
3. Starting with the third cold boot, test at least ten deliberate normal taps
   and several intentionally too-short presses near/below 128 ms.
4. Correlate button-down, green-LED and first-frame timing with video if the
   subjective acceptance boundary remains unclear.
5. Verify normal shutdown, forced-off behavior, lid wake, charging startup and
   recovery-key behavior are unchanged.
6. If the green LED still appears late, separate PMIC acceptance time from
   bootloader LED policy; do not misattribute an LED delay to the power key.
7. Bake the verified 128 ms setting into the reproducible final firmware and
   remove the experimental installer.

## References

- [X-Powers AXP2101 datasheet](https://bbs.aw-ol.com/assets/uploads/files/1662612785463-c9f5c599-8055-43f4-ae16-690bbc0536e6-axp2101_datasheet_v1.0_en.pdf)
- [Allwinner Linux PMIC development guide mirror](https://whycan.com/files/allwinner/f133mx-hxx/Software%E8%BD%AF%E4%BB%B6%E7%B1%BB%E6%96%87%E6%A1%A3/SDK%E6%A8%A1%E5%9D%97%E5%BC%80%E5%8F%91%E6%8C%87%E5%8D%97/Linux_PMIC_%E5%BC%80%E5%8F%91%E6%8C%87%E5%8D%97.pdf)
