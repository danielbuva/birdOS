#!/bin/sh
# Rebuild the untrimmed ROCKNIX 20260701 H700 kernel from the exact stable
# source, executed patch order, shipping configuration, RG34XX-SP DTB and
# separately packaged H700 joypad driver.
# This is an offline artifact gate only; it never writes to removable media.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROCKNIX_SOURCE=${ROCKNIX_SOURCE:-$HOME/rocknix-distribution-20260701}
JOYPAD_SOURCE=${JOYPAD_SOURCE:-$HOME/muos-kernel-source/rocknix-joypad}
FIRMWARE_SOURCE=${FIRMWARE_SOURCE:-$HOME/muos-kernel-source/linux-firmware-20260309}
IMAGE=${BIRD_MAINLINE_BUILD_IMAGE:-sha256:aac053f343e057c6bb412cf4d6bab3090b6d050b94c80d60e86a6d794185f460}
OUTPUT=${OUTPUT:-$ROOT/kernel/work/rocknix-source-reference}
BUILD_OUTPUT="$OUTPUT/build"
SHIPPING_KERNEL=${SHIPPING_KERNEL:-$OUTPUT/shipping-KERNEL}
INITRAMFS_ARCHIVE=${INITRAMFS_ARCHIVE:-$ROOT/kernel/work/rocknix-official-initramfs-20260701/rocknix-initramfs.cpio}
DEFER_PANFROST=${DEFER_PANFROST:-0}
BUILTIN_JOYPAD=${BUILTIN_JOYPAD:-0}
SINGLE_GPIO_READ=${SINGLE_GPIO_READ:-0}
SINGLE_INPUT_SYNC=${SINGLE_INPUT_SYNC:-0}
CHANGED_INPUT_SYNC=${CHANGED_INPUT_SYNC:-0}
FIXED_GPIO_FASTPATH=${FIXED_GPIO_FASTPATH:-0}
IRQ_GPIO_BUTTONS=${IRQ_GPIO_BUTTONS:-0}
SKIP_RAID6_BENCHMARK=${SKIP_RAID6_BENCHMARK:-0}
IRQ_GPIO_TRANSFORM=$ROOT/kernel/rocknix/transform-joypad-irq.py
JOBS=${JOBS:-4}

ROCKNIX_COMMIT=3e4ee5852e6ca5ea73a38369d2639fad2262648b
LINUX_COMMIT=bb532bfaf7919c7c98caab81864e9ce2646e11e3
JOYPAD_COMMIT=7647fdb0fc89cd69b284903bf7707e861df5dc7e
SHIPPING_KERNEL_SHA=af4e75cb30b097ee5764764eb056d686bc00c6bd03fefece26b0ebbaa7fbb673
SHIPPING_DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
SHIPPING_DTB_BYTES=49010
INITRAMFS_ARCHIVE_SHA=5d2b7b247bfa78db7b1fad490e0c5cdc70ec31af18cac743aee4dc1027d66045
PATCH_COUNT=30

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

command -v docker >/dev/null 2>&1 || fail 'docker is required'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
case "$DEFER_PANFROST" in
	0 | 1) ;;
	*) fail 'DEFER_PANFROST must be 0 or 1' ;;
esac
case "$BUILTIN_JOYPAD" in
	0 | 1) ;;
	*) fail 'BUILTIN_JOYPAD must be 0 or 1' ;;
esac
case "$SINGLE_GPIO_READ" in
	0 | 1) ;;
	*) fail 'SINGLE_GPIO_READ must be 0 or 1' ;;
esac
[ "$SINGLE_GPIO_READ" -eq 0 ] || [ "$BUILTIN_JOYPAD" -eq 1 ] || \
	fail 'SINGLE_GPIO_READ requires BUILTIN_JOYPAD=1'
case "$SINGLE_INPUT_SYNC" in
	0 | 1) ;;
	*) fail 'SINGLE_INPUT_SYNC must be 0 or 1' ;;
esac
[ "$SINGLE_INPUT_SYNC" -eq 0 ] || [ "$SINGLE_GPIO_READ" -eq 1 ] || \
	fail 'SINGLE_INPUT_SYNC requires SINGLE_GPIO_READ=1'
case "$CHANGED_INPUT_SYNC" in
	0 | 1) ;;
	*) fail 'CHANGED_INPUT_SYNC must be 0 or 1' ;;
esac
[ "$CHANGED_INPUT_SYNC" -eq 0 ] || [ "$SINGLE_INPUT_SYNC" -eq 1 ] || \
	fail 'CHANGED_INPUT_SYNC requires SINGLE_INPUT_SYNC=1'
case "$FIXED_GPIO_FASTPATH" in
	0 | 1) ;;
	*) fail 'FIXED_GPIO_FASTPATH must be 0 or 1' ;;
esac
[ "$FIXED_GPIO_FASTPATH" -eq 0 ] || [ "$CHANGED_INPUT_SYNC" -eq 1 ] || \
	fail 'FIXED_GPIO_FASTPATH requires CHANGED_INPUT_SYNC=1'
