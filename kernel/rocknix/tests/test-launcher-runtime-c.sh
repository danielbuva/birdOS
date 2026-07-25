#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-launcher-runtime.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

CC=${CC:-cc}
"$CC" -std=c11 -O1 -Wall -Wextra -Werror \
	-Wno-unused-function -Wno-unused-variable \
	"$ROOT/kernel/rocknix/tests/launcher-runtime-host.c" \
	-o "$TMP/launcher-runtime-host"
"$TMP/launcher-runtime-host"
