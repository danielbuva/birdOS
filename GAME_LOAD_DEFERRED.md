# Deferred cold-game launch optimization

This track is deliberately parked until the current boot, userspace, storage,
audio and firmware-image roadmap is complete. The fixed direct bridge remains
installed because it is smaller, deterministic and hardware-functional, but
its perceived cold-load improvement was not meaningful enough to keep game
startup on the active critical path.

## What the measurements proved

The ROM partition and compatibility runtime were already ready before every
profiled request. The launcher needed about 0.1 seconds to release framebuffer
and input ownership, so neither cached-index browsing nor storage mounting
caused the observed wait.

| Phase | Cold | Warm | Finding |
| --- | ---: | ---: | --- |
| Generic SDL/controller setup | 1.63 s | 0.04 s | Repeated scan of general controller data; removable with the fixed muOS-Keys map. |
| Remaining shell/config work | 0.20 s | 0.20 s | Rewrites constant RetroArch resolution, map, kiosk and threaded-video files on every launch. |
| RetroArch exec to identity color-stage marker | 5.67 s | 1.79 s | Cold executable, shared-library and core page-in dominates. |

The direct bridge removes the first two generic phases, embeds the exact
RG34XX-SP SDL row, hardcodes the fixed 720x480/no-rotation policy, omits control
swap detection and does not preload `libmustage.so`. Hardware testing confirmed
controls, sound, volume, gameplay, saves/return behavior and shutdown, but the
cold game still felt slow.

The remaining general RetroArch binary is 12.4 MB and directly requests 24
shared libraries. Its dependency list includes FFmpeg codec/device/format,
scaling and resampling libraries, ASS subtitles, FriBidi, Fontconfig, FreeType,
libusb and other capabilities outside the fixed experience. The Flycast core
used for the controlled cold/warm comparison is another 22.4 MB. This is real
cold I/O and relocation work, not a fixed sleep that can simply be deleted.

## Resume-later checklist

1. Reproduce the exact RetroArch 1.22.2 build and record its current configure
   flags, source revision and transitive dependency sizes.
2. Build a fixed RG34XX-SP RetroArch without video decoding, subtitles,
   translations, font discovery, USB input and unused menu/network features.
3. Keep only the video, udev/direct-input, ALSA/PipeWire compatibility, save
   state and command interfaces proven necessary by the selected cores.
4. Add a low-overhead first-emulated-frame marker rather than using the color
   overlay as a proxy.
5. Benchmark cold and warm GBA/SNES, Flycast and one standalone emulator so
   frontend cost and core cost are separated.
6. Compare a smaller binary against selective `readahead` and a resident
   process. Prefer removing bytes and dependencies; do not hide waste with
   unconditional boot-time prefetch unless interaction measurements justify it.
7. Remove verbose RetroArch logging from production after exact failure, save
   and return requirements are captured.

The installed fixed bridge source remains in `launcher/lr-fixed.sh`; the
behavior-preserving measurement wrapper remains in `launcher/lr-profiled.sh`.
