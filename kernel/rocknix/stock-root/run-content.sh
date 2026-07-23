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
	rm -f "$REQUEST"
	case "$HOST_PATH" in
		/mnt/mmc/*) CONTENT=/storage/bird-data/${HOST_PATH#/mnt/mmc/} ;;
		*) printf 'Rejected Bird content path: %s\n' "$HOST_PATH" >"$LOG"; exit 1 ;;
	esac
fi

start_sway() {
	systemctl start sway.service || return 1
	for _ in $(seq 1 200); do
		[ -S "$SWAY_SOCKET" ] && return 0
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
		/usr/bin/start_portmaster.sh
		return
	fi
	case "$KIND" in
		1|2|4|5)
			read -r PLATFORM EMULATOR CORE < <(rocknix_tuple) || return 1
			/usr/bin/runemu.sh "$CONTENT" "-P$PLATFORM" \
				"--core=$CORE" "--emulator=$EMULATOR" --controllers=""
			;;
		3)
			# Installed muOS-era PortMaster scripts contain /mnt/mmc paths.
			# Translate only the selected script into tmpfs; ROCKNIX still owns
			# its runtime, mapper, controller and performance policy.
			sed 's#/mnt/mmc#/storage/bird-data#g' "$CONTENT" >/run/bird/port-launch.sh
			chmod 0755 /run/bird/port-launch.sh
			/usr/bin/runemu.sh /run/bird/port-launch.sh -Pports \
				--core=portmaster --emulator=portmaster --controllers=""
			;;
		6) /usr/bin/start_mplayer.sh "$CONTENT" ;;
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
	start_sway || exit 1
	run_selected
	STATUS=$?
	stop_sway
	printf 'Bird ROCKNIX session result=%s uptime=' "$STATUS"
	cut -d ' ' -f 1 /proc/uptime
	exit "$STATUS"
} >"$LOG" 2>&1
