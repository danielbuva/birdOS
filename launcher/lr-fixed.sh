#!/bin/sh

# Fixed libretro bridge for Dani's RG34XX-SP. The mutable muOS launcher has
# already produced the required RetroArch files; this path contains only the
# exact constant environment and controller map used by this device.

HOME=/root
XDG_RUNTIME_DIR=/run
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket
PIPEWIRE_RUNTIME_DIR=/run
ALSA_CONFIG=/usr/share/alsa/alsa.conf
MUOS_SHARE_DIR=/opt/muos/share
LD_LIBRARY_PATH=/usr/lib/gl4es:/opt/muos/frontend/lib

SDL_ASSERT=always_ignore
SDL_HQ_SCALER=0
SDL_ROTATION=0
SDL_BLITTER_DISABLED=1
SDL_GAMECONTROLLERCONFIG='19000000010000000100000000010000,muOS-Keys,a:b3,b:b4,x:b6,y:b5,leftshoulder:b7,rightshoulder:b8,lefttrigger:b13,righttrigger:b14,guide:b11,start:b10,back:b9,dpup:h0.1,dpleft:h0.8,dpright:h0.2,dpdown:h0.4,volumedown:b1,volumeup:b2,leftx:a0,lefty:a1,leftstick:b12,rightx:a2,righty:a3,rightstick:b15,platform:Linux,'

export HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS PIPEWIRE_RUNTIME_DIR
export ALSA_CONFIG MUOS_SHARE_DIR LD_LIBRARY_PATH
export SDL_ASSERT SDL_HQ_SCALER SDL_ROTATION SDL_BLITTER_DISABLED
export SDL_GAMECONTROLLERCONFIG

NAME=$1
CORE=$2
FILE=${3%/}

printf '%s' retroarch >/opt/muos/config/system/foreground_process

case "$CORE" in
	*flycast* | *morpheuscast*) export SDL_NO_SIGNAL_HANDLERS=1 ;;
	*j2me*)
		JAVA_HOME=/opt/java
		PATH=$PATH:$JAVA_HOME/bin
		export JAVA_HOME PATH
		;;
esac

IFS=' ' read -r FIXED_LAUNCH_UPTIME _ </proc/uptime
printf 'fixed libretro exec uptime=%s core=%s name=%s\n' \
	"$FIXED_LAUNCH_UPTIME" "$CORE" "$NAME"

# Diagnostics remain enabled for this proof. The final bridge drops -v after
# its exact error and save-state requirements have been captured.
exec retroarch -v -f -L "$MUOS_SHARE_DIR/core/$CORE" "$FILE"
