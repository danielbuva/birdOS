#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
BUILDER=$ROOT/kernel/rocknix/build-stock-root-compat.sh
EARLY_BUILDER=$ROOT/kernel/rocknix/build-stock-root-early-initramfs.sh
ACTIVE_SELECTOR=$ROOT/kernel/rocknix/stock-root/extlinux.conf
FALLBACK_SELECTOR=$ROOT/kernel/rocknix/stock-root/extlinux.fallback.conf
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
grep -Fq 'SYSTEM_BUSYBOX_SHA=b90f5f58dd5c39348f7be9bbef79b349f51e6ac0117b217691e2701d73714b38' \
	"$BUILDER" || fail 'SYSTEM BusyBox identity is not pinned'
grep -Fq 'for APPLET in awk chmod cmp cp mv rm stat; do' "$BUILDER" &&
	grep -Fq 'exact SYSTEM BusyBox lacks required $APPLET applet' "$BUILDER" ||
	fail 'SYSTEM policy applet capabilities are not verified during preflight'
grep -Fq "grep -Fq '/sysroot/usr/bin/busybox chmod 0755'" "$BUILDER" ||
	fail 'generated mount hook executable modes are not validated'
grep -Fq "grep -Fq '/sysroot/usr/bin/busybox chmod 0644'" "$BUILDER" ||
	fail 'generated mount hook data modes are not validated'
grep -Fq 'print "  if [ \"${BOOT_STEP}\" = \"mount_storage\" ]; then"' \
	"$EARLY_BUILDER" ||
	fail 'generated init does not isolate mount-storage failure'
grep -Fq 'status=failed step=mount_storage' "$EARLY_BUILDER" ||
	fail 'generated init does not persist mount-storage failure evidence'
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
grep -Fq "grep -q '^#define ACTION_RELOAD 13$'" "$BUILDER" ||
	fail 'production builder does not validate the reload action'
grep -Fq "grep -Fq '13) consume_handoff_action ;;'" "$BUILDER" ||
	fail 'production builder does not validate reload dispatch'
grep -Fq 'start_portmaster_network start' "$BUILDER" ||
	fail 'production builder does not validate direct PortMaster networking'
if grep -Fq "grep -q '^#define ACTION_ROCKNIX 13$'" "$BUILDER" ||
	grep -Fq "grep -Fq 'run_content --rocknix'" "$BUILDER" ||
	grep -Fq "grep -Fq 'run_managed /usr/bin/start_es.sh'" "$BUILDER"; then
	fail 'production builder still requires the removed stock frontend'
