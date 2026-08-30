# Active birdOS path

This document is the authority for the code that builds, installs and runs the
current birdOS system. The active implementation path is **stock-root v6.23**.
The current human promotion record binds clean public source
`5373c644b9c91ac21a17e145375747a8196a3337`,
immutable release `v6.23-20260814-201218`, deploy-manifest digest
`904c8da42a6ec84ccf4b291205999c3b0e25900f4bec7bb3f9e0cfefb29164dd`,
device-contract digest
`1664a3778abcd3687865a82fd28bba5b468f6c3c7e9a46bf90f7c3acb1e08162`
and generated-catalog digest
`9795aae6baddc292f5d9954a444656e303db305c639284f16eb10288c41f1f93`.
The complete host gate and broad RG34XX-SP behavior gate passed on 2026-08-14.
This canonicalizes the accepted Stage 9 IRQ button path and the reviewed
Stage 10 runtime/tooling boundary. All 17 digital controls, including L3/R3,
use independent 5 ms GPIO
edge debounce; only four analog axes retain the 10 ms ADC poll. Broad behavior
passed, and Input Test completed all 29 digital, analog, auxiliary and rumble
checks. Its kernel SHA-256 is
`cad7ad8437d0a7de0d819846b12fdf83078f5878313704d0de79274431ec9d64`. This is
functional acceptance, not a calibrated latency or energy claim. The
previously accepted immutable release `v6.23-20260811-234132` is verified in
the private archive at manifest digest
`a0a38b04be25f2d09009b0677d33c0d34c65b027c0ff1b9463f71cdeec9b274b`.
That release was built from clean source
`c07fe18769a13a3b1997e2cf1a4900cc55423d5b`; it remains verified external
history, not an on-card production rollback requirement. A successor becomes
the optimization baseline only when its exact clean source, release, manifest,
contract and catalogue tuple passes the host and physical gates.

birdOS targets one device: the Anbernic RG34XX-SP. Fixed paths, device names,
display geometry and hardware policy are deliberate. Older muOS stages,
source-kernel challengers and clean-root experiments remain useful evidence,
but they are not alternate active implementations.

The accepted pre-rotation card snapshot selected `v6.23-20260808-214626`; its
previous selector named `v6.23-20260808-124816`. The current 128 MiB residency
policy keeps one immutable canonical base plus mutable `dev-current`, archives
and verifies superseded immutable releases privately, self-references the
canonical selector, and only then deletes their card copies rather than keeping
an on-card release history. Stage 6 namespace v1 is active: the runtime uses
`/run/bird`, `/storage/roms`, `/storage/media` and
`/storage/bird-data/Bird`. The corrected canonical provider map and broad
RetroArch, Flycast, PPSSPP, DraStic, OpenBOR, Ports, media, networking,
persistence and hardware gate passed. Legacy fallback boot bytes and the old UI
are no longer installed; remaining historical source is not active-path
compatibility or ordinary production history.
The immutable-dispatcher, immutable-supervisor, first-frame-preparation and
boot-snapshot, complete-toolset, content-shell, fixed-autostart, fixed-session,
fixed-housekeeping, fixed-application-profile, fixed-performance and warm-
manager batches passed their RG34XX-SP gates. The manager experiments proved
that on-demand seatd and post-coldplug udevd exit move work into content launch,
so both remain warm. HDMI and Bluetooth remain unchanged; retention or removal
of either is an explicit later product decision.

Optimization is lexicographic: honest usable menu first; navigation plus every
launch, close and interactive return second; calibrated battery life third;
memory/storage fourth. Interaction and battery use measured fixed-consumer
decisions rather than an all-warm or all-cold rule. A launch-critical process
may remain prepared when its latency benefit is material; unrelated residency
requires a measured energy justification and may be quiesced only inside the
frozen boot/interaction margins.

The operational tie-break is temporal. While a requested navigation, launch,
switch, close or menu-return transition is active, responsiveness wins and
noncritical cleanup is deferred. Once responsive ownership is established and
no action is pending, battery wins and the system should converge promptly to
its lowest practical idle state. Small precomputed or cached state may remain
when its measured common-action benefit justifies idle energy; entire generic
services do not remain warm by default.

## Authority

| Responsibility | Canonical source |
| --- | --- |
| Complete stock-root build | [`kernel/rocknix/build-stock-root-compat.sh`](kernel/rocknix/build-stock-root-compat.sh) |
| Early initramfs overlay | [`kernel/rocknix/build-stock-root-early-initramfs.sh`](kernel/rocknix/build-stock-root-early-initramfs.sh), invoked by the complete build |
| Final-root integration | [`kernel/rocknix/stock-root/`](kernel/rocknix/stock-root/) |
| Launcher | [`launcher/bird-launcher.c`](launcher/bird-launcher.c) and its generated catalogue |
| Launcher visual source | [`firmware/assets/bird-launcher-backdrop.png`](firmware/assets/bird-launcher-backdrop.png) and [`firmware/generate-launcher-bootlogo.py`](firmware/generate-launcher-bootlogo.py) |
| Card deployment | [`firmware/mac-update-rocknix-stock-root-v6.sh`](firmware/mac-update-rocknix-stock-root-v6.sh) |
| Mutable local development | [`dev-build-and-deploy.sh`](dev-build-and-deploy.sh) and [`DEV_WORKFLOW.md`](DEV_WORKFLOW.md) |
| Legacy Ports data migration | [`firmware/mac-migrate-rocknix-ports.sh`](firmware/mac-migrate-rocknix-ports.sh), run separately before deployment |
| Accepted hardware and product policy | [`DEVICE_PROFILE.md`](DEVICE_PROFILE.md) |
| Current optimization work | [`ROADMAP.md`](ROADMAP.md) and [`ROCKNIX_AUDIT.md`](ROCKNIX_AUDIT.md) |
| Fixed machine-readable hardware contract | [`bird-device-contract.tsv`](bird-device-contract.tsv), compiled through its generated launcher header |

The complete build emits `deploy-manifest.tsv` at the build-output root. That
manifest is the authority for every deployed regular file, required empty
directory, mode and digest, plus every immutable external byte stream consumed
by build or deployment. The updater uses the same file for preflight, staging
and installed-tree verification; a second hand-maintained copy list is not an
independent source of truth.

The manifest records the deployed device contract and its digest plus the
generated catalogue digest. The device contract never refers back to the
manifest. A promotion record created only after the physical gate binds source
SHA, immutable release ID, manifest digest, device-contract digest and
catalogue digest. Live measurements are acquired and sealed outside the source
tree before any optional import under `measurements/`.

Generated files below `kernel/work/` are build results, not source. The
committed `launcher/bird-launcher.o`, old card-side installers and historical
payload checksums do not participate in the active stock-root build unless the
complete builder names them explicitly.

## Pinned compatibility base

The active baseline retains the exact ROCKNIX `20260701` DDR4 compatibility
base:

- the release `KERNEL` and `dtb.img`;
- the immutable ROCKNIX `SYSTEM` image;
- the captured, configured writable `STORAGE` image; and
- the release-matched H700 joypad module used by the early overlay.

The complete builder verifies these inputs before generating birdOS files.
birdOS currently changes the external initramfs overlay, launcher, fixed
services, integration scripts and activation metadata. It does not claim to
rebuild or trim the release kernel yet.

Stage 8 promoted its production-only parity candidate. Its authority is
[`kernel/rocknix/source-kernel-parity.tsv`](kernel/rocknix/source-kernel-parity.tsv):
unmodified ROCKNIX 7.0.11 source and all modules, a shipping-identical DTB, the
source-built H700 joypad module, the exact official embedded initramfs and the
accepted current SYSTEM with only its module subtree replaced. The ordinary
canonical path remains `stock`; the candidate requires
`--source-kernel-parity`; release `v6.23-20260811-011242` passed its separate
RG34XX-SP gate and is now the source-built baseline for Stage 9.

The first Stage 9 candidate is separately bound by
[`kernel/rocknix/source-kernel-builtin-input.tsv`](kernel/rocknix/source-kernel-builtin-input.tsv).
It links the exact pinned RG34XX-SP joypad driver into the kernel Image, retains
the unchanged external module only as a build oracle, and omits that duplicate
module from the early overlay. The explicit production flag is
`--builtin-input-kernel`; it does not alter the accepted Stage 8 authority.
The candidate kernel and SYSTEM reproduced byte-for-byte in independent builds;
the Image size is unchanged and the external early overlay is 11,683 compressed
bytes smaller. These are host artifact results, not a hardware timing claim.
Immutable release `v6.23-20260811-030650` passed the broad device gate and is
now the accepted built-in-input baseline. A subsequent button-only candidate,
immutable release `v6.23-20260811-034244`, incorrectly treated the four analog
axes as unpopulated and stopped sampling them. Physical testing proved the
RG34XX-SP has two working sticks; that candidate is rejected and its build mode
has been removed. Corrective release `v6.23-20260811-050010` restored the
accepted built-in driver, axis capabilities and ADC sampling and passed the
broad hardware gate. Release `v6.23-20260811-071550` then preserved every ADC
path while collapsing each GPIO button's immediate error-check/value double
read to one read; its broad hardware gate passed with normal stopwatch timing.
Release `v6.23-20260811-093148` then retained every sample while publishing axes
plus buttons in one combined input frame per poll instead of two successive
frames. Its broad gate passed with normal sub-three-second stopwatch timing.
Release `v6.23-20260811-100937` preserved the 10 ms sampling cadence but
suppressed the combined frame when Linux accepted no changed control value.
Its broad gate passed with normal sub-three-second stopwatch timing. Release
`v6.23-20260811-220044` added direct non-sleeping access for fixed H700 PIO
buttons and one initial input frame on open/reconnect; its broad physical gate
passed while retaining the same DTB, four stick samples, identity, capabilities
and rumble.

Release `v6.23-20260811-234132` completed that move: all 17 digital controls,
including L3/R3, use H700 GPIO edge interrupts with independent 5 ms per-key
debounce, while only the four ADC axes remain on the 10 ms poll. The full input,
rumble, auxiliary-control and broad behavior gate passed. Latency and energy
remain unmeasured rather than inferred from the functional pass.

The previous cold path reused the proven off-to-on resume strike because Linux
backlight takeover had not yet been shown to illuminate the panel reliably
without it. The final Stage 9 path instead stores the rounded ten-percent
cold-start level (raw 250 of 2499) before clearing Linux's inherited backlight
blank. Cold boot therefore has one brightness write, no timed strike and no
restore; the proven 50 ms strike remains limited to suspend/resume. Returned
RG34XX-SP boots showed the Bird menu without a black interval or flash. The
instrumented pair was descriptively about 50--55 ms earlier than the preceding
cold-strike boots; it does not establish a wider timing distribution. Canonical
release `v6.23-20260814-201218` includes this path and passed its separate broad
RG34XX-SP gate, so Stage 9 is accepted rather than remaining mutable
`dev-current` work.

Stage 10 has completed its first candidate's non-deploying host gate. Two
isolated baseline builds reproduce the 621,049-byte shipping DDR4 U-Boot
exactly at SHA-256
`42c01f4524b45cba7c239cd940fc4e71eed7545901da201f27fed2193b7fdf45`,
and two isolated constant-green builds are byte-identical at SHA-256
`080ae5fde3476addb5aa74f03a021aa4fbaa5deccb0964227c0fc91fe657b584`.
The reviewed candidate changes exactly one combined-artifact byte, at offset
488836, for the fixed GPIO 267/PI11 red to GPIO 268/PI12 green selection. Its
U-Boot payload SHA-256 is
`c60605e6a533404d5eb66549e4905152c42ff937de8cc922a1b8b8b7eac3ff56`,
and its exact expected 16 MiB prefix SHA-256 is
`fe363dd09e40ccef994912c01ed1c77d3285485299a40ce7ae7fc74431b5a998`.
Independent artifact, installer and exact-baseline-recovery host audits passed,
so the bounded installer is no longer blocked on pending identities.

The candidate keeps the shipping assertion point and constant-on policy. Its
first physical installation attempt exposed a macOS raw-device contract: the
621,049-byte logical payload left a partial final 512-byte sector, so `gdd`
returned `EINVAL`; Disk Arbitration then remounted the card before the old
cleanup path could reopen it. No boot was attempted; the explicit baseline
repair therefore passed before the corrected installation. The corrected installer
writes 621,056 sector-aligned bytes, preserving the seven-byte tail from the
verified prefix, forcibly re-unmounts before recovery, and its host fixture now
rejects the former write shape. The returned card passed broad functionality
but did not pass the intended constant-green gate: the visible red-then-green
sequence was unchanged. No timing or power improvement is inferred from the
host parity or functional pass. The reason is now explicit: the first candidate
initializes only PI12/green in full U-Boot; it neither runs the LED framework in SPL nor owns a
second PI11/red-off entry. The next isolated candidate uses U-Boot's existing
`CONFIG_SPL_DRIVERS_MISC` hook with green-on plus red-off entries. It may shorten
the red interval to the earliest supported SPL hook, but H616 documents PI11
and PI12 as high-impedance at reset. StockOS and muOS nevertheless establish
green earlier through an unavailable boot-chain implementation. After more
than twelve hours without reproducing it, green-at-power work is deferred
unless another boot task reveals the missing owner. Its exact source transform and focused host gate
pass. One non-deploying build keeps the fixed 40,960-byte SPL region valid with
3,685 trailing zero bytes: the two-entry LED framework consumes 392 bytes of
the former SPL reserve and grows full U-Boot by 24 bytes. A second isolated
build is byte-identical (combined SHA-256
`ac55433c1b39363b6665d3de0bb949f25ee067a7863ac149fc07b885e14b5c82`;
SPL SHA-256
`c9e0982fb0aaced7ef658bd8c89a822009e9e3b1bb570720ba8ac4e6e125c8a0`),
and its exact component, config and prefix identities are now sealed as
installer authority. The successor remains undeployed with green-at-power work
deferred. The installer writes 1,214 complete sectors, verifies the resulting
16 MiB prefix, and restores the prior reviewed green prefix on a failed
transaction; explicit baseline repair also clears the successor's extra
24-byte logical tail. The launcher green-off handoff is deferred with the LED
work. Generic U-Boot provides a persistent FAT environment so users and board
integrations can change boot settings without rebuilding; birdOS instead owns
one immutable compiled policy and has no `uboot.env`. Removing that unused
backend passed the broad RG34XX-SP functional gate with the stopwatch still
below three seconds:
two builds are byte-identical at combined SHA-256
`970b5c485b0468e60c894ed39a0fbf786a3633d92e852a1f4005091b40d887e7`,
with exact unchanged SPL/control DTB and full-prefix SHA-256
`eceb7bcf3f8831b7a7cbb90859ea47bdf67c0cf87650a17977e225c4a43a54f2`.
It derives directly from the physically identified shipping baseline and
contains no LED change.
It retains MMC, FAT, extlinux and compiled boot defaults while removing only
the always-missing `uboot.env` backend. The host-only
exact-baseline repair gate recovers partial or unknown U-Boot bytes, rejects
drift outside that exact range and converges after injected write/readback
failure without adding an alternate card boot path or persistent recovery
state. This accepts the subtraction functionally but makes no timing claim.

Why the next path existed before: generic U-Boot distro boot searches bootable
partitions, filesystem types, `/` and `/boot`, then carries FEL/PXE/DHCP
fallback targets for variable media. birdOS always boots extlinux from MMC0
partition 1. The accepted direct-extlinux boundary keeps MMC initialization and
the same extlinux parser but executes the fixed sysboot command directly. Two
builds are
byte-identical at combined SHA-256
`cd99dd9edaad868e460b256729c2e0f5a20a606a2a33e4015d93c42159da1191`;
the deterministic 16 MiB prefix is
`f81187878bbe491dabaf1a4f5fda051d4edabbcb476681d1323d73557e3072ff`.
The bounded installer and no-op transaction gates pass. The device then passed
the broad functional matrix at about 2.6 seconds by the user's stopwatch. Recent
interactive-frame records are descriptively several milliseconds earlier, but
do not isolate or calibrate U-Boot time. The direct-extlinux boundary is now
physically accepted.

