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
		flycastvl_libretro.so) printf '%s\n' flycast_libretro.so ;;
		km_fbneo_xtreme_amped_libretro.so) printf '%s\n' fbneo_libretro.so ;;
		mednafen_pce_fast_libretro.so) printf '%s\n' beetle_pce_fast_libretro.so ;;
		ext-drastic) printf '%s\n' melonds_libretro.so ;;
		ext-ppsspp) printf '%s\n' ppsspp_libretro.so ;;
		*) printf '%s\n' "$1" ;;
	esac
}

run_retroarch() {
	CORE=$(native_core "$1")
	[ -r "$RUNTIME/usr/lib/libretro/$CORE" ] || {
		printf 'Bird native core missing: %s\n' "$CORE"
		return 1
	}
	/usr/sbin/chroot "$RUNTIME" /usr/bin/env -i \
		HOME=/storage/MUOS/Bird \
		USER=root LANG=C \
		PATH=/usr/bin:/usr/sbin:/bin:/sbin \
		LIBGL_DRIVERS_PATH=/usr/lib/dri \
		GBM_BACKENDS_PATH=/usr/lib/gbm \
		__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json \
		LIBGL_DEBUG=verbose \
		/usr/bin/retroarch --verbose --fullscreen \
		--config /usr/config/retroarch/retroarch.cfg \
		--appendconfig /run/bird/retroarch-append.cfg \
		-L "/usr/lib/libretro/$CORE" "$CONTENT"
}

run_mpv() {
	case "$CONTENT" in
		*.mp3|*.MP3|*.flac|*.FLAC|*.ogg|*.OGG|*.opus|*.OPUS|*.wav|*.WAV|*.m4a|*.M4A)
			VIDEO_OPTIONS='--vid=no --force-window=no'
			;;
		*)
			# Direct DRM is the compositor-free correctness path. Replace the
			# software VO with the measured Panfrost GPU path after it is proven.
			VIDEO_OPTIONS='--vo=drm --drm-device=/dev/dri/card0'
			;;
	esac
	/usr/sbin/chroot "$RUNTIME" /usr/bin/env -i \
		HOME=/storage/MUOS/Bird USER=root LANG=C \
		PATH=/usr/bin:/usr/sbin:/bin:/sbin \
		SDL_GAMECONTROLLERCONFIG_FILE=/run/bird/h700-sdl-gamecontrollerdb.txt \
		/usr/bin/mpv --no-config --hwdec=no --ao=alsa --fullscreen \
		--input-gamepad=yes \
		--audio-device=alsa/hw:0,0 \
		--input-conf=/run/bird/mpv-input.conf $VIDEO_OPTIONS "$CONTENT"
}

cleanup_content() {
	rm -f "$ACTIVE" "$ACTIVE_PID"
}

: >"$ACTIVE"
printf '%s\n' "$$" >"$ACTIVE_PID"
trap cleanup_content EXIT INT TERM
{
	printf 'Bird native content start uptime: '
	cut -d ' ' -f 1 /proc/uptime
	printf 'kind=%s requested_core=%s name=%s path=%s\n' \
		"$KIND" "$REQUESTED_CORE" "$NAME" "$CONTENT"
	case "$KIND" in
		1) run_retroarch "$REQUESTED_CORE" ;;
		2) run_retroarch ext-ppsspp ;;
		4) run_retroarch ext-drastic ;;
		6) run_mpv ;;
		*)
			printf 'Bird native launch kind not implemented yet: %s\n' "$KIND"
			false
			;;
	esac
	RESULT=$?
	printf 'Bird native content result=%s uptime=' "$RESULT"
	cut -d ' ' -f 1 /proc/uptime
} >"$LOG" 2>&1
cp -f "$LOG" "$LATEST"
dmesg >"$LOG.dmesg" 2>&1 || :
cleanup_content
trap - EXIT INT TERM
exit "$RESULT"
