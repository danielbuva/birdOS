# birdOS kernel delta from stock ROCKNIX

This records exactly how the RG34XX-SP kernel differs from stock ROCKNIX
20260701. `ACTIVE_PATH.md` remains the promotion authority; the TSV files below
bind the exact reproducible artifacts.

## Common source authority

- ROCKNIX commit: `3e4ee5852e6ca5ea73a38369d2639fad2262648b`.
- Linux commit: `bb532bfaf7919c7c98caab81864e9ce2646e11e3` (7.0.11).
- Joypad commit: `7647fdb0fc89cd69b284903bf7707e861df5dc7e`.
- Build container:
  `sha256:aac053f343e057c6bb412cf4d6bab3090b6d050b94c80d60e86a6d794185f460`.
- The DTB remains byte-identical to stock:
  `f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31`.
- The source-built module archive remains
  `56bd291210ef47a020c3c6dfcac6f6987135ef4bf20f22435138acafb6107211`.

Stage 8 first established behavior-equivalent source ownership. It kept the
pinned official embedded initramfs and accepted SYSTEM, substituting only the
complete reproducible 7.0.11 module tree. It did not intentionally remove
kernel features or hardware support.

## Currently accepted kernel

`kernel/rocknix/source-kernel-single-gpio-read.tsv` binds the kernel deployed in
`v6.23-20260811-071550`. It differs from stock in two ways:

1. The exact RG34XX-SP `rocknix-singleadc-joypad` driver is linked into the
   Image instead of inserted later as an external module. The module is still
   built as an oracle, but the early initramfs no longer embeds the duplicate.
   Identity, all keys and axes, both sticks, rumble and reconnect are retained.
2. Each GPIO button is read once per 10 ms poll. Stock read the same GPIO once
   for error detection and immediately again for its value. Bird stores the
   first result and uses it for both. All four analog-axis ADC reads remain.

The accepted Image is 30,926,856 bytes with SHA-256
`1dfa7e4a740a79ee9814c2da54080a0d843e874f5ec92fbd1fb91e58a9c8c2b5`.
These changes remove no CPU/GPU/turbo range, suspend, audio, display, storage,
networking, Bluetooth, HDMI or rumble capability.

## Current unaccepted candidate

`kernel/rocknix/source-kernel-single-input-sync.tsv` includes the accepted
changes above and changes only event publication:

- stock/accepted code publishes an ADC frame and then a GPIO frame each poll;
- the candidate samples the same controls in the same order, then emits one
  combined `SYN_REPORT` per 10 ms poll;
- driver open still emits one complete initial-state frame.

This structurally removes 100 input-frame publications per second without
removing a hardware read. Its reproducible 30,926,856-byte Image is
`7c37f4faad42326926740286f1b9d8d2beb461d31751d81103c25d9baa44bde3`.
It remains unaccepted until its separate RG34XX-SP gate passes.

## Rejected experiment

The button-only experiment removed live ADC polling while leaving nominal axis
capabilities. Hardware testing proved both analog sticks are real and used.
That mode was removed and is not an optimization baseline.

## Intentionally unchanged for later work

- CPU, GPU and turbo controls remain within RG34XX-SP-supported ranges.
- Built-in vibration/rumble remains supported.
- HDMI and Bluetooth remain unchanged pending a product decision.
- Panel readiness, brightness ownership, input IRQ conversion, kernel
  subtraction, green boot LED policy and further power work remain separate
  measured candidates.

## Reproduction

`kernel/rocknix/build-source-reference.sh` applies each bounded change under an
exact-text authority check, builds in the pinned container and emits hashes and
`parity.tsv`. Candidates must reproduce byte-for-byte in two separate builds.
`kernel/rocknix/tests/test-source-kernel-system.sh` verifies the source and
SYSTEM contracts; the canonical builder verifies every bound digest again.
