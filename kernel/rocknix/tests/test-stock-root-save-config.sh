#!/bin/sh
# Host-only fault-injection tests for the atomic shutdown configuration
# checkpoint.  The production script is path-substituted into a private
# fixture; command shims affect only the copied script's PATH.

# This file doubles as the cp/mv/sync shim through private symlinks.  Keeping
# the dispatcher here avoids generating executable helper scripts at runtime.
case ${0##*/} in
	cp)
		case ${BIRD_TEST_COPY_MODE:-success} in
			fail)
				exit 23
				;;
			interrupt)
				kill -TERM "$PPID"
				exit 143
				;;
			success|corrupt)
				"$BIRD_TEST_REAL_CP" "$@" || exit $?
				if [ "${BIRD_TEST_COPY_MODE:-success}" = corrupt ]; then
					for BIRD_TEST_DESTINATION do :; done
					printf '%s\n' 'fault-injected trailing bytes' >>"$BIRD_TEST_DESTINATION"
				fi
				exit 0
				;;
			*)
				exit 125
				;;
		esac
		;;
	mv)
		if [ "${BIRD_TEST_MOVE_MODE:-success}" = fail ]; then
			exit 24
		fi
		"$BIRD_TEST_REAL_MV" "$@"
		exit $?
		;;
	sync)
		if [ "${BIRD_TEST_SYNC_MODE:-success}" = fail ]; then
			exit 25
		fi
		exit 0
		;;
esac

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
IMPLEMENTATION=$ROOT/kernel/rocknix/stock-root/bird-save-config.sh
SELF=$ROOT/kernel/rocknix/tests/test-stock-root-save-config.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-save-config.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

MOCK_BIN=$TMP/mock-bin
mkdir -p "$MOCK_BIN"
ln -s "$SELF" "$MOCK_BIN/cp"
ln -s "$SELF" "$MOCK_BIN/mv"
ln -s "$SELF" "$MOCK_BIN/sync"

BIRD_TEST_REAL_CP=$(command -v cp)
BIRD_TEST_REAL_MV=$(command -v mv)
export BIRD_TEST_REAL_CP BIRD_TEST_REAL_MV

fail_test() {
	printf 'save-config test failure: %s\n' "$*" >&2
	exit 1
}

assert_log_has() {
	LOG_FILE=$1
	EXPECTED=$2
	grep -Fq "$EXPECTED" "$LOG_FILE" ||
		fail_test "missing diagnostic '$EXPECTED' in $LOG_FILE"
}

assert_no_temporary() {
	BACKUP_PATH=$1
	set -- "$BACKUP_PATH".tmp.*
	[ ! -e "$1" ] || fail_test "temporary checkpoint survived: $1"
}

prepare_case() {
	CASE_NAME=$1
	CASE_DIR=$TMP/$CASE_NAME
	CONFIG_DIR=$CASE_DIR/storage/.config/system/configs
	LOG_FILE=$CASE_DIR/storage/bird-data/Bird/log/shutdown-latest.log
	SOURCE_FILE=$CONFIG_DIR/system.cfg
	BACKUP_FILE=$CONFIG_DIR/system.cfg.backup
	EXPECTED_OLD=$CASE_DIR/expected-old
	EXPECTED_NEW=$CASE_DIR/expected-new
	UPTIME_FILE=$CASE_DIR/proc/uptime
	UNDER_TEST=$CASE_DIR/bird-save-config.sh

	mkdir -p "$CONFIG_DIR" "${LOG_FILE%/*}" "${UPTIME_FILE%/*}"
	printf '%s\n' 'known-good checkpoint: complete' >"$EXPECTED_OLD"
	printf '%s\n' 'replacement checkpoint: complete' >"$EXPECTED_NEW"
	cp "$EXPECTED_OLD" "$BACKUP_FILE"
	cp "$EXPECTED_NEW" "$SOURCE_FILE"
	printf '%s\n' '12.50 4.25' >"$UPTIME_FILE"

	sed \
		-e "s#^SOURCE=.*#SOURCE=$SOURCE_FILE#" \
		-e "s#^BACKUP=.*#BACKUP=$BACKUP_FILE#" \
		-e "s#^LOG=.*#LOG=$LOG_FILE#" \
		-e 's#^TEMP_STEM=.*#TEMP_STEM=${BACKUP}.tmp.test#' \
		-e "s#/proc/uptime#$UPTIME_FILE#g" \
		"$IMPLEMENTATION" >"$UNDER_TEST"
	chmod 0755 "$UNDER_TEST"
}

run_checkpoint() {
	COPY_MODE=$1
	MOVE_MODE=$2
	SYNC_MODE=$3
	set +e
	BIRD_TEST_COPY_MODE=$COPY_MODE \
	BIRD_TEST_MOVE_MODE=$MOVE_MODE \
	BIRD_TEST_SYNC_MODE=$SYNC_MODE \
	PATH=$MOCK_BIN:$PATH \
		"$UNDER_TEST"
	CHECKPOINT_STATUS=$?
	set -e
}

assert_failed_checkpoint() {
	EXPECTED_STATUS=$1
	EXPECTED_DIAGNOSTIC=$2
	[ "$CHECKPOINT_STATUS" -eq "$EXPECTED_STATUS" ] ||
		fail_test "expected exit $EXPECTED_STATUS, got $CHECKPOINT_STATUS"
	assert_log_has "$LOG_FILE" "$EXPECTED_DIAGNOSTIC"
	cmp -s "$EXPECTED_OLD" "$BACKUP_FILE" ||
		fail_test 'failed checkpoint replaced or damaged the old backup'
	assert_no_temporary "$BACKUP_FILE"
}

