#!/bin/sh
# Immutable initramfs-side selector for the versioned Bird boot hook.  The
# active extlinux entry selects this loader and a matching release directory;
# the preserved legacy initramfs continues to source /flash/post-flash.sh.

BIRD_HOST_TEST_MODE=${BIRD_HOST_TEST_MODE:-0}
case "$BIRD_HOST_TEST_MODE" in
	0)
		BIRD_LOADER_FLASH=/flash
		BIRD_LOADER_CMDLINE=/proc/cmdline
		BIRD_LOADER_REBOOT=reboot
		BIRD_LOADER_RELEASE=v6.23
		BIRD_LOADER_SELECTOR_SHA=f6434463ef51f752b6871186497a9d96888b89e9b2d158c3ea75bcbef9a58776
		BIRD_LOADER_KERNEL_SHA=a53a3483731d28d2e96e53def0fba347fa53607aa9fbda8bfb82db677126daef
		BIRD_LOADER_DTB_SHA=f3a4273986d6e4f431b110cead8aa19e8da52ff08c64c4b204ef9664d28b5c31
		;;
	1)
		BIRD_LOADER_FLASH=${BIRD_LOADER_FLASH:?}
		BIRD_LOADER_CMDLINE=${BIRD_LOADER_CMDLINE:?}
		BIRD_LOADER_REBOOT=${BIRD_LOADER_REBOOT:?}
		BIRD_LOADER_RELEASE=${BIRD_LOADER_RELEASE:-v6.23}
		BIRD_LOADER_SELECTOR_SHA=${BIRD_LOADER_SELECTOR_SHA:?}
		BIRD_LOADER_KERNEL_SHA=${BIRD_LOADER_KERNEL_SHA:?}
		BIRD_LOADER_DTB_SHA=${BIRD_LOADER_DTB_SHA:?}
		case "$BIRD_LOADER_FLASH:$BIRD_LOADER_CMDLINE" in
			/var/folders/*:/var/folders/*|/private/tmp/*:/private/tmp/*|/tmp/*:/tmp/*) ;;
			*) printf '%s\n' 'unsafe Bird release-loader test paths' >&2; return 1 ;;
		esac
		;;
	*) return 1 ;;
esac

bird_loader_sha256() {
	sha256sum "$1" | awk '{print $1}'
}

bird_loader_activate_fallback() {
	SOURCE=$BIRD_LOADER_FLASH/extlinux/extlinux.fallback.conf
	TARGET=$BIRD_LOADER_FLASH/extlinux/extlinux.conf
	TEMP=$BIRD_LOADER_FLASH/extlinux/.extlinux.conf.loader.$$
	KERNEL=$BIRD_LOADER_FLASH/KERNEL.fallback
	DTB=$BIRD_LOADER_FLASH/dtb.img

	[ -f "$SOURCE" ] &&
	[ "$(bird_loader_sha256 "$SOURCE")" = "$BIRD_LOADER_SELECTOR_SHA" ] &&
	[ -f "$KERNEL" ] &&
	[ "$(bird_loader_sha256 "$KERNEL")" = "$BIRD_LOADER_KERNEL_SHA" ] &&
	[ -f "$DTB" ] &&
	[ "$(bird_loader_sha256 "$DTB")" = "$BIRD_LOADER_DTB_SHA" ] || return 1
	mount -o remount,rw "$BIRD_LOADER_FLASH" || return 1
	cp -f "$SOURCE" "$TEMP" || {
		rm -f "$TEMP"
		mount -o remount,ro "$BIRD_LOADER_FLASH" || :
		return 1
	}
	[ "$(bird_loader_sha256 "$TEMP")" = "$BIRD_LOADER_SELECTOR_SHA" ] || {
		rm -f "$TEMP"
		mount -o remount,ro "$BIRD_LOADER_FLASH" || :
		return 1
	}
	sync || {
		rm -f "$TEMP"
		mount -o remount,ro "$BIRD_LOADER_FLASH" || :
		return 1
	}
	mv -f "$TEMP" "$TARGET" || {
		rm -f "$TEMP"
		mount -o remount,ro "$BIRD_LOADER_FLASH" || :
		return 1
	}
	[ "$(bird_loader_sha256 "$TARGET")" = "$BIRD_LOADER_SELECTOR_SHA" ] || {
		mount -o remount,ro "$BIRD_LOADER_FLASH" || :
		return 1
	}
	sync || {
		mount -o remount,ro "$BIRD_LOADER_FLASH" || :
		return 1
	}
	mount -o remount,ro "$BIRD_LOADER_FLASH" || return 1
}

bird_loader_fail() {
	{ printf 'bird release-loader: %s\n' "$1" >/dev/kmsg; } 2>/dev/null || :
	if bird_loader_activate_fallback; then
		"$BIRD_LOADER_REBOOT" -f
		return 1
	fi
	error bird-release-loader "$1; fallback activation also failed" || :
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
[ "$(stat -c '%s' "$BIRD_LOADER_HOOK" 2>/dev/null || printf invalid)" = \
	"$BIRD_LOADER_HOOK_BYTES" ] &&
[ "$(bird_loader_sha256 "$BIRD_LOADER_HOOK")" = "$BIRD_LOADER_HOOK_SHA" ] || {
	bird_loader_fail 'versioned boot hook failed manifest verification'
	return 1
}

. "$BIRD_LOADER_HOOK"
