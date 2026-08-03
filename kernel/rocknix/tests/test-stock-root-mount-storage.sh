#!/bin/bash
# Host-only regression coverage for the stock-root storage mount topology.
# The executable setup prefix is sourced with every mount operation mocked;
# this test cannot address a block device or write outside its temporary log.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
MOUNT_STORAGE=$ROOT/kernel/rocknix/stock-root/mount-storage.sh
SUPERVISOR=$ROOT/kernel/rocknix/stock-root/supervisor.sh
EARLY_BUILDER=$ROOT/kernel/rocknix/build-stock-root-early-initramfs.sh
INIT_BUSYBOX=$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/usr/bin/busybox
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-mount-storage.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

PREFIX_RAW=$TMP/mount-storage-prefix-raw.sh
PREFIX=$TMP/mount-storage-prefix.sh
awk '
	/^# These are deliberately copied after \/storage exists\./ { exit }
	{ print }
' "$MOUNT_STORAGE" >"$PREFIX_RAW"
sed \
	-e 's#^SUSPEND_CONFIG=.*#SUSPEND_CONFIG=$TEST_SUSPEND_CONFIG#' \
	-e 's#^SUSPEND_SLEEP_CONFIG=.*#SUSPEND_SLEEP_CONFIG=$TEST_SLEEP_CONFIG#' \
	-e 's#^SUSPEND_LOGIND_CONFIG=.*#SUSPEND_LOGIND_CONFIG=$TEST_LOGIND_CONFIG#' \
	-e 's#^FIXED_SLEEP_CONFIG=.*#FIXED_SLEEP_CONFIG=$TEST_FIXED_SLEEP_CONFIG#' \
	-e 's#^FIXED_LOGIND_CONFIG=.*#FIXED_LOGIND_CONFIG=$TEST_FIXED_LOGIND_CONFIG#' \
	-e 's#^FIXED_SUSPEND_POLICY=.*#FIXED_SUSPEND_POLICY=$TEST_FIXED_SUSPEND_POLICY#' \
	-e 's#^SYSTEM_BUSYBOX=.*#SYSTEM_BUSYBOX=$TEST_SYSTEM_BUSYBOX#' \
	-e 's#^RETROARCH_CONFIG_DIR=.*#RETROARCH_CONFIG_DIR=$TEST_RETROARCH_CONFIG_DIR#' \
	-e 's#^FIXED_RETROARCH_CONFIG_DIR=.*#FIXED_RETROARCH_CONFIG_DIR=$TEST_FIXED_RETROARCH_CONFIG_DIR#' \
	"$PREFIX_RAW" >"$PREFIX"

grep -q '^STORAGE_IMAGE=/birddata/MUOS/runtime/ROCKNIX-STORAGE$' "$PREFIX"
grep -q '^mount --move /birddata /run/bird-data || {$' "$PREFIX"
grep -q '^mount --bind /run/bird-data /storage/bird-data || {$' "$PREFIX"
if grep -Eq '^mount --move [^ ]+ /storage(/|[[:space:]])' "$PREFIX"; then
	printf '%s\n' 'real data mount is still moved beneath /storage' >&2
	exit 1
fi

# The pinned initramfs has no chmod applet. Runtime installation must use the
# pinned final-root BusyBox already mounted below /sysroot, and the generated
# init must stop before stock UI startup if that transaction fails.
[ -f "$INIT_BUSYBOX" ]
if strings -a -n 2 "$INIT_BUSYBOX" | grep -Fqx chmod; then
	printf '%s\n' 'pinned initramfs unexpectedly gained chmod' >&2
	exit 1
fi
if grep -Eq '^[[:space:]]*chmod[[:space:]]' "$MOUNT_STORAGE"; then
	printf '%s\n' 'mount-storage still invokes unavailable chmod' >&2
	exit 1
fi
grep -Fq '/sysroot/usr/bin/busybox chmod 0755' "$MOUNT_STORAGE"
grep -Fq '/sysroot/usr/bin/busybox chmod 0644' "$MOUNT_STORAGE"
grep -Fq '[ -x "/storage/.config/bird/$FILE" ] || return 1' \
	"$MOUNT_STORAGE"
