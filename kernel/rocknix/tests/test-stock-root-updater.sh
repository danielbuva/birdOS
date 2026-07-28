#!/bin/sh
# Host-only transaction tests for the macOS v6.23 updater. Publication and
# selector switching run on a private hdiutil-backed FAT image; disk identity
# metadata comes from a TSV fixture, so no physical block device is addressed.

set -eu

if [ "$(uname -s)" != Darwin ]; then
	printf '%s\n' 'stock-root updater test skipped: macOS host required'
	exit 0
fi

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
UPDATER=$ROOT/firmware/mac-update-rocknix-stock-root-v6.sh
MIGRATION=$ROOT/firmware/mac-migrate-rocknix-ports.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-updater.XXXXXX")
HOST_TMP=$TMP/host-tmp
FAT_DEVICE=
cleanup() {
	[ -z "$FAT_DEVICE" ] || hdiutil detach "$FAT_DEVICE" >/dev/null 2>&1 || :
	rm -rf "$TMP"
}
trap cleanup EXIT INT TERM HUP
mkdir -p "$HOST_TMP"

# Exercise the real publication filesystem, not a spoofed mode field. The
# hdiutil image is private test storage and is never mapped to the physical SD.
BIRD=$TMP/BIRD
FAT_IMAGE=$TMP/bird-fat.dmg
mkdir -p "$BIRD"
hdiutil create -quiet -size 64m -fs MS-DOS -volname BIRDTEST \
	"$FAT_IMAGE"
ATTACH_OUTPUT=$(hdiutil attach -nobrowse -noautoopen -mountpoint "$BIRD" \
	"$FAT_IMAGE")
FAT_DEVICE=$(printf '%s\n' "$ATTACH_OUTPUT" | \
	awk '$2 == "DOS_FAT_32" {print $1; exit}')
