#!/bin/bash
# Prepare ROCKNIX's native PortMaster provider only when a Port is selected.
# Bird's boot and launcher never wait for this compatibility work.

set -u

PORT_ROOT=/storage/roms/ports
PORTMASTER=$PORT_ROOT/PortMaster
CONFIG=/storage/.config/PortMaster
LEGACY=/storage/bird-data/MUOS/PortMaster
MARKER=/run/bird/ports-ready
PROVIDER_MARKER=$PORTMASTER/.bird-release-complete

[ -e "$MARKER" ] && exit 0

printf 'Bird Ports prepare start uptime='
cut -d ' ' -f 1 /proc/uptime

mkdir -p "$PORT_ROOT" /run/bird || exit 1

# Reproduce the setup half of the release's start_portmaster.sh without
# starting its network UI. All provider files still come from the immutable
# ROCKNIX release rather than a Bird reimplementation.
if [ ! -d "$CONFIG" ]; then
	cp -r /usr/config/PortMaster /storage/.config/ || exit 1
fi
cp -f /usr/config/PortMaster/control.txt "$CONFIG/control.txt" || exit 1
cp -f /usr/config/PortMaster/mapper.txt "$CONFIG/mapper.txt" || exit 1
chmod 0755 "$CONFIG/control.txt" "$CONFIG/mapper.txt" || exit 1
rm -f "$CONFIG/gamecontrollerdb.txt"
ln -s /usr/config/SDL-GameControllerDB/gamecontrollerdb.txt \
	"$CONFIG/gamecontrollerdb.txt" || exit 1

provider_ready() {
	[ -f "$PROVIDER_MARKER" ] &&
	[ -f "$PORTMASTER/pugwash" ] &&
	[ -f "$PORTMASTER/PortMaster.sh" ] &&
	[ -f "$PORTMASTER/control.txt" ] &&
	[ -f "$PORTMASTER/mod_ROCKNIX.txt" ] &&
	[ -f "$PORTMASTER/funcs.txt" ] &&
	[ -f "$PORTMASTER/oga_controls" ] &&
	[ -f "$PORTMASTER/harbourmaster" ]
}

if ! provider_ready; then
	ARCHIVE=/usr/config/PortMaster/release/PortMaster.zip
	TEMP=$PORT_ROOT/.PortMaster.bird-new
	rm -rf "$TEMP" || exit 1
	unzip -tq "$ARCHIVE" >/dev/null || exit 1
	mkdir -p "$TEMP"
	unzip -q "$ARCHIVE" -d "$TEMP" || exit 1
	for REQUIRED in pugwash PortMaster.sh control.txt mod_ROCKNIX.txt \
		funcs.txt oga_controls harbourmaster; do
		[ -f "$TEMP/PortMaster/$REQUIRED" ] || exit 1
	done
	touch "$TEMP/PortMaster/.bird-release-complete"
	rm -rf "$PORTMASTER" || exit 1
	mv "$TEMP/PortMaster" "$PORTMASTER" || exit 1
	rmdir "$TEMP" || exit 1
fi
provider_ready || exit 1

chmod 0755 "$PORTMASTER/PortMaster.sh" || exit 1
rm -f "$PORTMASTER/tasksetter"
rm -f "$CONFIG/gptokeyb"
cp -f "$PORTMASTER/gptokeyb" "$CONFIG/gptokeyb" || exit 1
chmod 0755 "$CONFIG/gptokeyb" || exit 1
cp -f "$CONFIG/control.txt" "$PORTMASTER/control.txt" || exit 1
cp -f "$CONFIG/mapper.txt" "$PORTMASTER/mapper.txt" || exit 1
cp -f "$CONFIG/gamecontrollerdb.txt" \
	"$PORTMASTER/gamecontrollerdb.txt" || exit 1
cp -f /usr/bin/oga_controls* "$PORTMASTER/" || exit 1

# Keep already-downloaded large PortMaster runtimes available without copying
# them or replacing ROCKNIX's provider. This bind is created after menu
# interaction and lives only for the running boot. `exlibs` deliberately stays
# native: exact pugwash/harbourmaster replaces it from the bundled pylibs.zip.
if [ -d "$LEGACY/libs" ]; then
	mkdir -p "$PORTMASTER/libs" || exit 1
	if ! mountpoint -q "$PORTMASTER/libs"; then
		mount --bind "$LEGACY/libs" "$PORTMASTER/libs" || exit 1
	fi
fi

touch "$MARKER" || exit 1
printf 'Bird Ports prepare ready uptime='
cut -d ' ' -f 1 /proc/uptime
