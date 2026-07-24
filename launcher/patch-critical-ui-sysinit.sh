#!/bin/sh
set -eu

TARGET=${1:-/opt/muos/script/init/sysinit}
BACKUP=${2:-/mnt/mmc/MUOS/boot-timing/bespoke-services/backup/sysinit.pre-critical-ui}
INSTALL_LOG=${3:-/mnt/mmc/MUOS/boot-timing/bespoke-services/install.log}
MARKER="BIRD_CRITICAL_UI_FIRST_V1"

[ -f "$TARGET" ] || {
	printf 'error: sysinit target missing: %s\n' "$TARGET" >&2
	exit 1
}

grep -q "$MARKER" "$TARGET" && exit 0

mkdir -p "${BACKUP%/*}" "${INSTALL_LOG%/*}"
[ -f "$BACKUP" ] || cp -p "$TARGET" "$BACKUP"

PATCHED="${TARGET}.bird-critical-new.$$"
CLEANUP() {
	rm -f "$PATCHED"
}
trap CLEANUP 0 1 2 15

IN_NORMAL=0
FUNCTION_ADDED=0
SKIPS_ADDED=0
CALL_ADDED=0
SKIP_FINAL_SYNC=0
FINAL_FUNCTION_REMOVED=0
FINAL_CALL_REMOVED=0
while IFS= read -r LINE; do
	if [ "$SKIP_FINAL_SYNC" -eq 1 ]; then
		if [ "$LINE" = '}' ]; then
			SKIP_FINAL_SYNC=0
		fi
	elif [ "$LINE" = 'FINAL_SYNC() {' ]; then
		SKIP_FINAL_SYNC=1
		FINAL_FUNCTION_REMOVED=1
	elif [ "$LINE" = "$(printf '\t\t%s' 'FINAL_SYNC &')" ]; then
		FINAL_CALL_REMOVED=1
	elif [ "$LINE" = 'RUN_NORMAL() {' ]; then
		printf '%s\n' '# BIRD_CRITICAL_UI_FIRST_V1'
		printf '%s\n' 'RUN_CRITICAL_UI() {'
		printf '\t%s\n' 'SCRIPT="$INIT_DIR/S03birdlauncher"'
		printf '\t%s\n' '[ -f "$SCRIPT" ] || { TIMING_EVENT "skip" "critical" "S03birdlauncher" "missing"; return 0; }'
		printf '\t%s\n' 'RUN_SCRIPT "$SCRIPT" "critical"'
		printf '\t%s\n' 'COUNT=0'
		printf '\t%s\n' 'while [ ! -e /run/muos/bird-first-frame-ready ]; do'
		printf '\t\t%s\n' 'COUNT=$((COUNT + 1))'
		printf '\t\t%s\n' '[ "$COUNT" -ge 250 ] && { TIMING_EVENT "timeout" "critical" "interactive_frame_ready" "1"; return 0; }'
		printf '\t\t%s\n' 'sleep 0.001'
		printf '\t%s\n' 'done'
		printf '\t%s\n' 'TIMING_EVENT "milestone" "critical" "interactive_frame_ready" "0"'
		printf '%s\n\n' '}'
		printf '%s\n' "$LINE"
		IN_NORMAL=1
		FUNCTION_ADDED=1
	elif [ "$IN_NORMAL" -eq 1 ] && \
		[ "$LINE" = "$(printf '\t\t%s' '[ -e "$SCRIPT" ] || continue')" ]; then
		printf '%s\n' "$LINE"
		printf '\t\t%s\n' 'case "${SCRIPT##*/}" in'
		printf '\t\t\t%s\n' 'S02rgb) TIMING_EVENT "skip" "sync" "S02rgb" "removed-fixed-device"; continue ;;'
		printf '\t\t\t%s\n' 'S03birdlauncher) TIMING_EVENT "skip" "sync" "S03birdlauncher" "already-critical"; continue ;;'
		printf '\t\t%s\n' 'esac'
		IN_NORMAL=0
		SKIPS_ADDED=1
	elif [ "$LINE" = "$(printf '\t\t%s' 'FBCON_DISABLE')" ]; then
		printf '%s\n' "$LINE"
		printf '\t\t%s\n' 'RUN_CRITICAL_UI'
		CALL_ADDED=1
	else
		printf '%s\n' "$LINE"
	fi
done <"$TARGET" >"$PATCHED"

if [ "$FUNCTION_ADDED" -ne 1 ] || [ "$SKIPS_ADDED" -ne 1 ] || \
	[ "$CALL_ADDED" -ne 1 ] || [ "$FINAL_FUNCTION_REMOVED" -ne 1 ] || \
	[ "$FINAL_CALL_REMOVED" -ne 1 ] || ! grep -q "$MARKER" "$PATCHED" || \
	! sh -n "$PATCHED"; then
	printf '%s ERROR: critical UI ordering patch did not match current sysinit\n' \
		"$(date -Iseconds 2>/dev/null || date)" >>"$INSTALL_LOG"
	exit 1
fi

chmod 755 "$PATCHED"
mv -f "$PATCHED" "$TARGET"
trap - 0 1 2 15
printf '%s launcher moved before observers; failed RGB init removed\n' \
	"$(date -Iseconds 2>/dev/null || date)" >>"$INSTALL_LOG"
