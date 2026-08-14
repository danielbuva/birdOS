#!/bin/sh
# Install the verified DDR4 birdOS U-Boot at its exact mainline raw range.
# No partition, release, selector, fallback, or data byte is a write target.

set -eu
umask 077

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DEVICE=${1:-}
ACTION=${2:-}
case "$ACTION" in
	--install-inplace-handoff)
		DEFAULT_UBOOT_BUILD=$ROOT/kernel/work/bird-uboot-inplace-handoff-20260701
		;;
	--install-fast-init)
		DEFAULT_UBOOT_BUILD=$ROOT/kernel/work/bird-uboot-fast-init-20260701
		;;
	--install-no-heap-clear)
		DEFAULT_UBOOT_BUILD=$ROOT/kernel/work/bird-uboot-no-heap-clear-20260701
		;;
	--install-direct-extlinux)
		DEFAULT_UBOOT_BUILD=$ROOT/kernel/work/bird-uboot-direct-extlinux-20260701
		;;
	--install-env-nowhere)
		DEFAULT_UBOOT_BUILD=$ROOT/kernel/work/bird-uboot-env-nowhere-20260701
		;;
	--install-early-green|--restore-baseline)
		DEFAULT_UBOOT_BUILD=$ROOT/kernel/work/bird-uboot-early-led-20260701
		;;
	*) DEFAULT_UBOOT_BUILD=$ROOT/kernel/work/bird-uboot-green-20260701 ;;
esac
UBOOT_BUILD=${3:-${UBOOT_BUILD:-$DEFAULT_UBOOT_BUILD}}
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/BIRD-DATA}
GDD=${GDD:-/opt/homebrew/bin/gdd}
HOST_TEST_MODE=${BIRD_UBOOT_HOST_TEST_MODE:-0}
TEST_RAW_DISK=${BIRD_TEST_RAW_DISK:-}
TEST_FAILPOINT=${BIRD_TEST_FAILPOINT:-}
TEST_ROOT=${BIRD_TEST_ROOT:-}

PREFIX_BYTES=16777216
RAW_OFFSET=8192
BASELINE_UBOOT_BYTES=621049
BASELINE_RAW_END=629241
EARLY_UBOOT_BYTES=621073
EARLY_RAW_END=629265
RAW_SECTOR_BYTES=512
RAW_SEEK_SECTORS=16
# macOS raw block-device writes must end on a complete device sector. Bounded
# physical writes therefore include only the already-verified prefix tail up
# to the next 512-byte boundary.
BASELINE_RAW_WRITE_SECTORS=1213
BASELINE_RAW_WRITE_BYTES=621056
BASELINE_RAW_WRITE_END=629248
EARLY_RAW_WRITE_SECTORS=1214
EARLY_RAW_WRITE_BYTES=621568
EARLY_RAW_WRITE_END=629760
BASELINE_SHA=42c01f4524b45cba7c239cd940fc4e71eed7545901da201f27fed2193b7fdf45
BASELINE_PREFIX_SHA=fa35109b0b710ffe58dcb541d26349617f77d9213d25867dc328e666c3435774
# Filled only after the exact reviewed green candidate is reproduced. The
# production transaction remains closed until its complete expected prefix is
# promoted alongside the candidate identities.
GREEN_PREFIX_SHA=fe363dd09e40ccef994912c01ed1c77d3285485299a40ce7ae7fc74431b5a998
EARLY_PREFIX_SHA=5352bf933068d5a90cbeed176b4b39ca71431cc7cc22ce051defbbf89cc421a8
ENV_UBOOT_BYTES=620745
ENV_PREFIX_SHA=eceb7bcf3f8831b7a7cbb90859ea47bdf67c0cf87650a17977e225c4a43a54f2
DIRECT_PREFIX_SHA=f81187878bbe491dabaf1a4f5fda051d4edabbcb476681d1323d73557e3072ff
NO_HEAP_CLEAR_UBOOT_BYTES=620745
# These identities are promoted only after the exact repeated no-heap-clear
# build has been reviewed. Until then, production installation is deliberately
# impossible even if a structurally plausible authority directory is supplied.
NO_HEAP_CLEAR_UBOOT_SHA=38ace6d738fed727fdd2274b510c3e18105b2c71f7b1d908dece357e31d1365c
NO_HEAP_CLEAR_PREFIX_SHA=ea1afbf3186945e562aa0844d7ab6d1b027be9cfafe225a0e4c0745ffc50b305
FAST_INIT_UBOOT_BYTES=556977
# Frozen after two isolated builds and independent component, configuration,
# and complete-prefix review.
FAST_INIT_UBOOT_SHA=4afc68bd2a7fdaacc212683a1a268380c07775d18cf12025285778221e986081
FAST_INIT_PREFIX_SHA=172ca1a500603ea371a17bee1b6a7632ba17e4991a400f57cee0b2231e75bdeb
FAST_INIT_RAW_WRITE_SECTORS=1088
FAST_INIT_RAW_WRITE_BYTES=557056
FAST_INIT_RAW_WRITE_END=565248
INPLACE_HANDOFF_UBOOT_BYTES=556977
INPLACE_HANDOFF_UBOOT_SHA=7423ffeda197645b6b774c83fcebcbefef47bd7eaa6f087c71ab339750af4e91
INPLACE_HANDOFF_PREFIX_SHA=c168640be0e3b0fc3899853d71aabc0c3b3e65fdf230b19782ff40ff19f001dd
TEST_BASELINE_PREFIX_SHA=${BIRD_TEST_BASELINE_PREFIX_SHA:-}
TEST_GREEN_PREFIX_SHA=${BIRD_TEST_GREEN_PREFIX_SHA:-}
TEST_EARLY_PREFIX_SHA=${BIRD_TEST_EARLY_PREFIX_SHA:-}
TEST_ENV_PREFIX_SHA=${BIRD_TEST_ENV_PREFIX_SHA:-}
TEST_NO_HEAP_CLEAR_UBOOT_SHA=${BIRD_TEST_NO_HEAP_CLEAR_UBOOT_SHA:-}
TEST_NO_HEAP_CLEAR_PREFIX_SHA=${BIRD_TEST_NO_HEAP_CLEAR_PREFIX_SHA:-}
TEST_FAST_INIT_UBOOT_SHA=${BIRD_TEST_FAST_INIT_UBOOT_SHA:-}
TEST_FAST_INIT_PREFIX_SHA=${BIRD_TEST_FAST_INIT_PREFIX_SHA:-}
TEST_INPLACE_HANDOFF_UBOOT_SHA=${BIRD_TEST_INPLACE_HANDOFF_UBOOT_SHA:-}
TEST_INPLACE_HANDOFF_PREFIX_SHA=${BIRD_TEST_INPLACE_HANDOFF_PREFIX_SHA:-}

case "$ACTION" in
	--install-early-green|--restore-baseline)
		UBOOT_BYTES=$EARLY_UBOOT_BYTES
		RAW_END=$EARLY_RAW_END
		RAW_WRITE_SECTORS=$EARLY_RAW_WRITE_SECTORS
		RAW_WRITE_BYTES=$EARLY_RAW_WRITE_BYTES
		RAW_WRITE_END=$EARLY_RAW_WRITE_END
		;;
	--install-env-nowhere|--install-direct-extlinux)
		UBOOT_BYTES=$ENV_UBOOT_BYTES
		RAW_END=$((RAW_OFFSET + ENV_UBOOT_BYTES))
		RAW_WRITE_SECTORS=$BASELINE_RAW_WRITE_SECTORS
		RAW_WRITE_BYTES=$BASELINE_RAW_WRITE_BYTES
		RAW_WRITE_END=$BASELINE_RAW_WRITE_END
		;;
	--install-no-heap-clear)
		UBOOT_BYTES=$NO_HEAP_CLEAR_UBOOT_BYTES
		RAW_END=$((RAW_OFFSET + NO_HEAP_CLEAR_UBOOT_BYTES))
		RAW_WRITE_SECTORS=$BASELINE_RAW_WRITE_SECTORS
		RAW_WRITE_BYTES=$BASELINE_RAW_WRITE_BYTES
		RAW_WRITE_END=$BASELINE_RAW_WRITE_END
		;;
	--install-fast-init|--install-inplace-handoff)
		UBOOT_BYTES=$FAST_INIT_UBOOT_BYTES
		RAW_END=$((RAW_OFFSET + FAST_INIT_UBOOT_BYTES))
		RAW_WRITE_SECTORS=$FAST_INIT_RAW_WRITE_SECTORS
		RAW_WRITE_BYTES=$FAST_INIT_RAW_WRITE_BYTES
		RAW_WRITE_END=$FAST_INIT_RAW_WRITE_END
		;;
	*)
		UBOOT_BYTES=$BASELINE_UBOOT_BYTES
		RAW_END=$BASELINE_RAW_END
		RAW_WRITE_SECTORS=$BASELINE_RAW_WRITE_SECTORS
		RAW_WRITE_BYTES=$BASELINE_RAW_WRITE_BYTES
		RAW_WRITE_END=$BASELINE_RAW_WRITE_END
		;;
