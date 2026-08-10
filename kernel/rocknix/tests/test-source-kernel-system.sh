#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd -P)
VERIFY=$ROOT/kernel/rocknix/verify-source-kernel-system-delta.py
BUILDER=$ROOT/kernel/rocknix/build-source-kernel-system.sh
SOURCE_BUILDER=$ROOT/kernel/rocknix/build-source-reference.sh
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
grep -Fq 'rocknix-official-initramfs-20260701/rocknix-initramfs.cpio' \
	"$SOURCE_BUILDER" || fail 'source kernel no longer requires the official embedded initramfs'
grep -Fq '5d2b7b247bfa78db7b1fad490e0c5cdc70ec31af18cac743aee4dc1027d66045' \
	"$SOURCE_BUILDER" || fail 'official embedded initramfs digest gate missing'
grep -Fq 'source module archive digest changed' "$BUILDER" || \
	fail 'module archive digest gate missing'
grep -Fq 'isolated source SYSTEM $FILE differs' "$BUILDER" || \
	fail 'two-build identity gate missing'
printf 'source-kernel SYSTEM tests: PASS\n'
