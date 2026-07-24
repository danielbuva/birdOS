#!/bin/sh
# BIRD_RG34XXSP_ONE_SHOT_BOOT_STATE_V1
#
# Capture the exact live FAT boot-resource and U-Boot environment partitions.
# This script is deliberately read-only with respect to both raw partitions.

set -eu

SELF=$0
ROM_MOUNT=/mnt/mmc
RESULT="$ROM_MOUNT/.firmware-work/one-shot-boot"
ORACLE="$RESULT/stock-oracle"
BOOT_RESOURCE_DEVICE=/dev/mmcblk0p2
ENV_DEVICE=/dev/mmcblk0p3
BOOT_RESOURCE_BYTES=33554432
ENV_BYTES=16777216
LOG_FILE="$ROM_MOUNT/MUOS/log/one-shot-boot-state-capture.log"

mkdir -p "$RESULT" "$ORACLE" "${LOG_FILE%/*}"
: >"$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

uptime_ms() {
	awk '{printf "%d", $1 * 1000}' /proc/uptime
}

log() {
	printf '[%s ms] %s\n' "$(uptime_ms)" "$*"
}

fail() {
	log "FAILED: $*"
	exit 1
}

ORIGINAL_KPTR=
restore_kptr() {
	[ -n "$ORIGINAL_KPTR" ] || return 0
	printf '%s\n' "$ORIGINAL_KPTR" >/proc/sys/kernel/kptr_restrict 2>/dev/null || :
	ORIGINAL_KPTR=
}
trap restore_kptr EXIT HUP INT TERM

capture_readable() {
	SOURCE=$1
	OUTPUT=$2
	if [ -r "$SOURCE" ]; then
		cp -f "$SOURCE" "$OUTPUT"
	else
		printf 'unavailable: %s\n' "$SOURCE" >"$OUTPUT.unavailable"
	fi
}

capture_partition() {
	DEVICE=$1
	BYTES=$2
	OUTPUT=$3
	TEMP="$OUTPUT.tmp"

	[ -b "$DEVICE" ] || fail "partition missing: $DEVICE"
	rm -f "$TEMP"
	dd if="$DEVICE" of="$TEMP" bs=1048576 count=$((BYTES / 1048576))
	sync
	[ "$(wc -c <"$TEMP" | tr -d ' ')" -eq "$BYTES" ] || \
		fail "short capture from $DEVICE"
	mv -f "$TEMP" "$OUTPUT"
	sha256sum "$OUTPUT"
}

log 'exact boot-state capture start (raw devices are read only)'
capture_partition "$BOOT_RESOURCE_DEVICE" "$BOOT_RESOURCE_BYTES" \
	"$RESULT/active-boot-resource.img"
capture_partition "$ENV_DEVICE" "$ENV_BYTES" "$RESULT/active-env.img"

log 'capturing accepted-kernel symbol and hardware oracle'
capture_readable /proc/config.gz "$ORACLE/config.gz"
capture_readable /proc/cmdline "$ORACLE/cmdline.txt"
capture_readable /proc/version "$ORACLE/version.txt"
capture_readable /proc/modules "$ORACLE/modules.txt"
capture_readable /proc/iomem "$ORACLE/iomem.txt"
capture_readable /proc/interrupts "$ORACLE/interrupts.txt"
capture_readable /sys/firmware/fdt "$ORACLE/running.dtb"
uname -a >"$ORACLE/uname.txt" 2>&1 || :
dmesg >"$ORACLE/dmesg.txt" 2>&1 || :
(
	for REGULATOR in /sys/class/regulator/regulator.*; do
		[ -d "$REGULATOR" ] || continue
		NAME=$(cat "$REGULATOR/name" 2>/dev/null || :)
		MICROVOLTS=$(cat "$REGULATOR/microvolts" 2>/dev/null || :)
		printf '%s\t%s\t%s\n' "${REGULATOR##*/}" "$NAME" "$MICROVOLTS"
	done
) >"$ORACLE/regulators.tsv"
find /lib/modules -type f -name '*.ko' -exec sha256sum {} \; \
	>"$ORACLE/module-files.sha256" 2>&1 || :

if [ -r /proc/sys/kernel/kptr_restrict ]; then
	ORIGINAL_KPTR=$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null)
	printf '%s\n' "$ORIGINAL_KPTR" >"$ORACLE/kptr-restrict-original.txt"
	if [ -w /proc/sys/kernel/kptr_restrict ]; then
		printf '0\n' >/proc/sys/kernel/kptr_restrict 2>/dev/null || :
	fi
fi
capture_readable /proc/kallsyms "$ORACLE/kallsyms.txt"
restore_kptr
if [ -f "$ORACLE/kallsyms.txt" ]; then
	if awk '$1 !~ /^0+$/ { found=1; exit } END { exit !found }' \
		"$ORACLE/kallsyms.txt"; then
		printf 'addresses-visible\n' >"$ORACLE/kallsyms-status.txt"
	else
		printf 'addresses-masked\n' >"$ORACLE/kallsyms-status.txt"
	fi
fi

(
	cd "$RESULT"
	sha256sum active-boot-resource.img active-env.img >sha256sums.txt
	find stock-oracle -type f -exec sha256sum {} \; | sort \
		>stock-oracle.sha256sums.txt
)
sync

case "$SELF" in
*.done) ;;
*) mv -f "$SELF" "$SELF.done" ;;
esac

log 'SUCCESS: exact boot state and accepted-kernel oracle captured'
exit 0
