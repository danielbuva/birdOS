#!/bin/sh
# Host-side regression test for the revisioned, fail-closed application marker.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SOURCE=$ROOT/kernel/rocknix/stock-root/999-export
RUNNER=$ROOT/kernel/rocknix/stock-root/run-content.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-application-contract.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

PROFILE_DIR=$TMP/storage/.config/profile.d
SWAY_DIR=$TMP/storage/.config/sway
PLATFORM_STAGE=$TMP/run/bird/fixed-platform
SWAY_STAGE=$TMP/run/bird/fixed-sway
READY_DIR=$TMP/run/bird
SYSTEM_EXPORT=$TMP/etc/profile.d/999-export
UPTIME=$TMP/proc/uptime
READY=$READY_DIR/application-contract-ready
UNDER_TEST=$TMP/999-export
HOST_BIN=$TMP/bin

mkdir -p "$PROFILE_DIR" "$SWAY_DIR" "$PLATFORM_STAGE" "$SWAY_STAGE" \
	"${SYSTEM_EXPORT%/*}" "${UPTIME%/*}" "$READY_DIR" "$HOST_BIN"
printf '%s\n' 'export BIRD_TEST_PROFILE=ready' >"$SYSTEM_EXPORT"
printf '%s\n' '1.25 0.50' >"$UPTIME"

for NAME in 001-device_config 002-turbo-mode_config 010-governors \
	010-led_control 020-fan_control 050-modifiers 091-ui_shader; do
	printf 'profile=%s\n' "$NAME" >"$PLATFORM_STAGE/$NAME"
	cp "$PLATFORM_STAGE/$NAME" "$PROFILE_DIR/$NAME"
done
printf '%s\n' 'sway fixed config' >"$SWAY_STAGE/config"
cp "$SWAY_STAGE/config" "$SWAY_DIR/config"
printf '%s\n' 'sway fixed profile' >"$SWAY_STAGE/095-sway"
cp "$SWAY_STAGE/095-sway" "$PROFILE_DIR/095-sway"
printf '%s\n' 'UI_SERVICE="essway.service"' >"$PROFILE_DIR/090-ui_service"

sed \
	-e "s#^PROFILE_DIR=.*#PROFILE_DIR=$PROFILE_DIR#" \
	-e "s#^SWAY_DIR=.*#SWAY_DIR=$SWAY_DIR#" \
	-e "s#^PLATFORM_STAGE=.*#PLATFORM_STAGE=$PLATFORM_STAGE#" \
	-e "s#^SWAY_STAGE=.*#SWAY_STAGE=$SWAY_STAGE#" \
	-e "s#^SYSTEM_EXPORT=.*#SYSTEM_EXPORT=$SYSTEM_EXPORT#" \
	-e "s#^READY_DIR=.*#READY_DIR=$READY_DIR#" \
	-e 's#^VOLUME_HELPER=.*#VOLUME_HELPER=/usr/bin/true#' \
	-e "s#/proc/uptime#$UPTIME#g" \
	"$SOURCE" >"$UNDER_TEST"
chmod 0755 "$UNDER_TEST"

# Keep invalid-marker checks fast while still allowing wait_application_contract
# to take its normal retry branch. An accepted marker returns before these
# stubs, so the malformed case below still detects a parser fail-open.
printf '%s\n' '#!/bin/sh' 'exit 0' >"$HOST_BIN/systemctl"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$HOST_BIN/usleep"
printf '%s\n' '#!/bin/sh' "printf '1\\n'" >"$HOST_BIN/seq"
chmod 0755 "$HOST_BIN/systemctl" "$HOST_BIN/usleep" "$HOST_BIN/seq"

"$UNDER_TEST"
[ "$(sed -n '1p' "$READY")" = \
	'contract_revision=bird-application-v1' ]

# ROCKNIX's coordinator ignores an earlier script failure. A mismatched fixed
# output must therefore invalidate an already-published marker on the rerun.
printf '%s\n' broken >"$SWAY_DIR/config"
if "$UNDER_TEST"; then
	printf '%s\n' 'false-ready marker accepted a broken Sway contract' >&2
	exit 1
fi
[ ! -e "$READY" ]
cp "$SWAY_STAGE/config" "$SWAY_DIR/config"

printf '%s\n' broken >"$PROFILE_DIR/010-governors"
if "$UNDER_TEST"; then
	printf '%s\n' 'false-ready marker accepted a broken platform contract' >&2
	exit 1
fi
[ ! -e "$READY" ]
cp "$PLATFORM_STAGE/010-governors" "$PROFILE_DIR/010-governors"

"$UNDER_TEST"
[ -s "$READY" ]

# The consumer must reject any bytes beyond the exact two-line contract, even
# when the trailing line reaches EOF without a newline (read assigns data but
# returns failure in that case).
BIRD_TEST_WAIT_APPLICATION_CONTRACT=1 BIRD_APPLICATION_READY="$READY" \
	PATH="$HOST_BIN:$PATH" \
	/bin/bash "$RUNNER"
printf '%s' 'trailing-bytes' >>"$READY"
if BIRD_TEST_WAIT_APPLICATION_CONTRACT=1 BIRD_APPLICATION_READY="$READY" \
	PATH="$HOST_BIN:$PATH" \
	/bin/bash "$RUNNER"; then
	printf '%s\n' 'application consumer accepted trailing marker bytes' >&2
	exit 1
fi

mv "$PROFILE_DIR" "$TMP/profile.saved"
printf '%s\n' blocker >"$PROFILE_DIR"
if "$UNDER_TEST"; then
	printf '%s\n' 'marker survived an application-profile setup failure' >&2
	exit 1
fi
[ ! -e "$READY" ]

sh -n "$SOURCE"
printf '%s\n' 'application-contract tests: PASS'