Why the previous implementation existed: generic U-Boot clears its malloc
arena so callers across many supported boards begin with zeroed memory. The
strongest remaining executed cost is that full-U-Boot heap setup:
`initr_malloc()` clears the entire `0x4020000`-byte (64.125 MiB) arena before
MMC and kernel loading. U-Boot labels this policy slow and recommends disabling
it for heaps larger than a few MiB. The accepted intermediate boundary stops
that full-U-Boot clear while retaining the arena size and the SPL policy. Its two
isolated builds are byte-identical at 620,745 bytes and SHA-256
`38ace6d738fed727fdd2274b510c3e18105b2c71f7b1d908dece357e31d1365c`;
the exact resulting prefix SHA-256 is
`ea1afbf3186945e562aa0844d7ab6d1b027be9cfafe225a0e4c0745ffc50b305`.
Its reviewed authority also pins the 579,785-byte FIT at
`991d29c7201afceea7e18e5bc03707c8308306ba2cf67f16a1d48f95c2d14a7b`
and the 500,936-byte full-U-Boot payload at
`d1ad2598283dac0913c5d49c5d3ccec7b21f9b14226038561c7334afff48fba4`.
The exact config, component, no-op and failure-restoration host gates pass. Its
physical installation completed the exact 16 MiB prefix readback and supplied
the required predecessor for the succeeding fast-init installation. The
returned broad device gate passed. This accepts removal of the 67,239,936-byte
clear as an intermediate transaction boundary, not as a separately measured
hardware timing improvement.

Why the removed generic behavior existed before: U-Boot supports interactive
autoboot interruption, filesystem and target discovery, an explicit MMC
selection command, network targets and boot-standard discovery. birdOS has one
fixed FAT boot partition and no boot-time network or bootflow search. The
physically accepted fast-init boundary fixes FAT explicitly, removes the
unnecessary `mmc dev` wrapper and UART abort check, uses boot delay `-2`, and
builds neither the network stack nor bootstd. The architecture-selected preboot
facility remains with an empty compiled hook. Its resolved GCC config delta has
42 symbols and produces two byte-identical 556,977-byte combined artifacts at
`4afc68bd2a7fdaacc212683a1a268380c07775d18cf12025285778221e986081`.
The 516,017-byte FIT is
`d827586fefa78cc12dba89b3912f1a428b5218415c62dc8308c24a252a0eaea9`,
the 437,168-byte full-U-Boot payload is
`9d557ccc6efb40b4e4f3daeea648f51ae313d6bec9c342d41abf4b8fdefbeb89`,
and its exact 16 MiB prefix is
`172ca1a500603ea371a17bee1b6a7632ba17e4991a400f57cee0b2231e75bdeb`.
It is 63,768 bytes (10.27 percent) smaller than no-heap-clear, with exact
unchanged SPL, TF-A and control DTB. No-heap-clear followed by fast-init passed
the combined RG34XX-SP gate while retaining both independently asserted
transaction authorities. The installer reread and matched the complete pinned
fast-init prefix before its successful remount; three subsequent boots reached
the direct launcher and the returned broad functional matrix passed. A fresh
raw reread is unavailable because the host sudo lease expired, so acceptance is
bound to that install-time exact verification and the post-install boot
evidence. Fast-init became the physically accepted predecessor for the next
boundary. The user did not report a new stopwatch result for this return, so no
hardware
timing improvement is claimed. Green-at-power work remains deferred unless
another boot task reveals its earlier owner.

Why the previous behavior existed: U-Boot relocates the initramfs and device
tree so unknown boards, load addresses and payload sizes receive fresh safely
allocated handoff ranges. Why change it: birdOS has one RG34XX-SP layout, and its
accepted extlinux path already loads the exact 603,487-byte initramfs at
`0x4ff00000` and the exact 49,010-byte DTB at `0x4fa00000`, with U-Boot's
12,288-byte DTB pad and every later fixed buffer proven non-overlapping. The
physically accepted in-place-handoff boundary compiles
`initrd_high=ffffffffffffffff` and `fdt_high=ffffffffffffffff` through the
board-scoped `bird-rg34xx-sp-handoff.env`; the only resolved config delta from
accepted fast-init is `CONFIG_ENV_SOURCE_FILE=""` to
`"bird-rg34xx-sp-handoff"`. The transformed defconfig is
`0254301f87e2222f04c67a34e5351bce16ebaac712bd96cc096f76027d9ded13`,
and the 55-byte environment is
`335b569a6f63acab13d20bccb843b5d6d979b7141ede3a5a5a2647b59ec132ce`.
Two builds reproduce the 556,977-byte combined artifact at
`7423ffeda197645b6b774c83fcebcbefef47bd7eaa6f087c71ab339750af4e91`,
the 516,017-byte FIT at
`c11d9b780c4c78940590ee17965550aa3eca7e7d0d04fdb37b4c9869b2418bf4`,
the 437,168-byte full-U-Boot payload at
`cff9a9ca1bd7db20a3a136fec655d7120481afa8a837930266a9962ab2dec578`,
the 47,408-byte resolved config at
`77f2bee66adc542e3475594c4727933607f76c2adf72e6428e0e57cadb6de762`,
and the exact 16 MiB prefix at
`c168640be0e3b0fc3899853d71aabc0c3b3e65fdf230b19782ff40ff19f001dd`.
The SPL (`0bef5378bc25e4597512fc302f90fa6afe994e3eff09a7a6d16fc3e95b95f26c`),
BL31 (`431009313966f9a6579ae5741976c15082071b387a3da82a8dee985383e97673`)
and control DTB
(`ba3a4f905c893dcc19bd8020990c485576f8911cef97555f04843e3423d4c589`)
remain byte-identical to fast-init. This models removal of one 603,487-byte
initramfs move plus a 61,298-byte padded-DTB move, or 664,785 bytes total; it is
not a hardware timing claim. Its bounded installer completed the exact
post-write authority check, and two returned RG34XX-SP cycles passed the broad
functional matrix. Canonical release `v6.23-20260814-201218`, built from clean
commit `5373c644b9c91ac21a17e145375747a8196a3337` with manifest digest
`904c8da42a6ec84ccf4b291205999c3b0e25900f4bec7bb3f9e0cfefb29164dd`,
then passed the complete returned behavior gate. Its four cold-boot records put
the usable frame at 1174, 1175, 1176 and 1177 ms, a midpoint median of 1175.5 ms
reported as about 1176 ms; input-ready median is 1170 ms. Three completed
asynchronous storage records have a 3514 ms median, while the fourth boot shut
down before storage readiness. That three-sample storage result is noise-scale.
The 2.8--2.9-second stopwatch result likewise shows no measurable improvement;
storage remains outside the usable-frame contract.

Why before: the retained ROCKNIX fake-suspend
provider owns the accepted audio, input, governor, core-parking and LED
transaction, while Bird restores the fixed panel and records rare transition
edges with `O_DSYNC` without adding an idle wakeup. Why change: no suspend
behavior is changed in this cycle because canonical boot `96df160e` preserved
a power suspend at 311.471 seconds and resume dispatch at 312.632 seconds but no
resume-complete, timeout,
orderly shutdown, panic, Oops, pstore or reset-cause record before the next
boot. Boot `a245d090` then completed three power/lid cycles with resume
completion 726--768 ms after the wake edge. The evidence narrows a future
focused investigation to the retained provider, PMIC/button and reset-surviving
diagnostics, but does not justify changing the accepted suspend path during
Stage 10.

In-place handoff plus the reviewed LZ4 bound remains the active physically
accepted U-Boot/kernel pair. Stage 10 is roughly 94 percent complete: five
accepted U-Boot transitions, the clean canonical prerequisite, raw-kernel
bootstage measurement and corrected uninstrumented LZ4 development-device gate
are complete. The reviewed simple-parser successor and bounded installer also
passed their hardware gate. Deeper subsystem pruning and the inherited-frame
experiment remain.

Why the previous measurement boundary existed: source inspection treated
generic bootm's `bootm_load_os` mark as the kernel-load boundary. The accepted
device trace proved that `booti` performs `BOOTM_STATE_LOADOS` itself and never
emits that mark. Why change it: the capture contract now requires the actually
emitted `boot_jump_linux` mark. Together with `bootm_start`, it bounds booti
setup/decompression and the remaining handoff without custom timing. Capture
requires one increasing mark for `board_init_f`, `board_init_r`, `main_loop`,
`bootm_start`, `boot_jump_linux` and `start_kernel`; incomplete or ambiguous
records fail closed and capture never enters first-frame work. `start_kernel`
means handoff-start before U-Boot's final cleanup. Why the first
two-pass builder stopped: `SPL_BOOTSTAGE=n` disabled SPL recording, but raw
`CONFIG_BOOTSTAGE` still added `gd->bootstage` and shifted the following
`cyclic_list`, so the generated SPL was no longer the accepted byte sequence.
Why change it: the host-reviewed measurement-only artifact packages the exact
accepted 40,960-byte SPL, retains the reproducible different generated SPL as
explicitly unused evidence, and changes only full-U-Boot data in the FIT. Its
561,073-byte combined image is
`0b22418db35ee591870ccd652d4aaa3d0a50bd216e600f7b8ca0c4052e2e8e83`;
the reconstructed 16 MiB prefix is
`c1dadb6b43782ac25b8be6ea168cbad7c2e435da49207210213be68701f7f94b`.
Both passes are byte-identical, and the 4,096-byte host size increase is not a
timing claim. Its artifact authority remains measurement-only and grants no
production-successor deployment. Why change the former no-write boundary: a
separately pinned `temporary-measurement-only` installer now accepts only the
exact in-place prefix plus canonical `v6.23-20260814-201218`, requires the
post-frame capture request to be armed, and has a direct exact in-place restore.
Its full sector-tail, forced-unmount and failure-recovery host gates pass. Three
returned traces preserved the actual emitted records. Their median phase times
were 602,524 us from reset to `board_init_f`, 304,745 us to `board_init_r`,
76,759 us to `main_loop`, 1,419,998 us from `main_loop` to `bootm_start`, and
224,968 us from `bootm_start` to `boot_jump_linux`. The seven human stopwatch
samples had a coarse 2.78-second median and all behavior passed. This is enough
to prioritize the LZ4 functional gate; it is not a calibrated total-boot
claim. Why the raw kernel existed:
it is the physically accepted, simplest
handoff and avoids
both a U-Boot decompression stage and its temporary output buffer. Why consider
changing it: the fixed 30,926,856-byte Image becomes a 17,565,707-byte LZ4
frame, leaving 13,361,149 fewer kernel payload bytes (43.2024 percent) to load before
accounting for decompression. The separate host-ready frame is at
`a7321d2a79b18e81f114aefd9bb7509ba70d5e56b562a345ea5ca66dbf11262a`,
but is likewise full-release-only until paired U-Boot sets
`kernel_comp_size=0x10c080b` and the resulting release passes its hardware
timing gate. These are host byte counts, not a device timing claim.
Two fresh isolated linked passes are byte-identical at combined SHA-256
`9f3d96da4126a6654187a3cddb9b0c038b251882aee9938e0b258d0bac94f35b`
and full-U-Boot SHA-256
`35cd4f8d50568f7bdae89fe01ce851b80276c4a44c18138de553872456523f9e`.
The config, SPL and control DTB remain accepted bytes; only four compiled
environment bytes change, FIT scope is U-Boot data only, and the exact guard
ends 19,378,066 bytes before the DTB. The derived prefix is
`2e6680950a885cef607a9642c0133a8794d7407c7879ccb0fe9c153b6be45f56`.
The two-pass pair is now sealed as reviewed production-successor authority.
Its bounded installer accepts only the exact in-place predecessor, verifies the
complete target prefix, and retains direct exact in-place recovery.

Why the two authorities remained separate: the linked LZ4 proof isolated the
four-byte bound while the accepted bootstage image preserved the exact timing
instrumentation. Why change: a new paired measurement authority independently
applies that proven equal-length delta to both reviewed bootstage A/B payloads.
They converge on a 561,073-byte image at SHA-256
`d386f00ee8b0db002f5de3206d4af522a33a0f26960efe0561b29e01dbf2a083`,
with full-U-Boot SHA-256
`57232f25c04da2fb8bac08f4c5f5be6af6d1da069b32e0bb50baaebff4219fe3`
and derived 16 MiB prefix
`cf13ad801ffc3a2c1b1e65879f72a683cebe29e476c7dfde7d0c136eeb54d2ee`.
The exact accepted SPL, config and control DT remain unchanged; FIT scope is
U-Boot data only. The 79-case workflow gate and focused release-builder gates
pass. The temporary instrumented pair remains nondeployable historical
evidence. The next boundary is installation of the reviewed uninstrumented
pair followed by the clean immutable LZ4 release.

Why the measurement path is now retired: bootstage existed to decide whether a
large next optimization was worth testing, and its returned records answered
that question. Why change: no further formal stopwatch or instrumented LZ4 A/B
is required. The next canonical runtime removes the bootstage capture helper,
the diagnostic U-Boot returns to exact accepted in-place handoff, and the
uninstrumented LZ4 pair advances on its exact authority plus a broad functional
RG34XX-SP gate. The retained raw traces remain engineering evidence; no
measurement code becomes part of accepted U-Boot.

The reviewed uninstrumented pair and immutable LZ4 release
`v6.23-20260826-194408` were installed from clean commit `15144a9`. Why before:
the existing `storage-failed` recovery waited for the early launcher to exit,
which assumed a shutdown or content action could always complete. The returned
gate disproved that assumption: the menu remained visible without usable
storage, content could not launch, shutdown could not reach its owner, and no
durable root-cause record survived. Why change: a permanent 30-second
initramfs-owned storage watchdog now starts immediately before the launcher and
outside launcher/systemd ownership. Only the verified post-`prepare_sysroot`
storage-anchor acknowledgement disarms it. On timeout it records uptime,
cmdline, mounts, partitions, modules, storage paths, readiness nodes, processes,
the mount-storage record, early-launcher output and dmesg, synchronizes through
a three-second final countdown, and forces poweroff. It retains an open p6 log
when available and otherwise writes one bounded top-level BIRD diagnostic.
Healthy boots disarm before persistent logging and remove any pending record.
This is a recovery/evidence gate, not a speculative storage fix; the next card
boot must provide the captured boundary before changing storage sequencing.

That boundary was strict release verification rather than an LZ4 timing race:
the valid LZ4 source-kernel provenance was absent from the exact optional-input
allowlist. Corrected `dev-current` source `f22e2b8` verified, published a
1.178-second usable frame, anchored storage at 3.388 seconds, disarmed the
watchdog and passed the broad charged-device screen. The observed 90-second
cutoff reported battery 0 percent, discharging, left no Bird shutdown/suspend
record and disappeared after charging.

Why the next generic path existed: sunxi implies distro defaults for an
interactive multi-command U-Boot. Why change: Bird executes one uninterruptible
`sysboot` command. The first formal sparse-policy build correctly stopped when
disabling distro defaults also removed boot dependencies that the feasibility
command had reselected transiently. The policy now records the exact retained
MMC/FAT/extlinux/LZ4/`booti` closure explicitly. Two fresh isolated builds are
byte-identical and reproduce the feasibility bytes while
removing hush, editing, completion, tracing and long help. Their combined
artifact is 518,369 bytes versus the
accepted pair's 556,977, a 38,608-byte (6.93 percent) reduction. Full U-Boot is
398,560 versus 437,168 bytes, an 8.83 percent reduction. SPL and control DTB are
byte-identical and FIT changes are limited to U-Boot data. No device timing or
deployment timing claim is made. The self-verifying authority pins the exact
candidate and predecessor prefixes. Its bounded installer accepts only the
reviewed LZ4 pair, writes 1,013 complete sectors, preserves the 287-byte final
sector tail from the verified prefix, verifies the complete 16 MiB result and
provides exact LZ4 recovery. The full destructive-path simulator passes; no
card write had occurred at that boundary. The exact candidate was then
installed with complete-prefix verification. Returned boot `07d80b9c` exercised
games, PSP, native Ports, PortMaster, music, books, video, favorites/return
state, networking, a complete suspend/resume, orderly shutdown/config save and
Input Tester 29/29. Its detailed supervisor, content, suspend, shutdown,
network and input records survived. No comparable initial usable-frame record
survived, so this gate makes no hardware timing claim.

The corrected source-kernel package reached Bird's early usable menu but not
application readiness. A temporary early watchdog proved that release-runtime
verification rejected the otherwise valid source-parity manifest because the
initramfs parser required exactly fourteen external inputs while source parity
adds its fifteenth authority record. The verifier now accepts only the exact
fourteen stock inputs plus that one optional, unique source-kernel authority;
unknown, missing and duplicate inputs still fail closed. The diagnostic
watchdog was removed after acquiring this evidence.

Clean `dev-current` source `741a997955e3463149b340e56e10d905b2d0ec98`
then passed the broad RG34XX-SP application and hardware matrix on the source
kernel. Two returned boots recorded input/usable readiness at 1219/1222 ms and
1230/1232 ms, with storage anchored at 3475 and 3430 ms. Games, native Ports,
music, books, movies, PortMaster, controls, suspend and shutdown reached their
normal owners. The two early DRM property warnings also occur in retained stock
kernel evidence and are not a source-build regression. This closes functional
and boot screening, not canonical source-baseline promotion.