case "$IRQ_GPIO_BUTTONS" in
	0 | 1) ;;
	*) fail 'IRQ_GPIO_BUTTONS must be 0 or 1' ;;
esac
[ "$IRQ_GPIO_BUTTONS" -eq 0 ] || [ "$FIXED_GPIO_FASTPATH" -eq 1 ] || \
	fail 'IRQ_GPIO_BUTTONS requires FIXED_GPIO_FASTPATH=1'
case "$SKIP_RAID6_BENCHMARK" in
	0 | 1) ;;
	*) fail 'SKIP_RAID6_BENCHMARK must be 0 or 1' ;;
esac
[ "$SKIP_RAID6_BENCHMARK" -eq 0 ] || [ "$IRQ_GPIO_BUTTONS" -eq 1 ] || \
	fail 'SKIP_RAID6_BENCHMARK requires IRQ_GPIO_BUTTONS=1'
[ -f "$IRQ_GPIO_TRANSFORM" ] || fail 'joypad IRQ transform helper is missing'
[ -d "$ROCKNIX_SOURCE/.git" ] || fail "ROCKNIX source missing: $ROCKNIX_SOURCE"
[ "$(git -C "$ROCKNIX_SOURCE" rev-parse HEAD)" = "$ROCKNIX_COMMIT" ] || \
	fail 'ROCKNIX source commit mismatch'
[ -z "$(git -C "$ROCKNIX_SOURCE" status --short)" ] || \
	fail 'ROCKNIX source is not clean'
[ -d "$JOYPAD_SOURCE/.git" ] || fail "ROCKNIX joypad source missing: $JOYPAD_SOURCE"
[ "$(git -C "$JOYPAD_SOURCE" rev-parse HEAD)" = "$JOYPAD_COMMIT" ] || \
	fail 'ROCKNIX joypad source commit mismatch'
[ -z "$(git -C "$JOYPAD_SOURCE" status --short)" ] || \
	fail 'ROCKNIX joypad source is not clean'
[ -f "$SHIPPING_KERNEL" ] || fail "shipping KERNEL oracle missing: $SHIPPING_KERNEL"
[ "$(shasum -a 256 "$SHIPPING_KERNEL" | awk '{print $1}')" = \
	"$SHIPPING_KERNEL_SHA" ] || fail 'shipping KERNEL checksum mismatch'

while IFS="$(printf '\t')" read -r firmware expected; do
	[ -f "$FIRMWARE_SOURCE/$firmware" ] &&
		[ ! -L "$FIRMWARE_SOURCE/$firmware" ] ||
		fail "required shipping firmware missing or unsafe: $FIRMWARE_SOURCE/$firmware"
	[ "$(sha256 "$FIRMWARE_SOURCE/$firmware")" = "$expected" ] ||
		fail "required shipping firmware changed: $firmware"
done <<'EOF'
rtl_bt/rtl8821cs_config.bin	6ddeb15f23588053e00cb08d25588bd7cf98d60fa93d9478efcef4ae8064a7ac
rtl_bt/rtl8821cs_fw.bin	3baa2eeaa43c959054687a67771e7435e73b2ff3e79dfb765121d8b7dc719391
rtw88/rtw8821c_fw.bin	2ef409bc418549fcf294061dd0cae1fc22fd9da79b60524950b25de18732f3f0
EOF

CONTAINER_IMAGE_ID=$(docker image inspect --format '{{.Id}}' "$IMAGE") ||
	fail 'pinned source-kernel build image is unavailable'
[ "$CONTAINER_IMAGE_ID" = \
	sha256:aac053f343e057c6bb412cf4d6bab3090b6d050b94c80d60e86a6d794185f460 ] ||
	fail 'source-kernel build image identity changed'

mkdir -p "$BUILD_OUTPUT"
find "$BUILD_OUTPUT" -mindepth 1 -depth -delete

