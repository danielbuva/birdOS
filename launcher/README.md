# birdOS launcher

**Status:** [`bird-launcher.c`](bird-launcher.c) is active, but most of this
document is the chronological proof record from earlier muOS and clean-root
stages. The authoritative stock-root v6.23 compile flags, process ownership,
readiness boundaries and content handoff are documented in
[`ACTIVE_PATH.md`](../ACTIVE_PATH.md) and implemented by
[`kernel/rocknix/build-stock-root-compat.sh`](../kernel/rocknix/build-stock-root-compat.sh).

The active build compiles this source twice: once for the retained initramfs
launcher and once for final-root recovery. It does not use the committed
relocatable object or the old `S03birdlauncher` muOS installer. The original
initramfs process remains the normal menu/input owner across `switch_root`; the
final-root supervisor adopts it, monitors child exit and first-frame readiness,
and starts a replacement only when required. Content executes outside the
launcher inside a separately supervised session boundary.

On nested pages, B navigates back. On the main page, B refreshes the current
Bird frame in-process and never retires the initramfs framebuffer/input owner.
It neither opens the ROCKNIX frontend, counts as a runtime failure nor selects
the clean-root boot fallback. The active UI labels that action `B REFRESH`.
Action 13 remains accepted only as a compatibility handoff from an older
already-running launcher. Historical passages below that describe “B STOCK”,
`S03birdlauncher`, muOS wrappers or stock frontend handoff do not define the
active behavior.

## Active visual and asset architecture

The current 720x480 visual architecture is inspired by Mister Menu's ES-DE
presentation, implemented entirely by the freestanding launcher rather than by
ES-DE, a compositor or a widget toolkit. The home screen uses a narrow vertical
rail labelled `HOME` and leaves the cream top bar battery-only. Nested views
reuse the rail for their local label and add paths such as
`PLAY / SYSTEMS / <SYSTEM>` to the top bar, with the vertical battery retained at the
right. The backdrop is covered by a fixed opaque burgundy content panel; there
is no runtime alpha blend. The centered 400x288 content frame matches the
reference panel's 1.39 width-to-height ratio while retaining nine complete
32-pixel rows. Fixed labels use 2x2 bitmap cells, the spaced vertical rail uses
3x3 cells and selectable rows use square 3x3 cells. Controls are drawn directly
over a restored wallpaper strip, with no opaque footer panel or visible
diagnostic line.

The source artwork is the pinned 720x480 RGB cat-and-stairway crop at
[`firmware/assets/bird-launcher-backdrop.png`](../firmware/assets/bird-launcher-backdrop.png)
(SHA-256
`3fdea84fe0c149378db32d1849e55b3fede22c74a613544810be880f48fdb9d3`).
[`firmware/generate-launcher-bootlogo.py`](../firmware/generate-launcher-bootlogo.py)
validates and decodes it only at build time, composites the fixed chrome for
U-Boot, then deterministically emits the frame-zero BMP, boot-frame digest
contract, a full native XRGB8888 verification page and a fixed-region native
wallpaper asset. The verification page is 720x480, top-down, 2,880-byte stride,
one page at offset 0:0, with bytes in `B,G,R,X` memory order. The shipped asset
packs only the nine wallpaper regions not hidden by the opaque top bar, menu
container and three-pixel menu shadow. It has no runtime header or parser; the
launcher copies the generated regions through fixed offsets and strides.
The PNG is the only editable wallpaper source in the repository. Neither it nor
the BMP enters the handheld image or a launcher runtime decode path.

A replacement wallpaper should use the same exact input contract: 720x480,
8-bit RGB, non-interlaced, no alpha, with sRGB color intent. The selected file
is pinned by SHA-256 and converted to native XRGB at build time. A continuous
loop is deliberately not part of the active architecture: each uncompressed
frame is 1,382,400 bytes and even 6 fps would store about 8.3 MB/s while adding
a periodic idle wakeup. Multiple build-time frames remain technically possible,
but animation stays deferred until it has explicit binary, framebuffer-write
and battery budgets.

