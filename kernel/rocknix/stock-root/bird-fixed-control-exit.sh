#!/bin/sh
# End only Bird's current foreground application. ROCKNIX's provider-owned
# name list remains the graceful first path; the managed process tree covers
# wrappers such as OpenBOR that do not publish a name there. The Bird launcher,
# supervisor and global-control process are never descendants of this root.

KILL_DATA=/tmp/.process-kill-data
SESSION_PID=/run/bird/content-session.pid
LOG=/storage/bird-data/MUOS/Bird/log/content-exit-latest.log

mkdir -p "${LOG%/*}"
: >"$LOG"
PROVIDER=0

printf 'Bird foreground exit request uptime=' >>"$LOG"
cut -d ' ' -f 1 /proc/uptime >>"$LOG"

if [ -s "$KILL_DATA" ]; then
	IFS= read -r TO_KILL <"$KILL_DATA"
	if [ -n "$TO_KILL" ]; then
		# Intentional word splitting preserves entries such as
		# "-9 retroarch retroarch32" from ROCKNIX's set_kill helper.
		# shellcheck disable=SC2086
		/usr/bin/killall $TO_KILL 2>/dev/null || :
		PROVIDER=1
		printf 'provider=%s\n' "$TO_KILL" >>"$LOG"
	fi
fi

[ -s "$SESSION_PID" ] || {
	printf '%s\n' 'managed_root=none' >>"$LOG"
	exit 0
}

IFS= read -r ROOT_PID <"$SESSION_PID"
case "$ROOT_PID" in
	''|*[!0-9]*) printf '%s\n' 'managed_root=invalid' >>"$LOG"; exit 0 ;;
esac
[ -d "/proc/$ROOT_PID" ] || {
	printf 'managed_root=%s state=gone\n' "$ROOT_PID" >>"$LOG"
	exit 0
}

TARGETS=
collect_tree() {
	PARENT=$1
	for CHILD in $(/usr/bin/pgrep -P "$PARENT" 2>/dev/null); do
		collect_tree "$CHILD"
	done
	TARGETS="$TARGETS $PARENT"
}

CHILDREN=$(/usr/bin/pgrep -P "$ROOT_PID" 2>/dev/null || :)
if [ -n "$CHILDREN" ]; then
	for CHILD in $CHILDREN; do
		collect_tree "$CHILD"
	done
	printf 'managed_root=%s action=children-term\n' "$ROOT_PID" >>"$LOG"
else
	[ "$PROVIDER" -eq 0 ] || exit 0
	# A wrapper may have exec'd its payload in place. In that case its managed
	# root is itself the foreground application.
	TARGETS=$ROOT_PID
	printf 'managed_root=%s action=root-term\n' "$ROOT_PID" >>"$LOG"
fi

for TARGET in $TARGETS; do
	kill -TERM "$TARGET" 2>/dev/null || :
done

for _ in 1 2 3 4 5 6 7 8 9 10; do
	SURVIVORS=
	for TARGET in $TARGETS; do
		kill -0 "$TARGET" 2>/dev/null && SURVIVORS="$SURVIVORS $TARGET"
	done
	[ -n "$SURVIVORS" ] || exit 0
	usleep 20000
done

# A provider that ignores TERM must not strand the user inside content, even
# if its wrapper exited and the payload was reparented during the grace period.
for TARGET in $SURVIVORS; do
	kill -KILL "$TARGET" 2>/dev/null || :
done
printf 'managed_root=%s action=survivors-kill pids=%s\n' \
	"$ROOT_PID" "$SURVIVORS" >>"$LOG"
