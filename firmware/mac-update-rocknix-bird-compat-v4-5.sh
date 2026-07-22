#!/bin/sh
# Stage v4.5: retain the proven KMS/Panfrost path and run only libretro
# sessions through ROCKNIX's matching native RetroArch executable and loader.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

COMPAT_PROFILE=v4.5 exec \
	"$ROOT/firmware/mac-update-rocknix-bird-compat-v4-2.sh"