[ -n "$FAT_DEVICE" ] || {
	printf '%s\n' 'could not attach temporary FAT updater fixture' >&2
	exit 1
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

bytes() {
	stat -f '%z' "$1"
}

mode() {
	stat -f '%Lp' "$1"
}

CARD=$TMP/build/card
MANIFEST=$TMP/build/deploy-manifest.tsv
DATA=$TMP/BIRD-DATA
STORAGE_SOURCE=$TMP/storage.ext4
RUNTIME=$DATA/MUOS/runtime/ROCKNIX-SYSTEM
INFO=$TMP/device-info.tsv
UPDATER_RELEASE_ID=v6.23

mkdir -p "$CARD/bird" "$CARD/extlinux" "$BIRD/bird" "$BIRD/extlinux" \
	"$DATA/MUOS/runtime" "$DATA/MUOS/Bird/boot-state/releases/v6.22" \
	"$DATA/ROMS/Ports/PortMaster" "$CARD/bird/empty-runtime"
PRIOR_ATTEMPTS=$DATA/MUOS/Bird/boot-state/releases/v6.22/attempts
RELEASE_ATTEMPTS=$DATA/MUOS/Bird/boot-state/releases/v6.23/attempts
printf '1\n' >"$PRIOR_ATTEMPTS"

printf 'candidate-kernel\n' >"$CARD/KERNEL"
printf 'fixed-dtb\n' >"$CARD/dtb.img"
printf 'early-initramfs\n' >"$CARD/bird-initramfs.cpio.gz"
printf '#!/bin/sh\nexit 0\n' >"$CARD/post-flash.sh"
printf '#!/bin/sh\nexit 0\n' >"$CARD/mount-storage.sh"
printf '#!/bin/sh\nexit 0\n' >"$CARD/bird/bird-suspend.sh"
: >"$CARD/SYSTEM"
printf '%s\n' \
	'LABEL BIRD' \
	'  LINUX /bird-releases/v6.23/KERNEL' \
	'  INITRD /bird-releases/v6.23/bird-initramfs.cpio.gz' \
	'  FDT /bird-releases/v6.23/dtb.img' \
	'  APPEND bird_release=v6.23' >"$CARD/extlinux/extlinux.conf"
printf '%s\n' \
	'LABEL BIRD-FALLBACK' \
	'  LINUX /KERNEL.fallback' \
	'  FDT /dtb.img' >"$CARD/extlinux/extlinux.fallback.conf"
chmod 0700 "$CARD/KERNEL" "$CARD/dtb.img"
chmod 0755 "$CARD/post-flash.sh" "$CARD/mount-storage.sh" \
	"$CARD/bird/bird-suspend.sh"
chmod 0644 "$CARD/SYSTEM" "$CARD/bird-initramfs.cpio.gz" \
	"$CARD/extlinux/extlinux.conf" "$CARD/extlinux/extlinux.fallback.conf"

printf 'exact-runtime\n' >"$RUNTIME"
dd if=/dev/zero of="$STORAGE_SOURCE" bs=2048 count=1 2>/dev/null
printf '\123\357' | dd of="$STORAGE_SOURCE" bs=1 seek=1080 conv=notrunc 2>/dev/null

ROCKNIX_KERNEL_SHA=$(sha256 "$CARD/KERNEL")
DTB_SHA=$(sha256 "$CARD/dtb.img")
RUNTIME_SHA=$(sha256 "$RUNTIME")
STORAGE_SHA=$(sha256 "$STORAGE_SOURCE")
V54_KERNEL=$TMP/fallback-kernel
printf 'fallback-kernel\n' >"$V54_KERNEL"
V54_KERNEL_SHA=$(sha256 "$V54_KERNEL")
AUTOSTART_SHA=1111111111111111111111111111111111111111111111111111111111111111
OFFICIAL_INIT_SHA=2222222222222222222222222222222222222222222222222222222222222222
JOYPAD_SHA=3333333333333333333333333333333333333333333333333333333333333333
INIT_BUSYBOX_SHA=4444444444444444444444444444444444444444444444444444444444444444
PORTMASTER_ARCHIVE_SHA=5555555555555555555555555555555555555555555555555555555555555555
for NAME in pugwash PortMaster.sh control.txt mod_ROCKNIX.txt funcs.txt \
	oga_controls harbourmaster; do
	printf 'test provider %s\n' "$NAME" >"$DATA/ROMS/Ports/PortMaster/$NAME"
done
chmod 0755 "$DATA/ROMS/Ports/PortMaster/pugwash" \
	"$DATA/ROMS/Ports/PortMaster/PortMaster.sh" \
	"$DATA/ROMS/Ports/PortMaster/harbourmaster"
PORTMASTER_PUGWASH_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/pugwash")
PORTMASTER_SH_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/PortMaster.sh")
PORTMASTER_MOD_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/mod_ROCKNIX.txt")
PORTMASTER_FUNCS_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/funcs.txt")
PORTMASTER_HARBOURMASTER_SHA=$(sha256 "$DATA/ROMS/Ports/PortMaster/harbourmaster")

FILE_LIST=$TMP/file-list
find "$CARD" -type f -print | LC_ALL=C sort >"$FILE_LIST"
DIR_LIST=$TMP/dir-list
find "$CARD" -mindepth 1 -type d -empty -print | LC_ALL=C sort >"$DIR_LIST"
{
	printf 'schema\tbird-deploy-v1\n'
	printf 'release\tv6.23\n'
	printf 'target-mode-policy\tfat-capability\n'
	printf 'source-commit\ttest\tclean\n'
	printf 'input\tKERNEL\t700\t%s\t%s\ttest:KERNEL\n' \
		"$(bytes "$CARD/KERNEL")" "$ROCKNIX_KERNEL_SHA"
	printf 'input\tdtb.img\t700\t%s\t%s\ttest:dtb.img\n' \
		"$(bytes "$CARD/dtb.img")" "$DTB_SHA"
	printf 'input\tROCKNIX-SYSTEM\t644\t%s\t%s\ttest:SYSTEM\n' \
		"$(bytes "$RUNTIME")" "$RUNTIME_SHA"
	printf 'input\tROCKNIX-STORAGE\t644\t%s\t%s\ttest:STORAGE\n' \
		"$(bytes "$STORAGE_SOURCE")" "$STORAGE_SHA"
	printf 'input\tusr/bin/autostart\t755\t1\t%s\ttest:autostart\n' "$AUTOSTART_SHA"
	printf 'input\tinitramfs/init\t755\t1\t%s\ttest:init\n' "$OFFICIAL_INIT_SHA"
	printf 'input\trocknix-singleadc-joypad.ko\t644\t1\t%s\ttest:joypad\n' "$JOYPAD_SHA"
	printf 'input\tinitramfs/busybox\t755\t1\t%s\ttest:busybox\n' "$INIT_BUSYBOX_SHA"
	printf 'input\tPortMaster.zip\t644\t1\t%s\ttest:PortMaster.zip\n' "$PORTMASTER_ARCHIVE_SHA"
	printf 'input\tKERNEL.fallback\t%s\t%s\t%s\ttest:fallback-KERNEL\n' \
		"$(mode "$V54_KERNEL")" "$(bytes "$V54_KERNEL")" "$V54_KERNEL_SHA"
	for NAME in pugwash PortMaster.sh mod_ROCKNIX.txt funcs.txt harbourmaster; do
		FILE=$DATA/ROMS/Ports/PortMaster/$NAME
		printf 'input\tPortMaster/%s\t%s\t%s\t%s\ttest:PortMaster/%s\n' \
			"$NAME" "$(mode "$FILE")" "$(bytes "$FILE")" "$(sha256 "$FILE")" "$NAME"
	done
	while IFS= read -r DIRECTORY; do
		printf 'dir\t%s\t%s\n' "${DIRECTORY#"$CARD"/}" "$(mode "$DIRECTORY")"
	done <"$DIR_LIST"
	while IFS= read -r FILE; do
		RELATIVE=${FILE#"$CARD/"}
		printf 'file\t%s\t%s\t%s\t%s\n' "$RELATIVE" \
			"$(mode "$FILE")" "$(bytes "$FILE")" "$(sha256 "$FILE")"
	done <"$FILE_LIST"
} >"$MANIFEST"

cp "$V54_KERNEL" "$BIRD/KERNEL"
cp "$CARD/dtb.img" "$BIRD/dtb.img"
printf '#!/bin/sh\n# preserved legacy hook\nexit 0\n' >"$BIRD/post-flash.sh"
cp "$CARD/mount-storage.sh" "$BIRD/mount-storage.sh"
cp "$CARD/SYSTEM" "$BIRD/SYSTEM"
printf 'legacy-runtime\n' >"$BIRD/bird/legacy-marker"
printf 'LABEL LEGACY\n  LINUX /KERNEL\n' >"$BIRD/extlinux/extlinux.conf"
touch "$DATA/ROMS/Ports/PortMaster/.bird-release-complete"
LEGACY_HOOK_SHA=$(sha256 "$BIRD/post-flash.sh")

printf '%s\t%s\t%s\n' \
	"$BIRD" 'Part of Whole' testdisk \
	"$DATA" 'Part of Whole' testdisk \
	'/dev/testdisk' 'Device Location' External \
	'/dev/testdisk' 'Protocol' 'Secure Digital' \
	'/dev/testdisk' 'Removable Media' Removable \
	'/dev/testdisk' 'Disk Size' '512074186752 Bytes (512074186752 Bytes)' \
	"$BIRD" 'Device Identifier' testdisks1 \
	"$BIRD" 'Partition Offset' '16777216 Bytes' \
	"$BIRD" 'Disk Size' '134217728 Bytes (134217728 Bytes)' \
	"$BIRD" 'Volume Read-Only' No \
	"$BIRD" 'File System Personality' 'MS-DOS FAT32' \
	'/dev/testdisks5' 'Partition Offset' '163577856 Bytes' \
	'/dev/testdisks5' 'Disk Size' '8589934592 Bytes (8589934592 Bytes)' \
	"$DATA" 'Device Identifier' testdisks6 \
	"$DATA" 'Partition Offset' '8753512448 Bytes' \
	"$DATA" 'Disk Size' '503320672768 Bytes (503320672768 Bytes)' \
	"$DATA" 'Volume Read-Only' No >"$INFO"

run_updater() {
	FAILPOINT=$1
	LC_ALL=${TEST_LOCALE:-C} TMPDIR=${TEST_TMPDIR:-$HOST_TMP} \
	BIRD_HOST_TEST_MODE=1 BIRD=$BIRD DATA=$DATA \
	BIRD_RELEASE_ID=$UPDATER_RELEASE_ID \
	CANDIDATE=$CARD MANIFEST=$MANIFEST \
	STORAGE_SOURCE=$STORAGE_SOURCE BIRD_DEVICE_INFO=$INFO \
	BIRD_TEST_FAILPOINT=$FAILPOINT \
	BIRD_TEST_LOCK_GATE=${LOCK_GATE:-} \
	BIRD_TEST_MANIFEST_GATE=${MANIFEST_GATE:-} \
	"$UPDATER"
}

run_migration() {
	LC_ALL=${TEST_LOCALE:-C} TMPDIR=${TEST_TMPDIR:-$HOST_TMP} \
	BIRD_HOST_TEST_MODE=1 BIRD=$BIRD DATA=$DATA \
	BIRD_DEVICE_INFO=${MIGRATION_INFO:-$INFO} \
	BIRD_TEST_LOCK_GATE=${MIGRATION_GATE:-} \
		"$MIGRATION"
}

ACTIVE_BEFORE=$(sha256 "$BIRD/extlinux/extlinux.conf")
mkdir -p "$DATA/ports/LegacyGame"
if run_updater none >"$TMP/legacy.out" 2>"$TMP/legacy.err"; then
	printf '%s\n' 'legacy Port migration unexpectedly ran inside updater' >&2
	exit 1
fi
grep -q 'legacy /ports data must be migrated separately' "$TMP/legacy.err"
[ -d "$DATA/ports/LegacyGame" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
rm -rf "$DATA/ports"

# Replacing the caller-owned manifest after its complete preflight must not
# affect any later field lookup or staging loop. The injected replacement
# points KERNEL one level above the hidden stage; the private snapshot must be
# the only manifest read, so that out-of-stage destination never appears.
ORIGINAL_MANIFEST=$MANIFEST
SWAPPABLE_MANIFEST=$TMP/deploy-manifest-swappable.tsv
MALICIOUS_MANIFEST=$TMP/deploy-manifest-traversal-after-preflight.tsv
ESCAPE_SOURCE=$CARD/../escaped-output
ESCAPE_TARGET=$BIRD/bird-releases/escaped-output
cp "$ORIGINAL_MANIFEST" "$SWAPPABLE_MANIFEST"
cp "$CARD/KERNEL" "$ESCAPE_SOURCE"
awk -F '\t' 'BEGIN {OFS="\t"}
	$1 == "file" && $2 == "KERNEL" {$2="../escaped-output"}
	{print}
' "$ORIGINAL_MANIFEST" >"$MALICIOUS_MANIFEST"
MANIFEST=$SWAPPABLE_MANIFEST
MANIFEST_GATE=$TMP/manifest-snapshot-gate
mkdir "$MANIFEST_GATE"
run_updater during-release-stage >"$TMP/manifest-swap.out" \
	2>"$TMP/manifest-swap.err" &
MANIFEST_SWAP_JOB=$!
GATE_WAIT=0
while [ ! -f "$MANIFEST_GATE/snapshot-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/manifest-swap.err" >&2
		printf '%s\n' 'updater did not complete manifest snapshot preflight' >&2
		exit 1
	}
	sleep 0.02
done
mv -f "$MALICIOUS_MANIFEST" "$SWAPPABLE_MANIFEST"
: >"$MANIFEST_GATE/release-snapshot"
set +e
wait "$MANIFEST_SWAP_JOB"
MANIFEST_SWAP_STATUS=$?
set -e
[ "$MANIFEST_SWAP_STATUS" -ne 0 ] || {
	printf '%s\n' 'manifest-swap stage failure unexpectedly succeeded' >&2
	exit 1
}
grep -q 'host-only injected failure: during-release-stage' \
	"$TMP/manifest-swap.err"
[ ! -e "$ESCAPE_TARGET" ] || {
	printf '%s\n' 'mutable manifest escaped the private release stage' >&2
	exit 1
}
[ ! -e "$BIRD/bird-releases/v6.23" ]
MANIFEST_GATE=
MANIFEST=$ORIGINAL_MANIFEST
rm -f "$ESCAPE_SOURCE"

if run_updater kill-during-release-stage >"$TMP/kill.out" 2>"$TMP/kill.err"; then
	printf '%s\n' 'SIGKILL stage injection unexpectedly succeeded' >&2
	exit 1
fi
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
find "$BIRD/bird-releases" -maxdepth 1 -name '.v6.23.new.*' | grep -q .

if run_updater during-release-stage >"$TMP/stage.out" 2>"$TMP/stage.err"; then
	printf '%s\n' 'incomplete-stage injection unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'host-only injected failure: during-release-stage' "$TMP/stage.err"
[ ! -e "$BIRD/bird-releases/v6.23" ]
if find "$BIRD/bird-releases" -maxdepth 1 -name '.v6.23.new.*' | grep -q .; then
	printf '%s\n' 'incomplete release staging directory survived' >&2
	exit 1
fi
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
[ "$(sha256 "$BIRD/post-flash.sh")" = "$LEGACY_HOOK_SHA" ]

# A complete release may become durable before the one selector switch.  An
# interruption at that boundary must leave the previous selector active.
if run_updater before-selector-activation >"$TMP/pre-activation.out" \
	2>"$TMP/pre-activation.err"; then
	printf '%s\n' 'pre-activation injection unexpectedly succeeded' >&2
	exit 1
fi
if ! grep -q 'host-only injected failure: before-selector-activation' \
	"$TMP/pre-activation.err"; then
	cat "$TMP/pre-activation.err" >&2
	printf '%s\n' 'pre-activation failpoint was not reached' >&2
	exit 1
fi
[ -f "$BIRD/bird-releases/v6.23/.complete" ]
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
[ "$(cat "$RELEASE_ATTEMPTS")" = 0 ]
[ "$(cat "$PRIOR_ATTEMPTS")" = 1 ]

if run_updater after-selector-rename >"$TMP/post-activation.out" \
	2>"$TMP/post-activation.err"; then
	printf '%s\n' 'post-selector injection unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'selector activation failed; previous selector restored' \
	"$TMP/post-activation.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_BEFORE" ]
[ "$(sha256 "$BIRD/post-flash.sh")" = "$LEGACY_HOOK_SHA" ]
[ "$(cat "$PRIOR_ATTEMPTS")" = 1 ]

# The abrupt boundary differs from the rollback simulation above: terminate
# immediately after the selector rename, before post-rename sync/verification.
# The exact new selector may remain active only because its complete release
# was already durable; the next invocation must recover the stale host owner.
CARD_LOCK_ROOT=/tmp/bird-card-locks
CARD_LOCK=$CARD_LOCK_ROOT/testdisk.lock
if run_updater kill-after-selector-rename >"$TMP/selector-kill.out" \
	2>"$TMP/selector-kill.err"; then
	printf '%s\n' 'post-selector SIGKILL unexpectedly succeeded' >&2
	exit 1
fi
cmp "$CARD/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.conf"
[ -f "$BIRD/bird-releases/v6.23/.complete" ]
cmp "$MANIFEST" "$BIRD/bird-releases/v6.23/deploy-manifest.tsv"
[ -L "$CARD_LOCK" ]

if ! run_updater none >"$TMP/install.out" 2>"$TMP/install.err"; then
	cat "$TMP/install.err" >&2
	exit 1
fi
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]

# The namespace is deliberately fixed across effective UIDs. Simulate a
# privileged/unprivileged mismatch through id(1): the second identity must
# reject the first owner's verified root rather than create a parallel lock.
FAKE_UID_BIN=$TMP/fake-cross-uid-bin
mkdir "$FAKE_UID_BIN"
cat >"$FAKE_UID_BIN/id" <<'EOF'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = -u ]; then
	printf '%s\n' 4294967294
	exit 0
fi
exec /usr/bin/id "$@"
EOF
chmod 0755 "$FAKE_UID_BIN/id"
HOST_REAL_PATH=$PATH
if PATH=$FAKE_UID_BIN:$PATH run_migration >"$TMP/cross-uid.out" \
	2>"$TMP/cross-uid.err"; then
	printf '%s\n' 'migration acquired a parallel cross-UID card lock' >&2
	exit 1
fi
PATH=$HOST_REAL_PATH
grep -q 'Bird card lock directory owner is unsafe' "$TMP/cross-uid.err"
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]

