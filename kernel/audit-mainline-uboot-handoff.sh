#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DTB=${1:-"$ROOT/kernel/work/mainline-compat/sun50i-h700-anbernic-rg34xx-sp-bird.dtb"}
UBOOT_DTB=${UBOOT_DTB:-"$ROOT/firmware/work/bootloader/stock-uboot.dtb"}
FDTGET=${FDTGET:-fdtget}
FDTPUT=${FDTPUT:-fdtput}

fail() {
	printf 'U-Boot handoff audit: %s\n' "$*" >&2
	exit 1
}

command -v "$FDTGET" >/dev/null 2>&1 || fail 'fdtget is required'
command -v "$FDTPUT" >/dev/null 2>&1 || fail 'fdtput is required'
test -s "$DTB" || fail "missing DTB: $DTB"
test -s "$UBOOT_DTB" || fail "missing captured U-Boot DTB: $UBOOT_DTB"

DTB_BYTES=$(stat -f %z "$DTB")
UBOOT_FDT_RAW_BYTES=$(stat -f %z "$UBOOT_DTB")
# common/board_f.c reserves 0x1000 bytes and aligns the working FDT to 32.
UBOOT_FDT_BYTES=$((((UBOOT_FDT_RAW_BYTES + 4096 + 31) / 32) * 32))
test "$DTB_BYTES" -le "$UBOOT_FDT_BYTES" \
	|| fail "Android DTB is larger than U-Boot's $UBOOT_FDT_BYTES-byte workspace"

MMC0=$($FDTGET -t s "$DTB" /aliases mmc0) \
	|| fail 'mmc0 alias missing'
test "$MMC0" = '/soc/mmc@4020000' \
	|| fail "unexpected mmc0 alias: $MMC0"
test "$($FDTGET -t s "$DTB" "$MMC0" status)" = okay \
	|| fail 'boot MMC node is not enabled'
$FDTGET -l "$DTB" / | grep -qx dram \
	|| fail 'vendor U-Boot /dram handoff node missing'
test "$($FDTGET -t s "$DTB" /dram device_type)" = dram \
	|| fail 'invalid /dram handoff node'

WORK=$(mktemp -d -t bird-uboot-handoff)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
MUTATED="$WORK/mutated.dtb"
cp "$DTB" "$MUTATED"

# Mirror board/sunxi/board_helper.c in the public sun50iw9-v2018.05
# lineage: enable mmc0, then write the 24 detected DRAM-training cells.
$FDTPUT -t s "$MUTATED" "$MMC0" status okay
for property in \
	dram_clk dram_type dram_zq dram_odt_en dram_para1 dram_para2 \
	dram_mr0 dram_mr1 dram_mr2 dram_mr3 \
	dram_tpr0 dram_tpr1 dram_tpr2 dram_tpr3 dram_tpr4 dram_tpr5 \
	dram_tpr6 dram_tpr7 dram_tpr8 dram_tpr9 dram_tpr10 dram_tpr11 \
	dram_tpr12 dram_tpr13; do
	$FDTPUT -t x "$MUTATED" /dram "$property" 0
	test "$($FDTGET -t x "$MUTATED" /dram "$property")" = 0 \
		|| fail "could not simulate U-Boot write to /dram/$property"
done

test "$(stat -f %z "$MUTATED")" -le "$UBOOT_FDT_BYTES" \
	|| fail 'simulated U-Boot mutation exceeds captured working-DTB capacity'

printf 'U-Boot handoff audit passed: %s -> %s-byte workspace\n' \
	"$DTB_BYTES" "$UBOOT_FDT_BYTES"
