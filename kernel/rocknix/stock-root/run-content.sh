#!/bin/bash
# Route Bird selections through the exact ROCKNIX 20260701 application
# contract. No chroot, copied library set, hand-written device metadata or
# substitute audio stack exists in this path.

set -u

. /etc/profile
. /etc/os-release

REQUEST=${1:-/run/muos/dani-launch-request}
LOG_DIR=/storage/bird-data/MUOS/Bird/log
LOG=$LOG_DIR/stock-root-content-latest.log
SWAY_SOCKET=/var/run/0-runtime-dir/sway-ipc.0.sock
PORTMASTER_ONLY=0
PORT_PREP=/storage/.config/bird/prepare-ports.sh
NETWORK=/storage/.config/bird/bird-network.sh
APPLICATION_READY=/run/bird/application-contract-ready

mkdir -p "$LOG_DIR" /run/bird

if [ "$REQUEST" = --portmaster ]; then
	PORTMASTER_ONLY=1
else
	[ -s "$REQUEST" ] || exit 1
	{
		IFS= read -r KIND
		IFS= read -r REQUESTED_CORE
		IFS= read -r NAME
		IFS= read -r HOST_PATH
	} <"$REQUEST"
	case "$HOST_PATH" in
		/mnt/mmc/*) CONTENT=/storage/bird-data/${HOST_PATH#/mnt/mmc/} ;;
		*) printf 'Rejected Bird content path: %s\n' "$HOST_PATH" >"$LOG"; exit 1 ;;
	esac
fi

BOOT_ID=$(cut -c 1-8 /proc/sys/kernel/random/boot_id 2>/dev/null || printf boot)
SESSION_TICK=$(cut -d ' ' -f 1 /proc/uptime | tr -d .)
if [ "$PORTMASTER_ONLY" -eq 1 ]; then
	SESSION_KIND=portmaster
else
	SESSION_KIND=kind$KIND
fi
SESSION_LOG=$LOG_DIR/stock-root-content-$BOOT_ID-$SESSION_TICK-$SESSION_KIND.log

start_sway() {
	systemctl start sway.service || return 1
	for _ in $(seq 1 200); do
		[ -S "$SWAY_SOCKET" ] && return 0
		usleep 25000
	done
	return 1
}

ensure_content_services() {
	# Bird can be selected before the background compatibility graph completes.
	# Join only the services every proven application session actually needs.
	systemctl start dbus.service || return 1
	systemctl start pipewire.service wireplumber.service \
		pipewire-pulse.service || return 1
}

wait_application_contract() {
	[ -e "$APPLICATION_READY" ] && return 0
	# A selection may arrive from initramfs before ROCKNIX has generated the
	# exact Sway/application configuration. Request that existing job and join
	# only its first usable milestone; the launcher remains independent.
	systemctl start --no-block rocknix-autostart.service || return 1
	for _ in $(seq 1 1200); do
		[ -e "$APPLICATION_READY" ] && return 0
		usleep 25000
	done
	return 1
}

stop_sway() {
	systemctl stop sway.service || :
	for _ in $(seq 1 100); do
		[ ! -S "$SWAY_SOCKET" ] && return 0
		usleep 20000
	done
}

install_mpv_input_policy() {
	SOURCE=/flash/bird/mpv-input.conf
	TARGET=/storage/.config/mpv/input.conf
	[ -f "$SOURCE" ] || return 1
	mkdir -p /storage/.config/mpv || return 1
	if ! cmp -s "$SOURCE" "$TARGET"; then
		cp -f "$SOURCE" "$TARGET" || return 1
		printf 'Bird MPV system-volume-only policy installed\n'
	fi
}

rocknix_tuple() {
	case "$HOST_PATH" in
		*/ROMS/A2600/*)      printf '%s %s %s\n' atari2600 retroarch stella ;;
		*/ROMS/ATOMISWAVE/*) printf '%s %s %s\n' atomiswave retroarch flycast2021 ;;
		*/ROMS/CPS1/*)       printf '%s %s %s\n' cps1 retroarch fbneo ;;
		*/ROMS/CPS2/*)       printf '%s %s %s\n' cps2 retroarch fbneo ;;
		*/ROMS/CPS3/*)       printf '%s %s %s\n' cps3 retroarch fbneo ;;
		*/ROMS/DOS/*)        printf '%s %s %s\n' pc retroarch dosbox_pure ;;
		*/ROMS/DREAMCAST/*)  printf '%s %s %s\n' dreamcast retroarch flycast2021 ;;
		*/ROMS/FBNEO/*)      printf '%s %s %s\n' fbneo retroarch fbneo ;;
		*/ROMS/FC/*)         printf '%s %s %s\n' famicom retroarch nestopia ;;
		*/ROMS/GB/*)         printf '%s %s %s\n' gb retroarch gambatte ;;
		*/ROMS/GBA/*)        printf '%s %s %s\n' gba retroarch mgba ;;
		*/ROMS/GBC/*)        printf '%s %s %s\n' gbc retroarch gambatte ;;
		*/ROMS/GG/*)         printf '%s %s %s\n' gamegear retroarch gearsystem ;;
		*/ROMS/GW/*)         printf '%s %s %s\n' gameandwatch retroarch gw ;;
		*/ROMS/HBMAME/*)     printf '%s %s %s\n' arcade retroarch fbneo ;;
		*/ROMS/MAME/*)       printf '%s %s %s\n' mame retroarch mame2003_plus ;;
		*/ROMS/MD/*)         printf '%s %s %s\n' megadrive retroarch genesis_plus_gx ;;
		*/ROMS/MSX/*)        printf '%s %s %s\n' msx retroarch bluemsx ;;
		*/ROMS/N64/*)        printf '%s %s %s\n' n64 retroarch mupen64plus_next ;;
		*/ROMS/NAOMI/*)      printf '%s %s %s\n' naomi retroarch flycast2021 ;;
		*/ROMS/NDS/*)        printf '%s %s %s\n' nds drastic drastic-sa ;;
		*/ROMS/OPENBOR/*)    printf '%s %s %s\n' openbor OpenBOR OpenBOR ;;
		*/ROMS/PCE/*)        printf '%s %s %s\n' pcengine retroarch beetle_pce_fast ;;
		*/ROMS/PICO/*)       printf '%s %s %s\n' pico-8 retroarch fake08 ;;
		*/ROMS/PSP/*)        printf '%s %s %s\n' psp ppsspp ppsspp-sa ;;
		*/ROMS/Ports/*)      printf '%s %s %s\n' ports portmaster portmaster ;;
		*/ROMS/SNES/*)       printf '%s %s %s\n' snes retroarch snes9x ;;
		*) return 1 ;;
	esac
}

run_selected() {
	if [ "$PORTMASTER_ONLY" -eq 1 ]; then
		"$PORT_PREP" || return 1
		"$NETWORK" start || :
		/usr/bin/start_portmaster.sh
		STATUS=$?
		"$NETWORK" stop || :
		return "$STATUS"
	fi
	case "$KIND" in
		1|2|4|5)
			read -r PLATFORM EMULATOR CORE < <(rocknix_tuple) || return 1
			/usr/bin/runemu.sh "$CONTENT" "-P$PLATFORM" \
				"--core=$CORE" "--emulator=$EMULATOR" --controllers=""
			;;
		3)
			"$PORT_PREP" || return 1
			PORT_SCRIPT=/storage/roms/ports/${CONTENT##*/}
			# This one pre-existing custom launcher is intentionally retained
			# until its game is reinstalled from the exact provider. Preserve its
			# basename while translating only its two old storage roots.
			if [ "${CONTENT##*/}" = StardewValley.sh ]; then
				mkdir -p /run/bird/ports
				PORT_SCRIPT=/run/bird/ports/StardewValley.sh
				sed \
					-e 's#/mnt/mmc/MUOS#/storage/bird-data/MUOS#g' \
					-e 's#/mnt/mmc/ports#/storage/roms/ports#g' \
					"$CONTENT" >"$PORT_SCRIPT" || return 1
				chmod 0755 "$PORT_SCRIPT" || return 1
			fi
			/usr/bin/runemu.sh "$PORT_SCRIPT" -Pports \
				--core=portmaster --emulator=portmaster --controllers=""
			;;
		6)
			install_mpv_input_policy || return 1
			/usr/bin/start_mplayer.sh "$CONTENT"
			;;
		*) return 1 ;;
	esac
}