# A predictable mutex below /tmp must never be opened through a hostile
# symlink. Use a distinct synthetic whole-disk identity so the safe testdisk
# mutex remains untouched, and prove the writable target retains its bytes.
HOSTILE_WHOLE=hostiletestdisk$$
HOSTILE_INFO=$TMP/device-info-hostile-lock.tsv
awk -F '\t' -v bird="$BIRD" -v data="$DATA" -v whole="$HOSTILE_WHOLE" \
	'BEGIN {OFS="\t"}
	$1 == bird && $2 == "Part of Whole" {$3=whole}
	$1 == data && $2 == "Part of Whole" {$3=whole}
	$1 == bird && $2 == "Device Identifier" {$3=whole "s1"}
	$1 == data && $2 == "Device Identifier" {$3=whole "s6"}
	$1 == "/dev/testdisk" {$1="/dev/" whole}
	{print}
' "$INFO" >"$HOSTILE_INFO"
HOSTILE_TARGET=$TMP/hostile-lock-target
HOSTILE_SERIAL=$CARD_LOCK_ROOT/$HOSTILE_WHOLE.serial
HOSTILE_TRANSACTION=$CARD_LOCK_ROOT/$HOSTILE_WHOLE.transaction
printf '%s\n' 'must-not-be-truncated' >"$HOSTILE_TARGET"
ln -s "$HOSTILE_TARGET" "$HOSTILE_SERIAL"
MIGRATION_INFO=$HOSTILE_INFO
if run_migration >"$TMP/hostile-lock.out" 2>"$TMP/hostile-lock.err"; then
	printf '%s\n' 'migration opened a hostile lock mutex symlink' >&2
	exit 1
