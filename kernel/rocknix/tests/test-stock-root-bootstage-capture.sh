#!/bin/sh
# Host-only coverage for the optional post-frame U-Boot bootstage snapshot.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SCRIPT=$ROOT/kernel/rocknix/stock-root/capture-uboot-bootstage.sh
CAPTURE=$ROOT/kernel/rocknix/stock-root/capture-boot-state.sh
SERVICE=$ROOT/kernel/rocknix/stock-root/rocknix-report-stats.service
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-bootstage-capture.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
TREE=$TMP/bootstage

mkdir -p "$TREE/0" "$TREE/1" "$TREE/2" "$TREE/3" "$TREE/4" \
	"$TREE/5" "$TREE/6" "$TREE/7" "$TREE/not-an-index"
printf 'reset\0' >"$TREE/0/name"
printf '\0\0\0\0' >"$TREE/0/mark"
printf 'board_init_f\0' >"$TREE/1/name"
printf '\0\0\0\42' >"$TREE/1/mark"
printf 'board_init_r\0' >"$TREE/2/name"
printf '\0\0\0\104' >"$TREE/2/mark"
printf 'main_loop\0' >"$TREE/3/name"
printf '\0\0\0\146' >"$TREE/3/mark"
printf 'bootm_start\0' >"$TREE/4/name"
printf '\0\0\0\210' >"$TREE/4/mark"
printf 'bootm_load_os\0' >"$TREE/5/name"
printf '\0\0\0\231' >"$TREE/5/mark"
printf 'start_kernel\0' >"$TREE/6/name"
printf '\0\0\0\252' >"$TREE/6/mark"
printf 'dram\0' >"$TREE/7/name"
printf '\0\1\0\0' >"$TREE/7/accum"
printf 'ignored\0' >"$TREE/not-an-index/name"
printf '\0\0\0\1' >"$TREE/not-an-index/mark"

BIRD_BOOTSTAGE_ROOT=$TREE "$SCRIPT" >"$TMP/output"
grep -Fxq 'bird_uboot_bootstage_version=1' "$TMP/output"
grep -Fqx "bird_uboot_bootstage_columns=index	kind	value_us	name" "$TMP/output"
grep -Fqx "0	mark	0	reset" "$TMP/output"
grep -Fqx "1	mark	34	board_init_f" "$TMP/output"
grep -Fqx "2	mark	68	board_init_r" "$TMP/output"
grep -Fqx "3	mark	102	main_loop" "$TMP/output"
grep -Fqx "4	mark	136	bootm_start" "$TMP/output"
grep -Fqx "5	mark	153	bootm_load_os" "$TMP/output"
grep -Fqx "6	mark	170	start_kernel" "$TMP/output"
grep -Fqx "7	accum	65536	dram" "$TMP/output"
grep -Fxq 'bird_uboot_bootstage_records=8' "$TMP/output"
grep -Fxq 'bird_uboot_bootstage_invalid=0' "$TMP/output"
grep -Fxq 'bird_uboot_bootstage_complete=yes' "$TMP/output"

RECORD_INDICES=$(awk -F '\t' 'NF == 4 && $1 ~ /^[0-9]+$/ { print $1 }' "$TMP/output")
[ "$RECORD_INDICES" = "$(printf '0\n1\n2\n3\n4\n5\n6\n7')" ]
if grep -Fq 'not-an-index' "$TMP/output"; then
	printf '%s\n' 'non-numeric bootstage child was captured' >&2
	exit 1
fi

# A well-formed but truncated tree is not valid measurement evidence.
TRUNCATED=$TMP/truncated
mkdir -p "$TRUNCATED/1" "$TRUNCATED/2"
cp "$TREE/1/name" "$TREE/1/mark" "$TRUNCATED/1/"
cp "$TREE/2/name" "$TREE/2/mark" "$TRUNCATED/2/"
BIRD_BOOTSTAGE_ROOT=$TRUNCATED "$SCRIPT" >"$TMP/truncated-output"
grep -Fxq 'bird_uboot_bootstage_invalid_phase=main_loop reason=missing' \
	"$TMP/truncated-output"
grep -Fxq 'bird_uboot_bootstage_invalid_phase=bootm_start reason=missing' \
	"$TMP/truncated-output"
grep -Fxq 'bird_uboot_bootstage_invalid_phase=bootm_load_os reason=missing' \
	"$TMP/truncated-output"
