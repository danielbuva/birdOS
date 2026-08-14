#!/bin/sh
# Emit the optional U-Boot bootstage FDT handoff as a small, stable record.
# This helper is called only by the explicitly requested post-frame snapshot;
# it must never be placed on the launcher or first-frame readiness path.
# Why before: five milestones bounded U-Boot generally, but merged kernel-load
# work into the long bootm-to-handoff interval. Why change: bootm_load_os is an
# existing exact mark which separates image loading from the later handoff.

set -u

BOOTSTAGE_ROOT=${BIRD_BOOTSTAGE_ROOT:-/sys/firmware/devicetree/base/bootstage}

[ -d "$BOOTSTAGE_ROOT" ] || exit 0

printf '%s\n' 'bird_uboot_bootstage_version=1'
printf 'bird_uboot_bootstage_columns=index\tkind\tvalue_us\tname\n'

INDICES=$(
	for ENTRY in "$BOOTSTAGE_ROOT"/*; do
		[ -d "$ENTRY" ] || continue
		printf '%s\n' "${ENTRY##*/}"
	done | LC_ALL=C grep '^[0-9][0-9]*$' | LC_ALL=C sort -n
)

RECORDS=0
INVALID=0
BOARD_INIT_F_COUNT=0
BOARD_INIT_F_MARKS=0
BOARD_INIT_F_US=0
BOARD_INIT_R_COUNT=0
BOARD_INIT_R_MARKS=0
BOARD_INIT_R_US=0
MAIN_LOOP_COUNT=0
MAIN_LOOP_MARKS=0
MAIN_LOOP_US=0
BOOTM_START_COUNT=0
BOOTM_START_MARKS=0
BOOTM_START_US=0
BOOTM_LOAD_OS_COUNT=0
BOOTM_LOAD_OS_MARKS=0
BOOTM_LOAD_OS_US=0
START_KERNEL_COUNT=0
START_KERNEL_MARKS=0
START_KERNEL_US=0
for INDEX in $INDICES; do
	ENTRY=$BOOTSTAGE_ROOT/$INDEX
	HAS_MARK=0
	HAS_ACCUM=0
	[ -f "$ENTRY/mark" ] && HAS_MARK=1
	[ -f "$ENTRY/accum" ] && HAS_ACCUM=1
	if [ $((HAS_MARK + HAS_ACCUM)) -ne 1 ]; then
		printf 'bird_uboot_bootstage_invalid_index=%s reason=property-count\n' \
			"$INDEX"
		INVALID=$((INVALID + 1))
		continue
	fi
	if [ "$HAS_MARK" -eq 1 ]; then
		KIND=mark
	else
		KIND=accum
	fi
	PROPERTY=$ENTRY/$KIND
	PROPERTY_BYTES=$(LC_ALL=C wc -c <"$PROPERTY")
	if [ "$PROPERTY_BYTES" -ne 4 ]; then
		printf 'bird_uboot_bootstage_invalid_index=%s reason=property-size bytes=%s\n' \
			"$INDEX" "$PROPERTY_BYTES"
		INVALID=$((INVALID + 1))
		continue
	fi
	if [ ! -r "$ENTRY/name" ]; then
		printf 'bird_uboot_bootstage_invalid_index=%s reason=name-missing\n' \
			"$INDEX"
		INVALID=$((INVALID + 1))
		continue
	fi

	set -- $(LC_ALL=C od -An -v -tu1 -N4 "$PROPERTY")
	if [ "$#" -ne 4 ]; then
		printf 'bird_uboot_bootstage_invalid_index=%s reason=property-read\n' \
			"$INDEX"
		INVALID=$((INVALID + 1))
		continue
	fi
	VALUE_US=$(($1 * 16777216 + $2 * 65536 + $3 * 256 + $4))
	NAME=$(LC_ALL=C tr -d '\000' <"$ENTRY/name" | \
		LC_ALL=C tr '\t\r\n' '   ')
	if [ -z "$NAME" ]; then
		printf 'bird_uboot_bootstage_invalid_index=%s reason=name-empty\n' \
			"$INDEX"
		INVALID=$((INVALID + 1))
		continue
	fi
	printf '%s\t%s\t%s\t%s\n' "$INDEX" "$KIND" "$VALUE_US" "$NAME"
	RECORDS=$((RECORDS + 1))
	case "$NAME" in
		board_init_f)
			BOARD_INIT_F_COUNT=$((BOARD_INIT_F_COUNT + 1))
			if [ "$KIND" = mark ]; then
				BOARD_INIT_F_MARKS=$((BOARD_INIT_F_MARKS + 1))
				BOARD_INIT_F_US=$VALUE_US
			fi
			;;
		board_init_r)
			BOARD_INIT_R_COUNT=$((BOARD_INIT_R_COUNT + 1))
			if [ "$KIND" = mark ]; then
				BOARD_INIT_R_MARKS=$((BOARD_INIT_R_MARKS + 1))
				BOARD_INIT_R_US=$VALUE_US
			fi
			;;
		main_loop)
			MAIN_LOOP_COUNT=$((MAIN_LOOP_COUNT + 1))
			if [ "$KIND" = mark ]; then
				MAIN_LOOP_MARKS=$((MAIN_LOOP_MARKS + 1))
				MAIN_LOOP_US=$VALUE_US
			fi
			;;
		bootm_start)
			BOOTM_START_COUNT=$((BOOTM_START_COUNT + 1))
			if [ "$KIND" = mark ]; then
				BOOTM_START_MARKS=$((BOOTM_START_MARKS + 1))
				BOOTM_START_US=$VALUE_US
			fi
			;;
		bootm_load_os)
			BOOTM_LOAD_OS_COUNT=$((BOOTM_LOAD_OS_COUNT + 1))
			if [ "$KIND" = mark ]; then
				BOOTM_LOAD_OS_MARKS=$((BOOTM_LOAD_OS_MARKS + 1))
				BOOTM_LOAD_OS_US=$VALUE_US
			fi
			;;
		start_kernel)
			START_KERNEL_COUNT=$((START_KERNEL_COUNT + 1))
			if [ "$KIND" = mark ]; then
				START_KERNEL_MARKS=$((START_KERNEL_MARKS + 1))
				START_KERNEL_US=$VALUE_US
			fi
			;;
	esac
