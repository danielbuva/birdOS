#!/bin/sh
set -eu

TARGET=${1:-/etc/inittab}
BACKUP=${2:-/mnt/mmc/MUOS/boot-timing/bespoke-services/backup/inittab.pre-earliest-ui}
INSTALL_LOG=${3:-/mnt/mmc/MUOS/boot-timing/bespoke-services/install.log}
MARKER="DANI_EARLIEST_UI_V1"

[ -f "$TARGET" ] || {
	printf 'error: inittab target missing: %s\n' "$TARGET" >&2
	exit 1
}

grep -q "$MARKER" "$TARGET" && exit 0

mkdir -p "${BACKUP%/*}" "${INSTALL_LOG%/*}"
[ -f "$BACKUP" ] || cp -p "$TARGET" "$BACKUP"

PATCHED="${TARGET}.dani-earliest-new.$$"
CLEANUP() {
	rm -f "$PATCHED"
}
trap CLEANUP 0 1 2 15

MATCHES=0
while IFS= read -r LINE; do
	printf '%s\n' "$LINE"
	if [ "$LINE" = '::sysinit:/bin/mkdir -p /run /run/lock /run/lock/subsys' ]; then
		printf '# %s\n' "$MARKER"
		printf '%s\n' '::sysinit:/opt/muos/script/init/dani-earliest-ui.sh'
		MATCHES=$((MATCHES + 1))
	fi
done <"$TARGET" >"$PATCHED"

if [ "$MATCHES" -ne 1 ] || ! grep -q "$MARKER" "$PATCHED"; then
	printf '%s ERROR: fixed /run setup line missing; inittab unchanged\n' \
		"$(date -Iseconds 2>/dev/null || date)" >>"$INSTALL_LOG"
	exit 1
fi

chmod 644 "$PATCHED"
mv -f "$PATCHED" "$TARGET"
trap - 0 1 2 15
printf '%s earliest UI in BusyBox inittab installed; active next boot\n' \
	"$(date -Iseconds 2>/dev/null || date)" >>"$INSTALL_LOG"
