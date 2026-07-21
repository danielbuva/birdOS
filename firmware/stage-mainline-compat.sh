#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
BUILD=${2:-$ROOT/firmware/work/mainline-compat-boot}
CANDIDATE="$BUILD/dani-boot-mainline-compat.img"
WORK_DIR="$CARD/.firmware-work"
INSTALLER="$CARD/MUOS/init/58-install-mainline-compat.sh"
COLLECTOR="$CARD/MUOS/init/57-capture-mainline-compat.sh"
BASE_SHA=872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f
EXPECTED_SHA=d683c1b9c3f4ed8c67e337a2f1d4527a5f1391b28c8a40c14c5d57660313ea6d
BOOT_BYTES=67108864

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -d "$CARD/MUOS/init" ] || fail "mounted Dani SP card not found: $CARD"
[ -f "$CANDIDATE" ] || fail "candidate missing: $CANDIDATE"
[ "$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')" = "$EXPECTED_SHA" ] || \
	fail 'candidate checksum mismatch'
[ "$(stat -f %z "$CANDIDATE")" -eq "$BOOT_BYTES" ] || \
	fail 'candidate is not exactly 64 MiB'
[ -f "$BUILD/candidate.sha256" ] || fail 'candidate manifest missing'
read -r MANIFEST_SHA _ <"$BUILD/candidate.sha256"
[ "$MANIFEST_SHA" = "$EXPECTED_SHA" ] || fail 'candidate manifest mismatch'
grep -q "^BASE_SHA=$BASE_SHA$" "$ROOT/firmware/device-install-mainline-compat.sh" || \
	fail 'installer base identity mismatch'
grep -q "^CANDIDATE_SHA=$EXPECTED_SHA$" \
	"$ROOT/firmware/device-install-mainline-compat.sh" || fail 'installer candidate identity mismatch'

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE" "$WORK_DIR/.dani-boot-mainline-compat.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-mainline-compat.sh" \
	"$CARD/MUOS/init/.58-install-mainline-compat.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/userspace/57capture-mainline-compat.sh" \
	"$CARD/MUOS/init/.57-capture-mainline-compat.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/mac-restore-mainline-compat.sh" \
	"$WORK_DIR/.mac-restore-mainline-compat.new"

[ "$(shasum -a 256 "$WORK_DIR/.dani-boot-mainline-compat.new" | awk '{print $1}')" = \
	"$EXPECTED_SHA" ] || fail 'staged candidate mismatch'
cmp "$ROOT/firmware/device-install-mainline-compat.sh" \
	"$CARD/MUOS/init/.58-install-mainline-compat.new"
cmp "$ROOT/userspace/57capture-mainline-compat.sh" \
	"$CARD/MUOS/init/.57-capture-mainline-compat.new"
cmp "$ROOT/firmware/mac-restore-mainline-compat.sh" \
	"$WORK_DIR/.mac-restore-mainline-compat.new"

for OLD in "$INSTALLER" "$INSTALLER.done" "$INSTALLER.failed" \
	"$COLLECTOR" "$COLLECTOR.done" "$COLLECTOR.failed"; do
	[ ! -e "$OLD" ] || rm -f "$OLD"
done

mv -f "$WORK_DIR/.dani-boot-mainline-compat.new" \
	"$WORK_DIR/dani-boot-mainline-compat.img"
mv -f "$CARD/MUOS/init/.58-install-mainline-compat.new" "$INSTALLER"
mv -f "$CARD/MUOS/init/.57-capture-mainline-compat.new" "$COLLECTOR"
mv -f "$WORK_DIR/.mac-restore-mainline-compat.new" \
	"$WORK_DIR/mac-restore-mainline-compat.sh"
chmod 755 "$INSTALLER" "$COLLECTOR" "$WORK_DIR/mac-restore-mainline-compat.sh"
find "$WORK_DIR" "$CARD/MUOS/init" -maxdepth 1 -name '._*' -delete
sync

printf 'Staged mainline installer: %s\n' "$INSTALLER"
printf 'Staged mainline first-boot collector: %s\n' "$COLLECTOR"
printf 'External recovery helper: %s\n' "$WORK_DIR/mac-restore-mainline-compat.sh"
printf 'Candidate SHA-256: %s\n' "$EXPECTED_SHA"
printf 'First boot installs after the menu; second cold boot tests mainline.\n'
