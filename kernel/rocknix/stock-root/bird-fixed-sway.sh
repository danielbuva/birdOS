#!/bin/sh
# Install the exact RG34XX-SP internal-panel Sway contract. The generic ROCKNIX
# generator scans every DRM connector and product family, rewrites these files,
# and un/masks Bird's already-running service on every boot.

set -eu

SWAY_DIR=/storage/.config/sway
PROFILE_DIR=/storage/.config/profile.d
RUN_DIR=/run/bird/fixed-sway
CONFIG=$SWAY_DIR/config
PROFILE=$PROFILE_DIR/095-sway
LOG=/storage/bird-data/Bird/log/fixed-sway-latest.log

mkdir -p "$SWAY_DIR" "$PROFILE_DIR" "$RUN_DIR" "${LOG%/*}"

file_matches_lines() {
	CURRENT=$1
	shift
	[ -f "$CURRENT" ] || return 1
	MATCH=1
	exec 3<"$CURRENT"
	for EXPECTED in "$@"; do
		ACTUAL=
		if ! IFS= read -r ACTUAL <&3 || [ "$ACTUAL" != "$EXPECTED" ]; then
			MATCH=0
			break
		fi
	done
	if [ "$MATCH" -eq 1 ] && IFS= read -r ACTUAL <&3; then
		MATCH=0
	fi
	exec 3<&-
	[ "$MATCH" -eq 1 ]
}

log_uptime() {
	LABEL=$1
	NOW=unknown
	UNUSED=
	IFS=' ' read -r NOW UNUSED </proc/uptime || NOW=unknown
	printf '%s%s\n' "$LABEL" "$NOW"
}

cat <<'EOF' >"$RUN_DIR/config"
seat * hide_cursor 1000
default_border none
exec_always mako
output DSI-1 transform 0
output DSI-1 bg #000000 solid_color
output DSI-1 allow_tearing yes
output DSI-1 max_render_time off
EOF

cat <<'EOF' >"$RUN_DIR/095-sway"
WLR_DRM_DEVICES=/dev/dri/card1
WLR_BACKENDS=drm,libinput
WLR_CON=DSI-1
EOF

{
	log_uptime 'Bird fixed Sway start uptime='
	if file_matches_lines "$CONFIG" \
		'seat * hide_cursor 1000' \
		'default_border none' \
		'exec_always mako' \
		'output DSI-1 transform 0' \
		'output DSI-1 bg #000000 solid_color' \
		'output DSI-1 allow_tearing yes' \
		'output DSI-1 max_render_time off'; then
		printf 'config=unchanged\n'
	else
		cp -f "$RUN_DIR/config" "$CONFIG"
		printf 'config=updated\n'
	fi
	if file_matches_lines "$PROFILE" \
		'WLR_DRM_DEVICES=/dev/dri/card1' \
		'WLR_BACKENDS=drm,libinput' \
		'WLR_CON=DSI-1'; then
		printf 'profile=unchanged\n'
	else
		cp -f "$RUN_DIR/095-sway" "$PROFILE"
		printf 'profile=updated\n'
	fi
	log_uptime 'Bird fixed Sway ready uptime='
} >"$LOG" 2>&1
