#!/bin/sh
# Host-only fault-injection tests for the atomic shutdown configuration
# checkpoint.  The production script is path-substituted into a private
# fixture; command shims affect only the copied script's PATH.

# This file doubles as the checkpoint command shim through private symlinks.
# Keeping the dispatcher here avoids generating executable helper scripts at
# runtime.
case ${0##*/} in
	cp|mv|sync|mkdir|cut)
		if [ -n "${BIRD_TEST_CHILD_LOG:-}" ]; then
			printf '%s\n' "${0##*/}" >>"$BIRD_TEST_CHILD_LOG"
		fi
		;;
esac

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
	mkdir)
		if [ "${BIRD_TEST_MKDIR_MODE:-success}" = fail ]; then
			exit 26
		fi
		"$BIRD_TEST_REAL_MKDIR" "$@"
		exit $?
		;;
	cut)
		# The checkpoint must obtain uptime through the shell builtin. Any cut
		# launch is an immediate regression, independent of its arguments.
		exit 27
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
ln -s "$SELF" "$MOCK_BIN/mkdir"
ln -s "$SELF" "$MOCK_BIN/cut"

BIRD_TEST_REAL_CP=$(command -v cp)
BIRD_TEST_REAL_MV=$(command -v mv)
BIRD_TEST_REAL_MKDIR=$(command -v mkdir)
export BIRD_TEST_REAL_CP BIRD_TEST_REAL_MV BIRD_TEST_REAL_MKDIR

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

