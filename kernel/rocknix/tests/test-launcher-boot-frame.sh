#!/bin/sh
# Host contract test for the build-only U-Boot base asset. The BMP never enters
# the early payload; until verified reuse, only its native XRGB counterpart does.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-boot-frame.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

for NAME in first second; do
	python3 "$ROOT/firmware/generate-launcher-bootlogo.py" \
		"$TMP/$NAME.bmp" --contract "$TMP/$NAME.contract" \
		--xrgb-output "$TMP/$NAME.xrgb" \
		--static-base-output "$TMP/$NAME.static.xrgb" >/dev/null
done

cmp "$TMP/first.bmp" "$TMP/second.bmp"
cmp "$TMP/first.contract" "$TMP/second.contract"
cmp "$TMP/first.xrgb" "$TMP/second.xrgb"
cmp "$TMP/first.static.xrgb" "$TMP/second.static.xrgb"
python3 - "$TMP/first.bmp" "$TMP/first.xrgb" \
	"$TMP/first.static.xrgb" <<'PY'
import struct
import sys
from pathlib import Path

bmp = Path(sys.argv[1]).read_bytes()
xrgb = Path(sys.argv[2]).read_bytes()
static_base = Path(sys.argv[3]).read_bytes()
assert bmp[:2] == b"BM"
pixel_offset = struct.unpack_from("<I", bmp, 10)[0]
dib_size, width, height, planes, bits, compression = struct.unpack_from(
    "<IiiHHI", bmp, 14
)
assert (pixel_offset, dib_size, width, height, planes, bits, compression) == (
    138, 124, 720, 480, 1, 24, 0
)
decoded = bytearray()
stride = width * 3
for screen_y in range(height):
    source_y = height - screen_y - 1
    row = bmp[pixel_offset + source_y * stride : pixel_offset + (source_y + 1) * stride]
    assert len(row) == stride
    for offset in range(0, stride, 3):
        decoded.extend(row[offset : offset + 3])
        decoded.append(0)
assert len(xrgb) == 720 * 480 * 4
assert not any(xrgb[3::4])

regions = (
    (0, 0, 720, 36), (0, 36, 160, 40), (560, 36, 160, 40),
    (0, 76, 720, 28), (0, 104, 160, 288), (560, 104, 160, 288),
    (0, 392, 163, 3), (560, 392, 160, 3), (0, 395, 720, 85),
)
unpacked = bytearray(len(xrgb))
packed_offset = 0
for x, y, width, height in regions:
    packed_stride = (width + (width & 1)) * 4
    for row in range(height):
        source = packed_offset + row * packed_stride
        target = ((y + row) * 720 + x) * 4
        unpacked[target : target + width * 4] = static_base[
            source : source + width * 4
        ]
        assert not any(static_base[source + width * 4 : source + packed_stride])
    packed_offset += packed_stride * height
assert packed_offset == len(static_base) == 852848
assert unpacked == xrgb

def region_bytes(buffer, x, y, width, height):
    for row in range(y, y + height):
        start = (row * 720 + x) * 4
        yield buffer[start : start + width * 4]

for region in ((160, 36, 400, 40), (160, 104, 400, 288),
               (163, 392, 397, 3)):
    assert all(not any(row) for row in region_bytes(xrgb, *region))

composited = bytearray(xrgb)
def rectangle(x, y, width, height, rgb):
    red, green, blue = rgb
    row = bytes((blue, green, red, 0)) * width
    for screen_y in range(y, y + height):
        start = (screen_y * 720 + x) * 4
        composited[start : start + len(row)] = row

rectangle(163, 392, 397, 3, (15, 8, 12))
rectangle(160, 36, 400, 40, (239, 226, 217))
rectangle(160, 104, 32, 288, (239, 226, 217))
rectangle(192, 104, 368, 288, (36, 10, 18))
rectangle(192, 104, 10, 288, (55, 18, 29))
assert composited == decoded
PY

