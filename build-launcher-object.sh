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
