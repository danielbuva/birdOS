#!/bin/sh
set -eu

TARGET=${1:-/opt/muos/script/system/startup.sh}
MARKER="BIRD_FIXED_STARTUP_TAIL_V1"

[ -f "$TARGET" ] || {
	printf 'error: startup target missing: %s\n' "$TARGET" >&2
	exit 1
}

grep -q "$MARKER" "$TARGET" && exit 0

PATCHED="$TARGET.bird-fixed-tail-new.$$"
cleanup() {
	rm -f "$PATCHED"
}
trap cleanup 0 1 2 15

SKIP_UNTIL=""
REMOVED_SECTIONS=0
REMOVED_VARS=0
FIRST=1
while IFS= read -r LINE; do
	if [ "$FIRST" -eq 1 ]; then
		printf '%s\n' "$LINE"
		printf '# %s\n' "$MARKER"
		FIRST=0
		continue
	fi

	if [ -n "$SKIP_UNTIL" ]; then
		if [ "$LINE" = "$SKIP_UNTIL" ]; then
			SKIP_UNTIL=""
			printf '%s\n' "$LINE"
		fi
		continue
	fi

	case "$LINE" in
		'#:] ### Set OS Release Metadata')
			SKIP_UNTIL='#:] ### Reset Display variables'
			REMOVED_SECTIONS=$((REMOVED_SECTIONS + 1))
			continue
			;;
		'#:] ### Rumble Self Test')
			SKIP_UNTIL='#:] ### Factory Reset Detection'
			REMOVED_SECTIONS=$((REMOVED_SECTIONS + 1))
			continue
			;;
		'#:] ### Permissions sanity pass (background)')
			SKIP_UNTIL='#:] ### Loopback Network'
			REMOVED_SECTIONS=$((REMOVED_SECTIONS + 1))
			continue
			;;
		'#:] ### System sounds (_background_)')
			SKIP_UNTIL='#:] ### User Init Scripts (_optional_)'
			REMOVED_SECTIONS=$((REMOVED_SECTIONS + 1))
			continue
			;;
		'#:] ### Log Cleaner')
			SKIP_UNTIL='#:] ### Low Power Indicator'
			REMOVED_SECTIONS=$((REMOVED_SECTIONS + 1))
			continue
			;;
		'#:] ### USB Gadget')
			SKIP_UNTIL='#:] ### Save kernel boot log'
			REMOVED_SECTIONS=$((REMOVED_SECTIONS + 1))
			continue
			;;
	esac

	case "$LINE" in
		'RUMBLE_SETTING=$(GET_VAR "config" "settings/advanced/rumble")' | \
		'RUMBLE_PIN=$(GET_VAR "device" "board/rumble")' | \
		'HAS_NETWORK=$(GET_VAR "device" "board/network")' | \
		'USB_FUNCTION=$(GET_VAR "config" "settings/advanced/usb_function")' | \
		'CONNECT_ON_BOOT=$(GET_VAR "config" "settings/network/boot")' | \
		'RA_CACHE=$(GET_VAR "config" "settings/advanced/retrocache")' | \
		'NET_ASYNC=$(GET_VAR "config" "settings/network/async_load")')
			REMOVED_VARS=$((REMOVED_VARS + 1))
			continue
			;;
	esac

	printf '%s\n' "$LINE"
done <"$TARGET" >"$PATCHED"

[ -z "$SKIP_UNTIL" ] && [ "$REMOVED_SECTIONS" -eq 6 ] && \
	[ "$REMOVED_VARS" -eq 7 ] && grep -q "$MARKER" "$PATCHED" && \
	grep -q '#:] ### User Init Scripts (_optional_)' "$PATCHED" && \
	grep -q '#:] ### Low Power Indicator' "$PATCHED" && \
	grep -q '#:] ### Save kernel boot log' "$PATCHED" && \
	! grep -q '#:] ### USB Gadget' "$PATCHED" && \
	! grep -q '#:] ### Catalogue Generator' "$PATCHED" && \
	sh -n "$PATCHED" || {
	printf 'error: fixed startup-tail patch did not match the expected script\n' >&2
	exit 1
}

chmod 755 "$PATCHED"
mv -f "$PATCHED" "$TARGET"
trap - 0 1 2 15

