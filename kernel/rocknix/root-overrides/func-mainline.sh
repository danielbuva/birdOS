#!/bin/sh
# Load every existing muOS helper unchanged. During an explicitly selected
# content session only, keep Bird's mainline graphics ABI ahead of GL4ES and
# the vendor frontend libraries.

. /run/muos/bird-func-vendor

if [ "${BIRD_MAINLINE_CONTENT-}" = 1 ] && \
	[ -r /run/muos/bird-mainline-env ]; then
	. /run/muos/bird-mainline-env
	BIRD_MAINLINE_REASSERT

	SETUP_GL4ES() {
		BIRD_MAINLINE_REASSERT
	}
fi