{
	printf 'Bird ROCKNIX session start uptime='
	cut -d ' ' -f 1 /proc/uptime
	if [ "$PORTMASTER_ONLY" -eq 0 ]; then
		printf 'kind=%s core=%s name=%s host=%s content=%s\n' \
			"$KIND" "$REQUESTED_CORE" "$NAME" "$HOST_PATH" "$CONTENT"
	fi
	if wait_application_contract; then
		printf 'Bird application contract ready uptime=%s dispatch=' \
			"$(cat "$APPLICATION_READY")"
		cut -d ' ' -f 1 /proc/uptime
		[ "$PORTMASTER_ONLY" -eq 1 ] || rm -f "$REQUEST"
		if start_sway; then
			ensure_content_services || STATUS=1
			: >/var/log/exec.log
			if [ "${STATUS:-0}" -eq 0 ]; then
				run_selected
				STATUS=$?
			fi
			if [ -s /var/log/exec.log ]; then
				printf '%s\n' '--- ROCKNIX application log (last 256 KiB) ---'
				tail -c 262144 /var/log/exec.log
				printf '%s\n' '--- end ROCKNIX application log ---'
			fi
			stop_sway
		else
			STATUS=1
		fi
	else
		STATUS=1
	fi
	printf 'Bird ROCKNIX session result=%s uptime=' "$STATUS"
	cut -d ' ' -f 1 /proc/uptime
} >"$SESSION_LOG" 2>&1

cp -f "$SESSION_LOG" "$LOG" || :
exit "$STATUS"
