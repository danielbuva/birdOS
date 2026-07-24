#!/bin/sh
# Guarded deployment of the compatibility-first stock-root milestone. P5 and
# content bytes stay untouched. V6.18 anchors storage after prepare_sysroot,
# removes the redundant UI start and explicitly activates saved networking.
# It retains the exact kernel and complete working ROCKNIX userspace.
# The exact ROCKNIX writable filesystem remains a loop image on p6, and the
# accepted v5.4 kernel remains on p1 as a fallback.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/dani-sp}
CANDIDATE=${CANDIDATE:-$ROOT/kernel/work/bird-rocknix-stock-root-v6.18/card}
STORAGE_SOURCE=${STORAGE_SOURCE:-/Users/dani/rocknix-reference-result/storage.ext4}
PORTMASTER_ARCHIVE=${PORTMASTER_ARCHIVE:-$ROOT/kernel/work/rocknix-system-exact-20260701/usr/config/PortMaster/release/PortMaster.zip}
RUNTIME=$DATA/MUOS/runtime/ROCKNIX-SYSTEM
STORAGE_TARGET=$DATA/MUOS/runtime/ROCKNIX-STORAGE

V54_KERNEL_SHA=a53a3483731d28d2e96e53def0fba347fa53607aa9fbda8bfb82db677126daef
ROCKNIX_KERNEL_SHA=af4e75cb30b097ee5764764eb056d686bc00c6bd03fefece26b0ebbaa7fbb673
DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
RUNTIME_SHA=6e2112fc9dc81d5fee944f2534346a8f20674f40e23a0a85bb795218d31eadac
STORAGE_SHA=12affdad7bc2042cb590fea60fc015a7ee8d4374ebcc3b1c11098a64b9ffa3be
PORTMASTER_ARCHIVE_SHA=9d6f25d461afced95569923a57c6a9c42df225190c043d74fe2ec0edcf40a477
PORTMASTER_PUGWASH_SHA=3b9ea60ccf202f64155c669fd0b2b18fcb0e5c72e293ad0c61f7c2f2fdcb51d8
STORAGE_BYTES=268435456
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

file_bytes() {
	stat -f '%z' "$1"
}

ext4_magic() {
	od -An -tx1 -j 1080 -N 2 "$1" | tr -d ' \n'
}

[ -d "$BIRD" ] || fail "BIRD volume missing: $BIRD"
[ -d "$DATA" ] || fail "data volume missing: $DATA"
[ -d "$CANDIDATE" ] || fail "built candidate missing: $CANDIDATE"
[ -f "$STORAGE_SOURCE" ] || fail 'reference ROCKNIX storage image missing'
[ -f "$RUNTIME" ] || fail 'exact ROCKNIX runtime missing on card'
for FILE in post-flash.sh mount-storage.sh SYSTEM KERNEL dtb.img \
	bird-initramfs.cpio.gz \
	extlinux/extlinux.conf extlinux/extlinux.fallback.conf \
	bird/090-ui_service bird/999-export bird/dani-launcher bird/bird-pidwait bird/essway.service \
	bird/rocknix.target bird/rocknix-automount.service \
	bird/rocknix-autostart.service bird/rocknix-report-stats.service \
	bird/NetworkManager.service bird/iwd.service \
	bird/systemd-resolved.service bird/systemd-timesyncd.service \
	bird/systemd-rfkill.service \
	bird/bird-fixed-controls bird/bird-fixed-controls.service \
	bird/bird-fixed-control-exit.sh \
	bird/bird-powerstate bird/bird-powerstate.service \
	bird/bird-autostart bird/bird-autostart-noop bird/bird-save-config.sh \
	bird/bird-save-config.service bird/bird-fixed-sway.sh \
	bird/bird-swap.conf \
	bird/supervisor.sh bird/run-content.sh \
	bird/prepare-ports.sh bird/fixed-storage.sh \
	bird/first-frame-prep.sh bird/capture-boot-state.sh \
	bird/bird-network.sh bird/mpv-input.conf; do
	[ -f "$CANDIDATE/$FILE" ] || fail "candidate payload missing: $FILE"
