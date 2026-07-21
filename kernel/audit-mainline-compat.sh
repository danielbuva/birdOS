#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUTPUT=${1:-"$ROOT/kernel/work/mainline-compat"}
CONFIG="$OUTPUT/built.config"
DTS="$OUTPUT/built.dts"

fail() {
	printf 'compatibility audit: %s\n' "$*" >&2
	exit 1
}

require_config() {
	grep -qx "$1=$2" "$CONFIG" || fail "expected $1=$2"
}

for file in \
	Image \
	sun50i-h700-anbernic-rg34xx-sp-dani.dtb \
	built.config \
	built.dts \
	kernel.release \
	System.map \
	Module.symvers \
	modules.list \
	modules.tar.xz \
	sizes.txt \
	sha256sums.txt; do
	test -s "$OUTPUT/$file" || fail "missing or empty $file"
done

test "$(cat "$OUTPUT/kernel.release")" = '7.0.11-dani-compat' \
	|| fail 'unexpected kernel release'
! grep -q '@[^@]*@' "$CONFIG" \
	|| fail 'unexpanded configuration placeholder'
grep -qx 'CONFIG_DEFAULT_HOSTNAME="dani-sp"' "$CONFIG" \
	|| fail 'fixed hostname missing'
grep -qx 'CONFIG_INITRAMFS_SOURCE=""' "$CONFIG" \
	|| fail 'unexpected kernel-embedded initramfs'
grep -qx 'CONFIG_LOCALVERSION="-dani-compat"' "$CONFIG" \
	|| fail 'fixed local version missing'
grep -qx '# CONFIG_LOCALVERSION_AUTO is not set' "$CONFIG" \
	|| fail 'automatic SCM release suffix is enabled'
grep -qx 'CONFIG_EXTRA_FIRMWARE="panels/anbernic,rg34xx-sp-panel.panel"' \
	"$CONFIG" || fail 'fixed panel command stream is not embedded'

for symbol in \
	CONFIG_DRM_FBDEV_EMULATION \
	CONFIG_DRM_CLIENT_DEFAULT_FBDEV \
	CONFIG_DRM_PANEL_MIPI \
	CONFIG_DRM_PANFROST \
	CONFIG_DRM_SUN4I \
	CONFIG_DRM_SUN50I_PLANES \
	CONFIG_INPUT_EVDEV \
	CONFIG_JOYSTICK_ADC \
	CONFIG_KEYBOARD_GPIO \
	CONFIG_MFD_AXP20X \
	CONFIG_REGULATOR_AXP20X \
	CONFIG_CHARGER_AXP20X \
	CONFIG_BATTERY_AXP20X \
	CONFIG_AXP20X_ADC \
	CONFIG_RTC_DRV_PCF8563 \
	CONFIG_SND_SUN4I_CODEC \
	CONFIG_MMC_SUNXI \
	CONFIG_EXT4_FS \
	CONFIG_EXFAT_FS \
	CONFIG_USB_MUSB_SUNXI; do
	require_config "$symbol" y
done

# Bluetooth deliberately stays out of the boot-critical built-in image. The
# compatibility build still carries it as a module for a later on-demand path.
require_config CONFIG_BT m

grep -Fq 'Anbernic RG34XX-SP (Dani fixed device)' "$DTS" \
	|| fail 'fixed board model missing from DTB'
grep -Fq 'anbernic,rg34xx-sp-panel' "$DTS" \
	|| fail 'RG34XX-SP panel identity missing from DTB'
grep -Fq 'compatible = "adc-joystick"' "$DTS" \
	|| fail 'standard analog input node missing from DTB'
grep -Fq 'nxp,pcf8563' "$DTS" \
	|| fail 'external RTC node missing from DTB'

(
	cd "$OUTPUT"
	shasum -a 256 -c sha256sums.txt
)

printf 'Compatibility audit passed: %s\n' "$OUTPUT"
