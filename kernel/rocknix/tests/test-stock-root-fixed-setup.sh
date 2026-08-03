#!/bin/bash
# Host coverage for fixed controller publication and repair-only setup.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
CONTROLLER=$ROOT/kernel/rocknix/stock-root/bird-fixed-controller.sh
CONTROLLER_SOURCE=$ROOT/kernel/rocknix/stock-root/bird-controller-profile
SETUP=$ROOT/kernel/rocknix/stock-root/bird-fixed-setup.sh
UI=$ROOT/kernel/rocknix/stock-root/090-ui_service
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-setup.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

PROFILE_DIR=$TMP/storage/profile.d
CONTROLLER_TARGET=$PROFILE_DIR/098-controller
mkdir -p "$PROFILE_DIR"
BUSYBOX=$TMP/busybox
cat >"$BUSYBOX" <<'EOF'
#!/bin/sh
APPLET=$1
shift
case "$APPLET" in
	cmp) exec cmp "$@" ;;
	rm) exec rm "$@" ;;
	cp) exec cp "$@" ;;
	chmod) exec chmod "$@" ;;
	mv) exec mv "$@" ;;
	*) exit 2 ;;
esac
EOF
chmod 0755 "$BUSYBOX"
BIRD_CONTROLLER_SOURCE=$CONTROLLER_SOURCE \
BIRD_CONTROLLER_TARGET=$CONTROLLER_TARGET \
BIRD_SYSTEM_BUSYBOX=$BUSYBOX "$CONTROLLER"
cmp "$CONTROLLER_SOURCE" "$CONTROLLER_TARGET"
CONTROLLER_MTIME=$(stat -f '%m' "$CONTROLLER_TARGET" 2>/dev/null || stat -c '%Y' "$CONTROLLER_TARGET")
sleep 1
BIRD_CONTROLLER_SOURCE=$CONTROLLER_SOURCE \
BIRD_CONTROLLER_TARGET=$CONTROLLER_TARGET \
BIRD_SYSTEM_BUSYBOX=$BUSYBOX "$CONTROLLER"
[ "$CONTROLLER_MTIME" = "$(stat -f '%m' "$CONTROLLER_TARGET" 2>/dev/null || stat -c '%Y' "$CONTROLLER_TARGET")" ]
printf '%s\n' stale >"$CONTROLLER_TARGET"
BIRD_CONTROLLER_SOURCE=$CONTROLLER_SOURCE \
BIRD_CONTROLLER_TARGET=$CONTROLLER_TARGET \
BIRD_SYSTEM_BUSYBOX=$BUSYBOX "$CONTROLLER"
cmp "$CONTROLLER_SOURCE" "$CONTROLLER_TARGET"

FUNCTIONS=$TMP/functions
SYSTEM_CONFIG=$TMP/storage/system.cfg
EVENTS=$TMP/events
cat >"$FUNCTIONS" <<'EOF'
J_CONF=$BIRD_TEST_SYSTEM_CONFIG
sort_settings() {
	printf '%s\n' sort_settings >>"$BIRD_TEST_EVENTS"
	LC_ALL=C sort "$J_CONF" >"$J_CONF.tmp"
	mv "$J_CONF.tmp" "$J_CONF"
}
get_setting() {
	sed -n "s/^$1=//p" "$J_CONF" | head -n 1
}
set_setting() {
	printf 'set_setting %s %s\n' "$1" "$2" >>"$BIRD_TEST_EVENTS"
	sed "/^$1=/d" "$J_CONF" >"$J_CONF.tmp"
	printf '%s=%s\n' "$1" "$2" >>"$J_CONF.tmp"
	mv "$J_CONF.tmp" "$J_CONF"
}
EOF
CHKSYSCONFIG=$TMP/chksysconfig
cat >"$CHKSYSCONFIG" <<'EOF'
#!/bin/sh
printf 'chksysconfig %s\n' "$*" >>"$BIRD_TEST_EVENTS"
EOF
chmod 0755 "$CHKSYSCONFIG"
printf '%s\n' 'audio.volume=60' 'clouddrive.mounted=0' 'system.hostname=H700' >"$SYSTEM_CONFIG"

