#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CARD=${1:-/Volumes/BIRD-DATA}
STORAGE_WORK="$CARD/MUOS/boot-timing/fixed-storage"
ENTROPY_WORK="$CARD/MUOS/boot-timing/entropy-once"
FIRMWARE_WORK="$CARD/.firmware-work"
POWER_IMAGE="$ROOT/firmware/work/power-key-128-build/bird-boot-power-key-128.img"
POWER_SHA="$ROOT/firmware/work/power-key-128-build/candidate.sha256"

[ -d "$CARD/MUOS/init" ] || {
	printf 'error: mounted birdOS card not found: %s\n' "$CARD" >&2
	exit 1
}

SCRIPTS="
$ROOT/storage/fixed-storage.sh
$ROOT/storage/fixed-start.sh
$ROOT/storage/fixed-bind.sh
$ROOT/storage/device-install-fixed-mount.sh
$ROOT/storage/device-install-fixed-bind.sh
$ROOT/userspace/S01entropy-once
$ROOT/userspace/device-install-entropy-once.sh
$ROOT/firmware/device-install-power-key-128.sh
$ROOT/99-frontend-native-log.sh
"
for SCRIPT in $SCRIPTS; do
	sh -n "$SCRIPT"
done

mkdir -p "$STORAGE_WORK" "$ENTROPY_WORK" "$FIRMWARE_WORK"
[ -f "$POWER_IMAGE" ] || {
	printf 'error: build the power-key candidate first with firmware/build-power-key-128.sh\n' >&2
	exit 1
}
[ -f "$POWER_SHA" ] || {
	printf 'error: power-key candidate checksum missing\n' >&2
	exit 1
}
COPYFILE_DISABLE=1 cp -f "$ROOT/storage/fixed-storage.sh" "$STORAGE_WORK/.fixed-storage.sh.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/storage/fixed-start.sh" "$STORAGE_WORK/.fixed-start.sh.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/storage/fixed-bind.sh" "$STORAGE_WORK/.fixed-bind.sh.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/userspace/S01entropy-once" "$ENTROPY_WORK/.S01entropy-once.new"
COPYFILE_DISABLE=1 cp -f "$POWER_IMAGE" "$FIRMWARE_WORK/.bird-boot-power-key-128.img.new"
COPYFILE_DISABLE=1 cp -f "$POWER_SHA" "$FIRMWARE_WORK/.bird-boot-power-key-128.sha256.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/firmware/device-install-power-key-128.sh" "$CARD/MUOS/init/.80-install-power-key-128.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/storage/device-install-fixed-mount.sh" "$CARD/MUOS/init/.81-install-fixed-mount.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/storage/device-install-fixed-bind.sh" "$CARD/MUOS/init/.82-install-fixed-bind.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/userspace/device-install-entropy-once.sh" "$CARD/MUOS/init/.83-install-entropy-once.new"
COPYFILE_DISABLE=1 cp -f "$ROOT/99-frontend-native-log.sh" "$CARD/MUOS/init/.99-boot-timing-marker.fixed-batch-new"

cmp "$ROOT/storage/fixed-storage.sh" "$STORAGE_WORK/.fixed-storage.sh.new"
cmp "$ROOT/storage/fixed-start.sh" "$STORAGE_WORK/.fixed-start.sh.new"
cmp "$ROOT/storage/fixed-bind.sh" "$STORAGE_WORK/.fixed-bind.sh.new"
cmp "$ROOT/userspace/S01entropy-once" "$ENTROPY_WORK/.S01entropy-once.new"
cmp "$POWER_IMAGE" "$FIRMWARE_WORK/.bird-boot-power-key-128.img.new"
cmp "$POWER_SHA" "$FIRMWARE_WORK/.bird-boot-power-key-128.sha256.new"
cmp "$ROOT/firmware/device-install-power-key-128.sh" "$CARD/MUOS/init/.80-install-power-key-128.new"
cmp "$ROOT/storage/device-install-fixed-mount.sh" "$CARD/MUOS/init/.81-install-fixed-mount.new"
cmp "$ROOT/storage/device-install-fixed-bind.sh" "$CARD/MUOS/init/.82-install-fixed-bind.new"
cmp "$ROOT/userspace/device-install-entropy-once.sh" "$CARD/MUOS/init/.83-install-entropy-once.new"
cmp "$ROOT/99-frontend-native-log.sh" "$CARD/MUOS/init/.99-boot-timing-marker.fixed-batch-new"

mv -f "$STORAGE_WORK/.fixed-storage.sh.new" "$STORAGE_WORK/fixed-storage.sh"
mv -f "$STORAGE_WORK/.fixed-start.sh.new" "$STORAGE_WORK/fixed-start.sh"
mv -f "$STORAGE_WORK/.fixed-bind.sh.new" "$STORAGE_WORK/fixed-bind.sh"
mv -f "$ENTROPY_WORK/.S01entropy-once.new" "$ENTROPY_WORK/S01entropy-once"
mv -f "$FIRMWARE_WORK/.bird-boot-power-key-128.img.new" "$FIRMWARE_WORK/bird-boot-power-key-128.img"
mv -f "$FIRMWARE_WORK/.bird-boot-power-key-128.sha256.new" "$FIRMWARE_WORK/bird-boot-power-key-128.sha256"
mv -f "$CARD/MUOS/init/.80-install-power-key-128.new" "$CARD/MUOS/init/80-install-power-key-128.sh"
mv -f "$CARD/MUOS/init/.81-install-fixed-mount.new" "$CARD/MUOS/init/81-install-fixed-mount.sh"
mv -f "$CARD/MUOS/init/.82-install-fixed-bind.new" "$CARD/MUOS/init/82-install-fixed-bind.sh"
mv -f "$CARD/MUOS/init/.83-install-entropy-once.new" "$CARD/MUOS/init/83-install-entropy-once.sh"
mv -f "$CARD/MUOS/init/.99-boot-timing-marker.fixed-batch-new" "$CARD/MUOS/init/99-boot-timing-marker.sh"

chmod 755 "$STORAGE_WORK/fixed-storage.sh" "$STORAGE_WORK/fixed-start.sh" \
	"$STORAGE_WORK/fixed-bind.sh" "$ENTROPY_WORK/S01entropy-once" \
	"$CARD/MUOS/init/80-install-power-key-128.sh" \
	"$CARD/MUOS/init/81-install-fixed-mount.sh" \
	"$CARD/MUOS/init/82-install-fixed-bind.sh" \
	"$CARD/MUOS/init/83-install-entropy-once.sh" \
	"$CARD/MUOS/init/99-boot-timing-marker.sh"

rm -f "$STORAGE_WORK"/._fixed-*.sh "$ENTROPY_WORK/._S01entropy-once" \
	"$FIRMWARE_WORK/._bird-boot-power-key-128.img" \
	"$FIRMWARE_WORK/._bird-boot-power-key-128.sha256" \
	"$CARD/MUOS/init/._80-install-power-key-128.sh" \
	"$CARD/MUOS/init/._81-install-fixed-mount.sh" \
	"$CARD/MUOS/init/._82-install-fixed-bind.sh" \
	"$CARD/MUOS/init/._83-install-entropy-once.sh" \
	"$CARD/MUOS/init/._99-boot-timing-marker.sh"
sync

printf 'Staged batch: 128 ms power key, fixed ROM mount/binds, and one-shot entropy.\n'
printf 'First boot installs all four; boot two tests userspace and programs the PMIC.\n'
printf 'Cold boot three is the first valid 128 ms power-button test.\n'
