#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BASE=${1:-$ROOT/firmware/work/direct-handoff-initramfs/bird-boot-trimmed-initramfs.img}
WORK=${2:-$ROOT/firmware/work/fixed-device-dtb-v1}
OUTPUT="$WORK/bird-boot-fixed-device-dtb-v1.img"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -f "$BASE" ] || fail "accepted direct-handoff image missing: $BASE"
[ "$(shasum -a 256 "$BASE" | awk '{print $1}')" = \
	"da5549e1cdad5b9f445f4634dacc0254fd468148182175a06b43346dc1dddbc7" ] || \
	fail "base is not the accepted direct-handoff image"
[ ! -e "$WORK" ] || fail "work directory already exists: $WORK"
mkdir -p "$WORK"

"$ROOT/firmware/unpack-boot.sh" "$BASE" "$WORK/base"
"$ROOT/firmware/set-fixed-device-dtb.sh" \
	"$WORK/base/device-tree.dtb" "$WORK/fixed-device-v1.dtb"
"$ROOT/firmware/repack-boot-dtb.sh" \
	"$BASE" "$WORK/fixed-device-v1.dtb" "$OUTPUT"
"$ROOT/firmware/unpack-boot.sh" "$OUTPUT" "$WORK/verify"

cmp "$WORK/base/kernel.img" "$WORK/verify/kernel.img"
cmp "$WORK/base/ramdisk.gz" "$WORK/verify/ramdisk.gz"
cmp "$WORK/fixed-device-v1.dtb" "$WORK/verify/device-tree.dtb"

while IFS= read -r NODE; do
	[ -n "$NODE" ] || continue
	[ "$(fdtget -t s "$WORK/verify/device-tree.dtb" "$NODE" status)" = \
		"disabled" ] || fail "repacked candidate enabled $NODE"
done <<'EOF'
/soc@03000000/usbc1@0
/soc@03000000/ehci1-controller@0x05200000
/soc@03000000/ohci1-controller@0x05200400
/soc@03000000/usbc2@0
/soc@03000000/ehci2-controller@0x05310000
/soc@03000000/ohci2-controller@0x05310400
/soc@03000000/usbc3@0
/soc@03000000/ehci3-controller@0x05311000
/soc@03000000/ohci3-controller@0x05311400
/soc@03000000/sdmmc@04022000
/soc@03000000/hdmi@06000000
/soc@03000000/hdmi_codec
/soc@03000000/ahub1_plat
/soc@03000000/ahub1_mach
/soc@03000000/tv0@01c94000
/soc@03000000/vind@0
/soc@03000000/deinterlace@0x01420000
/soc@03000000/bt
/soc@03000000/btlpm
/soc@03000000/uart@05000400
EOF

for NODE in \
	'/soc@03000000/disp@01000000' \
	'/soc@03000000/lcd0@01c0c000' \
	'/soc@03000000/sdmmc@04020000' \
	'/soc@03000000/sdmmc@04021000' \
	'/soc@03000000/wlan' \
	'/soc@03000000/codec@0x05096000' \
	'/soc@03000000/codec_mach' \
	'/soc@03000000/usbc0@0' \
	'/soc@03000000/udc-controller@0x05100000'; do
	[ "$(fdtget -t s "$WORK/verify/device-tree.dtb" "$NODE" status)" = \
		"okay" ] || fail "required node not preserved: $NODE"
done

[ "$(fdtget -t s "$WORK/verify/device-tree.dtb" \
	'/soc@03000000/lcd0@01c0c000' lcd_driver_name)" = "rg34xxsp_v1" ] || \
	fail "panel identity changed"
[ "$(stat -f %z "$OUTPUT")" -eq 67108864 ] || fail "candidate is not 64 MiB"

diff -u "$WORK/base/device-tree.dts" "$WORK/verify/device-tree.dts" > \
	"$WORK/device-tree.diff" || true
shasum -a 256 "$OUTPUT" >"$WORK/candidate.sha256"
printf 'Built and verified fixed-device DTB v1 candidate: %s\n' "$OUTPUT"
cat "$WORK/candidate.sha256"
