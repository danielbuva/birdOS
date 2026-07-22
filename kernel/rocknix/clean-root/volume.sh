#!/bin/sh
# Direct fixed-codec volume adjustment. No PipeWire or session daemon is
# required; the native applications use the same ALSA card directly.

[ -e /run/bird/runtime-ready ] || exit 1
case "${1-}" in
	U) CHANGE=5%+ ;;
	D) CHANGE=5%- ;;
	*) exit 1 ;;
esac

for CONTROL in Headphone 'Headphone Playback Volume' DAC; do
	/usr/sbin/chroot /run/bird-runtime /usr/bin/amixer -q -c 0 \
		sset "$CONTROL" "$CHANGE" 2>/dev/null && exit 0
done
exit 1
