#!/bin/bash
# Host-only behavioral coverage for the fixed final-root storage repair path.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SOURCE=$ROOT/kernel/rocknix/stock-root/fixed-storage.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-storage.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

bash -n "$SOURCE"
grep -Fqx 'ROM_SOURCE=/storage/bird-data/ROMS' "$SOURCE"
grep -Fqx 'MEDIA_SOURCE=/storage/bird-data/MEDIA' "$SOURCE"
grep -Fqx 'ROM_TARGET=/storage/roms' "$SOURCE"
grep -Fqx 'MEDIA_TARGET=/storage/media' "$SOURCE"
grep -Fq 'mount --bind "$ROM_SOURCE" "$ROM_TARGET" || exit 1' "$SOURCE"
grep -Fq 'mount -o remount,bind,rw,exec "$ROM_TARGET" || exit 1' "$SOURCE"
grep -Fq 'mount --bind "$MEDIA_SOURCE" "$MEDIA_TARGET" || exit 1' "$SOURCE"
grep -Fq 'rom_mount_is_rw_exec || exit 1' "$SOURCE"
if grep -Eq '^[[:space:]]*(cut|grep)[[:space:]]' "$SOURCE"; then
	printf '%s\n' 'fixed storage regained a diagnostic cut/grep child' >&2
	exit 1
fi
if grep -Eq 'lsblk|blkid|findmnt|/dev/(sd|mmc|nvme)' "$SOURCE"; then
	printf '%s\n' 'fixed storage regained generic block-device discovery' >&2
	exit 1
fi

write_stub_commands() {
	local CASE_DIR=$1
	mkdir -p "$CASE_DIR/bin"
	cat >"$CASE_DIR/bin/mount" <<'EOF'
#!/bin/bash
set -eu
printf 'mount' >>"$FIXED_COMMANDS"
printf '|%s' "$@" >>"$FIXED_COMMANDS"
printf '\n' >>"$FIXED_COMMANDS"

write_mounts() {
	printf '/dev/fake %s exfat rw,noatime 0 0\n' "$FIXED_BIRD_DATA"
	printf '/dev/fake %s exfat rw,noatime 0 0\n' "$FIXED_ROM_TARGET"
	printf '/dev/fake %s exfat rw,noatime 0 0\n' "$FIXED_MEDIA_TARGET"
}

[ "${FIXED_MOUNT_FAIL:-0}" -eq 0 ] || exit 1
if [ "$1" = --bind ] && [ "$2" = "$FIXED_ROM_SOURCE" ] && \
	[ "$3" = "$FIXED_ROM_TARGET" ]; then
	rm -rf "$FIXED_ROM_TARGET"
	ln -s "$FIXED_ROM_SOURCE" "$FIXED_ROM_TARGET"
	write_mounts >"$FIXED_MOUNTS"
	exit 0
fi
if [ "$1" = -o ] && [ "$2" = remount,bind,rw,exec ] && \
	[ "$3" = "$FIXED_ROM_TARGET" ]; then
	write_mounts >"$FIXED_MOUNTS"
	exit 0
fi
exit 2
EOF
	cat >"$CASE_DIR/bin/umount" <<'EOF'
#!/bin/bash
set -eu
printf 'umount' >>"$FIXED_COMMANDS"
printf '|%s' "$@" >>"$FIXED_COMMANDS"
printf '\n' >>"$FIXED_COMMANDS"
[ "$1" = "$FIXED_ROM_TARGET" ] || exit 2
[ "${FIXED_UMOUNT_MODE:-fail}" = peel ] || exit 1
rm -f "$FIXED_ROM_TARGET"
ln -s "$FIXED_ROM_SOURCE" "$FIXED_ROM_TARGET"
printf '/dev/fake %s exfat rw,noatime 0 0\n' "$FIXED_BIRD_DATA" >"$FIXED_MOUNTS"
printf '/dev/fake %s exfat rw,noatime 0 0\n' "$FIXED_ROM_TARGET" >>"$FIXED_MOUNTS"
printf '/dev/fake %s exfat rw,noatime 0 0\n' "$FIXED_MEDIA_TARGET" >>"$FIXED_MOUNTS"
EOF
	cat >"$CASE_DIR/bin/cut" <<'EOF'
#!/bin/sh
printf '%s\n' cut >>"$FIXED_COMMANDS"
exit 97
EOF
	cat >"$CASE_DIR/bin/grep" <<'EOF'
#!/bin/sh
printf '%s\n' grep >>"$FIXED_COMMANDS"
exit 98
EOF
	chmod 0755 "$CASE_DIR/bin/mount" "$CASE_DIR/bin/umount" \
		"$CASE_DIR/bin/cut" "$CASE_DIR/bin/grep"
}

