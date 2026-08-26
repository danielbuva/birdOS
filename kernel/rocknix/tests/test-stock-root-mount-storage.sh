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
SYSTEM_UNITS=$ROOT/kernel/work/rocknix-system-exact-20260701/usr/lib/systemd/system
JOURNAL_POLICY=$ROOT/kernel/rocknix/stock-root/bird-journald.conf
SYSTEM_MASK_POLICY=$ROOT/kernel/rocknix/hermetic-system-masks.tsv
SYSTEM_OVERRIDE_POLICY=$ROOT/kernel/rocknix/hermetic-system-overrides.tsv
SWAP_POLICY=$ROOT/kernel/rocknix/stock-root/bird-swap.conf
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-mount-storage.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

PREFIX_RAW=$TMP/mount-storage-prefix-raw.sh
PREFIX=$TMP/mount-storage-prefix.sh
awk '
	/^# The selected release is verified before \/flash\/bird is published/ { exit }
	{ print }
' "$MOUNT_STORAGE" >"$PREFIX_RAW"
sed \
	-e 's#^SUSPEND_CONFIG=.*#SUSPEND_CONFIG=$TEST_SUSPEND_CONFIG#' \
	-e 's#^SUSPEND_SLEEP_CONFIG=.*#SUSPEND_SLEEP_CONFIG=$TEST_SLEEP_CONFIG#' \
	-e 's#^FIXED_SLEEP_CONFIG=.*#FIXED_SLEEP_CONFIG=$TEST_FIXED_SLEEP_CONFIG#' \
	-e 's#^FIXED_SUSPEND_POLICY=.*#FIXED_SUSPEND_POLICY=$TEST_FIXED_SUSPEND_POLICY#' \
	-e 's#^SYSTEM_BUSYBOX=.*#SYSTEM_BUSYBOX=$TEST_SYSTEM_BUSYBOX#' \
	-e 's#^RETROARCH_CONFIG_DIR=.*#RETROARCH_CONFIG_DIR=$TEST_RETROARCH_CONFIG_DIR#' \
	-e 's#^FIXED_RETROARCH_CONFIG_DIR=.*#FIXED_RETROARCH_CONFIG_DIR=$TEST_FIXED_RETROARCH_CONFIG_DIR#' \
	-e 's#/birddata/Bird/namespace-v1.tsv#$TEST_NAMESPACE#g' \
	"$PREFIX_RAW" >"$PREFIX"

grep -q '^STORAGE_IMAGE=/birddata/MUOS/runtime/ROCKNIX-STORAGE$' "$PREFIX"
grep -q '^mount --move /birddata /run/bird-data || {$' "$PREFIX"
grep -q '^mount --bind /run/bird-data /storage/bird-data || {$' "$PREFIX"
if grep -Eq 'wc -l|grep -Fqx.*NAMESPACE_RECORD' "$PREFIX"; then
	printf '%s\n' 'namespace validation still launches external readers' >&2
	exit 1
fi
if grep -Eq 'exec [0-9]|<&[0-9]|[0-9]<&' "$PREFIX"; then
	printf '%s\n' 'sourced storage hook borrows a caller file descriptor' >&2
	exit 1
fi
grep -Fq 'done <"$NAMESPACE_RECORD"' "$PREFIX"
grep -Fqx 'Storage=volatile' "$JOURNAL_POLICY"
grep -Fqx 'Compress=no' "$JOURNAL_POLICY"
grep -Fqx 'RuntimeMaxUse=2M' "$JOURNAL_POLICY"
grep -Fqx 'ZRAM_SIZE="0"' "$SWAP_POLICY"
grep -Fqx 'SWAP_FILE_SIZE="0"' "$SWAP_POLICY"
grep -Fqx 'KSM_ENABLE="disable"' "$SWAP_POLICY"
if grep -Eq '^mount --move [^ ]+ /storage(/|[[:space:]])' "$PREFIX"; then
	printf '%s\n' 'real data mount is still moved beneath /storage' >&2
	exit 1
fi

# The pinned initramfs has no chmod applet. Only the mutable ROCKNIX memory
# policy still needs mode normalization through the pinned final-root BusyBox.
[ -f "$INIT_BUSYBOX" ]
if strings -a -n 2 "$INIT_BUSYBOX" | grep -Fqx chmod; then
	printf '%s\n' 'pinned initramfs unexpectedly gained chmod' >&2
	exit 1