esac

VERIFY_WORK=
MOUNTED=1
WRITE_STARTED=0
WRITE_OCCURRED=0
COMMITTED=0
BIRD_CARD_LOCK_OWNED=0
CLEANUP_ACTIVE=0

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

usage() {
	printf 'usage: %s /dev/diskN --install-green|--install-early-green|--install-env-nowhere|--install-direct-extlinux|--install-no-heap-clear|--install-fast-init|--install-inplace-handoff|--restore-baseline [UBOOT_BUILD_DIRECTORY]\n' "$0" >&2
	exit 2
}

sha256() {
	shasum -a 256 "$1" | awk '{print $1}'
}

report_current_uboot_identity() {
	CURRENT_BASE_SHA=$(sha256 "$VERIFY_WORK/current-baseline-range.bin")
	CURRENT_MAX_SHA=$(sha256 "$VERIFY_WORK/current-uboot.bin")
	case "$CURRENT_PREFIX_SHA" in
		"$BASELINE_PREFIX_SHA") CURRENT_LABEL=shipping-baseline ;;
		"$GREEN_PREFIX_SHA") CURRENT_LABEL=full-green ;;
		"$EARLY_PREFIX_SHA") CURRENT_LABEL=early-green ;;
		"$ENV_PREFIX_SHA") CURRENT_LABEL=environment-nowhere ;;
		"$DIRECT_PREFIX_SHA") CURRENT_LABEL=direct-extlinux ;;
		"$NO_HEAP_CLEAR_PREFIX_SHA") CURRENT_LABEL=no-heap-clear ;;
		"$FAST_INIT_PREFIX_SHA") CURRENT_LABEL=fast-init ;;
		"$INPLACE_HANDOFF_PREFIX_SHA") CURRENT_LABEL=in-place-handoff ;;
		*) CURRENT_LABEL=unknown-prefix ;;
	esac
	printf 'Detected raw boot state: %s\n' "$CURRENT_LABEL" >&2
	printf '  prefix-sha256=%s\n' "$CURRENT_PREFIX_SHA" >&2
	printf '  first-%s-byte-sha256=%s\n' "$BASELINE_UBOOT_BYTES" "$CURRENT_BASE_SHA" >&2
	printf '  first-%s-byte-sha256=%s\n' "$UBOOT_BYTES" "$CURRENT_MAX_SHA" >&2
}

is_regular_file() {
	[ -f "$1" ] && [ ! -L "$1" ]
}

is_sha256_value() {
	[ "${#1}" -eq 64 ] || return 1
	case "$1" in *[!0-9a-f]*) return 1 ;; esac
}