INITRAMFS_CONFIG=
if [ -n "$INITRAMFS_ARCHIVE" ]; then
	case "$INITRAMFS_ARCHIVE" in
	/*) ;;
	*) INITRAMFS_ARCHIVE="$PWD/$INITRAMFS_ARCHIVE" ;;
	esac
	[ -f "$INITRAMFS_ARCHIVE" ] || \
		fail "Bird initramfs archive missing: $INITRAMFS_ARCHIVE"
	[ ! -L "$INITRAMFS_ARCHIVE" ] || \
		fail "Bird initramfs archive is a symlink: $INITRAMFS_ARCHIVE"
	[ "$(sha256 "$INITRAMFS_ARCHIVE")" = "$INITRAMFS_ARCHIVE_SHA" ] || \
		fail 'official embedded initramfs digest changed'
	INITRAMFS_CONFIG=/bird-initramfs.cpio
	shasum -a 256 "$INITRAMFS_ARCHIVE" >"$BUILD_OUTPUT/input-initramfs.sha256"
else
	printf '%s\n' 'none  no-embedded-initramfs' \
		>"$BUILD_OUTPUT/input-initramfs.sha256"
fi

set -- docker run --rm --platform linux/arm64 \
	-e JOBS="$JOBS" \
	-e LINUX_COMMIT="$LINUX_COMMIT" \
	-e JOYPAD_COMMIT="$JOYPAD_COMMIT" \
	-e INITRAMFS_CONFIG="$INITRAMFS_CONFIG" \
	-e DEFER_PANFROST="$DEFER_PANFROST" \
	-e BUILTIN_JOYPAD="$BUILTIN_JOYPAD" \
	-e SINGLE_GPIO_READ="$SINGLE_GPIO_READ" \
	-e SINGLE_INPUT_SYNC="$SINGLE_INPUT_SYNC" \
	-e CHANGED_INPUT_SYNC="$CHANGED_INPUT_SYNC" \
	-e FIXED_GPIO_FASTPATH="$FIXED_GPIO_FASTPATH" \
	-e IRQ_GPIO_BUTTONS="$IRQ_GPIO_BUTTONS" \
	-e SKIP_RAID6_BENCHMARK="$SKIP_RAID6_BENCHMARK" \
	-e LOCALVERSION= \
	-v "$ROCKNIX_SOURCE:/rocknix:ro" \
	-v "$JOYPAD_SOURCE:/rocknix-joypad:ro" \
	-v "$FIRMWARE_SOURCE:/shipping-firmware:ro" \
	-v "$SHIPPING_KERNEL:/shipping-KERNEL:ro" \
	-v "$IRQ_GPIO_TRANSFORM:/bird-transform-joypad-irq.py:ro" \
	-v "$BUILD_OUTPUT:/out"
if [ -n "$INITRAMFS_ARCHIVE" ]; then
	set -- "$@" -v "$INITRAMFS_ARCHIVE:/bird-initramfs.cpio:ro"
fi
set -- "$@" "$IMAGE" sh -eu -c '
		export KBUILD_BUILD_USER=bird
		export KBUILD_BUILD_HOST=rg34xxsp
		export KBUILD_BUILD_VERSION=1
		export KBUILD_BUILD_TIMESTAMP="2026-07-01 04:53:00 UTC"
		export SOURCE_DATE_EPOCH=1782881580
		cd /src/linux
		git reset --hard "$LINUX_COMMIT" >/dev/null
		git clean -fdx >/dev/null
		test "$(git rev-parse HEAD)" = "$LINUX_COMMIT"

		: > /out/applied-patches.txt
		for group in \
			/rocknix/projects/ROCKNIX/packages/linux/patches/mainline \
			/rocknix/projects/ROCKNIX/packages/linux/patches/7.0 \
			/rocknix/projects/ROCKNIX/devices/H700/patches/linux; do
			for item in "$group"/*.patch; do
				test -f "$item"
				printf "%s  %s\n" \
					"$(sha256sum "$item" | awk "{print \$1}")" \
					"${item#/rocknix/}" >> /out/applied-patches.txt
				sed -e "s#@TARGET_CPU@#cortex-a53#g" \
					-e "s#@DEVICE@#H700#g" "$item" | patch -s -p1
			done
		done

		rsync -a \
			/rocknix/projects/ROCKNIX/devices/H700/linux/dts/ \
			arch/arm64/boot/dts/

		# RG34XX-SP is the only target. In the Stage 9 candidate, link the
		# already pinned H700 input driver into the kernel so device-init can
		# register it before initramfs userspace instead of spawning insmod on
		# the menu-critical path. Keep producing the exact external module as
		# a build oracle until the physical candidate is accepted.
		if [ "$BUILTIN_JOYPAD" = 1 ]; then
			cp /rocknix-joypad/rocknix-singleadc-joypad.c \
				drivers/input/joystick/rocknix-singleadc-joypad.c
			cp /rocknix-joypad/rocknix-joypad.h \
				drivers/input/joystick/rocknix-joypad.h
			printf "%s\n" "obj-y += rocknix-singleadc-joypad.o" \
				>> drivers/input/joystick/Makefile
			if [ "$SINGLE_GPIO_READ" = 1 ]; then
				python3 - drivers/input/joystick/rocknix-singleadc-joypad.c <<"PY"
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = """\t\tif (gpio_get_value_cansleep(gpio->num) < 0) {
\t\t\tdev_err(joypad->dev, "failed to get gpio state\\n");
\t\t\tcontinue;
\t\t}
\t\tvalue = gpio_get_value_cansleep(gpio->num);
"""
new = """\t\tvalue = gpio_get_value_cansleep(gpio->num);
\t\tif (value < 0) {
\t\t\tdev_err(joypad->dev, "failed to get gpio state\\n");
\t\t\tcontinue;
\t\t}
"""
if source.count(old) != 1:
    raise SystemExit("joypad GPIO poll authority changed")
path.write_text(source.replace(old, new), encoding="utf-8")
PY
				[ "$(grep -Fc "gpio_get_value_cansleep(gpio->num)" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 2 ]
				[ "$(grep -Fc "joypad_adc_check(poll_dev);" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 2 ]
			fi
			if [ "$SINGLE_INPUT_SYNC" = 1 ]; then
				python3 - drivers/input/joystick/rocknix-singleadc-joypad.c <<"PY"
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old_gpio = """\t}
\tinput_sync(poll_dev->input);
}

/*----------------------------------------------------------------------------*/
static void joypad_adc_check"""
new_gpio = """\t}
}

