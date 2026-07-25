# Historical engineering record

birdOS keeps failed experiments, measurements and intermediate designs because
they explain why the active fixed-device architecture exists. They are evidence,
not supported deployment alternatives. The authoritative current path is
[`ACTIVE_PATH.md`](../../ACTIVE_PATH.md).

## Major historical branches

- [`PROJECT_CHRONOLOGY.md`](PROJECT_CHRONOLOGY.md) preserves the project-wide
  timing record, accepted checkpoints and complete version-by-version narrative
  formerly kept in the root README.
- [`LEGACY_ROADMAP.md`](LEGACY_ROADMAP.md) preserves the original full roadmap,
  including its muOS-era architecture, feature sequence and accumulated stage
  notes. The concise root [`ROADMAP.md`](../../ROADMAP.md) is now authoritative.
- [`GAME_LOAD_DEFERRED.md`](GAME_LOAD_DEFERRED.md) preserves the muOS-era cold
  RetroArch/direct-bridge profile; the active stock-root dispatcher uses the
  retained ROCKNIX provider.
- [`INPUT_MAP.md`](INPUT_MAP.md) preserves the cross-OS and `muOS-Keys` input
  captures; the active path uses the release-matched `H700 Gamepad` mapping.
- [`POWER_BUTTON_DEFERRED.md`](POWER_BUTTON_DEFERRED.md) preserves the vendor
  PMIC-threshold and U-Boot LED proof; it does not describe the active ROCKNIX
  boot chain.
- [`BOOT_PROCESS_AUDIT.md`](../../BOOT_PROCESS_AUDIT.md) is the measured
  muOS/static-PID-1 boot graph that preceded the active ROCKNIX stock-root path.
- [`launcher/README.md`](../../launcher/README.md) records the launcher proofs,
  muOS handoffs, catalogue experiments and transition to the persistent
  initramfs process. The launcher source remains active; most staged delivery
  descriptions in that document are historical.
- [`userspace/README.md`](../../userspace/README.md) records checksum-gated muOS
  service experiments. These card-side installers are not the active ROCKNIX
  stock-root integration.
- [`storage/README.md`](../../storage/README.md) records the corresponding muOS
  mount, bind and card-installer experiments.
- [`firmware/README.md`](../../firmware/README.md) records muOS firmware,
  bootloader, brightness, power-key and clean-root investigations. Its measured
  hardware evidence remains useful, but its old deployment paths are not
  current.
- [`kernel/mainline/README.md`](../../kernel/mainline/README.md) records the
  rejected Android-handoff/mainline attempt.
- [`kernel/SOURCE_AUDIT.md`](../../kernel/SOURCE_AUDIT.md) records the dated
  vendor-4.9 source gap that motivated the source-complete ROCKNIX route.
- [`kernel/rocknix/clean-root/README.md`](../../kernel/rocknix/clean-root/README.md)
  and the v5 sections of [`kernel/rocknix/README.md`](../../kernel/rocknix/README.md)
  record the permanent-initramfs clean-root experiment now retained only as the
  boot fallback and as architecture evidence.
- [`kernel/rocknix/README.md`](../../kernel/rocknix/README.md) is the long
  chronological ROCKNIX source-kernel, clean-root and stock-root record. Its
  stock-root v6.22 result is the immediate physical predecessor of the current
  v6.23 repository candidate.

## Safe reading rule

Do not deploy a command merely because it appears in a historical README.
Trace it from the complete active builder and candidate manifest first. Old
version numbers, paths and checksums are intentionally retained where they are
part of a dated result; only text claiming to describe the *current* system is
expected to match [`ACTIVE_PATH.md`](../../ACTIVE_PATH.md).
