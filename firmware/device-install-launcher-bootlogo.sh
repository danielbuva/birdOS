#!/bin/sh
set -eu

SOURCE="/mnt/mmc/.firmware-work/boot-resource/dani-boot-resource.img"
WORK_DIR="/mnt/mmc/.firmware-work/boot-resource"
BACKUP="$WORK_DIR/device-boot-resource-before-dani.img"
MARKER="$WORK_DIR/launcher-bootlogo-installed"
LOG_DIR="/mnt/mmc/MUOS/log"
LOG="$LOG_DIR/firmware-launcher-bootlogo-install.log"
TARGET="/dev/mmcblk0p2"
EXPECTED_SIZE=33554432
STOCK_SHA="59e302e1d1734990fea85a809704375db01c200c26505ab1f428519a511c458f"
CANDIDATE_SHA="38f42814f8523225e6695f6e446eb435a821410c53214ded80be729f2b138fd7"

mkdir -p "$WORK_DIR" "$LOG_DIR"

UPTIME_MS() {
	awk '{ printf "%d", $1 * 1000 }' /proc/uptime
}

LOG_EVENT() {
	printf '[%s ms] %s\n' "$(UPTIME_MS)" "$*" >>"$LOG"
}

HASH_FILE() {
	sha256sum "$1" | awk '{print $1}'
}

HASH_TARGET() {
	dd if="$TARGET" bs=1M count=32 2>/dev/null | sha256sum | awk '{print $1}'
}

FAIL() {
	LOG_EVENT "ERROR: $*"
	exit 1
}

: >"$LOG"
LOG_EVENT "RG34XX-SP launcher frame-zero installer start"
[ -b "$TARGET" ] || FAIL "target partition missing: $TARGET"
[ -f "$SOURCE" ] || FAIL "candidate missing: $SOURCE"
[ "$(wc -c <"$SOURCE")" -eq "$EXPECTED_SIZE" ] || FAIL "candidate size is not 32 MiB"
[ "$(HASH_FILE "$SOURCE")" = "$CANDIDATE_SHA" ] || FAIL "candidate checksum mismatch"

CURRENT_SHA=$(HASH_TARGET)
LOG_EVENT "current boot-resource SHA-256: $CURRENT_SHA"
if [ "$CURRENT_SHA" = "$CANDIDATE_SHA" ]; then
	printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
	LOG_EVENT "candidate already active"
	exit 0
fi
[ "$CURRENT_SHA" = "$STOCK_SHA" ] || FAIL "active boot-resource is neither known stock nor candidate"

if [ ! -f "$BACKUP" ]; then
	LOG_EVENT "backing up active stock boot-resource"
	dd if="$TARGET" of="$BACKUP" bs=1M count=32 conv=fsync
	[ "$(wc -c <"$BACKUP")" -eq "$EXPECTED_SIZE" ] || FAIL "backup size mismatch"
	[ "$(HASH_FILE "$BACKUP")" = "$STOCK_SHA" ] || FAIL "backup checksum mismatch"
	LOG_EVENT "stock boot-resource backup complete"
else
	[ "$(HASH_FILE "$BACKUP")" = "$STOCK_SHA" ] || FAIL "existing backup checksum mismatch"
	LOG_EVENT "using verified existing stock backup"
fi

LOG_EVENT "writing launcher-aligned boot-resource candidate"
dd if="$SOURCE" of="$TARGET" bs=1M count=32 conv=fsync
sync
WRITTEN_SHA=$(HASH_TARGET)
if [ "$WRITTEN_SHA" != "$CANDIDATE_SHA" ]; then
	LOG_EVENT "write verification failed ($WRITTEN_SHA); restoring stock"
	dd if="$BACKUP" of="$TARGET" bs=1M count=32 conv=fsync
	sync
	[ "$(HASH_TARGET)" = "$STOCK_SHA" ] || FAIL "automatic stock restore failed"
	FAIL "candidate write failed; stock restored"
fi

printf '%s\n' "$CANDIDATE_SHA" >"$MARKER"
LOG_EVENT "SUCCESS: launcher frame zero verified; visible on next cold boot"
exit 0
