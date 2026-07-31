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
FIXED_PORT_ROOT=/storage/bird-data/ROMS/Ports
FIXED_STORAGE=/storage/.config/bird/fixed-storage.sh
PROVIDER_MANIFEST=/storage/.config/bird/portmaster-provider.manifest.tsv
PROVIDER_VERIFIER=/storage/.config/bird/verify-portmaster-provider.sh
PROVIDER_READY_CHECKPOINT=

manifest_checkpoint() {
	local DIGEST_LINE DIGEST REVISION
	DIGEST_LINE=$(sha256sum "$PROVIDER_MANIFEST" 2>/dev/null) || return 1
	DIGEST=${DIGEST_LINE%% *}
	case "$DIGEST" in
		????????????????????????????????????????????????????????????????) ;;
		*) return 1 ;;
	esac
	case "$DIGEST" in *[!0-9a-f]*) return 1 ;; esac
	REVISION=$(awk -F '\t' '
		$1 == "revision" && NF == 2 {value=$2; count++}
		END {if (count != 1) exit 1; print value}
	' "$PROVIDER_MANIFEST") || return 1
	case "$REVISION" in
		????.??.??-????) ;;
		*) return 1 ;;
	esac
	printf 'bird-portmaster-v3:%s:%s\n' "$REVISION" "$DIGEST"
}

checkpoint_file_matches() {
	local FILE=$1 EXPECTED=$2 VALUE BYTES
	[ -f "$FILE" ] && [ ! -L "$FILE" ] || return 1
	VALUE=$(cat "$FILE") || return 1
	BYTES=$(wc -c <"$FILE" | tr -d '[:space:]') || return 1
	[ "$BYTES" = "$((${#EXPECTED} + 1))" ] || return 1
	[ "$VALUE" = "$EXPECTED" ]
}

ready_marker_valid() {
	provider_install_checkpoint_valid || return 1
	checkpoint_file_matches "$MARKER" "$PROVIDER_READY_CHECKPOINT"
}

provider_checkpoint() {
	# All three consumers establish the fixed /run PYTHONPYCACHEPREFIX in
	# run-content.sh before reaching this preparation boundary.
	"$PROVIDER_VERIFIER" --allow-isolated-python-cache \
		"$PROVIDER_MANIFEST" "$1"
}

provider_install_checkpoint_valid() {
	local CHECKPOINT
	[ -d "$PORTMASTER" ] && [ ! -L "$PORTMASTER" ] || return 1
	CHECKPOINT=$(manifest_checkpoint) || return 1
	checkpoint_file_matches "$PROVIDER_MARKER" "$CHECKPOINT" || return 1
	PROVIDER_READY_CHECKPOINT=$CHECKPOINT
}

provider_absent_or_empty() {
	if [ ! -e "$PORTMASTER" ] && [ ! -L "$PORTMASTER" ]; then
		return 0
	fi
	[ -d "$PORTMASTER" ] && [ ! -L "$PORTMASTER" ] || return 1
	! find "$PORTMASTER" -mindepth 1 -maxdepth 1 -print -quit | grep -q .
}

bootstrap_provider() {
	local ARCHIVE TEMP REQUIRED CHECKPOINT
	ARCHIVE=/usr/config/PortMaster/release/PortMaster.zip
	TEMP=$PORT_ROOT/.PortMaster.bird-new
	if [ -e "$TEMP" ] || [ -L "$TEMP" ]; then
		[ -d "$TEMP" ] && [ ! -L "$TEMP" ] || {
			printf 'Bird Ports bootstrap staging path is unsafe: %s\n' \
				"$TEMP" >&2
			return 1
		}
		rm -rf "$TEMP" || return 1
	fi
	unzip -tq "$ARCHIVE" >/dev/null || return 1
	mkdir -p "$TEMP" || return 1
	unzip -q "$ARCHIVE" -d "$TEMP" || return 1
	for REQUIRED in pugwash PortMaster.sh control.txt mod_ROCKNIX.txt \
		funcs.txt oga_controls harbourmaster; do
		[ -f "$TEMP/PortMaster/$REQUIRED" ] || return 1
	done
	CHECKPOINT=$(provider_checkpoint "$TEMP/PortMaster") || {
		printf 'Bird Ports bootstrap archive does not match the exact provider manifest; provider remains unselected.\n' >&2
		rm -rf "$TEMP"
		return 1
	}
	(umask 077; printf '%s\n' "$CHECKPOINT" \
		>"$TEMP/PortMaster/.bird-release-complete") || return 1
	if [ -d "$PORTMASTER" ]; then
		rmdir "$PORTMASTER" || return 1
	fi
	mv "$TEMP/PortMaster" "$PORTMASTER" || return 1
	rmdir "$TEMP" || return 1
	PROVIDER_READY_CHECKPOINT=$CHECKPOINT
}

