#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
SOURCE="$ROOT/userspace/57capture-kernel-baseline.sh"
TARGET="$CARD/MUOS/init/57-capture-kernel-baseline.sh"
TEMP="$CARD/MUOS/init/.57-capture-kernel-baseline.new"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -d "$CARD/MUOS/init" ] || fail "mounted birdOS card not found: $CARD"
[ -f "$SOURCE" ] || fail "kernel baseline collector missing: $SOURCE"

for OLD in "$TARGET" "$TARGET.done" "$TARGET.failed"; do
	[ ! -e "$OLD" ] || rm -f "$OLD"
done

COPYFILE_DISABLE=1 cp -f "$SOURCE" "$TEMP"
cmp "$SOURCE" "$TEMP"
mv -f "$TEMP" "$TARGET"
chmod 755 "$TARGET"
find "$CARD/MUOS/init" -maxdepth 1 -name '._*' -delete
sync

printf 'Staged one-boot kernel inventory: %s\n' "$TARGET"
printf 'It runs after the menu is interactive and writes under:\n'
printf '  %s\n' "$CARD/MUOS/boot-timing/kernel-baseline"
