#!/bin/bash
# Host coverage for the accepted fixed-profile comparison and repair paths.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SOURCE=$ROOT/kernel/rocknix/stock-root/bird-fixed-platform.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-platform.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

PROFILE=$TMP/profile.d
STAGE=$TMP/run/bird/fixed-platform
LOG=$TMP/Bird/log/fixed-platform-latest.log
UPTIME=$TMP/proc/uptime
UNDER_TEST=$TMP/bird-fixed-platform.sh
BIN=$TMP/bin
COMMANDS=$TMP/commands
mkdir -p "$PROFILE" "$STAGE" "${LOG%/*}" "${UPTIME%/*}" "$BIN"
printf '%s\n' '12.340000 1.000000' >"$UPTIME"

sed \
	-e "s#^PROFILE=.*#PROFILE=$PROFILE#" \
	-e "s#^STAGE=.*#STAGE=$STAGE#" \
	-e "s#^LOG=.*#LOG=$LOG#" \
	-e "s#/proc/uptime#$UPTIME#g" \
	"$SOURCE" >"$UNDER_TEST"
chmod 0755 "$UNDER_TEST"

# First publication repairs every absent persistent profile while producing the
# complete volatile authority consumed by 999-export.
"$UNDER_TEST"
for NAME in 001-device_config 002-turbo-mode_config 010-governors \
	010-led_control 020-fan_control 050-modifiers 091-ui_shader; do
	cmp "$STAGE/$NAME" "$PROFILE/$NAME"
done
grep -Fq 'Bird fixed platform start uptime=12.340000' "$LOG"
grep -Fq 'Bird fixed platform ready uptime=12.340000' "$LOG"
[ "$(grep -c '=updated$' "$LOG")" -eq 7 ]

cat >"$BIN/cmp" <<'EOF'
#!/bin/sh
printf '%s\n' cmp >>"$BIRD_PLATFORM_COMMANDS"
exit 97
EOF
cat >"$BIN/cut" <<'EOF'
#!/bin/sh
printf '%s\n' cut >>"$BIRD_PLATFORM_COMMANDS"
exit 98
EOF
cat >"$BIN/cp" <<'EOF'
#!/bin/sh
printf 'cp' >>"$BIRD_PLATFORM_COMMANDS"
printf '|%s' "$@" >>"$BIRD_PLATFORM_COMMANDS"
printf '\n' >>"$BIRD_PLATFORM_COMMANDS"
exec /bin/cp "$@"
EOF
chmod 0755 "$BIN/cmp" "$BIN/cut" "$BIN/cp"
export BIRD_PLATFORM_COMMANDS=$COMMANDS

# The ordinary accepted state uses shell reads: no cmp, cut, or repair copy.
: >"$COMMANDS"
PATH="$BIN:/usr/bin:/bin" "$UNDER_TEST"
[ ! -s "$COMMANDS" ]
[ "$(grep -c '=unchanged$' "$LOG")" -eq 7 ]
for NAME in 001-device_config 002-turbo-mode_config 010-governors \
	010-led_control 020-fan_control 050-modifiers 091-ui_shader; do
	cmp "$STAGE/$NAME" "$PROFILE/$NAME"
done

# One mismatched file causes exactly one existing repair copy.
printf '%s\n' broken >"$PROFILE/010-governors"
: >"$COMMANDS"
PATH="$BIN:/usr/bin:/bin" "$UNDER_TEST"
printf 'cp|-f|%s|%s\n' "$STAGE/010-governors" \
	"$PROFILE/010-governors" >"$TMP/expected"
cmp "$TMP/expected" "$COMMANDS"
cmp "$STAGE/010-governors" "$PROFILE/010-governors"
grep -Fq '010-governors=updated' "$LOG"

# Trailing data is not accepted as an exact fixed profile.
printf '%s\n' trailing >>"$PROFILE/020-fan_control"
: >"$COMMANDS"
PATH="$BIN:/usr/bin:/bin" "$UNDER_TEST"
printf 'cp|-f|%s|%s\n' "$STAGE/020-fan_control" \
	"$PROFILE/020-fan_control" >"$TMP/expected"
cmp "$TMP/expected" "$COMMANDS"
cmp "$STAGE/020-fan_control" "$PROFILE/020-fan_control"

if grep -Eq '^[[:space:]]*(cmp|cut)[[:space:]]' "$SOURCE"; then
	printf '%s\n' 'fixed platform regained accepted-path cmp/cut children' >&2
	exit 1
fi
sh -n "$SOURCE" "$UNDER_TEST"
printf '%s\n' 'stock-root fixed-platform tests: PASS'