fi
grep -q 'Bird card lock mutex is unsafe' "$TMP/hostile-lock.err"
[ "$(cat "$HOSTILE_TARGET")" = 'must-not-be-truncated' ]
rm -f "$HOSTILE_SERIAL"
rm -f "$HOSTILE_TRANSACTION"
MIGRATION_INFO=

RELEASE=$BIRD/bird-releases/v6.23
[ -f "$RELEASE/.complete" ]
cmp "$MANIFEST" "$RELEASE/deploy-manifest.tsv"
[ -d "$RELEASE/bird/empty-runtime" ]
cmp "$CARD/extlinux/extlinux.conf" "$BIRD/extlinux/extlinux.conf"
[ "$(sha256 "$BIRD/post-flash.sh")" = "$LEGACY_HOOK_SHA" ]
[ -s "$DATA/ROMS/Ports/PortMaster/.bird-release-complete" ]
PREVIOUS_SHA=$(sha256 "$BIRD/extlinux/extlinux.previous.conf")

run_updater none >"$TMP/idempotent.out"
[ "$(sha256 "$BIRD/extlinux/extlinux.previous.conf")" = "$PREVIOUS_SHA" ]

# Prove lock ordering, not only exclusion: a contender waiting on the lifetime
# transaction lock must not hold the short serial mutex needed by the owner to
# release. Once the live owner is ungated, both operations finish successfully
# instead of deadlocking until the contender timeout.
ORDER_GATE=$TMP/lock-order-gate
mkdir "$ORDER_GATE"
LOCK_GATE=$ORDER_GATE
run_updater hold-after-lock >"$TMP/order-owner.out" \
	2>"$TMP/order-owner.err" &
