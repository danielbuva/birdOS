#!/bin/sh

set -eu

CLANG=${CLANG:-/opt/homebrew/opt/llvm/bin/clang}
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

"$CLANG" \
    --target=aarch64-linux-gnu \
    -mcpu=cortex-a53 \
    -O2 \
    -ffreestanding \
    -fno-builtin \
    -fno-stack-protector \
    -fno-unwind-tables \
    -fno-asynchronous-unwind-tables \
    -fno-ident \
    -fvisibility=hidden \
    -nostdlib \
    -Wall -Wextra -Werror \
    -c "$ROOT/launcher/dani-launcher.c" \
    -o "$ROOT/launcher/dani-launcher.o"

file "$ROOT/launcher/dani-launcher.o"
OBJECT_HASH=$(shasum -a 256 "$ROOT/launcher/dani-launcher.o" | cut -d ' ' -f 1)
INIT_HASH=$(shasum -a 256 "$ROOT/launcher/S03danilauncher" | cut -d ' ' -f 1)
ORDER_HASH=$(shasum -a 256 "$ROOT/launcher/patch-critical-ui-sysinit.sh" | cut -d ' ' -f 1)
{
	printf '%s\n%s\n%s\n' "$OBJECT_HASH" "$INIT_HASH" "$ORDER_HASH"
    for CORE in gw_libretro.so bluemsx_libretro.so fake08_libretro.so; do
        shasum -a 256 "$ROOT/launcher/optional-cores/$CORE" | cut -d ' ' -f 1
    done
} | shasum -a 256 | cut -d ' ' -f 1 >"$ROOT/launcher/catalog.revision"
printf 'catalog revision: '
cat "$ROOT/launcher/catalog.revision"
