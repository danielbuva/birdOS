#!/bin/sh
# Installs and collects the frontend's built-in monotonic startup log.

TIMING_TMP="/tmp/muos/boot-timing.tsv"
TIMING_FINAL_DIR="/mnt/mmc/MUOS/log/boot"
TRACE_ROOT="/mnt/mmc/MUOS/boot-timing/frontend-native"
TRACE_LOG_DIR="/mnt/mmc/MUOS/log/frontend-native"
TARGET="/opt/muos/script/mux/frontend.sh"
BACKUP="$TRACE_ROOT/backup/frontend.sh.pre-native-log"
INSTALL_LOG="$TRACE_ROOT/install.log"
PATCH_MARKER="BOOT_TIMING_FRONTEND_NATIVE_LOG_V1"
LOG_COPY_ROOT="/mnt/mmc/MUOS/boot-timing/deferred-log-copy"
LOG_COPY_BACKUP="$LOG_COPY_ROOT/backup/frontend.sh.pre-deferred-log-copy"
LOG_COPY_INSTALL_LOG="$LOG_COPY_ROOT/install.log"
LOG_COPY_MARKER="BOOT_TIMING_DEFER_LOG_COPY_V1"
STRACE_ROOT="/mnt/mmc/MUOS/boot-timing/frontend-strace"
STRACE_LOG_DIR="/mnt/mmc/MUOS/log/frontend-strace"
STRACE_STATE="$STRACE_ROOT/state"
STRACE_TARGET="/opt/muos/frontend/muxfrontend"
STRACE_REAL="/opt/muos/frontend/muxfrontend.boottrace-real"
STRACE_WRAPPER="$STRACE_ROOT/muxfrontend-wrapper.sh"
QUIET_ROOT="/mnt/mmc/MUOS/boot-timing/quiet-critical-path"
QUIET_STARTUP="/opt/muos/script/system/startup.sh"
QUIET_DEVICE="/opt/muos/script/device/start.sh"
QUIET_STARTUP_MARKER="BOOT_TIMING_QUIET_STARTUP_V1"
QUIET_DEVICE_MARKER="BOOT_TIMING_DEFER_EMULATOR_VERIFY_V1"
FONT_ROOT="/mnt/mmc/MUOS/boot-timing/english-fonts"
FONT_STUB_DIR="$FONT_ROOT/stubs"
FONT_BACKUP_DIR="$FONT_ROOT/backup"
FONT_STATE="$FONT_ROOT/state"
FONT_INSTALL_LOG="$FONT_ROOT/install.log"
FONT_LIB_DIR="/opt/muos/frontend/lib"
FONT_LANGUAGE_FILE="/opt/muos/config/settings/general/language"
BESPOKE_ROOT="/mnt/mmc/MUOS/boot-timing/bespoke-services"
BESPOKE_STARTUP="$BESPOKE_ROOT/backup/startup.sh.pre-bespoke-services"
BESPOKE_DEVICE="$BESPOKE_ROOT/backup/device-start.sh.pre-bespoke-services"
BESPOKE_SYSINIT="$BESPOKE_ROOT/backup/sysinit.pre-bespoke-services"
BESPOKE_STARTUP_MARKER="BOOT_TIMING_BESPOKE_BACKGROUND_V1"
BESPOKE_DEVICE_MARKER="BOOT_TIMING_WIFI_ON_DEMAND_V1"
BESPOKE_SYSINIT_MARKER="BOOT_TIMING_DEFER_CHRONY_ENTROPY_V1"
BESPOKE_ENTROPY_FIX_MARKER="BOOT_TIMING_RESTORE_EARLY_ENTROPY_V2"
WIFI_DIAG_ROOT="/mnt/mmc/MUOS/boot-timing/wifi-module-diagnostic"
WIFI_DIAG_STATE="$WIFI_DIAG_ROOT/state"
WIFI_MODULE_TARGET="/opt/muos/script/device/module.sh"
WIFI_MODULE_MARKER="BOOT_TIMING_WIFI_MODULE_ON_DEMAND_V1"
DEPMOD_CACHE_MARKER="BOOT_TIMING_CACHE_DEPMOD_V1"
DEPMOD_STATUS="/tmp/muos/depmod-status"
LAUNCHER_ROOT="/mnt/mmc/MUOS/bespoke-launcher"
LAUNCHER_OBJECT="$LAUNCHER_ROOT/dani-launcher.o"
LAUNCHER_TARGET="/opt/muos/bin/dani-launcher"
LAUNCHER_PROOF_STATE="$LAUNCHER_ROOT/proof-v4-remaining.state"
LAUNCHER_PROOF_LOG="$LAUNCHER_ROOT/proof-v4-remaining.log"
EARLY_LAUNCHER_STATE="$LAUNCHER_ROOT/early-launcher-v1.state"
EARLY_INIT_SOURCE="$LAUNCHER_ROOT/S11danilauncher"
EARLY_INIT_TARGET="/opt/muos/script/init/S11danilauncher"
EARLY_STARTUP_TARGET="/opt/muos/script/system/startup.sh"
EARLY_STARTUP_BACKUP="$LAUNCHER_ROOT/startup.pre-early-launcher"
EARLY_STARTUP_MARKER="DANI_EARLY_LAUNCHER_V1"

