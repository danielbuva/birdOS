#!/bin/bash
# Retain ROCKNIX configuration recovery while avoiding accepted-state writes
# to persistent settings and already-correct compatibility paths.

set -eu

FUNCTIONS=${BIRD_FUNCTIONS:-/etc/profile.d/001-functions}
# shellcheck source=/dev/null
. "$FUNCTIONS"

CACHE_DIR=${BIRD_CACHE_DIR:-/tmp/cache}
CACHE_LINK=${BIRD_CACHE_LINK:-/storage/cache/.cores}
PROFILE_DIR=${BIRD_PROFILE_DIR:-/storage/.config/profile.d}
RUNTIME_DIR=${BIRD_RUNTIME_DIR:-/var/run/0-runtime-dir}
CHKSYSCONFIG=${BIRD_CHKSYSCONFIG:-/usr/bin/chksysconfig}
J_CONF=${BIRD_SYSTEM_CONFIG:-$J_CONF}

[ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
[ -d "${CACHE_LINK%/*}" ] || mkdir -p "${CACHE_LINK%/*}"
if [ -L "$CACHE_LINK" ] && [ "$CACHE_LINK" -ef "$CACHE_DIR" ]; then
	:
else
	rm -rf "$CACHE_LINK"
	ln -s "$CACHE_DIR" "$CACHE_LINK"
fi

[ -d "$PROFILE_DIR" ] || mkdir -p "$PROFILE_DIR"

# This remains the accepted recovery boundary. mount-storage seeds its three
# prerequisites so an ordinary boot takes only the verifier's read path.
"$CHKSYSCONFIG" verify

# sort_settings intentionally filters and rewrites malformed configuration.
# Skip that persistent transaction only when the file is already canonical.
if ! LC_ALL=C awk '
	$0 !~ /^[a-z0-9]/ { exit 1 }
	NR > 1 && $0 < previous { exit 1 }
	{ previous = $0 }
' "$J_CONF"; then
	sort_settings
fi

# The generic hook deleted and re-appended this setting even when already zero.
[ "$(get_setting clouddrive.mounted)" = 0 ] || \
	set_setting clouddrive.mounted 0

[ -d "$RUNTIME_DIR" ] || mkdir -p "$RUNTIME_DIR"
chmod 0700 "$RUNTIME_DIR"
