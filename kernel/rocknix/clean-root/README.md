# Bird clean root

This directory is Bird's first permanent-root userspace. It deliberately does
not import muOS startup scripts or application wrappers.

The boot split is:

1. The static first init mounts only kernel filesystems, loads the exact H700
   input module and starts the static launcher supervisor.
2. The launcher paints and opens direct input. This is the usability gate.
3. The permanent static PID 1 starts `post-frame.sh` independently.
4. Post-frame work mounts p6, warms Panfrost, mounts the pinned ROCKNIX SYSTEM
   image read-only and starts the separate global-controls process.
5. `run-content.sh` consumes only the launcher's four-line request and runs a
   native application with its matching core, configuration baseline, loader
   and libraries inside the read-only runtime.

Files:

- `supervisor.sh`: keeps the launcher alive and dispatches content or shutdown.
- `post-frame.sh`: prepares storage, GPU, runtime and controls after usability.
- `run-content.sh`: Bird-owned native application/core policy.
- `retroarch-append.cfg`: the small fixed RG34XX-SP override to native defaults.
- `volume.sh`, `suspend.sh`, `shutdown.sh`: fixed device lifecycle operations.

ROCKNIX is currently a pinned application/runtime provider and the source of
the open kernel/driver chain. It is not Bird's frontend, init system or booted
root. P5 exists only as a recovery oracle during this hardware gate and can be
removed from the final partition layout after Bird's native paths are proven.