Final-root recovery always installs the fixed-region native asset as
`/flash/bird/launcher-base.xrgb`: exactly 852,848 bytes, with SHA-256
`e6f9ca8ef4100cdf384bc2f8f3f7b902bc83cee6c4bc36e82fbc666328b382de`.
Until `BIRD_REUSE_UBOOT_FRAME` has a byte-identical hardware-verified contract,
the early initramfs carries the same asset at
`/opt/bird/launcher-base.xrgb` and has a 786,432-byte compressed-overlay
budget. A verified reuse build would omit that early duplicate and retain the
262,144-byte compressed-overlay budget; it does not remove the final-root
recovery asset. At startup the launcher copies the fixed regions and draws
opaque chrome into the skipped areas before one
framebuffer barrier. It can do that before evdev is ready, but withholds every
selectable row until the named input has opened, then draws the interactive
overlay and publishes first-frame readiness.

The wallpaper costs no additional framebuffer traffic versus the preceding
full-page source: both paths write the same 1,448,860 physical bytes for the
cold base-plus-menu render. Why before: a full 1,382,400-byte page made the
source layout identical to the framebuffer and kept the first implementation
simple. Why change: 529,552 opaque bytes were never read by the nine-region
copy path. The fixed-region asset removes them, is 852,848 bytes raw and
compresses to 387,374 bytes by itself versus 403,990 bytes for the preceding
page. The deployed profile early-overlay size is reported by each build. Its measured cold base-plus-menu render remains 1,448,860
physical framebuffer bytes. These are byte/storage measurements, not a claim
of measured device boot latency.

## Historical direct-framebuffer launcher proof

`bird-launcher.c` is an intentionally freestanding AArch64 Linux program. It
uses direct kernel syscalls and has no libc or dynamic-library dependencies.
The macOS build produces a relocatable object; the RG34XX-SP's own GNU linker
creates the final static executable during user-init.

This is a functionally proven prototype, not the final optimized launcher.
Architectural boot-path work has priority. The first idle-efficiency pass has
replaced the 4 ms input poll and raw-event logging with a blocking `ppoll` on
the fixed evdev descriptor. A 50 ms timeout exists only until ROM storage is
ready; ordinary menu idle then generates no launcher timer wake-ups. Later
profiling targets framebuffer write volume, redraw granularity, catalogue
representation, code size and supervisor handoff overhead. Battery efficiency
outranks memory reduction when those trade off.

The stock-root v6.9 milestone first kept the original initramfs launcher alive
through the mount move as the sole input owner. Open directory descriptors
anchor its runtime, evdev, power and storage operations to the moved mounts;
the systemd supervisor sleeps in a separate 896-byte static pidfd waiter until
that original Bird actually exits. Bird also
reads the fixed AXP717 `capacity` value and updates the upper-right percentage
only on kernel power-supply uevents. Charging changes therefore add neither a
polling interval nor a resident battery helper. That value is the PMIC's raw
fuel-gauge register, not a launcher estimate, and still needs device-specific
calibration.

The calibration runs were deliberately late and temporary:

1. Stock muOS reaches its normal screen.
2. The proof stops stock after three seconds.
3. The proof draws its own 720x480 menu and opens evdev devices directly.
4. The fourth proof captured both Linux evdev events and `/dev/input/js*`
   joystick button/axis events for every remaining built-in control.
5. A timeout ended each capture automatically.
6. Stock muOS restarts automatically.

Input-calibration results are written to
`/mnt/mmc/MUOS/bespoke-launcher/proof-v4-remaining.log`. A
successful run gives the exact framebuffer format, stride, input device names,
first-frame uptime and exit reason needed for the early-boot version.

The first early version started after udev and produced a usable custom screen
in 7.28 seconds by stopwatch (5.581 seconds of kernel boot time). Its launcher
rendered in 19 ms, while the stock `mufbset` helper consumed about 1.65 seconds.

The direct-event version removes that helper and the joystick compatibility
path. `S03birdlauncher` starts before udev, and the binary waits only for the
fixed `/dev/fb0` and `/dev/input/event1` nodes. It reads the RG34XX-SP controls
straight from evdev while stock initialization continues behind it. B hands
off to stock after the system-ready marker. D-pad navigation wraps so every
direction press visibly moves.