ORDER_OWNER_JOB=$!
GATE_WAIT=0
while [ ! -f "$ORDER_GATE/owner-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/order-owner.err" >&2
		printf '%s\n' 'lock-order owner did not become ready' >&2
		exit 1
	}
	sleep 0.02
done
run_migration >"$TMP/order-contender.out" \
	2>"$TMP/order-contender.err" &
ORDER_CONTENDER_JOB=$!
sleep 0.1
kill -0 "$ORDER_CONTENDER_JOB"
: >"$ORDER_GATE/release-owner"
set +e
wait "$ORDER_OWNER_JOB"
ORDER_OWNER_STATUS=$?
wait "$ORDER_CONTENDER_JOB"
ORDER_CONTENDER_STATUS=$?
set -e
[ "$ORDER_OWNER_STATUS" -eq 0 ] || {
	cat "$TMP/order-owner.err" >&2
	exit 1
}
[ "$ORDER_CONTENDER_STATUS" -eq 0 ] || {
	cat "$TMP/order-contender.err" >&2
	exit 1
}
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]
LOCK_GATE=

# Updater and migration share one atomic owner symlink. A paused live updater
# blocks migration; SIGKILL leaves a complete stale identity which migration
# recovers under the lockf mutex. Killing that recovery owner is recoverable.
mkdir -p "$DATA/ports/SharedLockTest"
BAD_MIGRATION_INFO=$TMP/device-info-not-p6.tsv
awk -F '\t' -v data="$DATA" 'BEGIN {OFS="\t"}
	$1 == data && $2 == "Device Identifier" {$3="testdisks5"}
	{print}
