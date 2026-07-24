#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
BUILD=${2:-$ROOT/firmware/work/static-pid1}
CANDIDATE="$BUILD/bird-boot-static-pid1.img"
CHECKSUM="$BUILD/candidate.sha256"
WORK_DIR="$CARD/.firmware-work"
INSTALLER="$CARD/MUOS/init/91-install-static-pid1.sh"
TIMING_MARKER="$CARD/MUOS/init/99-boot-timing-marker.sh"

[ -d "$CARD/MUOS/init" ] || {
	printf 'error: mounted birdOS card not found: %s\n' "$CARD" >&2
	exit 1
}
[ -f "$CANDIDATE" ] && [ -f "$CHECKSUM" ] || {
	printf 'error: build the static PID 1 candidate first: %s\n' "$BUILD" >&2
	exit 1
}

read -r EXPECTED_SHA _ <"$CHECKSUM"
ACTUAL_SHA=$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || {
	printf 'error: candidate checksum mismatch\n' >&2
	exit 1
}
[ "$(stat -f %z "$CANDIDATE")" -eq 67108864 ] || {
	printf 'error: candidate is not exactly 64 MiB\n' >&2
	exit 1
}
sh -n "$ROOT/firmware/device-install-static-pid1.sh"
sh -n "$ROOT/99-frontend-native-log.sh"

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE" "$WORK_DIR/.bird-boot-static-pid1.new"
COPYFILE_DISABLE=1 cp -f "$CHECKSUM" "$WORK_DIR/.bird-boot-static-pid1.sha256.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-static-pid1.sh" \
	"$CARD/MUOS/init/.91-install-static-pid1.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.static-pid1-new"

[ "$(shasum -a 256 "$WORK_DIR/.bird-boot-static-pid1.new" | awk '{print $1}')" = \
	"$EXPECTED_SHA" ] || {
	printf 'error: staged candidate verification failed\n' >&2
	exit 1
}
cmp "$ROOT/firmware/device-install-static-pid1.sh" \
	"$CARD/MUOS/init/.91-install-static-pid1.new"
cmp "$ROOT/99-frontend-native-log.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.static-pid1-new"

mv -f "$WORK_DIR/.bird-boot-static-pid1.new" \
	"$WORK_DIR/bird-boot-static-pid1.img"
mv -f "$WORK_DIR/.bird-boot-static-pid1.sha256.new" \
	"$WORK_DIR/bird-boot-static-pid1.sha256"
mv -f "$CARD/MUOS/init/.91-install-static-pid1.new" "$INSTALLER"
mv -f "$CARD/MUOS/init/.99-boot-timing-marker.static-pid1-new" "$TIMING_MARKER"
chmod 755 "$INSTALLER" "$TIMING_MARKER"
sync

printf 'Staged static-root-PID1 installer: %s\n' "$INSTALLER"
printf 'Candidate SHA-256: %s\n' "$EXPECTED_SHA"
printf 'Boot once and leave it on for 30 seconds to install; the following cold boot tests it.\n'
