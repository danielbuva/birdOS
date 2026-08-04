#!/bin/sh
# Host-only fault injection for atomic boot attempts and fallback activation.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
HOOK=$ROOT/kernel/rocknix/stock-root/post-flash.sh
LOADER=$ROOT/kernel/rocknix/stock-root/bird-release-loader.sh
EARLY_BUILDER=$ROOT/kernel/rocknix/build-stock-root-early-initramfs.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-post-flash.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
BUSYBOX_MOCK=$TMP/busybox

# Emulate only the pinned ROCKNIX applet forms used by the release loader.
# In particular, reject GNU stat -c so host tests cannot mask target drift.
cat >"$BUSYBOX_MOCK" <<'EOF'
#!/bin/sh
APPLET=$1
shift
case "$APPLET" in
	stat)
		[ "$1" = -Lt ] || exit 64
		shift
		SIZE=$(stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1") || exit 1
		printf '%s %s\n' "$1" "$SIZE"
		;;
	sha256sum) shasum -a 256 "$@" ;;
	awk) exec awk "$@" ;;
	usleep)
		printf 'usleep %s\n' "$1" >>"$BIRD_TEST_STATE/usleep.log"
		;;
	*) exit 64 ;;
esac
EOF
chmod 0755 "$BUSYBOX_MOCK"

# The production init owns the non-returning boundary around the sourced
# loader. Any hook, cleanup, fallback publication or reboot error must enter
# this fatal wait instead of falling through to normal init processing.
grep -Fq 'print "    if ! . /bird-release-loader.sh; then"' "$EARLY_BUILDER"
grep -Fq 'print "      while :; do sleep 3600; done"' "$EARLY_BUILDER"
grep -Fq 'BIRD_FIRST_FRAME_WAIT_TICKS=1000' "$HOOK"
grep -Fq '"$BIRD_LOADER_BUSYBOX" usleep 20000' "$HOOK"

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

bytes() {
	stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"
}