' "$INFO" >"$BAD_MIGRATION_INFO"
MIGRATION_INFO=$BAD_MIGRATION_INFO
if run_migration >"$TMP/migrate-not-p6.out" 2>"$TMP/migrate-not-p6.err"; then
	printf '%s\n' 'migration accepted a data volume that was not p6' >&2
	exit 1
fi
if ! grep -q 'data is not p6' "$TMP/migrate-not-p6.err"; then
	cat "$TMP/migrate-not-p6.err" >&2
	printf '%s\n' 'migration p6 rejection was not reported' >&2
	exit 1
fi
[ -d "$DATA/ports/SharedLockTest" ]
MIGRATION_INFO=
# The lock owner and contender both run under a locale whose ps(1) lstart
# rendering is non-English. The helper's internal LC_ALL=C normalization must
# still preserve the live owner's exact identity and reject the contender.
TEST_LOCALE=fa_IR.UTF-8
[ "$(LC_ALL=$TEST_LOCALE ps -p $$ -o lstart=)" != \
	"$(LC_ALL=C ps -p $$ -o lstart=)" ] || {
	printf '%s\n' 'lock locale fixture did not produce localized ps output' >&2
	exit 1
}
LOCK_GATE=$TMP/update-lock-gate
mkdir "$LOCK_GATE"
run_updater hold-after-lock >"$TMP/paused-owner.out" \
	2>"$TMP/paused-owner.err" &
PAUSED_JOB=$!
GATE_WAIT=0
while [ ! -f "$LOCK_GATE/owner-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/paused-owner.err" >&2
		printf '%s\n' 'updater did not publish its atomic host lock' >&2
		exit 1
	}
	sleep 0.02
done
PAUSED_OWNER=$(cat "$LOCK_GATE/owner-ready")
PAUSED_TOKEN=$(readlink "$CARD_LOCK")
[ "${PAUSED_TOKEN%%:*}" = "$PAUSED_OWNER" ]
case "$PAUSED_TOKEN" in *[!0-9A-Za-z:]*) exit 1 ;; esac
kill -STOP "$PAUSED_OWNER"
# A second process deliberately uses a different TMPDIR. It must still reach
# the same fixed /tmp lock and reject the paused live owner.
TEST_TMPDIR=$TMP/different-host-tmp
mkdir "$TEST_TMPDIR"
if run_migration >"$TMP/migrate-blocked.out" 2>"$TMP/migrate-blocked.err"; then
	printf '%s\n' 'migration bypassed a paused updater owner' >&2
	exit 1
fi
grep -q 'another Bird card transaction is active' "$TMP/migrate-blocked.err"
[ -d "$DATA/ports/SharedLockTest" ]
TEST_TMPDIR=
kill -KILL "$PAUSED_OWNER"
set +e
wait "$PAUSED_JOB"
set -e
[ "$(readlink "$CARD_LOCK")" = "$PAUSED_TOKEN" ]
LOCK_GATE=

MIGRATION_GATE=$TMP/migration-lock-gate
mkdir "$MIGRATION_GATE"
run_migration >"$TMP/recovery-owner.out" 2>"$TMP/recovery-owner.err" &
RECOVERY_JOB=$!
GATE_WAIT=0
while [ ! -f "$MIGRATION_GATE/owner-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/recovery-owner.err" >&2
		printf '%s\n' 'migration did not recover the SIGKILLed updater lock' >&2
		exit 1
	}
	sleep 0.02
done
RECOVERY_OWNER=$(cat "$MIGRATION_GATE/owner-ready")
RECOVERY_TOKEN=$(readlink "$CARD_LOCK")
[ "${RECOVERY_TOKEN%%:*}" = "$RECOVERY_OWNER" ]
kill -KILL "$RECOVERY_OWNER"
set +e
wait "$RECOVERY_JOB"
set -e
[ "$(readlink "$CARD_LOCK")" = "$RECOVERY_TOKEN" ]
MIGRATION_GATE=

run_migration >"$TMP/migration-recovered.out"
[ -d "$DATA/ROMS/Ports/SharedLockTest" ]
[ ! -e "$DATA/ports" ]
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]
TEST_LOCALE=C

# A child doing card I/O inherits the full-lifetime advisory descriptor. If
# the updater shell is SIGKILLed, its owner symlink becomes diagnostically
# stale but must not be recovered while that orphan can still mutate bytes.
mkdir -p "$DATA/ports/OrphanChildLockTest"
ORPHAN_GATE=$TMP/orphan-child-lock-gate
mkdir "$ORPHAN_GATE"
LOCK_GATE=$ORPHAN_GATE
run_updater orphan-child-after-lock >"$TMP/orphan-owner.out" \
	2>"$TMP/orphan-owner.err" &
