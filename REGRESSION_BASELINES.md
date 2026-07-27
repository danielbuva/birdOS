# birdOS regression baselines

This file records accepted device behavior and the code or provider conditions
known to affect it. A candidate is not a new baseline until the listed physical
checks pass. When a regression is found, record both the breaking condition and
the restoring condition here, even when the final fix is deferred.

## Accepted gate: stock-root v6.23 (2026-07-26)

Canonical deploy-manifest digest:
`e441f9c2755173353a9d29969807c2a05411240b7e9d2a1d18ed099d3c91b4d2`.

| Area | Accepted behavior | Known break condition | Restoring condition / invariant | Physical check |
|---|---|---|---|---|
| Movies | Reopening media resumes from the clean-exit position. | MPV launched without a persistent `save-position-on-quit` policy. | `run-content.sh` installs the Bird resume policy without replacing user MPV settings. | Play past 30 seconds, exit, reopen, confirm resume. |
| Brightness + lid | Manual control includes stable 5%, 3% and 1% low-end ticks; lid close/open restores each exact lit raw level; zero is display-off only. | Low PWM values remain visible once running but cannot start this panel after DPMS. The 2026-07-26 physical gate proved raw 25, 75 and 125 fail to wake while raw 250 succeeds. Any late generic write or saving zero also breaks restoration. | `bird-fixed-controls` maps the low end to raw 125/75/25 on max 2499. Wake powers the panel, strikes at the proven 10%/raw-250 threshold for 50 ms, then restores the exact saved tick. | Test raw 25, 75, 125 and 250 through lid close/open; all must return to their saved visible level. |
| Volume/brightness OSD | Dedicated volume and Menu+volume show the ROCKNIX OSD while applying the change. | Bypassing `/usr/bin/volume`, failed fixed-controls dispatch, or compositor ownership changes. | Fixed controls must dispatch the stock volume helper; collect control log if OSD remains absent. | Test tap and hold in menu and content. |
| Global audio | Internal speaker is audible in every application at the saved numeric volume. | WirePlumber route state can persist `mute=true` independently from `audio.volume`; the 2026-07-26 card image proved exactly this silent-but-healthy graph. | Bird reapplies the saved ROCKNIX volume and explicitly unmutes the default sink at application readiness, before each launch, and on every global volume action. Diagnostics record effective sink volume and mute. | Cold boot, test one RetroArch game, PSP, a Port, music and a movie; then tap both volume keys. |
| RetroArch exit | Native Menu+Start remains available; Bird global Select+Start exits all content. | Global input ownership or an exit helper that sends RetroArch menu input before terminating. | Fixed controls do not grab the gamepad; Select+Start terminates only the managed content boundary without replacing native application bindings. | Test both chords in two RetroArch cores and PPSSPP. |
| Favorites | Footer names the physical Y button and Y toggles state persistently. | H700 event code `BTN_WEST` is the physical X button even when a generic logical label says Y. | Launcher footer uses `Y`; H700 event mapping uses physical Y (`BTN_NORTH`). | Add/remove, reboot, confirm persistence. |
| Ports | Native PortMaster launchers and the retained Stardew launcher run without modifying originals. | Dispatching the old `/mnt/mmc/ROMS/Ports` copy or applying muOS paths to the native ROCKNIX provider. | Native launchers run from `/storage/roms/ports`; Stardew alone uses a volatile provider-specific translation. | Test a native PortMaster port and Stardew Valley. |
| MSX | Multiple cartridges reach gameplay and exit normally. | ROCKNIX `bluemsx_libretro.so` segfaults after initialization (observed exit 139). | v6.22+ maps MSX to release `fmsx_libretro.so` and supplies its six BIOS ROMs. | Test at least four titles. |
| PSP | PPSSPP displays gameplay, retains its native Menu+Start menu and exits through Bird's Select+Start chord. | Provider/config/display or global-input ownership changes. | Keep standalone `ppsspp-sa`; fixed controls never grab or rewrite native app input. | Test Burnout and one second title. |
| N64 audio | Stable audio at baseline titles. | RetroArch core latency, sync, threaded-video, governor or audio-route changes. | Preserve the accepted v6.23 core/config and fixed global audio route before tuning. | Test the same two baseline titles. |
| Nintendo DS display | DraStic output has no striped/column-corrupt effect. | DraStic using its GLES2 presentation path; this failure was previously reproduced as corrupt columns. | Use DraStic's desktop OpenGL path with Panfrost, the restoring condition established in the v5.4 hardware work and preserved by the accepted stock-root provider. | Test the same title and orientation used for acceptance. |
| OpenBOR | Pack reaches gameplay and Select+Start exits. | Provider binary/data-path or managed-lifetime changes. | Preserve the accepted OpenBOR 7530 payload and managed boundary. | Test Castlevania Dracula's Legacy. |

## Change discipline

For any change touching `run-content.sh`, fixed controls, suspend, Sway, emulator
payloads, RetroArch configuration, or writable-provider migration:

1. Name every affected row in the change notes.
2. Preserve the last accepted provider/config artifact unless replacement is
   intentional and independently reversible.
3. Run the host contract suite, then repeat the row's physical check.
4. Record the observed breaking and restoring revisions or conditions here.