grep -Fq 'LAUNCHER=/flash/bird/bird-launcher' "$SUPERVISOR"
grep -Fq 'RUNNER=/flash/bird/run-content.sh' "$SUPERVISOR"
if sed -n '/^for FILE in bird-pidwait/,/^done$/p' "$MOUNT_STORAGE" |
	grep -Fq 'bird-launcher'; then
	printf '%s\n' 'immutable final-root launcher is still copied per boot' >&2
	exit 1
fi
if sed -n '/^for FILE in bird-pidwait/,/^done$/p' "$MOUNT_STORAGE" |
	grep -Fq 'supervisor.sh'; then
	printf '%s\n' 'immutable supervisor is still copied per boot' >&2
	exit 1
fi
if sed -n '/^for FILE in bird-pidwait/,/^done$/p' "$MOUNT_STORAGE" |
	grep -Fq 'first-frame-prep.sh'; then
	printf '%s\n' 'immutable first-frame preparation is still copied per boot' >&2
	exit 1
fi
if sed -n '/^for FILE in bird-pidwait/,/^done$/p' "$MOUNT_STORAGE" |
	grep -Fq 'capture-boot-state.sh'; then
	printf '%s\n' 'immutable boot snapshot is still copied per boot' >&2
	exit 1
fi
grep -Fq 'print "  if [ \"${BOOT_STEP}\" = \"mount_storage\" ]; then"' \
	"$EARLY_BUILDER"
grep -Fq 'mount-storage-latest.log' "$EARLY_BUILDER"
grep -Fq 'mount --bind /flash/bird/bird-restore-suspend-policy.sh \' \
	"$MOUNT_STORAGE"
grep -Fq '/sysroot/usr/lib/autostart/common/009-sleepmode || {' \
	"$MOUNT_STORAGE"
if sed -n '/^for SCRIPT in 001-emulationstation/,/^done$/p' "$MOUNT_STORAGE" |
	grep -Fq '009-sleepmode'; then
	printf '%s\n' 'common suspend recovery is still suppressed as a no-op' >&2
	exit 1
fi

EVENTS=$TMP/events
FAIL_OPERATION=
TEST_SUSPEND_CONFIG=$TMP/storage/system.cfg
TEST_SLEEP_CONFIG=$TMP/storage/sleep.conf.d/sleep.conf
TEST_LOGIND_CONFIG=$TMP/storage/logind.conf.d/login.conf
TEST_FIXED_SLEEP_CONFIG=$ROOT/kernel/rocknix/stock-root/bird-sleep.conf
TEST_FIXED_LOGIND_CONFIG=$ROOT/kernel/rocknix/stock-root/bird-logind.conf
TEST_FIXED_SUSPEND_POLICY=$ROOT/kernel/rocknix/stock-root/bird-suspend-policy.generated.sh
TEST_RETROARCH_CONFIG_DIR=$TMP/storage/retroarch
TEST_FIXED_RETROARCH_CONFIG_DIR=$TMP/fixed-retroarch
TEST_SYSTEM_BUSYBOX=$TMP/system-busybox-policy
POLICY_EVENTS=$TMP/policy-events
/bin/mkdir -p "${TEST_SUSPEND_CONFIG%/*}" \
	"${TEST_SLEEP_CONFIG%/*}" "${TEST_LOGIND_CONFIG%/*}" \
	"$TEST_RETROARCH_CONFIG_DIR" "$TEST_FIXED_RETROARCH_CONFIG_DIR"
printf '%s\n' 'fixed core options' \
	>"$TEST_FIXED_RETROARCH_CONFIG_DIR/retroarch-core-options.cfg"
printf '%s\n' 'fixed retroarch config' \
	>"$TEST_FIXED_RETROARCH_CONFIG_DIR/retroarch.cfg"
cat >"$TEST_SUSPEND_CONFIG" <<'EOF'
system.suspendmode=mem
system.suspendmode=off
system.suspend.enable=1
system.suspend.enable=0
system.suspend.enable_timed_shutdown=0
system.suspend.enable_timed_shutdown=1
system.suspend.park_cores=1
system.suspend.park_cores=0
system.hostname=H700
unrelated.setting=preserved
EOF
printf '%s\n' stale-sleep >"$TEST_SLEEP_CONFIG"
printf '%s\n' stale-logind >"$TEST_LOGIND_CONFIG"
printf '%s\n' '[Sleep]' 'AllowSuspend=yes' \
	>"${TEST_SLEEP_CONFIG%/*}/zz-override.conf"
