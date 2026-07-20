#!/bin/sh
set -eu

CARD=${1:-/Volumes/dani-sp}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SNAPSHOT_WORK="$CARD/MUOS/boot-timing/stable-runtime"
STARTUP_WORK="$CARD/MUOS/boot-timing/fixed-startup"
INIT_DIR="$CARD/MUOS/init"

[ -d "$CARD/MUOS" ] || {
	printf 'error: muOS ROM partition not found at %s\n' "$CARD" >&2
	exit 1
}

stage_file() {
	SOURCE=$1
	TARGET=$2
	TEMP="$TARGET.dani-new"
	mkdir -p "${TARGET%/*}"
	rm -f "$TEMP"
	cp "$SOURCE" "$TEMP"
	chmod 755 "$TEMP"
	mv -f "$TEMP" "$TARGET"
}

stage_file "$ROOT/userspace/S98dani-stable-snapshot" \
	"$SNAPSHOT_WORK/S98dani-stable-snapshot"
stage_file "$ROOT/userspace/device-update-stable-snapshot.sh" \
	"$INIT_DIR/67-update-stable-snapshot.sh"
stage_file "$ROOT/userspace/startup-rg34xxsp.sh" \
	"$STARTUP_WORK/startup-rg34xxsp.sh"
stage_file "$ROOT/userspace/device-install-fixed-startup.sh" \
	"$INIT_DIR/68-install-fixed-startup.sh"

# Rearm the capture that the old pre-mount check missed.
: >"$SNAPSHOT_WORK/armed"

rm -f \
	"$SNAPSHOT_WORK"/._S98dani-stable-snapshot \
	"$SNAPSHOT_WORK"/._armed \
	"$STARTUP_WORK"/._startup-rg34xxsp.sh \
	"$INIT_DIR"/._67-update-stable-snapshot.sh \
	"$INIT_DIR"/._68-install-fixed-startup.sh

sync
printf 'staged fixed-init batch on %s\n' "$CARD"
printf '  67: repair/rearm one-shot stable runtime capture\n'
printf '  68: install fixed RG34XX-SP startup orchestrator\n'