fi
if grep -Eq '^[[:space:]]*chmod[[:space:]]' "$MOUNT_STORAGE"; then
	printf '%s\n' 'mount-storage still invokes unavailable chmod' >&2
	exit 1
fi
if grep -Fq '/sysroot/usr/bin/busybox chmod 0755' "$MOUNT_STORAGE"; then
	printf '%s\n' 'immutable executable chmod transaction remained' >&2
	exit 1
fi
grep -Fq '/sysroot/usr/bin/busybox chmod 0644' "$MOUNT_STORAGE"
grep -Fq 'cp -f /flash/bird/bird-swap.conf /storage/.config/swap.conf' \
	"$MOUNT_STORAGE"
if grep -Fq '"/storage/.config/bird/$FILE"' "$MOUNT_STORAGE"; then
	printf '%s\n' 'immutable final-root publication remained' >&2
	exit 1
fi
grep -Fq 'LAUNCHER=/flash/bird/bird-launcher' "$SUPERVISOR"
grep -Fq 'RUNNER=/flash/bird/run-content.sh' "$SUPERVISOR"
grep -Fq 'print "  if [ \"${BOOT_STEP}\" = \"mount_storage\" ]; then"' \
	"$EARLY_BUILDER"
grep -Fq 'mount-storage-latest.log' "$EARLY_BUILDER"
python3 - "$ROOT/kernel/rocknix/stock-root/bird-early.sh" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
watchdog = source.index('/bird-early.sh watchdog >/dev/null 2>&1 &')
launcher = source.index('"$LAUNCHER" >>"$LOG" 2>&1 &')
assert watchdog < launcher
assert 'storage-anchor-ready >"$WATCHDOG_DISARM"' in source
assert 'status=fatal reason=storage-readiness-timeout' in source
assert 'launcher_exit=detected' not in source
PY
if grep -Fq '/usr/lib/autostart' "$MOUNT_STORAGE"; then
	printf '%s\n' 'per-script autostart bind replacement remained' >&2
	exit 1
fi
if grep -Eq 'mount --bind .*/flash/bird/(rocknix-automount|rocknix-autostart|bird-fixed-controls|bird-powerstate|bird-save-config|NetworkManager|iwd|systemd-resolved|systemd-timesyncd|systemd-rfkill|rocknix-report-stats|bird-journald|essway|rocknix[.]target)' \
	"$MOUNT_STORAGE"; then
	printf '%s\n' 'fixed SYSTEM file replacement bind remained' >&2
	exit 1
fi
[ "$(grep -Fc 'mount --bind /dev/null' "$MOUNT_STORAGE")" -eq 1 ]
for DEFERRED_UNIT in hdmi-hotplug.path video.service sixaxis@.service \
	systemd-rfkill.socket; do
	grep -Fq "$DEFERRED_UNIT" "$MOUNT_STORAGE"
	if grep -Fq "$(printf 'mask\tusr/lib/systemd/system/%s' "$DEFERRED_UNIT")" \
		"$SYSTEM_MASK_POLICY"; then
		printf 'deferred hardware policy was baked: %s\n' "$DEFERRED_UNIT" >&2
		exit 1
	fi
done
[ "$(wc -l <"$SYSTEM_OVERRIDE_POLICY" | tr -d ' ')" -eq 14 ]
for OVERRIDE in \
	'rocknix-automount.service usr/lib/systemd/system/rocknix-automount.service' \
	'rocknix-autostart.service usr/lib/systemd/system/rocknix-autostart.service' \
	'bird-fixed-controls.service usr/lib/systemd/system/input.service' \
	'bird-powerstate.service usr/lib/systemd/system/powerstate.service' \
	'bird-save-config.service usr/lib/systemd/system/save-sysconfig.service' \
	'NetworkManager.service usr/lib/systemd/system/NetworkManager.service' \
	'iwd.service usr/lib/systemd/system/iwd.service' \
	'systemd-resolved.service usr/lib/systemd/system/systemd-resolved.service' \
	'systemd-timesyncd.service usr/lib/systemd/system/systemd-timesyncd.service' \
	'systemd-rfkill.service usr/lib/systemd/system/systemd-rfkill.service' \
	'rocknix-report-stats.service usr/lib/systemd/system/rocknix-report-stats.service' \
	'bird-journald.conf etc/systemd/journald.conf' \
	'essway.service usr/lib/systemd/system/essway.service' \
	'rocknix.target usr/lib/systemd/system/rocknix.target'; do
	set -- $OVERRIDE
	SOURCE_SHA=$(shasum -a 256 "$ROOT/kernel/rocknix/stock-root/$1" | awk '{print $1}')
	grep -Fqx "$(printf 'file\t%s\t%s\t0644\t%s' "$1" "$2" "$SOURCE_SHA")" \
		"$SYSTEM_OVERRIDE_POLICY"