done

WHOLE=$(field "$BIRD" 'Part of Whole')
[ -n "$WHOLE" ] || fail 'cannot identify card parent'
[ "$WHOLE" = "$(field "$DATA" 'Part of Whole')" ] || fail 'volumes are on different disks'
[ "$(field "/dev/$WHOLE" 'Device Location')" = External ] || \
	[ "$(field "/dev/$WHOLE" 'Protocol')" = 'Secure Digital' ] || \
	fail 'refusing disk that is neither external nor a physical SD card'
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

# The old muOS layout separated launcher scripts in ROMS/Ports from their game
# directories in /ports. ROCKNIX's native contract keeps both under one tree.
# Validate every rename before changing the card; all moves stay on the same
# ExFAT filesystem and therefore do not recopy the 16 GiB library.
LEGACY_PORTS=$DATA/ports
NATIVE_PORTS=$DATA/ROMS/Ports
if [ -d "$LEGACY_PORTS" ]; then
	find "$LEGACY_PORTS" -mindepth 1 -maxdepth 1 -name '.*' | grep -q . && \
		fail 'hidden legacy Port entry requires manual review'
	for ENTRY in "$LEGACY_PORTS"/*; do
		[ -e "$ENTRY" ] || break
		[ -d "$ENTRY" ] || fail "legacy Port entry is not a directory: $ENTRY"
		NAME=${ENTRY##*/}
		[ ! -e "$NATIVE_PORTS/$NAME" ] || fail "native Port collision: $NAME"
	done
fi

portmaster_ready() {
	[ -f "$NATIVE_PORTS/PortMaster/.bird-release-complete" ] &&
	[ -f "$NATIVE_PORTS/PortMaster/pugwash" ] &&
	[ -f "$NATIVE_PORTS/PortMaster/PortMaster.sh" ] &&
	[ -f "$NATIVE_PORTS/PortMaster/control.txt" ] &&
	[ -f "$NATIVE_PORTS/PortMaster/mod_ROCKNIX.txt" ] &&
	[ -f "$NATIVE_PORTS/PortMaster/funcs.txt" ] &&
	[ -f "$NATIVE_PORTS/PortMaster/oga_controls" ] &&
	[ -f "$NATIVE_PORTS/PortMaster/harbourmaster" ]
}

if ! portmaster_ready; then
	[ -f "$PORTMASTER_ARCHIVE" ] || fail 'exact PortMaster archive missing'
	[ "$(sha256 "$PORTMASTER_ARCHIVE")" = "$PORTMASTER_ARCHIVE_SHA" ] || \
		fail 'exact PortMaster archive changed'
	/usr/bin/unzip -tq "$PORTMASTER_ARCHIVE" >/dev/null || \
		fail 'exact PortMaster archive failed integrity test'
fi

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

if [ -f "$STORAGE_TARGET" ]; then
	[ "$(file_bytes "$STORAGE_TARGET")" = "$STORAGE_BYTES" ] || fail 'installed STORAGE size changed'
	[ "$(ext4_magic "$STORAGE_TARGET")" = 53ef ] || fail 'installed STORAGE is not ext4'
else
	COPYFILE_DISABLE=1 cp -f "$STORAGE_SOURCE" "$DATA/MUOS/runtime/.ROCKNIX-STORAGE.new"
	[ "$(sha256 "$DATA/MUOS/runtime/.ROCKNIX-STORAGE.new")" = "$STORAGE_SHA" ] || fail 'storage copy failed'
	mv -f "$DATA/MUOS/runtime/.ROCKNIX-STORAGE.new" "$STORAGE_TARGET"
fi

