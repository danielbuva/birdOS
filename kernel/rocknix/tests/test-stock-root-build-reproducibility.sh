#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
BUILDER=$ROOT/kernel/rocknix/build-stock-root-compat.sh
EARLY_BUILDER=$ROOT/kernel/rocknix/build-stock-root-early-initramfs.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-build-reproducibility.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

line_number() {
	grep -n "$1" "$2" | head -n 1 | cut -d: -f1
}

# Keep the production ordering explicit: provenance starts before the first
# tracked payload read and is rechecked after candidate bytes are complete but
# before the manifest is published.
RECORD_LINE=$(line_number '^record_source_identity$' "$BUILDER")
FIRST_SOURCE_READ=$(line_number 'sha256.*extlinux\.fallback\.conf' "$BUILDER")
VERIFY_LINE=$(line_number '^verify_source_identity$' "$BUILDER")
MANIFEST_LINE=$(line_number '^MANIFEST=' "$BUILDER")
[ "$RECORD_LINE" -lt "$FIRST_SOURCE_READ" ] || fail 'source identity is recorded too late'
[ "$VERIFY_LINE" -lt "$MANIFEST_LINE" ] || fail 'source identity is verified too late'
grep -Fq 'chmod 0644 "$OUTPUT/card/SYSTEM"' "$BUILDER" ||
	fail 'SYSTEM mode is not explicit'
grep -Fq '*) OUTPUT=$PWD/$OUTPUT ;;' "$BUILDER" ||
	fail 'relative OUTPUT is not canonicalized before inventory generation'
grep -Fq "sed 's#^\\./##'" "$BUILDER" || fail 'deploy inventories are not relative'
grep -Fq 'find "$PAYLOAD" -type d -exec chmod 0755 {} +' "$EARLY_BUILDER" ||
	fail 'initramfs directory modes are not explicit'
grep -Fq 'touch -t 202601010000.00' "$EARLY_BUILDER" ||
	fail 'initramfs timestamp is not explicit to the second'
for SCRIPT in "$BUILDER" "$EARLY_BUILDER"; do
	grep -Fq 'umask 022' "$SCRIPT" || fail "fixed umask missing from $SCRIPT"
	grep -Fq 'TZ=UTC' "$SCRIPT" || fail "fixed timezone missing from $SCRIPT"
done
if grep -Eq 'rev-parse.*unknown|status.*unknown' "$BUILDER"; then
	fail 'source provenance still has a permissive unknown fallback'
fi

# Exercise the exact production provenance functions in an isolated Git
# repository. A stable clean or dirty tree is accepted; a persistent change
# between record and verify must fail closed.
FUNCTIONS=$TMP/provenance-functions.sh
awk '
	/^capture_source_identity\(\) \{$/ { copying = 1 }
	copying { print }
	/^verify_source_identity\(\) \{$/ { in_verify = 1 }
	copying && in_verify && /^}$/ { exit }
' "$BUILDER" >"$FUNCTIONS"
grep -Fq 'verify_source_identity()' "$FUNCTIONS" ||
	fail 'could not extract production provenance functions'

REPO=$TMP/source-repository
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email bird-build-test@example.invalid
git -C "$REPO" config user.name 'birdOS build test'
printf 'original\n' >"$REPO/tracked.txt"
git -C "$REPO" add tracked.txt
git -C "$REPO" commit -qm initial
COMMIT=$(git -C "$REPO" rev-parse HEAD)

capture_and_verify() (
	ROOT=$REPO
	OUTPUT=$1
	mkdir -p "$OUTPUT/build"
	fail() { printf 'provenance failure: %s\n' "$*" >&2; exit 1; }
	sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
	file_bytes() { stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"; }
	file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
	. "$FUNCTIONS"
	record_source_identity
	verify_source_identity
	printf '%s\t%s\n' "$SOURCE_COMMIT" "$SOURCE_STATE"
)

CLEAN_IDENTITY=$(capture_and_verify "$TMP/clean-provenance")
TAB=$(printf '\t')
[ "$CLEAN_IDENTITY" = "$COMMIT${TAB}clean" ] || fail 'clean source identity is not exact'
printf 'stable dirty change\n' >>"$REPO/tracked.txt"
DIRTY_IDENTITY=$(capture_and_verify "$TMP/dirty-provenance")
case "$DIRTY_IDENTITY" in
	"$COMMIT${TAB}dirty:"[0-9a-f][0-9a-f]*) ;;
	*) fail 'stable dirty source identity was not retained' ;;
