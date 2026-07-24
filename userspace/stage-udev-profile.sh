#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
PAYLOAD="$ROOT/userspace/S10udev-profile"
INSTALL_SOURCE="$ROOT/userspace/device-install-udev-profile.sh"
WORK_DIR="$CARD/MUOS/boot-timing/udev-profile"
PAYLOAD_TARGET="$WORK_DIR/S10udev-profile"
INSTALL_TARGET="$CARD/MUOS/init/88-install-udev-profile.sh"
TIMING_TARGET="$CARD/MUOS/init/99-boot-timing-marker.sh"

[ -d "$CARD/MUOS/init" ] || {
	printf 'error: mounted birdOS card not found: %s\n' "$CARD" >&2
	exit 1
}
sh -n "$PAYLOAD"
sh -n "$INSTALL_SOURCE"
sh -n "$ROOT/99-frontend-native-log.sh"

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$PAYLOAD" "$WORK_DIR/.S10udev-profile.new"
COPYFILE_DISABLE=1 cp -f "$INSTALL_SOURCE" "$CARD/MUOS/init/.88-install-udev-profile.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.udev-profile-new"
cmp "$PAYLOAD" "$WORK_DIR/.S10udev-profile.new"
cmp "$INSTALL_SOURCE" "$CARD/MUOS/init/.88-install-udev-profile.new"
cmp "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.udev-profile-new"

mv -f "$WORK_DIR/.S10udev-profile.new" "$PAYLOAD_TARGET"
mv -f "$CARD/MUOS/init/.88-install-udev-profile.new" "$INSTALL_TARGET"
mv -f "$CARD/MUOS/init/.99-boot-timing-marker.udev-profile-new" "$TIMING_TARGET"
chmod 755 "$PAYLOAD_TARGET" "$INSTALL_TARGET" "$TIMING_TARGET"
# FAT volumes can acquire AppleDouble metadata files even when copyfile is
# disabled. They have no device-side purpose and must not ship with the stage.
rm -f "$WORK_DIR/._S10udev-profile" \
	"$CARD/MUOS/init/._88-install-udev-profile.sh" \
	"$CARD/MUOS/init/._99-boot-timing-marker.sh"
sync

printf 'Staged udev pre/post profiler installer: %s\n' "$INSTALL_TARGET"
printf 'First boot installs it; the following cold boot captures its inventory.\n'
