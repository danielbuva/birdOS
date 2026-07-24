#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
PAYLOAD="$ROOT/userspace/S10minimal-udev"
INSTALL_SOURCE="$ROOT/userspace/device-install-minimal-udev.sh"
WORK_DIR="$CARD/MUOS/boot-timing/udev-minimal"
PAYLOAD_TARGET="$WORK_DIR/S10minimal-udev"
INSTALL_TARGET="$CARD/MUOS/init/86-install-minimal-udev.sh"
TIMING_TARGET="$CARD/MUOS/init/99-boot-timing-marker.sh"

[ -d "$CARD/MUOS/init" ] || {
	printf 'error: mounted birdOS card not found: %s\n' "$CARD" >&2
	exit 1
}
sh -n "$PAYLOAD"
sh -n "$INSTALL_SOURCE"
sh -n "$ROOT/99-frontend-native-log.sh"

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$PAYLOAD" "$WORK_DIR/.S10minimal-udev.new"
COPYFILE_DISABLE=1 cp -f "$INSTALL_SOURCE" "$CARD/MUOS/init/.86-install-minimal-udev.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.minimal-udev-new"
cmp "$PAYLOAD" "$WORK_DIR/.S10minimal-udev.new"
cmp "$INSTALL_SOURCE" "$CARD/MUOS/init/.86-install-minimal-udev.new"
cmp "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.minimal-udev-new"

mv -f "$WORK_DIR/.S10minimal-udev.new" "$PAYLOAD_TARGET"
mv -f "$CARD/MUOS/init/.86-install-minimal-udev.new" "$INSTALL_TARGET"
mv -f "$CARD/MUOS/init/.99-boot-timing-marker.minimal-udev-new" "$TIMING_TARGET"
chmod 755 "$PAYLOAD_TARGET" "$INSTALL_TARGET" "$TIMING_TARGET"
rm -f "$WORK_DIR/._S10minimal-udev" \
	"$CARD/MUOS/init/._86-install-minimal-udev.sh" \
	"$CARD/MUOS/init/._99-boot-timing-marker.sh"
sync

printf 'Staged minimal input/sound udev installer: %s\n' "$INSTALL_TARGET"
printf 'First boot installs/restores it; the following cold boot tests compatibility.\n'
