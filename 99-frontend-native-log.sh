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
BESPOKE_BRIGHTNESS_DEVICE="$BESPOKE_ROOT/backup/device-start.sh.pre-no-brightness-restore"
BESPOKE_SYSINIT="$BESPOKE_ROOT/backup/sysinit.pre-bespoke-services"
BESPOKE_STARTUP_MARKER="BOOT_TIMING_BESPOKE_BACKGROUND_V1"
BESPOKE_DEVICE_MARKER="BOOT_TIMING_WIFI_ON_DEMAND_V1"
BESPOKE_OLD_BRIGHTNESS_MARKER="DANI_BRIGHTNESS_READY_V1"
BESPOKE_BRIGHTNESS_MARKER="DANI_DISABLE_ASYNC_BRIGHTNESS_RESTORE_V1"
BESPOKE_SYSINIT_MARKER="BOOT_TIMING_DEFER_CHRONY_ENTROPY_V1"
BESPOKE_ENTROPY_FIX_MARKER="BOOT_TIMING_RESTORE_EARLY_ENTROPY_V2"
CRITICAL_UI_BACKUP="$BESPOKE_ROOT/backup/sysinit.pre-critical-ui"
LEAN_USERSPACE_STATE="/opt/muos/config/system/dani_lean_userspace_v1"
WIFI_DIAG_ROOT="/mnt/mmc/MUOS/boot-timing/wifi-module-diagnostic"
WIFI_DIAG_STATE="$WIFI_DIAG_ROOT/state"
WIFI_MODULE_TARGET="/opt/muos/script/device/module.sh"
WIFI_MODULE_MARKER="BOOT_TIMING_WIFI_MODULE_ON_DEMAND_V1"
DEPMOD_CACHE_MARKER="BOOT_TIMING_CACHE_DEPMOD_V1"
DEPMOD_STATUS="/tmp/muos/depmod-status"
LAUNCHER_ROOT="/mnt/mmc/MUOS/bespoke-launcher"
LAUNCHER_OBJECT="$LAUNCHER_ROOT/dani-launcher.o"
LAUNCHER_TARGET="/opt/muos/bin/dani-launcher"
OPTIONAL_CORE_SOURCE_DIR="$LAUNCHER_ROOT/optional-cores"
OPTIONAL_CORE_TARGET_DIR="/opt/muos/share/core"
OPTIONAL_CORE_NAMES="gw_libretro.so bluemsx_libretro.so fake08_libretro.so"
OPTIONAL_EMULATOR_ROOT="$LAUNCHER_ROOT/optional-emulators"
OPTIONAL_EMULATOR_REVISION_SOURCE="$OPTIONAL_EMULATOR_ROOT/revision"
OPTIONAL_EMULATOR_STATE="$LAUNCHER_ROOT/optional-emulators-current.revision"
OPTIONAL_EMULATOR_LOG="$OPTIONAL_EMULATOR_ROOT/install.log"
NDS_ARCHIVE="$OPTIONAL_EMULATOR_ROOT/Extra.-.Nintendo.DS.muxzip"
OPENBOR_ARCHIVE="$OPTIONAL_EMULATOR_ROOT/Extra.-.OpenBOR.muxzip"
LAUNCHER_PROOF_STATE="$LAUNCHER_ROOT/proof-v4-remaining.state"
LAUNCHER_PROOF_LOG="$LAUNCHER_ROOT/proof-v4-remaining.log"
EARLY_LAUNCHER_STATE="$LAUNCHER_ROOT/early-launcher-current.revision"
EARLY_OLD_LAUNCHER_STATE="$LAUNCHER_ROOT/early-launcher-v11-real-catalog.revision"
EARLY_LAUNCHER_REVISION_SOURCE="$LAUNCHER_ROOT/catalog.revision"
EARLY_INIT_SOURCE="$LAUNCHER_ROOT/S03danilauncher"
EARLY_INIT_TARGET="/opt/muos/script/init/S03danilauncher"
EARLIEST_UI_SOURCE="$LAUNCHER_ROOT/dani-earliest-ui.sh"
EARLIEST_UI_TARGET="/opt/muos/script/init/dani-earliest-ui.sh"
EARLIEST_UI_INITTAB="/etc/inittab"
EARLIEST_UI_INITTAB_BACKUP="$BESPOKE_ROOT/backup/inittab.pre-earliest-ui"
EARLIEST_UI_PATCH_SOURCE="$LAUNCHER_ROOT/patch-earliest-ui-inittab.sh"
CRITICAL_UI_PATCH_SOURCE="$LAUNCHER_ROOT/patch-critical-ui-sysinit.sh"
EARLY_OLD_INIT_TARGET="/opt/muos/script/init/S11danilauncher"
EARLY_STARTUP_TARGET="/opt/muos/script/system/startup.sh"
EARLY_STARTUP_BACKUP="$LAUNCHER_ROOT/startup.pre-early-launcher"
EARLY_STARTUP_MARKER="DANI_EARLY_LAUNCHER_V1"
UDEV_PROFILE_TMP="/tmp/muos/udev-profile"
UDEV_PROFILE_ROOT="/mnt/mmc/MUOS/boot-timing/udev-profile/results"
FIXED_DEVICE_TMP="/tmp/muos/fixed-device-init.tsv"
FIXED_DEVICE_ROOT="/mnt/mmc/MUOS/boot-timing/udev-fixed/results"
MINIMAL_UDEV_TMP="/tmp/muos/minimal-udev.tsv"
MINIMAL_UDEV_ROOT="/mnt/mmc/MUOS/boot-timing/udev-minimal/results"
UDEV_ONCE_TMP="/tmp/muos/udev-once.tsv"
UDEV_ONCE_ROOT="/mnt/mmc/MUOS/boot-timing/udev-once/results"

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
	if [ -e /run/muos/dani-root-init-active ]; then
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$BOOT_ID" "$UPTIME_S" "milestone" "init" "static_pid1_active" "0" >>"$TIMING_TMP"
	fi

	mkdir -p "$TIMING_FINAL_DIR"
	cp -f "$TIMING_TMP" "$TIMING_FINAL_DIR/boot-timing-$BOOT_ID.tsv"
	cp -f "$TIMING_TMP" "$TIMING_FINAL_DIR/boot-timing-latest.tsv"