esac
printf 'original\n' >"$REPO/tracked.txt"

if (
	ROOT=$REPO
	OUTPUT=$TMP/mutated-provenance
	mkdir -p "$OUTPUT/build"
	fail() { printf 'provenance failure: %s\n' "$*" >&2; exit 1; }
	sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
	file_bytes() { stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"; }
	file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
	. "$FUNCTIONS"
	record_source_identity
	printf 'changed during build\n' >>"$REPO/tracked.txt"
	verify_source_identity
) 2>"$TMP/mutation.err"; then
	fail 'persistent mid-build source mutation was accepted'
fi
grep -Fq 'source tree changed while candidate bytes were being built' \
	"$TMP/mutation.err" || fail 'source mutation failure was not diagnostic'
printf 'original\n' >"$REPO/tracked.txt"

# Build the real early-initramfs twice from the pinned local inputs. The caller
# deliberately supplies different umasks, timezones and output directory names;
# every resulting byte and Unix mode must remain identical.
for REQUIRED in \
	"$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/init" \
	"$ROOT/kernel/work/rocknix-official-initramfs-20260701/ramdisk/usr/bin/busybox" \
	"$ROOT/kernel/work/rocknix-system-exact-20260701/usr/lib/kernel-overlays/base/lib/modules/7.0.11/rocknix-joypad/rocknix-singleadc-joypad.ko" \
	/opt/homebrew/opt/llvm/bin/clang \
	/opt/homebrew/opt/lld/bin/ld.lld \
	/opt/homebrew/opt/llvm/bin/llvm-readelf; do
	[ -e "$REQUIRED" ] || fail "required pinned build input is missing: $REQUIRED"
done

build_early() (
	umask "$1"
	TZ=$2
	export TZ
	OUTPUT=$3
	mkdir -p "$OUTPUT/build" "$OUTPUT/card"
	OUTPUT=$OUTPUT "$EARLY_BUILDER"
)

FIRST=$TMP/output-umask-022-utc
SECOND=$TMP/output-umask-077-pacific
build_early 022 UTC "$FIRST" >"$TMP/first-build.log"
build_early 077 America/Los_Angeles "$SECOND" >"$TMP/second-build.log"

python3 - "$FIRST" "$SECOND" <<'PY'
from __future__ import annotations

import hashlib
import os
import stat
import sys
from pathlib import Path


def snapshot(root: Path) -> dict[str, tuple[str, int, str]]:
    result: dict[str, tuple[str, int, str]] = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        mode = stat.S_IMODE(path.lstat().st_mode)
        if path.is_symlink():
            result[relative] = ("symlink", mode, os.readlink(path))
        elif path.is_dir():
            result[relative] = ("directory", mode, "")
        elif path.is_file():
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            result[relative] = ("file", mode, digest)
        else:
            raise SystemExit(f"unexpected special node: {path}")
    return result


first = snapshot(Path(sys.argv[1]))
second = snapshot(Path(sys.argv[2]))
if first != second:
    keys = sorted(set(first) | set(second))
    differences = [key for key in keys if first.get(key) != second.get(key)]
    for key in differences[:20]:
        print(f"{key}: {first.get(key)!r} != {second.get(key)!r}", file=sys.stderr)
    raise SystemExit("early-initramfs outputs differ across umask/TZ/output path")
PY

printf 'stock-root build reproducibility tests: PASS\n'
