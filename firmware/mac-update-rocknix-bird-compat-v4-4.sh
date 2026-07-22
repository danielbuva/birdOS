#!/bin/sh
# Stage v4.4: retain the proven asynchronous Panfrost topology and capture the
# exact SDL loader, KMS resources and DRM-master result on the first content
# request. The diagnostic remains completely outside the visible boot path.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

COMPAT_PROFILE=v4.4 exec \
	"$ROOT/firmware/mac-update-rocknix-bird-compat-v4-2.sh"