fi

# Persist an explicitly armed one-boot udev inventory after the ROM partition
# exists. The S10 wrapper never waits for removable storage itself.
if [ -d "$UDEV_PROFILE_TMP" ]; then
	UDEV_PROFILE_FINAL="$UDEV_PROFILE_ROOT/$BOOT_ID"
	mkdir -p "$UDEV_PROFILE_FINAL"
	cp -R "$UDEV_PROFILE_TMP/." "$UDEV_PROFILE_FINAL/"
fi

if [ -f "$FIXED_DEVICE_TMP" ]; then
	mkdir -p "$FIXED_DEVICE_ROOT"
	cp -f "$FIXED_DEVICE_TMP" "$FIXED_DEVICE_ROOT/$BOOT_ID.tsv"
	cp -f "$FIXED_DEVICE_TMP" "$FIXED_DEVICE_ROOT/latest.tsv"
fi

if [ -f "$MINIMAL_UDEV_TMP" ]; then
	mkdir -p "$MINIMAL_UDEV_ROOT"
	cp -f "$MINIMAL_UDEV_TMP" "$MINIMAL_UDEV_ROOT/$BOOT_ID.tsv"
	cp -f "$MINIMAL_UDEV_TMP" "$MINIMAL_UDEV_ROOT/latest.tsv"
fi

