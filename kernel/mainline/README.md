# Source-complete RG34XX-SP compatibility kernel

This is the first source-level kernel workstream. It does **not** replace the
accepted 4.9.170 boot image yet.

The accepted kernel is a hard performance gate, not merely a recovery
artifact. A trimmed source kernel is promoted only if the same Bird
initramfs/userspace beats it on power-to-input, kernel-to-first-frame,
interaction latency and efficiency. Stock reverse engineering is deliberately
targeted: when the source path loses a measured boundary, recover only that
vendor behavior and implement it in controlled source.

## Pinned source

- Linux stable `v7.0.11`, commit
  `bb532bfaf7919c7c98caab81864e9ce2646e11e3`. This deliberately matches
  ROCKNIX's H700 patch base; updating stable releases comes after the first
  hardware-compatible build is reproducible.
- ROCKNIX `next`, commit
  `d88cf6393e55364ec6470d625737125fc0d32cd4`, used only for its public,
  hardware-used H700 display, panel, PWM, PMIC, USB and board patches.

Linux 7.0 contains upstream H700/RG35XX-SP support, AXP717 power/battery/USB
drivers, the H616 codec, Panfrost, the PCF8563 RTC and the fixed digital GPIO
buttons. ROCKNIX supplies the remaining RG34XX-SP LCD pipeline and panel
firmware interface. Our board DTS keeps the upstream input model and describes
the two analog sticks with standard `adc-joystick`, `io-channel-mux` and
`gpio-mux` bindings; it does not import ROCKNIX's legacy polling joypad driver.
The RG34XX-SP panel command stream is embedded in the kernel so first display
does not wait for real-root firmware. Wi-Fi and Bluetooth firmware is not
embedded and remains eligible for explicit on-demand loading.
The PCF8563 external RTC is explicitly enabled because the broad ROCKNIX H700
config declares the device but otherwise leaves its driver out.

The initial compatibility configuration is intentionally broader than the
final kernel. It exists to prove display, controls, root storage, power,
charging, lid/suspend, internal audio, GPU, games and media before removals.
Only after that baseline passes do HDMI, Bluetooth and Wi-Fi become explicit
on-demand module closures and unused drivers disappear.

The first two hardware attempts mixed this source kernel with Anbernic's
vendor U-Boot/TF-A and Android boot handoff. Both retained the U-Boot logo and
provided no Linux evidence. The next bring-up baseline therefore reproduces
ROCKNIX's exact working H700 boot chain first; Bird replaces its initramfs and
userspace only after that unmodified source-based boundary boots this exact
hardware revision.

## Build

```sh
./kernel/build-mainline-compat.sh
```

The container provides a case-sensitive Linux filesystem. This is mandatory:
both the legacy and current kernel trees contain filenames that collide on the
default case-insensitive macOS filesystem.

Successful output is placed under ignored `kernel/work/mainline-compat/`:

- `Image`
- `sun50i-h700-anbernic-rg34xx-sp-dani.dtb`
- `built.config`
- `built.dts` and `kernel.release`
- `System.map` and `Module.symvers`
- `modules.list` and deterministic `modules.tar.xz`
- `sizes.txt`
- `sha256sums.txt`

These files are build evidence, not a card candidate. Packaging is gated on a
separate compatibility audit because the current launcher and application
stack use the vendor framebuffer/Mali ABI, while the new kernel uses DRM/KMS
and Panfrost.

Run the machine-checkable pre-deployment audit with:

```sh
./kernel/audit-mainline-compat.sh
```

The audit requires every boot-critical display, input, storage, power, RTC and
audio driver to be built in, requires Bluetooth to remain modular, checks the
fixed board description, and verifies every artifact checksum. Passing it
means the source baseline is internally coherent; it does not claim hardware
compatibility until a rollback-safe card test passes.

[`BUILD_AUDIT.md`](BUILD_AUDIT.md) records the passing two-build
reproducibility result, artifact identities, deliberate compatibility excess
and the remaining pre-trim hardware gates.
[`UBOOT_HANDOFF_AUDIT.md`](UBOOT_HANDOFF_AUDIT.md) records the padded FDT
capacity, Android-DTB copy path and simulated MMC/DRAM mutations required while
the accepted vendor U-Boot remains in place.
[`FIRST_BOOT_RESULT.md`](FIRST_BOOT_RESULT.md) records the rejected first boot,
verified recovery and the staged red-LED boot-boundary derivative.

## DTB v1 result that led here

The Android-boot DTB-only candidate installed and booted, and all tested
functionality passed at about 3.5 seconds. The capture nevertheless showed that
all 20 disabled nodes were `okay` again and every USB, second-SD, HDMI,
camera/deinterlace and Bluetooth probe still ran. Its decompiled live DTB is
identical to the original live tree. The vendor U-Boot `update dts` step is
therefore restoring those status properties before Linux starts.

That experiment is rejected as a performance change: `/init` moved from
1.829244 to 1.816965 seconds, only 12.279 ms and within ordinary boot jitter.
It proved that reliable removal belongs in the compiled kernel/config (or,
later, the U-Boot DT source), not in this Android-boot DTB slot alone.