remove_verify_work() {
	[ -n "$VERIFY_WORK" ] || return 0
	case "$VERIFY_WORK" in
		/var/folders/*|/private/var/folders/*|/private/tmp/*|/tmp/*)
			/bin/rm -rf "$VERIFY_WORK"
			;;
		*) return 1 ;;
	esac
}

mount_card() {
	[ "$MOUNTED" -eq 0 ] || return 0
	if [ "$HOST_TEST_MODE" -eq 0 ]; then
		diskutil mountDisk "/dev/$WHOLE" >/dev/null || return 1
	fi
	MOUNTED=1
}

unmount_card() {
	[ "$MOUNTED" -eq 1 ] || return 0
	if [ "$HOST_TEST_MODE" -eq 0 ]; then
		# FilesystemKit or its kernel-side owner can transiently dissent even
		# after every user process has released the card. Flush first, try the
		# ordinary whole-disk operation, then use diskutil's bounded force mode
		# for this already revalidated removable disk only.
		sync
		if ! diskutil unmountDisk "/dev/$WHOLE" >/dev/null; then
			printf 'Ordinary whole-disk unmount was refused; retrying the exact verified card with force.\n' >&2
			diskutil unmountDisk force "/dev/$WHOLE" >/dev/null || return 1
		fi
	fi
	MOUNTED=0
}

force_unmount_card() {
	# A failed raw write can cause Disk Arbitration to rediscover and remount the
	# card behind our in-memory MOUNTED flag. Recovery must ask macOS to unmount
	# the whole disk again instead of trusting that stale flag.
	if [ "$HOST_TEST_MODE" -eq 0 ]; then
		diskutil unmountDisk "/dev/$WHOLE" >/dev/null || return 1
	fi
	MOUNTED=0
}

prepare_user_snapshot() {
	SNAPSHOT=$1
	: >"$SNAPSHOT" || return 1
	chmod 600 "$SNAPSHOT" || return 1
	[ -f "$SNAPSHOT" ] && [ ! -L "$SNAPSHOT" ] || return 1
	[ "$(stat -f '%u' "$SNAPSHOT")" = "$(id -u)" ] || return 1
}

read_raw_prefix() {
	DESTINATION=$1
	prepare_user_snapshot "$DESTINATION" || return 1
	if [ "$HOST_TEST_MODE" -eq 0 ]; then
		# The invoking shell opens this user-owned file. sudo is used only to
		# read the raw device and can never create a root-owned host snapshot.
		sudo -n "$GDD" if="$RAW_DISK" bs=4M count="$PREFIX_BYTES" \
			iflag=count_bytes,fullblock status=none >"$DESTINATION" || return 1
	else
		"$GDD" if="$RAW_DISK" bs=4M count="$PREFIX_BYTES" \
			iflag=count_bytes,fullblock status=none >"$DESTINATION" || return 1
	fi
	[ "$(stat -f '%z' "$DESTINATION")" -eq "$PREFIX_BYTES" ] || return 1
	[ "$(stat -f '%u' "$DESTINATION")" = "$(id -u)" ] || return 1
}

extract_raw_write_slice() {
	PREFIX=$1
	DESTINATION=$2
	"$GDD" if="$PREFIX" of="$DESTINATION" bs="$RAW_SECTOR_BYTES" \
		skip="$RAW_SEEK_SECTORS" count="$RAW_WRITE_SECTORS" \
		iflag=fullblock status=none || return 1
	[ "$(stat -f '%z' "$DESTINATION")" -eq "$RAW_WRITE_BYTES" ] || return 1
}

write_raw_slice() {
	SOURCE=$1
	[ "$(stat -f '%z' "$SOURCE")" -eq "$RAW_WRITE_BYTES" ] || return 1
	if [ "$HOST_TEST_MODE" -eq 0 ]; then
		sudo -n "$GDD" if="$SOURCE" of="$RAW_DISK" bs="$RAW_SECTOR_BYTES" \
			seek="$RAW_SEEK_SECTORS" count="$RAW_WRITE_SECTORS" \
			iflag=fullblock \
			conv=fsync,notrunc status=none
	else
		"$GDD" if="$SOURCE" of="$RAW_DISK" bs="$RAW_SECTOR_BYTES" \
			seek="$RAW_SEEK_SECTORS" count="$RAW_WRITE_SECTORS" \
			iflag=fullblock \
			conv=fsync,notrunc status=none
	fi
}

restore_original_uboot() {
	if [ "$ACTION" = --restore-baseline ]; then
		RECOVERY_PREFIX=$VERIFY_WORK/expected-prefix.bin
	else
		RECOVERY_PREFIX=$VERIFY_WORK/before-prefix.bin
	fi
	printf 'U-Boot transaction did not commit; restoring the exact verified recovery slice...\n' >&2
	force_unmount_card || return 1
	write_raw_slice "$VERIFY_WORK/recovery-write-slice.bin" || return 1
	read_raw_prefix "$VERIFY_WORK/restored-prefix.bin" || return 1
	cmp "$RECOVERY_PREFIX" \
		"$VERIFY_WORK/restored-prefix.bin" >/dev/null || return 1
	WRITE_STARTED=0
	if [ "$ACTION" = --restore-baseline ]; then
		printf 'Exact accepted baseline 16 MiB prefix restored and verified.\n' >&2
	else
		printf 'Exact pre-transaction 16 MiB prefix restored and verified.\n' >&2
	fi
	return 0
}

cleanup() {
	STATUS=$?
	[ "$CLEANUP_ACTIVE" -eq 0 ] || exit "$STATUS"
	CLEANUP_ACTIVE=1
	trap - EXIT HUP INT TERM
	if [ "$STATUS" -ne 0 ] && [ "$WRITE_STARTED" -eq 1 ] && \
		[ "$COMMITTED" -eq 0 ]; then
		if ! restore_original_uboot; then
			printf 'error: automatic baseline restoration failed; keep the card inserted and retain diagnostics at %s\n' \
				"$VERIFY_WORK" >&2
		fi
	fi
	if ! mount_card; then
		printf 'error: could not remount /dev/%s after U-Boot transaction\n' "$WHOLE" >&2
		STATUS=1
	fi
	if command -v bird_card_lock_release >/dev/null 2>&1; then
		bird_card_lock_release || STATUS=1
	fi
	if [ "$STATUS" -eq 0 ] || [ "$WRITE_OCCURRED" -eq 0 ]; then
		remove_verify_work || STATUS=1
	elif [ -n "$VERIFY_WORK" ]; then
		printf 'Host diagnostic snapshot retained at: %s\n' "$VERIFY_WORK" >&2
	fi
	exit "$STATUS"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
case "$DEVICE" in /dev/disk[0-9]*) ;; *) usage ;; esac
case "$ACTION" in
	--install-green|--install-early-green|--install-env-nowhere|--install-direct-extlinux|--install-no-heap-clear|--install-fast-init|--install-inplace-handoff|--restore-baseline) ;;
	*) usage ;;
esac
WHOLE=${DEVICE#/dev/}

case "$HOST_TEST_MODE" in
	0)
		[ -z "${BIRD_DEVICE_INFO:-}${TEST_RAW_DISK}${TEST_FAILPOINT}${TEST_ROOT}${TEST_BASELINE_PREFIX_SHA}${TEST_GREEN_PREFIX_SHA}${TEST_EARLY_PREFIX_SHA}${TEST_ENV_PREFIX_SHA}${TEST_NO_HEAP_CLEAR_UBOOT_SHA}${TEST_NO_HEAP_CLEAR_PREFIX_SHA}${TEST_FAST_INIT_UBOOT_SHA}${TEST_FAST_INIT_PREFIX_SHA}${TEST_INPLACE_HANDOFF_UBOOT_SHA}${TEST_INPLACE_HANDOFF_PREFIX_SHA}" ] ||
			fail 'test overrides require U-Boot host-test mode'
		RAW_DISK=/dev/r$WHOLE
		;;
	1)
		: "${BIRD_DEVICE_INFO:?host-test device metadata is required}"
		: "${TEST_RAW_DISK:?host-test raw-disk fixture is required}"
		: "${TEST_ROOT:?host-test root is required}"
		[ -n "$TEST_EARLY_PREFIX_SHA" ] || TEST_EARLY_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA
		[ -n "$TEST_ENV_PREFIX_SHA" ] || TEST_ENV_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA
		is_sha256_value "$TEST_BASELINE_PREFIX_SHA" &&
			is_sha256_value "$TEST_GREEN_PREFIX_SHA" &&
			is_sha256_value "$TEST_EARLY_PREFIX_SHA" &&
			is_sha256_value "$TEST_ENV_PREFIX_SHA" ||
			fail 'host-test full-prefix digests are malformed'
		[ "$TEST_BASELINE_PREFIX_SHA" != "$TEST_GREEN_PREFIX_SHA" ] ||
			fail 'host-test baseline and green full-prefix digests must differ'
		BASELINE_PREFIX_SHA=$TEST_BASELINE_PREFIX_SHA
		GREEN_PREFIX_SHA=$TEST_GREEN_PREFIX_SHA
		EARLY_PREFIX_SHA=$TEST_EARLY_PREFIX_SHA
		ENV_PREFIX_SHA=$TEST_ENV_PREFIX_SHA
		if [ "$ACTION" = --install-no-heap-clear ]; then
			is_sha256_value "$TEST_NO_HEAP_CLEAR_UBOOT_SHA" &&
				is_sha256_value "$TEST_NO_HEAP_CLEAR_PREFIX_SHA" ||
				fail 'host-test no-heap-clear digests are malformed'
			NO_HEAP_CLEAR_UBOOT_SHA=$TEST_NO_HEAP_CLEAR_UBOOT_SHA
			NO_HEAP_CLEAR_PREFIX_SHA=$TEST_NO_HEAP_CLEAR_PREFIX_SHA
		fi
		if [ "$ACTION" = --install-fast-init ]; then
			is_sha256_value "$TEST_FAST_INIT_UBOOT_SHA" &&
				is_sha256_value "$TEST_FAST_INIT_PREFIX_SHA" ||
				fail 'host-test fast-init digests are malformed'
			FAST_INIT_UBOOT_SHA=$TEST_FAST_INIT_UBOOT_SHA
			FAST_INIT_PREFIX_SHA=$TEST_FAST_INIT_PREFIX_SHA
		fi
		if [ "$ACTION" = --install-inplace-handoff ]; then
			is_sha256_value "$TEST_INPLACE_HANDOFF_UBOOT_SHA" &&
				is_sha256_value "$TEST_INPLACE_HANDOFF_PREFIX_SHA" ||
				fail 'host-test in-place-handoff digests are malformed'
			INPLACE_HANDOFF_UBOOT_SHA=$TEST_INPLACE_HANDOFF_UBOOT_SHA
			INPLACE_HANDOFF_PREFIX_SHA=$TEST_INPLACE_HANDOFF_PREFIX_SHA
		fi
		RAW_DISK=$TEST_RAW_DISK
		;;
	*) fail 'invalid U-Boot host-test mode' ;;
esac

for COMMAND in python3 shasum awk cmp stat wc tr grep; do
	command -v "$COMMAND" >/dev/null 2>&1 || fail "required command missing: $COMMAND"
done
[ -x "$GDD" ] || fail 'GNU dd is required; install it with: brew install coreutils'
if [ "$HOST_TEST_MODE" -eq 0 ]; then
	for COMMAND in diskutil plutil sudo; do
		command -v "$COMMAND" >/dev/null 2>&1 || fail "required command missing: $COMMAND"
	done
fi

if [ "$HOST_TEST_MODE" -eq 1 ]; then
	[ -d "$TEST_ROOT" ] && [ ! -L "$TEST_ROOT" ] ||
		fail 'U-Boot host-test root is missing or unsafe'
	[ "$(stat -f '%u' "$TEST_ROOT")" = "$(id -u)" ] ||
		fail 'U-Boot host-test root owner is unsafe'
	CANONICAL_TEST_ROOT=$(python3 -c \
		'import os,sys; print(os.path.realpath(sys.argv[1]))' "$TEST_ROOT")
	case "$CANONICAL_TEST_ROOT" in
		/private/var/folders/*|/private/tmp/*) ;;
		*) fail 'U-Boot host-test root is outside temporary storage' ;;
	esac
	for TEST_PATH in "$BIRD" "$DATA" "$BIRD_DEVICE_INFO" \
		"$TEST_RAW_DISK" "$UBOOT_BUILD"; do
		CANONICAL_TEST_PATH=$(python3 -c \
			'import os,sys; print(os.path.realpath(sys.argv[1]))' "$TEST_PATH")
		case "$CANONICAL_TEST_PATH" in
			"$CANONICAL_TEST_ROOT"/*) ;;
			*) fail 'U-Boot host-test path escapes its private temporary root' ;;
		esac
	done
	[ -d "$BIRD" ] && [ ! -L "$BIRD" ] &&
		[ -d "$DATA" ] && [ ! -L "$DATA" ] &&
		[ -d "$UBOOT_BUILD" ] && [ ! -L "$UBOOT_BUILD" ] ||
		fail 'U-Boot host-test directories are unsafe'
	is_regular_file "$BIRD_DEVICE_INFO" && is_regular_file "$TEST_RAW_DISK" ||
		fail 'U-Boot host-test metadata or raw fixture is unsafe'
	[ "$(stat -f '%u' "$BIRD_DEVICE_INFO")" = "$(id -u)" ] &&
		[ "$(stat -f '%u' "$TEST_RAW_DISK")" = "$(id -u)" ] ||
		fail 'U-Boot host-test fixture owner is unsafe'
fi

AUTHORITY_VERIFIER=$ROOT/kernel/rocknix/verify-uboot-install-authority.py
EARLY_AUTHORITY_VERIFIER=$ROOT/kernel/rocknix/verify-uboot-early-led-build.py
ENV_AUTHORITY_VERIFIER=$ROOT/kernel/rocknix/verify-uboot-environment-nowhere-build.py
DIRECT_AUTHORITY_VERIFIER=$ROOT/kernel/rocknix/verify-uboot-direct-extlinux-build.py
NO_HEAP_CLEAR_AUTHORITY_VERIFIER=$ROOT/kernel/rocknix/verify-uboot-no-heap-clear-build.py
FAST_INIT_AUTHORITY_VERIFIER=$ROOT/kernel/rocknix/verify-uboot-fast-init-build.py
INPLACE_HANDOFF_AUTHORITY_VERIFIER=$ROOT/kernel/rocknix/verify-uboot-inplace-handoff-build.py
INVENTORY_TOOL=$ROOT/kernel/rocknix/inventory-bird-boot-volume.py
RELEASE_VERIFIER=$ROOT/kernel/rocknix/verify-selected-bird-release.py
is_regular_file "$AUTHORITY_VERIFIER" || fail 'U-Boot install-authority verifier is missing or unsafe'
is_regular_file "$EARLY_AUTHORITY_VERIFIER" || fail 'early-LED U-Boot verifier is missing or unsafe'
is_regular_file "$ENV_AUTHORITY_VERIFIER" || fail 'environment U-Boot verifier is missing or unsafe'
is_regular_file "$DIRECT_AUTHORITY_VERIFIER" || fail 'direct-extlinux U-Boot verifier is missing or unsafe'
if [ "$ACTION" = --install-no-heap-clear ]; then
	is_regular_file "$NO_HEAP_CLEAR_AUTHORITY_VERIFIER" ||
		fail 'no-heap-clear U-Boot verifier is missing or unsafe'
fi
if [ "$ACTION" = --install-fast-init ]; then
	is_regular_file "$FAST_INIT_AUTHORITY_VERIFIER" ||
		fail 'fast-init U-Boot verifier is missing or unsafe'
fi
if [ "$ACTION" = --install-inplace-handoff ]; then
	is_regular_file "$INPLACE_HANDOFF_AUTHORITY_VERIFIER" ||
		fail 'in-place-handoff U-Boot verifier is missing or unsafe'
fi
is_regular_file "$INVENTORY_TOOL" || fail 'BIRD inventory verifier is missing or unsafe'
is_regular_file "$RELEASE_VERIFIER" || fail 'selected-release verifier is missing or unsafe'
case "$ACTION" in
	--install-early-green|--restore-baseline)
		BUILD_BASELINE=$UBOOT_BUILD/shipping-baseline.bin
		BUILD_BASELINE_PREFIX=$UBOOT_BUILD/baseline-prefix-16m.bin
		;;
	--install-env-nowhere)
		BUILD_BASELINE=$UBOOT_BUILD/shipping-baseline.bin
		BUILD_BASELINE_PREFIX=$UBOOT_BUILD/baseline-prefix-16m.bin
		;;
	--install-direct-extlinux|--install-no-heap-clear|--install-fast-init|--install-inplace-handoff)
		BUILD_BASELINE=$UBOOT_BUILD/shipping-baseline.bin
		BUILD_BASELINE_PREFIX=$UBOOT_BUILD/baseline-prefix-16m.bin
		;;
	*)
		BUILD_BASELINE=$UBOOT_BUILD/rocknix-baseline.bin
		BUILD_BASELINE_PREFIX=
		;;
esac
is_regular_file "$BUILD_BASELINE" ||
	fail 'shipping U-Boot baseline oracle is missing or unsafe'
[ "$(stat -f '%z' "$BUILD_BASELINE")" -eq "$BASELINE_UBOOT_BYTES" ] ||
	fail 'shipping U-Boot baseline size changed'
[ "$(sha256 "$BUILD_BASELINE")" = "$BASELINE_SHA" ] ||
	fail 'shipping U-Boot baseline identity changed'
BUILD_CANDIDATE=
if [ "$ACTION" = --install-green ]; then
	if [ "$HOST_TEST_MODE" -eq 1 ]; then
		BIRD_UBOOT_AUTHORITY_HOST_TEST=1 python3 "$AUTHORITY_VERIFIER" \
			--allow-unreviewed-test-candidate "$UBOOT_BUILD" >/dev/null ||
			fail 'U-Boot host-test build authority verification failed'
	else
		python3 "$AUTHORITY_VERIFIER" "$UBOOT_BUILD" >/dev/null ||
			fail 'U-Boot build authority verification failed'
	fi
	BUILD_CANDIDATE=$UBOOT_BUILD/bird-uboot-green.bin
	is_regular_file "$BUILD_CANDIDATE" ||
		fail 'verified green U-Boot candidate is missing or unsafe'
	[ "$(stat -f '%z' "$BUILD_CANDIDATE")" -eq "$UBOOT_BYTES" ] ||
		fail 'verified green U-Boot candidate size changed'
	[ "$(sha256 "$BUILD_CANDIDATE")" != "$BASELINE_SHA" ] ||
		fail 'green U-Boot candidate is byte-identical to baseline'
elif [ "$ACTION" = --install-early-green ]; then
	python3 "$EARLY_AUTHORITY_VERIFIER" --verify-output "$UBOOT_BUILD" >/dev/null ||
		fail 'early-LED U-Boot build authority verification failed'
	BUILD_CANDIDATE=$UBOOT_BUILD/early-green.bin
	is_regular_file "$BUILD_CANDIDATE" ||
		fail 'verified early-green U-Boot candidate is missing or unsafe'
	[ "$(stat -f '%z' "$BUILD_CANDIDATE")" -eq "$EARLY_UBOOT_BYTES" ] ||
		fail 'verified early-green U-Boot candidate size changed'
elif [ "$ACTION" = --install-env-nowhere ]; then
	python3 "$ENV_AUTHORITY_VERIFIER" --verify-output "$UBOOT_BUILD" >/dev/null ||
		fail 'nowhere-environment U-Boot authority verification failed'
	BUILD_CANDIDATE=$UBOOT_BUILD/env-nowhere.bin
	is_regular_file "$BUILD_CANDIDATE" ||
		fail 'verified nowhere-environment U-Boot candidate is missing or unsafe'
	[ "$(stat -f '%z' "$BUILD_CANDIDATE")" -eq "$ENV_UBOOT_BYTES" ] ||
		fail 'verified nowhere-environment U-Boot candidate size changed'
elif [ "$ACTION" = --install-direct-extlinux ]; then
	python3 "$DIRECT_AUTHORITY_VERIFIER" --verify-output "$UBOOT_BUILD" >/dev/null ||
		fail 'direct-extlinux U-Boot authority verification failed'
	BUILD_CANDIDATE=$UBOOT_BUILD/direct-extlinux.bin
	is_regular_file "$BUILD_CANDIDATE" || fail 'verified direct-extlinux candidate is missing or unsafe'
	[ "$(stat -f '%z' "$BUILD_CANDIDATE")" -eq "$ENV_UBOOT_BYTES" ] ||
		fail 'verified direct-extlinux candidate size changed'
elif [ "$ACTION" = --install-no-heap-clear ]; then
	[ "$NO_HEAP_CLEAR_UBOOT_SHA" != pending ] &&
		[ "$NO_HEAP_CLEAR_PREFIX_SHA" != pending ] ||
		fail 'no-heap-clear U-Boot identities have not been promoted'
	python3 "$NO_HEAP_CLEAR_AUTHORITY_VERIFIER" --verify-output "$UBOOT_BUILD" >/dev/null ||
		fail 'no-heap-clear U-Boot authority verification failed'
	BUILD_CANDIDATE=$UBOOT_BUILD/no-heap-clear.bin
	is_regular_file "$BUILD_CANDIDATE" ||
		fail 'verified no-heap-clear candidate is missing or unsafe'
	[ "$(stat -f '%z' "$BUILD_CANDIDATE")" -eq "$NO_HEAP_CLEAR_UBOOT_BYTES" ] ||
		fail 'verified no-heap-clear candidate size changed'
	[ "$(sha256 "$BUILD_CANDIDATE")" = "$NO_HEAP_CLEAR_UBOOT_SHA" ] ||
		fail 'verified no-heap-clear candidate identity changed'
elif [ "$ACTION" = --install-fast-init ]; then
	[ "$FAST_INIT_UBOOT_SHA" != pending ] &&
		[ "$FAST_INIT_PREFIX_SHA" != pending ] ||
		fail 'fast-init U-Boot identities have not been promoted'
	python3 "$FAST_INIT_AUTHORITY_VERIFIER" --verify-output "$UBOOT_BUILD" >/dev/null ||
		fail 'fast-init U-Boot authority verification failed'
	BUILD_CANDIDATE=$UBOOT_BUILD/fast-init.bin
	is_regular_file "$BUILD_CANDIDATE" ||
		fail 'verified fast-init candidate is missing or unsafe'
	[ "$(stat -f '%z' "$BUILD_CANDIDATE")" -eq "$FAST_INIT_UBOOT_BYTES" ] ||
		fail 'verified fast-init candidate size changed'
	[ "$(sha256 "$BUILD_CANDIDATE")" = "$FAST_INIT_UBOOT_SHA" ] ||
		fail 'verified fast-init candidate identity changed'
elif [ "$ACTION" = --install-inplace-handoff ]; then
	python3 "$INPLACE_HANDOFF_AUTHORITY_VERIFIER" --verify-output "$UBOOT_BUILD" >/dev/null ||
		fail 'in-place-handoff U-Boot authority verification failed'
	BUILD_CANDIDATE=$UBOOT_BUILD/inplace-handoff.bin
	is_regular_file "$BUILD_CANDIDATE" ||
		fail 'verified in-place-handoff candidate is missing or unsafe'
	[ "$(stat -f '%z' "$BUILD_CANDIDATE")" -eq "$INPLACE_HANDOFF_UBOOT_BYTES" ] ||
		fail 'verified in-place-handoff candidate size changed'
	[ "$(sha256 "$BUILD_CANDIDATE")" = "$INPLACE_HANDOFF_UBOOT_SHA" ] ||
		fail 'verified in-place-handoff candidate identity changed'
fi
if [ "$ACTION" = --install-early-green ] || [ "$ACTION" = --install-env-nowhere ] ||
	[ "$ACTION" = --install-direct-extlinux ] || [ "$ACTION" = --install-no-heap-clear ] ||
	[ "$ACTION" = --install-fast-init ] ||
	[ "$ACTION" = --install-inplace-handoff ] ||
	[ "$ACTION" = --restore-baseline ]; then
	is_regular_file "$BUILD_BASELINE_PREFIX" &&
		[ "$(stat -f '%z' "$BUILD_BASELINE_PREFIX")" -eq "$PREFIX_BYTES" ] &&
		[ "$(sha256 "$BUILD_BASELINE_PREFIX")" = "$BASELINE_PREFIX_SHA" ] ||
		fail 'accepted baseline 16 MiB prefix oracle changed'
fi

plist_value() {
	if [ "$HOST_TEST_MODE" -eq 1 ]; then
		awk -F '\t' -v device="$1" -v key="$2" \
			'$1 == device && $2 == key {print $3; exit}' "$BIRD_DEVICE_INFO"
		return
	fi
	diskutil info -plist "$1" | plutil -extract "$2" raw -o - -
}

# shellcheck source=mac-removable-device.sh
. "$ROOT/firmware/mac-removable-device.sh"
# shellcheck source=mac-stock-root-card-identity.sh
. "$ROOT/firmware/mac-stock-root-card-identity.sh"
# shellcheck source=mac-bird-card-lock.sh
. "$ROOT/firmware/mac-bird-card-lock.sh"

validate_requested_card() {
	validate_stock_root_card_identity
	[ "$WHOLE" = "${DEVICE#/dev/}" ] ||
		fail 'requested whole disk differs from the mounted Bird volumes'
	bird_require_safe_removable_device "/dev/$WHOLE"
}

validate_requested_card
LOCKED_WHOLE=$WHOLE

# Authenticate before taking the shared transaction lock. Every later raw
# operation is non-interactive and the lock is never held across a password UI.
if [ "$HOST_TEST_MODE" -eq 0 ]; then
	sudo -v
fi

bird_card_lock_acquire
validate_requested_card
[ "$WHOLE" = "$LOCKED_WHOLE" ] ||
	fail 'card identity changed after acquiring its U-Boot transaction lock'

VERIFY_WORK=$(mktemp -d "${TMPDIR:-/tmp}/bird-uboot-install.XXXXXX") ||
	fail 'could not create private U-Boot verification directory'
# Snapshot every later raw-write input while holding the shared card lock. The
# externally supplied directory is never trusted again afterward. Recovery
# needs only the independently pinned shipping oracle; green installation
# continues to require the complete reviewed build authority.
if [ "$ACTION" = --install-green ] || [ "$ACTION" = --install-early-green ] ||
	[ "$ACTION" = --install-env-nowhere ] || [ "$ACTION" = --install-direct-extlinux ] ||
	[ "$ACTION" = --install-no-heap-clear ] || [ "$ACTION" = --install-fast-init ] ||
	[ "$ACTION" = --install-inplace-handoff ]; then
	AUTHORITY_SNAPSHOT=$VERIFY_WORK/build-authority
	COPYFILE_DISABLE=1 cp -R "$UBOOT_BUILD" "$AUTHORITY_SNAPSHOT" ||
		fail 'could not snapshot the complete U-Boot build authority under lock'
	if [ "$ACTION" = --install-green ] && [ "$HOST_TEST_MODE" -eq 1 ]; then
		BIRD_UBOOT_AUTHORITY_HOST_TEST=1 python3 "$AUTHORITY_VERIFIER" \
			--allow-unreviewed-test-candidate "$AUTHORITY_SNAPSHOT" >/dev/null ||
			fail 'snapshotted U-Boot host-test authority verification failed'
	elif [ "$ACTION" = --install-green ]; then
		python3 "$AUTHORITY_VERIFIER" "$AUTHORITY_SNAPSHOT" >/dev/null ||
			fail 'snapshotted U-Boot build authority verification failed'
	elif [ "$ACTION" = --install-early-green ]; then
		python3 "$EARLY_AUTHORITY_VERIFIER" --verify-output "$AUTHORITY_SNAPSHOT" >/dev/null ||
			fail 'snapshotted early-LED U-Boot build authority verification failed'
	elif [ "$ACTION" = --install-env-nowhere ]; then
		python3 "$ENV_AUTHORITY_VERIFIER" --verify-output "$AUTHORITY_SNAPSHOT" >/dev/null ||
			fail 'snapshotted nowhere-environment U-Boot authority verification failed'
	elif [ "$ACTION" = --install-direct-extlinux ]; then
		python3 "$DIRECT_AUTHORITY_VERIFIER" --verify-output "$AUTHORITY_SNAPSHOT" >/dev/null ||
			fail 'snapshotted direct-extlinux U-Boot authority verification failed'
	elif [ "$ACTION" = --install-no-heap-clear ]; then
		python3 "$NO_HEAP_CLEAR_AUTHORITY_VERIFIER" --verify-output "$AUTHORITY_SNAPSHOT" >/dev/null ||
			fail 'snapshotted no-heap-clear U-Boot authority verification failed'
	elif [ "$ACTION" = --install-fast-init ]; then
		python3 "$FAST_INIT_AUTHORITY_VERIFIER" --verify-output "$AUTHORITY_SNAPSHOT" >/dev/null ||
			fail 'snapshotted fast-init U-Boot authority verification failed'
	else
		python3 "$INPLACE_HANDOFF_AUTHORITY_VERIFIER" --verify-output "$AUTHORITY_SNAPSHOT" >/dev/null ||
			fail 'snapshotted in-place-handoff U-Boot authority verification failed'
	fi
	if [ "$ACTION" = --install-green ]; then
		BASELINE=$AUTHORITY_SNAPSHOT/rocknix-baseline.bin
		BASELINE_PREFIX=
		CANDIDATE=$AUTHORITY_SNAPSHOT/bird-uboot-green.bin
	elif [ "$ACTION" = --install-early-green ]; then
		BASELINE=$AUTHORITY_SNAPSHOT/shipping-baseline.bin
		BASELINE_PREFIX=$AUTHORITY_SNAPSHOT/baseline-prefix-16m.bin
		CANDIDATE=$AUTHORITY_SNAPSHOT/early-green.bin
	elif [ "$ACTION" = --install-env-nowhere ]; then
		BASELINE=$AUTHORITY_SNAPSHOT/shipping-baseline.bin
		BASELINE_PREFIX=$AUTHORITY_SNAPSHOT/baseline-prefix-16m.bin
		CANDIDATE=$AUTHORITY_SNAPSHOT/env-nowhere.bin
	elif [ "$ACTION" = --install-direct-extlinux ]; then
		BASELINE=$AUTHORITY_SNAPSHOT/shipping-baseline.bin
		BASELINE_PREFIX=$AUTHORITY_SNAPSHOT/baseline-prefix-16m.bin
		CANDIDATE=$AUTHORITY_SNAPSHOT/direct-extlinux.bin
	elif [ "$ACTION" = --install-no-heap-clear ]; then
		BASELINE=$AUTHORITY_SNAPSHOT/shipping-baseline.bin
		BASELINE_PREFIX=$AUTHORITY_SNAPSHOT/baseline-prefix-16m.bin
		CANDIDATE=$AUTHORITY_SNAPSHOT/no-heap-clear.bin
	elif [ "$ACTION" = --install-fast-init ]; then
		BASELINE=$AUTHORITY_SNAPSHOT/shipping-baseline.bin
		BASELINE_PREFIX=$AUTHORITY_SNAPSHOT/baseline-prefix-16m.bin
		CANDIDATE_BASE_PREFIX=$AUTHORITY_SNAPSHOT/base-no-heap-clear-prefix-16m.bin
		CANDIDATE=$AUTHORITY_SNAPSHOT/fast-init.bin
	else
		BASELINE=$AUTHORITY_SNAPSHOT/shipping-baseline.bin
		BASELINE_PREFIX=$AUTHORITY_SNAPSHOT/baseline-prefix-16m.bin
		CANDIDATE_BASE_PREFIX=$AUTHORITY_SNAPSHOT/base-fast-init-prefix-16m.bin
		CANDIDATE=$AUTHORITY_SNAPSHOT/inplace-handoff.bin
	fi
else
	BASELINE=$VERIFY_WORK/rocknix-baseline.bin
	BASELINE_PREFIX=$VERIFY_WORK/baseline-prefix-16m.bin
	COPYFILE_DISABLE=1 cp -f "$BUILD_BASELINE" "$BASELINE" ||
		fail 'could not snapshot the shipping U-Boot baseline under lock'
	COPYFILE_DISABLE=1 cp -f "$BUILD_BASELINE_PREFIX" "$BASELINE_PREFIX" ||
		fail 'could not snapshot the accepted baseline prefix under lock'
	CANDIDATE=
fi
[ -f "$BASELINE" ] && [ ! -L "$BASELINE" ] &&
	[ "$(stat -f '%z' "$BASELINE")" -eq "$BASELINE_UBOOT_BYTES" ] &&
	[ "$(sha256 "$BASELINE")" = "$BASELINE_SHA" ] ||
	fail 'snapshotted shipping U-Boot baseline identity changed'
if [ "$ACTION" = --install-early-green ] || [ "$ACTION" = --install-env-nowhere ] ||
	[ "$ACTION" = --install-direct-extlinux ] || [ "$ACTION" = --install-no-heap-clear ] ||
	[ "$ACTION" = --install-fast-init ] ||
	[ "$ACTION" = --install-inplace-handoff ] ||
	[ "$ACTION" = --restore-baseline ]; then
	[ -f "$BASELINE_PREFIX" ] && [ ! -L "$BASELINE_PREFIX" ] &&
		[ "$(stat -f '%z' "$BASELINE_PREFIX")" -eq "$PREFIX_BYTES" ] &&
		[ "$(sha256 "$BASELINE_PREFIX")" = "$BASELINE_PREFIX_SHA" ] ||
		fail 'snapshotted baseline prefix identity changed'
fi
if [ "$ACTION" = --install-fast-init ]; then
	[ -f "$CANDIDATE_BASE_PREFIX" ] && [ ! -L "$CANDIDATE_BASE_PREFIX" ] &&
		[ "$(stat -f '%z' "$CANDIDATE_BASE_PREFIX")" -eq "$PREFIX_BYTES" ] &&
		[ "$(sha256 "$CANDIDATE_BASE_PREFIX")" = "$NO_HEAP_CLEAR_PREFIX_SHA" ] ||
		fail 'snapshotted no-heap-clear predecessor prefix identity changed'
fi
if [ "$ACTION" = --install-inplace-handoff ]; then
	[ -f "$CANDIDATE_BASE_PREFIX" ] && [ ! -L "$CANDIDATE_BASE_PREFIX" ] &&
		[ "$(stat -f '%z' "$CANDIDATE_BASE_PREFIX")" -eq "$PREFIX_BYTES" ] &&
		[ "$(sha256 "$CANDIDATE_BASE_PREFIX")" = "$FAST_INIT_PREFIX_SHA" ] ||
		fail 'snapshotted fast-init predecessor prefix identity changed'
fi
if [ "$HOST_TEST_MODE" -eq 1 ]; then
	python3 "$RELEASE_VERIFIER" --host-test "$BIRD" \
		>"$VERIFY_WORK/selected-release.txt" ||
		fail 'active BIRD selector or selected release failed verification'
else
	python3 "$RELEASE_VERIFIER" "$BIRD" \
		>"$VERIFY_WORK/selected-release.txt" ||
		fail 'active BIRD selector or selected release failed verification'
fi
for OBSOLETE_BOOT_PATH in \
	"$BIRD/KERNEL.fallback" \
	"$BIRD/dtb.img" \
	"$BIRD/extlinux/extlinux.fallback.conf" \
	"$DATA/Bird/boot-state/releases"; do
	[ ! -e "$OBSOLETE_BOOT_PATH" ] && [ ! -L "$OBSOLETE_BOOT_PATH" ] ||
		fail "obsolete alternate-boot state remains: $OBSOLETE_BOOT_PATH"
done
python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-before.tsv" ||
	fail 'could not inventory BIRD before U-Boot installation'
NAMESPACE=$DATA/Bird/namespace-v1.tsv
is_regular_file "$NAMESPACE" &&
	[ "$(wc -l <"$NAMESPACE" | tr -d ' ')" -eq 2 ] &&
	grep -Fqx 'revision	bird-canonical-namespace-v1' "$NAMESPACE" &&
	grep -Fqx 'state	committed' "$NAMESPACE" ||
	fail 'canonical namespace v1 is not committed'
NAMESPACE_BYTES=$(stat -f '%z' "$NAMESPACE")
NAMESPACE_SHA=$(sha256 "$NAMESPACE")

read_raw_prefix "$VERIFY_WORK/before-prefix.bin" ||
	fail 'could not read the complete user-owned 16 MiB prefix snapshot'
CURRENT_PREFIX_SHA=$(sha256 "$VERIFY_WORK/before-prefix.bin")
"$GDD" if="$VERIFY_WORK/before-prefix.bin" \
	of="$VERIFY_WORK/current-uboot.bin" bs=64K skip="$RAW_OFFSET" \
	count="$UBOOT_BYTES" iflag=skip_bytes,count_bytes,fullblock status=none
[ "$(stat -f '%z' "$VERIFY_WORK/current-uboot.bin")" -eq "$UBOOT_BYTES" ] ||
fail 'current raw U-Boot read was short'
"$GDD" if="$VERIFY_WORK/before-prefix.bin" \
	of="$VERIFY_WORK/current-baseline-range.bin" bs=64K skip="$RAW_OFFSET" \
	count="$BASELINE_UBOOT_BYTES" iflag=skip_bytes,count_bytes,fullblock status=none
[ "$(stat -f '%z' "$VERIFY_WORK/current-baseline-range.bin")" -eq "$BASELINE_UBOOT_BYTES" ] ||
	fail 'current baseline-range U-Boot read was short'

case "$ACTION" in
	--install-green)
		if cmp "$VERIFY_WORK/current-uboot.bin" "$CANDIDATE" >/dev/null; then
			[ "$GREEN_PREFIX_SHA" != pending ] &&
				[ "$CURRENT_PREFIX_SHA" = "$GREEN_PREFIX_SHA" ] ||
				fail 'complete current green 16 MiB prefix differs from the reviewed oracle'
			python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" ||
				fail 'could not re-inventory BIRD for U-Boot no-op verification'
			cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null ||
				fail 'BIRD payload changed during U-Boot no-op verification'
			printf 'Verified green U-Boot is already installed at raw bytes [%s,%s).\n' \
				"$RAW_OFFSET" "$RAW_END"
			COMMITTED=1
			exit 0
		fi
		cmp "$VERIFY_WORK/current-uboot.bin" "$BASELINE" >/dev/null ||
			fail 'current raw U-Boot is neither the exact shipping baseline nor this candidate'
		[ "$CURRENT_PREFIX_SHA" = "$BASELINE_PREFIX_SHA" ] ||
			fail 'complete current baseline 16 MiB prefix differs from the accepted layout oracle'
		TARGET_UBOOT=$CANDIDATE
		EXPECTED_PREFIX_SHA=$GREEN_PREFIX_SHA
		TARGET_DESCRIPTION='verified green U-Boot'
		TARGET_UBOOT_BYTES=$BASELINE_UBOOT_BYTES
		;;
	--install-early-green)
		if cmp "$VERIFY_WORK/current-uboot.bin" "$CANDIDATE" >/dev/null; then
			[ "$CURRENT_PREFIX_SHA" = "$EARLY_PREFIX_SHA" ] ||
				fail 'complete current early-green 16 MiB prefix differs from the reviewed oracle'
			python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" ||
				fail 'could not re-inventory BIRD for early-green no-op verification'
			cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null ||
				fail 'BIRD payload changed during early-green no-op verification'
			printf 'Verified early-green U-Boot is already installed at raw bytes [%s,%s).\n' \
				"$RAW_OFFSET" "$RAW_END"
			COMMITTED=1
			exit 0
		fi
		cmp "$VERIFY_WORK/current-baseline-range.bin" \
			"$AUTHORITY_SNAPSHOT/base-green.bin" >/dev/null ||
			fail 'current raw U-Boot is not the exact reviewed full-U-Boot green base'
		[ "$CURRENT_PREFIX_SHA" = "$GREEN_PREFIX_SHA" ] ||
			fail 'complete current green 16 MiB prefix differs from the reviewed oracle'
		TARGET_UBOOT=$CANDIDATE
		TARGET_UBOOT_BYTES=$EARLY_UBOOT_BYTES
		EXPECTED_PREFIX_SHA=$EARLY_PREFIX_SHA
		TARGET_DESCRIPTION='verified early-green/red-off U-Boot'
		;;
	--install-env-nowhere)
		"$GDD" if="$VERIFY_WORK/before-prefix.bin" \
			of="$VERIFY_WORK/current-env-range.bin" bs=64K skip="$RAW_OFFSET" \
			count="$ENV_UBOOT_BYTES" iflag=skip_bytes,count_bytes,fullblock status=none
		if cmp "$VERIFY_WORK/current-env-range.bin" "$CANDIDATE" >/dev/null; then
			[ "$CURRENT_PREFIX_SHA" = "$ENV_PREFIX_SHA" ] ||
				fail 'complete current nowhere-environment prefix differs from the reviewed oracle'
			python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" ||
				fail 'could not re-inventory BIRD for environment no-op verification'
			cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null ||
				fail 'BIRD payload changed during environment no-op verification'
			printf 'Verified nowhere-environment U-Boot is already installed.\n'
			COMMITTED=1
			exit 0
		fi
		cmp "$VERIFY_WORK/current-baseline-range.bin" \
			"$AUTHORITY_SNAPSHOT/base-shipping.bin" >/dev/null || {
			report_current_uboot_identity
			fail 'current raw U-Boot is not the exact shipping base'
		}
		[ "$CURRENT_PREFIX_SHA" = "$BASELINE_PREFIX_SHA" ] ||
			fail 'complete current shipping prefix differs from the reviewed oracle'
		TARGET_UBOOT=$CANDIDATE
		TARGET_UBOOT_BYTES=$ENV_UBOOT_BYTES
		EXPECTED_PREFIX_SHA=$ENV_PREFIX_SHA
		TARGET_DESCRIPTION='verified nowhere-environment U-Boot'
		;;
	--install-direct-extlinux)
		"$GDD" if="$VERIFY_WORK/before-prefix.bin" \
			of="$VERIFY_WORK/current-direct-range.bin" bs=64K skip="$RAW_OFFSET" \
			count="$ENV_UBOOT_BYTES" iflag=skip_bytes,count_bytes,fullblock status=none
		if cmp "$VERIFY_WORK/current-direct-range.bin" "$CANDIDATE" >/dev/null; then
			[ "$CURRENT_PREFIX_SHA" = "$DIRECT_PREFIX_SHA" ] ||
				fail 'complete current direct-extlinux prefix differs from the reviewed oracle'
			python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" ||
				fail 'could not re-inventory BIRD for direct-extlinux no-op verification'
			cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null ||
				fail 'BIRD payload changed during direct-extlinux no-op verification'
			printf 'Verified direct-extlinux U-Boot is already installed.\n'
			COMMITTED=1
			exit 0
		fi
		cmp "$VERIFY_WORK/current-direct-range.bin" \
			"$AUTHORITY_SNAPSHOT/base-env.bin" >/dev/null || {
			report_current_uboot_identity
			fail 'current raw U-Boot is not the exact accepted environment-only base'
		}
		[ "$CURRENT_PREFIX_SHA" = "$ENV_PREFIX_SHA" ] ||
			fail 'complete current environment-only prefix differs from the reviewed oracle'
		TARGET_UBOOT=$CANDIDATE
		TARGET_UBOOT_BYTES=$ENV_UBOOT_BYTES
		EXPECTED_PREFIX_SHA=$DIRECT_PREFIX_SHA
		TARGET_DESCRIPTION='verified direct-extlinux U-Boot'
		;;
	--install-no-heap-clear)
		"$GDD" if="$VERIFY_WORK/before-prefix.bin" \
			of="$VERIFY_WORK/current-no-heap-clear-range.bin" bs=64K skip="$RAW_OFFSET" \
			count="$NO_HEAP_CLEAR_UBOOT_BYTES" iflag=skip_bytes,count_bytes,fullblock status=none
		if cmp "$VERIFY_WORK/current-no-heap-clear-range.bin" "$CANDIDATE" >/dev/null; then
			[ "$NO_HEAP_CLEAR_PREFIX_SHA" != pending ] &&
				[ "$CURRENT_PREFIX_SHA" = "$NO_HEAP_CLEAR_PREFIX_SHA" ] ||
				fail 'complete current no-heap-clear prefix differs from the reviewed oracle'
			python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" ||
				fail 'could not re-inventory BIRD for no-heap-clear no-op verification'
			cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null ||
				fail 'BIRD payload changed during no-heap-clear no-op verification'
			printf 'Verified no-heap-clear U-Boot is already installed.\n'
			COMMITTED=1
			exit 0
		fi
		cmp "$VERIFY_WORK/current-no-heap-clear-range.bin" \
			"$AUTHORITY_SNAPSHOT/base-direct.bin" >/dev/null || {
			report_current_uboot_identity
			fail 'current raw U-Boot is not the exact accepted direct-extlinux base'
		}
		[ "$CURRENT_PREFIX_SHA" = "$DIRECT_PREFIX_SHA" ] ||
			fail 'complete current direct-extlinux prefix differs from the accepted oracle'
		TARGET_UBOOT=$CANDIDATE
		TARGET_UBOOT_BYTES=$NO_HEAP_CLEAR_UBOOT_BYTES
		EXPECTED_PREFIX_SHA=$NO_HEAP_CLEAR_PREFIX_SHA
		TARGET_DESCRIPTION='verified no-heap-clear U-Boot'
		;;
	--install-fast-init)
		"$GDD" if="$VERIFY_WORK/before-prefix.bin" \
			of="$VERIFY_WORK/current-fast-init-range.bin" bs=64K skip="$RAW_OFFSET" \
			count="$FAST_INIT_UBOOT_BYTES" iflag=skip_bytes,count_bytes,fullblock status=none
		if cmp "$VERIFY_WORK/current-fast-init-range.bin" "$CANDIDATE" >/dev/null; then
			[ "$FAST_INIT_PREFIX_SHA" != pending ] &&
				[ "$CURRENT_PREFIX_SHA" = "$FAST_INIT_PREFIX_SHA" ] ||
				fail 'complete current fast-init prefix differs from the reviewed oracle'
			python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" ||
				fail 'could not re-inventory BIRD for fast-init no-op verification'
			cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null ||
				fail 'BIRD payload changed during fast-init no-op verification'
			printf 'Verified fast-init U-Boot is already installed.\n'
			COMMITTED=1
			exit 0
		fi
		"$GDD" if="$VERIFY_WORK/before-prefix.bin" \
			of="$VERIFY_WORK/current-no-heap-clear-base-range.bin" bs=64K skip="$RAW_OFFSET" \
			count="$NO_HEAP_CLEAR_UBOOT_BYTES" iflag=skip_bytes,count_bytes,fullblock status=none
		cmp "$VERIFY_WORK/current-no-heap-clear-base-range.bin" \
			"$AUTHORITY_SNAPSHOT/base-no-heap-clear.bin" >/dev/null || {
			report_current_uboot_identity
			fail 'current raw U-Boot is not the exact accepted no-heap-clear base'
		}
		[ "$CURRENT_PREFIX_SHA" = "$NO_HEAP_CLEAR_PREFIX_SHA" ] ||
			fail 'complete current no-heap-clear prefix differs from the accepted oracle'
		TARGET_UBOOT=$CANDIDATE
		TARGET_UBOOT_BYTES=$FAST_INIT_UBOOT_BYTES
		EXPECTED_PREFIX_SHA=$FAST_INIT_PREFIX_SHA
		TARGET_DESCRIPTION='verified fast-init U-Boot'
		;;
	--install-inplace-handoff)
		"$GDD" if="$VERIFY_WORK/before-prefix.bin" \
			of="$VERIFY_WORK/current-inplace-handoff-range.bin" bs=64K skip="$RAW_OFFSET" \
			count="$INPLACE_HANDOFF_UBOOT_BYTES" iflag=skip_bytes,count_bytes,fullblock status=none
		if cmp "$VERIFY_WORK/current-inplace-handoff-range.bin" "$CANDIDATE" >/dev/null; then
			[ "$CURRENT_PREFIX_SHA" = "$INPLACE_HANDOFF_PREFIX_SHA" ] ||
				fail 'complete current in-place-handoff prefix differs from the reviewed oracle'
			python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" ||
				fail 'could not re-inventory BIRD for in-place-handoff no-op verification'
			cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null ||
				fail 'BIRD payload changed during in-place-handoff no-op verification'
			printf 'Verified in-place-handoff U-Boot is already installed.\n'
			COMMITTED=1
			exit 0
		fi
		cmp "$VERIFY_WORK/current-inplace-handoff-range.bin" \
			"$AUTHORITY_SNAPSHOT/base-fast-init.bin" >/dev/null || {
			report_current_uboot_identity
			fail 'current raw U-Boot is not the exact accepted fast-init base'
		}
		[ "$CURRENT_PREFIX_SHA" = "$FAST_INIT_PREFIX_SHA" ] ||
			fail 'complete current fast-init prefix differs from the accepted oracle'
		TARGET_UBOOT=$CANDIDATE
		TARGET_UBOOT_BYTES=$INPLACE_HANDOFF_UBOOT_BYTES
		EXPECTED_PREFIX_SHA=$INPLACE_HANDOFF_PREFIX_SHA
		TARGET_DESCRIPTION='verified in-place-handoff U-Boot'
		;;
	--restore-baseline)
		if cmp "$VERIFY_WORK/current-baseline-range.bin" "$BASELINE" >/dev/null &&
			[ "$CURRENT_PREFIX_SHA" = "$BASELINE_PREFIX_SHA" ]; then
			python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" ||
				fail 'could not re-inventory BIRD for baseline no-op verification'
			cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null ||
				fail 'BIRD payload changed during baseline no-op verification'
			printf 'Verified shipping baseline U-Boot is already restored at raw bytes [%s,%s).\n' \
				"$RAW_OFFSET" "$RAW_END"
			COMMITTED=1
			exit 0
		fi
		TARGET_UBOOT=$BASELINE
		TARGET_UBOOT_BYTES=$BASELINE_UBOOT_BYTES
		EXPECTED_PREFIX_SHA=$BASELINE_PREFIX_SHA
		TARGET_DESCRIPTION='shipping baseline U-Boot'
		;;
esac

if [ "$ACTION" = --restore-baseline ]; then
	python3 - "$VERIFY_WORK/before-prefix.bin" "$BASELINE_PREFIX" \
		"$RAW_OFFSET" "$EARLY_RAW_END" <<'PY' ||
import pathlib
import sys

current = pathlib.Path(sys.argv[1]).read_bytes()
baseline = pathlib.Path(sys.argv[2]).read_bytes()
start, end = map(int, sys.argv[3:])
if current[:start] != baseline[:start] or current[end:] != baseline[end:]:
    raise SystemExit(1)
PY
		fail 'current prefix differs from the accepted layout outside the recoverable U-Boot range'
	COPYFILE_DISABLE=1 cp -f "$BASELINE_PREFIX" "$VERIFY_WORK/expected-prefix.bin"
else
	if [ "$ACTION" = --install-env-nowhere ] || [ "$ACTION" = --install-direct-extlinux ] ||
		[ "$ACTION" = --install-no-heap-clear ]; then
		COPYFILE_DISABLE=1 cp -f "$BASELINE_PREFIX" "$VERIFY_WORK/expected-prefix.bin"
	elif [ "$ACTION" = --install-fast-init ]; then
		COPYFILE_DISABLE=1 cp -f "$CANDIDATE_BASE_PREFIX" \
			"$VERIFY_WORK/expected-prefix.bin"
	elif [ "$ACTION" = --install-inplace-handoff ]; then
		COPYFILE_DISABLE=1 cp -f "$CANDIDATE_BASE_PREFIX" \
			"$VERIFY_WORK/expected-prefix.bin"
	else
		COPYFILE_DISABLE=1 cp -f "$VERIFY_WORK/before-prefix.bin" \
			"$VERIFY_WORK/expected-prefix.bin"
	fi
	"$GDD" if="$TARGET_UBOOT" of="$VERIFY_WORK/expected-prefix.bin" bs=64K \
		seek="$RAW_OFFSET" count="$TARGET_UBOOT_BYTES" \
		iflag=count_bytes,fullblock oflag=seek_bytes conv=notrunc status=none
fi
[ "$EXPECTED_PREFIX_SHA" != pending ] &&
	[ "$(sha256 "$VERIFY_WORK/expected-prefix.bin")" = "$EXPECTED_PREFIX_SHA" ] ||
	fail 'complete expected 16 MiB prefix is not the pinned result'

# Build complete-sector write inputs from the already verified full-prefix
# snapshots. The last seven physical bytes are therefore preserved exactly and
# are never synthesized from the shorter 621,049-byte U-Boot artifact.
extract_raw_write_slice "$VERIFY_WORK/expected-prefix.bin" \
	"$VERIFY_WORK/target-write-slice.bin" ||
	fail 'could not prepare the sector-aligned target write slice'
if [ "$ACTION" = --restore-baseline ]; then
	RECOVERY_WRITE_PREFIX=$VERIFY_WORK/expected-prefix.bin
else
	RECOVERY_WRITE_PREFIX=$VERIFY_WORK/before-prefix.bin
fi
extract_raw_write_slice "$RECOVERY_WRITE_PREFIX" \
	"$VERIFY_WORK/recovery-write-slice.bin" ||
	fail 'could not prepare the sector-aligned recovery write slice'

# Repeat the complete volume-to-whole-disk binding immediately before the
# mounted filesystems are taken away and the raw path becomes the write target.
validate_requested_card
[ "$WHOLE" = "$LOCKED_WHOLE" ] ||
	fail 'card identity changed before the raw U-Boot write'

printf 'Writing %s to %s raw bytes [%s,%s)...\n' \
	"$TARGET_DESCRIPTION" "$RAW_DISK" "$RAW_OFFSET" "$RAW_END"
printf 'Physical write is sector-aligned [%s,%s); bytes [%s,%s) are preserved from the verified prefix.\n' \
	"$RAW_OFFSET" "$RAW_WRITE_END" "$RAW_END" "$RAW_WRITE_END"
unmount_card || fail 'could not unmount the complete Bird card before raw U-Boot write'
WRITE_STARTED=1
WRITE_OCCURRED=1
write_raw_slice "$VERIFY_WORK/target-write-slice.bin" || fail 'bounded raw U-Boot write failed'

if [ "$HOST_TEST_MODE" -eq 1 ] && [ "$TEST_FAILPOINT" = after-write-corrupt ]; then
	"$GDD" if=/dev/zero of="$RAW_DISK" bs=1 seek=$((RAW_OFFSET + 4)) \
		count=1 conv=fsync,notrunc status=none
fi
	if [ "$HOST_TEST_MODE" -eq 1 ] &&
		{ [ "$ACTION" = --install-green ] || [ "$ACTION" = --install-early-green ] ||
			[ "$ACTION" = --install-env-nowhere ] || [ "$ACTION" = --install-direct-extlinux ] ||
			[ "$ACTION" = --install-no-heap-clear ] || [ "$ACTION" = --install-fast-init ] ||
			[ "$ACTION" = --install-inplace-handoff ]; } &&
	[ "$TEST_FAILPOINT" = after-write-authority-drift ]; then
	printf 'drift\n' >>"$BUILD_BASELINE"
	printf 'drift\n' >>"$BUILD_CANDIDATE"
	fail 'host-only injected failure: after-write-authority-drift'
fi
if [ "$HOST_TEST_MODE" -eq 1 ] && [ "$TEST_FAILPOINT" = after-write ]; then
	fail 'host-only injected failure: after-write'
fi

read_raw_prefix "$VERIFY_WORK/installed-prefix.bin" ||
	fail 'could not reread the complete installed 16 MiB prefix'
cmp "$VERIFY_WORK/expected-prefix.bin" \
	"$VERIFY_WORK/installed-prefix.bin" >/dev/null ||
	fail 'installed 16 MiB prefix differs outside or inside the exact target range'

mount_card || fail 'could not remount the Bird card after raw U-Boot verification'
validate_requested_card
[ "$WHOLE" = "$LOCKED_WHOLE" ] ||
	fail 'card identity changed after remounting the U-Boot target'
if [ "$HOST_TEST_MODE" -eq 0 ]; then
	diskutil verifyVolume "$BIRD" >/dev/null ||
		fail 'BIRD FAT verification failed after U-Boot installation'
fi
python3 "$INVENTORY_TOOL" "$BIRD" >"$VERIFY_WORK/bird-after.tsv" ||
	fail 'could not inventory BIRD after U-Boot installation'
cmp "$VERIFY_WORK/bird-before.tsv" "$VERIFY_WORK/bird-after.tsv" >/dev/null ||
	fail 'BIRD payload changed across the bounded raw U-Boot installation'
if [ "$HOST_TEST_MODE" -eq 1 ]; then
	python3 "$RELEASE_VERIFIER" --host-test "$BIRD" \
		>"$VERIFY_WORK/selected-release-after.txt" ||
		fail 'selected release failed verification after U-Boot installation'
else
	python3 "$RELEASE_VERIFIER" "$BIRD" \
		>"$VERIFY_WORK/selected-release-after.txt" ||
		fail 'selected release failed verification after U-Boot installation'
fi
cmp "$VERIFY_WORK/selected-release.txt" \
	"$VERIFY_WORK/selected-release-after.txt" >/dev/null ||
	fail 'selected release changed across U-Boot installation'
is_regular_file "$NAMESPACE" &&
	[ "$(stat -f '%z' "$NAMESPACE")" = "$NAMESPACE_BYTES" ] &&
	[ "$(sha256 "$NAMESPACE")" = "$NAMESPACE_SHA" ] ||
	fail 'BIRD-DATA canonical namespace marker changed across U-Boot installation'

COMMITTED=1
WRITE_STARTED=0
sync
if [ "$ACTION" = --install-green ]; then
	printf 'Green U-Boot installed and exact full-prefix verification passed.\n'
elif [ "$ACTION" = --install-early-green ]; then
	printf 'Early green/red-off U-Boot installed and exact full-prefix verification passed.\n'
elif [ "$ACTION" = --install-env-nowhere ]; then
	printf 'Nowhere-environment U-Boot installed and exact full-prefix verification passed.\n'
elif [ "$ACTION" = --install-direct-extlinux ]; then
	printf 'Direct-extlinux U-Boot installed and exact full-prefix verification passed.\n'
elif [ "$ACTION" = --install-no-heap-clear ]; then
	printf 'No-heap-clear U-Boot installed and exact full-prefix verification passed.\n'
elif [ "$ACTION" = --install-fast-init ]; then
	printf 'Fast-init U-Boot installed and exact full-prefix verification passed.\n'
elif [ "$ACTION" = --install-inplace-handoff ]; then
	printf 'In-place-handoff U-Boot installed and exact full-prefix verification passed.\n'
else
	printf 'Shipping baseline U-Boot restored and exact full-prefix verification passed.\n'
fi
printf 'BIRD releases, selectors, p1, p5, p6, and BIRD-DATA were not write targets.\n'
printf 'Safe eject: diskutil eject /dev/%s\n' "$WHOLE"