The requested 30-second-settled, 60-second short-label menu-idle sample also
passed structural parity. The two D-pad edges at 3.7 and 4.5 seconds preceded
the settle boundary and are excluded. Aggregate busy time was 0.285 percent
versus the accepted stock window's 0.289 percent; context switches and total
interrupts were within 0.6 and 0.8 percent, and arch-timer interrupts were
within 2.2 percent. ADC remained 300.1/s. Launcher, supervisor, PipeWire,
PulseAudio, WirePlumber and seatd accumulated no runtime or timeslices;
powerstate accumulated 0.876 ms and eight timeslices versus stock's 0.868 ms
and eight. Launcher PSS/USS was 1832/1824 KiB versus stock's 1776/1772 KiB,
while the warm audio stack was 20,600 KiB versus 20,898 KiB and seatd remained
263 KiB. These are non-inferior structural and memory screening results, not a
calibrated energy claim. Stage 8 may now proceed to the all-local host gate and
canonical immutable source-kernel build before its final physical acceptance.

## Build and deployment

Supported birdOS-owned local changes use
`./dev-build-and-deploy.sh --changed` during iteration. The one mutable
`dev-current` release is derived from a verified immutable production release,
is rebuilt only through its complete manifest, and is never an accepted
release, production rollback, previous selector or archive target.
`./dev-build-and-deploy.sh --all-local` is the complete local rebuild and
host-test gate before the final development-device physical gate. A passing
development gate still does not confer production acceptance.

Canonical production deployment requires
`./dev-build-and-deploy.sh --clean` first and fails closed if `dev-current` or
its `/flash/bird-dev` metadata remains. If malformed metadata prevents ordinary
rollback while `dev-current` is selected,
`./dev-build-and-deploy.sh --recover-production` restores only the separately
saved, fully verified production selector and preserves the damaged metadata
for diagnosis. `./dev-build-and-deploy.sh --clean-recovered` then verifies that
exact selector without parsing the damaged state and removes only the reserved
development release, attempts, metadata, and stale `.dev-current.new.*` copy
stages. Before deleting anything, both cleanup modes publish the strict
top-level `bird-dev-cleanup.tsv` authority containing the exact production
selector, production manifest digest, and fallback/recovery byte identities.
It survives partial metadata deletion and is removed only after cleanup and
production invariants verify. Production refuses that authority, interrupted
`.bird-dev-cleanup.tsv.dev-new.*` publications, and hidden copy stages until
`--recover-production` plus `--clean-recovered` completes. The complete
workflow and its supported/full-release boundary are authoritative in
[`DEV_WORKFLOW.md`](DEV_WORKFLOW.md).

The fast path is now in stabilization. Do not add recovery states or safety
machinery for hypothetical residue. Use `--changed` and `--all-local`, record
actual duration, rebuild scope, output clarity, rollback/cleanup friction and
observed failures, and change hardening only from that evidence or a direct
production/data-loss risk. The current bounded exceptions are ordinary-path
truthfulness and false-rebuild fixes.

Committed changes to the production builder or updater cannot be validated by
deriving `dev-current` from an older production manifest: the first development
build intentionally stops before card writes until a clean canonical release
from the current commit or a descendant has passed its own RG34XX-SP gate.
Release `v6.23-20260814-201218`, built from
`5373c644b9c91ac21a17e145375747a8196a3337` with deploy-manifest digest
`904c8da42a6ec84ccf4b291205999c3b0e25900f4bec7bb3f9e0cfefb29164dd`, passed
that gate and is the current eligible `dev-current` base. A later committed
full-release-only change creates
a new transition; the workflow does not add mandatory promotion-record
machinery during stabilization.

The first real `--all-local` exercise reached its actual-output capacity gate
after 716.01 seconds of host build and required tests. It needed 37,617,684
bytes with 30,601,728 available and stopped before card mutation; production
selection, release bytes and recovery assets remained unchanged, with no
development release or metadata published. The attempted 128-to-138 MiB remedy
then failed before unmount or raw write because the privileged raw-read
temporary was unreadable by the following unprivileged comparison. The card
remained on its original 128 MiB p1, and the migration path is retired.

The adopted correction treats the card as execution media, not release-history
storage. Canonical deployment retains one immutable base, archives and
independently verifies every superseded immutable release in the private GitHub
archive, makes `extlinux.previous.conf` self-reference the activated base, and
only then removes the verified old card directory. The freed rotating slot
belongs to `dev-current`. The fixed top-level v5.4 fallback stays
temporarily because deleting it requires a separate boot-contract rewrite; it
is not normal production history or development rollback. A failed boot returns
the card to the host for verified selector restoration or redeployment. This
storage-policy correction makes no boot, interaction, energy, memory or Stage 6
performance claim.

The normal macOS entry point is `./build-and-deploy.sh --release`, or
`./build-and-deploy.sh --profile` for lightweight launcher counters. It chooses
one release ID before the build, passes that ID to both canonical scripts and
selects a fresh timestamped ID whenever the preferred immutable directory or
archived GitHub release tag is already occupied. `--release-id ID` chooses a
different preferred ID and `--dry-run` performs the read-only preflight only.

1. `build-stock-root-compat.sh` validates the pinned upstream inputs and the
   exact upstream files it consumes.
2. It compiles the final-root launcher, PID waiter, controls worker and power
   worker, generates the reduced autostart coordinator, and invokes the early
   overlay builder.
3. It assembles a complete release card tree and emits the canonical
   `deploy-manifest.tsv` only after validating scripts, binaries, units and
   upstream identities.
4. The Mac updater validates the removable-card identity and immutable inputs,
   then stages the complete release in a hidden sibling below
   `/flash/bird-releases/` without modifying the active runtime.
5. It verifies the staged tree against the release manifest, atomically
   renames it to `/flash/bird-releases/<release-id>`, and records the manifest
   digest in that release's `.complete` marker. The previously selected complete
   release remains intact throughout staging, verification and activation. Only
   afterward may the canonical workflow archive and independently verify its
   exact card copy. If the legacy root `KERNEL` has already been
   retired, the build wrapper pins a fully verified installed release as its
   kernel source throughout that transition.
6. The active extlinux entry refers only to its versioned kernel,
   initramfs and DTB paths and passes the matching `bird_release` ID. One verified
   temporary-file rename of `/flash/extlinux/extlinux.conf` is the activation
   point. After old-release archival, `extlinux.previous.conf` self-references
   that same canonical release rather than naming a removed directory. The
   superseded directory is removed only after that selector commit succeeds. The
   separate fixed fallback entry continues to name its preserved top-level
   assets until its own boot-contract rewrite.
7. Legacy same-volume Port layout conversion is an explicit card-data migration
   performed by
   [`firmware/mac-migrate-rocknix-ports.sh`](firmware/mac-migrate-rocknix-ports.sh),
   outside the runtime transaction. The updater refuses a nonempty legacy tree
   or an unverified PortMaster provider, so both conditions must be resolved
   before selector activation without producing a mixed birdOS runtime.

The accepted PortMaster provider is the exact repository-pinned managed
inventory of the official `2026.07.28-1212` tag. Its optional upstream
`pylibs.zip` is accepted only when absent or byte-identical to the recorded
nested archive. Provider-local Python caches are tolerated only because every
PortMaster, Port and KOReader execution redirects Python cache lookup to a fresh
tmpfs prefix and disables bytecode writes; they are never an executable trust
source. The updater may atomically migrate an absent, empty, v1 or v2 checkpoint
after exact verification, but it never rewrites managed provider bytes. A
different v3 checkpoint or unrecognized provider state fails before stale-stage
cleanup or selector mutation.
The full managed-tree verifier runs only during host deployment or a
transactional provider bootstrap. Normal device boots and content launches
validate the exact persistent installation checkpoint, perform bounded
once-per-boot setup, and never rescan or hash the 445 MB provider tree.

The 128 MiB `BIRD` partition intentionally holds only one canonical release
plus `dev-current`. The top-level command never retires the release named by the
active extlinux selector. Before any card write it identifies and completely
verifies the immutable source that the candidate will supersede, confirms the
private immutable GitHub archive is available, and rechecks the temporarily
retained fixed-fallback bytes. It reserves only the measured candidate staging
bytes, including the fixed kernel/DTB margin; it does not reserve a future
development copy.

If a pre-existing inactive immutable release prevents candidate staging, the
guarded space planner first archives, downloads and independently verifies that
inactive release. It then atomically makes the previous selector byte-identical
to the current selected release before removing only the inactive directory. It
never removes the active/build-source release, so a later host-build failure
leaves current and previous self-referencing the complete canonical base. This
is the one-time bootstrap from the old active-plus-previous layout; ordinary
later rotations normally need only the post-activation step below.

The canonical builder and updater then stage, verify and activate the new
release while the old source remains intact. After activation, the wrapper
reacquires the shared card lock, revalidates the card, current release and fixed
fallback, packages the exact superseded bytes, and publishes them as an attested
private GitHub release. It downloads the canonical manifest and archive again,
then verifies every archived path, byte and manifest identity. Archive tar-
header identity is deliberately not authority: directory timestamps can change
tar bytes without changing the canonical release payload.

Only after that independent verification does one atomic selector replacement
make `extlinux.previous.conf` byte-identical to the current canonical selector;
only after that does the wrapper remove the superseded release directory. It
then rechecks current, previous and fixed-fallback identities. A draft or failed
upload leaves the new release active but preserves the complete old release and
its previous selector. GitHub release immutability is required; otherwise card
reclamation is refused.

The builder fixes locale, timezone, umask and generated filesystem metadata,
and it rejects a persistent source-tree change during the build. Repeatability
is tested with the current host toolchain across distinct output paths and host
settings. The Homebrew compiler and archive tools are not yet hermetically
pinned across future upgrades; that stronger cross-host guarantee belongs to
the complete-image work in the roadmap. Release and installed bytes are still
fully content-addressed by the canonical manifest.

The host transaction covers updater process interruption: before the selector
rename, the previous complete runtime remains selected; after a verified
rename, only the complete new release is selected. A partially copied tree is
never a valid activation target. The selector lives on FAT, so this is not a
claim that arbitrary power loss during a FAT metadata update is boot-atomic.
The selected policy handles an unbootable result by returning the card to the
host; it does not add a U-Boot A/B state machine.

### Development-workflow scope record

Commit `036c0423a8f4b491f273eee051289af197c51f6a` introduced the mutable
`dev-current` lifecycle. Its subject mentions host-only transaction tests, but
its actual scope also added the operator entry point and 2,342-line deployment
engine, extracted the shared local binary compiler contract, modified both
canonical final-root and early-initramfs builders, documented the workflow and
added its compiler and transaction suites. This note records that already
published scope without rewriting shared history. The commit did not make
`dev-current` a production or acceptance authority.

## Boot and runtime sequence

1. **Bootloader:** extlinux selects the active release's versioned unchanged
   ROCKNIX kernel and DTB plus its `bird-initramfs.cpio.gz`, and identifies that
   release with the `bird_release` command-line parameter. The accepted
   production entry maps fbcon away from the fixed panel and disables the VT
   cursor without enabling the serial console, so Sway teardown
   cannot clear the launcher-owned framebuffer or expose a console cursor before
   the replacement launcher takes ownership. The previous release selector and
   fixed fallback retain `console=ttyS0,115200` for diagnostics and recovery.
2. **Early overlay:** the overlaid ROCKNIX init calls `bird-early.sh start`
   after the special filesystems exist. It creates the storage event channel,
   loads the exact H700 input module and starts the static framebuffer launcher.
3. **First usable menu:** the launcher installs a `/dev/input` creation watch,
   tries the measured event hint and makes one complete named-input recovery
   scan before inspecting framebuffer recovery. If input is not already
   available, it paints a launcher-owned base with no menu rows, then blocks on
   the watch and validates only newly created numbered event nodes. A queue
   overflow permits a complete rescan; unavailable inotify retains the bounded
   polling fallback. An H700 name match is accepted only when its complete
   input ID and event/key/absolute/force-feedback bitmaps match the generated
   fixed-device contract; the retained legacy mapping remains name-based. The
   launcher also installs a `/dev` watch before probing the one fixed `fb0`
   node, accepts only its create/move events and uses the prior 1 ms polling
   path only when inotify is unavailable. Queue overflow permits one exact
   reprobe. Geometry, stride, format and mapping are still validated before
   use. Only
   after input is open does it paint interactive rows, execute the framebuffer
   barrier and publish first-frame readiness. From that marker,
   every zero-time input poll and complete drain may advance at most one deferred
   profiling, logging, checkpoint, power, storage or Favorites task; input,
   reconnect and exit work always interrupt that sequence. Its cached catalogue
   does not require a boot-time ROM scan. List viewports use fixed nine-row
   pages: movement within a page redraws only the old and new rows plus status,
   while crossing a page boundary redraws the bounded content region. The
   persisted selection deterministically restores its containing page. After
   startup is complete, the one-shot storage FIFO consumes at most one read
   attempt per post-input background slot. Power uevents consume at most eight
   read attempts per slot and coalesce matching records into one sysfs snapshot
   and at most one battery render; any unread tail yields to another complete
   input sample. Generated catalogue access is isolated behind fixed-index
   accessors. The generator rejects duplicate canonical game or media paths and
   emits one game-path order for logarithmic Favorites lookup. Favorites load
   publishes a fixed catalogue-ordered `u16` member index in one bounded bitmap
   pass, independent of file order; browsing and saving then touch only the
   requested ordinal or the actual member count, while the persistent file
   remains exact-path based and reorder-compatible. The generated catalogue
   stores exact UTF-8 strings once in an immutable NUL-terminated pool and
   represents every logical record with naturally aligned `u32` pool offsets,
   `u32` ranges and `u8` identities. Accessors return stable pointers directly
   into that pool, so rendering and handoff do no runtime decoding or path
   reconstruction and the launcher carries no catalogue pointer-relocation
   table.
4. **Stock-root preparation:** the selected initramfs uses its immutable
   `bird-release-loader.sh`, not the mutable top-level compatibility hook. The
   loader requires the exact `bird_release` selector, validates the complete
   release and its manifest-listed versioned `post-flash.sh`, then sources that
   hook. The hook transactionally records the boot attempt, revalidates every
   runtime file it will expose, binds the release's `mount-storage.sh` and
   `bird/` tree over the fixed boot targets, mounts p6 and binds the pinned
   `SYSTEM` image into ROCKNIX's normal handoff. Once those exact binds and the
   launcher's honest input-open framebuffer barrier both exist, the hook
   transactionally commits that release's boot health. A later user refresh or
   reboot from an already-usable menu is therefore never charged as a failed
   full-stack attempt. Previous initramfs images keep
   their original top-level hook, so changing the extlinux selector is the only
   runtime activation boundary. The selected mount helper then publishes the
   fixed ROM/BIOS view. The replacement launcher now executes from the selected
   immutable `/flash/bird` tree and is neither copied nor rewritten on p6.
   Remaining compatibility files copied into the writable storage image have
   their exact modes repaired by the pinned BusyBox in the already-mounted
   SYSTEM tree; the smaller initramfs BusyBox intentionally has no `chmod`
   applet. Init checks the selected mount helper's result explicitly. A failed
   storage transaction leaves the interactive early launcher in control and
   records `mount-storage-latest.log` on p6 instead of continuing into a
   partially configured stock frontend.
5. **Persistent launcher ownership:** after `prepare_sysroot` establishes the
   final tree, init signals the early launcher. The launcher retains exact
   storage and configuration descriptors and acknowledges them before special
   mounts move. The same process remains the input owner across `switch_root`.
6. **Final-root supervision:** systemd starts the stable birdOS supervisor at
   the graphical boundary. It adopts the early launcher through the PID waiter
   or starts a replacement directly from `/flash/bird/bird-launcher` when
   adoption is unavailable. Launcher health races
   first-frame readiness against child exit and uses bounded local recovery for
   recoverable startup failures. A usable early launcher may complete an
   authoritative content, shutdown or PortMaster handoff before
   the supervisor exists. In that case only the conjunction of
   the fresh interactive-frame
   marker and an exact atomically published action is accepted as boot health;
   the release-scoped attempt reset must become durable before the action is
   consumed. A failed reset leaves the action intact for a supervisor retry.
7. **Application contract:** retained ROCKNIX setup continues asynchronously.
   Its final export publishes a revisioned ready marker only after every
   required profile and link is validated. A queued selection remains intact
   when that contract cannot be completed.
