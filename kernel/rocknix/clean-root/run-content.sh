#!/bin/sh
# Bird-owned native application policy. Every executable and libretro core in
# this file comes from the same mounted ROCKNIX runtime; no muOS wrapper,
# binary, core, configuration or shared library is executed.

REQUEST=${1:-/run/muos/dani-launch-request}
RUNTIME=/run/bird-runtime
LOG_DIR=/mnt/mmc/MUOS/Bird/log
LATEST=$LOG_DIR/content-latest.log
ACTIVE=/run/bird/content-active
ACTIVE_PID=/run/bird/content.pid
SESSION_PID=/run/bird/content-session.pid
PERFORMANCE_ACTIVE=0

[ -s "$REQUEST" ] || exit 1
{
	IFS= read -r KIND
	IFS= read -r REQUESTED_CORE
	IFS= read -r NAME
	IFS= read -r HOST_PATH
} <"$REQUEST"
rm -f "$REQUEST"

case "$HOST_PATH" in
	/mnt/mmc/*) CONTENT=/storage/${HOST_PATH#/mnt/mmc/} ;;
	*) printf 'Bird rejected non-storage content path: %s\n' "$HOST_PATH" >"$LATEST"; exit 1 ;;
esac

mkdir -p "$LOG_DIR"
BOOT_TAG=$(cut -d ' ' -f 1 /proc/uptime | tr -d .)
LOG=$LOG_DIR/content-${BOOT_TAG}-kind${KIND}.log

native_core() {
	case "$1" in
		stella2014_libretro.so) printf '%s\n' stella_libretro.so ;;
		# ROCKNIX deliberately defaults H700 Dreamcast, Naomi and
		# Atomiswave to its LOW_END/LOW_RES AArch64 Flycast 2021 build.
		flycastvl_libretro.so) printf '%s\n' flycast2021_libretro.so ;;
		km_fbneo_xtreme_amped_libretro.so) printf '%s\n' fbneo_libretro.so ;;
		mednafen_pce_fast_libretro.so) printf '%s\n' beetle_pce_fast_libretro.so ;;
		*) printf '%s\n' "$1" ;;
	esac
}

run_session() {
	/usr/bin/setsid "$@" &
	SESSION=$!
	printf '%s\n' "$SESSION" >"$SESSION_PID"
	wait "$SESSION"
	STATUS=$?
	# A wrapper may exit before its game or controller helper. Drain the whole
	# fixed content process group before handing the display back to Bird.
	/bin/kill -TERM "-$SESSION" 2>/dev/null || :
	COUNT=0
	while /bin/kill -0 "-$SESSION" 2>/dev/null && [ "$COUNT" -lt 20 ]; do
		COUNT=$((COUNT + 1))
		/bin/usleep 10000
	done
	/bin/kill -KILL "-$SESSION" 2>/dev/null || :
	rm -f "$SESSION_PID"
	return "$STATUS"
}

clear_launcher_frame() {
	# The static launcher has exited before application dispatch, but fbcon can
	# briefly rescan its last pixels while an SDL app recreates a KMS window.
	# Erase that fixed 720x480x32bpp backing store once at the app boundary.
	dd if=/dev/zero of=/dev/fb0 bs=1382400 count=1 2>/dev/null || :
}

run_retroarch() {
	CORE=$(native_core "$1")
	[ -r "$RUNTIME/usr/lib/libretro/$CORE" ] || {
		printf 'Bird native core missing: %s\n' "$CORE"
		return 1
	}
	if [ "$CORE" = flycast2021_libretro.so ]; then
		MIGRATION=/mnt/mmc/MUOS/Bird/migrations/v5.3-flycast2021
		if [ ! -e "$MIGRATION" ]; then
			mkdir -p "${MIGRATION%/*}"
			rm -f "/mnt/mmc/MUOS/Bird/.config/retroarch/config/Flycast/Flycast.opt"
			: >"$MIGRATION"
			printf '%s\n' 'Bird cleared incompatible modern Flycast options once'
		fi
	fi
	run_session /usr/sbin/chroot "$RUNTIME" /usr/bin/env -i \
		HOME=/storage/MUOS/Bird \
		USER=root LANG=C XDG_RUNTIME_DIR=/run/bird/xdg \
		PATH=/usr/bin:/usr/sbin:/bin:/sbin \
		LIBGL_DRIVERS_PATH=/usr/lib/dri \
		GBM_BACKENDS_PATH=/usr/lib/gbm \
		__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json \
		/usr/bin/retroarch --verbose --fullscreen \
		--config /usr/config/retroarch/retroarch.cfg \
		--appendconfig /run/bird/retroarch-append.cfg \
		-L "/usr/lib/libretro/$CORE" "$CONTENT"
}

prepare_drastic() {
	HOST_DIR=/mnt/mmc/MUOS/Bird/apps/drastic
	if [ ! -x "$HOST_DIR/drastic" ]; then
		mkdir -p "$HOST_DIR"
		cp -R "$RUNTIME/usr/config/drastic/." "$HOST_DIR/" || return 1
		printf '%s\n' 'Bird installed native H700 DraStic payload'
	fi
	mkdir -p "$HOST_DIR/backup" "$HOST_DIR/savestates"
}

run_drastic() {
	prepare_drastic || return 1
	run_session /usr/sbin/chroot "$RUNTIME" /usr/bin/env -i \
		HOME=/storage/MUOS/Bird/home USER=root LANG=C \
		PATH=/usr/bin:/usr/sbin:/bin:/sbin \
		XDG_RUNTIME_DIR=/run/bird/xdg \
		AUDIODEV=hw:0,0 SDL_AUDIODRIVER=alsa \
		SDL_VIDEODRIVER=kmsdrm SDL_RENDER_DRIVER=opengl \
		SDL_KMSDRM_DEVICE_INDEX=0 \
		SDL_GAMECONTROLLERCONFIG_FILE=/run/bird/h700-sdl-gamecontrollerdb.txt \
		LD_PRELOAD=/usr/lib/libdrastouch.so \
		DSHOOK_MIC_THRESH=0 DSHOOK_SHADER=none SDL_TOUCH_MOUSE_EVENTS=0 \
		/usr/bin/bash -c \
		'cd /storage/MUOS/Bird/apps/drastic && exec ./drastic "$1"' \
		bird-drastic "$CONTENT"
}

prepare_ppsspp() {
	HOST_DIR=/mnt/mmc/.config/ppsspp
	if [ ! -r "$HOST_DIR/PSP/SYSTEM/ppsspp.ini" ]; then
		mkdir -p "$HOST_DIR"
		# The runtime's assets include a symlink that exFAT cannot represent.
		# PPSSPP already loads immutable assets from /usr/share/ppsspp, so only
		# its writable PSP configuration tree belongs on the data volume.
		cp -R "$RUNTIME/usr/config/ppsspp/PSP" "$HOST_DIR/" || return 1
		printf '%s\n' 'Bird installed native H700 PPSSPP payload'
	fi
	INI=$HOST_DIR/PSP/SYSTEM/ppsspp.ini
	if grep -q '^TransparentBackground = ' "$INI"; then
		sed -i 's/^TransparentBackground = .*/TransparentBackground = False/' "$INI"
	else
		sed -i '/^\[CPU\]/i TransparentBackground = False' "$INI"
	fi
	# Driver and PPSSPP version changes invalidate persisted GL programs.
	MIGRATION=/mnt/mmc/MUOS/Bird/migrations/v5.4-ppsspp-kms
	if [ ! -e "$MIGRATION" ]; then
		rm -f "$HOST_DIR"/PSP/SYSTEM/CACHE/*.glshadercache
		: >"$MIGRATION"
	fi
	mkdir -p /mnt/mmc/roms/savestates/psp/ppsspp-sa
}

run_ppsspp() {
	prepare_ppsspp || return 1
	run_session /usr/sbin/chroot "$RUNTIME" /usr/bin/env -i \
		HOME=/storage/MUOS/Bird/home USER=root LANG=C \
		PATH=/usr/bin:/usr/sbin:/bin:/sbin \
		XDG_RUNTIME_DIR=/run/bird/xdg \
		AUDIODEV=hw:0,0 SDL_AUDIODRIVER=alsa \
		SDL_VIDEODRIVER=kmsdrm SDL_RENDER_DRIVER=opengles2 \
		SDL_KMSDRM_DEVICE_INDEX=0 \
		SDL_GAMECONTROLLERCONFIG_FILE=/run/bird/h700-sdl-gamecontrollerdb.txt \
		/usr/bin/ppsspp --fullscreen --pause-menu-exit "$CONTENT"
}

run_port() {
	[ -r /mnt/mmc/MUOS/PortMaster/control.txt ] || {
		printf '%s\n' 'Bird PortMaster payload missing'
		return 1
	}
	run_session /usr/sbin/chroot "$RUNTIME" /usr/bin/env -i \
		HOME=/storage/MUOS/Bird/home USER=root LANG=C \
		XDG_DATA_HOME=/storage/MUOS \
		XDG_CONFIG_HOME=/storage/MUOS/Bird/home/.config \
		XDG_RUNTIME_DIR=/run/bird/xdg \
		PATH=/usr/bin:/usr/sbin:/bin:/sbin:/storage/MUOS/PortMaster \
		AUDIODEV=hw:0,0 SDL_AUDIODRIVER=alsa \
		ALSA_CONFIG_PATH=/run/bird/asound-bird.conf \
		ALSOFT_DRIVERS=alsa \
		SDL_VIDEODRIVER=kmsdrm SDL_RENDER_DRIVER=opengles2 \
		SDL_KMSDRM_DEVICE_INDEX=0 \
		SDL_GAMECONTROLLERCONFIG_FILE=/run/bird/h700-sdl-gamecontrollerdb.txt \
		LIBGL_DRIVERS_PATH=/usr/lib/dri \
		GBM_BACKENDS_PATH=/usr/lib/gbm \
		__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json \
		/usr/bin/bash -c \
		'sed "s#/mnt/mmc#/storage#g" "$1" > /run/bird/port-launch.sh && exec /usr/bin/bash /run/bird/port-launch.sh' \
		bird-port "$CONTENT"
}

run_mpv() {
	case "$CONTENT" in
		*.mp3|*.MP3|*.flac|*.FLAC|*.ogg|*.OGG|*.opus|*.OPUS|*.wav|*.WAV|*.m4a|*.M4A)
			run_session /usr/sbin/chroot "$RUNTIME" /usr/bin/env -i \
				HOME=/storage/MUOS/Bird USER=root LANG=C \
				PATH=/usr/bin:/usr/sbin:/bin:/sbin \
				SDL_GAMECONTROLLERCONFIG_FILE=/run/bird/h700-sdl-gamecontrollerdb.txt \
				/usr/bin/mpv --no-config --hwdec=no --ao=alsa \
				--vid=no --force-window=no --input-gamepad=yes \
				--no-input-default-bindings --term-status-msg= \
				--audio-device=alsa/hw:0,0 \
				--input-conf=/run/bird/mpv-input.conf "$CONTENT"
			;;
		*)
			# MPV's gamepad input initializes SDL before the SDL video output,
			# which makes that output reject its second SDL owner. Direct DRM is
			# the proven compositor-free display path until Bird builds MPV with
			# a native EGL/V4L2-request output.
			run_session /usr/sbin/chroot "$RUNTIME" /usr/bin/env -i \
				HOME=/storage/MUOS/Bird USER=root LANG=C \
				PATH=/usr/bin:/usr/sbin:/bin:/sbin \
				SDL_GAMECONTROLLERCONFIG_FILE=/run/bird/h700-sdl-gamecontrollerdb.txt \
				/usr/bin/mpv --no-config --hwdec=no --ao=alsa \
				--vo=drm --drm-device=/dev/dri/card0 \
				--fullscreen --input-gamepad=yes \
				--no-input-default-bindings --term-status-msg= \
				--audio-device=alsa/hw:0,0 \
				--input-conf=/run/bird/mpv-input.conf "$CONTENT"
			;;
	esac
}

needs_performance() {
	case "$KIND" in
		1|2|3|4) return 0 ;;
		6)
			case "$CONTENT" in
				*.mp3|*.MP3|*.flac|*.FLAC|*.ogg|*.OGG|*.opus|*.OPUS|*.wav|*.WAV|*.m4a|*.M4A) ;;
				*) return 0 ;;
			esac
			;;
	esac
	return 1
}

stop_session() {
	[ -s "$SESSION_PID" ] || return 0
	SESSION=$(cat "$SESSION_PID")
	case "$SESSION" in *[!0-9]*|'') return 0 ;; esac
	/bin/kill -TERM "-$SESSION" 2>/dev/null || :
}

cleanup_content() {
	stop_session
	if [ "$PERFORMANCE_ACTIVE" = 1 ]; then
		/opt/bird/content-performance.sh leave || :
		PERFORMANCE_ACTIVE=0
	fi
	rm -f "$ACTIVE" "$ACTIVE_PID" "$SESSION_PID"
}

: >"$ACTIVE"
printf '%s\n' "$$" >"$ACTIVE_PID"
trap cleanup_content EXIT INT TERM
{
	printf 'Bird native content start uptime: '
	cut -d ' ' -f 1 /proc/uptime
	printf 'kind=%s requested_core=%s name=%s path=%s\n' \
		"$KIND" "$REQUESTED_CORE" "$NAME" "$CONTENT"
	/opt/bird/content-performance.sh snapshot
	if needs_performance; then
		/opt/bird/content-performance.sh enter
		PERFORMANCE_ACTIVE=1
	fi
	clear_launcher_frame
	case "$KIND" in
		1) run_retroarch "$REQUESTED_CORE" ;;
		2) run_ppsspp ;;
		3) run_port ;;
		4) run_drastic ;;
		6) run_mpv ;;
		*)
			printf 'Bird native launch kind not implemented yet: %s\n' "$KIND"
			false
			;;
	esac
	RESULT=$?
	if [ "$PERFORMANCE_ACTIVE" = 1 ]; then
		/opt/bird/content-performance.sh leave || :
		PERFORMANCE_ACTIVE=0
	fi
	printf 'Bird native content result=%s uptime=' "$RESULT"
	cut -d ' ' -f 1 /proc/uptime
} >"$LOG" 2>&1
cp -f "$LOG" "$LATEST"
dmesg >"$LOG.dmesg" 2>&1 || :
cleanup_content
trap - EXIT INT TERM
exit "$RESULT"