if [ -r /proc/sys/kernel/random/boot_id ]; then
	IFS= read -r BOOT_ID </proc/sys/kernel/random/boot_id
else
	BOOT_ID="unknown"
fi

# Keep the existing late user-init timing marker.
if [ -f "$TIMING_TMP" ]; then
	IFS=' ' read -r UPTIME_S _ </proc/uptime
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$BOOT_ID" "$UPTIME_S" "milestone" "user" "user_init_hook" "0" >>"$TIMING_TMP"

	mkdir -p "$TIMING_FINAL_DIR"
	cp -f "$TIMING_TMP" "$TIMING_FINAL_DIR/boot-timing-$BOOT_ID.tsv"
	cp -f "$TIMING_TMP" "$TIMING_FINAL_DIR/boot-timing-latest.tsv"
fi

mkdir -p "$TRACE_ROOT/backup" "$TRACE_LOG_DIR"

# User-init is intentionally late: this changes the next boot, not the boot
# currently in progress.
if [ -f "$TARGET" ] && ! grep -q "$PATCH_MARKER" "$TARGET"; then
	[ -f "$BACKUP" ] || cp -p "$TARGET" "$BACKUP"

	PATCHED="/tmp/frontend-native-log.$$.sh"
	{
		IFS= read -r FIRST_LINE
		printf '%s\n' "$FIRST_LINE"
		printf '# %s\n' "$PATCH_MARKER"
		sed 's|EXEC_MUX "launcher" "muxfrontend"$|EXEC_MUX "launcher" "muxfrontend" 2>"/tmp/muxfrontend-startup.log"|'
	} <"$TARGET" >"$PATCHED"

	if grep -q 'muxfrontend-startup.log' "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$TARGET"
		printf '%s frontend native-log capture installed; collection begins next boot\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$INSTALL_LOG"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: frontend launcher line not found; no change made\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$INSTALL_LOG"
	fi
fi

# The stock launcher blocks on mkdir before starting the frontend and then
# competes with frontend loading while it copies logs. Preserve the copy, but
# start it after the UI has had time to render. Like the native-log patch, this
# affects the next boot because user-init itself runs late.
if [ -f "$TARGET" ] && ! grep -q "$LOG_COPY_MARKER" "$TARGET"; then
	mkdir -p "$LOG_COPY_ROOT/backup"
	[ -f "$LOG_COPY_BACKUP" ] || cp -p "$TARGET" "$LOG_COPY_BACKUP"

	PATCHED="/tmp/frontend-deferred-log-copy.$$.sh"
	while IFS= read -r LINE; do
		if [ "$LINE" = 'BL_PATH="$ROM_MOUNT/MUOS/log/boot"' ]; then
			IFS= read -r MKDIR_LINE || MKDIR_LINE=""
			IFS= read -r COPY_LINE || COPY_LINE=""
			printf '%s\n' "$LINE"
			if [ "$MKDIR_LINE" = 'mkdir -p "$BL_PATH"' ] && \
				[ "$COPY_LINE" = 'cp "$MUOS_LOG_DIR"/*.log "$BL_PATH"/. &' ]; then
				printf '# %s\n' "$LOG_COPY_MARKER"
				printf '%s\n' '('
				printf '%s\n' '    sleep 20'
				printf '%s\n' '    mkdir -p "$BL_PATH"'
				printf '%s\n' '    cp "$MUOS_LOG_DIR"/*.log "$BL_PATH"/.'
				printf '%s\n' ') &'
			else
				printf '%s\n' "$MKDIR_LINE" "$COPY_LINE"
			fi
		else
			printf '%s\n' "$LINE"
		fi
	done <"$TARGET" >"$PATCHED"

	if grep -q "$LOG_COPY_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$TARGET"
		printf '%s boot-log copy deferred until 20 seconds after frontend start; experiment begins next boot\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$LOG_COPY_INSTALL_LOG"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: stock boot-log copy block not found; no change made\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$LOG_COPY_INSTALL_LOG"
	fi
fi