# A restarted compatibility service must never be allowed to leave Ports on a
# generic ROCKNIX storage view. Repair the fixed namespace before honoring the
# per-boot provider marker.
if [ ! "$PORT_ROOT" -ef "$FIXED_PORT_ROOT" ]; then
	"$FIXED_STORAGE" || exit 1
fi
[ "$PORT_ROOT" -ef "$FIXED_PORT_ROOT" ] || exit 1

mkdir -p "$PORT_ROOT" /run/bird || exit 1

[ -x "$PROVIDER_VERIFIER" ] && [ ! -L "$PROVIDER_VERIFIER" ] || {
	printf 'Bird Ports exact provider verifier is missing or unsafe: %s\n' \
		"$PROVIDER_VERIFIER" >&2
	exit 1
}
[ -f "$PROVIDER_MANIFEST" ] && [ ! -L "$PROVIDER_MANIFEST" ] || {
	printf 'Bird Ports exact provider manifest is missing or unsafe: %s\n' \
		"$PROVIDER_MANIFEST" >&2
	exit 1
}

# /run is fresh each boot. Full provider-tree verification belongs only to
# transactional installation/replacement. Normal launches trust the immutable
# completion checkpoint written after that transaction and never hash the
# 445 MB tree. The per-boot checkpoint makes the lightweight setup run once.
if ready_marker_valid; then
	printf 'Bird Ports cached ready uptime='
	cut -d ' ' -f 1 /proc/uptime
	exit 0
fi
if [ -e "$MARKER" ] || [ -L "$MARKER" ]; then
	[ -f "$MARKER" ] && [ ! -L "$MARKER" ] || {
		printf 'Bird Ports per-boot marker is unsafe: %s\n' "$MARKER" >&2
		exit 1
	}
	rm -f "$MARKER" || exit 1
fi

if provider_install_checkpoint_valid; then
	:
else
	if ! provider_absent_or_empty; then
		printf 'Bird Ports provider is present but lacks this release installation checkpoint; preserving it without replacement: %s\n' \
			"$PORTMASTER" >&2
		exit 1
	fi
	printf 'Bird Ports provider is absent or empty; attempting the pinned bootstrap archive.\n'
	bootstrap_provider || exit 1
fi
checkpoint_file_matches "$PROVIDER_MARKER" "$PROVIDER_READY_CHECKPOINT" || {
	printf 'Bird Ports provider did not satisfy its installation checkpoint after bootstrap: %s\n' \
		"$PORTMASTER" >&2
	exit 1
}
printf 'Bird Ports prepare start uptime='
cut -d ' ' -f 1 /proc/uptime

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

# Exact PortMaster.sh repairs its archive modes before entering the UI. Do the
# same only when needed before Bird launches a game directly.
if [ ! -x "$PORTMASTER/gptokeyb" ] || \
	[ ! -x "$PORTMASTER/runtimes/love_11.5/love.aarch64" ]; then
	chmod -R a+x "$PORTMASTER" || exit 1
fi

checkpoint_file_matches "$PROVIDER_MARKER" "$PROVIDER_READY_CHECKPOINT" || {
	printf 'Bird Ports provider changed before readiness publication; refusing the per-boot marker: %s\n' \
		"$PORTMASTER" >&2
	exit 1
}

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

printf '%s\n' 'Bird Ports executable mount state:'
grep -E ' /storage/(bird-data|roms) ' /proc/mounts || :
if [ ! -x "$PORTMASTER/gptokeyb" ]; then
	printf 'Bird Ports provider is not executable: %s\n' \
		"$PORTMASTER/gptokeyb"
	exit 126
fi
MARKER_TEMP=$MARKER.tmp.$$
(umask 077; printf '%s\n' "$PROVIDER_READY_CHECKPOINT" >"$MARKER_TEMP") || exit 1
mv -f "$MARKER_TEMP" "$MARKER" || { rm -f "$MARKER_TEMP"; exit 1; }
printf 'Bird Ports prepare ready uptime='
cut -d ' ' -f 1 /proc/uptime