/*----------------------------------------------------------------------------*/
static void joypad_adc_check"""
old_adc = """\t}
\tinput_sync(poll_dev->input);
}

/*----------------------------------------------------------------------------*/
static void joypad_poll"""
new_adc = """\t}
}

/*----------------------------------------------------------------------------*/
static void joypad_poll"""
old_poll = """\t\t\tinput_report_abs(poll_dev->input, ABS_RY, joypad->miyoo.right_y);
\t\t\tinput_sync(poll_dev->input);

\t\t\tjoypad_gpio_check(poll_dev);
\t\t} else {
\t\t\tjoypad_adc_check(poll_dev);
\t\t\tjoypad_gpio_check(poll_dev);
\t\t}
\t}
"""
new_poll = """\t\t\tinput_report_abs(poll_dev->input, ABS_RY, joypad->miyoo.right_y);

\t\t\tjoypad_gpio_check(poll_dev);
\t\t} else {
\t\t\tjoypad_adc_check(poll_dev);
\t\t\tjoypad_gpio_check(poll_dev);
\t\t}
\t\tinput_sync(poll_dev->input);
\t}
"""
old_open = """\tjoypad_adc_check(poll_dev);
\tjoypad_gpio_check(poll_dev);

\t/* button report enable */"""
new_open = """\tjoypad_adc_check(poll_dev);
\tjoypad_gpio_check(poll_dev);
\tinput_sync(poll_dev->input);

\t/* button report enable */"""
for old, new, label in (
    (old_gpio, new_gpio, "GPIO helper sync"),
    (old_adc, new_adc, "ADC helper sync"),
    (old_poll, new_poll, "poll frame"),
    (old_open, new_open, "open frame"),
):
    if source.count(old) != 1:
        raise SystemExit(f"joypad {label} authority changed")
    source = source.replace(old, new)
path.write_text(source, encoding="utf-8")
PY
				[ "$(grep -Fc "input_sync(poll_dev->input);" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 3 ]
				[ "$(grep -Fc "joypad_adc_check(poll_dev);" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 2 ]
			fi
			if [ "$CHANGED_INPUT_SYNC" = 1 ]; then
				python3 - drivers/input/joystick/rocknix-singleadc-joypad.c <<"PY"
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
replacements = (
    (
        "static void joypad_gpio_check(struct input_polled_dev *poll_dev)\n{\n"
        "\tstruct joypad *joypad = poll_dev->private;\n\tint nbtn, value;",
        "static bool joypad_gpio_check(struct input_polled_dev *poll_dev)\n{\n"
        "\tstruct joypad *joypad = poll_dev->private;\n"
        "\tbool changed = false;\n\tint nbtn, value;",
        "GPIO change result declaration",
    ),
    (
        "\t\tif (value != gpio->old_value) {\n\t\t\tinput_event(poll_dev->input,",
        "\t\tif (value != gpio->old_value) {\n\t\t\tchanged = true;\n"
        "\t\t\tinput_event(poll_dev->input,",
        "GPIO changed flag",
    ),
    (
        "\t}\n}\n\n/*----------------------------------------------------------------------------*/\n"
        "static void joypad_adc_check",
        "\t}\n\treturn changed;\n}\n\n"
        "/*----------------------------------------------------------------------------*/\nstatic bool joypad_adc_check",
        "GPIO return and ADC signature",
    ),
    (
        "\tstruct joypad *joypad = poll_dev->private;\n\tint nbtn;\n\tint mag;\n\n"
        "\t/* Assumes an even number of axes",
        "\tstruct joypad *joypad = poll_dev->private;\n"
        "\tbool changed = false;\n\tint nbtn;\n\tint mag;\n\tint old_value;\n\n"
        "\t/* Assumes an even number of axes",
        "ADC change result declaration",
    ),
    (
        "\t\tinput_report_abs(poll_dev->input,\n"
        "\t\t\tadcx->report_type,\n"
        "\t\t\tadcx->invert ? adcx->value * (-1) : adcx->value);\n"
        "\t\tinput_report_abs(poll_dev->input,\n"
        "\t\t\tadcy->report_type,\n"
        "\t\t\tadcy->invert ? adcy->value * (-1) : adcy->value);",
        "\t\told_value = input_abs_get_val(poll_dev->input, adcx->report_type);\n"
        "\t\tinput_report_abs(poll_dev->input,\n"
        "\t\t\tadcx->report_type,\n"
        "\t\t\tadcx->invert ? adcx->value * (-1) : adcx->value);\n"
        "\t\tchanged |= input_abs_get_val(poll_dev->input, adcx->report_type) != old_value;\n"
        "\t\told_value = input_abs_get_val(poll_dev->input, adcy->report_type);\n"
        "\t\tinput_report_abs(poll_dev->input,\n"
        "\t\t\tadcy->report_type,\n"
        "\t\t\tadcy->invert ? adcy->value * (-1) : adcy->value);\n"
        "\t\tchanged |= input_abs_get_val(poll_dev->input, adcy->report_type) != old_value;",
        "ADC accepted-value change tracking",
    ),
    (
        "\t}\n}\n\n/*----------------------------------------------------------------------------*/\n"
        "static void joypad_poll",
        "\t}\n\treturn changed;\n}\n\n"
        "/*----------------------------------------------------------------------------*/\nstatic void joypad_poll",
        "ADC return",
    ),
    (
        "\tstruct joypad *joypad = poll_dev->private;\n\n\tif (joypad->enable) {",
        "\tstruct joypad *joypad = poll_dev->private;\n"
        "\tbool changed = false;\n\tint old_value;\n\n\tif (joypad->enable) {",
        "poll change declaration",
    ),
)
for old, new, label in replacements:
    if source.count(old) != 1:
        raise SystemExit(f"joypad {label} authority changed")
    source = source.replace(old, new)

for code, spacing, expression in (
    ("ABS_X", "  ", "joypad->miyoo.left_x"),
    ("ABS_Y", "  ", "joypad->miyoo.left_y"),
    ("ABS_RX", " ", "joypad->miyoo.right_x"),
    ("ABS_RY", " ", "joypad->miyoo.right_y"),
):
    old = f"\t\t\tinput_report_abs(poll_dev->input, {code},{spacing}{expression});"
    new = (
        f"\t\t\told_value = input_abs_get_val(poll_dev->input, {code});\n"
        f"\t\t\tinput_report_abs(poll_dev->input, {code}, {expression});\n"
        f"\t\t\tchanged |= input_abs_get_val(poll_dev->input, {code}) != old_value;"
    )
    if source.count(old) != 1:
        raise SystemExit(f"joypad {code} change tracking authority changed")
    source = source.replace(old, new)

for old, new, label in (
    ("\t\t\tjoypad_gpio_check(poll_dev);\n\t\t} else {",
     "\t\t\tchanged |= joypad_gpio_check(poll_dev);\n\t\t} else {",
     "serial GPIO result"),
    ("\t\t\tjoypad_adc_check(poll_dev);\n\t\t\tjoypad_gpio_check(poll_dev);",
     "\t\t\tchanged |= joypad_adc_check(poll_dev);\n"
     "\t\t\tchanged |= joypad_gpio_check(poll_dev);",
     "ADC/GPIO results"),
    ("\t\tinput_sync(poll_dev->input);\n\t}",
     "\t\tif (changed)\n\t\t\tinput_sync(poll_dev->input);\n\t}",
     "conditional poll sync"),
):
    if source.count(old) != 1:
        raise SystemExit(f"joypad {label} authority changed")
    source = source.replace(old, new)

path.write_text(source, encoding="utf-8")
PY
				[ "$(grep -Fc "if (changed)" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 1 ]
				[ "$(grep -Fc "input_abs_get_val(poll_dev->input" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 12 ]
			fi
			if [ "$FIXED_GPIO_FASTPATH" = 1 ]; then
				python3 - drivers/input/joystick/rocknix-singleadc-joypad.c <<"PY"
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old_read = "gpio_get_value_cansleep(gpio->num)"
if source.count(old_read) != 2:
    raise SystemExit("joypad fixed GPIO access authority changed")
source = source.replace(old_read, "gpio_get_value(gpio->num)")

old_open = """\t}
\tinput_sync(poll_dev->input);

