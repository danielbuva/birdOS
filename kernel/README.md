# Fixed RG34XX-SP kernel work

The active device runs the Allwinner vendor kernel:

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

The staged `57-capture-kernel-baseline.sh` is a one-boot, post-menu collector.
It saves the running `/proc/config.gz`, loaded modules, interrupts, I/O map,
input devices, live DTB and kernel log.  This tells later config work what the
fixed device actually uses; it does not delay the first interactive frame.