mode() {
	stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

reset_case() {
	CASE=$1
	rm -rf "$TMP/$CASE"
	FLASH=$TMP/$CASE/flash
	DATA=$TMP/$CASE/data
	STATE=$TMP/$CASE/state
	mkdir -p "$FLASH/extlinux" "$FLASH/bird" \
		"$DATA/MUOS/runtime" \
		"$DATA/Bird/boot-state/releases/v6.23" "$STATE"
	ATTEMPTS_FILE=$DATA/Bird/boot-state/releases/v6.23/attempts
	FIRST_FRAME=$TMP/$CASE/bird-first-frame-ready
	PRIOR_ATTEMPTS=$DATA/Bird/boot-state/releases/v6.22/attempts
	mkdir -p "${PRIOR_ATTEMPTS%/*}"
	touch "$FLASH/mount-storage.sh" "$FLASH/SYSTEM" \
		"$DATA/MUOS/runtime/ROCKNIX-SYSTEM" \
		"$DATA/MUOS/runtime/ROCKNIX-STORAGE"
	printf 'candidate-selector\n' >"$FLASH/extlinux/extlinux.conf"
	printf 'fallback-selector\n' >"$FLASH/extlinux/extlinux.fallback.conf"
	printf 'fallback-kernel\n' >"$FLASH/KERNEL.fallback"
	printf 'fallback-dtb\n' >"$FLASH/dtb.img"
	sha256 "$FLASH/extlinux/extlinux.fallback.conf" >"$STATE/selector.sha"
	sha256 "$FLASH/KERNEL.fallback" >"$STATE/kernel.sha"
	sha256 "$FLASH/dtb.img" >"$STATE/dtb.sha"
	printf 'quiet\n' >"$TMP/$CASE/cmdline"
	printf '2\n' >"$ATTEMPTS_FILE"
	printf '1\n' >"$PRIOR_ATTEMPTS"
	printf '0\n' >"$STATE/sync-count"
	printf '0\n' >"$STATE/mv-count"
	: >"$STATE/mount.log"
	: >"$STATE/reboot.log"
	: >"$STATE/error.log"
	: >"$STATE/umount.log"
	: >"$STATE/event.log"
	: >"$STATE/usleep.log"
	enable_release
}

enable_release() {
	RELEASE=$FLASH/bird-releases/v6.23
	mkdir -p "$RELEASE/bird"
	cp "$HOOK" "$RELEASE/post-flash.sh"
	printf '#!/bin/sh\n' >"$RELEASE/mount-storage.sh"
	printf '#!/bin/sh\n' >"$RELEASE/bird/supervisor.sh"
	printf 'schema\tstring\tbird-device-v1\n' \
		>"$RELEASE/bird/bird-device-contract.tsv"
	chmod 0755 "$RELEASE/post-flash.sh" "$RELEASE/mount-storage.sh" \
		"$RELEASE/bird/supervisor.sh"
	MANIFEST=$RELEASE/deploy-manifest.tsv
	{
		printf 'schema\tbird-deploy-v1\n'
		printf 'release\tv6.23\n'
		printf 'target-mode-policy\tfat-capability\n'
		printf 'source-commit\ttest\tclean\n'
		printf 'artifact\tdevice-contract\tbird/bird-device-contract.tsv\t%s\n' \
			"$(sha256 "$RELEASE/bird/bird-device-contract.tsv")"
		printf 'artifact\tcatalog\tlauncher/catalog.generated.h\t%s\n' \
			2222222222222222222222222222222222222222222222222222222222222222
		for INPUT in KERNEL dtb.img ROCKNIX-SYSTEM ROCKNIX-STORAGE \
			usr/bin/autostart initramfs/init rocknix-singleadc-joypad.ko \
			initramfs/busybox PortMaster.zip KERNEL.fallback \
			PortMaster/pugwash PortMaster/PortMaster.sh \
			PortMaster/mod_ROCKNIX.txt PortMaster/funcs.txt \
			PortMaster/harbourmaster; do
			printf 'input\t%s\t644\t1\t%s\ttest\n' "$INPUT" \
				0000000000000000000000000000000000000000000000000000000000000000
		done
		for RELATIVE in post-flash.sh mount-storage.sh bird/supervisor.sh \
			bird/bird-device-contract.tsv; do
			FILE=$RELEASE/$RELATIVE
			printf 'file\t%s\t%s\t%s\t%s\n' "$RELATIVE" "$(mode "$FILE")" \
				"$(bytes "$FILE")" "$(sha256 "$FILE")"
		done
	} >"$MANIFEST"
	sha256 "$MANIFEST" >"$RELEASE/.complete"
	printf 'quiet bird_release=v6.23\n' >"$TMP/$CASE/cmdline"
}

run_hook() {
	FAILURE=$1
	BIRD_HOST_TEST_MODE=1 BIRD_FLASH_ROOT=$FLASH \
	BIRD_CMDLINE_FILE=$TMP/$CASE/cmdline \
	BIRD_DATA_MOUNT=$DATA \
	BIRD_DATA_DEVICE=/dev/bird-test \
	BIRD_FIRST_FRAME=$FIRST_FRAME \
	BIRD_FIRST_FRAME_WAIT_TICKS=2 \
	BIRD_LOADER_FLASH=$FLASH \
	BIRD_LOADER_CMDLINE=$TMP/$CASE/cmdline \
	BIRD_LOADER_REBOOT=reboot \
	BIRD_LOADER_BUSYBOX=$BUSYBOX_MOCK \
	BIRD_LOADER_RELEASE=v6.23 \
	BIRD_LOADER_SELECTOR_SHA=$(cat "$STATE/selector.sha") \
	BIRD_LOADER_KERNEL_SHA=$(cat "$STATE/kernel.sha") \
	BIRD_LOADER_DTB_SHA=$(cat "$STATE/dtb.sha") \
	BIRD_TEST_FAILURE=$FAILURE \
	BIRD_TEST_STATE=$STATE \
	BIRD_TEST_LOADER=$LOADER \
	sh -c '
		printf() {
			if [ "$BIRD_TEST_FAILURE" = health-reset-write ] &&
			    [ "$#" -eq 2 ] && [ "$1" = "%s\\n" ] && [ "$2" = 0 ]; then
				return 1
			fi
			command printf "$@"
		}
		stat() {
			[ "$1" = -c ] && return 64
			command stat "$@"
		}
		cat() {
			case "$BIRD_TEST_FAILURE:$1" in
				attempts-verify:*/.attempts.*) printf "%s\n" malformed; return 0 ;;
				health-reset-verify:*/attempts)
					VALUE=$(command cat "$1" 2>/dev/null) || return 1
					if [ "$VALUE" = 0 ]; then
						printf "%s\n" malformed
						return 0
					fi
					;;
			esac
			command cat "$@"
		}
		mount() {
			printf "%s\n" "$*" >>"$BIRD_TEST_STATE/mount.log"
			[ "$BIRD_TEST_FAILURE" = data-mount ] && \
				[ "$1" = -t ] && return 1
			case "$BIRD_TEST_FAILURE:$*" in
				release-storage-bind:*bird-releases/*/mount-storage.sh*) return 1 ;;
			system-bind:*ROCKNIX-SYSTEM*) return 1 ;;
			esac
			return 0
		}
		umount() {
			printf "%s\n" "$*" >>"$BIRD_TEST_STATE/umount.log"
			printf "umount %s\n" "$*" >>"$BIRD_TEST_STATE/event.log"
			[ "$BIRD_TEST_FAILURE" = data-unmount ] && \
				[ "$1" = "$BIRD_DATA_MOUNT" ] && return 1
			return 0
		}
		sync() {
			printf "sync %s\n" "$*" >>"$BIRD_TEST_STATE/event.log"
			COUNT=$(cat "$BIRD_TEST_STATE/sync-count")
			COUNT=$((COUNT + 1))
			printf "%s\n" "$COUNT" >"$BIRD_TEST_STATE/sync-count"
			# write_attempts owns sync 1-2 and fallback cleanup owns 3-4;
			# fail sync 5 inside selector publication, not a brittle earlier phase.
			[ "$BIRD_TEST_FAILURE" = fallback-selector-sync ] && \
				[ "$COUNT" -eq 5 ] && return 1
			[ "$BIRD_TEST_FAILURE" = attempts-sync ] && [ "$COUNT" -eq 1 ] && return 1
			[ "$BIRD_TEST_FAILURE" = health-reset-sync ] &&
				[ "$COUNT" -eq 3 ] && return 1
			return 0
		}
		cp() {
			[ "$BIRD_TEST_FAILURE" = fallback-copy ] && return 1
			command cp "$@"
		}
		mv() {
			COUNT=$(cat "$BIRD_TEST_STATE/mv-count")
			COUNT=$((COUNT + 1))
			printf "%s\n" "$COUNT" >"$BIRD_TEST_STATE/mv-count"
			[ "$BIRD_TEST_FAILURE" = fallback-rename ] && [ "$COUNT" -eq 2 ] && return 1
			[ "$BIRD_TEST_FAILURE" = attempts-rename ] && [ "$COUNT" -eq 1 ] && return 1
			[ "$BIRD_TEST_FAILURE" = health-reset-rename ] &&
				[ "$COUNT" -eq 2 ] && return 1
			command mv "$@"
		}
		reboot() {
			printf "%s\n" "$*" >>"$BIRD_TEST_STATE/reboot.log"
			printf "reboot %s\n" "$*" >>"$BIRD_TEST_STATE/event.log"
			return 0
		}
		error() {
			printf "%s %s\n" "$1" "$2" >>"$BIRD_TEST_STATE/error.log"
		}
		. "$BIRD_TEST_LOADER"
	'
}

assert_fallback_activated() {
	FAILURE=$1
	CLEANUP_EXPECTED=${2:-yes}
	if run_hook "$FAILURE"; then
		printf 'case %s unexpectedly succeeded\n' "$FAILURE" >&2
		exit 1
	fi
	cmp "$FLASH/extlinux/extlinux.conf" "$FLASH/extlinux/extlinux.fallback.conf"
	grep -qx -- '-f' "$STATE/reboot.log"
	[ -s "$FLASH/bird-loader-failure.txt" ]
	grep -q '^release=v6.23$' "$FLASH/bird-loader-failure.txt"
	grep -q '^reason=' "$FLASH/bird-loader-failure.txt"
	grep -Eq '^selector_count=[1-9][0-9]*$' "$FLASH/bird-loader-failure.txt"
	grep -q '^cmdline=.*bird_release=v6.23$' "$FLASH/bird-loader-failure.txt"
	if [ "$CLEANUP_EXPECTED" = yes ]; then
		SYNC_LINE=$(grep -n '^sync ' "$STATE/event.log" | head -n 1 | cut -d: -f1)
		DATA_UMOUNT_LINE=$(grep -nF "umount $DATA" "$STATE/event.log" | \
			tail -n 1 | cut -d: -f1)
		REBOOT_LINE=$(grep -n '^reboot -f$' "$STATE/event.log" | cut -d: -f1)
		[ -n "$SYNC_LINE" ] && [ -n "$DATA_UMOUNT_LINE" ] && [ -n "$REBOOT_LINE" ]
		[ "$SYNC_LINE" -lt "$DATA_UMOUNT_LINE" ]
		[ "$DATA_UMOUNT_LINE" -lt "$REBOOT_LINE" ]
	fi
}

assert_failed_without_activation() {
	FAILURE=$1
	if run_hook "$FAILURE"; then
		printf 'case %s unexpectedly succeeded\n' "$FAILURE" >&2
		exit 1
	fi
	grep -qx 'candidate-selector' "$FLASH/extlinux/extlinux.conf"
	[ ! -s "$STATE/reboot.log" ]
	if find "$FLASH/extlinux" "$DATA/Bird/boot-state" \
		-name '.extlinux.conf.*' -o -name '.attempts.*' | grep -q .; then
		printf 'case %s left a transaction temporary\n' "$FAILURE" >&2
		exit 1
	fi
}

reset_case happy
if run_hook none; then
	printf 'third-attempt hook unexpectedly returned success\n' >&2
	exit 1
fi
cmp "$FLASH/extlinux/extlinux.conf" "$FLASH/extlinux/extlinux.fallback.conf"
[ "$(cat "$ATTEMPTS_FILE")" = 3 ]
[ "$(cat "$PRIOR_ATTEMPTS")" = 1 ]
grep -qx -- '-f' "$STATE/reboot.log"
[ "$(wc -l <"$STATE/usleep.log" | tr -d " ")" = 2 ]
[ "$(sort -u "$STATE/usleep.log")" = 'usleep 20000' ]

# A current honest frame wins even when two older boots did not reach their
# commit point. The third boot resets its release state instead of selecting
# recovery from stale history.
reset_case third-attempt-usable
: >"$FIRST_FRAME"
run_hook none
grep -qx 'candidate-selector' "$FLASH/extlinux/extlinux.conf"
[ "$(cat "$ATTEMPTS_FILE")" = 0 ]
[ ! -s "$STATE/reboot.log" ]

# Once the launcher publishes the honest input-open barrier, failure to persist
# the health reset must never turn that usable third start into recovery. The
# supervisor can retry the same release-scoped transaction after final-root.
for FAILURE in health-reset-write health-reset-sync health-reset-rename \
	health-reset-verify; do
	reset_case "$FAILURE"
	: >"$FIRST_FRAME"
	run_hook "$FAILURE"
	grep -qx 'candidate-selector' "$FLASH/extlinux/extlinux.conf"
	[ ! -s "$STATE/reboot.log" ]
	[ ! -e "$FLASH/bird-loader-failure.txt" ]
	if find "$DATA/Bird/boot-state" -name '.attempts.*' | grep -q .; then
		printf 'case %s left a health-reset transaction temporary\n' \
			"$FAILURE" >&2
		exit 1
	fi
	case "$FAILURE" in
		health-reset-verify) [ "$(cat "$ATTEMPTS_FILE")" = 0 ] ;;
		*) [ "$(cat "$ATTEMPTS_FILE")" = 3 ] ;;
	esac
done

reset_case missing-attempts
rm -f "$ATTEMPTS_FILE"
assert_fallback_activated none

reset_case duplicate-selector
printf 'quiet bird_release=v6.23 bird_release=v6.23\n' >"$TMP/$CASE/cmdline"
assert_fallback_activated none no
[ "$(cat "$ATTEMPTS_FILE")" = 2 ]
[ "$(cat "$PRIOR_ATTEMPTS")" = 1 ]

for CORRUPT_ATTEMPTS in empty malformed out-of-range; do
	reset_case "corrupt-attempts-$CORRUPT_ATTEMPTS"
	case "$CORRUPT_ATTEMPTS" in
		empty) : >"$ATTEMPTS_FILE" ;;
		malformed) printf '%s\n' invalid >"$ATTEMPTS_FILE" ;;
		out-of-range) printf '%s\n' 999999999999999999999999999999999999 \
			>"$ATTEMPTS_FILE" ;;
	esac
	if run_hook none; then
		printf 'corrupt attempts case %s unexpectedly returned success\n' \
			"$CORRUPT_ATTEMPTS" >&2
		exit 1
	fi
	cmp "$FLASH/extlinux/extlinux.conf" "$FLASH/extlinux/extlinux.fallback.conf"
	[ "$(cat "$ATTEMPTS_FILE")" = 3 ]
	[ "$(cat "$PRIOR_ATTEMPTS")" = 1 ]
	grep -qx -- '-f' "$STATE/reboot.log"
done

reset_case bad-kernel
printf 'corrupt\n' >"$FLASH/KERNEL.fallback"
assert_failed_without_activation none

reset_case duplicate-release-selector
printf 'quiet bird_release=v6.23 bird_release=v6.23\n' >"$TMP/$CASE/cmdline"
assert_fallback_activated none no

reset_case attempts-sync
assert_fallback_activated attempts-sync
[ "$(cat "$ATTEMPTS_FILE")" = 2 ]

reset_case attempts-verify
assert_fallback_activated attempts-verify
[ "$(cat "$ATTEMPTS_FILE")" = 2 ]

reset_case attempts-rename
assert_fallback_activated attempts-rename
[ "$(cat "$ATTEMPTS_FILE")" = 2 ]

reset_case data-mount
assert_fallback_activated data-mount no

for MISSING in system storage; do
	reset_case "missing-$MISSING"
	case "$MISSING" in
		system) rm -f "$DATA/MUOS/runtime/ROCKNIX-SYSTEM" ;;
		storage) rm -f "$DATA/MUOS/runtime/ROCKNIX-STORAGE" ;;
	esac
	printf '0\n' >"$ATTEMPTS_FILE"
	assert_fallback_activated none
done

reset_case release-valid
printf '0\n' >"$ATTEMPTS_FILE"
: >"$FIRST_FRAME"
run_hook none
grep -q 'bird-releases/v6.23/bird' "$STATE/mount.log"
grep -q 'bird-releases/v6.23/mount-storage.sh' "$STATE/mount.log"
[ "$(cat "$ATTEMPTS_FILE")" = 0 ]
[ "$(cat "$PRIOR_ATTEMPTS")" = 1 ]

# Reaching the honest interactive barrier commits boot health before the later
# graphical supervisor. Without that marker the attempt stays charged for the
# supervisor's existing health race; it must not immediately select recovery.
reset_case first-frame-missing
printf '0\n' >"$ATTEMPTS_FILE"
run_hook none
[ "$(cat "$ATTEMPTS_FILE")" = 1 ]
grep -qx 'candidate-selector' "$FLASH/extlinux/extlinux.conf"
[ ! -s "$STATE/reboot.log" ]

reset_case release-corrupt
printf '0\n' >"$ATTEMPTS_FILE"
printf 'corrupt\n' >>"$RELEASE/bird/supervisor.sh"
assert_fallback_activated none

reset_case release-manifest-corrupt
printf '0\n' >"$ATTEMPTS_FILE"
printf 'corrupt\n' >>"$MANIFEST"
assert_fallback_activated none no

reset_case release-manifest-artifacts-missing
printf '0\n' >"$ATTEMPTS_FILE"
awk -F '\t' '$1 != "artifact"' "$MANIFEST" >"$MANIFEST.new"
mv "$MANIFEST.new" "$MANIFEST"
sha256 "$MANIFEST" >"$RELEASE/.complete"
assert_fallback_activated none

reset_case release-manifest-contract-binding
printf '0\n' >"$ATTEMPTS_FILE"
awk -F '\t' 'BEGIN {OFS="\t"}
	$1 == "artifact" && $2 == "device-contract" {$4 = "0000000000000000000000000000000000000000000000000000000000000000"}
	{print}' "$MANIFEST" >"$MANIFEST.new"
mv "$MANIFEST.new" "$MANIFEST"
sha256 "$MANIFEST" >"$RELEASE/.complete"
assert_fallback_activated none

reset_case release-manifest-artifact-duplicate
printf '0\n' >"$ATTEMPTS_FILE"
awk -F '\t' '$1 == "artifact" && $2 == "catalog" {print; print; next} {print}' \
	"$MANIFEST" >"$MANIFEST.new"
mv "$MANIFEST.new" "$MANIFEST"
sha256 "$MANIFEST" >"$RELEASE/.complete"
assert_fallback_activated none

reset_case release-storage-bind
printf '0\n' >"$ATTEMPTS_FILE"
assert_fallback_activated release-storage-bind
grep -q "$FLASH/bird" "$STATE/umount.log"
! grep -qF "umount $FLASH/SYSTEM" "$STATE/event.log"
! grep -qF "umount $FLASH/mount-storage.sh" "$STATE/event.log"
RUNTIME_LINE=$(grep -nF "umount $FLASH/bird" "$STATE/event.log" | cut -d: -f1)
DATA_LINE=$(grep -nF "umount $DATA" "$STATE/event.log" | cut -d: -f1)
REBOOT_LINE=$(grep -n '^reboot -f$' "$STATE/event.log" | cut -d: -f1)
[ "$RUNTIME_LINE" -lt "$DATA_LINE" ]
[ "$DATA_LINE" -lt "$REBOOT_LINE" ]

reset_case system-bind
printf '0\n' >"$ATTEMPTS_FILE"
assert_fallback_activated system-bind
! grep -qF "umount $FLASH/SYSTEM" "$STATE/event.log"
STORAGE_LINE=$(grep -nF "umount $FLASH/mount-storage.sh" \
	"$STATE/event.log" | cut -d: -f1)
RUNTIME_LINE=$(grep -nF "umount $FLASH/bird" "$STATE/event.log" | cut -d: -f1)
DATA_LINE=$(grep -nF "umount $DATA" "$STATE/event.log" | cut -d: -f1)
REBOOT_LINE=$(grep -n '^reboot -f$' "$STATE/event.log" | cut -d: -f1)
[ "$STORAGE_LINE" -lt "$RUNTIME_LINE" ]
[ "$RUNTIME_LINE" -lt "$DATA_LINE" ]
[ "$DATA_LINE" -lt "$REBOOT_LINE" ]

reset_case data-unmount
assert_failed_without_activation data-unmount
[ "$(cat "$ATTEMPTS_FILE")" = 3 ]
grep -qF "umount $DATA" "$STATE/event.log"
[ ! -s "$STATE/reboot.log" ]

for FAILURE in fallback-copy fallback-selector-sync fallback-rename; do
	reset_case "$FAILURE"
	assert_failed_without_activation "$FAILURE"
	[ "$(cat "$ATTEMPTS_FILE")" = 3 ]
	[ "$(cat "$PRIOR_ATTEMPTS")" = 1 ]
	grep -q 'remount,ro' "$STATE/mount.log"
done

printf '%s\n' 'post-flash transaction tests passed'
