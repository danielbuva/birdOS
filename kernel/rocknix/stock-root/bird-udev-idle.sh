#!/bin/sh
# The fixed device is fully coldplugged before this post-application step.
# Stop only udevd's resident process; its control and kernel sockets remain
# active and restart the manager if a later hardware event actually needs it.

set -u

UDEVADM=${BIRD_UDEVADM:-/usr/bin/udevadm}
SYSTEMCTL=${BIRD_SYSTEMCTL:-/usr/bin/systemctl}
TIMEOUT=${BIRD_TIMEOUT:-/usr/bin/timeout}

"$UDEVADM" settle --timeout=10 || exit 1
"$TIMEOUT" --signal=TERM --kill-after=1s 3s \
	"$SYSTEMCTL" stop systemd-udevd.service || exit 1

BIRD_UDEV_STATE=$("$TIMEOUT" --signal=TERM --kill-after=1s 3s \
	"$SYSTEMCTL" show --property=ActiveState --value \
	systemd-udevd.service 2>/dev/null) || exit 1
case "$BIRD_UDEV_STATE" in
	inactive|failed) ;;
	*) exit 1 ;;
esac

printf 'fixed_udev_manager=%s sockets=retained\n' "$BIRD_UDEV_STATE"
