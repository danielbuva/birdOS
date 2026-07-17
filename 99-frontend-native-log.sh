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
# restarts it after connecting. haveged is retained but starts after the menu,
# avoiding entropy generation competing with udev, storage, and the frontend.
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
			printf '\t\t\t%s\n' 'S01entropy) TIMING_EVENT "skip" "sync" "S01entropy" "deferred-20s"; continue ;;'
			printf '\t\t%s\n' 'esac'
			printf '%s\n' "$LINE"
		else
			printf '%s\n' "$LINE"
		fi
	done <"$SYSINIT_TARGET" >"$PATCHED"

	if grep -q "$BESPOKE_SYSINIT_MARKER" "$PATCHED"; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$SYSINIT_TARGET"
		printf '%s chrony removed from boot and entropy generation deferred\n' \
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
			printf '%s\n' '(' '    sleep 20' '    /opt/muos/script/init/S01entropy start' ') &'
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
		printf '%s boot Wi-Fi disabled; sounds, entropy, low-power, USB, controls, and SDL setup deferred\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: startup network block not found; background-service patch not installed\n' \
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

exit 0