# Keep expensive maintenance away from the frontend loader. Recursive
# permission repair, log/catalogue scans, and emulator-binary checks are still
# performed, but only after the menu should be visible. Emulator verification
# is cached by OS build so unchanged binaries are not re-hashed every boot.
if [ -f "$QUIET_STARTUP" ] && ! grep -q "$QUIET_STARTUP_MARKER" "$QUIET_STARTUP"; then
	mkdir -p "$QUIET_ROOT/backup"
	[ -f "$QUIET_ROOT/backup/startup.sh.pre-quiet" ] || \
		cp -p "$QUIET_STARTUP" "$QUIET_ROOT/backup/startup.sh.pre-quiet"

	PATCHED="/tmp/startup-quiet.$$.sh"
	while IFS= read -r LINE; do
		if [ "$LINE" = 'chown -R root:root "/root" "/opt/openssh" "/opt/sftpgo" &' ]; then
			IFS= read -r CHMOD_LINE || CHMOD_LINE=""
			if [ "$CHMOD_LINE" = 'chmod -R 755 "/root" "/opt/openssh" "/opt/sftpgo" &' ]; then
				printf '# %s\n' "$QUIET_STARTUP_MARKER"
				printf '%s\n' '('
				printf '%s\n' '    sleep 20'
				printf '%s\n' '    ionice -c idle chown -R root:root "/root" "/opt/openssh" "/opt/sftpgo"'
				printf '%s\n' '    ionice -c idle chmod -R 755 "/root" "/opt/openssh" "/opt/sftpgo"'
				printf '%s\n' ') &'
			else
				printf '%s\n' "$LINE" "$CHMOD_LINE"
			fi
		elif [ "$LINE" = 'LOG_CLEANER &' ]; then
			printf '%s\n' '(' '    sleep 20' '    LOG_CLEANER' ') &'
		elif [ "$LINE" = '/opt/muos/script/system/catalogue.sh &' ]; then
			printf '%s\n' '(' '    sleep 20' '    /opt/muos/script/system/catalogue.sh' ') &'
		elif [ "$LINE" = 'dmesg >"$ROM_MOUNT/MUOS/log/dmesg/dmesg__$(date +"%Y_%m_%d__%H_%M_%S").log" &' ]; then
			printf '%s\n' '(' '    sleep 20' '    dmesg >"$ROM_MOUNT/MUOS/log/dmesg/dmesg__$(date +"%Y_%m_%d__%H_%M_%S").log"' ') &'
		else
			printf '%s\n' "$LINE"
		fi
	done <"$QUIET_STARTUP" >"$PATCHED"

	if grep -q "$QUIET_STARTUP_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$QUIET_STARTUP"
		printf '%s startup maintenance deferred off the UI critical path\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$QUIET_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: startup maintenance block not found; no startup change made\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$QUIET_ROOT/install.log"
	fi
fi

if [ -f "$QUIET_DEVICE" ] && ! grep -q "$QUIET_DEVICE_MARKER" "$QUIET_DEVICE"; then
	mkdir -p "$QUIET_ROOT/backup"
	[ -f "$QUIET_ROOT/backup/device-start.sh.pre-quiet" ] || \
		cp -p "$QUIET_DEVICE" "$QUIET_ROOT/backup/device-start.sh.pre-quiet"

	PATCHED="/tmp/device-start-quiet.$$.sh"
	QUIET_BLOCK_FOUND=0
	while IFS= read -r LINE; do
		if [ "$LINE" = '# Add device specific Retroarch Binary' ] && [ "$QUIET_BLOCK_FOUND" -eq 0 ]; then
			QUIET_BLOCK_FOUND=1
			printf '# %s\n' "$QUIET_DEVICE_MARKER"
			printf '%s\n' 'EMU_VERIFY_STAMP="/opt/muos/config/system/emulator_verify_build"'
			printf '%s\n' 'EMU_VERIFY_BUILD=$(cat /opt/muos/config/system/build 2>/dev/null)'
			printf '%s\n' 'if [ ! -f "$EMU_VERIFY_STAMP" ] || [ "$(cat "$EMU_VERIFY_STAMP" 2>/dev/null)" != "$EMU_VERIFY_BUILD" ]; then'
			printf '%s\n' '('
			printf '%s\n' '    sleep 20'
			printf '%s\n' "$LINE"
		else
			printf '%s\n' "$LINE"
		fi
	done <"$QUIET_DEVICE" >"$PATCHED"

	if [ "$QUIET_BLOCK_FOUND" -eq 1 ]; then
		printf '%s\n' '    printf "%s\n" "$EMU_VERIFY_BUILD" >"$EMU_VERIFY_STAMP"' >>"$PATCHED"
		printf '%s\n' ') &' 'fi' >>"$PATCHED"
	fi

	if grep -q "$QUIET_DEVICE_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$QUIET_DEVICE"
		printf '%s emulator verification deferred and cached by OS build\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$QUIET_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: emulator verification block not found; no device-start change made\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$QUIET_ROOT/install.log"
	fi
fi

# Keep networking completely off the boot path. network.sh already loads the
# Wi-Fi driver and calls rfkill when an explicit connection is requested, so
# PortMaster, the network menu, and future scraper wrappers retain on-demand
# access without the driver's SDIO probe/retry churn competing with the UI.
if [ -f "$QUIET_DEVICE" ] && ! grep -q "$BESPOKE_DEVICE_MARKER" "$QUIET_DEVICE"; then
	mkdir -p "$BESPOKE_ROOT/backup"
	[ -f "$BESPOKE_DEVICE" ] || cp -p "$QUIET_DEVICE" "$BESPOKE_DEVICE"

	PATCHED="/tmp/device-start-bespoke.$$.sh"
	while IFS= read -r LINE; do
		if [ "$LINE" = 'rfkill unblock all 2>/dev/null' ]; then
			printf '# %s\n' "$BESPOKE_DEVICE_MARKER"
			printf '%s\n' ': # Wi-Fi is powered only by an explicit network.sh connect request.'
		else
			printf '%s\n' "$LINE"
		fi
	done <"$QUIET_DEVICE" >"$PATCHED"

	if grep -q "$BESPOKE_DEVICE_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$QUIET_DEVICE"
		printf '%s removed unconditional rfkill/Wi-Fi activation from device startup\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: startup rfkill line not found; device startup unchanged\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi

