#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
BUILD=${2:-$ROOT/firmware/work/trimmed-initramfs}
CANDIDATE="$BUILD/bird-boot-trimmed-initramfs.img"
CHECKSUM="$BUILD/candidate.sha256"
WORK_DIR="$CARD/.firmware-work"
INSTALLER="$CARD/MUOS/init/59-install-trimmed-initramfs.sh"
DIAGNOSTICS="$CARD/MUOS/init/99-boot-timing-marker.sh"
OLD_DIAGNOSTICS_SHA="2832c118227d5b26e15bfc0c01fcf3a08ae8fc99423cf16572aa9e680f225803"
BOOT_BYTES=67108864

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -d "$CARD/MUOS/init" ] || fail "mounted birdOS card not found: $CARD"
[ -f "$CANDIDATE" ] || fail "candidate missing: $CANDIDATE"
[ -f "$CHECKSUM" ] || fail "candidate checksum missing: $CHECKSUM"

read -r EXPECTED_SHA _ <"$CHECKSUM"
[ "$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')" = "$EXPECTED_SHA" ] ||
	fail "candidate checksum mismatch"
[ "$(stat -f %z "$CANDIDATE")" -eq "$BOOT_BYTES" ] ||
	fail "candidate is not exactly 64 MiB"

NEW_DIAGNOSTICS_SHA=$(shasum -a 256 "$ROOT/userspace/99bird-diagnostics.sh" |
	awk '{print $1}')
CURRENT_DIAGNOSTICS_SHA=$(shasum -a 256 "$DIAGNOSTICS" | awk '{print $1}')
case "$CURRENT_DIAGNOSTICS_SHA" in
"$OLD_DIAGNOSTICS_SHA" | "$NEW_DIAGNOSTICS_SHA") ;;
*) fail "refusing unknown diagnostics collector $CURRENT_DIAGNOSTICS_SHA" ;;
esac

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE" \
	"$WORK_DIR/.bird-boot-trimmed-initramfs.new"
COPYFILE_DISABLE=1 cp -f "$CHECKSUM" \
	"$WORK_DIR/.bird-boot-trimmed-initramfs.sha256.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-trimmed-initramfs.sh" \
	"$CARD/MUOS/init/.59-install-trimmed-initramfs.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/userspace/99bird-diagnostics.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.trimmed-new"

[ "$(shasum -a 256 "$WORK_DIR/.bird-boot-trimmed-initramfs.new" |
	awk '{print $1}')" = "$EXPECTED_SHA" ] || fail "staged candidate mismatch"
cmp "$ROOT/firmware/device-install-trimmed-initramfs.sh" \
	"$CARD/MUOS/init/.59-install-trimmed-initramfs.new"
cmp "$ROOT/userspace/99bird-diagnostics.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.trimmed-new"

mv -f "$WORK_DIR/.bird-boot-trimmed-initramfs.new" \
	"$WORK_DIR/bird-boot-trimmed-initramfs.img"
mv -f "$WORK_DIR/.bird-boot-trimmed-initramfs.sha256.new" \
	"$WORK_DIR/bird-boot-trimmed-initramfs.sha256"
mv -f "$CARD/MUOS/init/.59-install-trimmed-initramfs.new" "$INSTALLER"
mv -f "$CARD/MUOS/init/.99-boot-timing-marker.trimmed-new" "$DIAGNOSTICS"
chmod 755 "$INSTALLER" "$DIAGNOSTICS"
find "$WORK_DIR" "$CARD/MUOS/init" -maxdepth 1 -name '._*' -delete
sync

printf 'Staged trimmed-initramfs installer: %s\n' "$INSTALLER"
printf 'Candidate SHA-256: %s\n' "$EXPECTED_SHA"
printf 'The installation boot keeps the current image; the next cold boot tests it.\n'
