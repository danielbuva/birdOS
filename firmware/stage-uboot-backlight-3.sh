#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
BUILD=${2:-$ROOT/firmware/work/bootloader-backlight-3}
CANDIDATE="$BUILD/toc1-backlight-3.bin"
CHECKSUM="$BUILD/candidate.sha256"
WORK_DIR="$CARD/.firmware-work/bootloader"
INSTALLER="$CARD/MUOS/init/92-install-uboot-backlight-3.sh"

[ -d "$CARD/MUOS/init" ] || {
	printf 'error: mounted Dani SP card not found: %s\n' "$CARD" >&2
	exit 1
}
[ -f "$CANDIDATE" ] && [ -f "$CHECKSUM" ] || {
	printf 'error: build the U-Boot raw-3 candidate first: %s\n' "$BUILD" >&2
	exit 1
}

read -r EXPECTED_SHA _ <"$CHECKSUM"
[ "$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')" = "$EXPECTED_SHA" ] || {
	printf 'error: candidate checksum mismatch\n' >&2
	exit 1
}
[ "$(stat -f %z "$CANDIDATE")" -eq 1310720 ] || {
	printf 'error: candidate is not exactly 1.25 MiB\n' >&2
	exit 1
}

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE" "$WORK_DIR/.toc1-backlight-3.new"
COPYFILE_DISABLE=1 cp -f "$CHECKSUM" "$WORK_DIR/.toc1-backlight-3.sha256.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-uboot-backlight-3.sh" \
	"$CARD/MUOS/init/.92-install-uboot-backlight-3.new"

[ "$(shasum -a 256 "$WORK_DIR/.toc1-backlight-3.new" | awk '{print $1}')" = \
	"$EXPECTED_SHA" ] || {
	printf 'error: staged TOC1 candidate verification failed\n' >&2
	exit 1
}

mv -f "$WORK_DIR/.toc1-backlight-3.new" "$WORK_DIR/toc1-backlight-3.bin"
mv -f "$WORK_DIR/.toc1-backlight-3.sha256.new" "$WORK_DIR/toc1-backlight-3.sha256"
mv -f "$CARD/MUOS/init/.92-install-uboot-backlight-3.new" "$INSTALLER"
chmod 755 "$INSTALLER"
sync

printf 'Staged U-Boot raw-3 installer: %s\n' "$INSTALLER"
printf 'Candidate SHA-256: %s\n' "$EXPECTED_SHA"
printf 'Boot once for 30 seconds to install; the next cold boot tests 1.18%% startup brightness.\n'
