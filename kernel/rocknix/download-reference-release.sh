#!/bin/sh
# Fetch the official, known-working RG34XX-SP DDR4 release with independent
# HTTP ranges.  Every byte is accepted only after the release SHA-256 matches.

set -eu

URL=https://github.com/ROCKNIX/distribution/releases/download/20260701/ROCKNIX-H700.aarch64-20260701-DDR4.img.gz
OUTPUT=${1:-/Users/dani/Downloads/ROCKNIX-H700.aarch64-20260701-DDR4.img.gz}
TOTAL=1221786248
EXPECTED_SHA=5b26c704ddab59e61eb7ead115879ad5370c20973be7118b823e32726bed24dc
PARTS=${TMPDIR:-/tmp}/dani-rocknix-release-parts
GDD=${GDD:-/opt/homebrew/bin/gdd}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
command -v curl >/dev/null 2>&1 || fail 'curl is required'
mkdir -p "$PARTS"

if [ -f "$OUTPUT" ]; then
	START=$(stat -f %z "$OUTPUT")
else
	START=0
	: >"$OUTPUT"
fi
[ "$START" -le "$TOTAL" ] || fail "oversized partial download: $START"

if [ "$START" -lt "$TOTAL" ]; then
	REMAINING=$((TOTAL - START))
	CHUNK=$(((REMAINING + 7) / 8))
	PIDS=
	RANGES=
	INDEX=0
	POS=$START
	while [ "$POS" -lt "$TOTAL" ]; do
		END=$((POS + CHUNK - 1))
		[ "$END" -lt "$TOTAL" ] || END=$((TOTAL - 1))
		PART="$PARTS/$POS-$END.part"
		curl --fail --location --retry 10 --retry-delay 2 \
			--retry-all-errors --range "$POS-$END" --output "$PART" \
			"$URL" --silent --show-error &
		PIDS="$PIDS $!"
		RANGES="$RANGES $POS:$END:$PART"
		INDEX=$((INDEX + 1))
		POS=$((END + 1))
	done
	printf 'Downloading %s remaining bytes in %s ranges...\n' \
		"$REMAINING" "$INDEX"
	for PID in $PIDS; do
		wait "$PID"
	done

	for SPEC in $RANGES; do
		POS=${SPEC%%:*}
		REST=${SPEC#*:}
		END=${REST%%:*}
		PART=${REST#*:}
		EXPECTED=$((END - POS + 1))
		ACTUAL=$(stat -f %z "$PART")
		[ "$ACTUAL" -eq "$EXPECTED" ] || \
			fail "short range $PART: expected $EXPECTED, got $ACTUAL"
		"$GDD" if="$PART" of="$OUTPUT" bs=4M seek="$POS" \
			oflag=seek_bytes conv=notrunc status=none
	done
fi

[ "$(stat -f %z "$OUTPUT")" -eq "$TOTAL" ] || fail 'release size mismatch'
SHA=$(shasum -a 256 "$OUTPUT" | awk '{print $1}')
[ "$SHA" = "$EXPECTED_SHA" ] || fail "release checksum mismatch: $SHA"
find "$PARTS" -type f -name '*.part' -delete
printf 'Official ROCKNIX release downloaded and verified:\n  %s\n' "$OUTPUT"
