#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
CARD=${1:-/Volumes/dani-sp}
PAYLOAD="$CARD/MUOS/bespoke-launcher"
HOST_BIOS_ROOT=${DANI_BIOS_ROOT:-"$HOME/Games/bios"}

if [ ! -d "$CARD/ROMS" ] || [ ! -d "$CARD/MUOS" ]; then
	printf 'Dani SP card not found at %s\n' "$CARD" >&2
	printf 'Insert the card, or pass its mount path as the first argument.\n' >&2
	exit 1
fi

printf 'Scanning %s/ROMS and %s/MEDIA...\n' "$CARD" "$CARD"
MEDIA_ROOT="$CARD/MEDIA" "$ROOT/generate-launcher-catalog.sh" "$CARD/ROMS"
"$ROOT/build-launcher-object.sh"

mkdir -p "$PAYLOAD"
mkdir -p "$PAYLOAD/optional-cores"

stage_file() {
	source_file=$1
	destination_file=$2
	temporary_file="$destination_file.rebuild-new"
	COPYFILE_DISABLE=1 cp -f "$source_file" "$temporary_file"
	if [ "$(shasum -a 256 "$source_file" | cut -d ' ' -f 1)" != \
		"$(shasum -a 256 "$temporary_file" | cut -d ' ' -f 1)" ]; then
		printf 'Copy verification failed: %s\n' "$source_file" >&2
		rm -f "$temporary_file"
		exit 1
	fi
	mv -f "$temporary_file" "$destination_file"
}

stage_file_if_changed() {
	source_file=$1
	destination_file=$2
	if [ ! -f "$destination_file" ] ||
		[ "$(shasum -a 256 "$source_file" | cut -d ' ' -f 1)" != \
		"$(shasum -a 256 "$destination_file" | cut -d ' ' -f 1)" ]; then
		stage_file "$source_file" "$destination_file"
	fi
}

stage_tree_if_missing() {
	source_dir=$1
	destination_dir=$2
	[ -d "$destination_dir" ] && return 0
	temporary_dir="$destination_dir.rebuild-new.$$"
	COPYFILE_DISABLE=1 cp -R "$source_dir" "$temporary_dir"
	mv "$temporary_dir" "$destination_dir"
}

stage_file "$ROOT/launcher/dani-launcher.o" "$PAYLOAD/dani-launcher.o"
stage_file "$ROOT/launcher/catalog.revision" "$PAYLOAD/catalog.revision"
stage_file "$ROOT/launcher/library.inventory.tsv" "$PAYLOAD/library.inventory.tsv"
stage_file "$ROOT/launcher/S03danilauncher" "$PAYLOAD/S03danilauncher"
stage_file "$ROOT/launcher/boot.wav" "$PAYLOAD/boot.wav"
stage_file "$ROOT/launcher/README.md" "$PAYLOAD/README.md"
for CORE in gw_libretro.so bluemsx_libretro.so fake08_libretro.so; do
	stage_file "$ROOT/launcher/optional-cores/$CORE" "$PAYLOAD/optional-cores/$CORE"
done
stage_file "$ROOT/launcher/optional-cores/README.md" "$PAYLOAD/optional-cores/README.md"
stage_file "$ROOT/99-frontend-native-log.sh" "$CARD/MUOS/init/99-boot-timing-marker.sh"

# User-owned system files are deliberately staged from the local BIOS library,
# not checked into this project. They are copied on the Mac and add no boot work.
if [ -f "$HOST_BIOS_ROOT/dc/naomi.zip" ]; then
	mkdir -p "$CARD/MUOS/bios/dc"
	stage_file_if_changed "$HOST_BIOS_ROOT/dc/naomi.zip" "$CARD/MUOS/bios/dc/naomi.zip"
fi
if [ -d "$HOST_BIOS_ROOT/Databases" ] && [ -d "$HOST_BIOS_ROOT/Machines" ]; then
	stage_tree_if_missing "$HOST_BIOS_ROOT/Databases" "$CARD/MUOS/bios/Databases"
	stage_tree_if_missing "$HOST_BIOS_ROOT/Machines" "$CARD/MUOS/bios/Machines"
fi

chmod 755 "$PAYLOAD/S03danilauncher" "$CARD/MUOS/init/99-boot-timing-marker.sh"
sync

game_count=$(awk -F '\t' 'NR > 1 && $1 == "PLAY" {count++} END {print count + 0}' \
	"$ROOT/launcher/library.inventory.tsv")
system_count=$(awk -F '\t' 'NR > 1 && $1 == "PLAY" {seen[$2] = 1} END {for (item in seen) count++; print count + 0}' \
	"$ROOT/launcher/library.inventory.tsv")
printf '\nCached %s games across %s systems.\n' "$game_count" "$system_count"
printf 'Payload verified and staged at %s.\n' "$PAYLOAD"
printf 'Boot once to install it, then boot again to use the rebuilt cache.\n'