The verified direct build starts at 2.269 seconds of kernel uptime with input
already usable and completes its first frame at 2.289 seconds. The corresponding
LED-on stopwatch time is approximately four seconds.

## Real embedded library catalogue

`generate-launcher-catalog.py` inventories the mounted card and converts every
supported ROM path into a C header compiled directly into the launcher. The
launcher never scans storage at boot and can browse cached names before
`/mnt/mmc` is mounted. A narrow 50 ms readiness probe reports when
`/mnt/mmc/ROMS` appears; selecting a cached title tests only that exact path.

The current inventory contains 5,984 launchable files across 27 populated systems.
It excludes AppleDouble files, hidden files, artwork directories, PNG artwork,
Windows thumbnail databases and other metadata. The generated TSV also records
the current media library: 51 Listen items, five Read items and eight Watch
items. v14 compiles both the game and media records into the executable; neither
catalog is read from the card or regenerated during boot.

Regenerate the complete cache and stage it on an inserted card by double-clicking
`Rebuild birdOS Library.command` on the Mac Desktop, or run:

```sh
./rebuild-library.command /Volumes/BIRD-DATA
```

The generator can still build a narrow diagnostic manifest by passing it as the
second argument to `generate-launcher-catalog.sh`. The full system view is now
a fixed nine-row paged list with L1/R1 paging, so all 27 systems remain visible.

## Fixed game handoff

Selecting a ready title writes a four-line request containing launch kind, exact
core, display name and exact ROM path, then exits cleanly to release framebuffer
and evdev ownership. `S03birdlauncher` waits for the already-dispatched startup,
PipeWire socket and fixed controller map. Libretro systems use the proven
`lr-general.sh` bridge with the system's compiled core; PSP, Ports, NDS and
OpenBOR use their dedicated muOS wrappers.

- SNES: `snes9x_libretro.so` through `lr-general.sh`
- PSP: standalone PPSSPP through `ext-ppsspp.sh`
- Ports: executable script through `ext-general.sh`
- NDS on the accepted vendor kernel: standalone DraStic through
  `ext-drastic.sh`
- NDS on source-kernel compatibility v4: pinned melonDS through the existing
  `lr-general.sh`/RetroArch policy (the vendor DraStic JIT traps there)
- OpenBOR: standalone OpenBOR 7530 through its optional package wrapper

The supervisor waits for the game process, records its result, and starts the
custom launcher again without starting the stock frontend or calling `mufbset`.
This keeps the proof narrow while retaining muOS's emulator configuration,
controls, audio setup, saves, and emulator exit behavior.

The hardware proof passed for all three launch paths: SNES through RetroArch,
PSP through standalone PPSSPP, and a native Port. Games were fully playable
with audio and the device volume controls, and each exited directly back to the
custom launcher. The measured interval from game-process end to the next first
launcher frame was 27--29 ms.

## Cold libretro launch profile

The static-root-PID-1 verification exposed the next interaction bottleneck.
ROM storage was ready by 4.05--4.50 seconds and the launcher handed each request
to the content bridge in about 0.1 seconds, but the first generic libretro
launch did not reach its RetroArch stage for another 5.78--7.40 seconds. A
second libretro launch during the same boot reached that stage in 2.19 seconds,
showing a cold general-wrapper/page-cache cost rather than a ROM-mount wait.

`lr-profiled.sh` is an otherwise behavior-identical copy of the exact 719-byte
muOS 2601.1 `lr-general.sh`. Temporary monotonic markers surround function-file
loading, logging, fixed home lookup, stage overlay, SDL setup, foreground state,
RetroArch configuration rewriting, control swapping and the final process
exec. The one-shot installer accepts only the exact stock wrapper SHA-256 and
backs it up before installing this diagnostic. The resulting measurements will
define a minimal fixed libretro bridge; the profiler is not a production
dependency.

