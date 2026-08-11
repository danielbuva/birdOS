#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd -P)
VERIFY=$ROOT/kernel/rocknix/verify-source-kernel-system-delta.py
BUILDER=$ROOT/kernel/rocknix/build-source-kernel-system.sh
SOURCE_BUILDER=$ROOT/kernel/rocknix/build-source-reference.sh
IRQ_TRANSFORM=$ROOT/kernel/rocknix/transform-joypad-irq.py
IRQ_TRANSFORM_TEST=$ROOT/kernel/rocknix/tests/test-joypad-irq-transform.py
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-source-system-test.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
HEADER='path\ttype\tmode\tuid\tgid\tmtime_ns\tsize\tcontent\thardlink\txattrs'
KEEP='etc/keep\tfile\t0644\t0\t0\t1\t4\tkeep\t-\t-'
OLD_DIR='usr/lib/kernel-overlays/base/lib/modules/7.0.11\tdir\t0755\t0\t0\t1\t4096\t-\t-\t-'
OLD='usr/lib/kernel-overlays/base/lib/modules/7.0.11/old.ko\tfile\t0644\t0\t0\t1\t3\told\t-\t-'
NEW='usr/lib/kernel-overlays/base/lib/modules/7.0.11/new.ko\tfile\t0644\t0\t0\t2\t3\tnew\t-\t-'
MODULE_DIR='lib/modules/7.0.11\tdir\t0755\t0\t0\t1\t4096\t-\t-\t-'
MODULE='lib/modules/7.0.11/new.ko\tfile\t0644\t0\t0\t2\t3\tnew\t-\t-'

printf '%b\n%b\n%b\n%b\n' "$HEADER" "$KEEP" "$OLD_DIR" "$OLD" >"$TMP/before.tsv"
printf '%b\n%b\n%b\n%b\n' "$HEADER" "$KEEP" "$OLD_DIR" "$NEW" >"$TMP/after.tsv"
printf '%b\n%b\n%b\n' "$HEADER" "$MODULE_DIR" "$MODULE" >"$TMP/modules.tsv"
python3 "$VERIFY" "$TMP/before.tsv" "$TMP/after.tsv" "$TMP/modules.tsv" \
	>"$TMP/good.out" || fail 'exact module-only delta was rejected'
grep -Fqx 'verified-source-module-nodes	2' "$TMP/good.out" || \
	fail 'verified source-module count missing'

sed 's/etc\/keep.*$/etc\/keep\tfile\t0644\t0\t0\t1\t5\twrong\t-\t-/' \
	"$TMP/after.tsv" >"$TMP/outside.tsv"
if python3 "$VERIFY" "$TMP/before.tsv" "$TMP/outside.tsv" "$TMP/modules.tsv" \
	>"$TMP/outside.out" 2>&1; then
	fail 'unrelated SYSTEM change was accepted'
fi
grep -Fq 'changed outside module tree: etc/keep' "$TMP/outside.out" || \
	fail 'unrelated change diagnostic missing'

sed '/new.ko/d' "$TMP/modules.tsv" >"$TMP/missing.tsv"
if python3 "$VERIFY" "$TMP/before.tsv" "$TMP/after.tsv" "$TMP/missing.tsv" \
	>"$TMP/missing.out" 2>&1; then
	fail 'incomplete source module authority was accepted'
fi
grep -Fq 'installed source module inventory mismatch' "$TMP/missing.out" || \
	fail 'module inventory diagnostic missing'

sh -n "$BUILDER" || fail 'source SYSTEM builder shell syntax failed'
sh -n "$SOURCE_BUILDER" || fail 'source kernel builder shell syntax failed'
python3 -m py_compile "$IRQ_TRANSFORM" "$IRQ_TRANSFORM_TEST" || \
	fail 'IRQ button transform Python syntax failed'
python3 "$IRQ_TRANSFORM_TEST" || fail 'IRQ button transform contract failed'
grep -Fq 'rocknix-official-initramfs-20260701/rocknix-initramfs.cpio' \
	"$SOURCE_BUILDER" || fail 'source kernel no longer requires the official embedded initramfs'
