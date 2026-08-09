#!/bin/sh
# Shared, read-only identity contract for the one supported RG34XX-SP card.
# Callers set BIRD, DATA and optionally BIRD_DEVICE_INFO, and provide fail().

BIRD_BYTES=144703488
BIRD_OFFSET=16777216
DISK_BYTES=512074186752
ROOT_BYTES=8589934592
ROOT_OFFSET=163577856
DATA_BYTES=503320672768
DATA_OFFSET=8753512448

field() {
	if [ -n "${BIRD_DEVICE_INFO:-}" ]; then
		awk -F '\t' -v device="$1" -v key="$2" \
			'$1 == device && $2 == key {print $3; exit}' "$BIRD_DEVICE_INFO"
		return
	fi
	diskutil info "$1" | awk -F: -v key="$2" \
		'$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {sub(/^[[:space:]]*/, "", $2); print $2; exit}'
}

disk_bytes() {
	field "$1" 'Disk Size' | sed -n 's/.*(\([0-9][0-9]*\) Bytes).*/\1/p'
}

validate_stock_root_card_identity() {
	[ -d "$BIRD" ] && [ ! -L "$BIRD" ] || \
		fail "BIRD volume missing or unsafe: $BIRD"
	[ -d "$DATA" ] && [ ! -L "$DATA" ] || \
		fail "data volume missing or unsafe: $DATA"

	WHOLE=$(field "$BIRD" 'Part of Whole')
	[ -n "$WHOLE" ] || fail 'cannot identify card parent'
	[ "$WHOLE" = "$(field "$DATA" 'Part of Whole')" ] || \
		fail 'volumes are on different disks'
	[ "$(field "/dev/$WHOLE" 'Device Location')" = External ] || \
		[ "$(field "/dev/$WHOLE" 'Protocol')" = 'Secure Digital' ] || \
		fail 'refusing disk that is neither external nor a physical SD card'
	[ "$(field "/dev/$WHOLE" 'Removable Media')" = Removable ] || \
		fail 'refusing non-removable disk'
	[ "$(disk_bytes "/dev/$WHOLE")" = "$DISK_BYTES" ] || \
		fail 'whole-card size changed'
	[ "$(field "$BIRD" 'Device Identifier')" = "${WHOLE}s1" ] || \
		fail 'BIRD is not p1'
	[ "$(field "$DATA" 'Device Identifier')" = "${WHOLE}s6" ] || \
		fail 'data is not p6'
	[ "$(field "$BIRD" 'Partition Offset' | awk '{print $1}')" = \
		"$BIRD_OFFSET" ] || fail 'p1 offset changed'
	[ "$(disk_bytes "$BIRD")" = "$BIRD_BYTES" ] || fail 'p1 size changed'
	[ "$(field "/dev/${WHOLE}s5" 'Partition Offset' | awk '{print $1}')" = \
		"$ROOT_OFFSET" ] || fail 'p5 offset changed'
	[ "$(disk_bytes "/dev/${WHOLE}s5")" = "$ROOT_BYTES" ] || \
		fail 'p5 size changed'
	[ "$(field "$DATA" 'Partition Offset' | awk '{print $1}')" = \
		"$DATA_OFFSET" ] || fail 'p6 offset changed'
	[ "$(disk_bytes "$DATA")" = "$DATA_BYTES" ] || fail 'p6 size changed'
	[ "$(field "$BIRD" 'Volume Read-Only')" = No ] || fail 'BIRD is read-only'
	[ "$(field "$DATA" 'Volume Read-Only')" = No ] || fail 'data is read-only'
}
