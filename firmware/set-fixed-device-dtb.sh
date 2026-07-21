#!/bin/sh
set -eu

INPUT=${1:-}
OUTPUT=${2:-}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -n "$INPUT" ] && [ -n "$OUTPUT" ] || \
	fail "usage: $0 INPUT_DTB OUTPUT_DTB"
[ -f "$INPUT" ] || fail "device tree not found: $INPUT"
[ "$INPUT" != "$OUTPUT" ] || fail "refusing to modify the source DTB in place"
[ ! -e "$OUTPUT" ] || fail "output already exists: $OUTPUT"
command -v fdtget >/dev/null 2>&1 || fail "fdtget is required"
command -v fdtput >/dev/null 2>&1 || fail "fdtput is required"

cp "$INPUT" "$OUTPUT"

# DANI_RG34XXSP_FIXED_DEVICE_DTB_V1
#
# Keep USB controller 0 for the USB-C device/charging path. Keep sdc0 for the
# only populated card and sdc1/WLAN for explicitly requested on-demand network.
# Internal display, input, PMIC, RTC, audio and GPU nodes are untouched.
while IFS= read -r NODE; do
	[ -n "$NODE" ] || continue
	OLD=$(fdtget -t s "$OUTPUT" "$NODE" status 2>/dev/null) || \
		fail "required node missing: $NODE"
	[ "$OLD" = "okay" ] || fail "expected okay status at $NODE; found $OLD"
	fdtput -t s "$OUTPUT" "$NODE" status disabled
	[ "$(fdtget -t s "$OUTPUT" "$NODE" status)" = "disabled" ] || \
		fail "could not disable $NODE"
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

printf 'Created RG34XX-SP fixed-device DTB v1: %s\n' "$OUTPUT"
