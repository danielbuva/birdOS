#!/bin/sh
# Panfrost and the display path are built into the mainline kernel.

case "${1-}" in
	load | unload) : ;;
	*)
		printf 'Usage: %s {load|unload}\n' "$0" >&2
		exit 1
		;;
esac