if [ -f "$UDEV_ONCE_TMP" ]; then
	mkdir -p "$UDEV_ONCE_ROOT"
	cp -f "$UDEV_ONCE_TMP" "$UDEV_ONCE_ROOT/$BOOT_ID.tsv"
	cp -f "$UDEV_ONCE_TMP" "$UDEV_ONCE_ROOT/latest.tsv"
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

# Preserve the display-handoff brightness already visible when Linux starts.
# Remove the later stock saved-setting restore from device/start.sh so it cannot
# overwrite that value asynchronously in the launcher or its boot animation.
BESPOKE_BRIGHTNESS_POLICY_READY=0
if [ -f "$QUIET_DEVICE" ] && ! grep -q "$BESPOKE_BRIGHTNESS_MARKER" "$QUIET_DEVICE"; then
	mkdir -p "$BESPOKE_ROOT/backup"
	[ -f "$BESPOKE_BRIGHTNESS_DEVICE" ] || cp -p "$QUIET_DEVICE" "$BESPOKE_BRIGHTNESS_DEVICE"

	PATCHED="/tmp/device-start-no-brightness-restore.$$.sh"
	SKIP_BRIGHTNESS_BLOCK=0
	BRIGHTNESS_BLOCK_FOUND=0
	BRIGHTNESS_BLOCK_ENDED=0
	while IFS= read -r LINE; do
		if [ "$SKIP_BRIGHTNESS_BLOCK" -eq 0 ] &&
			[ "$LINE" = "$(printf '\t%s' '/opt/muos/script/device/bright.sh R')" ]; then
			printf '\t# %s\n' "$BESPOKE_BRIGHTNESS_MARKER"
			printf '\t%s\n' ': # Keep display-handoff brightness; manual controls remain available.'
			SKIP_BRIGHTNESS_BLOCK=1
			BRIGHTNESS_BLOCK_FOUND=1
		elif [ "$SKIP_BRIGHTNESS_BLOCK" -eq 1 ]; then
			case "$LINE" in
				*'GET_VAR "config" "settings/colour/temperature"'*)
					SKIP_BRIGHTNESS_BLOCK=0
					BRIGHTNESS_BLOCK_ENDED=1
					printf '%s\n' "$LINE"
					;;
			esac
		else
			printf '%s\n' "$LINE"
		fi
	done <"$QUIET_DEVICE" >"$PATCHED"

	if grep -q "$BESPOKE_BRIGHTNESS_MARKER" "$PATCHED" &&
		! grep -q "$BESPOKE_OLD_BRIGHTNESS_MARKER" "$PATCHED" &&
		[ "$BRIGHTNESS_BLOCK_FOUND" -eq 1 ] && [ "$BRIGHTNESS_BLOCK_ENDED" -eq 1 ]; then
		chmod 755 "$PATCHED"
		mv -f "$PATCHED" "$QUIET_DEVICE"
		printf '%s removed asynchronous brightness restore; preserved display-handoff value\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	else
		rm -f "$PATCHED"
		printf '%s ERROR: stock brightness block not found; asynchronous restore retained\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi
if grep -q "$BESPOKE_BRIGHTNESS_MARKER" "$QUIET_DEVICE" 2>/dev/null; then
	BESPOKE_BRIGHTNESS_POLICY_READY=1
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

# The framebuffer and fixed input node exist before muOS init begins. Dispatch
# the launcher before every observer and general service, then wait only for its
# post-draw marker. RGB is skipped entirely. Entropy starts immediately after
# the visible menu so the proven CRNG/audio behaviour is preserved.
if [ -x "$CRITICAL_UI_PATCH_SOURCE" ] && [ -x "$LAUNCHER_TARGET" ] && \
	[ -s "$EARLY_INIT_TARGET" ]; then
	"$CRITICAL_UI_PATCH_SOURCE" "$SYSINIT_TARGET" "$CRITICAL_UI_BACKUP" \
		"$BESPOKE_ROOT/install.log" || :
fi