The hardware profile split the cold first launch as follows: function loading
and fixed home lookup were 0.01 seconds, generic SDL/controller setup was 1.63
seconds, remaining foreground/config/swap work was 0.20 seconds, and the period
from RetroArch exec to the identity color-stage message was 5.67 seconds. On
the second launch, SDL setup fell to 0.04 seconds and exec-to-stage fell to 1.79
seconds. This is a cold file/dependency cost, not an arbitrary delay.

`lr-fixed.sh` was the installed fixed bridge. It directly exported the measured
RG34XX-SP values (720x480, no rotation, retro ABXY mapping, fixed muOS-Keys SDL
row), wrote the foreground owner, and executed RetroArch. It removed the
controller-database scan, per-launch configuration rewrite, swap detection and
`libmustage.so` preload; the latter only reported identity brightness, contrast,
saturation, hue and gamma values. The prerequisite RetroArch files were already
created by the verified generic path and are checked by the one-shot installer.

Hardware testing confirmed the bridge retained gameplay, controls, audio,
volume, save/return behavior and shutdown. Perceived cold timing remained slow,
because the dominant work was the oversized generic RetroArch dependency graph
and core rather than this wrapper. The historical profile is preserved in
[`docs/history/GAME_LOAD_DEFERRED.md`](../docs/history/GAME_LOAD_DEFERRED.md);
it does not describe the active stock-root dispatcher.

## Native system actions

The launcher uses the same narrow exit-code handoff for its remaining system
actions. Shutdown calls muOS's proven poweroff path directly, without entering
the stock frontend. Input Tester action 15 directly runs the static
framebuffer/evdev tester, then restores the saved launcher frame and exact Tools
selection by contract. It drains but does not count its first 400 ms of input,
so the A activation cannot pre-complete its own test; a one-second L1+R1 hold
clears the session and repeats that guard. Its 29/29 RG34XX-SP gate passed. It
starts no compositor, audio graph or network service. PortMaster
waits for the normal audio/controller runtime,
loads and connects the RG34XX-SP network only when selected, runs PortMaster,
then disconnects services, unloads the Wi-Fi device, restores launcher ownership
and redraws the custom menu. Network setup therefore adds no work to boot.

Both hardware tests passed: PortMaster connected on demand and installed ROTA,
existing games still launched, and Shutdown powered the device off directly.
The following boot entered the launcher at 2.307 seconds and finished its first
interactive frame at 2.326 seconds.

## Persistent library state

The v6 proof added ROTA to the five-title embedded catalog and turned Favorites
into a real view. Y toggles the selected title. Favorites are stored as exact ROM
paths in an atomically replaced text cache, so rebuilding or reordering the
compiled catalog cannot silently point a favorite at the wrong game. The cache
loads asynchronously only after storage is ready and never delays first frame.
Each launch also atomically records the exact most-recent path for the later
History/Resume decision. Per-boot launcher logs are archived by kernel boot ID
so a later shutdown no longer overwrites evidence from a PortMaster or game run.

The hardware proof persisted ROTA across a reboot, launched it from Favorites,
removed other favorites correctly, and recorded Goof Troop as the latest path.
The larger build still entered at 2.256 seconds and drew its first interactive
frame at 2.276 seconds. Favorites loaded at 3.677 seconds, after first frame and
only 40 ms after the ROM root became visible.

## Nonblocking boot-effects proof

The first boot process draws the complete interactive menu before beginning a
procedural accent line. Input ends the animation immediately, and game returns
do not replay it. No images, decoder, timer service, compositor or new launcher
library is involved.

`generate-boot-sound.py` deterministically produces a 320 ms, 48 kHz, 16-bit
mono WAV. The supervisor waits in parallel for the normal system-ready marker,
PipeWire socket and exact asset path, then uses muOS's existing audio player. It
cancels the pending sound on game, PortMaster, stock or shutdown handoff. This
first audio proof deliberately preserves the known-good PipeWire setup; a later
profile will decide whether replacing the player is worth its dependency cost.

The v7 hardware run kept first frame at 2.275--2.356 seconds, proved input skip,
played the chime normally, and cancelled it when a game was opened. It also
exposed two useful refinements: the later saved-brightness restore visually
split the line, and `mpv` remained alive for roughly 4.7 seconds to play a
320 ms file.

