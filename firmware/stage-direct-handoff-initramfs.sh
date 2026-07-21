#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
BUILD=${2:-$ROOT/firmware/work/direct-handoff-initramfs}
CANDIDATE="$BUILD/dani-boot-trimmed-initramfs.img"
CHECKSUM="$BUILD/candidate.sha256"
WORK_DIR="$CARD/.firmware-work"
INSTALLER="$CARD/MUOS/init/58-install-direct-handoff-initramfs.sh"
DIAGNOSTICS="$CARD/MUOS/init/99-boot-timing-marker.sh"
OLD_DIAGNOSTICS_SHA="1ef13729542c320011d21ff86e8363cefbb21a624360e08ee6691556c2f5f71d"
BOOT_BYTES=67108864

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -d "$CARD/MUOS/init" ] || fail "mounted Dani SP card not found: $CARD"
[ -f "$CANDIDATE" ] || fail "candidate missing: $CANDIDATE"
[ -f "$CHECKSUM" ] || fail "candidate checksum missing: $CHECKSUM"
read -r EXPECTED_SHA _ <"$CHECKSUM"
[ "$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')" = "$EXPECTED_SHA" ] ||
	fail "candidate checksum mismatch"
[ "$(stat -f %z "$CANDIDATE")" -eq "$BOOT_BYTES" ] ||
	fail "candidate is not exactly 64 MiB"

NEW_DIAGNOSTICS_SHA=$(shasum -a 256 "$ROOT/userspace/99dani-diagnostics.sh" |
	awk '{print $1}')
CURRENT_DIAGNOSTICS_SHA=$(shasum -a 256 "$DIAGNOSTICS" | awk '{print $1}')
case "$CURRENT_DIAGNOSTICS_SHA" in
"$OLD_DIAGNOSTICS_SHA" | "$NEW_DIAGNOSTICS_SHA") ;;
*) fail "refusing unknown diagnostics collector $CURRENT_DIAGNOSTICS_SHA" ;;
esac

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE" \
	"$WORK_DIR/.dani-boot-direct-handoff-initramfs.new"
COPYFILE_DISABLE=1 cp -f "$CHECKSUM" \
	"$WORK_DIR/.dani-boot-direct-handoff-initramfs.sha256.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-direct-handoff-initramfs.sh" \
	"$CARD/MUOS/init/.58-install-direct-handoff-initramfs.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/userspace/99dani-diagnostics.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.direct-new"

[ "$(shasum -a 256 "$WORK_DIR/.dani-boot-direct-handoff-initramfs.new" |
	awk '{print $1}')" = "$EXPECTED_SHA" ] || fail "staged candidate mismatch"
cmp "$ROOT/firmware/device-install-direct-handoff-initramfs.sh" \
	"$CARD/MUOS/init/.58-install-direct-handoff-initramfs.new"
cmp "$ROOT/userspace/99dani-diagnostics.sh" \
	"$CARD/MUOS/init/.99-boot-timing-marker.direct-new"

mv -f "$WORK_DIR/.dani-boot-direct-handoff-initramfs.new" \
	"$WORK_DIR/dani-boot-direct-handoff-initramfs.img"
mv -f "$WORK_DIR/.dani-boot-direct-handoff-initramfs.sha256.new" \
	"$WORK_DIR/dani-boot-direct-handoff-initramfs.sha256"
mv -f "$CARD/MUOS/init/.58-install-direct-handoff-initramfs.new" "$INSTALLER"
mv -f "$CARD/MUOS/init/.99-boot-timing-marker.direct-new" "$DIAGNOSTICS"
chmod 755 "$INSTALLER" "$DIAGNOSTICS"
find "$WORK_DIR" "$CARD/MUOS/init" -maxdepth 1 -name '._*' -delete
sync

printf 'Staged direct-handoff installer: %s\n' "$INSTALLER"
printf 'Candidate SHA-256: %s\n' "$EXPECTED_SHA"
printf 'Installation boot writes it; the following cold boot tests it.\n'
