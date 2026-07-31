#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-fixed-controls.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

NONEXEC=$TMP/non-executable
printf '%s\n' '#!/bin/sh' 'exit 0' >"$NONEXEC"
chmod 0644 "$NONEXEC"

CC=${CC:-cc}
"$CC" -std=c11 -O1 -Wall -Wextra -Werror \
	-Wno-unused-function -Wno-macro-redefined \
	-I "$ROOT/launcher" \
	"$ROOT/kernel/rocknix/tests/fixed-controls-host.c" \
	-o "$TMP/fixed-controls-host"
"$TMP/fixed-controls-host" "$NONEXEC"
