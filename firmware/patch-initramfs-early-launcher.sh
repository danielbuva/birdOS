#!/bin/sh
set -eu

TARGET=${1:-}
MARKER="DANI_INITRAMFS_LAUNCHER_V1"

[ -n "$TARGET" ] && [ -f "$TARGET" ] || {
	printf 'usage: %s INITRAMFS_INIT\n' "$0" >&2
	exit 1
}

grep -q "$MARKER" "$TARGET" && exit 0

PATCHED="$TARGET.dani-new.$$"
CLEANUP() {
	rm -f "$PATCHED"
}
trap CLEANUP 0 1 2 15

MATCHES=0
while IFS= read -r LINE; do
	if [ "$LINE" = '[ -x /mnt/init ] && mount -o noatime,move /dev /mnt/dev && exec switch_root /mnt /init' ]; then
		printf '%s\n' '# DANI_INITRAMFS_LAUNCHER_V1'
		printf '%s\n' 'if [ -x /mnt/init ]; then'
		printf '\t%s\n' 'mkdir -p /mnt/dev /mnt/proc /mnt/sys /mnt/run /mnt/tmp /mnt/opt/muos/bin'
		printf '\t%s\n' 'mount -o noatime,move /dev /mnt/dev'
		printf '\t%s\n' 'mount -o move /proc /mnt/proc'
		printf '\t%s\n' 'mount -o move /sys /mnt/sys'
		printf '\t%s\n' 'mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /mnt/run'
		printf '\t%s\n' 'mount -t tmpfs -o mode=1777 tmpfs /mnt/tmp'
		printf '\t%s\n' 'mkdir -p /mnt/run/muos'
		printf '\t%s\n' 'if [ -x /opt/dani-launcher ] && [ -x /mnt/opt/muos/script/init/S03danilauncher ]; then'
		printf '\t\t%s\n' '[ -e /mnt/opt/muos/bin/dani-launcher ] || : >/mnt/opt/muos/bin/dani-launcher'
		printf '\t\t%s\n' 'if mount -o bind /opt/dani-launcher /mnt/opt/muos/bin/dani-launcher; then'
		printf '\t\t\t%s\n' '/usr/sbin/chroot /mnt /opt/muos/script/init/S03danilauncher start || true'
		printf '\t\t\t%s\n' 'COUNT=0'
		printf '\t\t\t%s\n' 'while [ ! -e /mnt/run/muos/dani-first-frame-ready ]; do'
		printf '\t\t\t\t%s\n' 'COUNT=`expr "$COUNT" + 1`'
		printf '\t\t\t\t%s\n' '[ "$COUNT" -ge 500 ] && break'
		printf '\t\t\t\t%s\n' 'sleep 0.001'
		printf '\t\t\t%s\n' 'done'
		printf '\t\t%s\n' 'fi'
		printf '\t%s\n' 'fi'
		printf '\t%s\n' 'exec switch_root /mnt /init'
		printf '%s\n' 'fi'
		MATCHES=$((MATCHES + 1))
	else
		printf '%s\n' "$LINE"
	fi
done <"$TARGET" >"$PATCHED"

if [ "$MATCHES" -ne 1 ] || ! grep -q "$MARKER" "$PATCHED" ||
	! sh -n "$PATCHED"; then
	printf 'error: exact stock switch_root line was not patched\n' >&2
	exit 1
fi

chmod 755 "$PATCHED"
mv -f "$PATCHED" "$TARGET"
trap - 0 1 2 15