grep -Fq '5d2b7b247bfa78db7b1fad490e0c5cdc70ec31af18cac743aee4dc1027d66045' \
	"$SOURCE_BUILDER" || fail 'official embedded initramfs digest gate missing'
grep -Fq 'obj-y += rocknix-singleadc-joypad.o' "$SOURCE_BUILDER" || \
	fail 'fixed-device built-in H700 input linkage missing'
grep -Fq 'built-in H700 input initcall missing' "$SOURCE_BUILDER" || \
	fail 'built-in H700 input symbol gate missing'
grep -Fq 'joypad-linkage' "$SOURCE_BUILDER" || \
	fail 'built-in/module input authority record missing'
if grep -Fq 'FIXED_NO_ANALOG_POLL' "$SOURCE_BUILDER"; then
	fail 'rejected no-analog polling mode remains selectable'
fi
if grep -Fq 'RG34XX-SP has buttons only' "$SOURCE_BUILDER"; then
	fail 'rejected button-only hardware assumption remains'
fi
grep -Fq 'SINGLE_GPIO_READ requires BUILTIN_JOYPAD=1' "$SOURCE_BUILDER" || \
	fail 'single GPIO read dependency gate missing'
grep -Fq 'joypad GPIO poll authority changed' "$SOURCE_BUILDER" || \
	fail 'single GPIO read source authority gate missing'
grep -Fq 'joypad_adc_check(poll_dev);' "$SOURCE_BUILDER" || \
	fail 'analog stick polling preservation gate missing'
grep -Fq 'SINGLE_INPUT_SYNC requires SINGLE_GPIO_READ=1' "$SOURCE_BUILDER" || \
	fail 'single input sync sequencing gate missing'
grep -Fq 'old_poll = ' "$SOURCE_BUILDER" || \
	fail 'single input sync source authority gate missing'
grep -Fq 'joypad-event-policy' "$SOURCE_BUILDER" || \
	fail 'single input sync authority record missing'
grep -Fq 'CHANGED_INPUT_SYNC requires SINGLE_INPUT_SYNC=1' "$SOURCE_BUILDER" || \
	fail 'changed input sync sequencing gate missing'
grep -Fq 'input_abs_get_val(poll_dev->input' "$SOURCE_BUILDER" || \
	fail 'accepted input-value change tracking missing'
grep -Fq 'joypad-idle-policy' "$SOURCE_BUILDER" || \
	fail 'changed input sync authority record missing'
grep -Fq 'FIXED_GPIO_FASTPATH requires CHANGED_INPUT_SYNC=1' "$SOURCE_BUILDER" || \
	fail 'fixed GPIO fast-path sequencing gate missing'
grep -Fq 'joypad fixed GPIO access authority changed' "$SOURCE_BUILDER" || \
	fail 'fixed GPIO source authority gate missing'
grep -Fq 'joypad-open-policy' "$SOURCE_BUILDER" || \
	fail 'single open-frame authority record missing'
grep -Fq 'IRQ_GPIO_BUTTONS requires FIXED_GPIO_FASTPATH=1' "$SOURCE_BUILDER" || \
	fail 'IRQ button sequencing gate missing'
grep -Fq '/bird-transform-joypad-irq.py' "$SOURCE_BUILDER" || \
	fail 'IRQ button transform invocation missing'
grep -Fq 'joypad-digital-policy' "$SOURCE_BUILDER" || \
	fail 'IRQ button authority record missing'
grep -Fq 'joypad-poll-policy' "$SOURCE_BUILDER" || \
	fail 'analog-only poll authority record missing'
grep -Fq 'joypad-fixed-buttons' "$SOURCE_BUILDER" || \
	fail 'fixed button-count authority record missing'
grep -Fq 'source module archive digest changed' "$BUILDER" || \
	fail 'module archive digest gate missing'
grep -Fq 'isolated source SYSTEM $FILE differs' "$BUILDER" || \
	fail 'two-build identity gate missing'
printf 'source-kernel SYSTEM tests: PASS\n'
