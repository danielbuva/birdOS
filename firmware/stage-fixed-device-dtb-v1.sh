#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
BUILD=${2:-$ROOT/firmware/work/fixed-device-dtb-v1}
CANDIDATE="$BUILD/bird-boot-fixed-device-dtb-v1.img"
CHECKSUM="$BUILD/candidate.sha256"
WORK_DIR="$CARD/.firmware-work"
INSTALLER="$CARD/MUOS/init/58-install-fixed-device-dtb-v1.sh"
COLLECTOR="$CARD/MUOS/init/57-capture-fixed-device-dtb-v1.sh"
BOOT_BYTES=67108864

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -d "$CARD/MUOS/init" ] || fail "mounted birdOS card not found: $CARD"
[ -f "$CANDIDATE" ] || fail "candidate missing: $CANDIDATE"
[ -f "$CHECKSUM" ] || fail "candidate checksum missing: $CHECKSUM"
read -r EXPECTED_SHA _ <"$CHECKSUM"
[ "$EXPECTED_SHA" = \
	"872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f" ] || \
	fail "unexpected fixed-device candidate checksum"
[ "$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')" = "$EXPECTED_SHA" ] || \
	fail "candidate checksum mismatch"
[ "$(stat -f %z "$CANDIDATE")" -eq "$BOOT_BYTES" ] || \
	fail "candidate is not exactly 64 MiB"

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE" \
	"$WORK_DIR/.bird-boot-fixed-device-dtb-v1.new"
COPYFILE_DISABLE=1 cp -f "$CHECKSUM" \
	"$WORK_DIR/.bird-boot-fixed-device-dtb-v1.sha256.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-fixed-device-dtb-v1.sh" \
	"$CARD/MUOS/init/.58-install-fixed-device-dtb-v1.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/userspace/57capture-fixed-device-dtb-v1.sh" \
	"$CARD/MUOS/init/.57-capture-fixed-device-dtb-v1.new"

[ "$(shasum -a 256 "$WORK_DIR/.bird-boot-fixed-device-dtb-v1.new" |
	awk '{print $1}')" = "$EXPECTED_SHA" ] || fail "staged candidate mismatch"
cmp "$ROOT/firmware/device-install-fixed-device-dtb-v1.sh" \
	"$CARD/MUOS/init/.58-install-fixed-device-dtb-v1.new"
cmp "$ROOT/userspace/57capture-fixed-device-dtb-v1.sh" \
	"$CARD/MUOS/init/.57-capture-fixed-device-dtb-v1.new"

for OLD in "$INSTALLER" "$INSTALLER.done" "$INSTALLER.failed" \
	"$COLLECTOR" "$COLLECTOR.done" "$COLLECTOR.failed"; do
	[ ! -e "$OLD" ] || rm -f "$OLD"
done

mv -f "$WORK_DIR/.bird-boot-fixed-device-dtb-v1.new" \
	"$WORK_DIR/bird-boot-fixed-device-dtb-v1.img"
mv -f "$WORK_DIR/.bird-boot-fixed-device-dtb-v1.sha256.new" \
	"$WORK_DIR/bird-boot-fixed-device-dtb-v1.sha256"
mv -f "$CARD/MUOS/init/.58-install-fixed-device-dtb-v1.new" "$INSTALLER"
mv -f "$CARD/MUOS/init/.57-capture-fixed-device-dtb-v1.new" "$COLLECTOR"
chmod 755 "$INSTALLER" "$COLLECTOR"
find "$WORK_DIR" "$CARD/MUOS/init" -maxdepth 1 -name '._*' -delete
sync

printf 'Staged fixed-device DTB v1 installer: %s\n' "$INSTALLER"
printf 'Staged first-candidate-boot collector: %s\n' "$COLLECTOR"
printf 'Candidate SHA-256: %s\n' "$EXPECTED_SHA"
printf 'First boot installs after the menu; second cold boot tests the DTB.\n'
