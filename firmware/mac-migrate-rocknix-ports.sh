#!/bin/sh
# Explicit, resumable same-volume data migration kept outside Bird runtime
# activation. Set BIRD and DATA when Finder uses custom volume labels.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/BIRD-DATA}
LEGACY=$DATA/ports
NATIVE=$DATA/ROMS/Ports
BIRD_HOST_TEST_MODE=${BIRD_HOST_TEST_MODE:-0}
BIRD_DEVICE_INFO=${BIRD_DEVICE_INFO:-}
BIRD_TEST_LOCK_GATE=${BIRD_TEST_LOCK_GATE:-}
BIRD_CARD_LOCK_OWNED=0

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

case "$BIRD_HOST_TEST_MODE" in
	0)
		[ -z "$BIRD_DEVICE_INFO" ] || fail 'device metadata override requires host-test mode'
		[ -z "$BIRD_TEST_LOCK_GATE" ] || fail 'lock gate requires host-test mode'
		;;
	1)
		[ -n "$BIRD_DEVICE_INFO" ] || fail 'host-test device metadata is required'
		case "$BIRD:$DATA:$BIRD_DEVICE_INFO" in
			/var/folders/*:/var/folders/*:/var/folders/*|\
			/private/tmp/*:/private/tmp/*:/private/tmp/*|\
			/tmp/*:/tmp/*:/tmp/*) ;;
			*) fail 'host-test migration paths must be temporary fixtures' ;;
		esac
		if [ -n "$BIRD_TEST_LOCK_GATE" ]; then
			case "$BIRD_TEST_LOCK_GATE" in
				/var/folders/*|/private/tmp/*|/tmp/*) ;;
				*) fail 'host-test lock gate must be a temporary fixture' ;;
			esac
		fi
		;;
	*) fail 'invalid Bird host-test mode' ;;
esac

field() {
	if [ -n "$BIRD_DEVICE_INFO" ]; then
		awk -F '\t' -v device="$1" -v key="$2" \
			'$1 == device && $2 == key {print $3; exit}' "$BIRD_DEVICE_INFO"
		return
	fi
	diskutil info "$1" | awk -F: -v key="$2" \
		'$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {sub(/^[[:space:]]*/, "", $2); print $2; exit}'
}

cleanup() {
	bird_card_lock_release
}

# shellcheck source=mac-bird-card-lock.sh
. "$ROOT/firmware/mac-bird-card-lock.sh"
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ -d "$BIRD" ] || fail "BIRD volume missing: $BIRD"
[ -d "$DATA" ] || fail "data volume missing: $DATA"
WHOLE=$(field "$BIRD" 'Part of Whole')
[ -n "$WHOLE" ] || fail 'cannot identify card parent'
[ "$WHOLE" = "$(field "$DATA" 'Part of Whole')" ] || fail 'volumes are on different disks'
[ "$(field "/dev/$WHOLE" 'Device Location')" = External ] ||
	[ "$(field "/dev/$WHOLE" 'Protocol')" = 'Secure Digital' ] ||
	fail 'refusing disk that is neither external nor a physical SD card'
[ "$(field "/dev/$WHOLE" 'Removable Media')" = Removable ] ||
	fail 'refusing non-removable disk'
[ "$(field "$BIRD" 'Device Identifier')" = "${WHOLE}s1" ] || fail 'BIRD is not p1'
[ "$(field "$DATA" 'Device Identifier')" = "${WHOLE}s6" ] || fail 'data is not p6'
[ "$(field "$BIRD" 'Volume Read-Only')" = No ] || fail 'BIRD is read-only'
[ "$(field "$DATA" 'Volume Read-Only')" = No ] || fail 'data is read-only'

# Both runtime deployment and data migration take this exact inherited host
# lock before mkdir or rename touches the card. Mutator children retain it if
# the parent shell is killed.
bird_card_lock_acquire
if [ -n "$BIRD_TEST_LOCK_GATE" ]; then
	printf '%s\n' "$$" >"$BIRD_TEST_LOCK_GATE/owner-ready"
	LOCK_GATE_WAIT=0
	while [ ! -f "$BIRD_TEST_LOCK_GATE/release-owner" ]; do
		LOCK_GATE_WAIT=$((LOCK_GATE_WAIT + 1))
		[ "$LOCK_GATE_WAIT" -le 400 ] || fail 'host-only lock gate timed out'
		sleep 0.02
	done
fi

[ -d "$LEGACY" ] || {
	printf '%s\n' 'No legacy /ports tree remains.'
	exit 0
}
[ ! -L "$LEGACY" ] || fail 'legacy /ports must not be a symlink'
mkdir -p "$NATIVE"
[ ! -L "$NATIVE" ] || fail 'native Ports destination must not be a symlink'

# A rename is only resumable and atomic inside one filesystem. Validate the
# mounted p6 root and both endpoints, not just their textual path prefixes.
DATA_FS=$(stat -f '%d' "$DATA")
[ "$(stat -f '%d' "$LEGACY")" = "$DATA_FS" ] ||
	fail 'legacy /ports is not on the p6 data filesystem'
[ "$(stat -f '%d' "$NATIVE")" = "$DATA_FS" ] ||
	fail 'native Ports destination is not on the p6 data filesystem'

find "$LEGACY" -mindepth 1 -maxdepth 1 -name '.*' | grep -q . &&
	fail 'hidden legacy Port entry requires manual review'

# Validate the complete remaining set before the first same-volume rename.
for ENTRY in "$LEGACY"/*; do
	[ -e "$ENTRY" ] || break
	[ ! -L "$ENTRY" ] || fail "legacy Port entry is a symlink: $ENTRY"
	[ -d "$ENTRY" ] || fail "legacy Port entry is not a directory: $ENTRY"
	NAME=${ENTRY##*/}
	[ ! -e "$NATIVE/$NAME" ] || fail "native Port collision: $NAME"
done

MOVED=0
for ENTRY in "$LEGACY"/*; do
	[ -e "$ENTRY" ] || break
	mv "$ENTRY" "$NATIVE/"
	sync
	MOVED=$((MOVED + 1))
done
rmdir "$LEGACY" || fail 'legacy Port directory did not become empty'
sync
printf 'Migrated %s Port data directories. Runtime deployment can now proceed.\n' \
	"$MOVED"
