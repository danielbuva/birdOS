#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PAYLOAD="$ROOT/launcher/optional-emulators"
POLICY="rg34xxsp-english-minimal-v1"
MANIFEST="$PAYLOAD/manifest.txt"

{
	printf 'policy\t%s\n' "$POLICY"
	for ARCHIVE in Extra.-.Nintendo.DS.muxzip Extra.-.OpenBOR.muxzip; do
		printf '%s\t%s\n' "$ARCHIVE" \
			"$(shasum -a 256 "$PAYLOAD/$ARCHIVE" | cut -d ' ' -f 1)"
	done
} >"$MANIFEST"

shasum -a 256 "$MANIFEST" | cut -d ' ' -f 1 >"$PAYLOAD/revision"
printf 'optional emulator revision: '
cat "$PAYLOAD/revision"
