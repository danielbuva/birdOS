#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-controls.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

CONTROL_SOURCE=$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c
OSD_SOURCE=$ROOT/kernel/rocknix/stock-root/bird-control-osd.sh
grep -Fq '#define VOLUME_PROGRAM "/flash/bird/bird-volume.sh"' "$CONTROL_SOURCE"
grep -Fq '#define OSD_PROGRAM "/flash/bird/bird-control-osd.sh"' "$CONTROL_SOURCE"
grep -Fq '#define SUSPEND_PROGRAM "/flash/bird/bird-suspend.sh"' "$CONTROL_SOURCE"
grep -Fq '#define EXIT_HELPER "/flash/bird/bird-fixed-control-exit.sh"' \
	"$CONTROL_SOURCE"

sh -n "$OSD_SOURCE"
grep -Fq '[ -n "$(pgrep -x sway 2>/dev/null)" ] || exit 0' "$OSD_SOURCE"
grep -Fq 'VALUE=$(get_setting audio.volume)' "$OSD_SOURCE"
grep -Fq '/usr/bin/mako-notify "Volume: $VALUE%" -no-es' "$OSD_SOURCE"
grep -Fq 'CURRENT=/sys/class/backlight/backlight/brightness' "$OSD_SOURCE"
grep -Fq 'MAXIMUM=/sys/class/backlight/backlight/max_brightness' "$OSD_SOURCE"
grep -Fq 'VALUE=$(((RAW * 100 + MAX / 2) / MAX))' "$OSD_SOURCE"
grep -Fq '/usr/bin/mako-notify "Brightness: $VALUE%" -no-es' "$OSD_SOURCE"

NONEXEC=$TMP/non-executable
printf '%s\n' '#!/bin/sh' 'exit 0' >"$NONEXEC"
chmod 0644 "$NONEXEC"

CC=${CC:-cc}
"$CC" -std=c11 -O1 -Wall -Wextra -Werror \
	-Wno-unused-function -Wno-macro-redefined \
	-I "$ROOT/launcher" \
	"$ROOT/kernel/rocknix/tests/fixed-controls-host.c" \
	-o "$TMP/fixed-controls-host"
"$TMP/fixed-controls-host" "$NONEXEC"
