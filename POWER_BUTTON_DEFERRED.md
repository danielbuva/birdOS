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

## Hardware result

The checksum-gated image installed and reread successfully. After the new
Linux driver had run and the device was shut down normally, the user confirmed
that an ordinary quick tap powers on the device. This strongly supports the
ownership model above: Linux programs the retained PMIC threshold for the next
cold start. Forced-off, lid, charging and repeated near-boundary behavior still
belong in the final firmware acceptance sweep.

The exact active DTB describes the upper indicator as two GPIOs: PI11 is
`red:status` and PI12 is `green:power`; PI12 defaults on in Linux. The matching
ROCKNIX DDR4 U-Boot defconfig enables its status-LED framework on GPIO 267,
which resolves to PI11, with state 2. That explains the observed red LED during
power-on: U-Boot is explicitly driving the red half before Linux takes over.
It also corrects the earlier diagnostic-era claim that this device exposed no
red LED.

The shorter PMIC acceptance threshold should advance the accepted-power
boundary by roughly 384 ms, but U-Boot currently chooses which colour appears.
The next LED experiment should change only the guarded U-Boot indicator policy
from PI11 red to PI12 green (GPIO 268), then measure the earliest safe assertion
with the proven external recovery route. Runtime Linux policy remains separate:
PI11 red is reserved for discharging capacity at or below 41 percent. Any
residual display-dark interval belongs to the fixed `rg34xxsp_v1` U-Boot panel
sequence, never the launcher.

## Remaining acceptance plan

1. Starting with a post-programming cold boot, test at least ten normal taps
   and several intentionally too-short presses near/below 128 ms.
2. Correlate button-down, green-LED and first-frame timing with video if the
   subjective acceptance boundary remains unclear.
3. Verify normal shutdown, forced-off behavior, lid wake, charging startup and
   recovery-key behavior are unchanged.
4. Change U-Boot's GPIO 267/PI11 red status selection to GPIO 268/PI12 green in
   a separately recoverable build, then measure its assertion independently of
   PMIC acceptance and panel response.
5. Bake the verified 128 ms setting into the reproducible final firmware and
   remove the experimental installer.

## ROCKNIX fake-suspend distinction

The exact H700 ROCKNIX profile currently disables real kernel suspend and uses
`rocknix-fake-suspend` from its input worker. That release policy deliberately
ignores power-key events while `lid-closed.flag` exists; opening the lid is the
expected resume action. The final power acceptance sweep must therefore test
three separate interactions rather than report all of them as one wake path:

1. With the lid open, press power to fake-suspend and press it again to resume.
2. Close the lid; a power press while it remains closed is expected to do
   nothing under the stock policy.
3. Open the lid; this must resume the device.

Only failures in cases 1 or 3 are compatibility defects. Allowing power to
override a closed lid would be a deliberate Bird policy change with the risk of
lighting the panel inside the closed shell, not a kernel-wake optimization.

## References

- [X-Powers AXP2101 datasheet](https://bbs.aw-ol.com/assets/uploads/files/1662612785463-c9f5c599-8055-43f4-ae16-690bbc0536e6-axp2101_datasheet_v1.0_en.pdf)
- [Allwinner Linux PMIC development guide mirror](https://whycan.com/files/allwinner/f133mx-hxx/Software%E8%BD%AF%E4%BB%B6%E7%B1%BB%E6%96%87%E6%A1%A3/SDK%E6%A8%A1%E5%9D%97%E5%BC%80%E5%8F%91%E6%8C%87%E5%8D%97/Linux_PMIC_%E5%BC%80%E5%8F%91%E6%8C%87%E5%8D%97.pdf)