printf '%s\n' '[Login]' 'HandleLidSwitch=suspend' \
	>"${TEST_LOGIND_CONFIG%/*}/zz-override.conf"
printf '%s\n' 'must remain' >"$TMP/outside-policy-target"
ln -s "$TMP/outside-policy-target" \
	"${TEST_LOGIND_CONFIG%/*}/zzz-symlink.conf"
cat >"$TEST_SYSTEM_BUSYBOX" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$POLICY_EVENTS"
APPLET=$1
shift
case "$APPLET" in
	awk) exec /usr/bin/awk "$@" ;;
	cmp) exec /usr/bin/cmp "$@" ;;
	cp) exec /bin/cp "$@" ;;
	chmod) exec /bin/chmod "$@" ;;
	mv) exec /bin/mv "$@" ;;
	rm) exec /bin/rm "$@" ;;
	stat)
		[ "$1" = -t ] || exit 2
		MODE=$(/usr/bin/stat -f %Lp "$2" 2>/dev/null || /usr/bin/stat -c %a "$2") || exit 1
		case "$MODE" in
			644) HEX_MODE=81a4 ;;
			600) HEX_MODE=8180 ;;
			755) HEX_MODE=81ed ;;
			*) exit 2 ;;
		esac
		printf '%s 0 0 %s 0 0 0 0\n' "$2" "$HEX_MODE"
		;;
	*) exit 2 ;;
esac
EOF
/bin/chmod 0755 "$TEST_SYSTEM_BUSYBOX"
export POLICY_EVENTS

mkdir() {
	printf 'mkdir|%s\n' "$*" >>"$EVENTS"
}

mount_part() {
	printf 'loop|%s|%s|%s\n' "$1" "$2" "$3" >>"$EVENTS"
	[ "$FAIL_OPERATION" != loop ]
}

mount() {
	printf 'mount|%s\n' "$*" >>"$EVENTS"
	case "$*" in
		'--move /birddata /run/bird-data')
			[ "$FAIL_OPERATION" != move ]
			;;
		'--bind /run/bird-data /storage/bird-data')
			[ "$FAIL_OPERATION" != data-bind ]
			;;
		*) return 0 ;;
	esac
}

error() {
	printf 'error|%s|%s\n' "$1" "$2" >>"$EVENTS"
}

run_prefix() {
	: >"$EVENTS"
	set +e
	# shellcheck source=/dev/null
	. "$PREFIX"
	STATUS=$?
	set -e
}

# The loop image must be opened while its backing filesystem still has the
# initramfs name. The real p6 mount then moves outside /storage, its bind alias
# is published below /storage, and only then may ROM and BIOS aliases appear.
FAIL_OPERATION=
: >"$POLICY_EVENTS"
run_prefix
[ "$STATUS" -eq 0 ]
grep -Fxq 'system.suspendmode=off' "$TEST_SUSPEND_CONFIG"
grep -Fxq 'system.suspend.enable=1' "$TEST_SUSPEND_CONFIG"
grep -Fxq 'system.suspend.enable_timed_shutdown=1' "$TEST_SUSPEND_CONFIG"
grep -Fxq 'system.suspend.park_cores=1' "$TEST_SUSPEND_CONFIG"
[ "$(grep -c '^system\.suspendmode=' "$TEST_SUSPEND_CONFIG")" -eq 1 ]
[ "$(grep -c '^system\.suspend\.enable=' "$TEST_SUSPEND_CONFIG")" -eq 1 ]
[ "$(grep -c '^system\.suspend\.enable_timed_shutdown=' "$TEST_SUSPEND_CONFIG")" -eq 1 ]
[ "$(grep -c '^system\.suspend\.park_cores=' "$TEST_SUSPEND_CONFIG")" -eq 1 ]
grep -Fxq 'unrelated.setting=preserved' "$TEST_SUSPEND_CONFIG"
cmp "$TEST_FIXED_SLEEP_CONFIG" "$TEST_SLEEP_CONFIG"
cmp "$TEST_FIXED_LOGIND_CONFIG" "$TEST_LOGIND_CONFIG"
cmp "$TEST_FIXED_RETROARCH_CONFIG_DIR/retroarch-core-options.cfg" \
	"$TEST_RETROARCH_CONFIG_DIR/retroarch-core-options.cfg"
