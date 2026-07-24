#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
PAYLOAD="$ROOT/userspace/S10fixed-devices"
INSTALL_SOURCE="$ROOT/userspace/device-install-fixed-devices.sh"
WORK_DIR="$CARD/MUOS/boot-timing/udev-fixed"
PAYLOAD_TARGET="$WORK_DIR/S10fixed-devices"
INSTALL_TARGET="$CARD/MUOS/init/87-install-fixed-devices.sh"
TIMING_TARGET="$CARD/MUOS/init/99-boot-timing-marker.sh"

[ -d "$CARD/MUOS/init" ] || {
	printf 'error: mounted birdOS card not found: %s\n' "$CARD" >&2
	exit 1
}
sh -n "$PAYLOAD"
sh -n "$INSTALL_SOURCE"
sh -n "$ROOT/99-frontend-native-log.sh"

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$PAYLOAD" "$WORK_DIR/.S10fixed-devices.new"
COPYFILE_DISABLE=1 cp -f "$INSTALL_SOURCE" "$CARD/MUOS/init/.87-install-fixed-devices.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.fixed-devices-new"
cmp "$PAYLOAD" "$WORK_DIR/.S10fixed-devices.new"
cmp "$INSTALL_SOURCE" "$CARD/MUOS/init/.87-install-fixed-devices.new"
cmp "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.fixed-devices-new"

mv -f "$WORK_DIR/.S10fixed-devices.new" "$PAYLOAD_TARGET"
mv -f "$CARD/MUOS/init/.87-install-fixed-devices.new" "$INSTALL_TARGET"
mv -f "$CARD/MUOS/init/.99-boot-timing-marker.fixed-devices-new" "$TIMING_TARGET"
chmod 755 "$PAYLOAD_TARGET" "$INSTALL_TARGET" "$TIMING_TARGET"
rm -f "$WORK_DIR/._S10fixed-devices" \
	"$CARD/MUOS/init/._87-install-fixed-devices.sh" \
	"$CARD/MUOS/init/._99-boot-timing-marker.sh"
sync

printf 'Staged fixed-device installer: %s\n' "$INSTALL_TARGET"
printf 'First boot installs it; the following cold boot tests the udev-free path.\n'
