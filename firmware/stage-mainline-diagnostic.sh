#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/dani-sp}
BUILD=${2:-$ROOT/firmware/work/mainline-diagnostic-boot}
CANDIDATE="$BUILD/dani-boot-mainline-diagnostic.img"
WORK_DIR="$CARD/.firmware-work"
INSTALLER="$CARD/MUOS/init/58-install-mainline-diagnostic.sh"
COLLECTOR="$CARD/MUOS/init/57-capture-mainline-diagnostic.sh"
EXPECTED_SHA=8b9ba42467b9879b94a7f61241fc5065c31206b71da1f29c21c6c13e993f9078
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
read -r MANIFEST_SHA _ <"$BUILD/candidate.sha256"
[ "$MANIFEST_SHA" = "$EXPECTED_SHA" ] || fail 'candidate manifest mismatch'
grep -q "^CANDIDATE_SHA=$EXPECTED_SHA$" \
	"$ROOT/firmware/device-install-mainline-diagnostic.sh" || \
	fail 'installer candidate identity mismatch'
grep -q "^EXPECTED_SHA=$EXPECTED_SHA$" \
	"$ROOT/userspace/57capture-mainline-diagnostic.sh" || \
	fail 'collector candidate identity mismatch'
grep -q "^CANDIDATE_SHA=$EXPECTED_SHA$" \
	"$ROOT/firmware/mac-restore-mainline-diagnostic.sh" || \
	fail 'recovery candidate identity mismatch'

mkdir -p "$WORK_DIR"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE" \
	"$WORK_DIR/.dani-boot-mainline-diagnostic.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-mainline-diagnostic.sh" \
	"$CARD/MUOS/init/.58-install-mainline-diagnostic.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/userspace/57capture-mainline-diagnostic.sh" \
	"$CARD/MUOS/init/.57-capture-mainline-diagnostic.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/mac-restore-mainline-diagnostic.sh" \
	"$WORK_DIR/.mac-restore-mainline-diagnostic.new"

[ "$(shasum -a 256 "$WORK_DIR/.dani-boot-mainline-diagnostic.new" | awk '{print $1}')" = \
	"$EXPECTED_SHA" ] || fail 'staged candidate mismatch'
cmp "$ROOT/firmware/device-install-mainline-diagnostic.sh" \
	"$CARD/MUOS/init/.58-install-mainline-diagnostic.new"
cmp "$ROOT/userspace/57capture-mainline-diagnostic.sh" \
	"$CARD/MUOS/init/.57-capture-mainline-diagnostic.new"
cmp "$ROOT/firmware/mac-restore-mainline-diagnostic.sh" \
	"$WORK_DIR/.mac-restore-mainline-diagnostic.new"

for OLD in \
	"$CARD/MUOS/init/58-install-mainline-diagnostic.sh" \
	"$CARD/MUOS/init/58-install-mainline-diagnostic.sh.done" \
	"$CARD/MUOS/init/58-install-mainline-diagnostic.sh.failed" \
	"$CARD/MUOS/init/57-capture-mainline-diagnostic.sh" \
	"$CARD/MUOS/init/57-capture-mainline-diagnostic.sh.done" \
	"$CARD/MUOS/init/57-capture-mainline-diagnostic.sh.failed"; do
	[ ! -e "$OLD" ] || rm -f "$OLD"
done

mv -f "$WORK_DIR/.dani-boot-mainline-diagnostic.new" \
	"$WORK_DIR/dani-boot-mainline-diagnostic.img"
mv -f "$CARD/MUOS/init/.58-install-mainline-diagnostic.new" "$INSTALLER"
mv -f "$CARD/MUOS/init/.57-capture-mainline-diagnostic.new" "$COLLECTOR"
mv -f "$WORK_DIR/.mac-restore-mainline-diagnostic.new" \
	"$WORK_DIR/mac-restore-mainline-diagnostic.sh"
chmod 755 "$INSTALLER" "$COLLECTOR" \
	"$WORK_DIR/mac-restore-mainline-diagnostic.sh"
find "$WORK_DIR" "$CARD/MUOS/init" -maxdepth 1 -name '._*' -delete
sync

printf 'Staged mainline diagnostic installer: %s\n' "$INSTALLER"
printf 'Candidate SHA-256: %s\n' "$EXPECTED_SHA"
printf 'First boot installs; second boot reports progress on the red LED.\n'