cmp "$TEST_FIXED_RETROARCH_CONFIG_DIR/retroarch.cfg" \
	"$TEST_RETROARCH_CONFIG_DIR/retroarch.cfg"
# These are the exact three retained chksysconfig prerequisites. With all of
# them present, common/001 must not enter its broad stock-tree restore branch.
[ -s "$TEST_RETROARCH_CONFIG_DIR/retroarch-core-options.cfg" ]
[ -s "$TEST_RETROARCH_CONFIG_DIR/retroarch.cfg" ]
grep -q '^system[.]hostname=' "$TEST_SUSPEND_CONFIG"
[ ! -e "${TEST_SLEEP_CONFIG%/*}/zz-override.conf" ]
[ ! -e "${TEST_LOGIND_CONFIG%/*}/zz-override.conf" ]
[ ! -L "${TEST_LOGIND_CONFIG%/*}/zzz-symlink.conf" ]
[ "$(cat "$TMP/outside-policy-target")" = 'must remain' ]
cat >"$TMP/expected-success" <<'EOF'
loop|/birddata/MUOS/runtime/ROCKNIX-STORAGE|/storage|loop,rw,noatime
mkdir|-p TEST_SLEEP_DIR TEST_LOGIND_DIR
mkdir|-p TEST_RETROARCH_DIR
mkdir|-p /run/bird-data /storage/bird-data /storage/roms /storage/.config/bird
mount|--move /birddata /run/bird-data
mount|--bind /run/bird-data /storage/bird-data
mount|--bind /storage/bird-data/ROMS /storage/roms
mkdir|-p /storage/roms/bios
mount|--bind /storage/bird-data/MUOS/bios /storage/roms/bios
EOF
sed -e "s#TEST_SLEEP_DIR#${TEST_SLEEP_CONFIG%/*}#" \
	-e "s#TEST_LOGIND_DIR#${TEST_LOGIND_CONFIG%/*}#" \
	-e "s#TEST_RETROARCH_DIR#$TEST_RETROARCH_CONFIG_DIR#" \
	"$TMP/expected-success" >"$TMP/expected-success.resolved"
cmp "$TMP/expected-success.resolved" "$EVENTS"

# Reverse the duplicate order to prove the canonical transaction agrees with
# ROCKNIX's first-match get_setting semantics in either corruption pattern.
cat >"$TEST_SUSPEND_CONFIG" <<'EOF'
system.suspendmode=off
system.suspendmode=mem
system.suspend.enable=0
system.suspend.enable=1
system.suspend.enable_timed_shutdown=1
system.suspend.enable_timed_shutdown=0
system.suspend.park_cores=0
system.suspend.park_cores=1
system.hostname=H700
unrelated.setting=preserved
EOF
# Equal bytes with stale modes must still take the replacement transaction.
/bin/chmod 0600 "$TEST_SLEEP_CONFIG" "$TEST_LOGIND_CONFIG"
: >"$POLICY_EVENTS"
run_prefix
[ "$STATUS" -eq 0 ]
for SETTING in \
	'system.suspendmode=off' \
	'system.suspend.enable=1' \
	'system.suspend.enable_timed_shutdown=1' \
	'system.suspend.park_cores=1'; do
	grep -Fxq "$SETTING" "$TEST_SUSPEND_CONFIG"
	[ "$(grep -Fxc "$SETTING" "$TEST_SUSPEND_CONFIG")" -eq 1 ]
done
[ "$(/usr/bin/stat -f %Lp "$TEST_SLEEP_CONFIG" 2>/dev/null || /usr/bin/stat -c %a "$TEST_SLEEP_CONFIG")" = 644 ]
[ "$(/usr/bin/stat -f %Lp "$TEST_LOGIND_CONFIG" 2>/dev/null || /usr/bin/stat -c %a "$TEST_LOGIND_CONFIG")" = 644 ]
grep -q '^awk ' "$POLICY_EVENTS"
[ "$(grep -c '^chmod 0644 ' "$POLICY_EVENTS")" -eq 3 ]

