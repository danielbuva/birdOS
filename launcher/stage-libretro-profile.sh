#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
PAYLOAD="$ROOT/launcher/lr-profiled.sh"
INSTALL_SOURCE="$ROOT/launcher/device-install-libretro-profile.sh"
PAYLOAD_TARGET="$CARD/MUOS/bespoke-launcher/lr-profiled.sh"
INSTALL_TARGET="$CARD/MUOS/init/90-install-libretro-profile.sh"

[ -d "$CARD/MUOS/init" ] && [ -d "$CARD/MUOS/bespoke-launcher" ] || {
	printf 'error: mounted Dani SP card not found: %s\n' "$CARD" >&2
	exit 1
}
sh -n "$PAYLOAD"
sh -n "$INSTALL_SOURCE"

COPYFILE_DISABLE=1 cp -f "$PAYLOAD" "$CARD/MUOS/bespoke-launcher/.lr-profiled.new"
COPYFILE_DISABLE=1 cp -f "$INSTALL_SOURCE" "$CARD/MUOS/init/.90-install-libretro-profile.new"
cmp "$PAYLOAD" "$CARD/MUOS/bespoke-launcher/.lr-profiled.new"
cmp "$INSTALL_SOURCE" "$CARD/MUOS/init/.90-install-libretro-profile.new"

mv -f "$CARD/MUOS/bespoke-launcher/.lr-profiled.new" "$PAYLOAD_TARGET"
mv -f "$CARD/MUOS/init/.90-install-libretro-profile.new" "$INSTALL_TARGET"
chmod 755 "$PAYLOAD_TARGET" "$INSTALL_TARGET"
sync

printf 'Staged profiled libretro wrapper installer: %s\n' "$INSTALL_TARGET"
printf 'On the next boot, wait 10 seconds before launching the first game.\n'
