# Fixed RG34XX-SP kernel work

**Status:** this document records the original vendor-kernel audit and the
replacement-kernel investigation. The active stock-root v6.23 candidate uses
the byte-identical ROCKNIX 20260701 Linux 7.0.11 kernel and DTB; kernel trimming
remains deferred. See [`ACTIVE_PATH.md`](../ACTIVE_PATH.md) for the running
boot path and [`docs/history/README.md`](../docs/history/README.md) for the
historical branches.

The original muOS baseline ran the Allwinner vendor kernel:

- Linux `4.9.170`, SMP PREEMPT;
- closest public source lineage: Orange Pi `orange-pi-4.9-sun50iw9` at commit
  `0cd0547ea405b84b5b60fbc92978ac1bc2b68055`;
- compiler: Linaro GCC `5.3.1 20160412`, release `5.3-2016.05`;
- build identity: `flower@flower-B85M-D2V`, build number 2;
- active `Image` SHA-256:
  `3fdc350415badec1937b8cb7b697ff97219b700d5d95e2092403fb045e6a1f7b`;
- active `Image` size: 17,686,536 bytes.

`baseline/vendor.config` is the complete configuration embedded in that active
kernel between its `IKCFG_ST` and `IKCFG_ED` records.  The source tree's own
`scripts/extract-ikconfig`, run with `LC_ALL=C`, independently produces the
same SHA-256:

`565948300ae2d0f68a8ec85a18be033cde06ad4c46a988bebf708b9ce35cb119`.

## Source boundary

The public Orange Pi commit is **not** the complete source for the active
kernel. Running `olddefconfig` with the embedded active config produces
`kernel/work/vendor-baseline/config-normalization.diff`: 97 diff lines are
needed because the public tree does not know about the active AXP2202 power
driver, its newer sunxi audio stack, exFAT code and several later wireless
choices. Those are functional requirements, not candidates for trimming.

Consequently, `build-vendor-baseline.sh` currently performs a reproducible
public-lineage audit and deliberately stops before compilation. It will emit an
`Image` only if the source can represent every line of the pinned active config.
**Never install the current public-lineage output on the card.** The audit
establishes compiler/source provenance, measures the gap and provides a
controlled base for reconstructing or replacing the unpublished downstream
pieces. A forced test compile also exposed an unresolved Motorcomm PHY symbol,
confirming that filling missing config lines with defaults is not sufficient.
The accepted vendor `Image` remains the bootable fallback until an auditable
kernel passes display, input, power, storage, audio, suspend, content and
shutdown acceptance.

[`SOURCE_AUDIT.md`](SOURCE_AUDIT.md) records the public trees checked and the
evidence for this boundary. Notably, current KNULLI has an exact RG34XX-SP
target but still selects the same Orange Pi 4.9 branch; its published H700
config differs from the active muOS config in 52 records and does not supply
the later downstream additions.

The build deliberately uses an amd64 Linux container.  The vendor tree has
source filenames that differ only by case, so building from a normal
case-insensitive macOS checkout silently corrupts it.  The container also runs
the exact x86-64 Linaro compiler named by the active kernel. Linaro's retired
archive now redirects binary downloads to a contact page, so the pinned
archive is fetched from Buildroot's source mirror and verified against
Buildroot's published SHA-256
`1941dcf6229d6706bcb89b7976d5d43d170efdd17c27d5fe1738e7ecf22adc37`.

Run:

```sh
./kernel/build-vendor-baseline.sh
```

Today this creates `built.config`, `config-normalization.diff` and pinned
comparison checksums, but no bootable kernel. Once the missing downstream code
is supplied or replaced and the config normalizes byte-for-byte, the same gate
continues through `Image`, module and checksum generation.

The first goal is not optimization. It is to record the complete live hardware
closure and close the source gap. Only a source-complete build may become a
checksum-gated kernel candidate, and no configuration option may be removed
until that unmodified candidate passes the full hardware and application
acceptance test.

The accepted `57-capture-kernel-baseline.sh` run saved the running
`/proc/config.gz`, loaded modules, interrupts, I/O map, input devices, live DTB
and kernel log without delaying the first interactive frame. The complete
capture and decompiled DTB are pinned under `baseline/live/`.

[`FIXED_DEVICE_PROFILE.md`](FIXED_DEVICE_PROFILE.md) turns that capture into the
measured pre-init timeline and exact hardware closure. The DTB-only candidate
booted and passed functionality, but the captured live tree proved that vendor
U-Boot restored all 20 disabled nodes before Linux. Every targeted probe still
ran and `/init` moved only 12.279 ms, which is ordinary jitter. That candidate
is retained as negative evidence, not as an optimization.

The first replacement implementation remains under [`mainline/`](mainline/).
It produced a reproducible Linux 7.0.11 compatibility build, but two hardware
attempts combined that kernel with the vendor Android boot path and stopped
before any Linux capture. Those attempts proved packaging reproducibility and
external recovery, not hardware compatibility.

The active replacement track is now [`rocknix/`](rocknix/). It starts from the
verified stable `20260701` DDR4 release and its exact public SPL, TF-A, U-Boot,
kernel, patch set and RG34XX-SP DTB. The generic release was provisioned only
with its documented `/dtb.img` copy. The first hardware gate is to boot that
unchanged known-working chain; Bird is substituted only after that proof.
The final source build remains a challenger and is promoted only after it
beats the accepted 4.9.170 Bird baseline.

The first Bird gates also corrected the meaning of “source complete.” The
stable H700 profile selects `rocknix-joypad` as a separate kernel package; it
is not one of the 30 Linux patches. The shipping RG34XX-SP DTB names that
driver directly. Bird v1 accidentally opened the independent volume-key event,
and v2 rejected that node but could not find the absent `H700 Gamepad`, so its
watchdog rebooted the only boot label. V3 pins the external GPL repository at
`7647fdb0fc89cd69b284903bf7707e861df5dc7e`, builds its H700 module against
the exact kernel ABI and inserts it from early init before launcher dispatch.
That module is a compatibility baseline, not the final design: after the broad
gate passes, remove its unrelated board paths or replace it with standard
fixed-device input bindings.