fi
for TOKEN in fbcon=map:1 vt.global_cursor_default=0; do
	[ "$(awk -v token="$TOKEN" '
		{ for (field = 1; field <= NF; field++) if ($field == token) {
			count++
			if ($1 == "APPEND") append++
		} }
		END { print (count + 0) ":" (append + 0) }
	' "$ACTIVE_SELECTOR")" = 1:1 ] ||
		fail "active selector must place $TOKEN on APPEND exactly once"
done
if grep -Fq 'console=ttyS0,115200' "$ACTIVE_SELECTOR"; then
	fail 'production selector still enables the diagnostic serial console'
fi
grep -Fq 'console=ttyS0,115200' "$FALLBACK_SELECTOR" ||
	fail 'fallback selector lost the diagnostic serial console'
FINAL_ASSET_LINE=$(line_number '^validate_final_launcher_static_assets$' "$BUILDER")
FINAL_COPY_LINE=$(line_number 'mpv-input.conf' "$BUILDER")
FINAL_MANIFEST_LINE=$(line_number '^MANIFEST=' "$BUILDER")
[ "$FINAL_ASSET_LINE" -gt "$FINAL_COPY_LINE" ] ||
	fail 'final static-asset budget runs before payload assembly completes'
[ "$FINAL_ASSET_LINE" -lt "$FINAL_MANIFEST_LINE" ] ||
	fail 'final static-asset budget runs after manifest publication begins'

# Exercise the exact production validators with safe and forbidden fixtures.
ASSET_FUNCTIONS=$TMP/static-asset-functions.sh
awk '
	/^validate_(final|early)_launcher_static_assets\(\) \{$/ { copying = 1 }
	copying { print }
	copying && /^}$/ { copying = 0; found++ }
	END { if (found != 2) exit 1 }
' "$BUILDER" "$EARLY_BUILDER" >"$ASSET_FUNCTIONS" ||
	fail 'could not extract production static-asset validators'
ASSET_ROOT=$TMP/static-assets
mkdir -p "$ASSET_ROOT/final/card/bird"
python3 "$ROOT/firmware/generate-launcher-bootlogo.py" \
	"$ASSET_ROOT/frame.bmp" \
	--xrgb-output "$ASSET_ROOT/final/card/bird/launcher-base.xrgb" >/dev/null
(
	OUTPUT=$ASSET_ROOT/final
	PAYLOAD=$ASSET_ROOT/early
	EARLY_STATIC_ASSET_BYTES=0
	mkdir -p "$OUTPUT/card/bird" "$PAYLOAD/opt/bird"
	printf 'configuration\n' >"$OUTPUT/card/bird/allowed.conf"
	printf 'module\n' >"$PAYLOAD/opt/bird/allowed.ko"
	fail() { printf 'asset validation failure: %s\n' "$*" >&2; exit 1; }
	file_bytes() { stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"; }
	sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
	. "$ASSET_FUNCTIONS"
	validate_final_launcher_static_assets
	validate_early_launcher_static_assets
	cp "$OUTPUT/card/bird/launcher-base.xrgb" \
		"$PAYLOAD/opt/bird/launcher-base.xrgb"
	EARLY_STATIC_ASSET_BYTES=1382400
	validate_early_launcher_static_assets
	EARLY_STATIC_ASSET_BYTES=0
	if (validate_early_launcher_static_assets) \
		2>"$TMP/early-duplicate.err"; then
		fail 'verified-reuse validator accepted a duplicate early wallpaper'
	fi
	grep -Fq 'duplicate early wallpaper' "$TMP/early-duplicate.err" ||
		fail 'duplicate early wallpaper rejection was not diagnostic'
	rm -f "$PAYLOAD/opt/bird/launcher-base.xrgb"
	printf 'pixels\n' >"$OUTPUT/card/bird/forbidden.raw"
	if (validate_final_launcher_static_assets) \
		2>"$TMP/final-asset.err"; then
		fail 'final static-asset validator accepted a raw framebuffer'
	fi
	grep -Fq 'unbudgeted static image' "$TMP/final-asset.err" ||
		fail 'final static-asset rejection was not diagnostic'
	printf 'pixels\n' >"$PAYLOAD/forbidden.bmp"
	if (validate_early_launcher_static_assets) \
		2>"$TMP/early-asset.err"; then
		fail 'early static-asset validator accepted an overlay bitmap'
	fi
	grep -Fq 'unbudgeted static image' "$TMP/early-asset.err" ||
		fail 'early static-asset rejection was not diagnostic'
)
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
	BIRD_RELEASE_ID=${4:-v6.23} BIRD_INITRAMFS_GZIP_LEVEL=${5:-9} \
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

# A selected immutable release must be compiled into the production loader;
# its host-test default remains independent and the generated shell stays
# syntactically valid.
CUSTOM=$TMP/output-custom-release
CUSTOM_ID=v6.23-repro-test
build_early 022 UTC "$CUSTOM" "$CUSTOM_ID" >"$TMP/custom-build.log"
grep -Fq "BIRD_LOADER_RELEASE=$CUSTOM_ID" \
	"$CUSTOM/build/early-initramfs/payload/bird-release-loader.sh" || \
	fail 'custom release ID did not reach the early release loader'
bash -n "$CUSTOM/build/early-initramfs/payload/bird-release-loader.sh" || \
	fail 'custom release loader is not valid shell'

# The screening compression candidate changes only the deterministic gzip
# level. It must unpack to the identical normalized cpio payload and remain
# explicitly recorded in the build flags.
FAST=$TMP/output-gzip-1
build_early 022 UTC "$FAST" v6.23-gzip-1 1 >"$TMP/gzip-1-build.log"
gzip -dc "$FAST/card/bird-initramfs.cpio.gz" | \
	cmp - "$FAST/build/early-initramfs/bird-initramfs.cpio" || \
	fail 'gzip level 1 did not preserve the normalized initramfs payload'
grep -Fq 'gzip -n -1 -c' "$FAST/build/build-flags.tsv" || \
	fail 'gzip level 1 was not recorded in build flags'
if BIRD_INITRAMFS_GZIP_LEVEL=2 OUTPUT=$TMP/output-gzip-invalid \
		"$EARLY_BUILDER" >"$TMP/gzip-invalid.log" 2>&1; then
	fail 'unsupported initramfs gzip level was accepted'
fi
grep -Fq 'gzip level must be 1 or 9' "$TMP/gzip-invalid.log" || \
	fail 'unsupported initramfs gzip level failure was not diagnostic'

printf 'stock-root build reproducibility tests: PASS\n'