8. **Content session:** `run-content.sh` maps the cached content identity to the
   pinned ROCKNIX provider, joins only the services needed by that selection
   and places the complete foreground tree inside one enforceable session
   boundary. Normal return and the global exit chord both terminate and reap
   the entire boundary before the launcher resumes. Before a content or
   PortMaster handoff, the launcher first commits authoritative UI state and
   may atomically publish a volatile descriptor bound to the exact visible RGB
   pixels of the measured one-page XRGB8888 framebuffer plus the displayed
   battery and Favorites state. An independent descriptor digest protects that
   snapshot from accidental corruption. The unused X byte is fingerprinted only
   for diagnostics because the measured format declares no transparency bits
   and DRM/fbdev ownership changes may normalize that non-visible byte. A
   replacement launcher preserves the frame only when input was already
   reopened and the exact format, UI state and all visible RGB pixels match; it
   then updates only the return-status region. A sealed descriptor with changed
   visible RGB still restores the exact Favorites and displayed-power snapshot
   before the normal full-render fallback. Missing, stale, dirty, corrupt,
   UI-mismatched or unsupported state takes the full-render path without trusting
   snapshot data. The descriptor lives only in `/run`, cannot authorize a
   content launch and is cleared after startup or any failed handoff.
   Returned hardware evidence on `v6.23-framebuffer-watch-84a2435` exercised
   this path: the replacement launcher started at 32033 ms, reopened H700 input
   at 32034 ms and published at 32091 ms with `render=recovery`, a restored
   snapshot, zero visible-region mismatches, stable unused X bytes and exact
   matching bound hashes.
9. **Fixed controls and power:** the separate controls and power workers own
   system volume, brightness, lid/power suspend and the low-battery LED policy.
   The kernel/PMIC owns charging state; the launcher only observes and displays
   it. The controls worker installs a persistent `/dev/input` watch before one
   bounded name scan, validates the exact H700 contract, and thereafter inspects
   only created nodes; reconnect or overflow permits one recovery scan. Its
   250 ms discovery timer exists only when inotify is unavailable. These
   responsibilities are not linked into the launcher. Before systemd starts,
   root preparation canonicalizes `system.suspendmode=off`, installs generated
   no-real-suspend and no-logind-input policy, and removes every competing
   `*.conf` drop-in before PID 1 starts. It also seeds either missing RetroArch
   configuration prerequisite individually, preventing retained
   `chksysconfig` recovery from restoring the complete stock configuration over
   Bird-owned policy. The generic H700 writers remain disabled; a fixed
   common/009 verifier runs after retained common/001 recovery and repairs mode
   or sleep-policy drift without writing on an accepted ordinary boot. This
   prevents split ownership with the H700 real-suspend
   path that the retained provider explicitly does not support. The persistent
   controls process continues to own the retained ROCKNIX resume transaction
   from the first accepted wake request until the wrapper explicitly reports
   core restoration, provider cleanup and Bird brightness restoration. During
   that interval it preserves at most one cancellable power or lid-close intent
   and never starts an overlapping helper.
   Optional networking is released only for direct PortMaster.
10. **Shutdown:** systemd retains ordered shutdown. The birdOS configuration
    checkpoint is an atomic, verified transaction and reports failure instead
    of publishing a false successful checkpoint. The supervisor bounds only the
    nonblocking systemd client to three seconds and resumes the launcher if the
    request was not accepted; accepted requests continue through ordinary
    ordered systemd shutdown. The real p6 data mount lives at `/run/bird-data`,
    outside the `/storage` loop filesystem backed by a file on p6. A bind alias
    publishes it at `/storage/bird-data`, permitting shutdown to unmount nested
    aliases, then the loop filesystem, and finally p6 without a mount/backing-
    filesystem cycle. The next boot archives the prior shutdown trace before a
    later request can overwrite it.

The two returned cold boots for the current framebuffer candidate recorded
launcher-start/input-ready/usable-frame values of 1221/1221/1224 ms and
1222/1223/1227 ms. The preceding release's three usable-frame observations
were 1226, 1229 and 1227 ms. The functional screen passed and no framebuffer
error appeared, but the late-registration inotify branch was not explicitly
instrumented on those boots. These values establish behavioral
non-regression, not a measured boot improvement. One lid-suspend attempt ended
in a reboot with an incomplete retained suspend trace; its cause is unproven
and remains deferred.

## Deployed Stage 3A and Stage 4 media candidate

The retained Stage 3A change subtracts only normal-success work from
`bird-early.sh`: a shell builtin `read` replaces the
pre-launch BusyBox `cat` of fixed maximum brightness; two brightness diagnostic
writes, three concurrent/later uptime `cut` children and four normal
root-ready/handoff LED `cat` children are removed; LED inspection remains
failure-only. Exact
brightness writes and strike timing, endpoint setup, module loading,
launcher/PID publication, storage acknowledgement, ownership checks, timeout
retirement and failure evidence remain unchanged. The target is one fewer
pre-launch process and two fewer pre-launch writes plus seven fewer
concurrent/later transient children. Its returned timings established
functional non-regression but did not establish a boot, interaction, energy or
memory improvement.

The returned Stage 3A boots recorded launcher/input/usable milestones of
1217/1218/1229 ms and 1211/1212/1225 ms, with storage anchored at 3685 and
3739 ms. The user verified the rest of the functional gate. The release and
its previous selector contain byte-identical MPV input policies, so the newly
observed pause-plus-audio-track action was not introduced by the shell
subtraction. Two attempted SDL-policy corrections then proved that changing
`GAMEPAD_ACTION_*` aliases cannot make the path deterministic: physical west
and east presses each retained one intended action while also changing audio
tracks.

Inspection found two simultaneous owners in the retained provider. ROCKNIX's
`start_mplayer.sh` starts `mpv.service`/`mpv_sense`, which reads raw evdev and
spawns `socat` commands, while the same wrapper starts MPV with
`--input-gamepad=yes`. The deployed Stage 4 candidate replaces both media-only
translation paths with one 6,424-byte freestanding `bird-mpv-controls` process.
It validates the complete H700 contract, uses watch-before-scan discovery,
discards overflowed evdev records through `SYN_REPORT`, resynchronizes held
keys, reconnects IPC without replaying stale commands, blocks in `ppoll`, and
sends direct JSON commands without per-press processes. The wrapper disables
MPV default/SDL gamepad bindings and never starts `mpv_sense`, while retaining
the provider's `mpv` freeze publication for fake suspend. The documented
regular and one-handed controls, chapter, playlist, subtitle and
shoulder+Select audio-track actions are preserved; Menu+D-pad adds isolated
contrast and saturation steps of exactly one point per press. This candidate is
loaded only after media selection and adds no initramfs, launcher, boot-time
process, timer, framebuffer traffic or ordinary menu-idle work.

The exact deployed tuple is clean source
`f866fe7dbeaec3e3ee0d3937296968c804b77665`, immutable release
`v6.23-mpv-single-input-f866fe7` and manifest
`475e786077d54d7247dbd11d463fcb8b8bd1377c7315e5913644f58bdb9fe017`.
The final-root helper is 6,424 bytes with 5,320 bytes of text, 32 bytes of data
and 2,936 bytes of BSS. The launcher is byte-identical to the previous release,
and the compressed early overlay is two bytes smaller; neither host fact is a
device boot-time claim. Physical command mapping, suspend integration, launch
and return behavior remain the promotion gate.

The returned gate rejects this exact tuple as the accepted media-control
candidate. Contrast and saturation passed, but bumper taps lost the preceding
player-relative volume contract, audio-language cycling was no longer directly
reachable, and chapter actions gave no feedback on the tested files. Physical
B was correctly reaching MPV's `frame-step` command: when invoked during
playback, that command pauses and advances one frame, which can look like a
rapid play/pause rather than a distinct control.

