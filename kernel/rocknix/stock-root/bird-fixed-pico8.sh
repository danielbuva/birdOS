#!/bin/sh
# Publish ROCKNIX's optional Pico-8 Splore sentinel only when it is missing.
# The generic hook touched an already-existing file on every boot.

set -eu

PICO_DIR=${BIRD_PICO_DIR:-/storage/roms/pico-8}
[ -d "$PICO_DIR" ] || exit 0
[ ! -e "$PICO_DIR/.disable_splore" ] || exit 0
[ -e "$PICO_DIR/Splore.png" ] || touch "$PICO_DIR/Splore.png"