# Retire completed high-frequency diagnostics from ordinary boots. Their source
# and historical output stay on the card and in Git, so a specific probe can be
# armed deliberately for a firmware experiment. The launcher's exact post-draw
# marker and the dispatcher TSV remain sufficient for current first-frame work.
if [ ! -f "$LEAN_USERSPACE_STATE" ]; then
	LEAN_REMOVED=0
	for LEAN_PATH in \
		/opt/muos/script/init/S02rgb \
		/opt/muos/script/init/async/S04backlightprobe.sh \
		/opt/muos/script/init/async/S90bootprobe.sh; do
		if [ -e "$LEAN_PATH" ]; then
			rm -f "$LEAN_PATH"
			LEAN_REMOVED=$((LEAN_REMOVED + 1))
		fi
	done
	printf '%s\n' "removed=$LEAN_REMOVED" >"$LEAN_USERSPACE_STATE"
	printf '%s lean userspace installed; removed %s obsolete boot hooks\n' \
		"$(date -Iseconds 2>/dev/null || date)" "$LEAN_REMOVED" >>"$BESPOKE_ROOT/install.log"
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

# Preserve the original late custom-launcher hardware proof installer for a
# fresh base image. The active fixed-device path below supersedes it after the
# one-time framebuffer/input calibration state exists. The
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

# Install each content-addressed fixed-device launcher revision in the earliest normal
# init slot. S03 starts before the 1.6-second udev phase, returns immediately,
# and lets normal muOS startup continue behind the custom screen. The binary
# waits only for /dev/fb0 and /dev/input/event1 and reads evdev directly. B on
# Home is the explicit recovery handoff after normal startup is ready. Games
# and media are both compiled caches and add no storage scan to first frame.
EARLY_LAUNCHER_WANTED_REVISION=$(cat "$EARLY_LAUNCHER_REVISION_SOURCE" 2>/dev/null)
EARLY_LAUNCHER_CURRENT_REVISION=$(cat "$EARLY_LAUNCHER_STATE" 2>/dev/null)
if [ "${#EARLY_LAUNCHER_WANTED_REVISION}" -ne 64 ] ||
	! printf '%s\n' "$EARLY_LAUNCHER_WANTED_REVISION" | grep -Eq '^[0-9a-f]{64}$'; then
	EARLY_LAUNCHER_WANTED_REVISION=""
