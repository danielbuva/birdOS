#!/bin/sh
# One existing stock service slot owns both explicit diagnostic requests.
# Systemd starts it only when either marker exists; Stage 5 wins if both do.

set -eu

STAGE5_REQUEST=${BIRD_STAGE5_REQUEST:-/storage/bird-data/Bird/stage5-idle-window.request}
BOOT_REQUEST=${BIRD_BOOT_DIAGNOSTICS_REQUEST:-/storage/bird-data/Bird/boot-diagnostics.request}
STAGE5_CAPTURE=${BIRD_STAGE5_CAPTURE:-/flash/bird/capture-stage5-window.sh}
BOOT_CAPTURE=${BIRD_BOOT_DIAGNOSTICS_CAPTURE:-/flash/bird/capture-boot-state.sh}

if [ -e "$STAGE5_REQUEST" ]; then
	exec "$STAGE5_CAPTURE"
fi
if [ -e "$BOOT_REQUEST" ]; then
	exec "$BOOT_CAPTURE"
fi
exit 0
