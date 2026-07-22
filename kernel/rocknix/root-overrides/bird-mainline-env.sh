#!/bin/sh
# On-demand userspace bridge for Bird's source kernel. Nothing in this file is
# executed on the visible boot path: S03danilauncher calls PREPARE only after a
# content or PortMaster selection.

BIRD_RUNTIME_IMAGE="/mnt/mmc/MUOS/runtime/ROCKNIX-SYSTEM"
BIRD_RUNTIME_ROOT="/run/bird-rocknix"
BIRD_COMPAT_LIB="/run/bird-mainline-lib"
BIRD_MALI_STUB="/run/muos/libmali-bird-stub.so"
BIRD_DRM_DIAG_MARKER="/run/muos/bird-drm-diagnosed"

BIRD_MAINLINE_MOUNTED() {
	while IFS=' ' read -r _ MOUNT_POINT _; do
		[ "$MOUNT_POINT" = "$BIRD_RUNTIME_ROOT" ] && return 0
	done </proc/mounts
	return 1
}

BIRD_MAINLINE_LINK() {
	LINK_NAME=$1
	LINK_TARGET=$2
	[ -e "$LINK_TARGET" ] || return 1
	ln -sf "$LINK_TARGET" "$BIRD_COMPAT_LIB/$LINK_NAME"
}

BIRD_MAINLINE_WAIT_GPU() {
	# S10udev starts Panfrost automatically after Bird's first frame. A content
	# selection made unusually early waits for that warm-up; it never owns or
	# initiates GPU setup itself.
	GPU_WAIT=0
	while [ ! -e /dev/dri/renderD128 ]; do
		GPU_WAIT=$((GPU_WAIT + 1))
		[ "$GPU_WAIT" -lt 200 ] || return 1
		sleep 0.01
	done
	printf 'mainline gpu ready: display=/dev/dri/card0 render=/dev/dri/renderD128\n'
}

BIRD_MAINLINE_REASSERT() {
	# Stock launch helpers prepend GL4ES and the frontend libraries. Preserve
	# those helpers, but keep the source-kernel graphics ABI first at exec time.
	NEW_LIBRARY_PATH=
	OLD_IFS=$IFS
	IFS=:
	for LIBRARY_PATH_ITEM in ${LD_LIBRARY_PATH-}; do
		[ -n "$LIBRARY_PATH_ITEM" ] || continue
		[ "$LIBRARY_PATH_ITEM" = "$BIRD_COMPAT_LIB" ] && continue
		NEW_LIBRARY_PATH="${NEW_LIBRARY_PATH}${NEW_LIBRARY_PATH:+:}$LIBRARY_PATH_ITEM"
	done
	IFS=$OLD_IFS
	LD_LIBRARY_PATH="$BIRD_COMPAT_LIB${NEW_LIBRARY_PATH:+:$NEW_LIBRARY_PATH}"

	# libmustage is a vendor-era display interposer. The Bird launcher already
	# owns transitions, so content does not need it on mainline DRM.
	unset LD_PRELOAD
	export LD_LIBRARY_PATH
	export SDL_VIDEODRIVER=kmsdrm
	# Bird registers the fixed sun4i panel before asynchronously warming
	# Panfrost, so the display is card0 and the later GPU supplies renderD128.
	export SDL_KMSDRM_DEVICE_INDEX=0
	# Keep one compatibility cycle verbose enough to expose SDL's exact device,
	# connector, DRM-master and GBM decisions in the preserved content log.
	export SDL_LOGGING=video=debug
	export LIBGL_DRIVERS_PATH="$BIRD_RUNTIME_ROOT/usr/lib/dri"
	export GBM_BACKENDS_PATH="$BIRD_RUNTIME_ROOT/usr/lib/gbm"
	export __EGL_VENDOR_LIBRARY_FILENAMES="$BIRD_RUNTIME_ROOT/usr/share/glvnd/egl_vendor.d/50_mesa.json"
	export MESA_LOADER_DRIVER_OVERRIDE=panfrost
}