done
for MASKED_UNIT in systemd-journal-flush.service \
	systemd-journal-catalog-update.service systemd-logind.service \
	systemd-tmpfiles-clean.timer systemd-update-utmp.service \
	systemd-update-utmp-runlevel.service; do
	grep -Fqx "$(printf 'mask\tusr/lib/systemd/system/%s' "$MASKED_UNIT")" \
		"$SYSTEM_MASK_POLICY"
done

# Every unit bind target must already exist in the immutable stock root. A bind
# mount cannot create a new pathname; missing this check strands Bird in the
# early launcher with no final-root controls or content runtime.
sed -n 's#^[[:space:]]*/sysroot/usr/lib/systemd/system/\([^[:space:]]*\).*#\1#p' \
	"$MOUNT_STORAGE" | while IFS= read -r UNIT; do
	[ -e "$SYSTEM_UNITS/$UNIT" ] || {
		printf 'missing stock unit bind target: %s\n' "$UNIT" >&2
		exit 1
	}
done

EVENTS=$TMP/events
FAIL_OPERATION=
TEST_SUSPEND_CONFIG=$TMP/storage/system.cfg
TEST_SLEEP_CONFIG=$TMP/storage/sleep.conf.d/sleep.conf
TEST_LOGIND_CONFIG=$TMP/storage/logind.conf.d/login.conf
TEST_FIXED_SLEEP_CONFIG=$ROOT/kernel/rocknix/stock-root/bird-sleep.conf
TEST_FIXED_SUSPEND_POLICY=$ROOT/kernel/rocknix/stock-root/bird-suspend-policy.generated.sh
TEST_RETROARCH_CONFIG_DIR=$TMP/storage/retroarch
TEST_FIXED_RETROARCH_CONFIG_DIR=$TMP/fixed-retroarch
TEST_SYSTEM_BUSYBOX=$TMP/system-busybox-policy
TEST_NAMESPACE=$TMP/namespace-v1.tsv
POLICY_EVENTS=$TMP/policy-events
/bin/mkdir -p "${TEST_SUSPEND_CONFIG%/*}" \
	"${TEST_SLEEP_CONFIG%/*}" "${TEST_LOGIND_CONFIG%/*}" \
	"$TEST_RETROARCH_CONFIG_DIR" "$TEST_FIXED_RETROARCH_CONFIG_DIR"
printf 'revision\tbird-canonical-namespace-v1\nstate\tcommitted\n' \
	>"$TEST_NAMESPACE"
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
	case "$*" in *"$TMP"*) /bin/mkdir "$@" ;; esac
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
FD3_SENTINEL=$TMP/upstream-fd3
exec 3>"$FD3_SENTINEL"
run_prefix
[ "$STATUS" -eq 0 ]
printf '%s\n' 'fd3-preserved' >&3
exec 3>&-
grep -Fxq 'fd3-preserved' "$FD3_SENTINEL"
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
[ "$(cat "$TEST_LOGIND_CONFIG")" = stale-logind ]
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
[ -e "${TEST_LOGIND_CONFIG%/*}/zz-override.conf" ]
[ -L "${TEST_LOGIND_CONFIG%/*}/zzz-symlink.conf" ]
[ "$(cat "$TMP/outside-policy-target")" = 'must remain' ]
cat >"$TMP/expected-success" <<'EOF'
loop|/birddata/MUOS/runtime/ROCKNIX-STORAGE|/storage|loop,rw,noatime
mkdir|-p /run/bird-data /storage/bird-data /storage/roms /storage/media
mount|--move /birddata /run/bird-data
mount|--bind /run/bird-data /storage/bird-data
mount|--bind /storage/bird-data/ROMS /storage/roms
mount|--bind /storage/bird-data/MEDIA /storage/media
EOF
cmp "$TMP/expected-success" "$EVENTS"

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
[ "$(/usr/bin/stat -f %Lp "$TEST_LOGIND_CONFIG" 2>/dev/null || /usr/bin/stat -c %a "$TEST_LOGIND_CONFIG")" = 600 ]
grep -q '^awk ' "$POLICY_EVENTS"
[ "$(grep -c '^chmod 0644 ' "$POLICY_EVENTS")" -eq 2 ]