# Chrony is only useful with a network connection, and network.sh explicitly
# restarts it after connecting. Entropy must remain early: PipeWire and SDL can
# block in getrandom until the kernel CRNG is initialised.
SYSINIT_TARGET="/opt/muos/script/init/sysinit"
if [ -f "$SYSINIT_TARGET" ] && ! grep -q "$BESPOKE_SYSINIT_MARKER" "$SYSINIT_TARGET"; then
	mkdir -p "$BESPOKE_ROOT/backup"
	[ -f "$BESPOKE_SYSINIT" ] || cp -p "$SYSINIT_TARGET" "$BESPOKE_SYSINIT"

	PATCHED="/tmp/sysinit-bespoke.$$.sh"
	SYSINIT_RUN_LINE=$(printf '\t\t%s' 'RUN_SCRIPT "$SCRIPT" "sync"')
	while IFS= read -r LINE; do
		if [ "$LINE" = "$SYSINIT_RUN_LINE" ]; then
			printf '\t\t# %s\n' "$BESPOKE_SYSINIT_MARKER"
			printf '\t\t%s\n' 'case "${SCRIPT##*/}" in'
			printf '\t\t\t%s\n' 'S00chrony) TIMING_EVENT "skip" "sync" "S00chrony" "deferred-to-network"; continue ;;'
			printf '\t\t%s\n' 'esac'
			printf '%s\n' "$LINE"
		else
			printf '%s\n' "$LINE"
		fi
	done <"$SYSINIT_TARGET" >"$PATCHED"

	if grep -q "$BESPOKE_SYSINIT_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$SYSINIT_TARGET"
		printf '%s chrony removed from boot; early entropy retained for audio/CRNG readiness\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: instrumented sysinit run hook not found; init services unchanged\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi

# Move optional jobs that are launched immediately after FRONTEND start far
# enough away that they cannot contend with its loader. Hardware/input/audio
# prerequisites stay where they are; only maintenance and convenience work is
# delayed. Wi-Fi autoconnect is disabled regardless of the stock default.
if [ -f "$QUIET_STARTUP" ] && ! grep -q "$BESPOKE_STARTUP_MARKER" "$QUIET_STARTUP"; then
	mkdir -p "$BESPOKE_ROOT/backup"
	[ -f "$BESPOKE_STARTUP" ] || cp -p "$QUIET_STARTUP" "$BESPOKE_STARTUP"

	PATCHED="/tmp/startup-bespoke.$$.sh"
	BESPOKE_NETWORK_FOUND=0
	while IFS= read -r LINE; do
		if [ "$LINE" = 'LOG_INFO "$0" 0 "BOOTING" "Starting Pipewire"' ]; then
			printf '# %s\n' "$BESPOKE_STARTUP_MARKER"
			printf '%s\n' "$LINE"
		elif [ "$LINE" = 'LOG_INFO "$0" 0 "BOOTING" "Connecting Network on Boot if requested and possible"' ]; then
			IFS= read -r NET_1 || NET_1=""
			IFS= read -r NET_2 || NET_2=""
			IFS= read -r NET_3 || NET_3=""
			IFS= read -r NET_4 || NET_4=""
			IFS= read -r NET_5 || NET_5=""
			IFS= read -r NET_6 || NET_6=""
			IFS= read -r NET_7 || NET_7=""
			if [ "$NET_1" = 'if [ "${HAS_NETWORK:-0}" -eq 1 ] && [ "${CONNECT_ON_BOOT:-0}" -eq 1 ]; then' ] && \
				[ "$NET_3" = "$(printf '\t\t/opt/muos/script/system/network.sh connect &')" ] && \
				[ "$NET_5" = "$(printf '\t\t/opt/muos/script/system/network.sh connect')" ] && \
				[ "$NET_7" = 'fi' ]; then
				printf '%s\n' 'LOG_INFO "$0" 0 "BOOTING" "Skipping boot network; Wi-Fi is on demand"'
				printf '%s\n' ': # PortMaster/network tools call network.sh connect when needed.'
				BESPOKE_NETWORK_FOUND=1
			else
				printf '%s\n' "$LINE" "$NET_1" "$NET_2" "$NET_3" "$NET_4" "$NET_5" "$NET_6" "$NET_7"
			fi
		elif [ "$LINE" = 'PREP_SOUND reboot &' ]; then
			IFS= read -r SOUND_2 || SOUND_2=""
			if [ "$SOUND_2" = 'PREP_SOUND shutdown &' ]; then
				printf '%s\n' '(' '    sleep 20' '    PREP_SOUND reboot' '    PREP_SOUND shutdown' ') &'
			else
				printf '%s\n' "$LINE" "$SOUND_2"
			fi
		elif [ "$LINE" = '/opt/muos/script/system/lowpower.sh &' ]; then
			printf '%s\n' '(' '    sleep 12' '    /opt/muos/script/system/lowpower.sh' ') &'
		elif [ "$LINE" = '[ "$USB_FUNCTION" -ne 0 ] && /opt/muos/script/system/usb_gadget.sh start &' ]; then
			printf '%s\n' '(' '    sleep 20' '    [ "$USB_FUNCTION" -ne 0 ] && /opt/muos/script/system/usb_gadget.sh start' ') &'
		elif [ "$LINE" = "$(printf '\t/opt/muos/script/device/control.sh FORCE_COPY &')" ]; then
			printf '\t%s\n' '( sleep 8; /opt/muos/script/device/control.sh FORCE_COPY ) &'
		elif [ "$LINE" = "$(printf '\t/opt/muos/script/device/control.sh &')" ]; then
			printf '\t%s\n' '( sleep 8; /opt/muos/script/device/control.sh ) &'
		elif [ "$LINE" = '/opt/muos/script/mux/sdl_map.sh &' ]; then
			printf '%s\n' '( sleep 8; /opt/muos/script/mux/sdl_map.sh ) &'
		else
			printf '%s\n' "$LINE"
		fi
	done <"$QUIET_STARTUP" >"$PATCHED"

	if grep -q "$BESPOKE_STARTUP_MARKER" "$PATCHED" && [ "$BESPOKE_NETWORK_FOUND" -eq 1 ]; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$QUIET_STARTUP"
		printf '%s\n' "0" >"/opt/muos/config/settings/network/boot"
		printf '%s boot Wi-Fi disabled; sounds, low-power, USB, controls, and SDL setup deferred\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: startup network block not found; background-service patch not installed\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi

# Repair V1 installations that deferred S01entropy. Measurements showed that
# this delayed kernel CRNG readiness to 11-13 seconds and made SDL audio block
# the frontend for another 4-6 seconds. Keep every other V1 service deferral.
if { grep -q 'S01entropy.*deferred-20s' "$SYSINIT_TARGET" 2>/dev/null || \
	grep -q '/opt/muos/script/init/S01entropy start' "$QUIET_STARTUP" 2>/dev/null; }; then
	PATCHED="/tmp/sysinit-entropy-fix.$$.sh"
	while IFS= read -r LINE; do
		case "$LINE" in
			*S01entropy*deferred-20s*) printf '\t\t\t# %s\n' "$BESPOKE_ENTROPY_FIX_MARKER" ;;
			*) printf '%s\n' "$LINE" ;;
		esac
	done <"$SYSINIT_TARGET" >"$PATCHED"

	if grep -q "$BESPOKE_ENTROPY_FIX_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$SYSINIT_TARGET"
	else
		rm -f "$PATCHED"
	fi

	PATCHED="/tmp/startup-entropy-fix.$$.sh"
	while IFS= read -r LINE; do
		if [ "$LINE" = "# $BESPOKE_STARTUP_MARKER" ]; then
			IFS= read -r ENTROPY_1 || ENTROPY_1=""
			IFS= read -r ENTROPY_2 || ENTROPY_2=""
			IFS= read -r ENTROPY_3 || ENTROPY_3=""
			IFS= read -r ENTROPY_4 || ENTROPY_4=""
			printf '%s\n' "$LINE" "# $BESPOKE_ENTROPY_FIX_MARKER"
			if [ "$ENTROPY_1" != '(' ] || [ "$ENTROPY_2" != '    sleep 20' ] || \
				[ "$ENTROPY_3" != '    /opt/muos/script/init/S01entropy start' ] || \
				[ "$ENTROPY_4" != ') &' ]; then
				printf '%s\n' "$ENTROPY_1" "$ENTROPY_2" "$ENTROPY_3" "$ENTROPY_4"
			fi
		else
			printf '%s\n' "$LINE"
		fi
	done <"$QUIET_STARTUP" >"$PATCHED"

	if grep -q "$BESPOKE_ENTROPY_FIX_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$QUIET_STARTUP"
		printf '%s restored early entropy after CRNG/audio regression; other service deferrals retained\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: could not remove deferred entropy startup block\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi

# General device-module setup claims to exclude networking, but module.sh
# still unconditionally modprobes 8821cs. The explicit network path uses
# device/network.sh and loads the same driver itself, so remove it from boot.
if [ -f "$WIFI_MODULE_TARGET" ] && ! grep -q "$WIFI_MODULE_MARKER" "$WIFI_MODULE_TARGET"; then
	mkdir -p "$BESPOKE_ROOT/backup"
	[ -f "$BESPOKE_ROOT/backup/device-module.sh.pre-wifi-on-demand" ] || \
		cp -p "$WIFI_MODULE_TARGET" "$BESPOKE_ROOT/backup/device-module.sh.pre-wifi-on-demand"

	PATCHED="/tmp/device-module-wifi-on-demand.$$.sh"
	WIFI_MODULE_LOAD_LINE=$(printf '\t\t%s' '[ "$HAS_NETWORK" -eq 1 ] && modprobe -q "$NET_NAME"')
	while IFS= read -r LINE; do
		if [ "$LINE" = "$WIFI_MODULE_LOAD_LINE" ]; then
			printf '\t\t# %s\n' "$WIFI_MODULE_MARKER"
			printf '\t\t%s\n' ': # Wi-Fi module is loaded only by device/network.sh on explicit request.'
		else
			printf '%s\n' "$LINE"
		fi
	done <"$WIFI_MODULE_TARGET" >"$PATCHED"

	if grep -q "$WIFI_MODULE_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$WIFI_MODULE_TARGET"
		printf '%s removed rtl8821cs from general module loading; explicit network remains available\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: general Wi-Fi modprobe line not found; module loading unchanged\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi

# The kernel/module set is fixed and ships with modules.dep. Rebuilding the
# complete dependency database on every boot only adds I/O. Retain a fallback
# rebuild so the system still recovers if the index is ever missing.
if [ -f "$WIFI_MODULE_TARGET" ] && ! grep -q "$DEPMOD_CACHE_MARKER" "$WIFI_MODULE_TARGET"; then
	[ -f "$BESPOKE_ROOT/backup/device-module.sh.pre-depmod-cache" ] || \
		cp -p "$WIFI_MODULE_TARGET" "$BESPOKE_ROOT/backup/device-module.sh.pre-depmod-cache"

	PATCHED="/tmp/device-module-depmod-cache.$$.sh"
	while IFS= read -r LINE; do
		if [ "$LINE" = 'depmod -a 2>/dev/null' ]; then
			printf '# %s\n' "$DEPMOD_CACHE_MARKER"
			printf '%s\n' 'if [ -s /lib/modules/4.9.170/modules.dep ]; then'
			printf '\t%s\n' 'printf "%s\n" "cached" >"/tmp/muos/depmod-status"'
			printf '%s\n' 'else'
			printf '\t%s\n' 'depmod -a 2>/dev/null'
			printf '\t%s\n' 'printf "%s\n" "rebuilt" >"/tmp/muos/depmod-status"'
			printf '%s\n' 'fi'
		else
			printf '%s\n' "$LINE"
		fi
	done <"$WIFI_MODULE_TARGET" >"$PATCHED"

	if grep -q "$DEPMOD_CACHE_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$WIFI_MODULE_TARGET"
		printf '%s cached depmod guard installed; active next boot\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: depmod line not found; module database behavior unchanged\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi

if [ -f "$DEPMOD_STATUS" ] && [ ! -f "$BESPOKE_ROOT/depmod-status" ]; then
	cp -f "$DEPMOD_STATUS" "$BESPOKE_ROOT/depmod-status"
fi

# Build and run the first custom-launcher hardware proof exactly once. The
# host supplies one freestanding AArch64 object; the target's own linker turns
# it into a static executable with no runtime library dependencies. Because
# user-init runs after the stock frontend has started, this proof stops stock,
# owns the framebuffer/input devices for at most 15 seconds, then restores
# stock. The next phase will move the proven binary earlier in the boot path.
if [ -s "$LAUNCHER_OBJECT" ] && [ ! -f "$LAUNCHER_PROOF_STATE" ]; then
	mkdir -p "$LAUNCHER_ROOT"
	LAUNCHER_NEW="/tmp/dani-launcher.$$"
	if /usr/bin/ld -static --build-id=none -z noexecstack -s -e _start \
		-o "$LAUNCHER_NEW" "$LAUNCHER_OBJECT" >"$LAUNCHER_ROOT/link-v4-remaining.log" 2>&1; then
		chmod 755 "$LAUNCHER_NEW"
		mv -f "$LAUNCHER_NEW" "$LAUNCHER_TARGET"
		(
			sleep 3
			. /opt/muos/script/var/func.sh
			{
				printf '%s\n' '--- /dev/input ---'
				ls -l /dev/input
				printf '%s\n' '--- /proc/bus/input/devices ---'
				cat /proc/bus/input/devices
			} >"$LAUNCHER_ROOT/input-inventory-v3.txt" 2>&1
			{
				printf 'proof supervisor start boot uptime: '
				cut -d ' ' -f 1 /proc/uptime
				FRONTEND stop
				if /opt/muos/frontend/mufbset -w 720 -h 480 -d 32; then
					printf '%s\n' 'fixed 720x480x32 framebuffer mode applied'
				else
					printf '%s\n' 'framebuffer mode reset failed; launcher will use current mode'
				fi
				"$LAUNCHER_TARGET"
				LAUNCHER_RESULT=$?
				FRONTEND start
				printf 'proof executable result: %s\n' "$LAUNCHER_RESULT"
				printf 'stock frontend restart requested at uptime: '
				cut -d ' ' -f 1 /proc/uptime
			} >"$LAUNCHER_PROOF_LOG" 2>&1
			printf '%s\n' "complete" >"$LAUNCHER_PROOF_STATE"
		) &
	else
		rm -f "$LAUNCHER_NEW"
		printf '%s launcher proof link failed; user-init will retry next boot\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi

# Promote the proven framebuffer/input program to an early interactive shell.
# S11 runs immediately after udev and returns at once while its supervisor keeps
# the launcher alive. Normal muOS startup continues in parallel, but skips the
# stock frontend while the custom launcher owns the display. B (or the safety
# timeout) hands off to stock only after startup reports that it is ready.
if [ -s "$LAUNCHER_OBJECT" ] && [ -s "$EARLY_INIT_SOURCE" ] && [ ! -f "$EARLY_LAUNCHER_STATE" ]; then
	LAUNCHER_NEW="/tmp/dani-launcher-early.$$"
	PATCHED="/tmp/startup-early-launcher.$$.sh"

	if /usr/bin/ld -static --build-id=none -z noexecstack -s -e _start \
		-o "$LAUNCHER_NEW" "$LAUNCHER_OBJECT" >"$LAUNCHER_ROOT/link-early-v1.log" 2>&1; then
		chmod 755 "$LAUNCHER_NEW"
		[ -f "$EARLY_STARTUP_BACKUP" ] || cp -p "$EARLY_STARTUP_TARGET" "$EARLY_STARTUP_BACKUP"

		while IFS= read -r LINE; do
			if [ "$LINE" = 'FRONTEND start' ]; then
				printf '# %s\n' "$EARLY_STARTUP_MARKER"
				printf '%s\n' 'mkdir -p "/run/muos"'
				printf '%s\n' ': >"/run/muos/dani-system-ready"'
				printf '%s\n' 'if [ ! -e "/run/muos/dani-launcher-active" ]; then'
				printf '\t%s\n' 'FRONTEND start'
				printf '%s\n' 'fi'
			else
				printf '%s\n' "$LINE"
			fi
		done <"$EARLY_STARTUP_TARGET" >"$PATCHED"

		if grep -q "$EARLY_STARTUP_MARKER" "$PATCHED"; then
			chmod 755 "$PATCHED"
			mv -f "$PATCHED" "$EARLY_STARTUP_TARGET"
			mv -f "$LAUNCHER_NEW" "$LAUNCHER_TARGET"
			cp -f "$EARLY_INIT_SOURCE" "$EARLY_INIT_TARGET"
			chmod 755 "$EARLY_INIT_TARGET"
			printf '%s\n' "installed" >"$EARLY_LAUNCHER_STATE"
			printf '%s early launcher installed after udev; active next boot\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
		else
			rm -f "$PATCHED" "$LAUNCHER_NEW"
			printf '%s ERROR: stock frontend start line not found; early launcher not installed\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
		fi
	else
		rm -f "$LAUNCHER_NEW"
		printf '%s ERROR: early launcher link failed; installation will retry\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi

