#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
BUILD=${2:-$ROOT/firmware/work/initramfs-launcher}
CANDIDATE="$BUILD/bird-boot-initramfs-launcher.img"
CHECKSUM="$BUILD/candidate.sha256"
WORK_DIR="$CARD/.firmware-work"
INSTALLER="$CARD/MUOS/init/94-install-initramfs-launcher.sh"

[ -d "$CARD/MUOS/init" ] || {
	printf 'error: mounted birdOS card not found: %s\n' "$CARD" >&2
	exit 1
}
[ -f "$CANDIDATE" ] && [ -f "$CHECKSUM" ] || {
	printf 'error: build the initramfs candidate first: %s\n' "$BUILD" >&2
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

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE" "$WORK_DIR/.bird-boot-initramfs-launcher.new"
COPYFILE_DISABLE=1 cp -f "$CHECKSUM" "$WORK_DIR/.bird-boot-initramfs-launcher.sha256.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-initramfs-launcher.sh" \
	"$CARD/MUOS/init/.94-install-initramfs-launcher.new"

[ "$(shasum -a 256 "$WORK_DIR/.bird-boot-initramfs-launcher.new" | awk '{print $1}')" = \
	"$EXPECTED_SHA" ] || {
	printf 'error: staged candidate verification failed\n' >&2
	exit 1
}

mv -f "$WORK_DIR/.bird-boot-initramfs-launcher.new" \
	"$WORK_DIR/bird-boot-initramfs-launcher.img"
mv -f "$WORK_DIR/.bird-boot-initramfs-launcher.sha256.new" \
	"$WORK_DIR/bird-boot-initramfs-launcher.sha256"
mv -f "$CARD/MUOS/init/.94-install-initramfs-launcher.new" "$INSTALLER"
chmod 755 "$INSTALLER"
sync

printf 'Staged initramfs-launcher installer: %s\n' "$INSTALLER"
printf 'Candidate SHA-256: %s\n' "$EXPECTED_SHA"
printf 'Boot once to install; the following cold boot tests the candidate.\n'
