#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-mpv-controls.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

${CC:-cc} -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-function \
	-I "$ROOT/launcher" \
	"$ROOT/kernel/rocknix/tests/mpv-controls-host.c" \
	-o "$TMP/mpv-controls-host"
"$TMP/mpv-controls-host"
