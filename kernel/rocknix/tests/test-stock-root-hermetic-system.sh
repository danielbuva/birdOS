#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd -P)
BUILDER=$ROOT/kernel/rocknix/build-stock-root-hermetic-system.sh
DOCKERFILE=$ROOT/kernel/rocknix/Dockerfile.hermetic-system
INVENTORY=$ROOT/kernel/rocknix/inventory-rootfs.py
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-hermetic-test.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

command -v docker >/dev/null 2>&1 || fail 'docker missing'
docker info >/dev/null 2>&1 || fail 'Docker engine is not running'
grep -Fq 'FROM debian@sha256:817e6cf99d6fc127ff4ffe8580049b60deba0adfbbb2bd65ddc3ef8fbb7aade0' \
	"$DOCKERFILE" || fail 'container base is not digest-pinned'
grep -Fq 'ARG DEBIAN_SNAPSHOT=20260803T000000Z' "$DOCKERFILE" &&
	grep -Fq 'snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}' "$DOCKERFILE" ||
	fail 'Debian package snapshot is not fixed'
grep -Fq 'squashfs-tools=1:4.5.1-1' "$DOCKERFILE" ||
	fail 'SquashFS tool version is not fixed'

RECIPE_SHA=$(cat "$DOCKERFILE" "$INVENTORY" | shasum -a 256 | awk '{print $1}')
IMAGE=bird-hermetic-system:$RECIPE_SHA
docker build --platform linux/arm64 --pull=false --quiet \
	-f "$DOCKERFILE" -t "$IMAGE" "$ROOT" >/dev/null

mkdir "$TMP/fixture"
docker run --rm --platform linux/arm64 \
	-v "$TMP/fixture:/output" --entrypoint /bin/sh "$IMAGE" -ec '
mkdir -p /work/root/etc /work/root/usr/bin /work/root/empty
printf "bird\n" >/work/root/etc/hostname
printf "#!/bin/sh\nexit 0\n" >/work/root/usr/bin/bird-test
chmod 0755 /work/root/usr/bin/bird-test
ln /work/root/etc/hostname /work/root/etc/hostname.hardlink
ln -s ../etc/hostname /work/root/hostname.link
mkfifo /work/root/event.fifo
find /work/root -exec touch -h -d @1782889443 {} +
mksquashfs /work/root /output/SYSTEM -noappend -no-progress -processors 1 \
  -no-xattrs -comp zstd -Xcompression-level 19 -b 1048576 \
  -mkfs-time 1782889443 >/output/create.log
'

FIXTURE=$TMP/fixture/SYSTEM
FIXTURE_SHA=$(shasum -a 256 "$FIXTURE" | awk '{print $1}')
FIXTURE_BYTES=$(stat -f '%z' "$FIXTURE" 2>/dev/null || stat -c '%s' "$FIXTURE")
OUTPUT=$TMP/parity
SYSTEM_SOURCE=$FIXTURE SYSTEM_SHA=$FIXTURE_SHA SYSTEM_BYTES=$FIXTURE_BYTES \
	"$BUILDER" --parity "$OUTPUT" >"$TMP/parity.log"

[ -f "$OUTPUT/SYSTEM" ] || fail 'parity SYSTEM missing'
cmp "$OUTPUT/shipping-inventory.tsv" "$OUTPUT/repacked-inventory.tsv" ||
	fail 'fixture effective tree changed'
grep -Fq 'schema	bird-hermetic-system-parity-v1' "$OUTPUT/parity.tsv" ||
	fail 'parity schema missing'
grep -Fq 'squashfs-tools	1:4.5.1-1' "$OUTPUT/toolchain.tsv" ||
	fail 'toolchain authority missing'
grep -Fq 'event.fifo	fifo	0644' "$OUTPUT/shipping-inventory.tsv" ||
	fail 'FIFO metadata missing from inventory'
grep -Fq 'hostname.hardlink' "$OUTPUT/shipping-inventory.tsv" ||
	fail 'hardlink metadata missing from inventory'

if SYSTEM_SOURCE=$FIXTURE SYSTEM_SHA=$(printf '0%.0s' $(jot 64)) \
	SYSTEM_BYTES=$FIXTURE_BYTES "$BUILDER" --parity "$TMP/bad" \
	>"$TMP/bad.log" 2>&1; then
	fail 'bad input digest was accepted'
fi
[ ! -e "$TMP/bad" ] || fail 'bad input published output'

ln -s "$TMP/elsewhere" "$TMP/unsafe"
if SYSTEM_SOURCE=$FIXTURE SYSTEM_SHA=$FIXTURE_SHA SYSTEM_BYTES=$FIXTURE_BYTES \
	"$BUILDER" --parity "$TMP/unsafe" >"$TMP/unsafe.log" 2>&1; then
	fail 'symlink output was accepted'
fi
[ -L "$TMP/unsafe" ] || fail 'unsafe output was mutated'

printf 'stock-root hermetic SYSTEM tests: PASS\n'