# The frontend links all five large non-English font DSOs even when English is
# selected. Replace those DSOs with tiny symbol-compatible libraries. The real
# English UI fonts (medium, big, and big-HD) are not changed. The AArch64 object
# files are prepared on the host; the device's own linker creates the shared
# libraries so they exactly match the target ABI.
if [ ! -f "$FONT_STATE" ]; then
	CURRENT_LANGUAGE=$(cat "$FONT_LANGUAGE_FILE" 2>/dev/null)
	if [ "$CURRENT_LANGUAGE" = "English" ]; then
		mkdir -p "$FONT_ROOT" "$FONT_BACKUP_DIR"
		FONT_BUILD_DIR="/tmp/muos-font-stubs.$$"
		mkdir -p "$FONT_BUILD_DIR"
		FONT_BUILD_FAILED=0

		for FONT_CODE in ar jp kr sc tc; do
			FONT_NAME="libnotosans_${FONT_CODE}_medium"
			FONT_OBJECT="$FONT_STUB_DIR/$FONT_NAME.o"
			FONT_OUTPUT="$FONT_BUILD_DIR/$FONT_NAME.so"
			if [ ! -s "$FONT_OBJECT" ]; then
				printf '%s ERROR: missing AArch64 object %s\n' \
					"$(date -Iseconds 2>/dev/null || date)" "$FONT_OBJECT" >>"$FONT_INSTALL_LOG"
				FONT_BUILD_FAILED=1
			elif ! /usr/bin/ld -shared --hash-style=both -soname "$FONT_NAME.so" \
				-o "$FONT_OUTPUT" "$FONT_OBJECT" >>"$FONT_INSTALL_LOG" 2>&1; then
				printf '%s ERROR: could not link %s\n' \
					"$(date -Iseconds 2>/dev/null || date)" "$FONT_NAME.so" >>"$FONT_INSTALL_LOG"
				FONT_BUILD_FAILED=1
			elif [ ! -s "$FONT_OUTPUT" ]; then
				printf '%s ERROR: linker produced an empty %s\n' \
					"$(date -Iseconds 2>/dev/null || date)" "$FONT_NAME.so" >>"$FONT_INSTALL_LOG"
				FONT_BUILD_FAILED=1
			fi
		done

		FONT_INSTALL_FAILED=$FONT_BUILD_FAILED
		if [ "$FONT_BUILD_FAILED" -eq 0 ]; then
			for FONT_CODE in ar jp kr sc tc; do
				FONT_NAME="libnotosans_${FONT_CODE}_medium"
				FONT_TARGET="$FONT_LIB_DIR/$FONT_NAME.so"
				FONT_BACKUP="$FONT_BACKUP_DIR/$FONT_NAME.so.original"
				FONT_NEW="$FONT_LIB_DIR/.$FONT_NAME.so.new"

				if [ ! -f "$FONT_TARGET" ]; then
					printf '%s ERROR: target font library is missing: %s\n' \
						"$(date -Iseconds 2>/dev/null || date)" "$FONT_TARGET" >>"$FONT_INSTALL_LOG"
					FONT_INSTALL_FAILED=1
					continue
				fi
				[ -f "$FONT_BACKUP" ] || cp -f "$FONT_TARGET" "$FONT_BACKUP"
				if cp -f "$FONT_BUILD_DIR/$FONT_NAME.so" "$FONT_NEW" && \
					chmod 755 "$FONT_NEW" && mv -f "$FONT_NEW" "$FONT_TARGET"; then
					printf '%s installed English-only stub %s (%s bytes)\n' \
						"$(date -Iseconds 2>/dev/null || date)" "$FONT_NAME.so" \
						"$(wc -c <"$FONT_TARGET")" >>"$FONT_INSTALL_LOG"
				else
					printf '%s ERROR: could not install %s\n' \
						"$(date -Iseconds 2>/dev/null || date)" "$FONT_NAME.so" >>"$FONT_INSTALL_LOG"
					FONT_INSTALL_FAILED=1
				fi
			done
		fi

		rm -rf "$FONT_BUILD_DIR"
		if [ "$FONT_INSTALL_FAILED" -eq 0 ]; then
			printf '%s\n' "installed" >"$FONT_STATE"
			printf '%s English-only font libraries installed persistently; active next boot\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$FONT_INSTALL_LOG"
		else
			printf '%s font installation incomplete; user-init will retry next boot\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$FONT_INSTALL_LOG"
		fi
	else
		mkdir -p "$FONT_ROOT"
		printf '%s skipped English-only fonts because configured language is [%s]\n' \
			"$(date -Iseconds 2>/dev/null || date)" "$CURRENT_LANGUAGE" >>"$FONT_INSTALL_LOG"
	fi
