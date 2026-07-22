#!/bin/sh
# Bird's complete fixed H616 speaker route. This runs from post-frame after the
# immutable application runtime is mounted and before native content is marked
# ready. It replaces a generic UCM/session manager with the one known device
# state required by the RG34XX-SP.

set -eu

RUNTIME=/run/bird-runtime
LOG=/mnt/mmc/MUOS/Bird/log/alsa-route-latest.txt

amixer() {
	/usr/sbin/chroot "$RUNTIME" /usr/bin/amixer -q -c 0 "$@"
}

mkdir -p "${LOG%/*}"
{
	printf 'Bird fixed audio route start uptime: '
	cut -d ' ' -f 1 /proc/uptime
	printf '%s\n' '--- before ---'
	/usr/sbin/chroot "$RUNTIME" /usr/bin/amixer -c 0 contents

	# The first, fourth and sixth controls are the pinned ROCKNIX H700 UCM
	# boot/speaker sequence. The remaining controls make the reset-state
	# assumptions explicit and replace its PipeWire-owned PlaybackMixerElem.
	amixer cset "name=DAC Playback Switch" on
	amixer cset "name=DAC Reversed Playback Switch" off
	amixer cset "name=Line Out Source Playback Route" Stereo
	amixer cset "name=DAC Playback Volume" 63
	amixer sset "Line Out" 60% unmute
	amixer cset "name=Speaker Switch" on

	printf '%s\n' '--- after ---'
	/usr/sbin/chroot "$RUNTIME" /usr/bin/amixer -c 0 contents
	printf 'Bird fixed audio route ready uptime: '
	cut -d ' ' -f 1 /proc/uptime
} >"$LOG" 2>&1