# The accepted policy causes no configuration or file-copy write on the next
# boot; only the two read-only comparisons and mode reads remain.
cp "$TEST_SUSPEND_CONFIG" "$TMP/system.cfg.accepted"
: >"$POLICY_EVENTS"
run_prefix
[ "$STATUS" -eq 0 ]
cmp "$TMP/system.cfg.accepted" "$TEST_SUSPEND_CONFIG"
[ "$(grep -c '^cmp -s ' "$POLICY_EVENTS")" -eq 2 ]
! grep -Eq '^(awk|cp|chmod|mv|rm) ' "$POLICY_EVENTS"

# A competing *.conf that cannot be removed must fail before final-root policy
# can become ambiguous. In particular, rm -f must not turn an unexpected
# directory into a silently accepted override boundary.
/bin/mkdir "${TEST_SLEEP_CONFIG%/*}/zzz-directory.conf"
: >"$POLICY_EVENTS"
FAIL_OPERATION=
run_prefix 2>"$TMP/expected-policy-directory-failure.err"
[ "$STATUS" -eq 1 ]
[ -s "$TMP/expected-policy-directory-failure.err" ]
grep -Fxq "rm -f ${TEST_SLEEP_CONFIG%/*}/zzz-directory.conf" "$POLICY_EVENTS"
if grep -Fq 'mount|--move /birddata /run/bird-data' "$EVENTS"; then
	printf '%s\n' 'ambiguous sleep policy continued into final-root setup' >&2
	exit 1
fi
/bin/rmdir "${TEST_SLEEP_CONFIG%/*}/zzz-directory.conf"

# A failed move must stop before any data, ROM, or BIOS bind is attempted.
FAIL_OPERATION=move
run_prefix
[ "$STATUS" -eq 1 ]
cat >"$TMP/expected-move-failure" <<'EOF'
loop|/birddata/MUOS/runtime/ROCKNIX-STORAGE|/storage|loop,rw,noatime
mkdir|-p TEST_SLEEP_DIR TEST_LOGIND_DIR
mkdir|-p TEST_RETROARCH_DIR
mkdir|-p /run/bird-data /storage/bird-data /storage/roms /storage/.config/bird
mount|--move /birddata /run/bird-data
error|bird-data-move|Could not move large Bird data volume to its final mount
EOF
sed -e "s#TEST_SLEEP_DIR#${TEST_SLEEP_CONFIG%/*}#" \
	-e "s#TEST_LOGIND_DIR#${TEST_LOGIND_CONFIG%/*}#" \
	-e "s#TEST_RETROARCH_DIR#$TEST_RETROARCH_CONFIG_DIR#" \
	"$TMP/expected-move-failure" >"$TMP/expected-move-failure.resolved"
cmp "$TMP/expected-move-failure.resolved" "$EVENTS"

# A failed publication bind must stop with the real filesystem still at its
# safe /run mount, without attempting either nested library bind.
FAIL_OPERATION=data-bind
run_prefix
[ "$STATUS" -eq 1 ]
cat >"$TMP/expected-bind-failure" <<'EOF'
loop|/birddata/MUOS/runtime/ROCKNIX-STORAGE|/storage|loop,rw,noatime
mkdir|-p TEST_SLEEP_DIR TEST_LOGIND_DIR
mkdir|-p TEST_RETROARCH_DIR
mkdir|-p /run/bird-data /storage/bird-data /storage/roms /storage/.config/bird
mount|--move /birddata /run/bird-data
mount|--bind /run/bird-data /storage/bird-data
error|bird-data-bind|Could not publish the large Bird data volume
EOF
sed -e "s#TEST_SLEEP_DIR#${TEST_SLEEP_CONFIG%/*}#" \
	-e "s#TEST_LOGIND_DIR#${TEST_LOGIND_CONFIG%/*}#" \
	-e "s#TEST_RETROARCH_DIR#$TEST_RETROARCH_CONFIG_DIR#" \
	"$TMP/expected-bind-failure" >"$TMP/expected-bind-failure.resolved"
cmp "$TMP/expected-bind-failure.resolved" "$EVENTS"

