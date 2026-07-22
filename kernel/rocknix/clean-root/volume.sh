#!/bin/sh
# Direct fixed-codec volume adjustment. No PipeWire or session daemon is
# required; the native applications use the same ALSA card directly.

[ -e /run/bird/runtime-ready ] || exit 1
case "${1-}" in
	U) CHANGE=5%+ ;;
	D) CHANGE=5%- ;;
	*) exit 1 ;;
esac

/usr/sbin/chroot /run/bird-runtime /usr/bin/amixer -q -c 0 \
	sset DAC "$CHANGE"
