#!/bin/sh
# All work here begins after the static menu is input-ready. Storage, GPU and
# the native application runtime are independent of Bird's visible boot gate.

set -u

DATA_DEVICE=/dev/mmcblk0p6
DATA_ROOT=/mnt/mmc
RUNTIME_IMAGE=$DATA_ROOT/MUOS/runtime/ROCKNIX-SYSTEM
RUNTIME_ROOT=/run/bird-runtime
READY=/run/bird/runtime-ready
LOG=/tmp/bird-post-frame.log

mark() {
	printf 'uptime=' >>"$LOG"
	cut -d ' ' -f 1 /proc/uptime >>"$LOG"
	printf ' stage=%s\n' "$1" >>"$LOG"
}

mounted_at() {
	while IFS=' ' read -r _ POINT _; do
		[ "$POINT" = "$1" ] && return 0
	done </proc/mounts
	return 1
}

bind_once() {
	SOURCE=$1
	TARGET=$2
	mounted_at "$TARGET" || mount -o bind "$SOURCE" "$TARGET"
}

: >"$LOG"
mark post-frame-start

COUNT=0
while [ ! -b "$DATA_DEVICE" ]; do
	COUNT=$((COUNT + 1))
	[ "$COUNT" -lt 200 ] || {
		mark data-device-timeout
		exit 1
	}
	/bin/usleep 10000
done

mounted_at "$DATA_ROOT" || \
	mount -t exfat -o noatime "$DATA_DEVICE" "$DATA_ROOT" || {
		mark data-mount-failed
		exit 1
	}
mark data-ready

# Global controls consume raw fixed-device events and are useful immediately;
# they do not depend on GPU or application-runtime readiness.
/opt/bird/controls >>/tmp/bird-controls.log 2>&1 &
printf '%s\n' "$!" >/run/bird/controls.pid

# Panfrost is not needed to paint or operate Bird. Warm it now so a selection
# can use native Mesa without making the launcher own GPU initialization.
if [ ! -e /dev/dri/renderD128 ]; then
	for MODULE in \
		/opt/bird/drm_shmem_helper.ko \
		/opt/bird/gpu-sched.ko \
		/opt/bird/panfrost.ko; do
		[ -r "$MODULE" ] || {
			mark gpu-module-missing
			exit 1
		}
	done
	[ -d /sys/module/drm_shmem_helper ] || \
		/sbin/insmod /opt/bird/drm_shmem_helper.ko || exit 1
	[ -d /sys/module/gpu_sched ] || \
		/sbin/insmod /opt/bird/gpu-sched.ko || exit 1
	/sbin/insmod /opt/bird/panfrost.ko || [ -e /dev/dri/renderD128 ] || exit 1
fi
COUNT=0
while [ ! -e /dev/dri/renderD128 ]; do
	COUNT=$((COUNT + 1))
	[ "$COUNT" -lt 200 ] || {
		mark gpu-timeout
		exit 1
	}
	/bin/usleep 10000
done
chmod 0666 /dev/dri/card0 /dev/dri/renderD128 2>/dev/null || :
mark gpu-ready

[ -r "$RUNTIME_IMAGE" ] || {
	mark runtime-image-missing
	exit 1
}
mkdir -p "$RUNTIME_ROOT"
mounted_at "$RUNTIME_ROOT" || \
	mount -t squashfs -o loop,ro "$RUNTIME_IMAGE" "$RUNTIME_ROOT" || {
		mark runtime-mount-failed
		exit 1
	}

# A chroot is used as a coherent ABI boundary, not as Bird's operating-system
# root. The immutable runtime supplies an application and all of its matching
# libraries; only live kernel interfaces and the data card cross the boundary.
bind_once /dev "$RUNTIME_ROOT/dev" || exit 1
bind_once /proc "$RUNTIME_ROOT/proc" || exit 1
bind_once /sys "$RUNTIME_ROOT/sys" || exit 1
bind_once /run "$RUNTIME_ROOT/run" || exit 1
bind_once /tmp "$RUNTIME_ROOT/tmp" || exit 1
bind_once "$DATA_ROOT" "$RUNTIME_ROOT/storage" || exit 1

mkdir -p "$DATA_ROOT/MUOS/Bird/log" \
	"$DATA_ROOT/MUOS/Bird/apps" \
	"$DATA_ROOT/MUOS/Bird/home/.config" \
	"$DATA_ROOT/MUOS/Bird/migrations" \
	"$DATA_ROOT/MUOS/Bird/save/files" \
	"$DATA_ROOT/MUOS/Bird/save/states" \
	"$DATA_ROOT/MUOS/Bird/screenshots" \
	/run/bird/joypads \
	/run/bird/xdg \
	/tmp/cores
chmod 0700 /run/bird/xdg
cp -f /opt/bird/retroarch-append.cfg /run/bird/retroarch-append.cfg
cp -f "$RUNTIME_ROOT/usr/config/retroarch/retroarch-core-options.cfg" \
	/run/bird/retroarch-core-options.cfg
cp -f /opt/bird/h700-gamepad.cfg "/run/bird/joypads/H700 Gamepad.cfg"
cp -f /opt/bird/h700-sdl-gamecontrollerdb.txt \
	/run/bird/h700-sdl-gamecontrollerdb.txt
cp -f /opt/bird/mpv-input.conf /run/bird/mpv-input.conf
cp -f /opt/bird/asound-bird.conf /run/bird/asound-bird.conf

# Installed Ports remain data, but their generic muOS control file is replaced
# only inside the immutable runtime view. The card copy is not modified and no
# PortMaster code enters Bird's launcher or boot gate.
PORT_CONTROL="$RUNTIME_ROOT/storage/MUOS/PortMaster/control.txt"
if [ -f "$PORT_CONTROL" ]; then
	if bind_once /opt/bird/portmaster-control.txt "$PORT_CONTROL"; then
		mark port-policy-ready
	else
		mark port-policy-bind-failed
	fi
else
	mark port-data-absent
fi

# Native libudev clients need one fixed record, not a generic boot dependency.
# Publish it only after Bird is usable and keep this outside the launcher.
/opt/bird/input-metadata.sh || {
	mark native-device-metadata-failed
	exit 1
}
mark native-device-metadata-ready

# Direct ALSA clients need only the fixed H616 codec route. This is a tiny
# deterministic post-menu initializer, not a daemon or launcher dependency.
/opt/bird/audio-init.sh || {
	mark fixed-audio-route-failed
	exit 1
}
mark fixed-audio-route-ready
mark runtime-ready
: >"$READY"
cp -f "$LOG" "$DATA_ROOT/MUOS/Bird/log/post-frame-latest.log"
exit 0
