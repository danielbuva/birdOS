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
	printf 'Bird fixed Sway start uptime='
	cut -d ' ' -f 1 /proc/uptime
	if cmp -s "$RUN_DIR/config" "$CONFIG"; then
		printf 'config=unchanged\n'
	else
		cp -f "$RUN_DIR/config" "$CONFIG"
		printf 'config=updated\n'
	fi
	if cmp -s "$RUN_DIR/095-sway" "$PROFILE"; then
		printf 'profile=unchanged\n'
	else
		cp -f "$RUN_DIR/095-sway" "$PROFILE"
		printf 'profile=updated\n'
	fi
	printf 'Bird fixed Sway ready uptime='
	cut -d ' ' -f 1 /proc/uptime
} >"$LOG" 2>&1
