#!/bin/sh
set -eu

TARGET=${1:-/opt/muos/script/init/sysinit}
MARKER="DANI_SKIP_BOOT_DBUS_V1"

[ -f "$TARGET" ] || {
	printf 'error: sysinit target missing: %s\n' "$TARGET" >&2
	exit 1
}

grep -q "$MARKER" "$TARGET" && exit 0

PATCHED="$TARGET.dani-postmenu-audio-new.$$"
cleanup() {
	rm -f "$PATCHED"
}
trap cleanup 0 1 2 15

MATCHES=0
while IFS= read -r LINE; do
	printf '%s\n' "$LINE"
	if [ "$LINE" = "$(printf '\t\t\t%s' 'S03danilauncher) TIMING_EVENT "skip" "sync" "S03danilauncher" "already-critical"; continue ;;')" ]; then
		printf '\t\t\t%s\n' '# DANI_SKIP_BOOT_DBUS_V1'
		printf '\t\t\t%s\n' 'S30dbus) TIMING_EVENT "skip" "sync" "S30dbus" "post-menu-audio"; continue ;;'
		MATCHES=$((MATCHES + 1))
	fi
done <"$TARGET" >"$PATCHED"

[ "$MATCHES" -eq 1 ] && grep -q "$MARKER" "$PATCHED" && sh -n "$PATCHED" || {
	printf 'error: sysinit post-menu audio patch did not match exactly once\n' >&2
	exit 1
}

chmod 755 "$PATCHED"
mv -f "$PATCHED" "$TARGET"
trap - 0 1 2 15