fi
if [ "$BESPOKE_BRIGHTNESS_POLICY_READY" -eq 1 ] &&
	[ -s "$LAUNCHER_OBJECT" ] && [ -s "$EARLY_INIT_SOURCE" ] &&
	[ -n "$EARLY_LAUNCHER_WANTED_REVISION" ] &&
	[ "$EARLY_LAUNCHER_CURRENT_REVISION" != "$EARLY_LAUNCHER_WANTED_REVISION" ]; then
	LAUNCHER_NEW="/tmp/dani-launcher-direct.$$"
	PATCHED="/tmp/startup-early-launcher.$$.sh"
	STARTUP_READY=0
	OPTIONAL_CORES_READY=1

	# These are the three requested libretro cores omitted by the base image.
	# Copy them only when the content-addressed launcher revision changes, never
	# during the early boot path itself.
	for CORE_NAME in $OPTIONAL_CORE_NAMES; do
		CORE_SOURCE="$OPTIONAL_CORE_SOURCE_DIR/$CORE_NAME"
		CORE_NEW="$OPTIONAL_CORE_TARGET_DIR/.$CORE_NAME.dani-new"
		CORE_TARGET="$OPTIONAL_CORE_TARGET_DIR/$CORE_NAME"
		if [ ! -s "$CORE_SOURCE" ] ||
			! cp -f "$CORE_SOURCE" "$CORE_NEW" ||
			! chmod 755 "$CORE_NEW" ||
			! mv -f "$CORE_NEW" "$CORE_TARGET"; then
			rm -f "$CORE_NEW"
			OPTIONAL_CORES_READY=0
			printf '%s ERROR: could not install optional core %s\n' \
				"$(date -Iseconds 2>/dev/null || date)" "$CORE_NAME" >>"$BESPOKE_ROOT/install.log"
		else
			printf '%s installed requested core %s (%s bytes)\n' \
				"$(date -Iseconds 2>/dev/null || date)" "$CORE_NAME" \
				"$(wc -c <"$CORE_TARGET")" >>"$BESPOKE_ROOT/install.log"
		fi
	done

	if [ "$OPTIONAL_CORES_READY" -eq 1 ] &&
		/usr/bin/ld -static --build-id=none -z noexecstack -s -e _start \
			-o "$LAUNCHER_NEW" "$LAUNCHER_OBJECT" >"$LAUNCHER_ROOT/link-early-v14-media.log" 2>&1; then
		chmod 755 "$LAUNCHER_NEW"
		if grep -q "$EARLY_STARTUP_MARKER" "$EARLY_STARTUP_TARGET"; then
			STARTUP_READY=1
		else
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
				STARTUP_READY=1
			fi
		fi

		if [ "$STARTUP_READY" -eq 1 ]; then
			mv -f "$LAUNCHER_NEW" "$LAUNCHER_TARGET"
			cp -f "$EARLY_INIT_SOURCE" "$EARLY_INIT_TARGET"
			chmod 755 "$EARLY_INIT_TARGET"
			rm -f "$EARLY_OLD_INIT_TARGET"
			printf '%s\n' "$EARLY_LAUNCHER_WANTED_REVISION" >"$EARLY_LAUNCHER_STATE"
			rm -f "$EARLY_OLD_LAUNCHER_STATE"
			printf '%s cached game/media launcher revision %s installed; active next boot\n' \
				"$(date -Iseconds 2>/dev/null || date)" "$EARLY_LAUNCHER_WANTED_REVISION" >>"$BESPOKE_ROOT/install.log"
		else
			rm -f "$PATCHED" "$LAUNCHER_NEW"
			printf '%s ERROR: stock frontend start line not found; early launcher not installed\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
		fi
	else
		rm -f "$LAUNCHER_NEW"
		printf '%s ERROR: early launcher/core installation failed; installation will retry\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$BESPOKE_ROOT/install.log"
	fi
fi

# Begin the fixed menu before the generic rcS tree. BusyBox has already mounted
# proc/dev/run through its inittab at this point, so the static launcher needs
# no service discovery. The new entry is deliberately additive: a missing or
# failed early helper returns to the stock rcS line immediately, and rcS still
# invokes S03 as the normal fallback.
if [ -s "$EARLIEST_UI_SOURCE" ] && [ -x "$EARLIEST_UI_PATCH_SOURCE" ] &&
	[ -f "$EARLIEST_UI_INITTAB" ]; then
	EARLIEST_UI_NEW="$EARLIEST_UI_TARGET.dani-new"
	if ! cmp -s "$EARLIEST_UI_SOURCE" "$EARLIEST_UI_TARGET" 2>/dev/null; then
		if cp -f "$EARLIEST_UI_SOURCE" "$EARLIEST_UI_NEW" &&
			chmod 755 "$EARLIEST_UI_NEW"; then
			mv -f "$EARLIEST_UI_NEW" "$EARLIEST_UI_TARGET"
		else
			rm -f "$EARLIEST_UI_NEW"
		fi
	fi

	[ ! -x "$EARLIEST_UI_TARGET" ] ||
		"$EARLIEST_UI_PATCH_SOURCE" "$EARLIEST_UI_INITTAB" \
			"$EARLIEST_UI_INITTAB_BACKUP" "$BESPOKE_ROOT/install.log" || :
fi