fi

# Arm a single diagnostic boot. The first user-init pass replaces muxfrontend
# with a strace wrapper. On the following boot the wrapper is already running
# by the time user-init executes, so the real binary is restored immediately
# for every later boot while that one traced process continues normally.
STRACE_STATE_VALUE=""
[ -f "$STRACE_STATE" ] && IFS= read -r STRACE_STATE_VALUE <"$STRACE_STATE"

case "$STRACE_STATE_VALUE" in
	"")
		if [ -f "$STRACE_TARGET" ] && [ -f "$STRACE_WRAPPER" ] && [ ! -e "$STRACE_REAL" ]; then
			mkdir -p "$STRACE_ROOT/backup" "$STRACE_LOG_DIR"
			cp -p "$STRACE_TARGET" "$STRACE_ROOT/backup/muxfrontend.pre-strace"
			mv -f "$STRACE_TARGET" "$STRACE_REAL"
			cp "$STRACE_WRAPPER" "$STRACE_TARGET"
			chmod 755 "$STRACE_TARGET"
			printf '%s\n' "armed" >"$STRACE_STATE"
			printf '%s one-boot frontend file-I/O trace armed; diagnostic begins next boot\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$STRACE_ROOT/install.log"
		fi
		;;
	armed)
		if [ -f "$STRACE_REAL" ]; then
			mv -f "$STRACE_REAL" "$STRACE_TARGET"
			chmod 755 "$STRACE_TARGET"
			printf '%s\n' "complete" >"$STRACE_STATE"
			printf '%s traced frontend was already running; normal binary restored for later boots\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$STRACE_ROOT/install.log"

			(
				sleep 25
				if [ -s /tmp/muxfrontend-startup.strace ]; then
					cp -f /tmp/muxfrontend-startup.strace "$STRACE_LOG_DIR/muxfrontend-$BOOT_ID.strace"
					cp -f /tmp/muxfrontend-startup.strace "$STRACE_LOG_DIR/muxfrontend-latest.strace"
					printf '%s captured frontend file-I/O trace for boot %s\n' \
						"$(date -Iseconds 2>/dev/null || date)" "$BOOT_ID" >>"$STRACE_ROOT/collection.log"
				fi
			) &
		else
			printf '%s ERROR: trace state armed but real frontend binary is missing\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$STRACE_ROOT/install.log"
		fi
		;;
esac

# On the following boot, copy the still-open log after the UI has had ample
# time to render. Copying it does not stop or restart the frontend.
(
	sleep 18
	if [ -s /tmp/muxfrontend-startup.log ]; then
		cp -f /tmp/muxfrontend-startup.log "$TRACE_LOG_DIR/muxfrontend-$BOOT_ID.log"
		cp -f /tmp/muxfrontend-startup.log "$TRACE_LOG_DIR/muxfrontend-latest.log"
		printf '%s captured native frontend log for boot %s\n' \
			"$(date -Iseconds 2>/dev/null || date)" "$BOOT_ID" >>"$TRACE_ROOT/collection.log"
	fi
) &

# One-shot late collection to identify what still auto-loads rtl8821cs after
# boot autoconnect and the unconditional rfkill call have both been removed.
if [ ! -f "$WIFI_DIAG_STATE" ]; then
	(
		sleep 25
		mkdir -p "$WIFI_DIAG_ROOT"
		[ -f /opt/muos/script/device/module.sh ] && \
			cp -f /opt/muos/script/device/module.sh "$WIFI_DIAG_ROOT/device-module.sh"
		[ -f /opt/muos/script/device/network.sh ] && \
			cp -f /opt/muos/script/device/network.sh "$WIFI_DIAG_ROOT/device-network.sh"
		[ -f /opt/muos/script/system/network.sh ] && \
			cp -f /opt/muos/script/system/network.sh "$WIFI_DIAG_ROOT/system-network.sh"
		find /opt/muos/device /etc/udev /lib/udev -maxdepth 5 -type f 2>/dev/null \
			>"$WIFI_DIAG_ROOT/candidate-files.txt"
		grep -R -n -i -E 'rtl8821|8821cs|sunxi-wlan|network\.sh|rfkill|wlan' \
			/opt/muos/device /opt/muos/script/device /etc/udev /lib/udev 2>/dev/null \
			>"$WIFI_DIAG_ROOT/references.txt"
		cat /proc/modules >"$WIFI_DIAG_ROOT/modules.txt"
		ps >"$WIFI_DIAG_ROOT/processes.txt"
		dmesg >"$WIFI_DIAG_ROOT/dmesg.txt"
		readlink -f /sys/class/net/wlan0/device/driver \
			>"$WIFI_DIAG_ROOT/wlan0-driver.txt" 2>/dev/null
		printf '%s\n' "complete" >"$WIFI_DIAG_STATE"
	) &
fi

exit 0