# Execute the exact runtime-copy block against a temporary ext4-like tree.
# A hostile chmod function proves the block has no hidden dependency on the
# applet missing from the device initramfs. Every program must remain
# executable, while static data needs only to be readable.
COPY_BLOCK_RAW=$TMP/runtime-copy-raw.sh
COPY_BLOCK=$TMP/runtime-copy.sh
awk '
	/^# These are deliberately copied after \/storage exists\./ { copy=1 }
	/^# Replace the generic partition scanner/ { exit }
	copy { print }
' "$MOUNT_STORAGE" >"$COPY_BLOCK_RAW"
sed -e 's#/flash/bird#$SOURCE_BIRD#g' \
	-e 's#/storage/\.config/bird#$DEST_BIRD#g' \
	-e 's#/storage/\.config/swap\.conf#$DEST_SWAP#g' \
	-e 's#/sysroot/usr/bin/busybox#$SYSTEM_BUSYBOX#g' \
	"$COPY_BLOCK_RAW" >"$COPY_BLOCK"

SOURCE_BIRD=$TMP/source-bird
DEST_BIRD=$TMP/dest-bird
DEST_SWAP=$TMP/dest-swap.conf
SYSTEM_BUSYBOX=$TMP/system-busybox
MODE_EVENTS=$TMP/mode-events
/bin/mkdir -p "$SOURCE_BIRD" "$DEST_BIRD"
EXECUTABLE_FILES='bird-pidwait bird-fixed-controls bird-powerstate bird-fixed-control-exit.sh bird-save-config.sh prepare-ports.sh verify-portmaster-provider.sh fixed-storage.sh bird-network.sh bird-suspend.sh bird-volume.sh bird-control-osd.sh'
MODE_EXECUTABLE_FILES='bird-pidwait bird-fixed-controls bird-powerstate bird-fixed-control-exit.sh bird-save-config.sh bird-suspend.sh bird-volume.sh bird-control-osd.sh prepare-ports.sh verify-portmaster-provider.sh fixed-storage.sh bird-network.sh'
for FILE in $EXECUTABLE_FILES portmaster-provider.manifest.tsv; do
	printf 'fixture %s\n' "$FILE" >"$SOURCE_BIRD/$FILE"
done
printf '%s\n' 'immutable launcher fixture' >"$SOURCE_BIRD/bird-launcher"
printf '%s\n' 'immutable content dispatcher fixture' >"$SOURCE_BIRD/run-content.sh"
printf '%s\n' 'immutable supervisor fixture' >"$SOURCE_BIRD/supervisor.sh"
printf '%s\n' 'immutable first-frame preparation fixture' \
	>"$SOURCE_BIRD/first-frame-prep.sh"
printf '%s\n' 'immutable boot snapshot fixture' \
	>"$SOURCE_BIRD/capture-boot-state.sh"
