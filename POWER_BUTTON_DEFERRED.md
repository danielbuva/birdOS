# Deferred power-button turn-on threshold

This hardware-owned interaction is intentionally placed at the end of the
current OS roadmap, beside the final kernel and U-Boot work. It is programmable
and should eventually be shortened, but it is independent of the userspace
service-removal work now in progress.

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

## Later proof plan

1. Add a PMIC-register read before changing anything and correlate button-down,
   green-LED and first-frame timing with video.
2. Patch only the active Linux DTB `pmu_powkey_on_time` from 512 to 128.
3. Boot once so the driver programs the PMIC, shut down normally, then test at
   least ten deliberate taps and several presses shorter than 128 ms.
4. Verify normal shutdown, forced-off behavior, lid wake, charging startup and
   recovery-key behavior are unchanged.
5. If the green LED still appears late, separate PMIC acceptance time from
   bootloader LED policy; do not misattribute an LED delay to the power key.
6. Bake the verified 128 ms setting into the reproducible final firmware and
   remove the experimental installer.

## References

- [X-Powers AXP2101 datasheet](https://bbs.aw-ol.com/assets/uploads/files/1662612785463-c9f5c599-8055-43f4-ae16-690bbc0536e6-axp2101_datasheet_v1.0_en.pdf)
- [Allwinner Linux PMIC development guide mirror](https://whycan.com/files/allwinner/f133mx-hxx/Software%E8%BD%AF%E4%BB%B6%E7%B1%BB%E6%96%87%E6%A1%A3/SDK%E6%A8%A1%E5%9D%97%E5%BC%80%E5%8F%91%E6%8C%87%E5%8D%97/Linux_PMIC_%E5%BC%80%E5%8F%91%E6%8C%87%E5%8D%97.pdf)
