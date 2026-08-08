#!/bin/sh
# Fast, manifest-preserving deployment of mutable birdOS-owned development
# bytes. Production releases remain immutable; build-and-deploy.sh remains the
# only promotion path.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
BIRD=${BIRD:-/Volumes/BIRD}
DATA=${DATA:-/Volumes/BIRD-DATA}
HOST_TEST_MODE=${BIRD_DEV_HOST_TEST_MODE:-0}
MODE=
PROFILE=0
DRY_RUN=0

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage: ./dev-build-and-deploy.sh MODE [--profile] [--dry-run]

Exactly one MODE is required:
  --changed     Build only component groups changed since dev activation
  --all-local   Rebuild every supported birdOS-owned local component
  --status      Show production/dev selection and source differences
  --rollback    Restore the exact saved production selector
  --recover-production
                Restore verified production even when dev state is damaged
  --rebase      Recreate dev-current from the selected production release
  --clean       Roll back, then remove only dev-current and its metadata

Modifiers:
  --profile     Build or preview profiled variants (changed/all-local/status/rebase)
  --dry-run     Validate and print the intended operation without writing
  --help        Show this help
EOF
}

set_mode() {
	[ -z "$MODE" ] || fail 'choose exactly one primary mode'
	MODE=$1
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--changed) set_mode changed ;;
		--all-local) set_mode all-local ;;
		--status) set_mode status ;;
		--rollback) set_mode rollback ;;
		--recover-production) set_mode recover-production ;;
		--rebase) set_mode rebase ;;
		--clean) set_mode clean ;;
		--profile) PROFILE=1 ;;
		--dry-run) DRY_RUN=1 ;;
		--help) usage; exit 0 ;;
		*) fail "unknown argument: $1" ;;
	esac
	shift
done

[ -n "$MODE" ] || fail 'choose exactly one primary mode'
case "$MODE:$PROFILE" in
	rollback:1|recover-production:1|clean:1) fail "--profile is not valid with --$MODE" ;;
esac

case "$HOST_TEST_MODE" in
	0)
		case "$MODE" in
			changed|all-local|rebase)
				[ "${CLANG+x}" != x ] ||
					fail 'CLANG override is not permitted for the canonical development toolchain'
				[ "${LLD+x}" != x ] ||
					fail 'LLD override is not permitted for the canonical development toolchain'
				[ "${READELF+x}" != x ] ||
					fail 'READELF override is not permitted for the canonical development toolchain'
				;;
		esac
		[ -z "${BIRD_DEVICE_INFO:-}" ] ||
			fail 'device metadata override requires host-test mode'
		[ -z "${BIRD_DEV_TEST_FAILPOINT:-}" ] ||
			fail 'failure injection requires host-test mode'
		[ -z "${BIRD_DEV_TEST_BUILD_FIXTURE:-}" ] ||
			fail 'build fixture override requires host-test mode'
		;;
	1)
		[ -n "${BIRD_DEVICE_INFO:-}" ] ||
			fail 'host-test device metadata is required'
		case "$BIRD:$DATA:$BIRD_DEVICE_INFO" in
			/var/folders/*:/var/folders/*:/var/folders/*|\
			/private/tmp/*:/private/tmp/*:/private/tmp/*|\
			/tmp/*:/tmp/*:/tmp/*) ;;
			*) fail 'host-test card paths must be temporary fixtures' ;;
		esac
		;;
	*) fail 'invalid Bird dev host-test mode' ;;
esac

# shellcheck source=firmware/mac-stock-root-card-identity.sh
. "$ROOT/firmware/mac-stock-root-card-identity.sh"
validate_stock_root_card_identity
export BIRD_DEV_WHOLE=$WHOLE

run_tool() {
	python3 "$ROOT/kernel/rocknix/dev-release-tool.py" \
		--root "$ROOT" --bird "$BIRD" --data "$DATA" --mode "$MODE" \
		--profile "$PROFILE" --dry-run "$DRY_RUN"
}

# Status and every dry run are strictly read-only. All real mutating modes use
# the same whole-card lifetime lock as production deployment and migration.
if [ "$MODE" = status ] || [ "$DRY_RUN" -eq 1 ]; then
	run_tool
	exit $?
fi

BIRD_CARD_LOCK_OWNED=0
# shellcheck source=firmware/mac-bird-card-lock.sh
. "$ROOT/firmware/mac-bird-card-lock.sh"
cleanup() {
	bird_card_lock_release
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
BIRD_DEV_LOCKED_WHOLE=$WHOLE
bird_card_lock_acquire
validate_stock_root_card_identity
[ "$WHOLE" = "$BIRD_DEV_LOCKED_WHOLE" ] || \
	fail 'card identity changed after acquiring its transaction lock'
export BIRD_DEV_WHOLE=$WHOLE
run_tool