# The accepted policy causes no configuration or file-copy write on the next
# boot; only the sleep-policy read-only comparison and mode read remain.
cp "$TEST_SUSPEND_CONFIG" "$TMP/system.cfg.accepted"
: >"$POLICY_EVENTS"
run_prefix
[ "$STATUS" -eq 0 ]
cmp "$TMP/system.cfg.accepted" "$TEST_SUSPEND_CONFIG"
[ "$(grep -c '^cmp -s ' "$POLICY_EVENTS")" -eq 1 ]
! grep -Eq '^(awk|cp|chmod|mv|rm) ' "$POLICY_EVENTS"

# Missing accepted-state directories retain the original repair behavior, but
# existing directories no longer launch two unconditional mkdir children.
/bin/mv "${TEST_SLEEP_CONFIG%/*}" "$TMP/sleep-policy.saved"
/bin/mv "$TEST_RETROARCH_CONFIG_DIR" "$TMP/retroarch.saved"
run_prefix
[ "$STATUS" -eq 0 ]
grep -Fxq "mkdir|-p ${TEST_SLEEP_CONFIG%/*}" "$EVENTS"
grep -Fxq "mkdir|-p $TEST_RETROARCH_CONFIG_DIR" "$EVENTS"
cmp "$TEST_FIXED_SLEEP_CONFIG" "$TEST_SLEEP_CONFIG"
cmp "$TEST_FIXED_RETROARCH_CONFIG_DIR/retroarch.cfg" \
	"$TEST_RETROARCH_CONFIG_DIR/retroarch.cfg"

# The built-in namespace reader remains strict: order, cardinality and both
# newline-terminated authority records are required before any mount move.
for BAD_NAMESPACE in reversed extra truncated; do
	case "$BAD_NAMESPACE" in
		reversed) printf 'state\tcommitted\nrevision\tbird-canonical-namespace-v1\n' >"$TEST_NAMESPACE" ;;
		extra) printf 'revision\tbird-canonical-namespace-v1\nstate\tcommitted\nextra\tbad\n' >"$TEST_NAMESPACE" ;;
		truncated) printf 'revision\tbird-canonical-namespace-v1\n' >"$TEST_NAMESPACE" ;;
	esac
	run_prefix
	[ "$STATUS" -eq 1 ]
	grep -Fq 'error|bird-namespace|' "$EVENTS"
	! grep -Fq 'mount|--move /birddata /run/bird-data' "$EVENTS"
done
printf 'revision\tbird-canonical-namespace-v1\nstate\tcommitted\n' >"$TEST_NAMESPACE"

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
mkdir|-p /run/bird-data /storage/bird-data /storage/roms /storage/media
mount|--move /birddata /run/bird-data
error|bird-data-move|Could not move large Bird data volume to its final mount
EOF
cmp "$TMP/expected-move-failure" "$EVENTS"

# A failed publication bind must stop with the real filesystem still at its
# safe /run mount, without attempting either nested library bind.
FAIL_OPERATION=data-bind
run_prefix
[ "$STATUS" -eq 1 ]
cat >"$TMP/expected-bind-failure" <<'EOF'
loop|/birddata/MUOS/runtime/ROCKNIX-STORAGE|/storage|loop,rw,noatime
mkdir|-p /run/bird-data /storage/bird-data /storage/roms /storage/media
mount|--move /birddata /run/bird-data
mount|--bind /run/bird-data /storage/bird-data
error|bird-data-bind|Could not publish the large Bird data volume
EOF
cmp "$TMP/expected-bind-failure" "$EVENTS"

