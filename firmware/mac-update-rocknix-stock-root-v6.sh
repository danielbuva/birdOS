#!/bin/sh
# Guarded deployment of the compatibility-first stock-root milestone. p5 and
# the user's library stay untouched. The exact ROCKNIX writable filesystem is
# copied as a loop image on p6, and the accepted v5.4 kernel remains on p1 as
# an automatic fallback.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/dani-sp}
CANDIDATE=${CANDIDATE:-$ROOT/kernel/work/bird-rocknix-stock-root-v6/card}
STORAGE_SOURCE=${STORAGE_SOURCE:-/Users/dani/rocknix-reference-result/storage.ext4}
RUNTIME=$DATA/MUOS/runtime/ROCKNIX-SYSTEM
STORAGE_TARGET=$DATA/MUOS/runtime/ROCKNIX-STORAGE

V54_KERNEL_SHA=a53a3483731d28d2e96e53def0fba347fa53607aa9fbda8bfb82db677126daef
ROCKNIX_KERNEL_SHA=af4e75cb30b097ee5764764eb056d686bc00c6bd03fefece26b0ebbaa7fbb673
DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
RUNTIME_SHA=6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac
STORAGE_SHA=12affdad7bc2042cb590fea60fc015a7ee8d4374ebcc3b1c11098a64b9ffa3be
BIRD_BYTES=134217728
BIRD_OFFSET=16777216
DISK_BYTES=512074186752
ROOT_BYTES=8589934592
ROOT_OFFSET=163577856
DATA_BYTES=503320672768
DATA_OFFSET=8753512448

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

field() {
	diskutil info "$1" | awk -F: -v key="$2" \
		'$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {sub(/^[[:space:]]*/, "", $2); print $2; exit}'
}

disk_bytes() {
	field "$1" 'Disk Size' | sed -n 's/.*(\([0-9][0-9]*\) Bytes).*/\1/p'
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

[ -d "$BIRD" ] || fail "BIRD volume missing: $BIRD"
[ -d "$DATA" ] || fail "data volume missing: $DATA"
[ -d "$CANDIDATE" ] || fail "built candidate missing: $CANDIDATE"
[ -f "$STORAGE_SOURCE" ] || fail 'reference ROCKNIX storage image missing'
[ -f "$RUNTIME" ] || fail 'exact ROCKNIX runtime missing on card'

WHOLE=$(field "$BIRD" 'Part of Whole')
[ -n "$WHOLE" ] || fail 'cannot identify card parent'
[ "$WHOLE" = "$(field "$DATA" 'Part of Whole')" ] || fail 'volumes are on different disks'
[ "$(field "/dev/$WHOLE" 'Device Location')" = External ] || fail 'refusing non-external disk'
[ "$(field "/dev/$WHOLE" 'Removable Media')" = Removable ] || fail 'refusing non-removable disk'
[ "$(disk_bytes "/dev/$WHOLE")" = "$DISK_BYTES" ] || fail 'whole-card size changed'
[ "$(field "$BIRD" 'Device Identifier')" = "${WHOLE}s1" ] || fail 'BIRD is not p1'
[ "$(field "$DATA" 'Device Identifier')" = "${WHOLE}s6" ] || fail 'data is not p6'
[ "$(field "$BIRD" 'Partition Offset' | awk '{print $1}')" = "$BIRD_OFFSET" ] || fail 'p1 offset changed'
[ "$(disk_bytes "$BIRD")" = "$BIRD_BYTES" ] || fail 'p1 size changed'
[ "$(field "/dev/${WHOLE}s5" 'Partition Offset' | awk '{print $1}')" = "$ROOT_OFFSET" ] || fail 'p5 offset changed'
[ "$(disk_bytes "/dev/${WHOLE}s5")" = "$ROOT_BYTES" ] || fail 'p5 size changed'
[ "$(field "$DATA" 'Partition Offset' | awk '{print $1}')" = "$DATA_OFFSET" ] || fail 'p6 offset changed'
[ "$(disk_bytes "$DATA")" = "$DATA_BYTES" ] || fail 'p6 size changed'
[ "$(field "$BIRD" 'Volume Read-Only')" = No ] || fail 'BIRD is read-only'
[ "$(field "$DATA" 'Volume Read-Only')" = No ] || fail 'data is read-only'

[ "$(sha256 "$CANDIDATE/KERNEL")" = "$ROCKNIX_KERNEL_SHA" ] || fail 'candidate KERNEL changed'
[ "$(sha256 "$CANDIDATE/dtb.img")" = "$DTB_SHA" ] || fail 'candidate DTB changed'
[ "$(sha256 "$RUNTIME")" = "$RUNTIME_SHA" ] || fail 'card SYSTEM changed'
[ "$(sha256 "$STORAGE_SOURCE")" = "$STORAGE_SHA" ] || fail 'reference STORAGE changed'

CURRENT=$(sha256 "$BIRD/KERNEL")
case "$CURRENT" in
	"$V54_KERNEL_SHA"|"$ROCKNIX_KERNEL_SHA") ;;
	*) fail "unexpected active KERNEL: $CURRENT" ;;