mkdir -p "$NATIVE_PORTS"
# Seed the exact release provider now so the first game does not pay its unzip
# cost. Complete and verify this transaction before moving any game directory.
# prepare-ports.sh reproduces the bootstrap on-device for a fresh or repaired
# card and then attaches already-downloaded large runtime assets.
if ! portmaster_ready; then
	PORTMASTER_TEMP=$NATIVE_PORTS/.PortMaster.bird-new
	rm -rf "$PORTMASTER_TEMP"
	mkdir -p "$PORTMASTER_TEMP"
	/usr/bin/unzip -q "$PORTMASTER_ARCHIVE" -d "$PORTMASTER_TEMP" || \
		fail 'exact PortMaster extraction failed'
	for REQUIRED in pugwash PortMaster.sh control.txt mod_ROCKNIX.txt \
		funcs.txt oga_controls harbourmaster; do
		[ -f "$PORTMASTER_TEMP/PortMaster/$REQUIRED" ] || \
			fail "exact PortMaster file missing after extraction: $REQUIRED"
	done
	[ "$(sha256 "$PORTMASTER_TEMP/PortMaster/pugwash")" = "$PORTMASTER_PUGWASH_SHA" ] || \
		fail 'extracted exact PortMaster provider changed'
	touch "$PORTMASTER_TEMP/PortMaster/.bird-release-complete"
	rm -rf "$NATIVE_PORTS/PortMaster"
	mv "$PORTMASTER_TEMP/PortMaster" "$NATIVE_PORTS/PortMaster"
	rmdir "$PORTMASTER_TEMP" || fail 'PortMaster temporary directory remained'
fi
portmaster_ready || fail 'installed PortMaster provider is incomplete'

MOVED_PORTS=0
if [ -d "$LEGACY_PORTS" ]; then
	for ENTRY in "$LEGACY_PORTS"/*; do
		[ -e "$ENTRY" ] || break
		NAME=${ENTRY##*/}
		[ ! -e "$NATIVE_PORTS/$NAME" ] || fail "native Port collision during move: $NAME"
		mv "$ENTRY" "$NATIVE_PORTS/"
		MOVED_PORTS=$((MOVED_PORTS + 1))
	done
	rmdir "$LEGACY_PORTS" || fail 'legacy Port directory did not become empty'
fi

mkdir -p "$BIRD/bird" "$BIRD/extlinux" "$DATA/MUOS/Bird/boot-state"
for FILE in post-flash.sh mount-storage.sh SYSTEM bird-initramfs.cpio.gz; do
	COPYFILE_DISABLE=1 cp -f "$CANDIDATE/$FILE" "$BIRD/$FILE"
