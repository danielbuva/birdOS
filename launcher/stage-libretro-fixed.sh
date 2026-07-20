#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
PAYLOAD="$ROOT/launcher/lr-fixed.sh"
INSTALL_SOURCE="$ROOT/launcher/device-install-libretro-fixed.sh"
PAYLOAD_TARGET="$CARD/MUOS/bespoke-launcher/lr-fixed.sh"
INSTALL_TARGET="$CARD/MUOS/init/89-install-libretro-fixed.sh"

[ -d "$CARD/MUOS/init" ] && [ -d "$CARD/MUOS/bespoke-launcher" ] || {
	printf 'error: mounted Dani SP card not found: %s\n' "$CARD" >&2
	exit 1
}
sh -n "$PAYLOAD"
sh -n "$INSTALL_SOURCE"

COPYFILE_DISABLE=1 cp -f "$PAYLOAD" "$CARD/MUOS/bespoke-launcher/.lr-fixed.new"
COPYFILE_DISABLE=1 cp -f "$INSTALL_SOURCE" "$CARD/MUOS/init/.89-install-libretro-fixed.new"
cmp "$PAYLOAD" "$CARD/MUOS/bespoke-launcher/.lr-fixed.new"
cmp "$INSTALL_SOURCE" "$CARD/MUOS/init/.89-install-libretro-fixed.new"

mv -f "$CARD/MUOS/bespoke-launcher/.lr-fixed.new" "$PAYLOAD_TARGET"
mv -f "$CARD/MUOS/init/.89-install-libretro-fixed.new" "$INSTALL_TARGET"
chmod 755 "$PAYLOAD_TARGET" "$INSTALL_TARGET"
sync

printf 'Staged fixed libretro bridge installer: %s\n' "$INSTALL_TARGET"
printf 'Install it on one boot, then cold boot and compare first and second launches.\n'