done

REQUIRED_COMPLETE=1
validate_required_phase() {
	PHASE=$1
	COUNT=$2
	MARKS=$3
	if [ "$COUNT" -eq 0 ]; then
		printf 'bird_uboot_bootstage_invalid_phase=%s reason=missing\n' "$PHASE"
	elif [ "$COUNT" -ne 1 ]; then
		printf 'bird_uboot_bootstage_invalid_phase=%s reason=duplicate count=%s\n' \
			"$PHASE" "$COUNT"
	elif [ "$MARKS" -ne 1 ]; then
		printf 'bird_uboot_bootstage_invalid_phase=%s reason=non-mark\n' "$PHASE"
	else
		return 0
	fi
	INVALID=$((INVALID + 1))
	REQUIRED_COMPLETE=0
}

validate_required_phase board_init_f "$BOARD_INIT_F_COUNT" "$BOARD_INIT_F_MARKS"
validate_required_phase board_init_r "$BOARD_INIT_R_COUNT" "$BOARD_INIT_R_MARKS"
validate_required_phase main_loop "$MAIN_LOOP_COUNT" "$MAIN_LOOP_MARKS"
validate_required_phase bootm_start "$BOOTM_START_COUNT" "$BOOTM_START_MARKS"
validate_required_phase bootm_load_os "$BOOTM_LOAD_OS_COUNT" "$BOOTM_LOAD_OS_MARKS"
validate_required_phase start_kernel "$START_KERNEL_COUNT" "$START_KERNEL_MARKS"

if [ "$REQUIRED_COMPLETE" -eq 1 ] && \
	{ [ "$BOARD_INIT_F_US" -ge "$BOARD_INIT_R_US" ] || \
	[ "$BOARD_INIT_R_US" -ge "$MAIN_LOOP_US" ] || \
	[ "$MAIN_LOOP_US" -ge "$BOOTM_START_US" ] || \
	[ "$BOOTM_START_US" -ge "$BOOTM_LOAD_OS_US" ] || \
	[ "$BOOTM_LOAD_OS_US" -ge "$START_KERNEL_US" ]; }; then
	printf '%s\n' \
		'bird_uboot_bootstage_invalid_phase_order=board_init_f,board_init_r,main_loop,bootm_start,bootm_load_os,start_kernel'
	INVALID=$((INVALID + 1))
fi

if [ "$INVALID" -eq 0 ]; then
	COMPLETE=yes
else
	COMPLETE=no
fi
printf 'bird_uboot_bootstage_records=%s\n' "$RECORDS"
printf 'bird_uboot_bootstage_invalid=%s\n' "$INVALID"
printf 'bird_uboot_bootstage_complete=%s\n' "$COMPLETE"
