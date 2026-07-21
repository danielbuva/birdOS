#!/bin/sh
# DANI_FIXED_DIAGNOSTICS_COLLECTOR_V3

BOOT_TMP="/tmp/muos/boot-timing.tsv"
BOOT_DIR="/mnt/mmc/MUOS/log/boot"
STARTUP_TRACE="/tmp/muos/fixed-startup.tsv"
STARTUP_RESULTS="/mnt/mmc/MUOS/boot-timing/fixed-startup/results"
UDEV_TRACE="/tmp/muos/minimal-udev.tsv"
UDEV_RESULTS="/mnt/mmc/MUOS/boot-timing/udev-minimal/results"

BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
[ -n "$BOOT_ID" ] || BOOT_ID=unknown

if [ -f "$BOOT_TMP" ]; then
	read -r NOW _ </proc/uptime
	printf '%s\t%s\tmilestone\tuser\tuser_init_hook\t0\n' \
		"$BOOT_ID" "$NOW" >>"$BOOT_TMP"
	[ ! -e /run/muos/dani-root-init-active ] ||
		printf '%s\t%s\tmilestone\tinit\tstatic_pid1_active\t0\n' \
			"$BOOT_ID" "$NOW" >>"$BOOT_TMP"
	[ ! -e /run/muos/dani-trimmed-initramfs-v1 ] ||
		printf '%s\t%s\tmilestone\tinit\ttrimmed_initramfs_active\t0\n' \
			"$BOOT_ID" "$NOW" >>"$BOOT_TMP"
	[ ! -e /run/muos/dani-direct-handoff-v1 ] ||
		printf '%s\t%s\tmilestone\tinit\tdirect_handoff_active\t0\n' \
			"$BOOT_ID" "$NOW" >>"$BOOT_TMP"
	[ ! -e /run/muos/dani-fsck-clean-skip ] ||
		printf '%s\t%s\tmilestone\tinit\tfsck_clean_skip\t0\n' \
			"$BOOT_ID" "$NOW" >>"$BOOT_TMP"
	mkdir -p "$BOOT_DIR"
	cp -f "$BOOT_TMP" "$BOOT_DIR/boot-timing-$BOOT_ID.tsv"
	cp -f "$BOOT_TMP" "$BOOT_DIR/boot-timing-latest.tsv"
fi

# startup.sh launches user init immediately before its final trace entry.  Join
# that sub-millisecond race without adding a persistent observer or long timer.
COUNT=0
while [ -f "$STARTUP_TRACE" ] &&
	! grep -q 'startup-complete' "$STARTUP_TRACE" && [ "$COUNT" -lt 50 ]; do
	COUNT=$((COUNT + 1))
	sleep 0.01
done

if [ -f "$STARTUP_TRACE" ]; then
	mkdir -p "$STARTUP_RESULTS"
	cp -f "$STARTUP_TRACE" "$STARTUP_RESULTS/$BOOT_ID.tsv"
	cp -f "$STARTUP_TRACE" "$STARTUP_RESULTS/latest.tsv"
fi

if [ -f "$UDEV_TRACE" ]; then
	mkdir -p "$UDEV_RESULTS"
	cp -f "$UDEV_TRACE" "$UDEV_RESULTS/$BOOT_ID.tsv"
	cp -f "$UDEV_TRACE" "$UDEV_RESULTS/latest.tsv"
fi
