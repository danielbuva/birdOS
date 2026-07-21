#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
SOURCE="$ROOT/firmware/device-capture-one-shot-boot-state.sh"
TARGET="$CARD/MUOS/init/56-capture-one-shot-boot-state.sh"
TEMP="$CARD/MUOS/init/.56-capture-one-shot-boot-state.new"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -d "$CARD/MUOS/init" ] || fail "mounted Dani SP card not found: $CARD"
[ -f "$SOURCE" ] || fail "boot-state collector missing: $SOURCE"

for OLD in "$TARGET" "$TARGET.done" "$TARGET.failed"; do
	[ ! -e "$OLD" ] || rm -f "$OLD"
done

COPYFILE_DISABLE=1 cp -f "$SOURCE" "$TEMP"
cmp "$SOURCE" "$TEMP"
mv -f "$TEMP" "$TARGET"
chmod 755 "$TARGET"
find "$CARD/MUOS/init" -maxdepth 1 -name '._*' -delete
sync

printf 'Staged read-only one-boot boot-state capture: %s\n' "$TARGET"
printf 'It copies the exact live p2 and p3 partitions under:\n'
printf '  %s\n' "$CARD/.firmware-work/one-shot-boot"
printf 'It also captures the accepted kernel symbols and hardware state there.\n'
