#!/bin/sh
# The canonical catalog path must reach the exact ROCKNIX provider tuple.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
RUNNER=$ROOT/kernel/rocknix/stock-root/run-content.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-rom-provider-map.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

python3 - "$RUNNER" "$TMP/rocknix-tuple.sh" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("rocknix_tuple() {")
end = source.index("\n}\n\nrun_network_helper() {", start) + 2
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY
sh -n "$TMP/rocknix-tuple.sh"

cat >"$TMP/cases.tsv" <<'EOF'
A2600	atari2600 retroarch stella
ATOMISWAVE	atomiswave retroarch flycast2021
CPS1	cps1 retroarch fbneo
CPS2	cps2 retroarch fbneo
CPS3	cps3 retroarch fbneo
DOS	pc retroarch dosbox_pure
DREAMCAST	dreamcast retroarch flycast2021
FBNEO	fbneo retroarch fbneo
FC	famicom retroarch nestopia
GB	gb retroarch gambatte
GBA	gba retroarch mgba
GBC	gbc retroarch gambatte
GG	gamegear retroarch gearsystem
GW	gameandwatch retroarch gw
HBMAME	arcade retroarch fbneo
MAME	mame retroarch mame2003_plus
MD	megadrive retroarch genesis_plus_gx
MSX	msx retroarch fmsx
N64	n64 retroarch mupen64plus_next
NAOMI	naomi retroarch flycast2021
NDS	nds drastic drastic-sa
OPENBOR	openbor OpenBOR OpenBOR
PCE	pcengine retroarch beetle_pce_fast
PICO	pico-8 retroarch fake08
PSP	psp ppsspp ppsspp-sa
Ports	ports portmaster portmaster
SNES	snes retroarch snes9x
EOF

. "$TMP/rocknix-tuple.sh"
while IFS="	" read -r DIRECTORY EXPECTED; do
	HOST_PATH=/storage/roms/$DIRECTORY/test.rom
	ACTUAL=$(rocknix_tuple)
	[ "$ACTUAL" = "$EXPECTED" ] || {
		printf 'wrong tuple for %s: %s\n' "$HOST_PATH" "$ACTUAL" >&2
		exit 1
	}
done <"$TMP/cases.tsv"

for HOST_PATH in \
	/mnt/mmc/ROMS/A2600/test.rom \
	/storage/ROMS/A2600/test.rom \
	/storage/roms/UNKNOWN/test.rom \
	/storage/media/WATCH/test.mkv; do
	if rocknix_tuple >/dev/null 2>&1; then
		printf 'noncanonical provider path accepted: %s\n' "$HOST_PATH" >&2
		exit 1
	fi
done

printf '%s\n' 'stock-root canonical ROM provider mapping tests passed'
