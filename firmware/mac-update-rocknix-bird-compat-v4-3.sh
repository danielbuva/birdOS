#!/bin/sh
# Stage v4.3: sun4i display is DRM card0; the complete Panfrost chain warms
# automatically after Bird's first interactive frame.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

COMPAT_PROFILE=v4.3 exec \
	"$ROOT/firmware/mac-update-rocknix-bird-compat-v4-2.sh"