Host `ffprobe` inspection found zero chapter records in the two tested files,
`12 Angry Men.mp4` and `Akira (1988).mp4`. The retained trigger mapping must be
verified with chaptered content: the card's `Angel's Egg.mkv` has seven chapter
records and `The Godfather.mp4` has 23. Silence on a zero-chapter file is not
evidence that the raw L2/R2 codes were missed.

The bounded successor retains the single raw-evdev owner. Physical X cycles
audio instead of mute; L1/R1 taps restore MPV-local volume while a bumper used
with another control remains the one-handed modifier; Menu+L1/R1 changes
MPV-local picture brightness; and L2/R2 remain chapter navigation with OSD
feedback where chapter metadata exists. Dedicated volume and Menu+volume stay
system-volume and panel-backlight controls. No SDL, `mpv_sense`, per-press
process, boot-time executable, or menu-idle wakeup returns.

That successor is deployed as clean source
`813226d4c1b0fe9715bdae3f37d44485e4ad815f`, immutable release
`v6.23-mpv-complete-controls-813226d` and canonical manifest
`05f20822324d62be334a290f9567d341efc6f08243c14ab88adda43073d975a6`.
All 56 manifest-owned files verified and
`v6.23-mpv-single-input-f866fe7` is the previous selector. Focused tests prove
that one physical B press queues one `frame-step` and no pause command, both
Select+Start orders suppress media actions, and modifier/reconnect paths cannot
leak a bumper-volume action. The helper is 6,704 bytes, 280 bytes larger than
the rejected helper; its loadable section total excluding `.comment` is 8,294
bytes, six bytes larger. The launcher is byte-identical to the rejected
release. These are host binary facts, not RG34XX-SP timing claims.

The returned physical gate confirmed the complete control map, including
one-frame B behavior, direct audio cycling, player-local volume and brightness,
chapter navigation on chaptered content, subtitles, picture controls, exit and
menu return. The same boot's early log recorded launcher start at 1218 ms,
validated input at 1219 ms, honest usable frame at 1222 ms and storage at
3945 ms. Its SHA-256 is
`5ca5e2aaa8174ff7226271f1ae6416bc8870fc32363d1115f8b72beb574623a8`.
The preceding candidate's latest sample was 1223 ms input and 1232 ms usable;
the unpaired single samples establish functional non-regression only, not a
boot improvement.

This gate also establishes a content-interaction attribution baseline. The
launcher published the MPV request at 7.558 s; the content session began at
10.09 s, application contract became ready at 12.21 s, Sway became ready at
14.04 s and provider dispatch began at 14.29 s. After provider return at
73.98 s, the replacement launcher started at 74.324 s and published a matched
retained-frame usable menu at 74.377 s. These kernel-relative stages do not
substitute for button-to-photon or first-content-photon measurement.

### Direct-flash replacement-launcher candidate

The next bounded Stage 4 candidate changes only the final-root replacement
path. The original initramfs launcher remains `/opt/bird/bird-launcher` and
retains framebuffer, input and storage ownership through `switch_root` exactly
as before. If adoption or content return needs another launcher, the supervisor
now executes `/flash/bird/bird-launcher` from the selected immutable release.
`mount-storage.sh` no longer copies, chmods or verifies a second writable
launcher under `/storage/.config/bird`. An old writable copy may remain as
inert data; ordinary boot neither executes nor deletes it.

Against the accepted MPV checkpoint, the per-boot writable copy set falls from
19 regular-file copy operations and 817,170 source bytes to 18 operations and
219,817 bytes. That is one fewer external `cp`, one fewer `chmod` operand, one
fewer destination capability check and 597,353 fewer aggregate source bytes
(73.1 percent); 597,336 bytes are the launcher itself and 17 bytes come from
the shorter supervisor path. The final-root launcher remains exactly 597,336
bytes with SHA-256
`df44db7997c88cc1ee3d9cbcbf33bb56ca8b45712009299b8199d33b51725a18`.
The early launcher remains exactly 600,600 bytes with SHA-256
`2d82606ad6b4cc28ceebcdd5005bef54d13c3ad846ed7f7da945d9e2e91b1821`;
both binaries are byte-identical to the accepted checkpoint. Profile-mode
final-root and early variants also compile at 658,408 and 669,992 bytes.

This is a storage/root-preparation and content-return candidate, not a launcher
rendering change. Host launcher syscalls, dynamic instructions, framebuffer
bytes, ELF sections and resident memory are unchanged by construction. It
removes no resident task or idle timer. Device boot, UI/content interaction,
transient memory and energy remain unmeasured; in particular, no boot or
battery improvement is claimed until the RG34XX-SP gate passes.

The RG34XX-SP functional gate passed direct `/flash` replacement launch and
return. Boot ID `a4886df4` recorded launcher start/input/usable-frame at
1220/1221/1224 ms, versus 1218/1219/1222 ms for the preceding MPV checkpoint.
The unpaired +2 ms observations are boot non-regression evidence only, not a
latency claim. An early selection at 3606 ms was queued before storage at
3889 ms, published at 3956 ms and relinquished the launcher at 3996 ms. The
provider did not start until 14.50 s. The unchanged menu pixels were therefore
visible but noninteractive for about 10.5 seconds: a real content-readiness UX
gap, not evidence that the kernel or launcher process was still hung.

### Logged emergency UI recovery candidate

Menu+Select+Start now invokes one operator-only recovery transaction. It first
writes a unique mode-0600 snapshot below
`/storage/bird-data/MUOS/Bird/log/emergency/`, including boot identity, unit and
process state, memory pressure, Bird state files, bounded journal/dmesg output
and the existing early/supervisor/content logs. It syncs that evidence before
using the existing foreground-exit helper, cancelling one pending request,
terminating only an exactly validated inherited launcher when necessary and
requesting a nonblocking `essway.service` restart. The chord is latched until
Select or Start is released, and a late Menu edge upgrades an already-issued
Select+Start exit to logged recovery.

The helper is executed directly from immutable `/flash` and is never copied
per boot. It is 6,254 bytes. The fixed-controls binary grows from 10,352 to
10,608 bytes: `.text` +60 bytes, `.rodata` +192 bytes and `.bss` unchanged at
8 bytes. There is no new resident task, syscall, timer, framebuffer traffic or
ordinary idle wakeup; diagnostics and sync cost occur only when the emergency
chord is deliberately invoked. Host dynamic-instruction counts are unavailable
because Valgrind is not installed. Physical chord recovery, preserved logs and
ordinary Select+Start behavior remain the device gate.

Boot ID `bf45b45b` passes that recovery gate. The initial launcher started at
1217 ms, validated input at 1218 ms and published a usable frame at 1221 ms.
Menu+Select+Start at 75.887 s persisted a 178,213-byte snapshot, completed the
managed foreground-exit path, cancelled the pending action and successfully
requested the UI restart. A retained-frame menu was usable at 76.543 s without
a reset. The same game then launched through RetroArch and returned with result
0. Brightness, volume, media launch and shutdown also remained functional.

The snapshot identifies the first-game freeze precisely. At 5.268 s systemd
found an ordering cycle from the retained multi-user-enabled
`powerstate.service`, through its `After=essway.service` edge, graphical target,
seatd and back to multi-user/powerstate. It deleted `essway.service/start` to
break the cycle. The early launcher later published the Atari request and
exited normally at 27.157 s, but no supervisor existed to consume it. No game,
RetroArch, OOM, input or kernel fault occurred before the freeze.

The bounded correction removes only powerstate's invalid reverse ordering edge.
`powerstate.service` remains requested by both the retained multi-user enablement
and `rocknix.target`, while `essway` remains behind the stable graphical
boundary. The unit shrinks from 291 to 276 bytes. The 597,336-byte launcher and
5,528-byte power worker are byte-identical to the recovery checkpoint; there is
no new task, timer, framebuffer byte, syscall loop, binary memory or early-boot
work. This is final-root correctness after the already-usable menu, not a boot
latency claim. It prevents systemd from sacrificing either the supervisor or
power worker and therefore protects content interaction and power policy.

Clean source `895e6a7ae557df3b202e6ac7b78234441b705c0e` is deployed as
`v6.23-ui-order-895e6a7`, canonical manifest
`fdf3e466ef85682c4b6de977ff8484c5bb9b24eddf953f4f6981eb206aa6e149`.
All 57 manifest-owned files verified, with the accepted emergency checkpoint as
the previous selector. That RG34XX-SP gate passes. Six returned boots recorded
usable-frame times of 1229, 1225, 1222, 1222, 1224 and 1218 ms, a descriptive
median of 1223 ms; the latest sample was the fastest. Every captured final-root
snapshot had both `essway.service` and `powerstate.service` active, and no
ordering-cycle/job-deletion event remained. Repeated cold first-game launch,
content return, media controls, suspend, shutdown and a second logged emergency
restart also passed. These observations establish functional and boot
non-regression, not a new latency distribution claim.

### Immutable content-dispatcher candidate

The next bounded Stage 4 candidate moves only the final-root content dispatcher
to the selected immutable release. The supervisor now executes
`/flash/bird/run-content.sh`; `mount-storage.sh` no longer copies, chmods or
verifies a writable duplicate under `/storage/.config/bird`. An old writable
copy may remain as inert data, but ordinary boot neither executes nor deletes
it. Provider selection, storage handoff, one-pending-intent behavior and the
dispatcher itself are unchanged. The deployed dispatcher remains exactly
65,346 bytes with SHA-256
`9a471700d333f1d22f5c55066c1ce1683b560ea42081c1b97b3534106432e6d9`,
byte-identical to the accepted ordering checkpoint.

Against that checkpoint, the writable preparation set falls from 18 files and
220,067 source bytes to 17 files and 154,715 bytes. This removes one external
`cp` child, one `chmod` operand, one destination capability check and 65,352
source bytes plus 65,352 destination bytes per boot, a 29.7 percent reduction
of that remaining payload and an 81.1 percent cumulative reduction from the
original 817,170-byte set. The final and early launchers, fixed controls and
power worker are byte-identical. The release initramfs differs by one compressed
byte solely because of release metadata. There is no launcher syscall,
framebuffer, input, resident-task, idle-timer or memory change.

Clean source `0b438f52b767e3c8ec008c1a5e7c342c0d503643` is deployed as
`v6.23-flash-runner-0b438f5`, canonical manifest
`2ca0ba49a33e0a62f9abbe73419696a32943af70fbc266659ad59bd08cf75ec6`.
All 57 manifest-owned files verified, with the accepted ordering checkpoint as
the previous selector. That RG34XX-SP gate passes: first content launch,
provider return, media controls, emergency recovery and shutdown remained
functional. Three surviving boot records reported usable-frame times of 1224,
1232 and 1239 ms, a descriptive median of 1232 ms. This is 9 ms above the
preceding six-boot median, but the early executable is byte-identical and the
external stopwatch remained about 2.7 seconds. The small unpaired set supports
non-regression only, not either a speedup or regression claim.

Suspend stress produced one non-blocking abrupt reboot after several successful
cycles. Its O_DSYNC trace completed four cycles, then ended with power dispatches
at 29.623 and 30.566 seconds without the normal resume-complete record before
the sequence reset on the next boot. No ordered shutdown, panic, Oops, OOM,
pstore record or reset reason survived, and the following boot completed repeated
suspend cycles normally. The evidence locates interruption inside an in-flight
resume but cannot attribute the provider, kernel or power hardware. No cooldown
or behavior change is justified; the quirk remains deferred for finer provider-
phase and reset-cause instrumentation.

### Immutable final-root supervisor candidate

The next bounded Stage 4 candidate changes only the final-root UI service exec
path. `essway.service` now starts `/flash/bird/supervisor.sh`, and
`mount-storage.sh` no longer copies, chmods or verifies a writable supervisor
duplicate. The same generated Bash supervisor, launcher adoption, content
dispatch, boot-attempt, recovery and shutdown behavior remain in place. The
manifest-verified `/flash/bird` mount is established before this service starts
and remains stable until the service is stopped for shutdown.

Against the accepted dispatcher checkpoint, writable preparation falls from 17
files/154,715 bytes to 16 files/136,973 bytes. This removes one `cp` child, one
mode operand, one destination capability check and 17,742 source plus 17,742
destination bytes, 11.47 percent of the remaining payload and 83.24 percent
cumulatively from the original 817,170-byte set. `essway.service` shrinks ten
bytes. The generated supervisor grows four immutable bytes only because the new
release ID is longer. Final and early launchers are byte-identical at 597,336
and 600,600 bytes; profile variants remain 658,408 and 669,992 bytes. The
615,251-byte early overlay differs from the accepted overlay by one compressed
metadata byte. There is no launcher, framebuffer, input, provider, suspend,
audio, task, timer, wakeup or resident-memory change.

Clean source `f06686ab0cf80676733de800809c39765aadfc6e` is deployed as
`v6.23-flash-supervisor-f06686a`, canonical manifest
`e69a5c90fae8479161819b5797984d03e9d8a15e0c96f23a75c4647c6582bb37`.
All 57 manifest-owned files verified, with the accepted immutable-dispatcher
checkpoint as previous. The RG34XX-SP gate passes the direct supervisor path,
both retained service states, game and media launch/return, retained-frame
emergency restart and orderly shutdown. The two valid per-boot records report
usable readiness at 1232 and 1221 ms after kernel start; the external stopwatch
remained near 2.7 seconds. The missing per-boot log from the abruptly reset run
is not reconstructed from `early-initramfs-latest.log`. These sparse records
establish boot non-regression only; no latency or energy improvement is claimed.

Audio-only MPV playback also exposed a retained fake-suspend discontinuity on
this otherwise accepted checkpoint. Boot `8e3ced38` dispatched power suspend and
resume at 38.956 and 40.910 seconds but left no resume-complete marker before an
abrupt reboot. No orderly shutdown, panic, Oops, OOM, pstore or reset cause
survived. On boot `aa4a04bf`, the same song completed suspend/resume at
22.122/24.647/25.697 seconds but replayed about one second before recovering;
a movie later completed lid suspend/resume at 52.314/53.600/54.639 seconds and
continued normally. The active and previous releases have byte-identical MPV,
suspend, controls and content-runner artifacts, so the immutable-supervisor
subtraction did not introduce this behavior.

The retained provider mutes PipeWire, stops matching MPV processes with
`SIGSTOP`, leaves PipeWire and WirePlumber running, then sends `SIGCONT` before
unmuting. That is not an acknowledged MPV pause transaction and can leave an
audio-only stream with stale buffered output; the exact buffer-level cause is
not logged. No behavior change is promoted: a blind pause toggle is
non-idempotent, pausing every media provider would regress the working movie
path, and letting MPV advance while muted conflicts with the current policy. A
future bounded audio-suspend candidate must distinguish audio-only from video,
preserve prior pause state through acknowledged IPC, align with background-music
policy and follow finer provider-phase/reset-cause instrumentation.

### Immutable first-frame preparation candidate

The next bounded Stage 4 candidate changes only `essway.service`'s pre-start
path from the writable duplicate to
`/flash/bird/first-frame-prep.sh`. The selected release is already required by
the accepted immutable supervisor, and this 811-byte script uses absolute
kernel/storage paths and writes only its diagnostic log. Root preparation no
longer copies, chmods or verifies the writable duplicate.

Against the accepted supervisor checkpoint, writable preparation falls from 16
files/136,973 bytes to 15 files/136,162 bytes. This removes one `cp` child, one
mode operand, one destination capability check and 811 source plus 811
destination bytes. The script still executes once later, so its execution read
is not counted as removed. There is no launcher, framebuffer, input, provider,
suspend, audio, task, timer, wakeup or resident-memory change. Boot timing, the
read-only brightness log, quick launch/return, repeated emergency restart and
shutdown remain the RG34XX-SP gate.

Clean source `094be8be0555c4ab51f2968b21f13993b63de96f` is deployed as
`v6.23-flash-firstframe-094be8b`, canonical manifest
`c90a4b6b5b21fd5cedabdb58f0756ec8ceb810adf18c39efae017becde8dff20`.
All 57 manifest-owned files and the `.complete` digest verified, with the
accepted immutable-supervisor checkpoint as the previous selector. The final
and early release launchers are byte-identical to that checkpoint at 597,336
and 600,600 bytes; `.text`, `.rodata`, `.data.rel.ro`, `.data` and `.bss` are
unchanged. Profile variants remain 658,408 and 669,992 bytes. The early overlay
is 615,256 bytes, five compressed bytes larger than the accepted overlay even
though its early launcher is byte-identical. The inactive immutable-dispatcher
release was archived and independently verified in the private GitHub release
archive before its card copy was reclaimed.

The physical gate passes. Five valid kernel-to-usable records were 1229, 1221,
1221, 1229 and 1226 ms, a descriptive median of 1226 ms and no regression from
the accepted supervisor checkpoint. The external stopwatch remained near 2.7
seconds. The immutable pre-start completed in about 10 ms without a brightness
write. Game, music, reader, movie, retained-frame returns, an emergency UI
restart and durable shutdown completed with no failed unit or ownership loss.
One shutdown requested before storage readiness exercised the existing bounded
final-root wait and still completed; that path was unchanged by this candidate.

### Immutable boot-snapshot candidate

The next bounded Stage 4 candidate changes only
`rocknix-report-stats.service` from the writable diagnostic duplicate to
`/flash/bird/capture-boot-state.sh`. The 4,831-byte script has one post-autostart
consumer, uses absolute paths and writes only its snapshot below writable
storage. The accepted immutable `/flash/bird` lifetime already covers the
launcher, dispatcher, supervisor and first-frame preparation.

Writable preparation falls from 15 files/136,162 bytes to 14 files/131,331
bytes. This removes one `cp` invocation, one mode operand, one destination
capability check and 4,831 source-read plus 4,831 destination-write bytes. The
diagnostic still runs once after autostart, so its execution read is not counted
as removed. Launcher, framebuffer, input, content, controls, suspend, audio,
timers, tasks and resident memory are unchanged. This is post-usable storage
work reduction; it cannot claim a first-frame improvement. Its physical gate is
boot non-inferiority, a fresh complete snapshot after 25 seconds, normal content
return and shutdown.

Clean source `9c4250ee50afd37c720a25b7cf109a64bd1a1303` is deployed as
`v6.23-flash-snapshot-9c4250e`, canonical manifest
`4d854a95edbea36e0e23e26ce7fa76c6a559b790ffcf30e0a852c98d0f877b93`.
All 57 manifest-owned files and the `.complete` digest verified, with the
accepted first-frame-preparation checkpoint as the previous selector. The final
and early release launchers and their ELF sections remain byte-identical at
597,336 and 600,600 bytes. Profile variants remain 658,408 and 669,992 bytes.
The early overlay remains 615,256 compressed bytes but has a new digest because
the initramfs copy list changed. The inactive immutable-supervisor release was
archived, published and independently verified in the private GitHub release
archive before its card copy was reclaimed.

The physical gate passes on boot `02d6aba1`. Input opened at 1222 ms, the usable
frame committed at 1229 ms and storage became ready at 3713 ms. The usable
sample is inside the accepted 1221--1229 ms range, so this is non-regression
rather than a speed claim. The 47,325-byte/786-line snapshot ran as
`/flash/bird/capture-boot-state.sh` through its final section, with zero failed
units and no pending jobs. Game, music, movie, PortMaster networking and cleanup,
suspend/resume, exact menu return and the durable shutdown checkpoint passed.

### Complete immutable final-root toolset candidate

The original stock-root bridge published Bird programs and fixed provider data
under `/storage/.config/bird` because that was the established writable runtime
namespace, FAT modes were not authoritative and destination checks had to fail
closed on partial installation. The selected release is now manifest-verified
before its session-long `/flash/bird` bind, and direct execution is physically
proven across the launcher, supervisor, dispatcher, recovery, preparation and
diagnostic paths.

The next aggressive Stage 4 batch converts every remaining immutable consumer
to `/flash/bird`: PID waiting, global controls, power policy, foreground exit,
shutdown save, PortMaster preparation/verifier/manifest, fixed storage,
networking, suspend, volume and OSD. Only the mutable 260-byte ROCKNIX memory
policy remains copied to `/storage/.config/swap.conf`. Preparation falls from 14
files/131,331 bytes to 1 file/260 bytes, removing 13 `cp` invocations, 131,071
source-read plus destination-write bytes, the complete executable chmod
transaction and 13 destination checks. Inert old writable copies are not
deleted; the fallback overwrites its own versions before use.

This batch changes no launcher, framebuffer, catalog, render traffic, retained
task or timer. It removes post-usable storage/application preparation work and
therefore cannot claim a first-usable-frame improvement. The physical gate must
cover boot timing, storage/application readiness, all global controls, normal
and forced content exit, game/media/reader/PortMaster launch and return, Wi-Fi
cleanup, repeated suspend/resume, input reconnect, changed and quick shutdown,
and rollback availability.

Clean source `61c51dd798af47330af604e2884553f2e0275e68` is deployed as
`v6.23-flash-toolset-61c51dd`, canonical manifest
`d806243beeb5edbffadc36ac1f83fb9306407935d1084e24d23aa11a2881a8a9`.
All 57 manifest-owned files and the `.complete` digest verified, with the
accepted boot-snapshot checkpoint as the previous selector. Release launchers
and their ELF sections remain byte-identical at 597,336/600,600 bytes; profile
launchers remain 658,408/669,992 bytes. Fixed controls shrink from 10,608 to
10,568 bytes entirely in `.rodata`; `.text`, data and BSS are unchanged. The
manifest-owned release shrinks 1,869 bytes, including a 1,692-byte smaller
mount hook and a two-byte smaller 615,254-byte compressed overlay. The inactive
first-frame release was archived, published and independently verified in the
private GitHub release archive before its card copy was reclaimed.

The broad RG34XX-SP gate passes. Boot `b116d112` opened the direct launcher and
input at 1218 ms, committed the honest usable frame at 1226 ms and published
storage readiness at 3723 ms. A game selected at 2493 ms remained exactly one
pending intent and dispatched only after storage became ready. Two managed game
sessions returned status 0 with matched retained-frame restoration. The
operator reported the complete behavior matrix passing, including controls,
providers, PortMaster/network cleanup, suspend/resume and shutdown. Shutdown
was requested at 92.50 s, dispatched at 92.56 s and completed the durable save
at 92.74 s. The 1226 ms usable result remains inside the accepted 1221--1229 ms
range, so timing is unchanged/non-inferior rather than improved.

### Requested diagnostics and content-shell candidate

The ordinary post-autostart snapshot existed to expose retained ROCKNIX unit,
process, memory, journal, kernel, udev and audio state after the compatibility
graph settled. It was idle-I/O-priority work, but boot `b116d112` proves it
still overlapped priority-two content startup: its 46,984-byte/782-line capture
began at 12.17 s, while the first content contract was ready at 12.10 s and
content services began at 13.94 s. Conventional shell parsers also made the
early and content state contracts easy to inspect while those contracts were
still changing. Finally, `systemd-run` retained its default `$` expansion even
for the cleanup guard's embedded shell program.

This candidate makes the full snapshot explicitly requested by the persistent
marker `/storage/bird-data/MUOS/Bird/boot-diagnostics.request`. Ordinary boots retain
readiness, supervisor, content, emergency and shutdown logs without launching
the broad probe set. A requested capture atomically publishes
`stock-root-boot-state-<boot-id>.log`, then refreshes the latest copy; the
supervisor no longer attributes an older latest capture to a later boot. Both
content `systemd-run` boundaries use `--expand-environment=no`, preserving
literal provider arguments and guard parameter expansion. This fixes the
invalid-environment warnings found in the accepted checkpoint's emergency
records and protects paths containing `$`.

Built-in reads replace all 39 external `/proc/uptime` parser sites across the
runner and supervisor, two `cat` plus three `awk` process-stat sites, three
per-launch path-validation helpers, three `sed | head` metadata pipelines,
four PortMaster owner-token `cat` substitutions and seven tiny supervisor
state-read commands. Exact-line parsing still rejects missing terminators,
extra lines and malformed action/PID records. Provider returns now distinguish
success, ordinary exits, SIGKILL, SIGTERM and other Linux signal-derived
statuses after content has returned.

Clean source `e87e4910459b953b7a1f2ebd19a0efee35fe9e57` is deployed as
`v6.23-content-shell-e87e491`, canonical manifest
`28e2372b36cef01c5f49b584c8896b00ce6969299a30eebb1d40a367d960c70c`,
with all 57 files verified and the physically accepted toolset checkpoint as
previous. Release/profile launcher pairs and their ELF sections remain
unchanged at 597,336/600,600 and 658,408/669,992 bytes. The manifest-owned
release grows 2,703 bytes from explicit validation and diagnostics code while
the compressed overlay shrinks three bytes to 615,251. The retired snapshot
release was published and independently verified in the private GitHub archive
before its card copy was reclaimed.

Launcher, framebuffer traffic, input ownership, timers and resident tasks are
unchanged, so no first-frame improvement is claimed. The physical gate must
prove an ordinary boot creates no broad snapshot, a deliberately armed boot is
complete and correctly attributed, systemd expansion warnings are absent,
immediate/pre-storage and normal content launch/return work, deliberate force
quit is classified, and boot/UI timing, providers, controls, suspend and
shutdown remain non-inferior. HDMI and Bluetooth are not part of this change.

The returned content-shell gate passed the complete behavior matrix. Boots
`d86b5a36` and `ce9da31c` opened direct input at 1223/1219 ms and published
usable frames at 1229/1222 ms. The latter is a new best sample but remains a
non-regression, not a distribution-level speed claim. Ordinary boots produced
no broad snapshot, content exits were correctly classified as 0, 143 or the
deliberate 137, retained frames matched and shutdown checkpoints completed.

### Fixed post-frame coordinator and volatile-journal candidate

The generic coordinator existed to preserve the ROCKNIX product matrix while
fixed-device consumers were still being audited. It still scanned H700/common
directories, launched 26 release-provided no-op scripts, forked approximately
45 `date` helpers and required 31 per-script bind substitutions. The accepted
journal was already bounded under `/run`, but systemd still launched an empty
persistent flush and message-catalog update after the menu.

Clean source `133834108ee66a6ad965c44441b6e09690eb8369` replaces that scan with
one fixed coordinator. It calls the 14 proven responsibilities in their exact
pinned order, preserves tolerant failure semantics and optional custom hooks,
and lets `999-export` validate application readiness. Fixed Bird producers run
from `/flash/bird`; retained stock producers run from exact SYSTEM paths. The
no-op helper and all autostart bind substitutions are gone. Journald remains
available with an explicit volatile 2 MiB/128 KiB policy; only the empty flush
and catalog jobs are masked.

Release `v6.23-fixed-autostart-1338341`, manifest
`2c9553b94c7fffd25dff2f45b764c342c134ca6564ed3f9ae9a040ca0149d198`,
is deployed with the accepted content-shell release as previous. Launcher and
profile binaries/sections are unchanged. The mount hook shrinks 2,719 bytes,
the manifest-owned release shrinks 1,789 bytes, and the release overlay changes
from 615,251 to 615,258 bytes. This is post-usable work: no first-frame gain is
claimed. The physical target is earlier application/content readiness and less
late CPU/I/O with boot/UI non-inferior. HDMI, Bluetooth, udev, seatd, logind and
the warm audio policy are unchanged.

The returned fixed-autostart gate passed all functions. Six boot-scoped samples
published usable readiness at 1223, 1226, 1228, 1229, 1229 and 1235 ms, versus
the accepted 1222--1229 ms range. That supports non-regression, not a faster
first-menu claim. The initially suspicious 1567 ms record was a stale
catalog/runtime file outside this release's boot-scoped evidence. Final-root
supervisor entry moved from 9.65--9.69 s to 9.25--9.53 s, consistent with less
post-frame coordinator work.

### Fixed session manager and idle-wakeup candidate

Logind remained because ROCKNIX normally delegates lid, power and login-session
policy to it. Bird now owns lid/power through its fixed controls, the retained
fake-suspend provider has no login1 client, and Sway explicitly joins seatd.
The tmpfiles timer served general persistent roots, while this image recreates
its cleaned `/tmp` and `/var` roots as tmpfs. UTMP recorders likewise served
multi-user login accounting, but wrote only volatile `/var` here.

Clean source `46dd1704e3453dd3f3fcbb55ea96488716deb840` masks logind, its one
resident task, the 15-minute/daily tmpfiles-clean timer and the two boot/runlevel
UTMP one-shots. Seatd, udev, journald, audio, networking, HDMI and Bluetooth
remain unchanged. Release `v6.23-fixed-session-46dd170`, manifest
`00ba951842afc78f2f27a34f952f790e7cc32eab385db4f902cc0e9c0d7df7cd`,
is deployed with the accepted fixed-autostart release as previous. Launcher,
ELF sections and compressed overlay are unchanged; added explicit assertions
grow the manifest-owned release by 530 bytes. No first-frame gain is claimed.
The returned physical gate passed all tested functionality. Boot-scoped samples
`17553b07`, `9ff881cd` and `b7c3b076` published usable readiness at 1222, 1223
and 1222 ms respectively, with direct input at 1219, 1221 and 1219 ms. This
accepts the fixed-session tuple as the next candidate's rollback and supports
first-menu non-regression, not a distribution-level improvement claim. PSS and
wakeup savings remain unclaimed until device measurement.

### Fixed post-frame housekeeping candidate

The generic logging and Pico-8 hooks existed to support mutable configuration
and many ROCKNIX devices. On this fixed image they still removed and recreated
an already-correct RetroArch log symlink and touched an existing `Splore.png`
sentinel every boot. Logind policy publication likewise survived from when
logind still owned input policy, despite the physically accepted service mask.

Clean source `91b2f58ed696dfcd547b1ffd52fcb5ceb3ad3602` replaces those two generic
hooks with fixed idempotent scripts and removes comparison, mode inspection and
drop-in cleanup for inert logind configuration. Udev, seatd, journald, audio,
networking, HDMI and Bluetooth remain unchanged. Release
`v6.23-fixed-housekeeping-91b2f58`, manifest
`41edbb038356df9cbf1086d451a6731ba3b2bc3c7ad71c9d0754d6b76ee9100f`,
is deployed with physically accepted fixed-session as previous. All 58 files
verify; release/profile launchers are byte-identical to the checkpoint. The
steady state removes `rm`, `ln` and `touch` filesystem mutations plus one
logind `cmp`, one `stat` and its obsolete drop-in scan. Manifest-owned bytes
increase by 403 and the fixed Bird-file subset by 564 bytes. These operations
occur after usable readiness, so no first-frame timing change is expected or
claimed; the target is lower post-frame I/O and earlier application readiness.

The returned physical gate passed all tested functionality. The preserved
clean boot reached direct input at 1216 ms and usable readiness at 1220 ms,
inside the accepted range; this is non-regression and a best observation, not a
distribution-level improvement. One suspend stress sequence dispatched lid
close and lid open but never recorded the normal coordinator resume completion,
then a new boot sequence began. Later suspend cycles passed. No panic or
watchdog cause survived, and the housekeeping candidate changed no suspend
path, so no speculative fix is included.

### Fixed application profiles candidate

The generic controller and setup hooks existed to derive profiles for arbitrary
controllers and repair mutable multi-device installations. On the fixed H700
they still ran `control-gen`, XML selection, two UUID generators, 100 per-input
`awk` operations and rewrote `098-controller` every boot. Setup also re-sorted
and replaced valid persistent settings, deleted and re-added
`clouddrive.mounted=0`, and recreated an already-correct cache link. The fixed
UI and application publishers rewrote two valid profiles and one symlink, while
`start.games` served only the absent EmulationStation unit.

Clean source `b87dcc2a5c7f7ef0fc8c4737eebf51ac60b2dd87` publishes a build-verified
H700 controller profile, retains `chksysconfig` recovery, and makes every other
accepted-state publication comparison-only. Application readiness now validates
the fixed controller bytes. Release `v6.23-fixed-profiles-b87dcc2`, manifest
`c9dbc12ff1ca1ef98d7436824321db922905dce45afcac50617db18e1ffe0564`,
is deployed with accepted fixed-housekeeping as previous. All 61 files and
`.complete` verify. Release/profile launchers are byte-identical; the release
overlay shrinks three bytes. Manifest-owned bytes grow 3,513 for explicit fixed
profiles and their repair code. This is post-usable work, so no first-frame
change is expected or claimed; application readiness and storage-write
reduction require device verification.

The returned RG34XX-SP gate accepted this exact fixed-profile release. All
menu, launch, return, media, storage, power and suspend checks passed. Two
preserved clean boots reached direct input at 1216/1218 ms and honest usable
readiness at 1222/1221 ms; their supervisors began at 9.28/9.26 s. These samples
establish non-regression inside the accepted first-menu range, not a faster
distribution. This release is the physical rollback for the next candidate.

The next retained-policy boundary replaces four generic post-frame wrappers:
multi-board CPU/GPU discovery, H700 GPU-overclock profile loading, recursive
platform rumble discovery and generic turbo settings loading. Fixed board paths
and limits retain adjustable core count, every captured CPU/GPU governor, the
600/648 MHz GPU maximum, turbo on/off and built-in PWM rumble on/off. HDMI,
Bluetooth and audio are unchanged. Each policy remains independently tested
and revertible even though the batch shares one hardware cycle.

Clean public source `01e8119ac9953f87442f1627bfd2032485cf9aa5` implements that
boundary. Release `v6.23-fixed-performance-01e8119`, canonical manifest
`70bfa8c408e1f939c3a678ba506ca65e3a5aebdbf33eaa2e5ca370ae2734cc6a`,
is selected with physically accepted fixed-profiles as its on-card rollback;
all 65 files and `.complete` verify. The fixed-housekeeping release was verified,
published to the private release archive and only then reclaimed. Release and
profile variants both compile; release launchers are byte-identical to the
rollback. `bird-autostart` shrinks 172 bytes, the four explicit policy scripts
total 4,544 bytes, manifest-owned bytes grow 5,239, and the compressed release
overlay shrinks four bytes. Production remains the no-serial entry; diagnostic
fallback retains `console=ttyS0,115200`. Because all policy execution remains
after usable readiness, no first-frame timing change is expected or claimed.

The returned hardware gate accepts the fixed-performance tuple. All tested
hardware and application behavior passed, including retained rumble and the
fixed performance closure. The preserved boot started the launcher at 1218 ms,
validated input at 1219 ms and published usable readiness at 1222 ms. This is
inside the accepted range and supports non-regression, not a faster
distribution.

One `12 Angry Men` observation reported imperfect lip sync. Its MP4 metadata
starts AAC audio at 0 while H.264 video starts 125.125 ms later; Bird has no
global or per-file `audio-delay`. MPV's cleaner observed run held its reported
A/V clock between -42 and +33 ms, but accumulated 155 dropped video frames
during a seek-heavy 1200x720/23.976 fps session. This evidence does not justify
a global offset that would desynchronize healthy media. The file-specific
observation remains open for comparison with other movies.

The next Stage 4 manager candidate independently makes seatd content-scoped and
quiesces udevd after successful coldplug. A fixed seatd unit requires an exact
`/run/bird/seat-request` lease; the content owner publishes it before Sway and
releases it only after Sway is proven stopped, including external-guard cleanup.
The udev step waits for settlement and stops only the resident manager while
retaining both activation sockets for later hardware events. Content timing is
a higher-priority gate: seatd-on-demand promotes only if Sway readiness remains
non-inferior. HDMI and Bluetooth capability are unchanged.

Clean public source `d2e064928727a0580f4c07085d2b8eb46be0a4ee` is deployed as
`v6.23-fixed-managers-d2e0649`, canonical manifest
`0c13e8d8a35042b3853b8debf1f1be05e78df4e7682e3a48cfeca53cf6a09463`,
with accepted fixed-performance as the on-card rollback. All 67 files and the
completion digest verify. Release/profile final-root and early-initramfs
variants compile; release launchers and the 615,254-byte compressed overlay are
byte-identical to rollback. The two policy files plus lease/cleanup logic add
2,316 manifest-owned bytes. A retained older manager snapshot observed 1,556
KiB RSS for seatd and 8,548 KiB for udevd before worker memory, but current PSS,
wakeups and energy remain unmeasured. Production remains no-serial; diagnostic
fallback retains serial.

The returned hardware gate found all tested behavior functional and preserved
the boot milestones at 1220 ms launcher/input and 1223 ms usable readiness,
effectively unchanged from fixed-performance's 1218/1219/1222 ms single-log
reference. The lower-priority seatd residency saving is nevertheless rejected:
stable content sessions reached Sway-ready in a 490 ms median versus 470 ms on
fixed-performance, a roughly 20 ms first-launch regression. Total
session-to-provider timing also moved from roughly 630 ms to 710 ms, but the
combined candidate cannot attribute the remainder between manager scheduling
and udev quiescence. The next isolated candidate therefore restores the warm
graphical-boot seatd policy and retains only post-coldplug udevd quiescence.
This intentionally retains seatd's observed 1,556 KiB RSS because content
interaction outranks memory. Udev reactivation, content timing, PSS, wakeups
and energy remain device gates. Production remains no-serial; diagnostic and
fallback entries retain serial.

Clean public source `7d74bf668e3a38a9ae1cd1ceb15d81babf191592` is deployed as
the isolated candidate `v6.23-udev-isolation-7d74bf6`, canonical manifest
`c5fbebc38faa9a469d5c6363dc47811ef0983e973e30908648c09872b8fdbe6f`.
All 66 manifest files verify. Fixed-managers is the on-card functional
rollback; fixed-performance was archived to the private GitHub release archive
before card-space reclamation. Release/profile final-root and early-initramfs
variants compile and the 600,600-byte release launcher is byte-identical to
fixed-managers. Removing the rejected seat unit and lease machinery reduces
manifest-owned bytes by 1,459; the compressed overlay changes by two bytes to
615,256. No boot-timing improvement is expected because warm seatd remains
post-usable graphical work and launcher bytes are unchanged.

The returned udev-isolation cycle resolves the combined timing attribution.
Its cold boot recorded launcher start at 1215 ms, validated input at 1216 ms
and usable readiness at 1219 ms; this is a fast non-regression sample, not a
distribution claim. With warm seatd restored, six stable content sessions
returned to a 470 ms median from session start through Sway readiness. The
later services-ready/provider boundary remained 690--730 ms from session start,
roughly 60--70 ms above the warm-manager reference. Sway and providers are
udev consumers, so stopping udevd after coldplug displaced daemon activation
into the A-button path rather than eliminating it. The udev-idle candidate is
rejected and the fixed coordinator returns to revision v2 with udevd warm.
The retained-userspace audit now intentionally keeps warm seatd and udevd for
priority-two interaction, keeps volatile journald for recovery, keeps audio
warm, removes logind, and gates networking to PortMaster. HDMI and Bluetooth
remain undecided and unchanged.

Clean public source `72d7fe6058dcd21d8c95545871c0acffc3d3dce6` is deployed as
`v6.23-warm-managers-72d7fe6`, canonical manifest
`8b81f34ab5f84e4c1faafee2ee13357de08a26af704f2a8a26e6ac8107f1b545`.
All 65 manifest files verify. Udev-isolation is the on-card rollback and the
older fixed-managers release is sealed in the private GitHub release archive.
Release/profile final-root and early-initramfs variants compile. The 597,336-
byte final-root and 600,600-byte early launchers are unchanged; removing the
udev-idle script reduces manifest-owned bytes by 875 while the compressed
overlay remains 615,256 bytes. Production remains no-serial; diagnostic and
fallback entries retain serial.

The warm-manager hardware return passes all tested behavior. Its cold boot
recorded launcher/input/usable milestones at 1217/1218/1221 ms, inside the
accepted range and consistent with the operator's unchanged stopwatch result.
Four stable content sessions reached Sway-ready in 460--490 ms and provider
dispatch in 700--720 ms. Because the complete runtime implementation is byte-
equivalent to the earlier fixed-performance checkpoint, the difference from
the older roughly 630 ms provider sample remains unclaimed run/environment
variation rather than an attributable regression or improvement.

Stage 5 begins with request-only measurement infrastructure. The existing
`boot-diagnostics.request` service calls a fixed versioned sampler after
autostart; ordinary boots do not execute it. The sampler records raw scheduler,
PSS/USS, wakeup-source, IRQ, CPU-idle and battery counters with an explicit
state label. These snapshots support paired attribution but are not calibrated
energy measurements and do not authorize a battery claim.

Clean public source `3ce316d17574e8487ab846975c404f82f3366e56` is deployed as
`v6.23-stage5-metrics-3ce316d`, canonical manifest
`aba835ad6dd467ff553df81ec64db6542ea4f13e87903fe3268e89bfe3083289`.
All 66 manifest files verify. Warm-managers is the on-card accepted rollback;
udev-isolation is sealed in the private GitHub release archive. Both launcher
modes compile and remain byte-identical. The request-only sampler adds one file
and 3,036 manifest-owned bytes; the compressed overlay changes by two bytes to
615,258. Its persistent request marker is not armed for the ordinary hardware
gate. Production remains no-serial; diagnostic and fallback entries retain
serial.

The returned measurement-infrastructure release passed the broad hardware
gate. Its cold boot recorded 1218 ms launcher, 1219 ms input and 1223 ms usable
readiness. Stable post-first-launch sessions reached Sway-ready in 460--470 ms
and provider dispatch in about 680--690 ms; launch return, PortMaster cleanup
and shutdown completed normally. This accepts the unarmed sampler without a
boot, interaction or battery improvement claim.

Clean public source `2ca82cdf5fd3d173644b756797ae8f0421f4a87d` is deployed as
`v6.23-stage5-idle-2ca82cd`, canonical manifest
`c44f2639aaa714d46ef264d26f3627ed7598699d85c4aaadb7e7abfe88af09c1`.
All 66 manifest files verify. Stage5-metrics is the on-card accepted rollback;
warm-managers is sealed in the private GitHub release archive. Both launcher
modes remain byte-identical. The one-shot control adds 566 manifest-owned bytes
while the compressed overlay changes to 615,255 bytes. When explicitly armed,
the diagnostic settles for five seconds, samples, records a fifteen-second
untouched interval, samples again and disarms the idle-window request after
atomic publication. Ordinary boots still execute no sampler. Production
remains no-serial; diagnostic and fallback entries retain serial.

The one-shot idle-window release passed the broad hardware gate with unchanged
boot behavior. Its first requested measurement did not execute: the documented
`/storage/.config` marker belongs to the internal ROCKNIX storage image, while
the macOS writer had placed the same relative path on BIRD-DATA, which the
device exposes at `/storage/bird-data`. No false sample is recorded. The fixed
request authority is now the existing host-visible Bird directory
`/storage/bird-data/MUOS/Bird`; both the systemd condition and one-shot disarm
path use that exact mount. The two ineffective BIRD-DATA `.config` markers were
removed. This changes measurement triggering only and adds no ordinary process,
timer or content-path work.

Clean public source `97dd6ffc55b2c1f86650bf1a7bb95cd10d1ff9e0` is deployed as
`v6.23-stage5-trigger-97dd6ff`, canonical manifest
`505ac5d6674d81f18aff22723117dd2d48fafdffb443d3d961de6229bf2a6af5`.
All 66 manifest files verify. Stage5-idle is the on-card accepted rollback;
stage5-metrics is sealed in the private GitHub release archive. Both launcher
modes remain byte-identical. The corrected absolute strings add 31 manifest-
owned bytes and the compressed overlay is 615,257 bytes. Production remains
no-serial; diagnostic and fallback entries retain serial.

The corrected trigger passed its broad hardware gate and produced boot-scoped
sample `62fc769f`; the one-shot marker disappeared only after both labels and
the atomic latest copy existed. Across 15.04 seconds, raw `/proc/stat` deltas
show 26 busy and 5,958 idle aggregate jiffies (0.43 percent busy), 22,087
context switches (about 1,469/s) and 15,498 hardware interrupts (about
1,030/s). The largest named IRQ deltas are `arch_timer` 7,317 (486.5/s) and
`5070000.adc` 4,512 (exactly 300/s), followed by I2C 113 and thermal 61. This is
screening evidence, not calibrated energy. The start sampler performed
structural reads after its scheduler timestamp, and one `/proc/PID` exit caused
the combined PSS awk to abort, so process memory and the exact global idle rate
from this run are invalid.

The next measurement-only correction uses a race-tolerant shell read for each
`smaps_rollup` and a minimal paired counter endpoint. Start enumerates structural
and per-process scheduler state before writing the final global scheduler
timestamp; end writes the global timestamp first. The timed global delta thus
excludes start-side enumeration. Per-process `schedstat` plus voluntary and
nonvoluntary context-switch counters identify actual runtime without inferring
cost from residency alone. The ADC and timer rates remain hypotheses until the
corrected sample repeats them.

Clean public source `9945f9d4f43013a0f09df7ea51a7a23dc1812b04` is deployed as
`v6.23-stage5-counters-9945f9d`, canonical manifest
`f65def91471288ea1aa7fb310ccfbb07fdc18414bf8d85d692d39fbe2814b704`.
All 67 manifest files verify. Stage5-trigger is the on-card rollback and
stage5-idle is sealed in the private GitHub release archive. The release
launcher remains 597,336 bytes and the early launcher 600,600 bytes; the new
counter endpoint adds one file and the release inventory grows by 3,371 bytes.
The compressed overlay changes by one byte to 615,258. Both profile variants
also compile; the profile early launcher is 669,992 bytes and its overlay is
630,752 bytes. Ordinary boots still execute no sampler. Production remains
no-serial; diagnostic and fallback entries retain serial.

The next armed boot must remain untouched for about 50 seconds. Acceptance
requires both versioned `start` and `end` counter blocks, race-tolerant PSS/USS
records, atomic publication and removal of the one-shot marker. Until that
physical return, this release is neutral measurement infrastructure and no
boot, interaction, battery or memory improvement is claimed.

The returned corrected 15-second window completed and the broad hardware gate
passed. Aggregate CPU was 0.45 percent busy with about 1,484 context switches/s.
The launcher used 0.423 ms and five scheduling slices; powerstate used 0.380 ms
and five slices. Warm PipeWire, PulseAudio, WirePlumber and seatd recorded zero
runtime during the window. Udevd used 53.3 ms and 24 slices, but the prior
isolated udev experiment measurably delayed content launch and remains rejected.
The dominant activity was kernel work and the fixed ADC/timer interrupt stream.
This is structural evidence, not calibrated energy.

Clean source `56d58d404817f90588e61e0faa58beb0e7547f66` is deployed as
`v6.23-stage5-settled-56d58d4`, manifest
`8e0988258c445c4c743f9afe8ae042a86d3bf144aa8a6c78456070641c343ebc`.
All 69 files verify; stage5-counters is the on-card rollback and stage5-trigger
is sealed in the private GitHub archive. A standalone request-only service now
settles for 30 seconds and measures for 60 seconds without running the broad
boot diagnostic. Global CPU, IRQ and softirq boundaries exclude process/sysfs
enumeration. The inventory adds two files and 1,745 bytes; release launchers
remain 597,336/600,600 bytes and the overlay shrinks five bytes to 615,253.
Ordinary boots add no process or timer. Production remains no-serial;
diagnostic/fallback entries retain serial.

The settled candidate failed its hardware gate before final-root handoff. Its
new `bird-stage5-window.service` bind target did not exist in the immutable
stock root, so root preparation stopped. The early launcher could navigate,
but content, controls, suspend and emergency recovery were unavailable because
their final-root owners never started. No new logs survived because storage
handoff never completed.

Clean source `d0c6e4edb02753f3f006ad2513976ce25b87cbfa` repairs this as
`v6.23-stage5-slot-d0c6e4e`, manifest
`bcf8e4575878ba81f8ffd854037436e2876a859148f959d167fe1c1981c8df95`.
The existing stock report-statistics service slot now dispatches either
explicit diagnostic request through two systemd OR conditions; no new bind
target is introduced. A host test rejects every systemd bind destination absent
from the pinned stock root. All 69 files verify. Stage5-counters remains the
known-good rollback; the failed release is archived privately and removed from
the card. Measurement is unarmed for the recovery gate. Launchers are unchanged
and the overlay is 615,252 bytes. Production remains no-serial.

The repaired slot passed the complete RG34XX-SP recovery gate. Launcher, input
and usable readiness were 1223/1224/1226 ms. Early pending launch dispatched
once at storage readiness; games, music, reader, movie, PortMaster, brightness,
volume, suspend, emergency recovery and shutdown all returned to their normal
owners. The clean Stage 5 window may now be armed on this same release.

The clean 30-second-settled, 60-second menu-idle acquisition passed on boot
`71d6d1b1`. Launcher/input/usable readiness was 1218/1218/1226 ms. Aggregate
CPU busy time was 0.289 percent; context switches were 1,454.5/s and interrupts
949.9/s. The launcher, supervisor, journald, udevd, PipeWire, PulseAudio,
WirePlumber and seatd recorded zero runtime and zero slices in the measured
window. `bird-powerstate` used 0.868 ms and eight slices. The fixed ADC produced
300.1 interrupts/s and the architecture timer 464.2/s; kernel workers dominated
recorded runtime. Launcher PSS/USS was 1,776/1,772 KiB. The warm audio stack was
20,898 KiB PSS and seatd 263 KiB PSS, but their zero-runtime idle result and
previous launch-latency gates keep them unchanged. Battery `current_now` was an
instantaneous 437 mA reading, not calibrated energy. This clean result exhausts
the obvious resident-userspace wakeup candidates for short-label menu idle; the
next independent comparison is marquee idle on the same binaries.

The marquee comparison passed on second-boot ID `cb7daf5b`. Boot remained
1217/1218/1226 ms launcher/input/usable. During its 60-second window the
launcher used 30.1 ms and 277 slices: 0.050 percent of one core and 4.62
scheduled slices/s while scrolling. Aggregate busy was 0.318 percent versus
0.289 percent in the short-label sample; ADC remained 300.1 interrupts/s.
Because the visual update cost is already small and only exists while a selected
label scrolls, no cadence or smoothness change is justified by these structural
counters. The request-only sampler now accepts separately labelled paused-game,
audio-playback, video-playback and external-power menu states so the remaining
matrix can be acquired without running ordinary-boot diagnostics.

Clean source `e8cd4ef2b5546bd158454bccaf0db951298a3237` is deployed as
`v6.23-stage5-states-e8cd4ef`, manifest
`9e62d8ffabe2d2091a5b832aca4f53b77e90c1a3cd450c247efc02774c299a18`.
All 69 files verify; stage5-slot is the on-card rollback. The older
stage5-counters release was verified, published to the private immutable GitHub
archive, then reclaimed from the card. Release launchers remain
597,336/600,600 bytes; the overlay is 615,249 bytes, three bytes smaller. The
candidate is deployed unarmed so its broad behavior gate remains separate from
the next requested measurement.

The unarmed RG34XX-SP gate passed. Launcher/input/usable readiness was
1219/1220/1222 ms, within the accepted range and four milliseconds faster at
usable readiness than the preceding logged boot. Broad menu, content and
hardware behavior passed. The same release may now acquire one explicitly
requested paused-game window; this is measurement only, not a timing claim.

The operator-positioned RetroArch paused-menu window passed on boot
`24facdce`. Launcher/input/usable readiness was 1215/1215/1218 ms, four
milliseconds faster at usable readiness on unchanged binaries and therefore
ordinary boot variation, not an optimization claim. Over 60 seconds RetroArch
recorded 53.59 CPU-seconds and 41,748 slices for the RetroArch main thread; the
Sway main thread recorded 5.55 CPU-seconds. Aggregate four-core busy was 28.58
percent,
with 5,902 context switches/s and 4,624 interrupts/s. RetroArch PSS/USS was
204,267/194,748 KiB. PipeWire, PulseAudio, WirePlumber and seatd recorded zero
runtime during the window. Thus the paused core does not imply a quiet UI:
RetroArch/Sway continue presenting its menu. The instantaneous battery reading
moved from 440 to 445 mA, but is not calibrated energy. Preserve menu
responsiveness for now; retain this as a measured battery candidate and acquire
ordinary audio playback next on identical binaries.

The ordinary MP3 playback window passed on boot `a91f03d0`.
Launcher/input/usable readiness was 1220/1221/1226 ms, eight milliseconds
slower at usable readiness than the paused-game boot on unchanged binaries and
therefore ordinary variation. Over 60 seconds the MPV main thread recorded 1.95
CPU-seconds and 5,712 slices. Aggregate four-core busy was 3.40 percent, with
2,166 context switches/s and 1,786 interrupts/s. PipeWire,
PulseAudio, WirePlumber, seatd, Sway and both Bird MPV helpers recorded
effectively zero runtime during the measured window. MPV PSS/USS was
32,373/29,528 KiB; the retained PipeWire/Pulse/WirePlumber stack totaled 18,682
KiB PSS. The instantaneous battery reading moved from 439 to 442 mA and is not
calibrated energy. The warm audio managers are now a measured memory/residency
candidate, but may not be removed unless provider launch and return remain
non-inferior. Acquire ordinary video playback next on identical binaries.

The ordinary video window passed on boot `35f2c9f5`. Launcher/input/usable
readiness was 1221/1222/1226 ms, identical at usable readiness to the audio
window. Over 60 seconds aggregate four-core busy was 63.32 percent, equivalent
to 2.53 cores, with 3,408 context switches/s and 2,906 interrupts/s. MPV
PSS/USS was 120,127/116,508 KiB; the retained audio stack held 18,820 KiB PSS
and again recorded zero main-thread runtime. The instantaneous battery reading
moved from 449 to 456 mA and is not calibrated energy.

Review of the sampler found that its per-process scheduler lines read only
`/proc/<pid>/schedstat`, which represents the main thread rather than all worker
threads. Global CPU, IRQ, memory and boot results above remain valid, but the
earlier RetroArch, Sway and MPV values are explicitly main-thread attribution.
Stage 5 counter ABI v2 enumerates `/proc/<pid>/task/<tid>` outside the measured
boundary so subsequent content windows can attribute multi-threaded work
without adding normal boot work.

The ABI-v2 video repeat passed on boot `cb83e535` with
1217/1218/1226 ms launcher/input/usable readiness. Over 60 seconds MPV's full
thread group used 167.83 CPU-seconds, PipeWire 0.79 and Sway 1.94; aggregate
four-core busy was 72.86 percent, equivalent to 2.91 cores. The 1916x1080 H.264
High-profile source did not report hardware decoding under `--hwdec=auto-safe`,
used the `wlshm` output and dropped frames. Do not force an unproven decoder
path. The same content session wrote 320,566 bytes across 5,852 log lines,
mostly MPV's continuous terminal status. The next bounded userspace candidate
disables terminal OSD and lowers release messages to warnings/errors while
retaining full output behind `BIRD_MPV_TRACE=1`.

The quiet-MPV paired screening window passed on boot `0f8278ee` with the same
movie and ABI-v2 sampler. Its content log fell from 320,566 bytes/5,852 lines to
1,349 bytes/21 lines, a 99.58 percent byte reduction. MPV thread-group runtime
fell from 167.83 to 130.28 CPU-seconds and aggregate load from 2.91 to 2.28
equivalent cores. Context switches moved from 3,422 to 3,385/s; interrupts from
2,815 to 2,862/s. The session emitted no warning or error and the physical
behavior gate passed. Launcher/input/usable readiness was 1217/1218/1229 ms;
the three-millisecond usable change on a byte-identical launcher is ordinary
variation. This is a large same-content screening result, not calibrated energy
or a statistically promoted battery claim. Retain the candidate and complete
the external-power idle window next.

The external-power menu-idle window passed on boot `e353f4cd`. USB remained
online and the battery remained charging throughout. Launcher, power worker,
PipeWire, PulseAudio, WirePlumber and seatd recorded zero thread runtime. Total
four-core busy was 0.302 percent, with 1,469 context switches/s and 1,068
interrupts/s; the fixed 300 Hz ADC source remained unchanged. The discharging
capacity timer was correctly absent. Launcher/input/usable readiness was
1215/1216/1222 ms, ordinary variation on unchanged binaries.

The same accepted shutdown logs expose one deterministic failure: after logind
removal, `systemctl --no-block poweroff` still routes through the masked logind
interface before Bird's effective shutdown path proceeds. The bounded client
now directly enqueues `poweroff.target`; reboot directly enqueues
`reboot.target`. This preserves systemd's ordered shutdown and avoids both the
known failed round trip and a forced-poweroff bypass. It runs only after a user
shutdown/reboot request and adds no boot or idle work.

The ordered-target physical gate passed on release
`v6.23-stage5-shutdown-d221dfd`. Reboot was accepted from the early handoff and
restarted normally. Quick shutdown logged dispatch-ready in about 140 ms;
post-content shutdown entered `poweroff.target` quickly enough that systemd
terminated the supervisor/client before its final success record. Both paths
ran the ordered config checkpoint, and neither emitted the former masked-logind
failure or waited for the three-second client bound. Two clean boots reached
usable readiness at 1221 ms. Accept the direct-target dispatch and begin the
Stage 6 active namespace inventory.

The Stage 6 inventory is now frozen by
`kernel/rocknix/canonical-namespace-v1.tsv` and its strict validator. The old
paths existed to bridge Bird onto retained ROCKNIX/muOS storage while keeping
the established fallback runnable. The migration therefore does not rename or
duplicate the 985 MB legacy `MUOS/Bird` history. It prepares a fresh canonical
`/storage/bird-data/Bird` tree, copies only favorites/recent persistence and a
content-verified BIOS tree, retains the old paths for fallback use, and
publishes the two canonical trees with resumable same-volume renames. This is
the accepted transaction boundary. The active runtime now uses the canonical
namespace; the legacy trees remain untouched solely for fallback boot.

The accepted atomic activation uses `/run/bird` for the early launcher and all
handoff markers, `/storage/bird-data/Bird/state` for favorites and recents,
`/storage/bird-data/Bird/log` for diagnostics, and direct catalog paths below
`/storage/roms` and `/storage/media`. It removes the launch-time
`/mnt/mmc`-to-`/storage/bird-data` rewrite and the nested legacy BIOS bind.
The launcher opens `/sysroot/storage` once at root-ready (or `/storage` when
started in final root), preserving one storage descriptor across the mount
transition. The accepted fallback remains untouched on its legacy paths. This
boundary passed its migrated-card and immutable-release RG34XX-SP gate.

The first namespace-v1 physical screen proved the mount and direct catalog
paths, plus Ports, media, books, PortMaster, networking and new-state
persistence. It also exposed one exact dispatcher mismatch: `rocknix_tuple()`
still matched legacy `*/ROMS/<system>/*` strings after the catalog began
emitting `/storage/roms/<system>/*`. Every emulator selection therefore
returned before `runemu.sh`; no ROM read or provider process was attempted.
The correction matches only the canonical fixed paths and adds a host test for
all 27 provider tuples plus legacy/malformed rejection. Recovering favorites
from the retired namespace is explicitly waived; canonical favorites created
after migration already persist. Commit `74e5a00` supplied that correction;
the broad gate on `v6.23-20260808-214626` passed the emulator and complete
functional matrix, so namespace v1 is accepted.

## Launcher visual architecture

The active 720x480 launcher presentation is inspired by Mister Menu's ES-DE
layout, but it remains birdOS's freestanding direct-framebuffer implementation;
ES-DE is not a launcher runtime dependency. The original source artwork is the
pinned 720x480 RGB PNG
[`firmware/assets/bird-launcher-backdrop.png`](firmware/assets/bird-launcher-backdrop.png).
The build-time generator verifies that PNG's format and SHA-256, decodes it on
the host, and deterministically emits a fully composited bottom-up 24-bit BMP
and a sparse one-page native XRGB8888 wallpaper image plus their digest
contract. The native artifact is exactly 720x480, top-down, 2,880-byte stride,
page offset 0:0 and `B,G,R,X` memory order. The opaque top bar, menu container
and menu shadow are subtracted to zero in that artifact. The PNG is the only
editable wallpaper source in the repository; neither PNG nor BMP is shipped to
or decoded by the launcher. Runtime recovery maps the native bytes, copies only
visible wallpaper spans and composes fixed chrome before one framebuffer
barrier.

The home view has a narrow vertical rail labelled `HOME`; its cream top bar is
otherwise reserved for the vertical battery icon and percentage. Nested Play, Systems,
Favorites and media views place their full path in the top bar as fixed
breadcrumbs while retaining the battery at the right. The content surface is
a fixed opaque burgundy panel over the backdrop. It does not use per-pixel
alpha or runtime alpha blending. The centered 400x288 content surface keeps
nine complete rows and the MiSTer reference's 1.39 panel aspect ratio. The
footer has no panel or visible diagnostic line: a fixed wallpaper strip is
restored before control-hint changes, with a 96,000-byte static inherited-frame snapshot as the only
fallback when no native base is mapped. The static backdrop and chrome may be painted
while the named evdev device is still unavailable, but all selectable menu rows
remain hidden until input has opened. Only that interactive overlay and its
framebuffer barrier can publish first-frame readiness.

## Readiness contracts

The first frame, storage anchor, application contract and content session are
different boundaries:

- **First frame ready** means the menu is visible and input works.
- **Storage ready** means the first launcher has retained the final content and
  configuration tree; it does not gate the first frame.
- **Application contract ready** means the retained ROCKNIX profiles and links
  required to launch content have all been validated for the expected contract
  revision.
- **Content session active** means one selected provider owns its supervised
  process boundary. It must become empty before birdOS resumes the menu.

No later marker may be inferred from an earlier one.

The final-root recovery payload always carries
`/flash/bird/launcher-base.xrgb`, the exact 1,382,400-byte sparse native XRGB page
generated from the pinned source. Until inherited U-Boot frame reuse is proven
on the RG34XX-SP, the early initramfs carries the same native page at
`/opt/bird/launcher-base.xrgb`; its compressed-overlay ceiling is therefore
786,432 bytes. `BIRD_REUSE_UBOOT_FRAME=1` is accepted only with an external
hardware-verified contract byte-identical to the generated build contract. In
that verified mode the early payload omits the duplicate XRGB page and returns
to the retained 262,144-byte compressed-overlay ceiling. The final-root asset
remains present in either mode for recovery after content. No mode introduces
a runtime PNG or BMP decoder.
Current enforced budgets are 600,000 release / 660,000 profile bytes for the
final launcher, 610,000 / 670,000 bytes for the early launcher, 786,432
compressed early-overlay bytes with the native fallback or 262,144 bytes with
verified U-Boot reuse, 2,100,000 physical framebuffer bytes for a cold Phase 5A
base-plus-menu render, 500,000 bytes for a verified inherited-base menu overlay
and 65,536 bytes for a matched application return. The generated boot contract
separately records 345,600 logical pixels, 1,036,800 visible bytes, one
framebuffer page and 1,382,400 physical XRGB bytes.
The current generated catalogue additionally enforces host-test ceilings of
460,000 immutable string-pool bytes, 56 KiB of fixed-width logical records and
16 KiB for the path-order index. Exact binary and section sizes remain reported
benchmark outputs rather than brittle equality contracts.

## Failure and host-repair semantics

The active boot contract has one selected release. The release loader and
post-flash hook still verify the manifest, completion marker and every exposed
runtime byte. On failure they persist `bird-loader-failure.txt`, leave the
selector unchanged and stop. They never increment a retry counter, reboot, or
select another kernel or UI. Final-root launcher startup and unexpected-exit
failures likewise log once and stop; systemd does not restart that supervisor.

- No `KERNEL.fallback`, fallback extlinux selector, root fallback DTB, alternate
  UI, or release-scoped boot-attempt journal is installed.
- A kernel, initramfs, verification, or launcher failure returns the card to the
  host for evidence collection and a verified repair or redeployment.
- B navigates back inside nested launcher views. On the main page it returns
  the selection to `PLAY` with an ordinary dirty-row update and is intentionally
  absent from the footer legend. It does **not** retire the early owner, open a
  stock ROCKNIX frontend, count as a runtime failure or select the boot
  target.

## Acceptance boundary

The accepted v6.23 baseline includes early menu/input, asynchronous fixed storage,
cached games and media, Favorites, exact-page return, supported game/media
dispatch, system volume and brightness, charging display, suspend/wake,
global foreground exit and shutdown. It also includes the canonical
`/run/bird`, `/storage/roms`, `/storage/media` and Bird-owned persistence
namespace with direct fixed provider dispatch. The v6.23 hardening pass adds deployment,
fallback, readiness, supervision and persistence correctness around those
behaviors. The physical gate also accepts movie resume, internal-speaker audio,
ROCKNIX volume/brightness notifications, Y-button Favorites, native Menu+Start
for RetroArch and PPSSPP alongside Bird's Select+Start global exit, native and
translated Ports, fMSX, standalone PSP, OpenBOR, N64 audio and DraStic's
non-striped desktop-OpenGL presentation. Brightness exposes stable 5, 3 and 1
percent low ticks. Cold boot stores the rounded 10-percent starting level before
unblanking without a timed strike; suspend/resume still strikes the panel at its
measured 10-percent threshold for 50 ms and restores the exact saved dim value.

The content boundary reconciles audio state without blocking provider launch:
it reads the exact H616 CARD headphone jack and changes the independent MIXER
speaker switch only when the live route disagrees. The RG34XX-SP physical gate
accepts headphone-only output from that correction. Crack/pop transients at
codec activation remain deferred Stage 4 work. An explicit muted PipeWire
prewake was tested, reported success, produced no audible improvement and is
not part of the active path.

Kernel trimming, U-Boot timing, earlier LED/display assertion, emulator and
PortMaster performance, remaining provider cold-load work, final boot effects
and the hermetic-image/fallback-only legacy boundary remain roadmap work. Their
absence is not evidence that the active stock-root path is incomplete.

The first `dev-current` Stage 6 storage subtraction passed the broad physical
hardware gate. Its boot log recorded input ready at 1217 ms, usable frame at
1229 ms and storage ready at 3703 ms; those single samples are descriptive and
do not establish a timing promotion. The accepted fixed mount state first
avoided an unconditional remount plus three diagnostic children, then a second
physical gate accepted removal of the remaining success-path directory-creation
child and repair-only mount inventory. That returned boot logged input at
1219 ms, usable frame at 1239 ms and storage at 3744 ms while the stopwatch
remained below three seconds. The following bounded candidate replaced nine
unchanged-profile comparison/timing children and four fixed-Sway children with
shell reads while preserving volatile contract files and mismatch repair. That
code is included in the later physically accepted
`v6.23-20260810-080340` release. Its latest fixed-platform log spans
9.10--9.11 seconds and fixed-Sway reports 10.99 seconds.

The accepted application-readiness candidate changed only `999-export`. Its old
accepted-state validator launched twenty-one avoidable external helpers for fixed
profile comparisons, line checks, uptime extraction and unconditional setup.
That implementation was intentionally straightforward: `cmp`, `wc`, `grep`
and `cut` made the final trust gate obvious and easy to diagnose while the
independent producer contracts were still changing. It favored correctness and
debuggability over one-shot process cost. Once those tiny contracts became
fixed, retaining the same external parsing no longer bought useful safety.
The candidate performs those exact newline-terminated text validations with
shell reads, rejects partial/trailing records, and leaves repair, symlink,
atomic marker publication and failure semantics intact. On a fresh accepted
boot only one `readlink`, the marker `chmod` and atomic `mv` remain as external
children. It runs after the honest usable menu and targets queued-launch and
application readiness. The combined physical gate passed games, media,
PortMaster, shutdown and the broad behavior matrix. Boot `25e66c8c` logged the
visible input-ready menu at 1222 ms and storage at 3405 ms; the stopwatch stayed
below three seconds.

The first physical gate on that candidate exposed an independent PortMaster
battery failure. Upstream `pugwash` prefers `/tmp/battery.percent`, then reads
the generic power-supply sysfs capacity file directly and assumes either source
is immediately readable. birdOS's native power owner replaced the older stack
without publishing that compatibility cache. On boot `a546e57e`, the AXP717
capacity read twice returned `ETIMEDOUT`; the uncaught Python exception exited
PortMaster and a second launcher read replaced the displayed percentage with
unavailable. The bounded repair leaves provider bytes untouched: the PortMaster
handoff atomically publishes the last valid value already acquired by Bird's
power owner, while launcher return/resume prefers that cache and ordinary power
events retain it only when direct kernel reads fail. Two physical PortMaster
launches then logged `battery-cache percent=51`, exited without the prior
exception and returned to Bird with 51% still displayed.

Port payload saves and configuration
below `ROMS/Ports/<game>/` are excluded from development catalog fingerprints,
matching the embedded catalog's top-level Port-launcher authority.

Stage 6 now also has a host-proven no-change SYSTEM builder. A digest-pinned
arm64 container and dated Debian snapshot produced two byte-identical
1,211,060,224-byte SquashFS images from separate clean extractions. Their full
54,510-node inventories are identical to the shipping SYSTEM, including Linux
ownership, modes, timestamps, links, hardlinks and content. The repack digest is
`769edbb4522ae031129e5a07712b5529a7ec238735762c2d3d7ddb288e7e37ab`;
the sealed inventory digest is
`0714f306f480e40849efa722505d8ae9ddc2921ebf2629130be579629725f86f`.
This is reproducibility evidence only. It has not yet replaced the active
SYSTEM and makes no device timing, energy or behavior claim.

The bounded physical-parity candidate now consumes that exact repack without
baking Bird policy into it. The canonical updater stages the image under
`/storage/bird-data/Bird/runtime/<release-id>/ROCKNIX-SYSTEM`, verifies its
manifest size and digest, and only then activates the matching selector. The
previously selected SYSTEM remains untouched until activation; verified release
rotation removes its release-scoped image, while the one-time legacy
`MUOS/runtime/ROCKNIX-SYSTEM` input is retired only after the new selector is
committed. This is a no-content-change Stage 6 gate. It still requires the full
RG34XX-SP behavior and boot-parity test before acceptance.

That no-content-change gate passed in immutable release
`v6.23-20260810-032646`, clean source
`faca047b626c7cb13bb2414663742514d257c538`, manifest
`a9bfc96764b3e621ef52ec57989ce29ee52715ff8a5bf78525fb333458f7a85d`.

The following mask subtraction passed in immutable release
`v6.23-20260810-051204`, clean source
`bee2f26f6c53798c1e6455d6f2d66c2cd083e58b`, manifest
`b14b7a2552ede731712b0b9dbd1a25ebdc0d46c820a75bedab48cc8a36081a22`.
The broad hardware matrix was fully functional and the stopwatch remained below
three seconds. Five recent boot logs recorded input ready from 1218--1226 ms
and usable frame from 1221--1236 ms. These are descriptive parity samples, not
a promoted timing distribution. The accepted SYSTEM bakes sixteen fixed-device
systemd masks as standard `/dev/null` symlinks while HDMI and
Bluetooth-adjacent masks remain reversible runtime policy.

The following bounded SYSTEM candidate also bakes fourteen already accepted fixed
service/config files byte-for-byte. Two isolated full builds are identical and
the combined inventory delta proves exactly sixteen masks plus fourteen files.
Its SYSTEM digest is
`214ae075864fbe848f0fc6c31d4bec68778a111efb2ed1de78366446348d2af4`;
its size remains 1,211,060,224 bytes. `mount-storage.sh` removes the fourteen
matching pre-systemd bind mounts. It passed the broad hardware matrix in
immutable release `v6.23-20260810-080340`, clean source
`e039e1dfd84f4196e4c9c7c0ad798cde948ce305`, manifest
`6e59560198455dd68e3124f9aea3bb46bf749a46607d7a57541fd0941b3cc505`.
The stopwatch remained below three seconds; two returned boots recorded input
ready at 1219 ms, usable frame at 1225/1232 ms and storage signal receipt at
3384/3404 ms. These are descriptive samples.

The next accepted-state storage candidate removes five more post-menu child
processes: two directory creations now run only as repair, and the exact
two-line namespace authority is validated with shell reads instead of `wc`
plus two `grep` processes. Missing directories still repair and malformed,
reordered, truncated or extra namespace records still fail before mount move.
Its first `dev-current` build incorrectly used and closed file descriptor 3,
which the sourcing ROCKNIX init owns as `SILENT_OUT`; the menu survived in the
early launcher, but final-root preparation stopped, so storage, favourites,
content, controls, power and persistent logs never became available. Preserving
FD 3 with a private FD 9 did not clear the device failure. The second correction
borrows no descriptor: it uses the redirected `while read` pattern already
proven earlier in this exact BusyBox hook, while the host test still proves the
caller's FD 3 remains usable. During this development gate only, a failed
storage hook now records directly to p6 and watches the early launcher; after a
requested action exits the launcher, a logged three-second countdown forces
poweroff instead of requiring a reset. This candidate still requires the
complete physical behavior gate.

After the descriptor-free attempt also failed without returning through the
storage failure boundary, the next diagnostic build adds an unconditional
30-second watchdog as an independent early-initramfs process. It begins before
the storage hook, records a one-second countdown and final mounts/process/kernel
snapshot directly to p6 when available, syncs, and repeatedly requests forced
poweroff. Temporary in-hook stage markers identify the last completed storage
operation. This is diagnostic-only and must be removed after the fault is
localized.

The watchdog localized the actual stop before `mount-storage.sh`: at 2.19
seconds the development post-flash hook searched for
`Bird/runtime/dev-current/ROCKNIX-SYSTEM`, although `dev-current` intentionally
reuses its immutable production base SYSTEM. The fast workflow now specializes
two independent authorities: process/runtime files remain `dev-current`, while
the SYSTEM path names the recorded immutable base release. Development
verification and transaction tests require that exact split.

The corrected `dev-current` passed the returned broad hardware gate. Its log
identifies the development supervisor, input readiness at 1220 ms, usable-frame
readiness at 1223 ms and storage readiness at 3467 ms, followed by successful
games, Ports, music, books, movies, PortMaster, Favorites, suspend and shutdown.
On this healthy boot the unconditional diagnostic watchdog recorded only 29
and 28 seconds before successful `switch_root` retired it; it was never intended
to shut down a working final root. The follow-up removed that watchdog and the
eleven temporary p6 stage writes while retaining the actual immutable-base
SYSTEM fix, the five-child storage subtraction and the failure-only
three-second logged shutdown path.

That diagnostic-free build passed the next broad hardware gate. It recorded
input readiness at 1219 ms, usable-frame readiness at 1225 ms and storage
readiness at 3408 ms. The actual base-SYSTEM fix and five-child subtraction are
therefore accepted for continued development; those individual timings remain
descriptive rather than a distribution claim.

## Accepted v6.23 evidence

The accepted human promotion binding is clean source
`e039e1dfd84f4196e4c9c7c0ad798cde948ce305`, release
`v6.23-20260810-080340`, manifest
`6e59560198455dd68e3124f9aea3bb46bf749a46607d7a57541fd0941b3cc505`,
device contract
`1664a3778abcd3687865a82fd28bba5b468f6c3c7e9a46bf90f7c3acb1e08162`
and catalogue
`9795aae6baddc292f5d9954a444656e303db305c639284f16eb10288c41f1f93`.
The v6.23 baseline completed these gates:

1. Build from the pinned inputs and verify every release file through
   `deploy-manifest.tsv`.
2. Inject updater process termination before, during and after release staging
   and selector publication, then prove the selected path names only a complete
   release. This host test does not substitute for bootloader-level power-loss
   recovery.
3. Exercise failed application export, launcher pre-frame exits, content that
   forks/reparents or ignores TERM, auxiliary-descriptor failure, over-limit
   catalogue paths and shutdown-checkpoint failure.
4. On the RG34XX-SP, repeat early input/storage timing plus the broad game,
   media, Ports, volume, brightness, suspend/wake, global-exit and shutdown
   suite.
5. Exercise the automatic attempt threshold and verify that the preserved
   clean-root kernel boots after the verified fallback selector publication.

The macOS suite drives the real registration dispatcher and cleanup functions
with fault-injected manager states. The device gate validates the required
user-visible behavior and managed exit paths. Future changes to Linux systemd
scope/cgroup ownership still require an on-device adversarial check in addition
to the host suite.

## Historical material

The rest of the repository records many deliberately superseded experiments.
Start at [`docs/history/README.md`](docs/history/README.md) before using them.
Historical files may document a result accurately for their own stage while no
longer describing the active runtime. When history and this document disagree
about what currently builds or boots, this document and the canonical build
graph win.
