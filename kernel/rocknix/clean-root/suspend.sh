#!/bin/sh
# Suspend is intentionally isolated from the launcher. The source-kernel
# suspend matrix will harden device quiescing later; this conservative first
# clean-root candidate requests the kernel's standard mem state directly.

sync
[ -w /sys/power/state ] || exit 1
printf '%s\n' mem >/sys/power/state
