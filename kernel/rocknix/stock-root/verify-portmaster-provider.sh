#!/bin/sh
# Verify one installed PortMaster provider against a repository-pinned managed
# file manifest. Output is the exact Bird checkpoint value on success. The
# explicit cache allowance is valid only for callers that redirect Python's
# cache lookup to fresh tmpfs before any PortMaster provider execution.

set -eu

ALLOW_PYTHON_CACHE=0
if [ "${1:-}" = --allow-isolated-python-cache ]; then
	ALLOW_PYTHON_CACHE=1
	shift
fi
[ "$#" -eq 2 ] || {
	printf 'usage: %s [--allow-isolated-python-cache] MANIFEST PROVIDER\n' "$0" >&2
	exit 2
}
MANIFEST=$1
PROVIDER=$2

fail() {
	printf 'PortMaster provider verification failed: %s\n' "$*" >&2
	exit 1
}

is_regular_file() {
	[ -f "$1" ] && [ ! -L "$1" ]
}

file_bytes() {
	stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1"
}

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		HASH_OUTPUT=$(sha256sum "$1") || fail "could not hash: $1"
	else
		HASH_OUTPUT=$(shasum -a 256 "$1") || fail "could not hash: $1"
	fi
	HASH=$(printf '%s\n' "$HASH_OUTPUT" | awk '
		NR == 1 && length($1) == 64 && $1 !~ /[^0-9a-f]/ {print $1; valid++}
		END {if (NR != 1 || valid != 1) exit 1}
	') || fail "hash command returned malformed output: $1"
	printf '%s\n' "$HASH"
}

is_excluded_path() {
	if [ "$ALLOW_PYTHON_CACHE" -eq 1 ]; then
		case "$1" in */__pycache__/*|*.pyc) return 0 ;; esac
	fi
	case "$1" in
		.Backup/*|autoinstall/*|config/*|controller_layout/*|libs/*|runtimes/*|\
		._*|*/._*) return 0 ;;
		control.txt|gamecontrollerdb.txt|oga_controls|oga_controls_settings.txt|\
		post-install|resources/do_init|tasksetter|\
		.bird-release-complete|.weston-refresh|harbourmaster.txt|log.txt|\
		mapper.txt|pugwash.txt) return 0 ;;
	esac
	return 1
}

is_regular_file "$MANIFEST" || fail 'manifest is missing or unsafe'
[ -d "$PROVIDER" ] && [ ! -L "$PROVIDER" ] || \
	fail 'provider root is missing or unsafe'

MANIFEST_SOURCE=$MANIFEST

VERIFY_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-portmaster-verify.XXXXXX") || \
	fail 'could not create verification workspace'