# Generated destinations are atomically replaced rather than followed.
printf '%s\n' 'sentinel' >"$TMP/sentinel"
ln -s "$TMP/sentinel" "$TMP/symlink.bmp"
python3 "$ROOT/firmware/generate-launcher-bootlogo.py" \
	"$TMP/symlink.bmp" >/dev/null
[ ! -L "$TMP/symlink.bmp" ]
grep -Fqx 'sentinel' "$TMP/sentinel"
cmp "$TMP/first.bmp" "$TMP/symlink.bmp"
[ "$(wc -c <"$TMP/first.bmp" | tr -d ' ')" -eq 1036938 ]
[ "$(shasum -a 256 "$TMP/first.bmp" | awk '{print $1}')" = \
	fca1176e4247c5b358df495cf062e88ff53c3aa781c54325545a02b26a9fcb15 ]
[ "$(wc -c <"$TMP/first.xrgb" | tr -d ' ')" -eq 1382400 ]
[ "$(shasum -a 256 "$TMP/first.xrgb" | awk '{print $1}')" = \
	6f9daae758675bd8bb805a851b30f1d64b06ec6e8367a17749707ac61824843a ]
[ "$(wc -c <"$TMP/first.static.xrgb" | tr -d ' ')" -eq 852848 ]
[ "$(shasum -a 256 "$TMP/first.static.xrgb" | awk '{print $1}')" = \
	e6f9ca8ef4100cdf384bc2f8f3f7b902bc83cee6c4bc36e82fbc666328b382de ]
grep -Fqx 'schema	bird-boot-frame-v4' "$TMP/first.contract"
grep -Fqx 'backdrop-sha256	3fdea84fe0c149378db32d1849e55b3fede22c74a613544810be880f48fdb9d3' "$TMP/first.contract"
grep -Fqx 'visible-hash-a	849df1c7262d2e3e' "$TMP/first.contract"
grep -Fqx 'visible-hash-b	754469f5749caa71' "$TMP/first.contract"
grep -Fqx 'logical-pixels	345600' "$TMP/first.contract"
grep -Fqx 'visible-framebuffer-bytes	1036800' "$TMP/first.contract"
grep -Fqx 'framebuffer-pages	1' "$TMP/first.contract"
grep -Fqx 'physical-framebuffer-bytes	1382400' "$TMP/first.contract"
grep -Fqx 'raw-resolution	720x480' "$TMP/first.contract"
grep -Fqx 'raw-pixel-format	XRGB8888' "$TMP/first.contract"
grep -Fqx 'raw-memory-channel-order	B,G,R,X' "$TMP/first.contract"
grep -Fqx 'raw-stride	2880' "$TMP/first.contract"
grep -Fqx 'raw-orientation	top-down' "$TMP/first.contract"
grep -Fqx 'raw-page-offset	0:0' "$TMP/first.contract"
grep -Fqx 'raw-subtracted-regions	top-bar,menu-container,menu-shadow' "$TMP/first.contract"
grep -Fqx 'static-base-layout	fixed-visible-regions-v1' "$TMP/first.contract"
grep -Fqx 'early-static-asset-bytes	0' "$TMP/first.contract"
grep -Fqx 'final-root-static-asset-bytes	852848' "$TMP/first.contract"
grep -Fqx 'final-root-static-asset-sha256	e6f9ca8ef4100cdf384bc2f8f3f7b902bc83cee6c4bc36e82fbc666328b382de' "$TMP/first.contract"

# The mutable release producer must request the packed final-root asset.  The
# full-page output remains a useful generator reference, but the launcher no
# longer accepts it as launcher-base.xrgb.
grep -Fq '"--static-base-output",' \
	"$ROOT/kernel/rocknix/dev-release-tool.py"
if grep -Fq '"--xrgb-output",' \
	"$ROOT/kernel/rocknix/dev-release-tool.py"; then
	printf '%s\n' 'mutable release producer still requests the full-page XRGB asset' >&2
	exit 1
fi

printf '%s\n' 'launcher boot-frame contract tests: PASS'