# Execute the exact remaining mutable-policy publication block against a
# temporary ext4-like tree. Immutable programs and provider data must stay at
# their verified release paths and never appear in the writable destination.
COPY_BLOCK_RAW=$TMP/runtime-copy-raw.sh
COPY_BLOCK=$TMP/runtime-copy.sh
awk '
	/^# The selected release is verified before \/flash\/bird is published/ { copy=1 }
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
IMMUTABLE_FILES='bird-pidwait bird-fixed-controls bird-powerstate bird-fixed-control-exit.sh bird-save-config.sh prepare-ports.sh verify-portmaster-provider.sh portmaster-provider.manifest.tsv fixed-storage.sh capture-boot-state.sh capture-requested-diagnostics.sh capture-stage5-state.sh capture-stage5-window-counters.sh capture-stage5-window.sh bird-network.sh bird-suspend.sh bird-volume.sh bird-control-osd.sh bird-launcher run-content.sh supervisor.sh first-frame-prep.sh'
for FILE in $IMMUTABLE_FILES; do
	printf 'immutable fixture %s\n' "$FILE" >"$SOURCE_BIRD/$FILE"
done
printf '%s\n' 'fixture swap' >"$SOURCE_BIRD/bird-swap.conf"
/bin/chmod 0644 "$SOURCE_BIRD"/*
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
printf 'chmod 0644 %s\n' "$DEST_SWAP" >"$EXPECTED_MODE_EVENTS"
cmp "$EXPECTED_MODE_EVENTS" "$MODE_EVENTS"

file_mode() {
	stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}
for FILE in $IMMUTABLE_FILES; do
	[ ! -e "$DEST_BIRD/$FILE" ]
done
[ -r "$DEST_SWAP" ]
[ "$(file_mode "$DEST_SWAP")" = 644 ]
cmp "$SOURCE_BIRD/bird-swap.conf" "$DEST_SWAP"

# A failed final-root chmod must fail the mutable data transaction immediately.
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
/bin/mkdir -p "$LOG_ROOT_A/Bird/log"
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
bird-early:storage-failed
fatal-sleep:3600
EOF
cmp "$TMP/expected-init-failure" "$INIT_EVENTS"
grep -Fqx 'bird mount_storage failed closed' "$KMSG"
grep -Fqx 'status=failed step=mount_storage' \
	"$LOG_ROOT_A/Bird/log/mount-storage-latest.log"
if grep -Eq 'check_update|prepare_sysroot|root-ready|handoff|stock' "$INIT_EVENTS"; then
	printf '%s\n' 'failed storage integration continued into later boot work' >&2
	exit 1
fi

# The same exact generated branch must remain transparent on success.
: >"$INIT_EVENTS"
: >"$KMSG"
/bin/rm -f "$LOG_ROOT_A/Bird/log/mount-storage-latest.log"
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
[ ! -e "$LOG_ROOT_A/Bird/log/mount-storage-latest.log" ]

# Execute the real watchdog case with only fixed paths and BusyBox operations
# redirected into a private fixture. This proves the failure capture, healthy
# disarm and p1 fallback without addressing hardware or invoking real poweroff.
WATCHDOG_SCRIPT=$TMP/bird-early-watchdog.sh
WATCHDOG_RUN=$TMP/watchdog-run
WATCHDOG_DATA=$TMP/watchdog-data
WATCHDOG_FLASH=$TMP/watchdog-flash
WATCHDOG_LED=$TMP/watchdog-led
WATCHDOG_EARLY_LOG=$TMP/watchdog-early.log
WATCHDOG_EVENTS=$TMP/watchdog-events
WATCHDOG_BUSYBOX=$TMP/watchdog-busybox
sed \
	-e 's#^BUSYBOX=.*#BUSYBOX=$WATCHDOG_BUSYBOX#' \
	-e 's#^RUN=.*#RUN=$WATCHDOG_RUN#' \
	-e 's#^LOG=.*#LOG=$WATCHDOG_EARLY_LOG#' \
	-e 's#^WATCHDOG_SECONDS=.*#WATCHDOG_SECONDS=0#' \
	-e 's#^WATCHDOG_PERSIST_DELAY=.*#WATCHDOG_PERSIST_DELAY=0#' \
	-e 's#/sysroot/storage/bird-data#$WATCHDOG_DATA#g' \
	-e 's#/storage/bird-data#$WATCHDOG_DATA#g' \
	-e 's#/run/bird-data#$WATCHDOG_DATA#g' \
	-e 's#/birddata#$WATCHDOG_DATA#g' \
	-e 's#/flash#$WATCHDOG_FLASH#g' \
	-e 's#/sys/class/leds/red:status/brightness#$WATCHDOG_LED#g' \
	"$ROOT/kernel/rocknix/stock-root/bird-early.sh" >"$WATCHDOG_SCRIPT"
cat >"$WATCHDOG_BUSYBOX" <<'EOF'
#!/bin/sh
COMMAND=$1
shift
case "$COMMAND" in
	cat) exec /bin/cat "$@" ;;
	head) exec /usr/bin/head "$@" ;;
	ls) exec /bin/ls "$@" ;;
	rm) exec /bin/rm "$@" ;;
	dmesg) printf '%s\n' 'mock kernel storage failure' ;;
	mount) printf 'mount:%s\n' "$*" >>"$WATCHDOG_EVENTS" ;;
	poweroff) printf 'poweroff:%s\n' "$*" >>"$WATCHDOG_EVENTS" ;;
	sleep|sync) : ;;
	*) printf 'unexpected busybox command: %s\n' "$COMMAND" >&2; exit 91 ;;
esac
EOF
/bin/chmod 0755 "$WATCHDOG_SCRIPT" "$WATCHDOG_BUSYBOX"
export WATCHDOG_RUN WATCHDOG_DATA WATCHDOG_FLASH WATCHDOG_LED \
	WATCHDOG_EARLY_LOG WATCHDOG_EVENTS WATCHDOG_BUSYBOX
/bin/mkdir -p "$WATCHDOG_RUN" "$WATCHDOG_DATA/Bird/log" "$WATCHDOG_FLASH"
printf '%s\n' 'mock early launcher failure' >"$WATCHDOG_EARLY_LOG"
: >"$WATCHDOG_EVENTS"
"$WATCHDOG_SCRIPT" watchdog
WATCHDOG_LOG=$(find "$WATCHDOG_DATA/Bird/log" -type f \
	-name 'boot-watchdog-*.log' -print)
[ "$(printf '%s\n' "$WATCHDOG_LOG" | wc -l | tr -d ' ')" -eq 1 ]
grep -Fqx 'schema=bird-early-storage-watchdog-v1' "$WATCHDOG_LOG"
grep -Fqx 'status=fatal reason=storage-readiness-timeout' "$WATCHDOG_LOG"
grep -Fqx 'section=mounts' "$WATCHDOG_LOG"
grep -Fqx 'section=mount-storage' "$WATCHDOG_LOG"
grep -Fqx 'section=kernel' "$WATCHDOG_LOG"
grep -Fqx 'mock kernel storage failure' "$WATCHDOG_LOG"
grep -Fqx 'poweroff:-f' "$WATCHDOG_EVENTS"

/bin/rm -rf "$WATCHDOG_DATA"
/bin/mkdir -p "$WATCHDOG_DATA/Bird/log"
printf '%s\n' storage-anchor-ready >"$WATCHDOG_RUN/boot-watchdog-disarmed"
: >"$WATCHDOG_EVENTS"
"$WATCHDOG_SCRIPT" watchdog
[ ! -s "$WATCHDOG_EVENTS" ]
if find "$WATCHDOG_DATA/Bird/log" -type f -print | grep -q .; then
	printf '%s\n' 'healthy watchdog left a persistent record' >&2
	exit 1
fi

/bin/rm -rf "$WATCHDOG_DATA"
/bin/rm -f "$WATCHDOG_RUN/boot-watchdog-disarmed"
: >"$WATCHDOG_EVENTS"
"$WATCHDOG_SCRIPT" watchdog
grep -Fqx 'schema=bird-early-storage-watchdog-v1' \
	"$WATCHDOG_FLASH/bird-watchdog-failure.txt"
grep -Fqx 'status=fatal reason=storage-readiness-timeout' \
	"$WATCHDOG_FLASH/bird-watchdog-failure.txt"
grep -Fqx 'section=kernel' "$WATCHDOG_FLASH/bird-watchdog-failure.txt"
grep -Fqx 'poweroff:-f' "$WATCHDOG_EVENTS"

printf '%s\n' 'stock-root mount-storage topology tests: PASS'