esac

if [ -f "$BIRD/KERNEL.fallback" ]; then
	[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$V54_KERNEL_SHA" ] || fail 'fallback KERNEL changed'
elif [ "$CURRENT" = "$V54_KERNEL_SHA" ]; then
	COPYFILE_DISABLE=1 cp -f "$BIRD/KERNEL" "$BIRD/.KERNEL.fallback.new"
	[ "$(sha256 "$BIRD/.KERNEL.fallback.new")" = "$V54_KERNEL_SHA" ] || fail 'fallback copy failed'
	mv -f "$BIRD/.KERNEL.fallback.new" "$BIRD/KERNEL.fallback"
else
	fail 'v5.4 fallback KERNEL is missing'
fi

COPYFILE_DISABLE=1 cp -f "$STORAGE_SOURCE" "$DATA/MUOS/runtime/.ROCKNIX-STORAGE.new"
[ "$(sha256 "$DATA/MUOS/runtime/.ROCKNIX-STORAGE.new")" = "$STORAGE_SHA" ] || fail 'storage copy failed'
mv -f "$DATA/MUOS/runtime/.ROCKNIX-STORAGE.new" "$STORAGE_TARGET"

mkdir -p "$BIRD/bird" "$BIRD/extlinux" "$DATA/MUOS/Bird/boot-state"
for FILE in post-flash.sh mount-storage.sh SYSTEM; do
	COPYFILE_DISABLE=1 cp -f "$CANDIDATE/$FILE" "$BIRD/$FILE"
done
for FILE in 090-ui_service dani-launcher essway.service rocknix.target supervisor.sh run-content.sh; do
	COPYFILE_DISABLE=1 cp -f "$CANDIDATE/bird/$FILE" "$BIRD/bird/$FILE"
done
COPYFILE_DISABLE=1 cp -f "$CANDIDATE/extlinux/extlinux.fallback.conf" \
	"$BIRD/extlinux/extlinux.fallback.conf"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE/dtb.img" "$BIRD/dtb.img"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE/KERNEL" "$BIRD/.KERNEL.stock-root.new"
[ "$(sha256 "$BIRD/.KERNEL.stock-root.new")" = "$ROCKNIX_KERNEL_SHA" ] || fail 'temporary KERNEL copy failed'
mv -f "$BIRD/.KERNEL.stock-root.new" "$BIRD/KERNEL"

# Activate the candidate only after every payload and fallback is durable.
printf '0\n' >"$DATA/MUOS/Bird/boot-state/stock-root-attempts"
COPYFILE_DISABLE=1 cp -f "$CANDIDATE/extlinux/extlinux.conf" \
	"$BIRD/extlinux/.extlinux.conf.new"
sync
mv -f "$BIRD/extlinux/.extlinux.conf.new" "$BIRD/extlinux/extlinux.conf"

xattr -c "$BIRD/KERNEL" "$BIRD/KERNEL.fallback" "$BIRD/dtb.img" \
	"$BIRD/post-flash.sh" "$BIRD/mount-storage.sh" "$BIRD/SYSTEM" \
	"$BIRD/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.fallback.conf" \
	"$BIRD/bird"/* "$STORAGE_TARGET" 2>/dev/null || :
find "$BIRD/bird" "$BIRD/extlinux" -name '._*' -delete
find "$BIRD" -maxdepth 1 -name '._KERNEL*' -delete
find "$BIRD" -maxdepth 1 -name '._dtb.img' -delete
find "$BIRD" -maxdepth 1 -name '._post-flash.sh' -delete
find "$BIRD" -maxdepth 1 -name '._mount-storage.sh' -delete
find "$BIRD" -maxdepth 1 -name '._SYSTEM' -delete
find "$DATA/MUOS/runtime" -maxdepth 1 -name '._ROCKNIX-STORAGE' -delete
sync

[ "$(sha256 "$BIRD/KERNEL")" = "$ROCKNIX_KERNEL_SHA" ] || fail 'installed KERNEL verification failed'
[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$V54_KERNEL_SHA" ] || fail 'installed fallback verification failed'
[ "$(sha256 "$BIRD/dtb.img")" = "$DTB_SHA" ] || fail 'installed DTB verification failed'
[ "$(sha256 "$STORAGE_TARGET")" = "$STORAGE_SHA" ] || fail 'installed STORAGE verification failed'
cmp "$CANDIDATE/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.conf" || fail 'active extlinux verification failed'

printf 'Bird stock-root v6 staged on /dev/%s.\n' "$WHOLE"
printf 'p5 and the p6 library were not modified.\n'
printf 'Exact ROCKNIX KERNEL: %s\n' "$ROCKNIX_KERNEL_SHA"
printf 'Automatic fallback KERNEL: %s\n' "$V54_KERNEL_SHA"
printf 'Test broad compatibility first; boot timing is intentionally deferred.\n'
