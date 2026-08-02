#!/bin/sh
# ROCKNIX common/001-setup may recover the complete stock /usr/config tree when
# an unrelated application config is missing. That recovery runs after Bird's
# pre-systemd root preparation and restores the stock real-suspend defaults.
# This fixed common/009 replacement runs later in the same ordered common phase
# and restores the one supported H700 provider mode through ROCKNIX's own
# settings transaction.

POLICY=${BIRD_SUSPEND_POLICY:-/flash/bird/bird-suspend-policy.generated.sh}
CONFIG=${BIRD_SUSPEND_CONFIG:-/storage/.config/system/configs/system.cfg}
FIXED_SLEEP=${BIRD_SUSPEND_FIXED_SLEEP:-/flash/bird/bird-sleep.conf}
SLEEP_CONFIG=${BIRD_SUSPEND_SLEEP_CONFIG:-/storage/.config/sleep.conf.d/sleep.conf}
SUSPENDMODE=${BIRD_SUSPENDMODE_PROGRAM:-/usr/bin/suspendmode}
BUSYBOX=${BIRD_SUSPEND_BUSYBOX:-/usr/bin/busybox}
MODE=
MODE_COUNT=0

read_mode() {
	MODE=
	MODE_COUNT=0
	while IFS= read -r CONFIG_LINE; do
		case "$CONFIG_LINE" in
			system.suspendmode=*)
				MODE_COUNT=$((MODE_COUNT + 1))
				MODE=${CONFIG_LINE#*=}
				;;
		esac
	done <"$CONFIG"
}

[ -r "$POLICY" ] || exit 1
. "$POLICY"
[ "${BIRD_SUSPEND_PROVIDER_MODE:-}" = off ] || exit 1
[ -r "$CONFIG" ] || exit 1
[ -r "$FIXED_SLEEP" ] || exit 1
[ -x "$SUSPENDMODE" ] || exit 1
[ -x "$BUSYBOX" ] || exit 1

read_mode
if [ "$MODE_COUNT" -ne 1 ] || [ "$MODE" != off ]; then
	"$SUSPENDMODE" off || exit 1
	read_mode
	[ "$MODE_COUNT" -eq 1 ] && [ "$MODE" = off ] || exit 1
fi

if ! "$BUSYBOX" cmp -s "$FIXED_SLEEP" "$SLEEP_CONFIG"; then
	SLEEP_TEMP=$SLEEP_CONFIG.bird-new
	"$BUSYBOX" rm -f "$SLEEP_TEMP" || exit 1
	"$BUSYBOX" cp -f "$FIXED_SLEEP" "$SLEEP_TEMP" &&
		"$BUSYBOX" chmod 0644 "$SLEEP_TEMP" &&
		"$BUSYBOX" mv -f "$SLEEP_TEMP" "$SLEEP_CONFIG" || {
			"$BUSYBOX" rm -f "$SLEEP_TEMP"
			exit 1
		}
fi
"$BUSYBOX" cmp -s "$FIXED_SLEEP" "$SLEEP_CONFIG" || exit 1

exit 0
