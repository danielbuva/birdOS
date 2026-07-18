#!/bin/bash
# Fixed RG34XX-SP/muOS launcher for the PortMaster compatibility build.

set -o pipefail

controlfolder="/mnt/mmc/MUOS/PortMaster"
gamedir="/mnt/mmc/ports/stardewvalley"
monodir="$HOME/mono"
monofile="$controlfolder/libs/mono-6.12.0.122-aarch64.squashfs"

source "$controlfolder/control.txt"
source "$controlfolder/device_info.txt"
source "$controlfolder/tasksetter"
source "$controlfolder/mod_muOS.txt"
get_controls
cd "$gamedir" || exit 1

cleanup() {
	pkill -9 -f gptokeyb 2>/dev/null || true
	umount "$monodir" 2>/dev/null || true
	printf "\033c" > /dev/tty0 2>/dev/null || true
}
trap cleanup EXIT INT TERM

chmod 666 /dev/tty0
printf "\033c" >/dev/tty0
printf '%s\n' "Loading Stardew Valley..." >/dev/tty0

if [ ! -s "$monofile" ]; then
	printf 'Missing Mono runtime: %s\n' "$monofile" | tee "$gamedir/log.txt"
	exit 1
fi

mkdir -p "$monodir"
umount "$monodir" 2>/dev/null || true
if ! mount -o loop,ro "$monofile" "$monodir"; then
	printf 'Could not mount Mono runtime: %s\n' "$monofile" | tee "$gamedir/log.txt"
	exit 1
fi

bind_directories "$HOME/.config/StardewValley" "$gamedir/savedata"

export MONOGAME_PATCH="$gamedir/dlls/StardewPatches.dll"
export MONO_PATH="$gamedir/dlls:$gamedir"
export PATH="$monodir/bin:$PATH"
export LD_LIBRARY_PATH="$gamedir/libs:$LD_LIBRARY_PATH"

rm -f "$gamedir/libs/libGL.so.1" "$gamedir/libs/libEGL.so.1"
source "$controlfolder/libgl_muOS.txt"
if [ -n "$LIBGL_ES" ]; then
	export SDL_VIDEO_GL_DRIVER="$gamedir/gl4es/libGL.so.1"
	export SDL_VIDEO_EGL_DRIVER="$gamedir/gl4es/libEGL.so.1"
fi

cd "$gamedir/gamedata" || exit 1
for ASSEMBLY in System.Data*.dll; do
	[ -f "$ASSEMBLY" ] && mv "$ASSEMBLY" "$gamedir/dlls/"
done
rm -f MonoGame.Framework.* System*.dll

if [ -f "Stardew Valley.exe" ]; then
	gameassembly="Stardew Valley.exe"
	cp "$gamedir/dlls/Stardew Valley.exe.config" \
		"$gamedir/gamedata/Stardew Valley.exe.config"
elif [ -f "StardewValley.exe" ]; then
	gameassembly="StardewValley.exe"
else
	printf '%s\n' 'No compatible Stardew Valley executable found.' | tee "$gamedir/log.txt"
	exit 1
fi

$GPTOKEYB "mono" &
$TASKSET mono ../SVLoader.exe "$gameassembly" 2>&1 | tee "$gamedir/log.txt"
exit $?