ORPHAN_JOB=$!
GATE_WAIT=0
while [ ! -f "$ORPHAN_GATE/owner-ready" ] || \
	[ ! -f "$ORPHAN_GATE/mutator-ready" ]; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		cat "$TMP/orphan-owner.err" >&2
		printf '%s\n' 'orphan-child lock fixture did not become ready' >&2
		exit 1
	}
	sleep 0.02
done
ORPHAN_OWNER=$(cat "$ORPHAN_GATE/owner-ready")
ORPHAN_MUTATOR=$(cat "$ORPHAN_GATE/mutator-ready")
ORPHAN_TOKEN=$(readlink "$CARD_LOCK")
[ "${ORPHAN_TOKEN%%:*}" = "$ORPHAN_OWNER" ]
kill -0 "$ORPHAN_MUTATOR"
ORPHAN_TARGET=$DATA/orphan-mutator-probe
MUTATOR_BEFORE=$(bytes "$ORPHAN_TARGET")
sleep 0.1
MUTATOR_AFTER=$(bytes "$ORPHAN_TARGET")
[ "$MUTATOR_AFTER" -gt "$MUTATOR_BEFORE" ]
kill -KILL "$ORPHAN_OWNER"
set +e
wait "$ORPHAN_JOB"
set -e
[ "$(readlink "$CARD_LOCK")" = "$ORPHAN_TOKEN" ]
kill -0 "$ORPHAN_MUTATOR"
MUTATOR_BEFORE=$(bytes "$ORPHAN_TARGET")
if run_migration >"$TMP/orphan-contender.out" \
	2>"$TMP/orphan-contender.err"; then
	printf '%s\n' 'migration bypassed an inherited orphan mutator lock' >&2
	exit 1
fi
grep -q 'another Bird card transaction is active (owner or inherited mutator child)' \
	"$TMP/orphan-contender.err"
MUTATOR_AFTER=$(bytes "$ORPHAN_TARGET")
[ "$MUTATOR_AFTER" -gt "$MUTATOR_BEFORE" ]
[ "$(readlink "$CARD_LOCK")" = "$ORPHAN_TOKEN" ]
: >"$ORPHAN_GATE/release-mutator"
GATE_WAIT=0
while kill -0 "$ORPHAN_MUTATOR" 2>/dev/null; do
	GATE_WAIT=$((GATE_WAIT + 1))
	[ "$GATE_WAIT" -le 400 ] || {
		printf '%s\n' 'orphan mutator did not exit after release' >&2
		exit 1
	}
	sleep 0.02
done
LOCK_GATE=
run_migration >"$TMP/orphan-recovered.out"
[ -d "$DATA/ROMS/Ports/OrphanChildLockTest" ]
[ ! -e "$DATA/ports" ]
[ ! -e "$CARD_LOCK" ] && [ ! -L "$CARD_LOCK" ]

GOOD_MANIFEST=$MANIFEST
ACTIVE_SHA=$(sha256 "$BIRD/extlinux/extlinux.conf")

MALFORMED_MANIFEST=$TMP/deploy-manifest-malformed.tsv
cp "$GOOD_MANIFEST" "$MALFORMED_MANIFEST"
printf 'unknown\trecord\n' >>"$MALFORMED_MANIFEST"
if MANIFEST=$MALFORMED_MANIFEST run_updater none >"$TMP/malformed.out" 2>"$TMP/malformed.err"; then
	printf '%s\n' 'malformed manifest unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'canonical deploy manifest is malformed' "$TMP/malformed.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

DUPLICATE_MANIFEST=$TMP/deploy-manifest-duplicate.tsv
cp "$GOOD_MANIFEST" "$DUPLICATE_MANIFEST"
awk -F '\t' '$1 == "file" && $2 == "KERNEL" {print; exit}' \
	"$GOOD_MANIFEST" >>"$DUPLICATE_MANIFEST"
if MANIFEST=$DUPLICATE_MANIFEST run_updater none >"$TMP/duplicate.out" 2>"$TMP/duplicate.err"; then
	printf '%s\n' 'duplicate manifest path unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'canonical deploy manifest has duplicate paths' "$TMP/duplicate.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

TRAVERSAL_MANIFEST=$TMP/deploy-manifest-traversal.tsv
cp "$GOOD_MANIFEST" "$TRAVERSAL_MANIFEST"
printf 'file\t../escape\t644\t1\t%s\n' \
	0000000000000000000000000000000000000000000000000000000000000000 \
	>>"$TRAVERSAL_MANIFEST"
if MANIFEST=$TRAVERSAL_MANIFEST run_updater none >"$TMP/traversal.out" 2>"$TMP/traversal.err"; then
	printf '%s\n' 'manifest traversal unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'canonical deploy manifest is malformed' "$TMP/traversal.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

