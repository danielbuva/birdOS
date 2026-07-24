#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROM_ROOT=${1:-/Volumes/BIRD-DATA/ROMS}
MEDIA_ROOT=${MEDIA_ROOT:-${ROM_ROOT%/ROMS}/MEDIA}

if [ "$#" -ge 2 ] && [ -n "$2" ]; then
	exec python3 "$ROOT/generate-launcher-catalog.py" \
		"$ROM_ROOT" --manifest "$2" --media-root "$MEDIA_ROOT" \
		--output "$ROOT/launcher/catalog.generated.h" \
		--inventory-output "$ROOT/launcher/library.inventory.tsv"
fi

exec python3 "$ROOT/generate-launcher-catalog.py" \
	"$ROM_ROOT" --media-root "$MEDIA_ROOT" \
	--output "$ROOT/launcher/catalog.generated.h" \
	--inventory-output "$ROOT/launcher/library.inventory.tsv"
