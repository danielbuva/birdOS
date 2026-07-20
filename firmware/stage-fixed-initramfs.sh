#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
BUILD=${2:-$ROOT/firmware/work/fixed-initramfs}
CANDIDATE="$BUILD/dani-boot-fixed-initramfs.img"
CHECKSUM="$BUILD/candidate.sha256"
WORK_DIR="$CARD/.firmware-work"
LAUNCHER_DIR="$CARD/MUOS/bespoke-launcher"
INSTALLER="$CARD/MUOS/init/93-install-fixed-initramfs.sh"

[ -d "$CARD/MUOS/init" ] || {
	printf 'error: mounted Dani SP card not found: %s\n' "$CARD" >&2
	exit 1
}
[ -f "$CANDIDATE" ] && [ -f "$CHECKSUM" ] || {
	printf 'error: build the fixed-initramfs candidate first: %s\n' "$BUILD" >&2
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
sh -n "$ROOT/launcher/S03danilauncher"

mkdir -p "$WORK_DIR" "$LAUNCHER_DIR"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE" "$WORK_DIR/.dani-boot-fixed-initramfs.new"
COPYFILE_DISABLE=1 cp -f "$CHECKSUM" "$WORK_DIR/.dani-boot-fixed-initramfs.sha256.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-fixed-initramfs.sh" \
	"$CARD/MUOS/init/.93-install-fixed-initramfs.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/launcher/S03danilauncher" \
	"$LAUNCHER_DIR/.S03danilauncher.fixed-init-new"
COPYFILE_DISABLE=1 cp -f "$ROOT/launcher/dani-launcher.o" \
	"$LAUNCHER_DIR/.dani-launcher.fixed-init-new"
COPYFILE_DISABLE=1 cp -f "$ROOT/launcher/catalog.revision" \
	"$LAUNCHER_DIR/.catalog.fixed-init-new"

[ "$(shasum -a 256 "$WORK_DIR/.dani-boot-fixed-initramfs.new" | awk '{print $1}')" = \
	"$EXPECTED_SHA" ] || {
	printf 'error: staged candidate verification failed\n' >&2
	exit 1
}
cmp "$ROOT/launcher/S03danilauncher" \
	"$LAUNCHER_DIR/.S03danilauncher.fixed-init-new"
cmp "$ROOT/launcher/dani-launcher.o" \
	"$LAUNCHER_DIR/.dani-launcher.fixed-init-new"
cmp "$ROOT/launcher/catalog.revision" \
	"$LAUNCHER_DIR/.catalog.fixed-init-new"

mv -f "$WORK_DIR/.dani-boot-fixed-initramfs.new" \
	"$WORK_DIR/dani-boot-fixed-initramfs.img"
mv -f "$WORK_DIR/.dani-boot-fixed-initramfs.sha256.new" \
	"$WORK_DIR/dani-boot-fixed-initramfs.sha256"
mv -f "$LAUNCHER_DIR/.S03danilauncher.fixed-init-new" \
	"$LAUNCHER_DIR/S03danilauncher"
mv -f "$LAUNCHER_DIR/.dani-launcher.fixed-init-new" \
	"$LAUNCHER_DIR/dani-launcher.o"
mv -f "$LAUNCHER_DIR/.catalog.fixed-init-new" \
	"$LAUNCHER_DIR/catalog.revision"
mv -f "$CARD/MUOS/init/.93-install-fixed-initramfs.new" "$INSTALLER"
chmod 755 "$INSTALLER" "$LAUNCHER_DIR/S03danilauncher"
sync

printf 'Staged fixed-initramfs installer: %s\n' "$INSTALLER"
printf 'Candidate SHA-256: %s\n' "$EXPECTED_SHA"
printf 'Boot once and leave it on for 30 seconds to install; the following cold boot tests it.\n'