# Install only the fixed-device pieces needed by the two optional systems in
# the embedded catalog. This is a one-time user-init operation, not boot-path
# discovery: later boots read only the completed revision state.
OPTIONAL_EMULATOR_WANTED=$(cat "$OPTIONAL_EMULATOR_REVISION_SOURCE" 2>/dev/null)
OPTIONAL_EMULATOR_CURRENT=$(cat "$OPTIONAL_EMULATOR_STATE" 2>/dev/null)
if [ "${#OPTIONAL_EMULATOR_WANTED}" -eq 64 ] &&
	printf '%s\n' "$OPTIONAL_EMULATOR_WANTED" | grep -Eq '^[0-9a-f]{64}$' &&
	[ "$OPTIONAL_EMULATOR_CURRENT" != "$OPTIONAL_EMULATOR_WANTED" ]; then
	EMULATOR_WORK="/tmp/dani-optional-emulators.$$"
	NDS_STAGE="$EMULATOR_WORK/nds/emulator/drastic-trngaje"
	OPENBOR_STAGE="$EMULATOR_WORK/openbor"
	OPTIONAL_EMULATOR_FAILED=0

	rm -rf "$EMULATOR_WORK"
	mkdir -p "$EMULATOR_WORK/nds" "$OPENBOR_STAGE"

	if ! command -v unzip >/dev/null 2>&1; then
		printf '%s ERROR: unzip is unavailable; optional emulators will retry\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$OPTIONAL_EMULATOR_LOG"
		OPTIONAL_EMULATOR_FAILED=1
	elif ! unzip -q "$NDS_ARCHIVE" \
		'emulator/drastic-trngaje/drastic' \
		'emulator/drastic-trngaje/launch.sh' \
		'emulator/drastic-trngaje/show_hotkeys' \
		'emulator/drastic-trngaje/game_database.xml' \
		'emulator/drastic-trngaje/usrcheat.dat' \
		'emulator/drastic-trngaje/config/*' \
		'emulator/drastic-trngaje/system/drastic_bios_arm7.bin' \
		'emulator/drastic-trngaje/system/drastic_bios_arm9.bin' \
		'emulator/drastic-trngaje/libs/rg/*' \
		'emulator/drastic-trngaje/resources/font/*' \
		'emulator/drastic-trngaje/resources/bg/720x480/*' \
		'emulator/drastic-trngaje/resources/menu/640/*' \
		'emulator/drastic-trngaje/resources/pen/*' \
		'emulator/drastic-trngaje/microphone/*' \
		-d "$EMULATOR_WORK/nds" ||
		[ ! -s "$NDS_STAGE/drastic" ] || [ ! -s "$NDS_STAGE/launch.sh" ] ||
		[ ! -s "$NDS_STAGE/libs/rg/libadvdrastic.so" ]; then
		printf '%s ERROR: could not extract minimal RG Nintendo DS payload\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$OPTIONAL_EMULATOR_LOG"
		OPTIONAL_EMULATOR_FAILED=1
	else
		NDS_TARGET="/opt/muos/share/emulator/drastic-trngaje"
		NDS_NEW="/opt/muos/share/emulator/.drastic-trngaje.dani-new"
		if [ -f "$NDS_TARGET/config/drastic.cf2" ]; then
			cp -f "$NDS_TARGET/config/drastic.cf2" "$NDS_STAGE/config/drastic.cf2"
		fi
		chmod 755 "$NDS_STAGE/drastic" "$NDS_STAGE/launch.sh" "$NDS_STAGE/show_hotkeys"
		chmod 755 "$NDS_STAGE"/libs/rg/*
		rm -rf "$NDS_NEW"
		if mv "$NDS_STAGE" "$NDS_NEW"; then
			rm -rf "$NDS_TARGET"
			if mv "$NDS_NEW" "$NDS_TARGET"; then
				printf '%s installed RG-only DraStic payload\n' \
					"$(date -Iseconds 2>/dev/null || date)" >>"$OPTIONAL_EMULATOR_LOG"
			else
				OPTIONAL_EMULATOR_FAILED=1
			fi
		else
			OPTIONAL_EMULATOR_FAILED=1
		fi
	fi

	if ! unzip -q "$OPENBOR_ARCHIVE" \
		'emulator/openbor/OpenBOR7530' \
		'script/launch/ext-openbor.sh' \
		'script/control/openbor.sh' \
		-d "$OPENBOR_STAGE" ||
		[ ! -s "$OPENBOR_STAGE/emulator/openbor/OpenBOR7530" ] ||
		[ ! -s "$OPENBOR_STAGE/script/launch/ext-openbor.sh" ]; then
		printf '%s ERROR: could not extract OpenBOR 7530 payload\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$OPTIONAL_EMULATOR_LOG"
		OPTIONAL_EMULATOR_FAILED=1
	else
		OPENBOR_TARGET="/opt/muos/share/emulator/openbor"
		OPENBOR_DATA="/mnt/mmc/MUOS/save/openbor"
		OPENBOR_INSTALL_FAILED=0
		mkdir -p "$OPENBOR_TARGET" \
			"$OPENBOR_DATA/screenshots/openbor" \
			"$OPENBOR_DATA/saves/openbor" \
			"$OPENBOR_DATA/system/logs/openbor" \
			"$OPENBOR_DATA/system/configs/openbor" \
			"/opt/muos/script/launch" "/opt/muos/script/control"
		if ! cp -f "$OPENBOR_STAGE/emulator/openbor/OpenBOR7530" \
			"$OPENBOR_TARGET/.OpenBOR7530.dani-new" ||
			! chmod 755 "$OPENBOR_TARGET/.OpenBOR7530.dani-new" ||
			! mv -f "$OPENBOR_TARGET/.OpenBOR7530.dani-new" "$OPENBOR_TARGET/OpenBOR7530"; then
			OPENBOR_INSTALL_FAILED=1
		fi
		if [ "$OPENBOR_INSTALL_FAILED" -eq 0 ]; then
			rm -rf "$OPENBOR_TARGET/userdata"
			ln -s "$OPENBOR_DATA" "$OPENBOR_TARGET/userdata" || OPENBOR_INSTALL_FAILED=1
		fi
		for OPENBOR_SCRIPT in launch/ext-openbor.sh control/openbor.sh; do
			OPENBOR_SCRIPT_TARGET="/opt/muos/script/$OPENBOR_SCRIPT"
			if ! cp -f "$OPENBOR_STAGE/script/$OPENBOR_SCRIPT" "$OPENBOR_SCRIPT_TARGET.dani-new" ||
				! chmod 755 "$OPENBOR_SCRIPT_TARGET.dani-new" ||
				! mv -f "$OPENBOR_SCRIPT_TARGET.dani-new" "$OPENBOR_SCRIPT_TARGET"; then
				OPENBOR_INSTALL_FAILED=1
			fi
		done
		if [ "$OPENBOR_INSTALL_FAILED" -eq 0 ]; then
			printf '%s installed OpenBOR 7530 with persistent card data\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$OPTIONAL_EMULATOR_LOG"
		else
			OPTIONAL_EMULATOR_FAILED=1
			printf '%s ERROR: OpenBOR 7530 installation incomplete\n' \
				"$(date -Iseconds 2>/dev/null || date)" >>"$OPTIONAL_EMULATOR_LOG"
		fi
	fi

	rm -rf "$EMULATOR_WORK"
	if [ "$OPTIONAL_EMULATOR_FAILED" -eq 0 ]; then
		printf '%s\n' "$OPTIONAL_EMULATOR_WANTED" >"$OPTIONAL_EMULATOR_STATE"
		printf '%s optional emulator revision %s complete\n' \
			"$(date -Iseconds 2>/dev/null || date)" "$OPTIONAL_EMULATOR_WANTED" >>"$OPTIONAL_EMULATOR_LOG"
	else
		printf '%s optional emulator installation incomplete; retrying next boot\n' \
			"$(date -Iseconds 2>/dev/null || date)" >>"$OPTIONAL_EMULATOR_LOG"
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