CACHE_DIR=$TMP/tmp/cache
CACHE_LINK=$TMP/storage/cache/.cores
RUNTIME_DIR=$TMP/run/0-runtime-dir
export BIRD_TEST_SYSTEM_CONFIG=$SYSTEM_CONFIG BIRD_TEST_EVENTS=$EVENTS
BIRD_FUNCTIONS=$FUNCTIONS BIRD_SYSTEM_CONFIG=$SYSTEM_CONFIG \
BIRD_CACHE_DIR=$CACHE_DIR BIRD_CACHE_LINK=$CACHE_LINK \
BIRD_PROFILE_DIR=$PROFILE_DIR BIRD_RUNTIME_DIR=$RUNTIME_DIR \
BIRD_CHKSYSCONFIG=$CHKSYSCONFIG "$SETUP"
[ -L "$CACHE_LINK" ] && [ "$CACHE_LINK" -ef "$CACHE_DIR" ]
[ "$(stat -f '%Lp' "$RUNTIME_DIR" 2>/dev/null || stat -c '%a' "$RUNTIME_DIR")" = 700 ]
grep -Fxq 'chksysconfig verify' "$EVENTS"
CONFIG_MTIME=$(stat -f '%m' "$SYSTEM_CONFIG" 2>/dev/null || stat -c '%Y' "$SYSTEM_CONFIG")
LINK_MTIME=$(stat -f '%m' "$CACHE_LINK" 2>/dev/null || stat -c '%Y' "$CACHE_LINK")
: >"$EVENTS"
sleep 1
BIRD_FUNCTIONS=$FUNCTIONS BIRD_SYSTEM_CONFIG=$SYSTEM_CONFIG \
BIRD_CACHE_DIR=$CACHE_DIR BIRD_CACHE_LINK=$CACHE_LINK \
BIRD_PROFILE_DIR=$PROFILE_DIR BIRD_RUNTIME_DIR=$RUNTIME_DIR \
BIRD_CHKSYSCONFIG=$CHKSYSCONFIG "$SETUP"
[ "$CONFIG_MTIME" = "$(stat -f '%m' "$SYSTEM_CONFIG" 2>/dev/null || stat -c '%Y' "$SYSTEM_CONFIG")" ]
[ "$LINK_MTIME" = "$(stat -f '%m' "$CACHE_LINK" 2>/dev/null || stat -c '%Y' "$CACHE_LINK")" ]
[ "$(cat "$EVENTS")" = 'chksysconfig verify' ]

printf '%s\n' 'system.hostname=H700' 'audio.volume=60' 'clouddrive.mounted=1' >"$SYSTEM_CONFIG"
: >"$EVENTS"
BIRD_FUNCTIONS=$FUNCTIONS BIRD_SYSTEM_CONFIG=$SYSTEM_CONFIG \
BIRD_CACHE_DIR=$CACHE_DIR BIRD_CACHE_LINK=$CACHE_LINK \
BIRD_PROFILE_DIR=$PROFILE_DIR BIRD_RUNTIME_DIR=$RUNTIME_DIR \
BIRD_CHKSYSCONFIG=$CHKSYSCONFIG "$SETUP"
grep -Fxq sort_settings "$EVENTS"
grep -Fxq 'set_setting clouddrive.mounted 0' "$EVENTS"
grep -Fxq 'clouddrive.mounted=0' "$SYSTEM_CONFIG"

UI_PROFILE=$PROFILE_DIR/090-ui_service
BIRD_UI_PROFILE=$UI_PROFILE "$UI"
UI_MTIME=$(stat -f '%m' "$UI_PROFILE" 2>/dev/null || stat -c '%Y' "$UI_PROFILE")
sleep 1
BIRD_UI_PROFILE=$UI_PROFILE "$UI"
[ "$UI_MTIME" = "$(stat -f '%m' "$UI_PROFILE" 2>/dev/null || stat -c '%Y' "$UI_PROFILE")" ]
printf '%s\n' broken >"$UI_PROFILE"
BIRD_UI_PROFILE=$UI_PROFILE "$UI"
[ "$(cat "$UI_PROFILE")" = 'UI_SERVICE="essway.service"' ]

printf '%s\n' 'stock-root fixed setup tests: PASS'