The v8 proof leaves the menu immediately usable but holds decorative motion
until the device-start brightness case emits an exact readiness marker. It then
redraws once at the final brightness and runs a shorter 1.6-second accent. The
sound wrapper prefers `pw-play`, then `aplay`, with the proven `mpv` path only as
a fallback; logs record the selected player and total lifetime. Hardware logs
showed that `pw-play` saw the PipeWire socket before a target sink existed,
failed after roughly 2.2 seconds, and only then invoked `mpv`. That explained
why the chime arrived after the animation.

The v9 build removes brightness handling from the boot experience rather than
choosing a card-side percentage. `device/start.sh` no longer performs its late
saved-brightness restore, so the display-handoff brightness remains stable
until the user changes it manually. The 1.6-second animation starts with the
first interactive frame again. Input still intentionally completes and removes
the decorative animation immediately; this is an explicit interaction policy,
not an accidental repaint side effect. The sound wrapper invokes the proven
`mpv` path directly, eliminating the known failing-player delay while keeping
game-launch cancellation.

## Critical interactive-menu phase

The current performance phase deliberately removes the proof animation and
MPV chime from the active boot path. They demonstrated the intended policy but
are not part of first-frame measurement; final animation and direct audio will
return only after the earliest interactive menu point is established.

The accepted vendor path creates `/run/muos/bird-first-frame-ready` immediately
after its framebuffer write barrier because its fixed input is already open.
The source-kernel v3 path separates visibility from usability: it paints as
soon as `/dev/fb0` is mapped, then publishes the same marker only after the
named `H700 Gamepad` opens. Thus missing input can no longer retain the boot
logo, but also cannot produce a false interactive measurement or cancel the
candidate watchdog. The fixed sysinit patch dispatches the launcher before all
asynchronous observers and general init services, waits only for that exact
marker, then continues initialization. `S02rgb` is skipped because
it consistently costs about 40 ms and returns failure on the RG34XX-SP. Early
entropy remains enabled after the first frame because prior hardware tests
proved that deferring it creates multi-second CRNG/audio stalls.

The next staged proof moves the same supervisor ahead of `rcS`. A small BusyBox
inittab entry runs `bird-earliest-ui.sh` immediately after essential mounts.
The supervisor refuses a duplicate start, so the later instrumented sysinit
entry becomes a no-op when early launch succeeds. If the helper or launcher
fails, BusyBox continues into normal `rcS`, which still contains the proven
launcher path and stock-frontend recovery.

## Permanent launcher shell

The v10 build removes the proof's two-minute automatic handoff to stock. The
launcher now remains the permanent shell until the user launches content,
selects a system action, or explicitly presses B on the main menu for recovery.

Hardware testing also proved that the apparent late display repaint was the
launcher's own ROM-readiness callback. Storage and Favorites became ready at
3.69--4.40 seconds and `probe_storage()` unnecessarily called `draw_screen()`.
The callback now changes state and logs readiness without drawing. The next
user action naturally renders the current state, so background storage work
cannot overwrite the foreground or interrupt unrelated visual effects.

The ROCKNIX stock-root path now keeps the first initramfs launcher as the
permanent menu owner across `switch_root`. File operations use retained
directory descriptors instead of resolving through that process's old root.
V6.9 physically proved uninterrupted input but showed that storage could be
mounted and moved between two 50 ms probes. V6.10 therefore acknowledges both
the content and config descriptors before init may move the mount. This is a
readiness check for storage ownership, not a dependency of first paint or
input.

Stock-root v6.21 also treats launcher recovery as a product invariant. Both the
initramfs and final-root binaries retain the current view in the volatile
16-byte record after navigation, and input discovery covers `event0` through
`event31`. A transient device re-enumeration or process recovery returns to the
same highlighted screen; reboot still clears `/run` and intentionally begins
at Home.

## Real-cache deployment

The v11 build replaces the five-title proof with the real 5,953-title card
inventory and carries a core assignment beside each system. A content-addressed
revision file covers the launcher object, supervisor and deliberately added
cores. User-init links a new payload only when that revision changes, which
makes repeated Mac-side cache rebuilds safe and avoids relinking unchanged
catalogs. Hardware testing kept first frame at 2.334 seconds and stopwatch boot
at approximately four seconds even with the full embedded inventory. The first
boot after a rebuild installs the revision; the following boot uses it from S03.

