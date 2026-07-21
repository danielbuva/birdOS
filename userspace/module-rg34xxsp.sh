#!/bin/sh
# DANI_FIXED_RG34XXSP_MODULE_V1

# Networking owns rtl8821cs explicitly and on demand. SquashFS is built into
# this kernel, so this suspend/resume helper owns only the Mali module.
case "${1-}" in
	load)
		modprobe -q mali_kbase
		;;
	unload)
		modprobe -qr mali_kbase
		;;
	*)
		printf 'Usage: %s {load|unload}\n' "$0" >&2
		exit 1
		;;
esac
