#!/bin/sh

# Fixed one-card storage orchestration. ROM mounting is already dispatched by
# S05earlyrom; this call joins it if needed, then exposes compatibility paths.
STAGES="/tmp/muos/fixed-storage-start.tsv"

mkdir -p /tmp/muos
printf 'uptime_s\tevent\n' >"$STAGES"

mark() {
	IFS=' ' read -r NOW _ </proc/uptime
	printf '%s\t%s\n' "$NOW" "$1" >>"$STAGES"
}

mark fixed-storage-start
/opt/muos/script/mount/storage.sh rom mount 1 || {
	mark fixed-storage-rom-failed
	exit 1
}
mark fixed-storage-rom-ready

/opt/muos/script/mount/union.sh start || {
	mark fixed-storage-union-failed
	exit 1
}
mark fixed-storage-compatibility-ready

/opt/muos/script/mount/bind.sh &
mark fixed-storage-bind-dispatched