## Exact game return and requested cores

The v12 launcher writes a 16-byte volatile UI record before a game handoff. It
contains only the current view, system and highlighted row. The next launcher
process consumes and deletes that record before its first draw, restoring the
exact Games or Favorites screen rather than returning to Home. Because the
record lives under `/run`, a real reboot always starts cleanly at Home.

The six completely failing test systems had three distinct causes. Game &
Watch and MSX were assigned to cores omitted by the base image. The PICO folder
contains PICO-8 carts, but v11 had incorrectly treated it as Sega Pico content.
v12 embeds the correct PICO-8 assignment and stages the official AArch64
`gw_libretro.so`, `bluemsx_libretro.so` and `fake08_libretro.so` cores. Game &
Watch and PICO-8 should therefore be complete. The Mac rebuild script also
copies the user's existing `$HOME/Games/bios/Machines` and `Databases` trees,
which completes blueMSX without putting BIOS data in this project or on the
boot path.

The other failures are not catalog problems: Nintendo DS lacks the optional
DraStic payload, OpenBOR lacks its optional emulator and launch wrapper, and
NAOMI's Flycast core reported a missing `naomi.zip` BIOS. The rebuild script now
copies the user's verified `$HOME/Games/bios/dc/naomi.zip` into the card's
Flycast system directory. Nintendo DS and OpenBOR remain separate optional
payload tasks rather than reasons to add boot-time scanning or fallback logic
to the launcher.

## Fixed-device optional systems and Stardew runtime

The v13 payload completes the two remaining catalog systems without installing
the generic package contents. Nintendo DS receives only DraStic, RG libraries,
the 720x480 layout and its runtime data; legacy DraStic, unused libretro cores,
TrimUI libraries, non-English translations and other screen layouts are
omitted. OpenBOR receives only build 7530 and its two muOS scripts. Its mutable
userdata points to `/mnt/mmc/MUOS/save/openbor` rather than living in rootfs.

The successful Port tests also exposed a game-specific Stardew Valley failure:
the official PortMaster script tried to mount a missing 250 MB Mono runtime,
then failed because `mono` did not exist. The Mac rebuild script verifies and
stages the official runtime from `$HOME/Games/runtimes`, and installs a fixed
muOS/RG34XX-SP-only Stardew wrapper with explicit runtime failure handling and
no irrelevant `systemctl` cleanup call. Neither optional emulators nor the Mono
runtime are inspected during normal boot.

## Fixed home hierarchy and native media handoff

The Home screen is the product structure rather than a diagnostic menu:
`PLAY`, `LISTEN`, `READ`, `WATCH`, `TOOLS`, and `QUIT`. Play contains Systems
and Favorites. Tools contains the direct Input Tester before on-demand
PortMaster. The tester displays all 17 gamepad controls, both analog sticks,
volume, power and rumble; Menu triggers a short vibration and holding B exits.
It drains but does not count the first 400 ms, and holding L1+R1 for one second
clears the session and repeats that guard. It blocks in `ppoll` when idle and
redraws only changed controls. Its 29/29 device gate passed. Quit contains
Reload, Reboot and Shutdown. Listen, Read and Watch contain
the first directory below their media root as a category, followed by exact
cached files. Read accepts EPUB and PDF and routes the exact selected file to
the installed KOReader PortMaster application.

The real card currently compiles two Listen categories with 51 audio files, one
Read category with five EPUB/PDF books, and one Watch category (`MOVIES`) with
eight MP4/MKV files. Every selection writes the same four-line content request
used by games. Audio/video is dispatched through ROCKNIX's existing MPV wrapper.
KOReader uses a session-specific transformed launcher under `/run/bird`; the
installed Port script, application archive and books remain untouched. Its
first launch can resume an incomplete extraction, verifies required files, and
opens the selected book rather than a directory. The volatile exact-return
record restores the selected media row after either provider exits and returns
to the Tools/PortMaster row after PortMaster exits.