MANIFEST=$GOOD_MANIFEST
ln -s KERNEL "$CARD/candidate-link"
if run_updater none >"$TMP/candidate-link.out" 2>"$TMP/candidate-link.err"; then
	printf '%s\n' 'candidate symlink unexpectedly succeeded' >&2
	exit 1
fi
if ! grep -q 'candidate contains a symlink or special node' \
	"$TMP/candidate-link.err"; then
	cat "$TMP/candidate-link.err" >&2
	printf '%s\n' 'candidate symlink rejection was not reported' >&2
	exit 1
fi
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]
rm -f "$CARD/candidate-link"

BAD_MANIFEST=$TMP/deploy-manifest-corrupt.tsv
awk -F '\t' 'BEGIN {OFS="\t"}
	$1 == "file" && $2 == "KERNEL" {
		$5="0000000000000000000000000000000000000000000000000000000000000000"
	}
	{print}
' "$MANIFEST" >"$BAD_MANIFEST"
if MANIFEST=$BAD_MANIFEST run_updater none >"$TMP/bad-manifest.out" 2>"$TMP/bad-manifest.err"; then
	printf '%s\n' 'corrupt manifest unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'candidate digest changed: KERNEL' "$TMP/bad-manifest.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

MANIFEST=$GOOD_MANIFEST
printf 'unlisted\n' >"$CARD/unlisted-payload"
if run_updater none >"$TMP/unlisted.out" 2>"$TMP/unlisted.err"; then
	printf '%s\n' 'unlisted candidate payload unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'candidate regular-file set differs from canonical manifest' \
	"$TMP/unlisted.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]
rm -f "$CARD/unlisted-payload"

printf 'corrupt\n' >>"$RELEASE/bird/bird-suspend.sh"
if run_updater none >"$TMP/bad-release.out" 2>"$TMP/bad-release.err"; then
	printf '%s\n' 'corrupt installed release unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'installed release size changed: bird/bird-suspend.sh' \
	"$TMP/bad-release.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]
cp "$CARD/bird/bird-suspend.sh" "$RELEASE/bird/bird-suspend.sh"

printf 'corrupt\n' >>"$CARD/bird/bird-suspend.sh"
if run_updater none >"$TMP/bad-candidate.out" 2>"$TMP/bad-candidate.err"; then
	printf '%s\n' 'corrupt candidate unexpectedly succeeded' >&2
	exit 1
fi
grep -q 'candidate size changed: bird/bird-suspend.sh' "$TMP/bad-candidate.err"
[ "$(sha256 "$BIRD/extlinux/extlinux.conf")" = "$ACTIVE_SHA" ]

# A caller-selected release ID must drive the manifest contract, immutable
# directory, selector and boot-attempt namespace together. Rebuild only the
# small fixture selector and its canonical file record; every other byte stays
# identical to the already-verified candidate.
cp "$RELEASE/bird/bird-suspend.sh" "$CARD/bird/bird-suspend.sh"
DYNAMIC_ID=v6.23-host-test
DYNAMIC_CARD=$TMP/dynamic-build/card
mkdir -p "${DYNAMIC_CARD%/*}"
cp -R "$CARD" "$DYNAMIC_CARD"
sed "s#v6\.23#$DYNAMIC_ID#g" "$CARD/extlinux/extlinux.conf" \
	>"$DYNAMIC_CARD/extlinux/extlinux.conf"
DYNAMIC_SELECTOR_BYTES=$(bytes "$DYNAMIC_CARD/extlinux/extlinux.conf")
DYNAMIC_SELECTOR_SHA=$(sha256 "$DYNAMIC_CARD/extlinux/extlinux.conf")
DYNAMIC_MANIFEST=$TMP/dynamic-build/deploy-manifest.tsv
awk -F '\t' -v release="$DYNAMIC_ID" -v selector_bytes="$DYNAMIC_SELECTOR_BYTES" \
	-v selector_sha="$DYNAMIC_SELECTOR_SHA" 'BEGIN {OFS="\t"}
	$1 == "release" {$2=release}
	$1 == "file" && $2 == "extlinux/extlinux.conf" {
		$4=selector_bytes
		$5=selector_sha
	}
	{print}
' "$GOOD_MANIFEST" >"$DYNAMIC_MANIFEST"
CARD=$DYNAMIC_CARD
MANIFEST=$DYNAMIC_MANIFEST
UPDATER_RELEASE_ID=$DYNAMIC_ID
run_updater none >"$TMP/dynamic-release.out"
DYNAMIC_RELEASE=$BIRD/bird-releases/$DYNAMIC_ID
[ -f "$DYNAMIC_RELEASE/.complete" ]
cmp "$DYNAMIC_MANIFEST" "$DYNAMIC_RELEASE/deploy-manifest.tsv"
grep -Fq "bird_release=$DYNAMIC_ID" "$BIRD/extlinux/extlinux.conf"
[ "$(cat "$DATA/MUOS/Bird/boot-state/releases/$DYNAMIC_ID/attempts")" = 0 ]
[ -f "$BIRD/bird-releases/v6.23/.complete" ]

printf '%s\n' 'stock-root updater transaction tests passed'
