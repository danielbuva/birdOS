#!/bin/sh
# Preserve the one useful ROCKNIX shutdown action without sourcing its complete
# interactive profile or copying an unchanged file on every shutdown.  A
# verified sibling temporary file keeps the previous checkpoint intact until
# the new snapshot is ready for one atomic rename.

set -u
umask 077

SOURCE=/storage/.config/system/configs/system.cfg
BACKUP=/storage/.config/system/configs/system.cfg.backup
LOG=/storage/bird-data/MUOS/Bird/log/shutdown-latest.log
BACKUP_DIR=${BACKUP%/*}
LOG_DIR=${LOG%/*}
TEMP=
TEMP_STEM=${BACKUP}.tmp.$$
TEMP_SUFFIX=0

cleanup() {
 if [ -n "$TEMP" ]; then
  rm -f -- "$TEMP"
 fi
}

fail() {
 stage=$1
 code=$2
 reason=$3
 printf 'config stage=%s result=failed reason=%s exit=%s\n' \
  "$stage" "$reason" "$code"
 exit "$code"
}

interrupted() {
 trap - HUP INT TERM
 fail signal 79 interrupted
}

mkdir -p "$LOG_DIR" || exit 70
exec >>"$LOG" 2>&1 || exit 71
trap cleanup EXIT
trap interrupted HUP INT TERM

printf 'Bird fixed shutdown save start uptime='
cut -d ' ' -f 1 /proc/uptime || fail start 72 uptime-read

[ -d "$BACKUP_DIR" ] || fail preflight 73 backup-directory-missing
[ -s "$SOURCE" ] || fail source-check 74 source-missing-or-empty

if cmp -s "$SOURCE" "$BACKUP" 2>/dev/null; then
 printf 'config stage=compare result=unchanged\n'
 printf 'Bird fixed shutdown save ready uptime='
 cut -d ' ' -f 1 /proc/uptime || fail ready 75 uptime-read
 exit 0
fi
printf 'config stage=compare result=changed\n'

while [ "$TEMP_SUFFIX" -lt 32 ]; do
 CANDIDATE=$TEMP_STEM.$TEMP_SUFFIX
 if (set -C; : >"$CANDIDATE") 2>/dev/null; then
  TEMP=$CANDIDATE
  break
 fi
 TEMP_SUFFIX=$((TEMP_SUFFIX + 1))
done
[ -n "$TEMP" ] || fail temp-create 76 exclusive-suffixes-exhausted
printf 'config stage=temp-create result=ready path=%s\n' "$TEMP"

if ! cp -p -- "$SOURCE" "$TEMP"; then
 fail copy 77 copy-failed
fi
printf 'config stage=copy result=complete\n'

SOURCE_BYTES=$(wc -c <"$SOURCE") || fail verify 78 source-size-failed
TEMP_BYTES=$(wc -c <"$TEMP") || fail verify 78 temp-size-failed
SOURCE_BYTES=$((SOURCE_BYTES + 0))
TEMP_BYTES=$((TEMP_BYTES + 0))
if [ "$SOURCE_BYTES" != "$TEMP_BYTES" ] || ! cmp -s "$SOURCE" "$TEMP"; then
 fail verify 78 byte-mismatch
fi
printf 'config stage=verify result=identical bytes=%s\n' "$TEMP_BYTES"

if sync "$TEMP" 2>/dev/null; then
 printf 'config stage=flush result=complete method=file\n'
elif sync -f "$TEMP" 2>/dev/null; then
 printf 'config stage=flush result=complete method=filesystem\n'
elif sync; then
 printf 'config stage=flush result=complete method=global\n'
else
 fail flush 80 sync-failed
fi

if ! mv -f -- "$TEMP" "$BACKUP"; then
 fail commit 81 rename-failed
fi
TEMP=
printf 'config stage=commit result=complete bytes=%s\n' "$TEMP_BYTES"

# Persist the directory entry as well as the already-flushed file.  GNU
# coreutils supports a targeted syncfs through -f; the plain-sync fallback
# preserves compatibility with smaller ROCKNIX recovery toolsets.
if sync "$BACKUP_DIR" 2>/dev/null; then
 printf 'config stage=directory-flush result=complete method=directory\n'
elif sync -f "$BACKUP_DIR" 2>/dev/null; then
 printf 'config stage=directory-flush result=complete method=filesystem\n'
elif sync; then
 printf 'config stage=directory-flush result=complete method=global\n'
else
 fail directory-flush 82 sync-failed
fi

printf 'Bird fixed shutdown save ready uptime='
cut -d ' ' -f 1 /proc/uptime || fail ready 83 uptime-read