printf '%s\n' 'fixture swap' >"$SOURCE_BIRD/bird-swap.conf"
/bin/chmod 0644 "$SOURCE_BIRD"/*
/bin/chmod 0755 "$SOURCE_BIRD/bird-launcher"
/bin/chmod 0755 "$SOURCE_BIRD/run-content.sh"
/bin/chmod 0755 "$SOURCE_BIRD/supervisor.sh"
/bin/chmod 0755 "$SOURCE_BIRD/first-frame-prep.sh"
/bin/chmod 0755 "$SOURCE_BIRD/capture-boot-state.sh"
cat >"$SYSTEM_BUSYBOX" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$MODE_EVENTS"
[ "$1" = chmod ] || exit 2
shift
case "${CHMOD_BEHAVIOR:-apply}" in
	apply) exec /bin/chmod "$@" ;;
	fail) exit 1 ;;
	noop) exit 0 ;;
	*) exit 2 ;;
esac
EOF
/bin/chmod 0755 "$SYSTEM_BUSYBOX"
export MODE_EVENTS CHMOD_BEHAVIOR
CHMOD_CALLED=$TMP/chmod-called
chmod() {
	printf '%s\n' "$*" >>"$CHMOD_CALLED"
	return 127
}
: >"$MODE_EVENTS"
CHMOD_BEHAVIOR=apply
set +e
# shellcheck source=/dev/null
. "$COPY_BLOCK"
STATUS=$?
set -e
[ "$STATUS" -eq 0 ]
[ ! -e "$CHMOD_CALLED" ]
EXPECTED_MODE_EVENTS=$TMP/expected-mode-events
{
	printf 'chmod 0755'
	for FILE in $MODE_EXECUTABLE_FILES; do
		printf ' %s/%s' "$DEST_BIRD" "$FILE"
	done
	printf '\nchmod 0644 %s %s\n' \
		"$DEST_BIRD/portmaster-provider.manifest.tsv" "$DEST_SWAP"
} >"$EXPECTED_MODE_EVENTS"
cmp "$EXPECTED_MODE_EVENTS" "$MODE_EVENTS"

file_mode() {
	stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}
for FILE in $EXECUTABLE_FILES; do
	[ -x "$DEST_BIRD/$FILE" ]
	[ "$(file_mode "$DEST_BIRD/$FILE")" = 755 ]
	cmp "$SOURCE_BIRD/$FILE" "$DEST_BIRD/$FILE"
done
[ -x "$SOURCE_BIRD/bird-launcher" ]
[ ! -e "$DEST_BIRD/bird-launcher" ]
[ -x "$SOURCE_BIRD/run-content.sh" ]
[ ! -e "$DEST_BIRD/run-content.sh" ]
[ -x "$SOURCE_BIRD/supervisor.sh" ]
[ ! -e "$DEST_BIRD/supervisor.sh" ]
[ -x "$SOURCE_BIRD/first-frame-prep.sh" ]
[ ! -e "$DEST_BIRD/first-frame-prep.sh" ]
[ -x "$SOURCE_BIRD/capture-boot-state.sh" ]
[ ! -e "$DEST_BIRD/capture-boot-state.sh" ]
[ -r "$DEST_BIRD/portmaster-provider.manifest.tsv" ]
[ -r "$DEST_SWAP" ]
[ "$(file_mode "$DEST_BIRD/portmaster-provider.manifest.tsv")" = 644 ]
[ "$(file_mode "$DEST_SWAP")" = 644 ]

# A failed final-root chmod must fail the transaction immediately. A defective
# chmod that reports success without changing mode must also be rejected by
# the executable-capability postcondition.
/bin/rm -rf "$DEST_BIRD" "$DEST_SWAP"
/bin/mkdir -p "$DEST_BIRD"
: >"$MODE_EVENTS"
CHMOD_BEHAVIOR=fail
set +e
# shellcheck source=/dev/null
. "$COPY_BLOCK"
STATUS=$?
set -e
[ "$STATUS" -eq 1 ]
[ "$(wc -l <"$MODE_EVENTS" | tr -d ' ')" -eq 1 ]
[ ! -x "$DEST_BIRD/bird-pidwait" ]

/bin/rm -rf "$DEST_BIRD" "$DEST_SWAP"
/bin/mkdir -p "$DEST_BIRD"
: >"$MODE_EVENTS"
CHMOD_BEHAVIOR=noop
set +e
# shellcheck source=/dev/null
. "$COPY_BLOCK"
STATUS=$?
set -e
[ "$STATUS" -eq 1 ]
cmp "$EXPECTED_MODE_EVENTS" "$MODE_EVENTS"
[ ! -x "$DEST_BIRD/bird-pidwait" ]
[ ! -e "$CHMOD_CALLED" ]

# Exercise the exact init-rewrite AWK program against a minimal pinned-init
# fixture. A failed storage step must enter the fatal wait before any later
# boot step, root-ready notification, final handoff, or stock startup marker.
INIT_REWRITE=$TMP/init-rewrite.awk
awk '
	BEGIN { quote = sprintf("%c", 39) }
	$0 == "awk " quote { copy = 1; next }
	copy && index($0, quote " \"$OFFICIAL_INIT\" >") == 1 { exit }
	copy { print }
' "$EARLY_BUILDER" >"$INIT_REWRITE"
grep -Fq 'print "  if [ \"${BOOT_STEP}\" = \"mount_storage\" ]; then"' \
	"$INIT_REWRITE"
grep -Fq 'while :; do sleep 3600; done' "$INIT_REWRITE"

OFFICIAL_INIT_FIXTURE=$TMP/official-init-fixture.sh
GENERATED_INIT_RAW=$TMP/generated-init-raw.sh
GENERATED_INIT=$TMP/generated-init.sh
cat >"$OFFICIAL_INIT_FIXTURE" <<'EOF'
#!/bin/sh
hidecursor
for BOOT_STEP in \
    load_modules \
    mount_storage \
    check_update \
    prepare_sysroot
do
  ${BOOT_STEP}
done
# move some special filesystems
printf '%s\n' stock-handoff >>"$INIT_EVENTS"
EOF
awk -f "$INIT_REWRITE" "$OFFICIAL_INIT_FIXTURE" >"$GENERATED_INIT_RAW"
sed -e 's#/bird-early\.sh#"$BIRD_EARLY"#g' \
	-e 's#>/dev/kmsg#>"$KMSG"#g' \
	-e 's#in /run/bird-data /birddata#in "$LOG_ROOT_A" "$LOG_ROOT_B"#g' \
	"$GENERATED_INIT_RAW" >"$GENERATED_INIT"

INIT_EVENTS=$TMP/init-events
KMSG=$TMP/init-kmsg
LOG_ROOT_A=$TMP/init-log-a
LOG_ROOT_B=$TMP/init-log-b
BIRD_EARLY=$TMP/bird-early-mock
/bin/mkdir -p "$LOG_ROOT_A/MUOS/Bird/log"
cat >"$BIRD_EARLY" <<'EOF'
#!/bin/bash
printf 'bird-early:%s\n' "$1" >>"$INIT_EVENTS"
EOF
/bin/chmod 0755 "$BIRD_EARLY"
export INIT_EVENTS

hidecursor() { printf '%s\n' hidecursor >>"$INIT_EVENTS"; }
load_modules() { printf '%s\n' load_modules >>"$INIT_EVENTS"; }
mount_storage() {
	printf '%s\n' mount_storage >>"$INIT_EVENTS"
	return "$MOUNT_RESULT"
}
check_update() { printf '%s\n' check_update >>"$INIT_EVENTS"; }
prepare_sysroot() { printf '%s\n' prepare_sysroot >>"$INIT_EVENTS"; }
error() { printf 'error:%s:%s\n' "$1" "$2" >>"$INIT_EVENTS"; }
sleep() {
	printf 'fatal-sleep:%s\n' "$1" >>"$INIT_EVENTS"
	exit 73
}

: >"$INIT_EVENTS"
: >"$KMSG"
MOUNT_RESULT=1
set +e
(
	# shellcheck source=/dev/null
	. "$GENERATED_INIT"
)
STATUS=$?
set -e
[ "$STATUS" -eq 73 ]
cat >"$TMP/expected-init-failure" <<'EOF'
hidecursor
bird-early:start
load_modules
mount_storage
fatal-sleep:3600
EOF
cmp "$TMP/expected-init-failure" "$INIT_EVENTS"
grep -Fqx 'bird mount_storage failed closed' "$KMSG"
grep -Fqx 'status=failed step=mount_storage' \
	"$LOG_ROOT_A/MUOS/Bird/log/mount-storage-latest.log"
if grep -Eq 'check_update|prepare_sysroot|root-ready|handoff|stock' "$INIT_EVENTS"; then
	printf '%s\n' 'failed storage integration continued into later boot work' >&2
	exit 1
fi

# The same exact generated branch must remain transparent on success.
: >"$INIT_EVENTS"
: >"$KMSG"
/bin/rm -f "$LOG_ROOT_A/MUOS/Bird/log/mount-storage-latest.log"
MOUNT_RESULT=0
(
	# shellcheck source=/dev/null
	. "$GENERATED_INIT"
)
cat >"$TMP/expected-init-success" <<'EOF'
hidecursor
bird-early:start
load_modules
mount_storage
check_update
prepare_sysroot
bird-early:root-ready
bird-early:handoff
stock-handoff
EOF
cmp "$TMP/expected-init-success" "$INIT_EVENTS"
[ ! -s "$KMSG" ]
[ ! -e "$LOG_ROOT_A/MUOS/Bird/log/mount-storage-latest.log" ]

printf '%s\n' 'stock-root mount-storage topology tests: PASS'