setup_case() {
	local NAME=$1 OPTIONS=$2 TARGET_KIND=$3
	CASE_DIR=$TMP/$NAME
	BIRD_DATA=$CASE_DIR/bird-data
	ROM_SOURCE=$BIRD_DATA/ROMS
	MEDIA_SOURCE=$BIRD_DATA/MEDIA
	ROM_TARGET=$CASE_DIR/roms
	MEDIA_TARGET=$CASE_DIR/media
	MOUNTS=$CASE_DIR/mounts
	UPTIME=$CASE_DIR/uptime
	COMMANDS=$CASE_DIR/commands
	UNDER_TEST=$CASE_DIR/fixed-storage.sh
	mkdir -p "$ROM_SOURCE/ports/PortMaster" "$MEDIA_SOURCE" \
		"$CASE_DIR/run"
	ln -s "$MEDIA_SOURCE" "$MEDIA_TARGET"
	case "$TARGET_KIND" in
		correct) ln -s "$ROM_SOURCE" "$ROM_TARGET" ;;
		wrong)
			mkdir -p "$CASE_DIR/wrong-roms"
			ln -s "$CASE_DIR/wrong-roms" "$ROM_TARGET"
			;;
		unbound) mkdir -p "$ROM_TARGET" ;;
		*) exit 2 ;;
	esac
	printf '/dev/fake %s exfat rw,noatime 0 0\n' "$BIRD_DATA" >"$MOUNTS"
	printf '/dev/fake %s exfat %s 0 0\n' "$ROM_TARGET" "$OPTIONS" >>"$MOUNTS"
	printf '/dev/fake %s exfat rw,noatime 0 0\n' "$MEDIA_TARGET" >>"$MOUNTS"
	printf '12.340000 1.000000\n' >"$UPTIME"
	: >"$COMMANDS"
	sed \
		-e "s#/storage/bird-data#$BIRD_DATA#g" \
		-e "s#/storage/roms#$ROM_TARGET#g" \
		-e "s#/storage/media#$MEDIA_TARGET#g" \
		-e "s#/run/bird#$CASE_DIR/run/bird#g" \
		-e "s#/proc/mounts#$MOUNTS#g" \
		-e "s#/proc/uptime#$UPTIME#g" \
		"$SOURCE" >"$UNDER_TEST"
	chmod 0755 "$UNDER_TEST"
	write_stub_commands "$CASE_DIR"
	export CASE_DIR BIRD_DATA ROM_SOURCE MEDIA_SOURCE ROM_TARGET MEDIA_TARGET
	export MOUNTS UPTIME COMMANDS UNDER_TEST
	export FIXED_BIRD_DATA=$BIRD_DATA
	export FIXED_ROM_SOURCE=$ROM_SOURCE FIXED_ROM_TARGET=$ROM_TARGET
	export FIXED_MEDIA_TARGET=$MEDIA_TARGET FIXED_MOUNTS=$MOUNTS
	export FIXED_COMMANDS=$COMMANDS
}

run_case() {
	PATH="$CASE_DIR/bin:/usr/bin:/bin" "$UNDER_TEST"
}

# The accepted boot state performs no mount, unmount, cut or grep command.
setup_case accepted 'rw,noatime' correct
printf '#!/bin/sh\nexit 0\n' >"$ROM_SOURCE/ports/PortMaster/provider-test.sh"
chmod 0755 "$ROM_SOURCE/ports/PortMaster/provider-test.sh"
run_case
[ ! -s "$COMMANDS" ]
"$ROM_TARGET/ports/PortMaster/provider-test.sh"
LOG=$BIRD_DATA/Bird/log/fixed-storage-latest.log
grep -Fq 'Bird fixed storage start uptime=12.340000' "$LOG"
grep -Fq " $ROM_TARGET " "$LOG"
grep -Fq 'Bird fixed storage ready uptime=12.340000' "$LOG"

# A correct source carrying noexec is repaired exactly once, then revalidated.
setup_case noexec 'rw,noexec,noatime' correct
run_case
printf 'mount|-o|remount,bind,rw,exec|%s\n' "$ROM_TARGET" >"$CASE_DIR/expected"
cmp "$CASE_DIR/expected" "$COMMANDS"
grep -Fq " $ROM_TARGET exfat rw,noatime " "$MOUNTS"

# A read-only bind receives the same one-shot rw+exec repair.
setup_case readonly 'ro,noatime' correct
run_case
printf 'mount|-o|remount,bind,rw,exec|%s\n' "$ROM_TARGET" >"$CASE_DIR/expected"
cmp "$CASE_DIR/expected" "$COMMANDS"

# A wrong stacked layer is peeled; a correct underlying bind needs no remount.
setup_case stacked 'rw,noexec' wrong
FIXED_UMOUNT_MODE=peel run_case
printf 'umount|%s\n' "$ROM_TARGET" >"$CASE_DIR/expected"
cmp "$CASE_DIR/expected" "$COMMANDS"
[ "$ROM_TARGET" -ef "$ROM_SOURCE" ]

# With no layer to peel, publish the fixed source and keep its exec capability.
setup_case unbound 'rw,noatime' unbound
FIXED_UMOUNT_MODE=fail run_case
printf 'umount|%s\nmount|--bind|%s|%s\n' \
	"$ROM_TARGET" "$ROM_SOURCE" "$ROM_TARGET" >"$CASE_DIR/expected"
cmp "$CASE_DIR/expected" "$COMMANDS"
[ "$ROM_TARGET" -ef "$ROM_SOURCE" ]

# A failed corrective remount remains a hard service error.
setup_case repair-failure 'rw,noexec' correct
set +e
FIXED_MOUNT_FAIL=1 run_case
STATUS=$?
set -e
[ "$STATUS" -eq 1 ]
printf 'mount|-o|remount,bind,rw,exec|%s\n' "$ROM_TARGET" >"$CASE_DIR/expected"
cmp "$CASE_DIR/expected" "$COMMANDS"

# Missing fixed content remains a hard error before any namespace mutation.
setup_case missing-source 'rw,noatime' correct
rm -f "$ROM_TARGET"
rm -rf "$ROM_SOURCE"
set +e
run_case
STATUS=$?
set -e
[ "$STATUS" -eq 1 ]
[ ! -s "$COMMANDS" ]
grep -Fq 'Missing fixed ROM source:' \
	"$BIRD_DATA/Bird/log/fixed-storage-latest.log"

printf '%s\n' 'stock-root fixed-storage tests: PASS'