assert_child_count() {
	CHILD_NAME=$1
	EXPECTED_COUNT=$2
	ACTUAL_COUNT=$(awk -v child="$CHILD_NAME" \
		'$0 == child { count++ } END { print count + 0 }' "$CHILD_LOG")
	[ "$ACTUAL_COUNT" -eq "$EXPECTED_COUNT" ] ||
		fail_test "expected $EXPECTED_COUNT $CHILD_NAME child calls, got $ACTUAL_COUNT"
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
	CHILD_LOG=$CASE_DIR/checkpoint-children.log

	mkdir -p "$CONFIG_DIR" "${LOG_FILE%/*}" "${UPTIME_FILE%/*}"
	printf '%s\n' 'known-good checkpoint: complete' >"$EXPECTED_OLD"
	printf '%s\n' 'replacement checkpoint: complete' >"$EXPECTED_NEW"
	cp "$EXPECTED_OLD" "$BACKUP_FILE"
	cp "$EXPECTED_NEW" "$SOURCE_FILE"
	printf '%s\n' '12.50 4.25' >"$UPTIME_FILE"
	: >"$CHILD_LOG"

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
	MKDIR_MODE=${4:-success}
	set +e
	BIRD_TEST_COPY_MODE=$COPY_MODE \
	BIRD_TEST_MOVE_MODE=$MOVE_MODE \
	BIRD_TEST_SYNC_MODE=$SYNC_MODE \
	BIRD_TEST_MKDIR_MODE=$MKDIR_MODE \
	BIRD_TEST_CHILD_LOG=$CHILD_LOG \
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
assert_log_has "$LOG_FILE" 'Bird fixed shutdown save start uptime=12.50'
assert_log_has "$LOG_FILE" 'Bird fixed shutdown save ready uptime=12.50'
assert_child_count mkdir 0
assert_child_count cut 0
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

# An unchanged source with its normal existing log directory must bypass
# mkdir, cut, copy, sync, and rename. All five shims are armed or counted so
# the test measures the three common child launches removed from this path.
prepare_case unchanged
cp "$EXPECTED_OLD" "$SOURCE_FILE"
run_checkpoint fail fail fail fail
[ "$CHECKPOINT_STATUS" -eq 0 ] || fail_test "unchanged exited $CHECKPOINT_STATUS"
cmp -s "$EXPECTED_OLD" "$BACKUP_FILE" ||
	fail_test 'unchanged checkpoint modified the backup'
assert_log_has "$LOG_FILE" 'config stage=compare result=unchanged'
if grep -Fq 'config stage=temp-create' "$LOG_FILE"; then
	fail_test 'unchanged checkpoint created a temporary file'
fi
assert_log_has "$LOG_FILE" 'Bird fixed shutdown save start uptime=12.50'
assert_log_has "$LOG_FILE" 'Bird fixed shutdown save ready uptime=12.50'
assert_child_count mkdir 0
assert_child_count cut 0
assert_child_count cp 0
assert_child_count mv 0
assert_child_count sync 0
assert_no_temporary "$BACKUP_FILE"

# A missing log directory remains a supported recovery path. It must invoke
# mkdir exactly once, then continue through the same builtin-uptime fast path.
prepare_case missing-log-directory
cp "$EXPECTED_OLD" "$SOURCE_FILE"
rmdir "${LOG_FILE%/*}"
run_checkpoint fail fail fail success
[ "$CHECKPOINT_STATUS" -eq 0 ] ||
	fail_test "missing log directory recovery exited $CHECKPOINT_STATUS"
assert_log_has "$LOG_FILE" 'Bird fixed shutdown save start uptime=12.50'
assert_log_has "$LOG_FILE" 'Bird fixed shutdown save ready uptime=12.50'
assert_child_count mkdir 1
assert_child_count cut 0
assert_child_count cp 0
assert_child_count mv 0
assert_child_count sync 0
assert_no_temporary "$BACKUP_FILE"

# A truncated uptime record must retain the start-phase exit and diagnostic
# instead of proceeding into any temporary-copy or durability operation.
prepare_case malformed-start-uptime
printf '%s' '12.50 4.25' >"$UPTIME_FILE"
run_checkpoint fail fail fail fail
assert_failed_checkpoint 72 \
	'config stage=start result=failed reason=uptime-read exit=72'
assert_child_count mkdir 0
assert_child_count cut 0
assert_child_count cp 0
assert_child_count mv 0
assert_child_count sync 0

# Feed one valid record followed by a truncated record through a FIFO so the
# unchanged ready phase retains its distinct exit 75 diagnostic.
prepare_case malformed-unchanged-ready-uptime
cp "$EXPECTED_OLD" "$SOURCE_FILE"
rm -f "$UPTIME_FILE"
mkfifo "$UPTIME_FILE"
(
	printf '%s\n' '12.50 4.25' >"$UPTIME_FILE"
	printf '%s' 'broken' >"$UPTIME_FILE"
) &
UPTIME_WRITER=$!
run_checkpoint fail fail fail fail
kill "$UPTIME_WRITER" 2>/dev/null || :
wait "$UPTIME_WRITER" 2>/dev/null || :
assert_failed_checkpoint 75 \
	'config stage=ready result=failed reason=uptime-read exit=75'
assert_child_count mkdir 0
assert_child_count cut 0
assert_child_count cp 0
assert_child_count mv 0
assert_child_count sync 0

# The changed path has already durably committed when its final uptime read
# fails. Preserve that snapshot and its distinct exit 83 diagnostic.
prepare_case malformed-changed-ready-uptime
rm -f "$UPTIME_FILE"
mkfifo "$UPTIME_FILE"
(
	printf '%s\n' '12.50 4.25' >"$UPTIME_FILE"
	printf '%s' 'broken' >"$UPTIME_FILE"
) &
UPTIME_WRITER=$!
run_checkpoint success success success fail
kill "$UPTIME_WRITER" 2>/dev/null || :
wait "$UPTIME_WRITER" 2>/dev/null || :
[ "$CHECKPOINT_STATUS" -eq 83 ] ||
	fail_test "expected changed ready exit 83, got $CHECKPOINT_STATUS"
assert_log_has "$LOG_FILE" \
	'config stage=ready result=failed reason=uptime-read exit=83'
cmp -s "$EXPECTED_NEW" "$BACKUP_FILE" ||
	fail_test 'ready uptime failure lost the durably committed checkpoint'
assert_child_count mkdir 0
assert_child_count cut 0
assert_child_count cp 1
assert_child_count mv 1
assert_child_count sync 2
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