cleanup() {
	case "$VERIFY_TEMP" in
		/var/folders/*|/private/tmp/*|/tmp/*) rm -rf "$VERIFY_TEMP" ;;
	esac
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

RECORDS=$VERIFY_TEMP/records.tsv
EXPECTED=$VERIFY_TEMP/expected-paths
EXPECTED_UNSORTED=$VERIFY_TEMP/expected-paths.unsorted
ACTUAL=$VERIFY_TEMP/actual-paths
ACTUAL_UNSORTED=$VERIFY_TEMP/actual-paths.unsorted
RAW_FILES=$VERIFY_TEMP/provider-files.raw
DUPLICATES=$VERIFY_TEMP/duplicate-paths
SPECIAL=$VERIFY_TEMP/special-paths
RAW_SPECIAL=$VERIFY_TEMP/provider-special.raw
MANIFEST=$VERIFY_TEMP/manifest.tsv

cp "$MANIFEST_SOURCE" "$MANIFEST" || fail 'could not snapshot the manifest'
is_regular_file "$MANIFEST" || fail 'manifest snapshot is unsafe'
MANIFEST_SHA=$(sha256 "$MANIFEST")
[ "$(sha256 "$MANIFEST_SOURCE")" = "$MANIFEST_SHA" ] || \
	fail 'manifest changed while it was being snapshotted'

awk -F '\t' '
	function safe_path(path) {
		return path ~ /^[A-Za-z0-9._ \/-]+$/ && path !~ /^\// &&
		       path !~ /\/$/ && path !~ /\/\// &&
		       path !~ /(^|\/)\.\.?($|\/)/ &&
		       path !~ /(^|\/) / && path !~ / ($|\/)/
	}
	$1 == "schema" {
		if (NF != 2 || $2 != "bird-portmaster-provider-v1" || schema++) exit 1
		next
	}
	$1 == "revision" {
		if (NF != 2 || $2 !~ /^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]{4}$/ || revision++) exit 1
		revision_value=$2
		print "revision\t" $2
		next
	}
	$1 == "source-url" {
		if (NF != 2 || $2 !~ /^https:\/\/github\.com\/PortsMaster\/PortMaster-GUI\/releases\/download\// || source++) exit 1
		source_url=$2
		next
	}
	$1 == "archive" {
		if (NF != 4 || $2 !~ /^[0-9]+$/ || length($3) != 64 ||
		    $3 ~ /[^0-9a-f]/ || length($4) != 32 || $4 ~ /[^0-9a-f]/ || archive++) exit 1
		next
	}
	$1 == "file" {
		if (NF != 4 || !safe_path($2) || $3 !~ /^[0-9]+$/ ||
		    length($4) != 64 || $4 ~ /[^0-9a-f]/) exit 1
		print "file\t" $2 "\t" $3 "\t" $4
		files++
		next
	}
	$1 == "optional-file" {
		if (NF != 4 || $2 != "pylibs.zip" || !safe_path($2) ||
		    $3 !~ /^[0-9]+$/ || length($4) != 64 ||
		    $4 ~ /[^0-9a-f]/ || optional++) exit 1
		print "optional-file\t" $2 "\t" $3 "\t" $4
		next
	}
	{exit 1}
	END {
		if (schema != 1 || revision != 1 || source != 1 || archive != 1 ||
		    files < 1 || optional != 1 ||
		    source_url != "https://github.com/PortsMaster/PortMaster-GUI/releases/download/" revision_value "/PortMaster.zip") exit 1
	}
' "$MANIFEST" >"$RECORDS" || fail 'manifest is malformed'

REVISION=$(awk -F '\t' '$1 == "revision" {print $2}' "$RECORDS")
: >"$EXPECTED_UNSORTED"
awk -F '\t' '$1 == "file" {print $2}' "$RECORDS" >>"$EXPECTED_UNSORTED"
while IFS="$(printf '\t')" read -r KIND RELATIVE EXPECTED_BYTES EXPECTED_SHA; do
	[ "$KIND" = optional-file ] || continue
	OPTIONAL_TARGET=$PROVIDER/$RELATIVE
	if [ -e "$OPTIONAL_TARGET" ] || [ -L "$OPTIONAL_TARGET" ]; then
		printf '%s\n' "$RELATIVE" >>"$EXPECTED_UNSORTED"
	fi
done <"$RECORDS"
LC_ALL=C sort "$EXPECTED_UNSORTED" >"$EXPECTED"
uniq -d "$EXPECTED" >"$DUPLICATES" || \
	fail 'could not inspect duplicate manifest paths'
[ ! -s "$DUPLICATES" ] || fail 'manifest has duplicate managed paths'

find "$PROVIDER" -type f -print >"$RAW_FILES" || \
	fail 'could not inventory provider files'
: >"$ACTUAL_UNSORTED"
while IFS= read -r PROVIDER_FILE; do
	RELATIVE=${PROVIDER_FILE#"$PROVIDER"/}
	is_excluded_path "$RELATIVE" && continue
	printf '%s\n' "$RELATIVE" >>"$ACTUAL_UNSORTED" || \
		fail 'could not record provider file inventory'
done <"$RAW_FILES"
LC_ALL=C sort "$ACTUAL_UNSORTED" >"$ACTUAL" || \
	fail 'could not sort provider file inventory'
cmp "$EXPECTED" "$ACTUAL" >/dev/null || \
	fail 'managed provider file set differs from the pinned revision'

find "$PROVIDER" -mindepth 1 ! -type f ! -type d -print \
	>"$RAW_SPECIAL" || fail 'could not inventory provider node types'
: >"$SPECIAL"
while IFS= read -r PROVIDER_NODE; do
	RELATIVE=${PROVIDER_NODE#"$PROVIDER"/}
	is_excluded_path "$RELATIVE" && continue
	printf '%s\n' "$RELATIVE" >>"$SPECIAL" || \
		fail 'could not record provider node inventory'
done <"$RAW_SPECIAL"
[ ! -s "$SPECIAL" ] || fail 'managed provider contains a symlink or special node'

TAB=$(printf '\t')
while IFS="$TAB" read -r KIND RELATIVE EXPECTED_BYTES EXPECTED_SHA; do
	case "$KIND" in
		file) ;;
		optional-file)
			TARGET=$PROVIDER/$RELATIVE
			[ -e "$TARGET" ] || [ -L "$TARGET" ] || continue
			;;
		*) continue ;;
	esac
	TARGET=$PROVIDER/$RELATIVE
	is_regular_file "$TARGET" || fail "managed file is missing or unsafe: $RELATIVE"
	[ "$(file_bytes "$TARGET")" = "$EXPECTED_BYTES" ] || \
		fail "managed file size changed: $RELATIVE"
	[ "$(sha256 "$TARGET")" = "$EXPECTED_SHA" ] || \
		fail "managed file digest changed: $RELATIVE"
done <"$RECORDS"

is_regular_file "$MANIFEST_SOURCE" && \
[ "$(sha256 "$MANIFEST_SOURCE")" = "$MANIFEST_SHA" ] || \
	fail 'manifest changed during provider verification'
printf 'bird-portmaster-v3:%s:%s\n' "$REVISION" "$MANIFEST_SHA"