# Changed configuration: a verified temporary snapshot is committed and the
# resulting backup is exactly the source.
prepare_case success
run_checkpoint success success success
[ "$CHECKPOINT_STATUS" -eq 0 ] || fail_test "success exited $CHECKPOINT_STATUS"
cmp -s "$EXPECTED_NEW" "$BACKUP_FILE" ||
	fail_test 'successful checkpoint does not match the source'
assert_log_has "$LOG_FILE" 'config stage=verify result=identical'
assert_log_has "$LOG_FILE" 'config stage=commit result=complete'
assert_log_has "$LOG_FILE" 'config stage=directory-flush result=complete'
assert_no_temporary "$BACKUP_FILE"

# Leftovers from an uncatchable failure or a reused PID must never be opened
# with truncation. The bounded exclusive loop skips them and commits through a
# fresh sibling while leaving every stale byte untouched.
prepare_case stale-temporaries
printf '%s\n' 'stale-zero' >"$BACKUP_FILE.tmp.test.0"
printf '%s\n' 'stale-one' >"$BACKUP_FILE.tmp.test.1"
cp "$BACKUP_FILE.tmp.test.0" "$CASE_DIR/stale-zero.expected"
cp "$BACKUP_FILE.tmp.test.1" "$CASE_DIR/stale-one.expected"
run_checkpoint success success success
[ "$CHECKPOINT_STATUS" -eq 0 ] ||
	fail_test "stale-temporary recovery exited $CHECKPOINT_STATUS"
cmp -s "$EXPECTED_NEW" "$BACKUP_FILE" ||
	fail_test 'stale temporary recovery did not commit the source'
cmp -s "$CASE_DIR/stale-zero.expected" "$BACKUP_FILE.tmp.test.0" ||
	fail_test 'exclusive creation truncated stale suffix zero'
cmp -s "$CASE_DIR/stale-one.expected" "$BACKUP_FILE.tmp.test.1" ||
	fail_test 'exclusive creation truncated stale suffix one'
assert_log_has "$LOG_FILE" "path=$BACKUP_FILE.tmp.test.2"
rm -f "$BACKUP_FILE.tmp.test.0" "$BACKUP_FILE.tmp.test.1"
assert_no_temporary "$BACKUP_FILE"

# If all bounded candidates are uncatchable-style leftovers, fail closed and
# retain the existing checkpoint and every stale candidate.
prepare_case stale-exhaustion
STALE_SUFFIX=0
while [ "$STALE_SUFFIX" -lt 32 ]; do
	printf 'stale-%s\n' "$STALE_SUFFIX" >"$BACKUP_FILE.tmp.test.$STALE_SUFFIX"
	STALE_SUFFIX=$((STALE_SUFFIX + 1))
done
run_checkpoint success success success
[ "$CHECKPOINT_STATUS" -eq 76 ] ||
	fail_test "stale suffix exhaustion exited $CHECKPOINT_STATUS"
assert_log_has "$LOG_FILE" \
	'config stage=temp-create result=failed reason=exclusive-suffixes-exhausted exit=76'
cmp -s "$EXPECTED_OLD" "$BACKUP_FILE" ||
	fail_test 'suffix exhaustion replaced or damaged the old backup'
STALE_SUFFIX=0
while [ "$STALE_SUFFIX" -lt 32 ]; do
	[ "$(cat "$BACKUP_FILE.tmp.test.$STALE_SUFFIX")" = "stale-$STALE_SUFFIX" ] ||
		fail_test "suffix exhaustion modified stale candidate $STALE_SUFFIX"
	STALE_SUFFIX=$((STALE_SUFFIX + 1))
done

# An unchanged source must bypass copy, sync, and rename.  All three shims are
# armed to fail so an accidental call turns this case red.
prepare_case unchanged
cp "$EXPECTED_OLD" "$SOURCE_FILE"
run_checkpoint fail fail fail
[ "$CHECKPOINT_STATUS" -eq 0 ] || fail_test "unchanged exited $CHECKPOINT_STATUS"
cmp -s "$EXPECTED_OLD" "$BACKUP_FILE" ||
	fail_test 'unchanged checkpoint modified the backup'
assert_log_has "$LOG_FILE" 'config stage=compare result=unchanged'
if grep -Fq 'config stage=temp-create' "$LOG_FILE"; then
	fail_test 'unchanged checkpoint created a temporary file'
fi
assert_no_temporary "$BACKUP_FILE"

prepare_case copy-failure
run_checkpoint fail success success
assert_failed_checkpoint 77 \
	'config stage=copy result=failed reason=copy-failed exit=77'

prepare_case verification-failure
run_checkpoint corrupt success success
assert_failed_checkpoint 78 \
	'config stage=verify result=failed reason=byte-mismatch exit=78'

prepare_case flush-failure
run_checkpoint success success fail
assert_failed_checkpoint 80 \
	'config stage=flush result=failed reason=sync-failed exit=80'

prepare_case rename-failure
run_checkpoint success fail success
assert_failed_checkpoint 81 \
	'config stage=commit result=failed reason=rename-failed exit=81'

# A termination received while copying must use the signal diagnostic and the
# EXIT cleanup trap, again leaving the known-good backup untouched.
prepare_case interruption
run_checkpoint interrupt success success
assert_failed_checkpoint 79 \
	'config stage=signal result=failed reason=interrupted exit=79'

sh -n "$IMPLEMENTATION"
sh -n "$0"
printf '%s\n' 'stock-root save-config tests: PASS'
