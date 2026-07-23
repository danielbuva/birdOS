# Bird clean root

This directory is Bird's first permanent-root userspace. It deliberately does
not import muOS startup scripts or application wrappers.

The boot split is:

1. The static first init mounts only kernel filesystems, loads the exact H700
   input module and starts the static launcher supervisor.
2. The launcher paints and opens direct input. This is the usability gate.
3. The permanent static PID 1 starts `post-frame.sh` independently.
4. Post-frame work mounts p6, starts the separate global-controls process,
   warms Panfrost and mounts the pinned ROCKNIX SYSTEM image read-only.
5. Bird bind-mounts only live kernel interfaces, writable `/tmp` and p6 into
   that runtime. It publishes one fixed H700 libudev record; no udev daemon,
   rule scan, hardware replay or hotplug worker is started.
6. A fixed six-control initializer programs the H616 DAC, Line Out and speaker
   after the menu; no UCM, PipeWire or audio daemon is started.
7. `run-content.sh` consumes only the launcher's four-line request and runs a
   native application with its matching core, configuration baseline, loader
   and libraries inside the read-only runtime.

Files:

- `supervisor.sh`: keeps the launcher alive and dispatches content or shutdown.
- `post-frame.sh`: prepares storage, GPU, runtime and controls after usability.
- `run-content.sh`: Bird-owned native application/core policy.
- `retroarch-append.cfg`: the small fixed RG34XX-SP override to native defaults.
- `h700-gamepad.cfg`: the one exact RetroArch map, with Select+Start as exit.
- `h700-sdl-gamecontrollerdb.txt`: the one exact SDL controller record.
- `input-metadata.sh`: publishes `ID_INPUT_JOYSTICK=1` for the built-in pad.
- `audio-init.sh`: programs the one fixed H616/RG34XX-SP speaker route.
- `content-performance.sh`: records the native CPU/GPU policy at application
  boundaries without writing clock controls.
- `portmaster-control.txt`: the fixed Bird adapter for installed Port scripts;
  it replaces generic CFW/device probing only inside the runtime view.
- `mpv-input.conf`: fixed movie controls; dedicated volume keys remain global.
- `exit-content.sh`: one process-group Select+Start contract for every app and
  helper it starts.
- `volume.sh`, `suspend.sh`, `shutdown.sh`: fixed device lifecycle operations.

Native RetroArch inherits its matching ROCKNIX configuration and H700 frame
pacing but overrides the fixed 720x480 panel mode, input profile, save paths
and direct ALSA endpoint. Mesa is not forced to `panfrost`: its native sun4i
KMSRO path pairs display `card0` with Panfrost `renderD128`. Dreamcast uses
ROCKNIX's H700-tuned Flycast 2021 core; DS and PSP use the matching standalone
DraStic and PPSSPP builds instead of slower or unstable libretro substitutes.
V5.4 restores MPV's proven direct-DRM presentation because this pinned build
cannot let its SDL gamepad and SDL video components own SDL simultaneously;
decoding remains software until Bird enables H616 Cedrus/V4L2-request in an
EGL-capable media build. DraStic uses Panfrost through SDL's desktop OpenGL
renderer, and PPSSPP receives an opaque KMS window and a clean versioned shader
cache. Ports inherit ALSA's complete native definitions with one fixed default
H616 endpoint. Every app runs without a compositor or session daemon and gets
a distinct persistent log plus dmesg snapshot.

V5.3 hardware evidence also rejected Bird's first clock helper. The native
policy reached 1.416 GHz CPU and 648 MHz GPU on demand; Bird's writes reduced
the GPU to 600 MHz and caused repeated H700 PLL-lock warnings at every enter
and leave. V5.4 removes all userspace clock writes while preserving snapshots.
The global controls process now consumes the already-present `gpio-keys-lid`
event directly, so lid suspend remains separate from the launcher.

The audio gate is deliberately the built-in-speaker path. The source kernel
already publishes the fixed headphone-detect GPIO and `Headphone` DAPM pin,
but enabling Bird's `Speaker Switch` does not automatically mute that external
amplifier when headphones are inserted. A tiny fixed jack policy is tracked
after speaker playback passes; no generic audio session manager will be added
for it.

ROCKNIX is currently a pinned application/runtime provider and the source of
the open kernel/driver chain. It is not Bird's frontend, init system or booted
root. P5 exists only as a recovery oracle during this hardware gate and can be
removed from the final partition layout after Bird's native paths are proven.
