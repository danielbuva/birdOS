#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROM_ROOT=${1:-/Volumes/dani-sp/ROMS}
MANIFEST=${2:-$ROOT/launcher/catalog-proof.txt}

exec python3 "$ROOT/generate-launcher-catalog.py" \
	"$ROM_ROOT" --manifest "$MANIFEST" \
	--output "$ROOT/launcher/catalog.generated.h"
