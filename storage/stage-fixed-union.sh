#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
PAYLOAD="$ROOT/storage/fixed-union.sh"
INSTALL_SOURCE="$ROOT/storage/device-install-fixed-union.sh"
WORK_DIR="$CARD/MUOS/boot-timing/fixed-storage"
PAYLOAD_TARGET="$WORK_DIR/fixed-union.sh"
INSTALL_TARGET="$CARD/MUOS/init/84-install-fixed-union.sh"
TIMING_TARGET="$CARD/MUOS/init/99-boot-timing-marker.sh"

[ -d "$CARD/MUOS/init" ] || {
	printf 'error: mounted Dani SP card not found: %s\n' "$CARD" >&2
	exit 1
}
sh -n "$PAYLOAD"
sh -n "$INSTALL_SOURCE"
sh -n "$ROOT/99-frontend-native-log.sh"

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$PAYLOAD" "$WORK_DIR/.fixed-union.sh.new"
COPYFILE_DISABLE=1 cp -f "$INSTALL_SOURCE" "$CARD/MUOS/init/.84-install-fixed-union.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.fixed-union-new"
cmp "$PAYLOAD" "$WORK_DIR/.fixed-union.sh.new"
cmp "$INSTALL_SOURCE" "$CARD/MUOS/init/.84-install-fixed-union.new"
cmp "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.fixed-union-new"

mv -f "$WORK_DIR/.fixed-union.sh.new" "$PAYLOAD_TARGET"
mv -f "$CARD/MUOS/init/.84-install-fixed-union.new" "$INSTALL_TARGET"
mv -f "$CARD/MUOS/init/.99-boot-timing-marker.fixed-union-new" "$TIMING_TARGET"
chmod 755 "$PAYLOAD_TARGET" "$INSTALL_TARGET" "$TIMING_TARGET"
rm -f "$WORK_DIR/._fixed-union.sh" \
	"$CARD/MUOS/init/._84-install-fixed-union.sh" \
	"$CARD/MUOS/init/._99-boot-timing-marker.sh"
sync

printf 'Staged fixed one-card UnionFS replacement: %s\n' "$INSTALL_TARGET"
printf 'First boot installs it; the following cold boot runs kernel bind mounts.\n'

