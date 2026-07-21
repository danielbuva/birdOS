#!/bin/sh
# DANI_FIXED_RG34XXSP_CHARGE_V1

. /opt/muos/script/var/func.sh

BOOT_MODE="/sys/class/power_supply/axp2202-battery/boot_mode"
GOVERNOR="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
WORK_LED="/sys/class/power_supply/axp2202-battery/work_led"
EXIT_STATUS="/tmp/charger_exit"

MODE=0
read -r MODE <"$BOOT_MODE" 2>/dev/null || MODE=0
[ "$MODE" -eq 1 ] || exit 0

printf '%s' powersave >"$GOVERNOR"
EXEC_MUX "" muxcharge

STATUS=0
read -r STATUS <"$EXIT_STATUS" 2>/dev/null || STATUS=0
[ "$STATUS" -ne 1 ] || /opt/muos/script/system/halt.sh poweroff

printf '%s' performance >"$GOVERNOR"
printf '%s' 1 >"$WORK_LED"