\tfor (nbtn = 0; nbtn < joypad->amux_count; nbtn++) {"""
new_open = """\t}

\tfor (nbtn = 0; nbtn < joypad->amux_count; nbtn++) {"""
if source.count(old_open) != 1:
    raise SystemExit("joypad open frame authority changed")
source = source.replace(old_open, new_open)
path.write_text(source, encoding="utf-8")
PY
				[ "$(grep -Fc "gpio_get_value(gpio->num)" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 2 ]
				[ "$(grep -Fc "gpio_get_value_cansleep(gpio->num)" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 0 ]
				[ "$(grep -Fc "input_sync(poll_dev->input);" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 2 ]
			fi
			if [ "$IRQ_GPIO_BUTTONS" = 1 ]; then
				python3 /bird-transform-joypad-irq.py \
					--expected-buttons 17 \
					drivers/input/joystick/rocknix-singleadc-joypad.c
				[ "$(grep -Fc "IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 1 ]
				[ "$(grep -Fc "joypad_adc_check(poll_dev, true);" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 1 ]
				[ "$(grep -Fc "joypad_gpio_check(poll_dev)" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 0 ]
				[ "$(grep -Fc "BIRD_FIXED_GPIO_BUTTONS 17" \
					drivers/input/joystick/rocknix-singleadc-joypad.c)" -eq 1 ]
			fi
		fi

		mkdir -p external-firmware/panels external-firmware/rtl_bt \
			external-firmware/rtw88
		cp -L \
			/rocknix/projects/ROCKNIX/packages/linux-firmware/kernel-firmware/extra-firmware/panels/* \
			external-firmware/panels/
		cp -L /shipping-firmware/rtl_bt/rtl8821cs_config.bin \
			/shipping-firmware/rtl_bt/rtl8821cs_fw.bin \
			external-firmware/rtl_bt/
		cp -L /shipping-firmware/rtw88/rtw8821c_fw.bin \
			external-firmware/rtw88/

		/src/linux/scripts/extract-ikconfig /shipping-KERNEL \
			> /out/shipping.config
		cp /out/shipping.config .config
		scripts/config --file .config --set-str CONFIG_INITRAMFS_SOURCE \
			"$INITRAMFS_CONFIG"
		scripts/config --file .config --set-str CONFIG_EXTRA_FIRMWARE_DIR \
			"external-firmware"
		# Btrfs retains RAID6 support.  The fixed Cortex-A53 target does not
		# need to spend roughly half a second benchmarking every parity
		# implementation: with benchmarking disabled, upstream selects the
		# first highest-priority valid implementation, NEONx8 on this build.
		if [ "$SKIP_RAID6_BENCHMARK" = 1 ]; then
			scripts/config --file .config --disable CONFIG_RAID6_PQ_BENCHMARK
		fi
		if [ "$DEFER_PANFROST" = 1 ]; then
			scripts/config --file .config --module CONFIG_DRM_PANFROST
		fi
		make ARCH=arm64 olddefconfig >/dev/null
		cp .config /out/built.config
		gcc --version | head -1 > /out/compiler.txt
		make -s ARCH=arm64 kernelrelease > /out/kernel.release

		make -j"$JOBS" ARCH=arm64 DTC_FLAGS=-@ \
			allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb
		cp arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb \
			/out/
		scripts/dtc/dtc -q -I dtb -O dts \
			-o /out/built.dts \
			arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb

		make -j"$JOBS" ARCH=arm64 DTC_FLAGS=-@ Image modules
		cp arch/arm64/boot/Image /out/Image
		if [ "$DEFER_PANFROST" = 1 ]; then
			cp drivers/gpu/drm/drm_shmem_helper.ko \
				/out/drm_shmem_helper.ko
			cp drivers/gpu/drm/scheduler/gpu-sched.ko \
				/out/gpu-sched.ko
			cp drivers/gpu/drm/panfrost/panfrost.ko /out/panfrost.ko
		fi
		cp System.map Module.symvers /out/
		mkdir -p /tmp/rocknix-joypad
		cp /rocknix-joypad/Makefile /rocknix-joypad/*.c \
			/rocknix-joypad/*.h /tmp/rocknix-joypad/
		make -j"$JOBS" ARCH=arm64 DEVICE=H700 \
			-C /src/linux M=/tmp/rocknix-joypad modules
		cp /tmp/rocknix-joypad/rocknix-singleadc-joypad.ko /out/
		printf "%s\n" "$JOYPAD_COMMIT" > /out/joypad.commit
		make ARCH=arm64 INSTALL_MOD_PATH=/tmp/reference-modules modules_install >/dev/null
		find /tmp/reference-modules/lib/modules -type l \
			\( -name build -o -name source \) -delete
		find /tmp/reference-modules -type f -print | LC_ALL=C sort \
			> /out/modules.list
		tar --sort=name --mtime="@1784617200" --owner=0 --group=0 \
			--numeric-owner --format=gnu -C /tmp/reference-modules -cJf \
			/out/modules.tar.xz .
'
"$@"

if [ "$BUILTIN_JOYPAD" = 1 ]; then
	grep -Eq '[[:space:]][tT][[:space:]]+joypad_init$' \
		"$BUILD_OUTPUT/System.map" || fail 'built-in H700 input initcall missing'
	strings "$BUILD_OUTPUT/Image" | grep -Fqx 'rocknix-singleadc-joypad' || \
		fail 'built-in H700 input identity missing from Image'
fi
[ "$(wc -l < "$BUILD_OUTPUT/applied-patches.txt" | tr -d ' ')" -eq \
	"$PATCH_COUNT" ] || fail 'executed patch count mismatch'

DTB="$BUILD_OUTPUT/sun50i-h700-anbernic-rg34xx-sp.dtb"
[ "$(stat -f %z "$DTB")" -eq "$SHIPPING_DTB_BYTES" ] || \
	fail 'source-built RG34XX-SP DTB size differs from shipping'
[ "$(shasum -a 256 "$DTB" | awk '{print $1}')" = "$SHIPPING_DTB_SHA" ] || \
	fail 'source-built RG34XX-SP DTB differs from shipping'

JOYPAD_MODULE="$BUILD_OUTPUT/rocknix-singleadc-joypad.ko"
strings "$JOYPAD_MODULE" | grep -Fqx \
	'vermagic=7.0.11 SMP preempt mod_unload modversions aarch64' || \
	fail 'H700 joypad module vermagic mismatch'
strings "$JOYPAD_MODULE" | grep -Fqx 'depends=' || \
	fail 'H700 joypad module gained a module dependency'
strings "$JOYPAD_MODULE" | grep -Fqx \
	'alias=of:N*T*Crocknix-singleadc-joypad' || \
	fail 'H700 joypad module DT alias missing'

python3 - "$BUILD_OUTPUT/shipping.config" "$BUILD_OUTPUT/built.config" \
	"$BUILD_OUTPUT/config-diff.txt" "$DEFER_PANFROST" \
	"$SKIP_RAID6_BENCHMARK" <<'PY'
import re
import sys

(
    oracle_path,
    built_path,
    report_path,
    defer_panfrost_arg,
    skip_raid6_benchmark_arg,
) = sys.argv[1:]
defer_panfrost = defer_panfrost_arg == "1"
skip_raid6_benchmark = skip_raid6_benchmark_arg == "1"

def symbols(path):
    result = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            match = re.match(r"(CONFIG_[A-Z0-9_]+)=", line)
            if match:
                result[match.group(1)] = line
                continue
            match = re.match(r"# (CONFIG_[A-Z0-9_]+) is not set$", line)
            if match:
                result[match.group(1)] = line
    return result

oracle = symbols(oracle_path)
built = symbols(built_path)
changed = []
for name in sorted(set(oracle) | set(built)):
    if oracle.get(name) != built.get(name):
        changed.append((name, oracle.get(name, "<missing>"), built.get(name, "<missing>")))

allowed = re.compile(
    r"^CONFIG_(?:INITRAMFS_.*|EXTRA_FIRMWARE_DIR|CC_VERSION_TEXT|GCC_.*|CLANG_VERSION|"
    r"AS_VERSION|LD_VERSION|LLD_VERSION|RUSTC_VERSION|RUSTC_LLVM_VERSION|"
    r"PAHOLE_VERSION|CC_HAS_.*|AS_HAS_.*|LD_CAN_.*|TOOLS_SUPPORT_.*|"
    r"KSTACK_ERASE|RANDSTRUCT_.*)$"
)
def is_allowed(name):
    return bool(allowed.match(name)) or (
        defer_panfrost and name in {
            "CONFIG_DRM_GEM_SHMEM_HELPER",
            "CONFIG_DRM_PANFROST",
            "CONFIG_DRM_SCHED",
        }
    ) or (
        skip_raid6_benchmark and name == "CONFIG_RAID6_PQ_BENCHMARK"
    )

unexpected = [entry for entry in changed if not is_allowed(entry[0])]

with open(report_path, "w", encoding="utf-8") as report:
    for name, old, new in changed:
        status = "allowed-fixed-profile-change" if is_allowed(name) else "UNEXPECTED"
        report.write(f"{status}: {name}\n  shipping: {old}\n  rebuilt:  {new}\n")

if unexpected:
    for name, old, new in unexpected:
        print(f"unexpected config drift: {name}\n  shipping: {old}\n  rebuilt:  {new}", file=sys.stderr)
    raise SystemExit(1)
PY

if [ "$SKIP_RAID6_BENCHMARK" = 1 ]; then
	grep -qx '# CONFIG_RAID6_PQ_BENCHMARK is not set' \
		"$BUILD_OUTPUT/built.config" || \
		fail 'RAID6 benchmark remains enabled'
	grep -qx 'CONFIG_RAID6_PQ=y' "$BUILD_OUTPUT/built.config" || \
		fail 'RAID6 parity support changed'
	grep -qx 'CONFIG_BTRFS_FS=y' "$BUILD_OUTPUT/built.config" || \
		fail 'Btrfs support changed'
	grep -Eq '[[:space:]][tT][[:space:]]+raid6_select_algo$' \
		"$BUILD_OUTPUT/System.map" || \
		fail 'RAID6 algorithm selection disappeared'
	strings "$BUILD_OUTPUT/Image" | \
		grep -Fq 'raid6: skipped pq benchmark and selected %s' || \
		fail 'non-benchmark RAID6 selection path is absent'
fi

PANFROST_ARTIFACT=
if [ "$DEFER_PANFROST" = 1 ]; then
	PANFROST_MODULE="$BUILD_OUTPUT/panfrost.ko"
	DRM_SHMEM_MODULE="$BUILD_OUTPUT/drm_shmem_helper.ko"
	GPU_SCHED_MODULE="$BUILD_OUTPUT/gpu-sched.ko"
	grep -qx 'CONFIG_DRM_PANFROST=m' "$BUILD_OUTPUT/built.config" || \
		fail 'Panfrost was not made a deferred module'
	for MODULE in "$DRM_SHMEM_MODULE" "$GPU_SCHED_MODULE" \
		"$PANFROST_MODULE"; do
		[ -f "$MODULE" ] || fail "deferred GPU module is missing: $MODULE"
		strings "$MODULE" | grep -Fqx \
			'vermagic=7.0.11 SMP preempt mod_unload modversions aarch64' || \
			fail "deferred GPU module vermagic mismatch: $MODULE"
	done
	strings "$PANFROST_MODULE" | grep -Fqx \
		'depends=gpu-sched,drm_shmem_helper' || \
		fail 'deferred Panfrost dependency set changed'
	PANFROST_ARTIFACT='drm_shmem_helper.ko gpu-sched.ko panfrost.ko'
else
	grep -qx 'CONFIG_DRM_PANFROST=y' "$BUILD_OUTPUT/built.config" || \
		fail 'shipping Panfrost configuration changed'
fi

if [ -n "$INITRAMFS_ARCHIVE" ]; then
	python3 - "$BUILD_OUTPUT/Image" "$INITRAMFS_ARCHIVE" \
		"$BUILD_OUTPUT/embedded-initramfs.txt" <<'PY'
import hashlib
import sys
import zlib

image_path, archive_path, report_path = sys.argv[1:]
image = open(image_path, "rb").read()
archive = open(archive_path, "rb").read()
expected = hashlib.sha256(archive).hexdigest()
offsets = []
position = 0
while True:
    position = image.find(b"\x1f\x8b\x08", position)
    if position < 0:
        break
    offsets.append(position)
    position += 1

match = None
for offset in offsets:
    try:
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        unpacked = decoder.decompress(image[offset:]) + decoder.flush()
    except zlib.error:
        continue
    if decoder.eof and hashlib.sha256(unpacked).hexdigest() == expected:
        match = (offset, len(unpacked))
        break

if match is None:
    raise SystemExit("embedded Bird initramfs does not reproduce its input archive")
with open(report_path, "w", encoding="utf-8") as report:
    report.write(f"gzip_offset={match[0]}\n")
    report.write(f"uncompressed_bytes={match[1]}\n")
    report.write(f"uncompressed_sha256={expected}\n")
PY
else
	printf '%s\n' 'none' >"$BUILD_OUTPUT/embedded-initramfs.txt"
fi

(
	cd "$BUILD_OUTPUT"
	wc -c Image sun50i-h700-anbernic-rg34xx-sp.dtb modules.tar.xz \
		rocknix-singleadc-joypad.ko $PANFROST_ARTIFACT >sizes.txt
)
(
	cd "$BUILD_OUTPUT"
	shasum -a 256 \
		Image \
		sun50i-h700-anbernic-rg34xx-sp.dtb \
		shipping.config \
		built.config \
		built.dts \
		compiler.txt \
		kernel.release \
		System.map \
		Module.symvers \
		rocknix-singleadc-joypad.ko \
		$PANFROST_ARTIFACT \
		joypad.commit \
		modules.list \
		modules.tar.xz \
		applied-patches.txt \
		config-diff.txt \
		embedded-initramfs.txt \
		input-initramfs.sha256 \
		sizes.txt > sha256sums.txt
)

{
	printf 'schema\tbird-source-kernel-parity-v1\n'
	printf 'container-image-id\t%s\n' "$CONTAINER_IMAGE_ID"
	printf 'rocknix-commit\t%s\n' "$ROCKNIX_COMMIT"
	printf 'linux-commit\t%s\n' "$LINUX_COMMIT"
	printf 'joypad-commit\t%s\n' "$JOYPAD_COMMIT"
	if [ "$BUILTIN_JOYPAD" = 1 ]; then
		printf 'joypad-linkage\tbuiltin\n'
	fi
	if [ "$SINGLE_GPIO_READ" = 1 ]; then
		printf 'joypad-policy\tsingle-gpio-read\n'
	fi
	if [ "$SINGLE_INPUT_SYNC" = 1 ]; then
		printf 'joypad-event-policy\tsingle-poll-sync\n'
	fi
	if [ "$CHANGED_INPUT_SYNC" = 1 ]; then
		printf 'joypad-idle-policy\tchanged-input-sync\n'
	fi
	if [ "$FIXED_GPIO_FASTPATH" = 1 ]; then
		printf 'joypad-gpio-access\tfixed-nonsleeping\n'
		printf 'joypad-open-policy\tsingle-open-sync\n'
	fi
	if [ "$IRQ_GPIO_BUTTONS" = 1 ]; then
		printf 'joypad-digital-policy\tboth-edge-irq-5ms-debounce\n'
		printf 'joypad-poll-policy\tanalog-only-10ms\n'
		printf 'joypad-fixed-buttons\t17\n'
	fi
	if [ "$SKIP_RAID6_BENCHMARK" = 1 ]; then
		printf 'raid6-pq-policy\tfixed-priority-no-benchmark\n'
		printf 'raid6-pq-selected\tneonx8-first-valid\n'
	fi
	printf 'shipping-kernel-sha256\t%s\n' "$SHIPPING_KERNEL_SHA"
	printf 'shipping-dtb-sha256\t%s\n' "$SHIPPING_DTB_SHA"
	printf 'source-kernel-sha256\t%s\n' "$(sha256 "$BUILD_OUTPUT/Image")"
	printf 'source-dtb-sha256\t%s\n' "$(sha256 "$DTB")"
	printf 'source-joypad-sha256\t%s\n' "$(sha256 "$JOYPAD_MODULE")"
	printf 'source-modules-sha256\t%s\n' "$(sha256 "$BUILD_OUTPUT/modules.tar.xz")"
} >"$BUILD_OUTPUT/parity.tsv"

printf 'Exact untrimmed ROCKNIX source gate passed under:\n  %s\n' "$BUILD_OUTPUT"
printf 'Shipping-identical DTB:\n'
shasum -a 256 "$DTB"
printf 'Build artifacts:\n'
cat "$BUILD_OUTPUT/sizes.txt"