grep -Fxq 'bird_uboot_bootstage_invalid_phase=start_kernel reason=missing' \
	"$TMP/truncated-output"
grep -Fxq 'bird_uboot_bootstage_invalid=4' "$TMP/truncated-output"
grep -Fxq 'bird_uboot_bootstage_complete=no' "$TMP/truncated-output"

# Required names must remain unique marks, and their time values must be
# strictly increasing before the record can be used for phase comparisons.
mkdir -p "$TREE/8"
cp "$TREE/5/name" "$TREE/5/mark" "$TREE/8/"
BIRD_BOOTSTAGE_ROOT=$TREE "$SCRIPT" >"$TMP/duplicate-output"
grep -Fxq 'bird_uboot_bootstage_invalid_phase=bootm_load_os reason=duplicate count=2' \
	"$TMP/duplicate-output"
grep -Fxq 'bird_uboot_bootstage_complete=no' "$TMP/duplicate-output"
rm -rf "$TREE/8"

mv "$TREE/5/mark" "$TREE/5/accum"
BIRD_BOOTSTAGE_ROOT=$TREE "$SCRIPT" >"$TMP/non-mark-output"
grep -Fxq 'bird_uboot_bootstage_invalid_phase=bootm_load_os reason=non-mark' \
	"$TMP/non-mark-output"
grep -Fxq 'bird_uboot_bootstage_complete=no' "$TMP/non-mark-output"
mv "$TREE/5/accum" "$TREE/5/mark"

# Both sides of the new load boundary are strict: it must follow bootm_start
# and precede start_kernel. Raw records remain present when validation fails.
printf '\0\0\0\200' >"$TREE/5/mark"
BIRD_BOOTSTAGE_ROOT=$TREE "$SCRIPT" >"$TMP/order-output"
grep -Fxq \
	'bird_uboot_bootstage_invalid_phase_order=board_init_f,board_init_r,main_loop,bootm_start,bootm_load_os,start_kernel' \
	"$TMP/order-output"
grep -Fqx "5	mark	128	bootm_load_os" "$TMP/order-output"
grep -Fxq 'bird_uboot_bootstage_complete=no' "$TMP/order-output"

printf '\0\0\1\0' >"$TREE/5/mark"
BIRD_BOOTSTAGE_ROOT=$TREE "$SCRIPT" >"$TMP/late-load-output"
grep -Fxq \
	'bird_uboot_bootstage_invalid_phase_order=board_init_f,board_init_r,main_loop,bootm_start,bootm_load_os,start_kernel' \
	"$TMP/late-load-output"
grep -Fqx "5	mark	256	bootm_load_os" "$TMP/late-load-output"
grep -Fxq 'bird_uboot_bootstage_complete=no' "$TMP/late-load-output"

mkdir "$TMP/empty"
BIRD_BOOTSTAGE_ROOT=$TMP/empty "$SCRIPT" >"$TMP/empty-output"
grep -Fxq 'bird_uboot_bootstage_records=0' "$TMP/empty-output"
grep -Fxq 'bird_uboot_bootstage_invalid=6' "$TMP/empty-output"
grep -Fxq 'bird_uboot_bootstage_complete=no' "$TMP/empty-output"
if BIRD_BOOTSTAGE_ROOT=$TMP/missing "$SCRIPT" >"$TMP/missing-output"; then
	[ ! -s "$TMP/missing-output" ]
else
	printf '%s\n' 'missing optional bootstage root was treated as failure' >&2
	exit 1
fi

# The broad snapshot owns persistence and is event-ordered behind normal
# autostart. The helper itself has no service or first-frame integration.
grep -Fqx 'After=rocknix-autostart.service' "$SERVICE"
grep -Fq 'if [ -d "$BOOTSTAGE_ROOT" ]; then' "$CAPTURE"
grep -Fq 'BIRD_BOOTSTAGE_ROOT=$BOOTSTAGE_ROOT "$BOOTSTAGE_CAPTURE"' "$CAPTURE"
if rg -q 'capture-uboot-bootstage' \
	"$ROOT/launcher/bird-launcher.c" \
	"$ROOT/kernel/rocknix/stock-root/first-frame-prep.sh"; then
	printf '%s\n' 'bootstage capture entered the first-frame path' >&2
	exit 1
fi

printf '%s\n' 'stock-root U-Boot bootstage capture tests passed'