BIRD_MAINLINE_DIAGNOSE() {
	[ -e "$BIRD_DRM_DIAG_MARKER" ] && return 0
	: >"$BIRD_DRM_DIAG_MARKER"
	printf 'mainline graphics env: SDL_VIDEODRIVER=%s SDL_KMSDRM_DEVICE_INDEX=%s\n' \
		"${SDL_VIDEODRIVER-}" "${SDL_KMSDRM_DEVICE_INDEX-}"
	printf '%s\n' 'mainline DRM nodes:'
	ls -l /dev/dri/card* /dev/dri/render* 2>&1 || :
	printf '%s\n' 'mainline card0 connectors:'
	for CONNECTOR_STATUS in /sys/class/drm/card0-*/status; do
		[ -r "$CONNECTOR_STATUS" ] || continue
		printf '%s=' "${CONNECTOR_STATUS%/status}"
		cat "$CONNECTOR_STATUS"
	done
	if [ -x "$BIRD_RUNTIME_ROOT/usr/bin/modetest" ]; then
		printf '%s\n' 'mainline modetest card0:'
		"$BIRD_RUNTIME_ROOT/usr/bin/modetest" -D /dev/dri/card0 -c 2>&1 || :
	fi
	if command -v retroarch >/dev/null 2>&1; then
		printf '%s\n' 'mainline RetroArch loader trace:'
		LD_TRACE_LOADED_OBJECTS=1 retroarch 2>&1 | \
			grep -E 'SDL|EGL|GLES|gbm|drm|mali' || :
	fi
}

BIRD_MAINLINE_PREPARE() {
	[ -r "$BIRD_RUNTIME_IMAGE" ] || {
		printf 'Bird mainline runtime missing: %s\n' "$BIRD_RUNTIME_IMAGE" >&2
		return 1
	}
	[ -r "$BIRD_MALI_STUB" ] || {
		printf 'Bird Mali ABI stub missing: %s\n' "$BIRD_MALI_STUB" >&2
		return 1
	}
	BIRD_MAINLINE_WAIT_GPU || {
		printf '%s\n' 'Bird asynchronous Panfrost warm-up timed out' >&2
		return 1
	}

	mkdir -p "$BIRD_RUNTIME_ROOT" "$BIRD_COMPAT_LIB"
	if ! BIRD_MAINLINE_MOUNTED; then
		mount -t squashfs -o loop,ro "$BIRD_RUNTIME_IMAGE" \
			"$BIRD_RUNTIME_ROOT" || return 1
	fi

	BIRD_MAINLINE_LINK libSDL2-2.0.so.0 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libSDL2-2.0.so.0.3200.10" || return 1
	BIRD_MAINLINE_LINK libEGL.so.1 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libEGL.so.1.1.0" || return 1
	BIRD_MAINLINE_LINK libGLESv2.so.2 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libGLESv2.so.2.1.0" || return 1
	BIRD_MAINLINE_LINK libGLESv1_CM.so.1 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libGLESv1_CM.so.1.2.0" || return 1
	BIRD_MAINLINE_LINK libGLdispatch.so.0 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libGLdispatch.so.0.0.0" || return 1
	BIRD_MAINLINE_LINK libEGL_mesa.so.0 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libEGL_mesa.so.0.0.0" || return 1
	BIRD_MAINLINE_LINK libgbm.so.1 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libgbm.so.1.0.0" || return 1
	BIRD_MAINLINE_LINK libdrm.so.2 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libdrm.so.2.128.0" || return 1
	BIRD_MAINLINE_LINK libgallium-26.1.2.so \
		"$BIRD_RUNTIME_ROOT/usr/lib/libgallium-26.1.2.so" || return 1
	# Mesa's shared EGL build has unconditional ELF dependencies on these
	# display-protocol libraries even when Bird selects the DRM/GBM path.  The
	# old muOS root has the stable base X11/XCB/FFI ABIs, but not these sonames.
	BIRD_MAINLINE_LINK libX11-xcb.so.1 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libX11-xcb.so.1.0.0" || return 1
	BIRD_MAINLINE_LINK libxcb-randr.so.0 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libxcb-randr.so.0.1.0" || return 1
	BIRD_MAINLINE_LINK libxcb-xfixes.so.0 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libxcb-xfixes.so.0.0.0" || return 1
	BIRD_MAINLINE_LINK libxcb-dri3.so.0 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libxcb-dri3.so.0.1.0" || return 1
	BIRD_MAINLINE_LINK libxcb-present.so.0 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libxcb-present.so.0.0.0" || return 1
	BIRD_MAINLINE_LINK libxcb-sync.so.1 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libxcb-sync.so.1.0.0" || return 1
	BIRD_MAINLINE_LINK libxshmfence.so.1 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libxshmfence.so.1.0.0" || return 1
	BIRD_MAINLINE_LINK libwayland-client.so.0 \
		"$BIRD_RUNTIME_ROOT/usr/lib/libwayland-client.so.0.23.1" || return 1
	ln -sf "$BIRD_MALI_STUB" "$BIRD_COMPAT_LIB/libmali.so.0"

	BIRD_MAINLINE_REASSERT
	BIRD_MAINLINE_DIAGNOSE
	return 0
}
