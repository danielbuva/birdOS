#!/bin/sh
set -eu

CARD=${1:-/Volumes/BIRD-DATA}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK="$CARD/MUOS/boot-timing/fixed-runtime-services"
SNAPSHOT="$CARD/MUOS/boot-timing/stable-runtime"
DIAGNOSTICS="$CARD/MUOS/boot-timing/minimal-diagnostics"
INIT="$CARD/MUOS/init"
OLD_DIAGNOSTICS_SHA="041ff3643b21c244b5a266267731f67abb914272b34b9056a85abedd4590e0d7"
NEW_DIAGNOSTICS_SHA="836366bafbe21abf6032fa2a2d01a2f88bf4c6ae583bc53b0d739b4847bed5e6"

[ -d "$CARD/MUOS" ] || {
	printf 'error: muOS ROM partition not found at %s\n' "$CARD" >&2
	exit 1
}

stage_file() {
	SOURCE=$1
	TARGET=$2
	TEMP="$TARGET.bird-new"
	mkdir -p "${TARGET%/*}"
	rm -f "$TEMP"
	COPYFILE_DISABLE=1 cp -f "$SOURCE" "$TEMP"
	cmp "$SOURCE" "$TEMP"
	chmod 755 "$TEMP"
	mv -f "$TEMP" "$TARGET"
}

for FILE in \
	device-start-rg34xxsp.sh \
	hotkey-rg34xxsp.sh \
	lid-rg34xxsp.sh \
	lowpower-rg34xxsp.sh \
	charge-rg34xxsp.sh \
	idle-disabled-rg34xxsp.sh \
	module-rg34xxsp.sh \
	user-init-fixed.sh; do
	stage_file "$ROOT/userspace/$FILE" "$WORK/$FILE"
done
stage_file "$ROOT/userspace/device-install-fixed-runtime-services.sh" \
	"$INIT/62-install-fixed-runtime-services.sh"

stage_file "$ROOT/userspace/startup-rg34xxsp.sh" \
	"$CARD/MUOS/boot-timing/fixed-startup/startup-rg34xxsp.sh"
stage_file "$ROOT/userspace/device-update-fixed-startup-v2.sh" \
	"$INIT/60-install-fixed-startup-v2.sh"

stage_file "$ROOT/userspace/S98bird-stable-snapshot" \
	"$SNAPSHOT/S98bird-stable-snapshot"
stage_file "$ROOT/userspace/device-install-runtime-snapshot.sh" \
	"$INIT/61-install-runtime-snapshot.sh"
: >"$SNAPSHOT/armed"

# The old 1,122-line migration engine has completed every active migration.
# Preserve one card-side copy for evidence, then make ordinary user-init run
# only the fixed diagnostics collector.
mkdir -p "$DIAGNOSTICS/backup"
CURRENT_DIAGNOSTICS_SHA=$(shasum -a 256 "$INIT/99-boot-timing-marker.sh" | awk '{print $1}')
case "$CURRENT_DIAGNOSTICS_SHA" in
	"$OLD_DIAGNOSTICS_SHA" | "$NEW_DIAGNOSTICS_SHA") ;;
	*)
		printf 'error: refusing unknown user-init diagnostics %s\n' \
			"$CURRENT_DIAGNOSTICS_SHA" >&2
		exit 1
		;;
esac
if [ ! -f "$DIAGNOSTICS/backup/99-boot-timing-marker.sh.pre-fixed" ]; then
	cp -f "$INIT/99-boot-timing-marker.sh" \
		"$DIAGNOSTICS/backup/99-boot-timing-marker.sh.pre-fixed"
fi
stage_file "$ROOT/userspace/99bird-diagnostics.sh" \
	"$INIT/99-boot-timing-marker.sh"

find "$WORK" "$SNAPSHOT" "$DIAGNOSTICS" "$INIT" \
	-maxdepth 1 -type f -name '._*' -delete
sync

printf 'staged fixed runtime batch on %s\n' "$CARD"
printf '  60: remove redundant fixed-startup probes and persistent writes\n'
printf '  61: one-shot post-change process/service snapshot\n'
printf '  62: eight fixed RG34XX-SP runtime scripts\n'
printf '  99: diagnostics-only collector (migration engine retired)\n'
