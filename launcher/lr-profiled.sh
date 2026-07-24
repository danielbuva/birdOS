#!/bin/sh

# Behavior-identical copy of muOS 2601.1 lr-general.sh with monotonic markers
# around each generic setup phase. This is temporary measurement scaffolding;
# the result will define the birdOS fixed libretro launch bridge.

PROFILE_STAGE() {
	IFS=' ' read -r PROFILE_UPTIME _ </proc/uptime
	printf 'libretro profile stage=%s uptime=%s\n' "$1" "$PROFILE_UPTIME"
}

PROFILE_STAGE script-entry
. /opt/muos/script/var/func.sh
PROFILE_STAGE func-loaded

NAME=$1
CORE=$2
FILE=${3%/}

LOG_INFO "$0" 0 "Content Launch" "DETAIL"
LOG_INFO "$0" 0 "NAME" "$NAME"
LOG_INFO "$0" 0 "CORE" "$CORE"
LOG_INFO "$0" 0 "FILE" "$FILE"
PROFILE_STAGE logging-complete

HOME="$(GET_VAR "device" "board/home")"
export HOME
PROFILE_STAGE home-ready

SETUP_STAGE_OVERLAY
PROFILE_STAGE stage-overlay-ready
SETUP_SDL_ENVIRONMENT
PROFILE_STAGE sdl-ready

SET_VAR "system" "foreground_process" "retroarch"
PROFILE_STAGE foreground-ready

RA_ARGS=$(CONFIGURE_RETROARCH)
PROFILE_STAGE retroarch-config-ready
IS_SWAP=$(DETECT_CONTROL_SWAP)
PROFILE_STAGE control-swap-ready

if echo "$CORE" | grep -qE "flycast|morpheuscast"; then
	export SDL_NO_SIGNAL_HANDLERS=1
fi

if echo "$CORE" | grep -q "j2me"; then
	export JAVA_HOME=/opt/java
	PATH=$PATH:$JAVA_HOME/bin
fi

PROFILE_STAGE retroarch-exec
retroarch -v -f $RA_ARGS -L "$MUOS_SHARE_DIR/core/$CORE" "$FILE"
PROFILE_STAGE retroarch-exit

[ "$IS_SWAP" -eq 1 ] && DETECT_CONTROL_SWAP
