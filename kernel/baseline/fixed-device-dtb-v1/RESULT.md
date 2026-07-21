# Fixed-device DTB v1 result

Hardware boot: `95953775-8ed2-44e9-aae1-e3d289b8629c`

Result: **functionally accepted, rejected as a performance change**.

The checksum-gated Android boot image installed and booted. Launcher, content,
controls, media and power behavior passed, and the external stopwatch remained
about 3.5 seconds. The post-boot collector nevertheless reported `FAIL` because
all intended disabled subsystems still probed.

The candidate's raw DTB hash differs from the accepted baseline, proving the
write occurred. Its decompiled live DTB is identical to the original live DTB,
and all 20 targeted nodes read `okay`. Vendor U-Boot's `update dts` operation
therefore replaces or rewrites those status values before Linux receives the
tree.

Kernel `/init` boundary:

- original: 1.829244 seconds;
- candidate: 1.816965 seconds;
- difference: 12.279 ms, treated as boot jitter.

No probe-time claim is credited to this candidate. The experiment establishes
that these fixed-device removals belong in a source-built kernel/config (and,
later, U-Boot's own DT source) rather than only in the Android boot DTB slot.