done
for FILE in 090-ui_service 999-export dani-launcher bird-pidwait essway.service rocknix.target \
	rocknix-automount.service rocknix-autostart.service \
	rocknix-report-stats.service \
	NetworkManager.service iwd.service systemd-resolved.service \
	systemd-timesyncd.service systemd-rfkill.service bird-fixed-controls \
	bird-fixed-controls.service bird-fixed-control-exit.sh \
	bird-powerstate bird-powerstate.service bird-swap.conf \
	bird-autostart bird-autostart-noop bird-save-config.sh bird-save-config.service \
	bird-fixed-sway.sh \
	supervisor.sh run-content.sh \
	prepare-ports.sh fixed-storage.sh first-frame-prep.sh \
	capture-boot-state.sh bird-network.sh mpv-input.conf; do
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
	"$BIRD/bird-initramfs.cpio.gz" \
	"$BIRD/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.fallback.conf" \
	"$BIRD/bird"/* "$STORAGE_TARGET" 2>/dev/null || :
xattr -cr "$NATIVE_PORTS/PortMaster" 2>/dev/null || :
find "$BIRD/bird" "$BIRD/extlinux" -name '._*' -delete
find "$NATIVE_PORTS/PortMaster" -name '._*' -delete
find "$NATIVE_PORTS" -maxdepth 1 -name '._PortMaster' -delete
find "$BIRD" -maxdepth 1 -name '._KERNEL*' -delete
find "$BIRD" -maxdepth 1 -name '._dtb.img' -delete
find "$BIRD" -maxdepth 1 -name '._post-flash.sh' -delete
find "$BIRD" -maxdepth 1 -name '._mount-storage.sh' -delete
find "$BIRD" -maxdepth 1 -name '._SYSTEM' -delete
find "$BIRD" -maxdepth 1 -name '._bird-initramfs.cpio.gz' -delete
find "$DATA/MUOS/runtime" -maxdepth 1 -name '._ROCKNIX-STORAGE' -delete
sync

[ "$(sha256 "$BIRD/KERNEL")" = "$ROCKNIX_KERNEL_SHA" ] || fail 'installed KERNEL verification failed'
[ "$(sha256 "$BIRD/KERNEL.fallback")" = "$V54_KERNEL_SHA" ] || fail 'installed fallback verification failed'
[ "$(sha256 "$BIRD/dtb.img")" = "$DTB_SHA" ] || fail 'installed DTB verification failed'
[ "$(file_bytes "$STORAGE_TARGET")" = "$STORAGE_BYTES" ] || fail 'installed STORAGE size verification failed'
[ "$(ext4_magic "$STORAGE_TARGET")" = 53ef ] || fail 'installed STORAGE ext4 verification failed'
cmp "$CANDIDATE/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.conf" || fail 'active extlinux verification failed'
cmp "$CANDIDATE/bird-initramfs.cpio.gz" "$BIRD/bird-initramfs.cpio.gz" || fail 'early initramfs verification failed'

printf 'Bird stock-root v6.18 staged on /dev/%s.\n' "$WHOLE"
printf 'Moved %s Port data directories into the native ROCKNIX tree.\n' "$MOVED_PORTS"
printf 'Generic storage discovery replaced by the fixed p6 Bird view.\n'
printf 'MPV physical volume ownership is system-only.\n'
printf 'Bird starts before generic userspace; autostart cannot repaint it.\n'
printf 'Network is PortMaster-only; unused fixed-profile units are masked.\n'
printf 'Early content selections queue once; fixed input and power events replace polling.\n'
printf 'Resolver and time synchronization now share that PortMaster-only gate.\n'
printf 'Bird and the release-matched H700 input module now begin in external initramfs.\n'
printf 'Battery percentage is kernel-driven, uevent-fed and shown in Bird.\n'
printf 'The original pidfd-adopted Bird owns input continuously across switch_root.\n'
printf 'Storage and config descriptors are acknowledged before special-mount handoff.\n'
printf 'The acknowledgement is an explicit post-prepare_sysroot FIFO event.\n'
printf 'Early content selections remain queued until the app contract is ready.\n'
printf 'Late generic display ownership and fixed-profile autostart no-ops are removed.\n'
printf 'Shutdown keeps the config checkpoint without a full interactive-profile load.\n'
printf 'The low-battery red LED threshold is fixed at 41 percent.\n'
printf 'Storage readiness has a bounded self-healing probe until success.\n'
printf 'Storage/config are retained after prepare_sysroot and before switch_root.\n'
printf 'A failed final-root anchor retires into the systemd fallback.\n'
printf 'The application compositor uses one fixed card1/DSI-1 profile.\n'
printf 'RF-kill state management now exists only inside network sessions.\n'
printf 'PortMaster networking waits for one usable NetworkManager link.\n'
printf 'The saved Wi-Fi profile is explicitly activated only for PortMaster.\n'
printf 'Generic autostart no longer starts the already-running Bird UI again.\n'
printf 'p5 was not modified; p6 content bytes were preserved by same-volume moves.\n'
printf 'Exact ROCKNIX KERNEL: %s\n' "$ROCKNIX_KERNEL_SHA"
printf 'Automatic fallback KERNEL: %s\n' "$V54_KERNEL_SHA"
printf 'Test early interaction timing, then repeat the broad compatibility gate.\n'
