#!/bin/bash
# Host coverage for the accepted fixed-Sway comparison and repair paths.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SOURCE=$ROOT/kernel/rocknix/stock-root/bird-fixed-sway.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-sway.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

SWAY_DIR=$TMP/sway
PROFILE_DIR=$TMP/profile.d
RUN_DIR=$TMP/run/bird/fixed-sway
LOG=$TMP/Bird/log/fixed-sway-latest.log
UPTIME=$TMP/proc/uptime
UNDER_TEST=$TMP/bird-fixed-sway.sh
BIN=$TMP/bin
COMMANDS=$TMP/commands
mkdir -p "$SWAY_DIR" "$PROFILE_DIR" "$RUN_DIR" "${LOG%/*}" \
	"${UPTIME%/*}" "$BIN"
printf '%s\n' '12.340000 1.000000' >"$UPTIME"

sed \
	-e "s#^SWAY_DIR=.*#SWAY_DIR=$SWAY_DIR#" \
	-e "s#^PROFILE_DIR=.*#PROFILE_DIR=$PROFILE_DIR#" \
	-e "s#^RUN_DIR=.*#RUN_DIR=$RUN_DIR#" \
	-e "s#^CONFIG=.*#CONFIG=$SWAY_DIR/config#" \
	-e "s#^PROFILE=.*#PROFILE=$PROFILE_DIR/095-sway#" \
	-e "s#^LOG=.*#LOG=$LOG#" \
	-e "s#/proc/uptime#$UPTIME#g" \
	"$SOURCE" >"$UNDER_TEST"
chmod 0755 "$UNDER_TEST"

# First publication repairs both absent persistent outputs.
"$UNDER_TEST"
cmp "$RUN_DIR/config" "$SWAY_DIR/config"
cmp "$RUN_DIR/095-sway" "$PROFILE_DIR/095-sway"
[ "$(grep -c '=updated$' "$LOG")" -eq 2 ]

cat >"$BIN/cmp" <<'EOF'
#!/bin/sh
printf '%s\n' cmp >>"$BIRD_SWAY_COMMANDS"
exit 97
EOF
cat >"$BIN/cut" <<'EOF'
#!/bin/sh
printf '%s\n' cut >>"$BIRD_SWAY_COMMANDS"
exit 98
EOF
cat >"$BIN/cp" <<'EOF'
#!/bin/sh
printf 'cp' >>"$BIRD_SWAY_COMMANDS"
printf '|%s' "$@" >>"$BIRD_SWAY_COMMANDS"
printf '\n' >>"$BIRD_SWAY_COMMANDS"
exec /bin/cp "$@"
EOF
chmod 0755 "$BIN/cmp" "$BIN/cut" "$BIN/cp"
export BIRD_SWAY_COMMANDS=$COMMANDS

# The ordinary accepted state performs no comparison or repair child process.
: >"$COMMANDS"
PATH="$BIN:/usr/bin:/bin" "$UNDER_TEST"
[ ! -s "$COMMANDS" ]
[ "$(grep -c '=unchanged$' "$LOG")" -eq 2 ]
grep -Fq 'Bird fixed Sway start uptime=12.340000' "$LOG"
grep -Fq 'Bird fixed Sway ready uptime=12.340000' "$LOG"

# A config mismatch repairs only config.
printf '%s\n' broken >"$SWAY_DIR/config"
: >"$COMMANDS"
PATH="$BIN:/usr/bin:/bin" "$UNDER_TEST"
printf 'cp|-f|%s|%s\n' "$RUN_DIR/config" "$SWAY_DIR/config" \
	>"$TMP/expected"
cmp "$TMP/expected" "$COMMANDS"
cmp "$RUN_DIR/config" "$SWAY_DIR/config"

# Trailing profile bytes are rejected and repaired exactly.
printf '%s\n' trailing >>"$PROFILE_DIR/095-sway"
: >"$COMMANDS"
PATH="$BIN:/usr/bin:/bin" "$UNDER_TEST"
printf 'cp|-f|%s|%s\n' "$RUN_DIR/095-sway" "$PROFILE_DIR/095-sway" \
	>"$TMP/expected"
cmp "$TMP/expected" "$COMMANDS"
cmp "$RUN_DIR/095-sway" "$PROFILE_DIR/095-sway"

if grep -Eq '^[[:space:]]*(cmp|cut)[[:space:]]' "$SOURCE"; then
	printf '%s\n' 'fixed Sway regained accepted-path cmp/cut children' >&2
	exit 1
fi
sh -n "$SOURCE" "$UNDER_TEST"
printf '%s\n' 'stock-root fixed-Sway tests: PASS'
