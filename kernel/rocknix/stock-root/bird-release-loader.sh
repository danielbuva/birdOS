#!/bin/sh
# Immutable initramfs-side selector for the versioned Bird boot hook.  The
# active extlinux entry selects this loader and a matching release directory;
# the preserved legacy initramfs continues to source /flash/post-flash.sh.

BIRD_HOST_TEST_MODE=${BIRD_HOST_TEST_MODE:-0}
case "$BIRD_HOST_TEST_MODE" in
	0)
		BIRD_LOADER_FLASH=/flash
		BIRD_LOADER_CMDLINE=/proc/cmdline
		BIRD_LOADER_BUSYBOX=/usr/bin/busybox
		BIRD_LOADER_RELEASE=v6.23
		;;
	1)
		BIRD_LOADER_FLASH=${BIRD_LOADER_FLASH:?}
		BIRD_LOADER_CMDLINE=${BIRD_LOADER_CMDLINE:?}
		BIRD_LOADER_BUSYBOX=${BIRD_LOADER_BUSYBOX:-}
		BIRD_LOADER_RELEASE=${BIRD_LOADER_RELEASE:-v6.23}
		case "$BIRD_LOADER_FLASH:$BIRD_LOADER_CMDLINE" in
			/var/folders/*:/var/folders/*|/private/tmp/*:/private/tmp/*|/tmp/*:/tmp/*) ;;
			*) printf '%s\n' 'unsafe Bird release-loader test paths' >&2; return 1 ;;
		esac
		;;
	*) return 1 ;;
esac

bird_loader_sha256() {
	if [ -n "$BIRD_LOADER_BUSYBOX" ]; then
		"$BIRD_LOADER_BUSYBOX" sha256sum "$1" |
			"$BIRD_LOADER_BUSYBOX" awk '{print $1}'
	else
		sha256sum "$1" | awk '{print $1}'
	fi
}

bird_loader_bytes() {
	if [ -n "$BIRD_LOADER_BUSYBOX" ]; then
		# This exact ROCKNIX BusyBox build exposes the traditional -t output
		# consumed by its own /init; it does not accept GNU stat's -c format.
		"$BIRD_LOADER_BUSYBOX" stat -Lt "$1" |
			"$BIRD_LOADER_BUSYBOX" awk '{print $2}'
	else
		stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1"
	fi
}

bird_loader_record_failure() {
	FAILURE_REASON=$1
	DIAGNOSTIC=$BIRD_LOADER_FLASH/bird-loader-failure.txt
	mount -o remount,rw "$BIRD_LOADER_FLASH" || return 1
	# Persist the exact fail-closed branch without changing any selector. A
	# failed release remains failed until the card returns to the host.
	{
		printf 'release=%s\n' "$BIRD_LOADER_SELECTED"
		printf 'reason=%s\n' "$FAILURE_REASON"
		printf 'selector_count=%s\n' "$BIRD_LOADER_SELECTOR_COUNT"
		printf 'cmdline='
		cat "$BIRD_LOADER_CMDLINE"
		printf '\n'
	} >"$DIAGNOSTIC" 2>/dev/null || return 1
	sync || {
		mount -o remount,ro "$BIRD_LOADER_FLASH" || :
		return 1
	}
	mount -o remount,ro "$BIRD_LOADER_FLASH" || return 1
}

bird_loader_fail() {
	{ printf 'bird release-loader: %s\n' "$1" >/dev/kmsg; } 2>/dev/null || :
	if ! bird_loader_record_failure "$1"; then
		{ printf 'bird release-loader: could not persist failure record\n' \
			>/dev/kmsg; } 2>/dev/null || :
	fi
	error bird-release-loader "$1" || :
	return 1
}

BIRD_LOADER_SELECTED=
BIRD_LOADER_SELECTOR_COUNT=0
for BIRD_LOADER_ARG in $(cat "$BIRD_LOADER_CMDLINE"); do
	case "$BIRD_LOADER_ARG" in
		bird_release=*)
			BIRD_LOADER_SELECTOR_COUNT=$((BIRD_LOADER_SELECTOR_COUNT + 1))
			BIRD_LOADER_SELECTED=${BIRD_LOADER_ARG#bird_release=}
			;;
	esac
done
[ "$BIRD_LOADER_SELECTOR_COUNT" -eq 1 ] &&
[ "$BIRD_LOADER_SELECTED" = "$BIRD_LOADER_RELEASE" ] || {
	bird_loader_fail "unexpected release selector: $BIRD_LOADER_SELECTED"
	return 1
}

BIRD_LOADER_ROOT=$BIRD_LOADER_FLASH/bird-releases/$BIRD_LOADER_SELECTED
BIRD_LOADER_MANIFEST=$BIRD_LOADER_ROOT/deploy-manifest.tsv
BIRD_LOADER_COMPLETE=$BIRD_LOADER_ROOT/.complete
BIRD_LOADER_HOOK=$BIRD_LOADER_ROOT/post-flash.sh
[ -f "$BIRD_LOADER_MANIFEST" ] && [ -s "$BIRD_LOADER_COMPLETE" ] &&
[ -f "$BIRD_LOADER_HOOK" ] || {
	bird_loader_fail 'selected release is incomplete'
	return 1
}

BIRD_LOADER_MANIFEST_SHA=$(cat "$BIRD_LOADER_COMPLETE" 2>/dev/null || printf '')
case "$BIRD_LOADER_MANIFEST_SHA" in *[!0-9a-f]*|'')
	bird_loader_fail 'invalid release completion marker'
	return 1
	;;
esac
[ "${#BIRD_LOADER_MANIFEST_SHA}" -eq 64 ] &&
[ "$(bird_loader_sha256 "$BIRD_LOADER_MANIFEST")" = "$BIRD_LOADER_MANIFEST_SHA" ] || {
	bird_loader_fail 'release manifest does not match completion marker'
	return 1
}

BIRD_LOADER_HOOK_RECORD=$(
	awk -F '\t' -v release="$BIRD_LOADER_SELECTED" '
		$1 == "schema" { if (NF != 2 || $2 != "bird-deploy-v1" || schema++) exit 1; next }
		$1 == "release" { if (NF != 2 || $2 != release || selected++) exit 1; next }
		$1 == "file" && $2 == "post-flash.sh" {
			if (NF != 5 || $4 !~ /^[0-9]+$/ || length($5) != 64 ||
			    $5 ~ /[^0-9a-f]/ || hook++) exit 1
			print $4 " " $5
		}
		END { if (schema != 1 || selected != 1 || hook != 1) exit 1 }
	' "$BIRD_LOADER_MANIFEST"
) || {
	bird_loader_fail 'release manifest has no unique boot-hook record'
	return 1
}
BIRD_LOADER_HOOK_BYTES=${BIRD_LOADER_HOOK_RECORD%% *}
BIRD_LOADER_HOOK_SHA=${BIRD_LOADER_HOOK_RECORD#* }
BIRD_LOADER_HOOK_ACTUAL_BYTES=$(bird_loader_bytes "$BIRD_LOADER_HOOK" 2>/dev/null ||
	printf invalid)
[ "$BIRD_LOADER_HOOK_ACTUAL_BYTES" = "$BIRD_LOADER_HOOK_BYTES" ] || {
	bird_loader_fail "versioned boot hook size mismatch: expected=$BIRD_LOADER_HOOK_BYTES actual=$BIRD_LOADER_HOOK_ACTUAL_BYTES"
	return 1
}
BIRD_LOADER_HOOK_ACTUAL_SHA=$(bird_loader_sha256 "$BIRD_LOADER_HOOK" 2>/dev/null ||
	printf invalid)
[ "$BIRD_LOADER_HOOK_ACTUAL_SHA" = "$BIRD_LOADER_HOOK_SHA" ] || {
	bird_loader_fail "versioned boot hook digest mismatch: expected=$BIRD_LOADER_HOOK_SHA actual=$BIRD_LOADER_HOOK_ACTUAL_SHA"
	return 1
}

. "$BIRD_LOADER_HOOK"
