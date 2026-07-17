#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

for SOURCE in "$SCRIPT_DIR"/font-stubs/*.c; do
	/usr/bin/clang \
		--target=aarch64-linux-gnu \
		-fPIC \
		-ffreestanding \
		-fno-stack-protector \
		-fvisibility=default \
		-c "$SOURCE" \
		-o "${SOURCE%.c}.o"
done

file "$SCRIPT_DIR"/font-stubs/*.o

