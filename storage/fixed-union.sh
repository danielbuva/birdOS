#!/bin/sh

# Fixed one-card replacement for the two UnionFS-FUSE processes. Preserve the
# compatibility paths while mapping each directly to the only storage source.
ROM_SOURCE="/mnt/mmc/ROMS"
ROM_TARGET="/mnt/union/ROMS"
PORT_SOURCE="/mnt/mmc/ports"
PORT_TARGET="/mnt/union/ports"
STAGES="/tmp/muos/fixed-union.tsv"

mkdir -p /tmp/muos

mark() {
	IFS=' ' read -r NOW _ </proc/uptime
	printf '%s\t%s\n' "$NOW" "$1" >>"$STAGES"
}

is_mounted() {
	grep -q " $1 " /proc/self/mountinfo 2>/dev/null
}

start_one() {
	SOURCE="$1"
	TARGET="$2"

	mkdir -p "$SOURCE" "$TARGET" || return 1
	is_mounted "$TARGET" && return 0
	mount -n --bind "$SOURCE" "$TARGET"
}

stop_one() {
	TARGET="$1"
	is_mounted "$TARGET" || return 0
	umount "$TARGET" 2>/dev/null || umount -l "$TARGET" 2>/dev/null
}

start_fixed() {
	printf 'uptime_s\tevent\n' >"$STAGES"
	mark fixed-union-start

	grep -qs ' /mnt/mmc ' /proc/mounts || {
		mark fixed-union-rom-unavailable
		return 1
	}

	start_one "$ROM_SOURCE" "$ROM_TARGET" || {
		mark fixed-union-rom-bind-failed
		return 1
	}
	mark fixed-union-rom-bound

	start_one "$PORT_SOURCE" "$PORT_TARGET" || {
		stop_one "$ROM_TARGET" || :
		mark fixed-union-port-bind-failed
		return 1
	}
	mark fixed-union-port-bound
	mark fixed-union-complete
}

stop_fixed() {
	mark fixed-union-stop
	stop_one "$PORT_TARGET" || return 1
	stop_one "$ROM_TARGET" || return 1
	mark fixed-union-stopped
}

case "${1-}" in
	start) start_fixed ;;
	stop) stop_fixed ;;
	restart)
		stop_fixed
		start_fixed
		;;
	*)
		printf 'Usage: %s {start|stop|restart}\n' "$0" >&2
		exit 2
		;;
esac

